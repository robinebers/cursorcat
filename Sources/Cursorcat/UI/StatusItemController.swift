import AppKit
import Combine
import SwiftUI

/// Owns the `NSStatusItem`, the attached SwiftUI popover dashboard, and
/// the short right-click actions menu. Observes `UsageStore` (for the
/// tray title) and drives `CatAnimator` (for state locks like
/// logged-out / error).
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let store: UsageStore
    private let animator: CatAnimator
    private let scheduler: PollScheduler
    private let menuBuilder: ActionsMenuBuilder
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []
    private var activeFixture: ScreenshotFixture?

    init(store: UsageStore, animator: CatAnimator, scheduler: PollScheduler) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.store = store
        self.animator = animator
        self.scheduler = scheduler
        let builder = ActionsMenuBuilder(
            target: StatusItemController.self as AnyObject, // placeholder
            refreshSelector: #selector(StatusItemController.refreshNow),
            openCursorSelector: #selector(StatusItemController.openCursor),
            openCloudAgentsSelector: #selector(StatusItemController.openCloudAgents),
            openStatusSelector: #selector(StatusItemController.openStatus),
            quitSelector: #selector(StatusItemController.quit),
            interactSelector: #selector(StatusItemController.performInteraction(_:)),
            screenshotSelector: #selector(StatusItemController.screenshotModeChanged(_:))
        )
        self.menuBuilder = builder
        self.popover = NSPopover()
        super.init()
        builder.target = self

        let actions = DashboardActions(
            refresh: { [weak self] in
                self?.scheduler.triggerNow()
            },
            openCursor: { [weak self] in
                self?.openCursorAndDismiss()
            },
            interact: { [weak self] anim in
                self?.animator.play(anim)
                self?.popover.performClose(nil)
            },
            quit: {
                NSApplication.shared.terminate(nil)
            }
        )
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(store: store, actions: actions)
        )

        statusItem.button?.title = " …"
        statusItem.button?.imagePosition = .imageLeft
        if let button = statusItem.button {
            button.action = #selector(handleStatusButton(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        animator.onFrame = { [weak self] image in
            self?.statusItem.button?.image = image
        }
        animator.start()

        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in self?.applySnapshot(snap) }
            .store(in: &cancellables)
    }

    private func applySnapshot(_ snapshot: UsageSnapshot) {
        if !snapshot.isLoggedIn {
            animator.setState(.sleeping)
            statusItem.button?.title = " Not logged in"
            return
        }

        if snapshot.todaySpend == nil && snapshot.lastUpdated == nil {
            animator.setState(.idle)
            statusItem.button?.title = " …"
            return
        }

        if snapshot.todaySpend == nil && snapshot.lastError != nil {
            animator.setState(.error)
            statusItem.button?.title = " ⚠"
            return
        }

        animator.setState(.idle)
        let spend = snapshot.todaySpend ?? 0
        statusItem.button?.title = " \(Money.format(cents: spend))"
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
        popover.show(relativeTo: button.bounds,
                     of: button,
                     preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showActionsMenu(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        }
        let menu = menuBuilder.build(
            isLoggedIn: store.snapshot.isLoggedIn,
            screenshotState: screenshotMenuState
        )
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private var screenshotMenuState: ScreenshotMenuState {
        guard store.isScreenshotMode else { return .off }
        switch activeFixture {
        case .positive: return .positive
        case .negative: return .negative
        case nil: return .off
        }
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        scheduler.triggerNow()
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
        guard let animation = ActionsMenuBuilder.animation(forTag: sender.tag) else { return }
        animator.play(animation)
    }

    @objc private func screenshotModeChanged(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1:
            activeFixture = .positive
            store.applyFixture(.positive)
        case 2:
            activeFixture = .negative
            store.applyFixture(.negative)
        default:
            activeFixture = nil
            store.exitScreenshotMode()
            scheduler.triggerNow()
        }
    }
}
