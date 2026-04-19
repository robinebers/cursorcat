import Foundation

@MainActor
final class DashboardPresentationState: ObservableObject {
    @Published var isPopoverVisible = false
}
