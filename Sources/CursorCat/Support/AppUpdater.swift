import AppKit
import Sparkle

@MainActor
final class AppUpdater: NSObject {
    private let updaterController: SPUStandardUpdaterController?

    override init() {
        if AppMetadata.sparkleFeedURL != nil, AppMetadata.sparklePublicEDKey != nil {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
        super.init()
    }

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    var isConfigured: Bool {
        updaterController != nil
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "About \(AppMetadata.displayName)"

        if isConfigured {
            alert.informativeText = "Version \(AppMetadata.versionDescription)"
        } else {
            alert.informativeText = "Version \(AppMetadata.versionDescription)\nAutomatic updates are not configured for this build."
        }

        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
