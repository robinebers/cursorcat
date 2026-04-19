import SwiftUI

struct DashboardActions {
    var refresh: () -> Void
    var openCursor: () -> Void
}

struct DashboardView: View {
    static let width: CGFloat = 280

    @ObservedObject var store: UsageStore
    @ObservedObject var settings: UserSettings
    @ObservedObject var scheduler: PollScheduler
    let actions: DashboardActions

    var body: some View {
        Group {
            switch store.viewState {
            case .loggedOut:
                LoggedOutCard(actions: actions)
            case .loading:
                LoadingCard()
            case .failed:
                FailedCard(message: store.snapshot.lastError, actions: actions)
            case .loaded:
                DashboardContent(
                    snapshot: store.snapshot,
                    settings: settings,
                    scheduler: scheduler,
                    actions: actions
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.width)
    }
}
