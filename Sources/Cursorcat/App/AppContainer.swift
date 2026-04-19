import Foundation

@MainActor
final class AppContainer {
    let settings: UserSettings
    let store: UsageStore
    let animator: CatAnimator
    let behavior: CatBehavior
    let scheduler: PollScheduler
    let controller: StatusItemController
    let hotKeyController: GlobalHotKeyController

    init() {
        let settings = UserSettings()
        let auth = CursorAuth()
        let api = CursorAPI(auth: auth)
        let store = UsageStore(settings: settings)
        let animator = CatAnimator()
        let behavior = CatBehavior(animator: animator, store: store)
        let scheduler = PollScheduler(api: api, store: store)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            animator: animator,
            scheduler: scheduler
        )
        let hotKeyController = GlobalHotKeyController(settings: settings) {
            controller.togglePopoverFromHotKey()
        }

        self.settings = settings
        self.store = store
        self.animator = animator
        self.behavior = behavior
        self.scheduler = scheduler
        self.controller = controller
        self.hotKeyController = hotKeyController
    }

    func start() {
        behavior.start()
        scheduler.start()
    }
}
