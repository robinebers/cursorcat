import XCTest
@testable import CursorCat

final class ManifestAndModelBreakdownTests: XCTestCase {
    func testBundledManifestLoadsFamilyMetadata() throws {
        let manifest = try BundledModelManifestSource().loadManifest()

        XCTAssertEqual(manifest.retrievedAt, "2026-04-19")
        XCTAssertEqual(manifest.pricing["claude-4.7-opus"]?.familyID, "claude-4.7-opus")
        XCTAssertEqual(manifest.pricing["claude-4.7-opus"]?.familyDisplayName, "Claude 4.7 Opus")

        let gpt55 = try XCTUnwrap(manifest.pricing["gpt-5.5"])
        let gpt55Fast = try XCTUnwrap(manifest.pricing["gpt-5.5-fast"])
        XCTAssertEqual(gpt55.inputPerMillion, 5.0)
        XCTAssertEqual(gpt55.cacheWritePerMillion, 5.0)
        XCTAssertEqual(gpt55.cacheReadPerMillion, 0.5)
        XCTAssertEqual(gpt55.outputPerMillion, 30.0)
        XCTAssertEqual(gpt55Fast.inputPerMillion, 12.5)
        XCTAssertEqual(gpt55Fast.cacheWritePerMillion, 12.5)
        XCTAssertEqual(gpt55Fast.cacheReadPerMillion, 1.25)
        XCTAssertEqual(gpt55Fast.outputPerMillion, 75.0)
        XCTAssertEqual(gpt55.longContextInputThreshold, 272_000)
        XCTAssertEqual(gpt55.longContextInputMultiplier, 2.0)
        XCTAssertEqual(gpt55.longContextOutputMultiplier, 1.5)
    }

    func testPricingResolvesModelFamily() {
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-7-high")?.displayName, "Claude 4.7 Opus")
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-7-thinking-high")?.displayName, "Claude 4.7 Opus")
        XCTAssertEqual(Pricing.family(for: "composer-2-fast")?.displayName, "Composer 2")
        XCTAssertEqual(Pricing.family(for: "gpt-5.3-codex-low-fast")?.displayName, "GPT-5.3 Codex")
        XCTAssertEqual(Pricing.family(for: "gpt-5.4-mini-high")?.displayName, "GPT-5.4 Mini")
        XCTAssertEqual(Pricing.family(for: "gpt-5.5-high")?.displayName, "GPT-5.5")
        XCTAssertEqual(Pricing.family(for: "gpt-5.5-extra-high")?.displayName, "GPT-5.5")
        XCTAssertEqual(Pricing.family(for: "gpt-5.5-high-fast")?.displayName, "GPT-5.5")
        XCTAssertEqual(Pricing.family(for: "gpt-5.5-extra-high-fast")?.displayName, "GPT-5.5")
        XCTAssertEqual(Pricing.family(for: "default")?.displayName, "Auto")
    }

    func testGPT55CostEstimationUsesStandardAndFastTiersSeparately() {
        let underLongContextThreshold = TokenUsage(
            inputCacheWrite: 0,
            inputNoCacheWrite: 100_000,
            cacheRead: 100_000,
            output: 100_000
        )

        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "gpt-5.5-high", maxMode: false, tokens: underLongContextThreshold),
            3.55,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "gpt-5.5-high-fast", maxMode: false, tokens: underLongContextThreshold),
            8.875,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "gpt-5.5-high", maxMode: true, tokens: underLongContextThreshold),
            3.55,
            accuracy: 0.000_001
        )
    }

    func testGPT55AggregateRowsDoNotInferLongContextPricing() {
        let aggregateTokensAboveThreshold = TokenUsage(
            inputCacheWrite: 0,
            inputNoCacheWrite: 1_000_000,
            cacheRead: 1_000_000,
            output: 1_000_000
        )

        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "gpt-5.5-high", maxMode: false, tokens: aggregateTokensAboveThreshold),
            35.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "gpt-5.5-high", maxMode: true, tokens: aggregateTokensAboveThreshold),
            35.5,
            accuracy: 0.000_001
        )
    }

    func testAggregatorCollapsesFamiliesAcrossRanges() {
        let now = date("2026-04-19T12:00:00Z")
        let cycleStart = date("2026-04-15T00:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let rows = [
            makeRow(
                date: date("2026-04-19T10:00:00Z"),
                model: "claude-opus-4-7-high",
                tokenTotal: 1_000,
                costDollars: 1.25
            ),
            makeRow(
                date: date("2026-04-19T09:00:00Z"),
                model: "claude-opus-4-7-thinking-high",
                tokenTotal: 2_000,
                costDollars: 2.50
            ),
            makeRow(
                date: date("2026-04-18T08:00:00Z"),
                model: "composer-2-fast",
                tokenTotal: 3_000,
                costDollars: 3.75
            ),
            makeRow(
                date: date("2026-04-16T08:00:00Z"),
                model: "mystery-model",
                tokenTotal: 4_000,
                costDollars: 0
            )
        ]

        let breakdowns = ModelBreakdownAggregator.aggregate(
            rows: rows,
            billingCycleWindow: BillingCycleWindow(
                currentStart: cycleStart,
                previousStart: date("2026-03-11T00:00:00Z")
            ),
            costMode: .rawAPI,
            now: now,
            calendar: calendar
        )

        let todayRows = breakdowns[.today] ?? []
        XCTAssertEqual(todayRows.count, 1)
        XCTAssertEqual(todayRows.first?.displayName, "Claude 4.7 Opus")
        XCTAssertEqual(todayRows.first?.totalTokens, 3_000)
        XCTAssertEqual(todayRows.first?.totalCostCents, 375)
        XCTAssertEqual(
            todayRows.first?.variants,
            [
                .init(model: "claude-opus-4-7-thinking-high", totalCostCents: 250, isUnpriced: false),
                .init(model: "claude-opus-4-7-high", totalCostCents: 125, isUnpriced: false)
            ]
        )

        let yesterdayRows = breakdowns[.yesterday] ?? []
        XCTAssertEqual(yesterdayRows.map(\.displayName), ["Composer 2"])

        let cycleRows = breakdowns[.billingCycle] ?? []
        XCTAssertEqual(cycleRows.map(\.displayName), ["Claude 4.7 Opus", "Composer 2", "mystery-model"])
        XCTAssertEqual(cycleRows.last?.isUnpriced, true)
        XCTAssertEqual(cycleRows.last?.totalCostCents, 0)
        XCTAssertEqual(
            cycleRows.last?.variants,
            [.init(model: "mystery-model", totalCostCents: 0, isUnpriced: true)]
        )
    }

    func testAggregatorUsesActualCostWhenRequested() {
        let now = date("2026-04-19T12:00:00Z")
        let cycleStart = date("2026-04-15T00:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let rows = [
            makeRow(
                date: date("2026-04-19T10:00:00Z"),
                model: "claude-opus-4-7-high",
                tokenTotal: 1_000,
                costDollars: 1.25,
                csvCost: "Included"
            ),
            makeRow(
                date: date("2026-04-19T09:00:00Z"),
                model: "composer-2-fast",
                tokenTotal: 2_000,
                costDollars: 2.50,
                csvCost: "$0.44"
            )
        ]

        let breakdowns = ModelBreakdownAggregator.aggregate(
            rows: rows,
            billingCycleWindow: BillingCycleWindow(
                currentStart: cycleStart,
                previousStart: date("2026-03-11T00:00:00Z")
            ),
            costMode: .actual,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(breakdowns[.today]?.map(\.displayName), ["Composer 2"])
        XCTAssertEqual(breakdowns[.today]?.first?.totalCostCents, 44)
    }

    func testProjectorBuildsSharedRangeSummaries() {
        let now = date("2026-04-19T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let cycleStart = date("2026-04-15T00:00:00Z")
        let cycleEnd = date("2026-05-15T00:00:00Z")

        let api = APISnapshot(
            usage: GetCurrentPeriodUsageResponse(
                billingCycleStart: unixMillis(cycleStart),
                billingCycleEnd: unixMillis(cycleEnd),
                planUsage: nil,
                spendLimitUsage: nil,
                enabled: true
            ),
            plan: nil,
            credits: nil,
            csvRows: [
                makeRow(date: date("2026-04-19T09:00:00Z"), model: "composer-2-fast", tokenTotal: 100, costDollars: 1.00),
                makeRow(date: date("2026-04-18T09:00:00Z"), model: "composer-2-fast", tokenTotal: 100, costDollars: 2.00),
                makeRow(date: date("2026-04-16T09:00:00Z"), model: "composer-2-fast", tokenTotal: 100, costDollars: 3.00),
                makeRow(date: date("2026-04-10T09:00:00Z"), model: "composer-2-fast", tokenTotal: 100, costDollars: 4.00),
                makeRow(date: date("2026-04-05T09:00:00Z"), model: "composer-2-fast", tokenTotal: 100, costDollars: 6.00),
                makeRow(date: date("2026-03-10T09:00:00Z"), model: "composer-2-fast", tokenTotal: 100, costDollars: 5.00)
            ],
            stripeBalanceCents: 0,
            csvStart: date("2026-03-10T00:00:00Z"),
            csvEnd: now
        )

        let snapshot = UsageSnapshotProjector.project(
            api: api,
            costMode: .rawAPI,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.rangeSummaries[DashboardRange.today], DashboardRangeSummary(totalCents: 100, comparisonCents: 200, comparisonLabel: "vs. yesterday"))
        XCTAssertEqual(snapshot.rangeSummaries[DashboardRange.yesterday], DashboardRangeSummary(totalCents: 200, comparisonCents: 100, comparisonLabel: "vs. today"))
        XCTAssertEqual(snapshot.rangeSummaries[DashboardRange.billingCycle], DashboardRangeSummary(totalCents: 600, comparisonCents: 1000, comparisonLabel: "vs. prev billing cycle"))
        XCTAssertEqual(snapshot.rangeSummaries[DashboardRange.last30Days], DashboardRangeSummary(totalCents: 1600, comparisonCents: 500, comparisonLabel: "vs. prev. 30 days"))
    }

    func testCSVWindowStartsAtPreviousBillingCycleStart() {
        let now = date("2026-04-19T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let cycleStart = date("2026-04-15T00:00:00Z")
        let cycleEnd = date("2026-05-16T00:00:00Z")
        let usage = GetCurrentPeriodUsageResponse(
            billingCycleStart: unixMillis(cycleStart),
            billingCycleEnd: unixMillis(cycleEnd),
            planUsage: nil,
            spendLimitUsage: nil,
            enabled: true
        )

        let (start, end) = CursorAPI.csvWindow(usage: usage, now: now, calendar: calendar)

        XCTAssertEqual(start, date("2026-03-15T00:00:00Z"))
        XCTAssertEqual(end, date("2026-04-19T23:59:59Z"))
    }

    func testCSVWindowFallsBackTo63DaysWithoutCycleData() {
        let now = date("2026-04-19T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let (start, end) = CursorAPI.csvWindow(usage: nil, now: now, calendar: calendar)

        XCTAssertEqual(start, date("2026-02-15T00:00:00Z"))
        XCTAssertEqual(end, date("2026-04-19T23:59:59Z"))
    }

    private func makeRow(
        date: Date,
        model: String,
        tokenTotal: Int,
        costDollars: Double,
        csvCost: String = ""
    ) -> UsageCSVRow {
        UsageCSVRow(
            date: date,
            model: model,
            canonicalModel: Pricing.canonicalModel(for: model),
            maxMode: false,
            tokens: TokenUsage(
                inputCacheWrite: tokenTotal,
                inputNoCacheWrite: 0,
                cacheRead: 0,
                output: 0
            ),
            imputedCostDollars: costDollars,
            csvCost: csvCost
        )
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func unixMillis(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970 * 1000))
    }
}
