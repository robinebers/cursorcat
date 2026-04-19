import Foundation
import Combine

/// Derived snapshot for the menu + tray title. All money is cents (Int).
struct UsageSnapshot: Equatable {
    var todaySpend: Int?
    var yesterdaySpend: Int?

    var billingCycleSpend: Int?
    var billingCycleResetsAt: Date?
    var modelBreakdowns: [ModelBreakdownRange: [ModelBreakdownRow]] = [:]

    var plan: String?

    var autoPercentLeft: Double?
    var apiPercentLeft: Double?

    var onDemandRemaining: Int?
    var onDemandLimit: Int?

    var creditsLeft: Int?
    var creditsTotal: Int?

    var lastUpdated: Date?
    var lastError: String?
    var isLoggedIn: Bool = true

    static let loading = UsageSnapshot()
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .loading
    @Published private(set) var viewState: UsageViewState = .loading

    func applySnapshot(_ api: APISnapshot, now: Date = Date(), calendar: Calendar = .current) {
        snapshot = UsageSnapshotProjector.project(
            api: api,
            previous: snapshot,
            now: now,
            calendar: calendar
        )
        viewState = .loaded
    }

    func setLoggedOut() {
        snapshot = UsageSnapshot(lastUpdated: snapshot.lastUpdated, isLoggedIn: false)
        viewState = .loggedOut
    }

    func setError(_ message: String) {
        var next = snapshot
        next.lastError = message
        snapshot = next
        viewState = hasRenderableContent(next) ? .loaded : .failed
    }

    private func hasRenderableContent(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.lastUpdated != nil || snapshot.todaySpend != nil
    }
}
