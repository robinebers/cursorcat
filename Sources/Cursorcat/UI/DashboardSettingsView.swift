import AppKit
import Carbon
import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Global trigger shortcut")
                    .font(.callout)
                    .fontWeight(.semibold)

                ShortcutRecorder(settings: settings)

                Text("Toggles the popover from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle(isOn: rawCostBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Use raw API cost")
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text("Off uses actual charged cost and ignores included or free usage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(shortcutLabel)
                    .font(.system(.body, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.quaternary)
                    )

                Button(isRecording ? "Cancel" : recordButtonTitle) {
                    isRecording ? stopRecording() : startRecording()
                }
                .controlSize(.small)
            }

            if settings.globalShortcut != nil {
                Button("Clear Shortcut") {
                    settings.globalShortcut = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var shortcutLabel: String {
        if isRecording {
            return "Press shortcut..."
        }
        return settings.globalShortcut?.displayString ?? "Not set"
    }

    private var recordButtonTitle: String {
        settings.globalShortcut == nil ? "Record" : "Change"
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
