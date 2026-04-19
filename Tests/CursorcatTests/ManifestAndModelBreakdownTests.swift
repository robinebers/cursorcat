import XCTest
@testable import CursorCat

final class ManifestAndModelBreakdownTests: XCTestCase {
    func testBundledManifestLoadsFamilyMetadata() throws {
        let manifest = try BundledModelManifestSource().loadManifest()

        XCTAssertEqual(manifest.retrievedAt, "2026-03-17")
        XCTAssertEqual(manifest.pricing["claude-4.7-opus"]?.familyID, "claude-4.7-opus")
        XCTAssertEqual(manifest.pricing["claude-4.7-opus"]?.familyDisplayName, "Claude 4.7 Opus")
    }

    func testPricingResolvesModelFamily() {
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-7-high")?.displayName, "Claude 4.7 Opus")
        XCTAssertEqual(Pricing.family(for: "claude-opus-4-7-thinking-high")?.displayName, "Claude 4.7 Opus")
        XCTAssertEqual(Pricing.family(for: "composer-2-fast")?.displayName, "Composer 2")
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
            cycleStart: cycleStart,
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
            cycleStart: cycleStart,
            costMode: .actual,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(breakdowns[.today]?.map(\.displayName), ["Composer 2"])
        XCTAssertEqual(breakdowns[.today]?.first?.totalCostCents, 44)
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
}
