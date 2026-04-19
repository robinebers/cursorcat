import SwiftUI

struct DashboardActions {
    var refresh: () -> Void
    var openCursor: () -> Void
    var quit: () -> Void
}

struct DashboardView: View {
    static let width: CGFloat = 280

    @ObservedObject var store: UsageStore
    let actions: DashboardActions

    var body: some View {
        Group {
            switch store.viewState {
            case .loggedOut:
                LoggedOutCard(actions: actions)
            case .loading:
                LoadingCard()
            case .failed:
                LoadingCard()
            case .loaded:
                DashboardContent(snapshot: store.snapshot, actions: actions)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.width)
    }
}
