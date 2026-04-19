import Foundation

@MainActor
final class AppContainer {
    let store: UsageStore
    let animator: CatAnimator
    let behavior: CatBehavior
    let scheduler: PollScheduler
    let controller: StatusItemController

    init() {
        let auth = CursorAuth()
        let api = CursorAPI(auth: auth)
        let store = UsageStore()
        let animator = CatAnimator()
        let behavior = CatBehavior(animator: animator, store: store)
        let scheduler = PollScheduler(api: api, store: store)
        let controller = StatusItemController(
            store: store,
            animator: animator,
            scheduler: scheduler
        )

        self.store = store
        self.animator = animator
        self.behavior = behavior
        self.scheduler = scheduler
        self.controller = controller
    }

    func start() {
        behavior.start()
        scheduler.start()
    }
}
