import Foundation

/// Hand-crafted `UsageSnapshot` fixtures used by the Screenshot Mode tray
/// menu. Each case produces a fully-formed snapshot so the popover
/// renders a realistic, photography-ready dashboard without touching the
/// network. Values are tuned for an Ultra plan that includes $400/month
/// of usage, so the `billing cycle` row sits on the right side of that
/// threshold for each fixture.
enum ScreenshotFixture {
    /// Healthy day — spend trending down, quotas fresh, well under the
    /// $400 Ultra included cap. Exercises the green delta and high-fill
    /// progress bars.
    case positive

    /// Rough day — spend surging above the $400 included cap, on-demand
    /// nearly drained, credits almost gone. Exercises the red delta and
    /// near-empty progress bars.
    case negative

    func snapshot(now: Date = Date()) -> UsageSnapshot {
        switch self {
        case .positive:
            return UsageSnapshot(
                todaySpend: 1_847,
                yesterdaySpend: 2_612,
                last7DaysSpend: 9_430,
                billingCycleSpend: 16_420,
                billingCycleResetsAt: now.addingTimeInterval(Self.offset(days: 12, hours: 4, minutes: 33)),
                plan: "Ultra",
                requestsUsed: nil,
                requestsLimit: nil,
                autoPercentLeft: 59,
                apiPercentLeft: 73,
                onDemandRemaining: 100,
                onDemandLimit: 100,
                creditsLeft: 48_320,
                creditsTotal: 50_000,
                lastUpdated: now,
                lastError: nil,
                isLoggedIn: true
            )
        case .negative:
            return UsageSnapshot(
                todaySpend: 8_491,
                yesterdaySpend: 2_230,
                last7DaysSpend: 31_184,
                billingCycleSpend: 64_753,
                billingCycleResetsAt: now.addingTimeInterval(Self.offset(days: 2, hours: 3, minutes: 14)),
                plan: "Ultra",
                requestsUsed: nil,
                requestsLimit: nil,
                autoPercentLeft: 6,
                apiPercentLeft: 14,
                onDemandRemaining: 3,
                onDemandLimit: 100,
                creditsLeft: 1_540,
                creditsTotal: 50_000,
                lastUpdated: now,
                lastError: nil,
                isLoggedIn: true
            )
        }
    }

    private static func offset(days: Int, hours: Int, minutes: Int) -> TimeInterval {
        TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60)
    }
}
