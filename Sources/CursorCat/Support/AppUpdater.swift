import AppKit
import Combine
@preconcurrency import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    enum InstallState: Equatable {
        case idle
        case available(version: String)
        case downloading(version: String)
        case ready(version: String)
        case installing(version: String)

        var version: String? {
            switch self {
            case .idle: nil
            case .available(let version),
                 .downloading(let version),
                 .ready(let version),
                 .installing(let version): version
            }
        }

        var isPending: Bool {
            self != .idle
        }

        var isBusy: Bool {
            switch self {
            case .downloading, .installing: true
            case .idle, .available, .ready: false
            }
        }

        var isInstallEnabled: Bool {
            switch self {
            case .available, .ready: true
            case .idle, .downloading, .installing: false
            }
        }

        var buttonTitle: String {
            switch self {
            case .idle, .available, .ready: "New version! Restart now."
            case .downloading: "Downloading…"
            case .installing: "Restarting…"
            }
        }
    }

    @Published private(set) var installState: InstallState = .idle

    private var updaterController: SPUStandardUpdaterController?
    private var startupCheckPerformed = false
    private var pendingUpdateItem: SUAppcastItem?
    private var immediateInstallBlock: (() -> Void)?

    override init() {
        super.init()

        if AppMetadata.sparkleFeedURL != nil, AppMetadata.sparklePublicEDKey != nil {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: self,
                userDriverDelegate: self
            )
        }
    }

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    var isConfigured: Bool {
        updaterController != nil
    }

    var shouldShowAlertCat: Bool {
        installState.isPending
    }

    func start() {
        guard let updaterController else { return }
        updaterController.startUpdater()

        guard !startupCheckPerformed else { return }
        startupCheckPerformed = true

        if updaterController.updater.automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func installUpdate() {
        guard let updaterController else { return }

        switch installState {
        case .idle:
            return
        case .available(let version):
            installState = .downloading(version: version)
            if !updaterController.updater.sessionInProgress,
               updaterController.updater.automaticallyChecksForUpdates {
                updaterController.updater.checkForUpdatesInBackground()
            }
        case .downloading:
            return
        case .ready(let version):
            installState = .installing(version: version)
            immediateInstallBlock?()
        case .installing:
            return
        }
    }

    func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "About \(AppMetadata.displayName)"

        let credit = "Made by Robin Ebers"
        let updateWarning = isConfigured ? "" : "\nAutomatic updates are not configured for this build."
        alert.informativeText = "Version \(AppMetadata.versionDescription)\n\(credit)\(updateWarning)"

        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = versionString(for: item)
        pendingUpdateItem = item
        immediateInstallBlock = nil

        switch installState {
        case .idle:
            installState = .available(version: version)
        case .available, .downloading, .ready, .installing:
            break
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        if pendingUpdateItem == nil {
            installState = .idle
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        if pendingUpdateItem == nil {
            installState = .idle
        }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        setPendingUpdate(item) { .downloading(version: $0) }
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        setPendingUpdate(item) { .downloading(version: $0) }
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        setPendingUpdate(item) { .downloading(version: $0) }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        setPendingUpdate(item) { .installing(version: $0) }
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        setPendingUpdate(item) { .available(version: $0) }
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        restorePendingState()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        restorePendingState()
    }

    func updater(_ updater: SPUUpdater,
                 didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        if error != nil {
            restorePendingState()
        } else if pendingUpdateItem == nil {
            installState = .idle
        }
    }
}

extension AppUpdater: SPUStandardUserDriverDelegate {
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        Task { @MainActor in
            guard !state.userInitiated else { return }

            let version = versionString(for: update)
            pendingUpdateItem = update

            switch state.stage {
            case .notDownloaded:
                if !installState.isPending {
                    installState = .available(version: version)
                }
            case .downloaded:
                installState = .ready(version: version)
            case .installing:
                installState = .installing(version: version)
            @unknown default:
                installState = .available(version: version)
            }
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            if case .installing = installState {
                return
            }
            restorePendingState()
        }
    }

    @objc(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)
    func updater(_ updater: SPUUpdater,
                 willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock installationBlock: @escaping () -> Void) -> Bool {
        pendingUpdateItem = item
        immediateInstallBlock = installationBlock
        installState = .ready(version: versionString(for: item))
        return true
    }

    private func versionString(for item: SUAppcastItem) -> String {
        item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
    }

    private func setPendingUpdate(_ item: SUAppcastItem, to state: (String) -> InstallState) {
        pendingUpdateItem = item
        installState = state(versionString(for: item))
    }

    private func restorePendingState() {
        guard let pendingUpdateItem else {
            immediateInstallBlock = nil
            installState = .idle
            return
        }

        let version = versionString(for: pendingUpdateItem)
        installState = immediateInstallBlock != nil ? .ready(version: version) : .available(version: version)
    }
}
