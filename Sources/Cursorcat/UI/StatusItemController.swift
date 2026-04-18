import AppKit
import Combine

/// Owns the NSStatusItem. Observes UsageStore + CatAnimator.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let store: UsageStore
    private let animator: CatAnimator
    private let scheduler: PollScheduler
    private let menuBuilder: MenuBuilder
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore, animator: CatAnimator, scheduler: PollScheduler) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.store = store
        self.animator = animator
        self.scheduler = scheduler
        let builder = MenuBuilder(
            target: StatusItemController.self as AnyObject, // placeholder, overwritten below
            refreshSelector: #selector(StatusItemController.refreshNow),
            openCursorSelector: #selector(StatusItemController.openCursor),
            quitSelector: #selector(StatusItemController.quit),
            interactSelector: #selector(StatusItemController.performInteraction(_:))
        )
        self.menuBuilder = builder
        super.init()
        builder.target = self

        statusItem.button?.title = " …"
        statusItem.button?.imagePosition = .imageLeft

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
        statusItem.menu = menuBuilder.build(snapshot: snapshot)

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

    @objc private func refreshNow() {
        scheduler.triggerNow()
    }

    @objc private func openCursor() {
        let cursorURL = URL(string: "cursor://")!
        if NSWorkspace.shared.urlForApplication(toOpen: cursorURL) != nil {
            NSWorkspace.shared.open(cursorURL)
            return
        }
        let appURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.open(appURL)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func performInteraction(_ sender: NSMenuItem) {
        guard let animation = MenuBuilder.animation(forTag: sender.tag) else { return }
        animator.play(animation)
    }
}
