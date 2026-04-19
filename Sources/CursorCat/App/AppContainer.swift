import Foundation

@MainActor
final class AppContainer {
    let settings: UserSettings
    let store: UsageStore
    let animator: CatAnimator
    let behavior: CatBehavior
    let scheduler: PollScheduler
    let updater: AppUpdater
    let controller: StatusItemController
    let hotKeyController: GlobalHotKeyController

    init() {
        let settings = UserSettings()
        let auth = CursorAuth()
        let api = CursorAPI(auth: auth)
        let store = UsageStore(settings: settings)
        let animator = CatAnimator()
        let behavior = CatBehavior(animator: animator, store: store)
        let scheduler = PollScheduler(auth: auth, api: api, store: store)
        let updater = AppUpdater()
        let controller = StatusItemController(
            store: store,
            settings: settings,
            animator: animator,
            scheduler: scheduler,
            updater: updater
        )
        let hotKeyController = GlobalHotKeyController(settings: settings) {
            controller.togglePopoverFromHotKey()
        }

        self.settings = settings
        self.store = store
        self.animator = animator
        self.behavior = behavior
        self.scheduler = scheduler
        self.updater = updater
        self.controller = controller
        self.hotKeyController = hotKeyController
    }

    func start() {
        behavior.start()
        scheduler.start()
    }

    func stop() {
        behavior.stop()
        scheduler.stop()
        hotKeyController.stop()
    }
}
