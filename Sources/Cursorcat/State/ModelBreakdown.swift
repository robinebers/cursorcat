import Foundation

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .models: return "Models"
        }
    }
}

enum ModelBreakdownRange: String, CaseIterable, Hashable, Identifiable {
    case today
    case yesterday
    case billingCycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .billingCycle: return "Billing Cycle"
        }
    }
}

struct ModelBreakdownRow: Equatable, Identifiable {
    let familyID: String
    let displayName: String
    let totalTokens: Int
    let totalCostCents: Int
    let isUnpriced: Bool

    var id: String { familyID }
}

enum ModelBreakdownAggregator {
    private struct Accumulator {
        let familyID: String
        let displayName: String
        let isUnpriced: Bool
        var totalTokens: Int = 0
        var totalCostDollars: Double = 0
    }

    static func aggregate(
        rows: [UsageCSVRow],
        cycleStart: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ModelBreakdownRange: [ModelBreakdownRow]] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday

        return [
            .today: aggregateRows(rows) { row in
                row.date >= startOfToday
            },
            .yesterday: aggregateRows(rows) { row in
                row.date >= startOfYesterday && row.date < startOfToday
            },
            .billingCycle: aggregateRows(rows) { row in
                row.date >= cycleStart
            }
        ]
    }

    private static func aggregateRows(
        _ rows: [UsageCSVRow],
        includeRow: (UsageCSVRow) -> Bool
    ) -> [ModelBreakdownRow] {
        var grouped: [String: Accumulator] = [:]

        for row in rows where includeRow(row) && hasVisibleUsage(row) {
            let family = Pricing.family(for: row.model)
            let familyID = family?.id ?? row.model
            let displayName = family?.displayName ?? row.model
            let isUnpriced = family == nil

            var accumulator = grouped[familyID] ?? Accumulator(
                familyID: familyID,
                displayName: displayName,
                isUnpriced: isUnpriced
            )
            accumulator.totalTokens += row.tokens.totalTokens
            accumulator.totalCostDollars += row.imputedCostDollars
            grouped[familyID] = accumulator
        }

        return grouped.values
            .map {
                ModelBreakdownRow(
                    familyID: $0.familyID,
                    displayName: $0.displayName,
                    totalTokens: $0.totalTokens,
                    totalCostCents: Pricing.toCents($0.totalCostDollars),
                    isUnpriced: $0.isUnpriced
                )
            }
            .sorted {
                if $0.totalCostCents != $1.totalCostCents {
                    return $0.totalCostCents > $1.totalCostCents
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private static func hasVisibleUsage(_ row: UsageCSVRow) -> Bool {
        row.tokens.totalTokens != 0 || row.imputedCostDollars != 0
    }
}
