import AppKit
import SwiftUI

@main
struct CursorcatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar agent apps have no main window. `Settings` gives SwiftUI a
        // valid scene without creating an activation window.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore!
    private var animator: CatAnimator!
    private var behavior: CatBehavior!
    private var scheduler: PollScheduler!
    private var controller: StatusItemController!
    private var auth: CursorAuth!
    private var api: CursorAPI!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Log.app.info("launch")

        auth = CursorAuth()
        api = CursorAPI(auth: auth)
        store = UsageStore()
        animator = CatAnimator()
        behavior = CatBehavior(animator: animator, store: store)
        scheduler = PollScheduler(api: api, store: store, auth: auth)
        controller = StatusItemController(
            store: store,
            animator: animator,
            scheduler: scheduler
        )

        behavior.start()
        scheduler.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("terminate")
    }
}
