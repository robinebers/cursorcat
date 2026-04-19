import AppKit
import Carbon
import Combine

struct GlobalShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let modifiers = Self.carbonModifiers(from: flags)
        guard modifiers != 0 else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.modifiers = modifiers
    }

    var displayString: String {
        "\(modifierSymbols)\(Self.keyDisplayName(for: keyCode))"
    }

    private var modifierSymbols: String {
        var symbols: [String] = []
        if modifiers & UInt32(controlKey) != 0 { symbols.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { symbols.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { symbols.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { symbols.append("⌘") }
        return symbols.joined()
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func keyDisplayName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        default:
            break
        }

        guard let layoutSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(layoutSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return "Key \(keyCode)"
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else {
            return "Key \(keyCode)"
        }

        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(bytes))
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )

        guard status == noErr, length > 0 else {
            return "Key \(keyCode)"
        }

        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

@MainActor
final class GlobalHotKeyController {
    private static let handler: EventHandlerUPP = { _, event, userData in
        guard let userData else { return noErr }
        let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
        controller.handleHotKey(event)
        return noErr
    }

    private static let signature: OSType = 0x43434154 // CCAT

    private let settings: UserSettings
    private let onTrigger: () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var cancellables: Set<AnyCancellable> = []
    private var lastRegisteredShortcut: GlobalShortcut?
    private var isRollingBackShortcut = false

    init(settings: UserSettings, onTrigger: @escaping () -> Void) {
        self.settings = settings
        self.onTrigger = onTrigger

        installHandler()
        register(settings.globalShortcut)

        settings.$globalShortcut
            .receive(on: RunLoop.main)
            .sink { [weak self] shortcut in
                guard let self else { return }
                if self.isRollingBackShortcut {
                    self.isRollingBackShortcut = false
                    return
                }
                self.register(shortcut)
            }
            .store(in: &cancellables)
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if status != noErr {
            settings.globalShortcutRegistrationError = "Global shortcut handler could not be installed."
        }
    }

    private func register(_ shortcut: GlobalShortcut?) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        guard let shortcut else {
            lastRegisteredShortcut = nil
            settings.globalShortcutRegistrationError = nil
            return
        }

        if attemptRegistration(shortcut) {
            lastRegisteredShortcut = shortcut
            settings.globalShortcutRegistrationError = nil
            return
        }

        if let lastRegisteredShortcut {
            _ = attemptRegistration(lastRegisteredShortcut)
        }
        settings.globalShortcutRegistrationError = "That shortcut is unavailable. Try a different combination."
        isRollingBackShortcut = true
        settings.globalShortcut = lastRegisteredShortcut
    }

    private func attemptRegistration(_ shortcut: GlobalShortcut) -> Bool {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    private func handleHotKey(_ event: EventRef?) {
        guard let event else { return }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == Self.signature else { return }
        onTrigger()
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
