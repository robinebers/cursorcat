import Foundation

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case models
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .models: return "Models"
        case .settings: return "Settings"
        }
    }
}

enum ModelBreakdownRange: String, CaseIterable, Hashable, Identifiable {
    case today
    case yesterday
    case billingCycle
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .billingCycle: return "Billing Cycle"
        case .last30Days: return "Last 30 Days"
        }
    }
}

struct ModelBreakdownRow: Equatable, Identifiable {
    struct Variant: Equatable, Identifiable {
        let model: String
        let totalCostCents: Int
        let isUnpriced: Bool

        var id: String { model }
    }

    let familyID: String
    let displayName: String
    let totalTokens: Int
    let totalCostCents: Int
    let isUnpriced: Bool
    let variants: [Variant]

    var id: String { familyID }
}

enum ModelBreakdownAggregator {
    private struct VariantAccumulator {
        let model: String
        let isUnpriced: Bool
        var totalCostDollars: Double = 0
    }

    private struct Accumulator {
        let familyID: String
        let displayName: String
        let isUnpriced: Bool
        var totalTokens: Int = 0
        var totalCostDollars: Double = 0
        var variants: [String: VariantAccumulator] = [:]
    }

    static func aggregate(
        rows: [UsageCSVRow],
        cycleStart: Date,
        costMode: CostMode,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ModelBreakdownRange: [ModelBreakdownRow]] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfLast30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday

        return [
            .today: aggregateRows(rows, costMode: costMode) { row in
                row.date >= startOfToday
            },
            .yesterday: aggregateRows(rows, costMode: costMode) { row in
                row.date >= startOfYesterday && row.date < startOfToday
            },
            .billingCycle: aggregateRows(rows, costMode: costMode) { row in
                row.date >= cycleStart
            },
            .last30Days: aggregateRows(rows, costMode: costMode) { row in
                row.date >= startOfLast30Days
            }
        ]
    }

    private static func aggregateRows(
        _ rows: [UsageCSVRow],
        costMode: CostMode,
        includeRow: (UsageCSVRow) -> Bool
    ) -> [ModelBreakdownRow] {
        var grouped: [String: Accumulator] = [:]

        for row in rows where includeRow(row) && hasVisibleUsage(row, costMode: costMode) {
            let family = Pricing.family(for: row.model)
            let familyID = family?.id ?? row.model
            let displayName = family?.displayName ?? row.model
            let costDollars = row.costDollars(for: costMode)
            let isUnpriced = rowIsUnpriced(row, family: family, costMode: costMode)

            var accumulator = grouped[familyID] ?? Accumulator(
                familyID: familyID,
                displayName: displayName,
                isUnpriced: isUnpriced
            )
            accumulator.totalTokens += row.tokens.totalTokens
            accumulator.totalCostDollars += costDollars

            var variant = accumulator.variants[row.model] ?? VariantAccumulator(
                model: row.model,
                isUnpriced: variantIsUnpriced(row, costMode: costMode)
            )
            variant.totalCostDollars += costDollars
            accumulator.variants[row.model] = variant
            grouped[familyID] = accumulator
        }

        return grouped.values
            .map {
                ModelBreakdownRow(
                    familyID: $0.familyID,
                    displayName: $0.displayName,
                    totalTokens: $0.totalTokens,
                    totalCostCents: Pricing.toCents($0.totalCostDollars),
                    isUnpriced: $0.isUnpriced,
                    variants: $0.variants.values
                        .map {
                            ModelBreakdownRow.Variant(
                                model: $0.model,
                                totalCostCents: Pricing.toCents($0.totalCostDollars),
                                isUnpriced: $0.isUnpriced
                            )
                        }
                        .sorted {
                            if $0.totalCostCents != $1.totalCostCents {
                                return $0.totalCostCents > $1.totalCostCents
                            }
                            return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
                        }
                )
            }
            .sorted {
                if $0.totalCostCents != $1.totalCostCents {
                    return $0.totalCostCents > $1.totalCostCents
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private static func hasVisibleUsage(_ row: UsageCSVRow, costMode: CostMode) -> Bool {
        switch costMode {
        case .actual:
            return row.costDollars(for: .actual) > 0
        case .rawAPI:
            return row.tokens.totalTokens != 0 || row.imputedCostDollars != 0
        }
    }

    private static func rowIsUnpriced(
        _ row: UsageCSVRow,
        family: Pricing.ModelFamily?,
        costMode: CostMode
    ) -> Bool {
        switch costMode {
        case .actual:
            return row.actualCostDollars == nil
        case .rawAPI:
            return family == nil
        }
    }

    private static func variantIsUnpriced(_ row: UsageCSVRow, costMode: CostMode) -> Bool {
        switch costMode {
        case .actual:
            return row.actualCostDollars == nil
        case .rawAPI:
            return Pricing.pricingEntry(for: row.model) == nil
        }
    }
}
