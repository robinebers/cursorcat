import Foundation
import Combine

/// Derived snapshot for the menu + tray title. All money is cents (Int).
struct UsageSnapshot: Equatable {
    var todaySpend: Int?
    var yesterdaySpend: Int?
    var billingCycleSpend: Int?
    var last30DaysSpend: Int?
    var previousBillingCycleSpend: Int?
    var previous30DaysSpend: Int?
    var billingCycleResetsAt: Date?
    var rangeSummaries: [DashboardRange: DashboardRangeSummary] = [:]
    var modelBreakdowns: [DashboardRange: [ModelBreakdownRow]] = [:]

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

    static let loading = UsageSnapshot(isLoggedIn: false)
}

@MainActor
final class UsageStore: ObservableObject {
    private let settings: UserSettings
    private var latestAPISnapshot: APISnapshot?
    private var cancellables: Set<AnyCancellable> = []

    @Published private(set) var snapshot: UsageSnapshot = .loading
    @Published private(set) var viewState: UsageViewState = .loading

    init(settings: UserSettings) {
        self.settings = settings

        settings.$costMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reprojectLatestSnapshot()
            }
            .store(in: &cancellables)
    }

    func applySnapshot(_ api: APISnapshot, now: Date = Date(), calendar: Calendar = .current) {
        latestAPISnapshot = api
        snapshot = UsageSnapshotProjector.project(
            api: api,
            costMode: settings.costMode,
            now: now,
            calendar: calendar
        )
        viewState = .loaded
    }

    func setLoggedOut() {
        latestAPISnapshot = nil
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
        snapshot.lastUpdated != nil || !snapshot.rangeSummaries.isEmpty
    }

    private func reprojectLatestSnapshot() {
        guard let latestAPISnapshot, viewState != .loggedOut else { return }

        let preservedLastUpdated = snapshot.lastUpdated
        let preservedLastError = snapshot.lastError
        let preservedViewState = viewState
        var next = UsageSnapshotProjector.project(
            api: latestAPISnapshot,
            costMode: settings.costMode,
            now: preservedLastUpdated ?? Date()
        )
        next.lastUpdated = preservedLastUpdated
        if preservedViewState != .loaded {
            next.lastError = preservedLastError
        }
        snapshot = next
        if preservedViewState == .loaded {
            viewState = .loaded
        }
    }
}
