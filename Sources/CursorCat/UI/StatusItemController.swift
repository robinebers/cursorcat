import AppKit
import Combine
import SwiftUI

/// Owns the `NSStatusItem`, the attached SwiftUI popover dashboard, and
/// the short right-click actions menu. Observes `UsageStore` (for the
/// tray title) and drives `CatAnimator` (for state locks like
/// logged-out / error).
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let store: UsageStore
    private let settings: UserSettings
    private let animator: CatAnimator
    private let scheduler: PollScheduler
    private let updater: AppUpdater
    private let popover: NSPopover
    private var eventMonitor: EventMonitor?
    private var cancellables: Set<AnyCancellable> = []
    private lazy var menuBuilder = ActionsMenuBuilder(
        target: self,
        refreshSelector: #selector(refreshNow),
        checkForUpdatesSelector: #selector(checkForUpdates),
        aboutSelector: #selector(showAbout),
        openCursorSelector: #selector(openCursor),
        openCloudAgentsSelector: #selector(openCloudAgents),
        openStatusSelector: #selector(openStatus),
        quitSelector: #selector(quit),
        interactSelector: #selector(performInteraction(_:))
    )

    init(store: UsageStore,
         settings: UserSettings,
         animator: CatAnimator,
         scheduler: PollScheduler,
         updater: AppUpdater) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.store = store
        self.settings = settings
        self.animator = animator
        self.scheduler = scheduler
        self.updater = updater
        self.popover = NSPopover()
        super.init()

        configurePopover()
        configureStatusButton()
        animator.onFrame = { [weak self] image in
            self?.statusItem.button?.image = image
        }
        animator.start()
        observeStore()
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                store: store,
                settings: settings,
                scheduler: scheduler,
                actions: makeDashboardActions()
            )
        )
    }

    private func configureStatusButton() {
        statusItem.button?.title = " …"
        statusItem.button?.imagePosition = .imageLeft
        guard let button = statusItem.button else { return }
        button.action = #selector(handleStatusButton(_:))
        button.target = self
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }

    private func observeStore() {
        store.$snapshot
            .combineLatest(store.$viewState)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, viewState in
                self?.renderStatusItem(snapshot: snapshot, viewState: viewState)
            }
            .store(in: &cancellables)
    }

    private func makeDashboardActions() -> DashboardActions {
        DashboardActions(
            refresh: { [weak self] in
                self?.scheduler.triggerNow(manual: true)
            },
            openCursor: { [weak self] in
                self?.openCursorAndDismiss()
            }
        )
    }

    private func renderStatusItem(snapshot: UsageSnapshot, viewState: UsageViewState) {
        switch viewState {
        case .loggedOut:
            animator.setState(.sleeping)
            statusItem.button?.title = " Not logged in"
        case .loading:
            animator.setState(.idle)
            statusItem.button?.title = " …"
        case .failed:
            animator.setState(.error)
            statusItem.button?.title = " ⚠"
        case .loaded:
            animator.setState(.idle)
            let spend = snapshot.todaySpend ?? 0
            statusItem.button?.title = " \(Money.format(cents: spend))"
        }
    }

    // MARK: - Click handling

    @objc private func handleStatusButton(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showActionsMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Pin the popover's reported content size to the SwiftUI frame
        // width. Without this, `NSHostingController` feeds AppKit a
        // larger intrinsic size and the popover body lays out around
        // that wider size while SwiftUI only paints content in
        // `DashboardView.width`. The invisible padding shows up as a
        // leftward shift of the body relative to the arrow.
        if let hosted = popover.contentViewController?.view,
           hosted.fittingSize.height > 0 {
            popover.contentSize = NSSize(width: DashboardView.width,
                                         height: hosted.fittingSize.height)
        }
        popover.show(relativeTo: button.bounds,
                     of: button,
                     preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        startEventMonitor()
    }

    func togglePopoverFromHotKey() {
        guard let button = statusItem.button else { return }
        togglePopover(from: button)
    }

    private func showActionsMenu(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        }
        let menu = menuBuilder.build(
            isLoggedIn: store.viewState != .loggedOut,
            canCheckForUpdates: updater.canCheckForUpdates
        )
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        scheduler.triggerNow(manual: true)
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func showAbout() {
        updater.showAboutPanel()
    }

    @objc private func openCursor() {
        openCursorAndDismiss()
    }

    @objc private func openCloudAgents() {
        openURLAndDismiss("https://cursor.com/agents")
    }

    @objc private func openStatus() {
        openURLAndDismiss("https://status.cursor.com/")
    }

    private func openCursorAndDismiss() {
        let cursorURL = URL(string: "cursor://")!
        if NSWorkspace.shared.urlForApplication(toOpen: cursorURL) != nil {
            NSWorkspace.shared.open(cursorURL)
        } else {
            let appURL = URL(fileURLWithPath: "/Applications/Cursor.app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                NSWorkspace.shared.open(appURL)
            }
        }
        popover.performClose(nil)
    }

    private func openURLAndDismiss(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
        popover.performClose(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func performInteraction(_ sender: NSMenuItem) {
        guard let action = InteractionMenuAction(rawValue: sender.tag) else { return }
        animator.play(action.animation)
    }

    func popoverWillClose(_ notification: Notification) {
        eventMonitor?.stop()
        eventMonitor = nil
    }

    private func startEventMonitor() {
        let monitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.shouldKeepPopoverOpen(for: event) {
                return event
            }
            self.popover.performClose(nil)
            return event
        }
        monitor.start()
        eventMonitor = monitor
    }

    private func shouldKeepPopoverOpen(for event: NSEvent) -> Bool {
        guard let eventWindow = event.window else {
            return false
        }
        if eventWindow == popover.contentViewController?.view.window {
            return true
        }
        if eventWindow == statusItem.button?.window {
            return true
        }
        let windowTypeName = String(describing: type(of: eventWindow))
        if windowTypeName.localizedCaseInsensitiveContains("Menu") {
            return true
        }
        return false
    }
}
