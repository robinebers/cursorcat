import AppKit
import Carbon
import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard shortcut")
                    .font(.callout)
                    .fontWeight(.semibold)

                ShortcutRecorder(settings: settings)

                if let error = settings.globalShortcutRegistrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Open CursorCat from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show full usage cost")
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text("Includes usage covered by your plan and free credits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: rawCostBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var rawCostBinding: Binding<Bool> {
        Binding(
            get: { settings.costMode == .rawAPI },
            set: { settings.costMode = $0 ? .rawAPI : .actual }
        )
    }
}

private struct ShortcutRecorder: View {
    @ObservedObject var settings: UserSettings

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                HStack(spacing: 8) {
                    chipContent
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quinary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isRecording ? 1.5 : 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isRecording, settings.globalShortcut != nil {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    @ViewBuilder
    private var chipContent: some View {
        if isRecording {
            Text("Type shortcut\u{2026}")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let shortcut = settings.globalShortcut {
            Text(shortcut.displayString)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                Text("Record Shortcut")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var borderColor: Color {
        isRecording ? Color.accentColor : Color(nsColor: .separatorColor)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func clear() {
        settings.globalShortcut = nil
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            guard let shortcut = GlobalShortcut(event: event) else {
                NSSound.beep()
                return nil
            }

            settings.globalShortcutRegistrationError = nil
            settings.globalShortcut = shortcut
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
