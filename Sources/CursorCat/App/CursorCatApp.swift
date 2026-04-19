import AppKit
import SwiftUI

@main
struct CursorCatApp: App {
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
    private var app: AppContainer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Log.app.info("launch")

        app = AppContainer()
        app.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.stop()
        Log.app.info("terminate")
    }
}
