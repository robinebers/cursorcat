import XCTest
@testable import CursorCat

final class ManifestAndModelBreakdownTests: XCTestCase {
    func testBundledManifestLoadsFamilyMetadata() throws {
        let manifest = try BundledModelManifestSource().loadManifest()

        XCTAssertEqual(manifest.retrievedAt, "2026-06-27")
        XCTAssertEqual(manifest.pricing["claude-4.7-opus"]?.familyID, "claude-4.7-opus")
        XCTAssertEqual(manifest.pricing["claude-4.7-opus"]?.familyDisplayName, "Claude 4.7 Opus")

        XCTAssertEqual(manifest.pricing["claude-4.8-opus"]?.familyID, "claude-4.8-opus")
        XCTAssertEqual(manifest.pricing["claude-4.8-opus"]?.familyDisplayName, "Claude 4.8 Opus")
        let opus48 = try XCTUnwrap(manifest.pricing["claude-4.8-opus"])
        XCTAssertEqual(opus48.inputPerMillion, 5.0)
        XCTAssertEqual(opus48.cacheWritePerMillion, 6.25)
        XCTAssertEqual(opus48.cacheReadPerMillion, 0.5)
        XCTAssertEqual(opus48.outputPerMillion, 25.0)
        let opus48Fast = try XCTUnwrap(manifest.pricing["claude-4.8-opus-fast"])
        XCTAssertEqual(opus48Fast.inputPerMillion, 10.0)
        XCTAssertEqual(opus48Fast.cacheWritePerMillion, 12.5)
        XCTAssertEqual(opus48Fast.cacheReadPerMillion, 1.0)
        XCTAssertEqual(opus48Fast.outputPerMillion, 50.0)
        XCTAssertEqual(opus48Fast.familyID, "claude-4.8-opus")
        XCTAssertEqual(opus48Fast.inputPerMillion, opus48.inputPerMillion * 2)
        XCTAssertEqual(opus48Fast.outputPerMillion, opus48.outputPerMillion * 2)

        let fable5 = try XCTUnwrap(manifest.pricing["claude-fable-5"])
        XCTAssertEqual(fable5.familyID, "claude-fable-5")
        XCTAssertEqual(fable5.familyDisplayName, "Claude Fable 5")
        XCTAssertEqual(fable5.inputPerMillion, 10.0)
        XCTAssertEqual(fable5.cacheWritePerMillion, 12.5)
        XCTAssertEqual(fable5.cacheReadPerMillion, 1.0)
        XCTAssertEqual(fable5.outputPerMillion, 50.0)
        XCTAssertEqual(fable5.inputPerMillion, opus48.inputPerMillion * 2)
        XCTAssertEqual(fable5.cacheWritePerMillion, opus48.cacheWritePerMillion * 2)
        XCTAssertEqual(fable5.cacheReadPerMillion, opus48.cacheReadPerMillion * 2)
        XCTAssertEqual(fable5.outputPerMillion, opus48.outputPerMillion * 2)

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

        let composer25 = try XCTUnwrap(manifest.pricing["composer-2.5"])
        let composer25Fast = try XCTUnwrap(manifest.pricing["composer-2.5-fast"])
        XCTAssertEqual(composer25.inputPerMillion, 0.5)
        XCTAssertEqual(composer25.cacheReadPerMillion, 0.2)
        XCTAssertEqual(composer25.outputPerMillion, 2.5)
        XCTAssertEqual(composer25Fast.inputPerMillion, 3.0)
        XCTAssertEqual(composer25Fast.cacheReadPerMillion, 0.5)
        XCTAssertEqual(composer25Fast.outputPerMillion, 15.0)

        let grok43 = try XCTUnwrap(manifest.pricing["grok-4.3"])
        XCTAssertEqual(grok43.inputPerMillion, 1.25)
        XCTAssertEqual(grok43.cacheReadPerMillion, 0.2)
        XCTAssertEqual(grok43.outputPerMillion, 2.5)

        let grokBuild = try XCTUnwrap(manifest.pricing["grok-build-0.1"])
        XCTAssertEqual(grokBuild.inputPerMillion, 1.0)
        XCTAssertEqual(grokBuild.cacheWritePerMillion, 1.0)
        XCTAssertEqual(grokBuild.cacheReadPerMillion, 0.2)
        XCTAssertEqual(grokBuild.outputPerMillion, 2.0)

        let gemini35Flash = try XCTUnwrap(manifest.pricing["gemini-3.5-flash"])
        XCTAssertEqual(gemini35Flash.inputPerMillion, 1.5)
        XCTAssertEqual(gemini35Flash.cacheWritePerMillion, 1.5)
        XCTAssertEqual(gemini35Flash.cacheReadPerMillion, 0.15)
        XCTAssertEqual(gemini35Flash.outputPerMillion, 9.0)
    }

    func testPricingResolvesModelFamily() {
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-7-high")?.displayName, "Claude 4.7 Opus")
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-7-thinking-high")?.displayName, "Claude 4.7 Opus")
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-8-thinking-high")?.displayName, "Claude 4.8 Opus")
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-8-thinking-max")?.displayName, "Claude 4.8 Opus")
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-8-thinking-high-fast")?.displayName, "Claude 4.8 Opus")
        XCTAssertEqual(Pricing.family(for: "claude-fable-5")?.displayName, "Claude Fable 5")
        XCTAssertEqual(Pricing.family(for: "claude-fable-5-thinking-xhigh")?.displayName, "Claude Fable 5")
        XCTAssertEqual(Pricing.family(for: "composer-2-fast")?.displayName, "Composer 2")
        XCTAssertEqual(Pricing.family(for: "composer-2.5")?.displayName, "Composer 2.5")
        XCTAssertEqual(Pricing.family(for: "composer-2.5-fast")?.displayName, "Composer 2.5")
        XCTAssertEqual(Pricing.family(for: "github_bugbot")?.displayName, "Bugbot Review")
        XCTAssertEqual(Pricing.family(for: "github_bugbot")?.id, "github_bugbot")
        XCTAssertEqual(Pricing.family(for: "grok-4.3")?.displayName, "Grok 4.3")
        XCTAssertEqual(Pricing.family(for: "grok-build-0.1")?.displayName, "Grok Build 0.1")
        XCTAssertEqual(Pricing.family(for: "grok-code-fast-1")?.displayName, "Grok Build 0.1")
        XCTAssertEqual(Pricing.family(for: "gpt-5.3-codex-low-fast")?.displayName, "GPT-5.3 Codex")
        XCTAssertEqual(Pricing.family(for: "gpt-5.4-mini-high")?.displayName, "GPT-5.4 Mini")
        XCTAssertEqual(Pricing.family(for: "gpt-5.5-high")?.displayName, "GPT-5.5")
        XCTAssertEqual(Pricing.family(for: "gpt-5.5-extra-high")?.displayName, "GPT-5.5")
        XCTAssertEqual(Pricing.family(for: "gpt-5.5-high-fast")?.displayName, "GPT-5.5")
        XCTAssertEqual(Pricing.family(for: "gpt-5.5-extra-high-fast")?.displayName, "GPT-5.5")
        XCTAssertEqual(Pricing.family(for: "gemini-3.5-flash")?.displayName, "Gemini 3.5 Flash")
        XCTAssertEqual(Pricing.family(for: "default")?.displayName, "Auto")
        XCTAssertEqual(Pricing.family(for: "glm-5.2")?.displayName, "GLM 5.2")
        XCTAssertEqual(Pricing.family(for: "glm-5.2-max")?.displayName, "GLM 5.2")
    }

    func testComposer25CostEstimation() {
        let tokens = TokenUsage(
            inputCacheWrite: 0,
            inputNoCacheWrite: 100_000,
            cacheRead: 100_000,
            output: 100_000
        )

        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "composer-2.5", maxMode: false, tokens: tokens),
            0.32,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "composer-2.5-fast", maxMode: false, tokens: tokens),
            1.85,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "grok-build-0.1", maxMode: false, tokens: tokens),
            0.32,
            accuracy: 0.000_001
        )
        let gpt55Sample = TokenUsage(
            inputCacheWrite: 0,
            inputNoCacheWrite: 100_000,
            cacheRead: 100_000,
            output: 100_000
        )
        XCTAssertEqual(
            Pricing.estimatedCostDollars(model: "github_bugbot", maxMode: false, tokens: gpt55Sample),
            Pricing.estimatedCostDollars(model: "gpt-5.5-high", maxMode: false, tokens: gpt55Sample),
            accuracy: 0.000_001
        )
    }

    func testBugbotAggregatesAsSeparateFamilyFromGPT55() {
        let now = date("2026-04-19T12:00:00Z")
        let cycleStart = date("2026-04-15T00:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let rows = [
            makeRow(date: date("2026-04-19T10:00:00Z"), model: "github_bugbot", tokenTotal: 1_000, costDollars: 1.0),
            makeRow(date: date("2026-04-19T09:00:00Z"), model: "gpt-5.5-high", tokenTotal: 2_000, costDollars: 2.0)
        ]

        let breakdowns = ModelBreakdownAggregator.aggregate(
            rows: rows,
            billingCycleWindow: BillingCycleWindow(currentStart: cycleStart, previousStart: cycleStart),
            costMode: .rawAPI,
            now: now,
            calendar: calendar
        )

        let todayNames = Set(breakdowns[.today]?.map(\.displayName) ?? [])
        XCTAssertEqual(todayNames, ["Bugbot Review", "GPT-5.5"])
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
            stripeBalanceCents: 0
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

    @MainActor
    func testUsageStoreSwitchesCostModeFromProjectedCache() {
        let suiteName = "CursorCatTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = UserSettings(defaults: defaults)
        let store = UsageStore(settings: settings)
        let now = date("2026-04-19T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        store.applySnapshot(
            APISnapshot(
                usage: nil,
                plan: nil,
                credits: nil,
                csvRows: [
                    makeRow(
                        date: date("2026-04-19T09:00:00Z"),
                        model: "composer-2-fast",
                        tokenTotal: 100,
                        costDollars: 1.00,
                        csvCost: "$2.50"
                    )
                ],
                stripeBalanceCents: 0
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(store.snapshot.todaySpend, 100)
        settings.costMode = .actual
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(store.snapshot.todaySpend, 250)
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
