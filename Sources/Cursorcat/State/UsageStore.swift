import Foundation
import Combine

/// Derived snapshot for the menu + tray title. All money is cents (Int).
struct UsageSnapshot: Equatable {
    var todaySpend: Int?
    var yesterdaySpend: Int?
    var last7DaysSpend: Int?

    var billingCycleSpend: Int?
    var billingCycleResetsAt: Date?

    var plan: String?
    var requestsUsed: Int?
    var requestsLimit: Int?

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
    static let loggedOut = UsageSnapshot(isLoggedIn: false)
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .loading

    /// When true, the store has been pinned to a hand-crafted fixture
    /// (see `ScreenshotFixture`) and the poll scheduler must not
    /// overwrite the snapshot until `exitScreenshotMode()` is called.
    @Published private(set) var isScreenshotMode: Bool = false

    func applySnapshot(_ api: APISnapshot, now: Date = Date(), calendar: Calendar = .current) {
        var next = snapshot
        next.isLoggedIn = true
        next.lastError = nil
        next.lastUpdated = now

        // Windowed derivations. All spend values are *imputed* (what usage would
        // have cost at provider list prices), computed from CSV rows via the
        // pricing manifest. Plan coverage (Ultra etc.) is ignored.
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOf7d = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        let cycleStart = api.usage?.billingCycleStart?.asUnixMillisDate ?? api.csvStart

        var today = 0.0
        var yesterday = 0.0
        var last7 = 0.0
        var cycle = 0.0
        for row in api.csvRows {
            let c = row.imputedCostDollars
            if row.date >= startOfToday { today += c }
            if row.date >= startOfYesterday, row.date < startOfToday { yesterday += c }
            if row.date >= startOf7d { last7 += c }
            if row.date >= cycleStart { cycle += c }
        }
        next.todaySpend = Pricing.toCents(today)
        next.yesterdaySpend = Pricing.toCents(yesterday)
        next.last7DaysSpend = Pricing.toCents(last7)
        next.billingCycleSpend = Pricing.toCents(cycle)

        // RPC auto/api percent and plan limit signals remain informative.
        if let pu = api.usage?.planUsage {
            if let auto = pu.autoPercentUsed {
                next.autoPercentLeft = max(0, 100 - auto)
            }
            if let api = pu.apiPercentUsed {
                next.apiPercentLeft = max(0, 100 - api)
            }
        }

        if let endStr = api.usage?.billingCycleEnd, let end = endStr.asUnixMillisDate {
            next.billingCycleResetsAt = end
        }

        if let spend = api.usage?.spendLimitUsage {
            let limit = spend.individualLimit ?? spend.pooledLimit
            let remaining = spend.individualRemaining ?? spend.pooledRemaining
            if let limit, limit > 0 {
                next.onDemandLimit = Int(limit.rounded())
                next.onDemandRemaining = Int((remaining ?? 0).rounded())
            }
        }

        if let name = api.plan?.planInfo?.planName, !name.isEmpty {
            next.plan = name
        }

        if let credits = api.credits, credits.hasCreditGrants == true {
            let total = Int(credits.totalCents ?? "0") ?? 0
            let used = Int(credits.usedCents ?? "0") ?? 0
            let stripeBonus = max(0, api.stripeBalanceCents)
            next.creditsLeft = max(0, total - used) + api.stripeBalanceCents
            next.creditsTotal = total + stripeBonus
        } else if api.stripeBalanceCents > 0 {
            next.creditsLeft = api.stripeBalanceCents
            next.creditsTotal = api.stripeBalanceCents
        } else {
            next.creditsLeft = nil
            next.creditsTotal = nil
        }

        snapshot = next
    }

    func setLoggedOut() {
        snapshot = UsageSnapshot(lastUpdated: snapshot.lastUpdated, isLoggedIn: false)
    }

    func setError(_ message: String) {
        var next = snapshot
        next.lastError = message
        snapshot = next
    }

    /// Pins the store to a fixture snapshot and turns on screenshot
    /// mode. `PollScheduler` early-returns while this flag is set so the
    /// fixture survives across wake events and manual refreshes.
    func applyFixture(_ fixture: ScreenshotFixture) {
        isScreenshotMode = true
        snapshot = fixture.snapshot()
    }

    /// Leaves screenshot mode but does NOT clear the snapshot — the
    /// caller is expected to trigger a real poll which will overwrite it
    /// within seconds.
    func exitScreenshotMode() {
        isScreenshotMode = false
    }
}
