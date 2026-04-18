import AppKit

/// Builds the small actions-only `NSMenu` surfaced by right-clicking the
/// status item. Data rows live in the popover dashboard; this menu only
/// carries actions the user might want to invoke without opening the
/// popover (Interact submenu, Refresh, Open Cursor, Quit).
/// Which entry in the Screenshot Mode submenu currently carries the
/// checkmark. `off` means the popover is showing real data from the
/// scheduler; the other two correspond to the loaded fixture.
enum ScreenshotMenuState {
    case off
    case positive
    case negative
}

@MainActor
final class ActionsMenuBuilder {
    weak var target: AnyObject?
    let refreshSelector: Selector
    let openCursorSelector: Selector
    let openCloudAgentsSelector: Selector
    let openStatusSelector: Selector
    let quitSelector: Selector
    let interactSelector: Selector
    let screenshotSelector: Selector

    init(target: AnyObject,
         refreshSelector: Selector,
         openCursorSelector: Selector,
         openCloudAgentsSelector: Selector,
         openStatusSelector: Selector,
         quitSelector: Selector,
         interactSelector: Selector,
         screenshotSelector: Selector) {
        self.target = target
        self.refreshSelector = refreshSelector
        self.openCursorSelector = openCursorSelector
        self.openCloudAgentsSelector = openCloudAgentsSelector
        self.openStatusSelector = openStatusSelector
        self.quitSelector = quitSelector
        self.interactSelector = interactSelector
        self.screenshotSelector = screenshotSelector
    }

    /// Interact submenu entries. Tag on each item identifies the animation.
    static let interactions: [(title: String, tag: Int)] = [
        ("Scratch head", 0),
        ("Scratch up", 4),
        ("Scratch down", 5),
        ("Sleep", 1),
        ("Alert", 2),
        ("Run around", 3)
    ]

    static func animation(forTag tag: Int) -> CatAnimation? {
        switch tag {
        case 0: return .scratchHead
        case 1: return .sleeping
        case 2: return .alert
        case 3: return .runAround
        case 4: return .scratchUp
        case 5: return .scratchDown
        default: return nil
        }
    }

    func build(isLoggedIn: Bool,
               screenshotState: ScreenshotMenuState = .off) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if !isLoggedIn {
            let open = NSMenuItem(title: "Open Cursor to log in",
                                  action: openCursorSelector,
                                  keyEquivalent: "")
            open.target = target
            menu.addItem(open)
            menu.addItem(.separator())
        }

        menu.addItem(makeInteractItem())

        let refresh = NSMenuItem(title: "Refresh now",
                                 action: refreshSelector,
                                 keyEquivalent: "r")
        refresh.target = target
        menu.addItem(refresh)

        menu.addItem(.separator())

        let cloud = NSMenuItem(title: "Cloud Agents",
                               action: openCloudAgentsSelector,
                               keyEquivalent: "")
        cloud.target = target
        cloud.image = NSImage(systemSymbolName: "cloud",
                              accessibilityDescription: nil)
        menu.addItem(cloud)

        let status = NSMenuItem(title: "Cursor Status",
                                action: openStatusSelector,
                                keyEquivalent: "")
        status.target = target
        status.image = NSImage(systemSymbolName: "waveform.path.ecg",
                               accessibilityDescription: nil)
        menu.addItem(status)

        menu.addItem(.separator())

        menu.addItem(makeScreenshotItem(state: screenshotState))

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Cursorcat",
                              action: quitSelector,
                              keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)

        return menu
    }

    private func makeInteractItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Interact", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Interact")
        for entry in Self.interactions {
            let item = NSMenuItem(title: entry.title,
                                  action: interactSelector,
                                  keyEquivalent: "")
            item.target = target
            item.tag = entry.tag
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    private func makeScreenshotItem(state: ScreenshotMenuState) -> NSMenuItem {
        let parent = NSMenuItem(title: "Screenshot Mode",
                                action: nil,
                                keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "camera",
                               accessibilityDescription: nil)

        let sub = NSMenu(title: "Screenshot Mode")

        let entries: [(title: String, tag: Int, matches: ScreenshotMenuState)] = [
            ("Turn off", 0, .off),
            ("Positive data", 1, .positive),
            ("Negative data", 2, .negative)
        ]

        for entry in entries {
            let item = NSMenuItem(title: entry.title,
                                  action: screenshotSelector,
                                  keyEquivalent: "")
            item.target = target
            item.tag = entry.tag
            item.state = (state == entry.matches) ? .on : .off
            sub.addItem(item)
        }

        parent.submenu = sub
        return parent
    }
}
