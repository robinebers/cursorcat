import Foundation

enum UsageSnapshotProjector {
    static func project(
        api: APISnapshot,
        costMode: CostMode,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        var next = UsageSnapshot()
        next.isLoggedIn = true
        next.lastError = nil
        next.lastUpdated = now

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfLast30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        let startOfPrevious30Days = calendar.date(byAdding: .day, value: -59, to: startOfToday) ?? startOfToday
        let billingCycleWindow = BillingCycleWindow.resolve(
            start: api.usage?.billingCycleStart?.asUnixMillisDate,
            end: api.usage?.billingCycleEnd?.asUnixMillisDate,
            now: now,
            calendar: calendar
        )

        var today = 0.0
        var yesterday = 0.0
        var billingCycle = 0.0
        var previousBillingCycle = 0.0
        var last30Days = 0.0
        var previous30Days = 0.0

        for row in api.csvRows {
            let cost = row.costDollars(for: costMode)
            if row.date >= startOfToday {
                today += cost
            }
            if row.date >= startOfYesterday, row.date < startOfToday {
                yesterday += cost
            }
            if row.date >= billingCycleWindow.currentStart {
                billingCycle += cost
            }
            if row.date >= billingCycleWindow.previousStart, row.date < billingCycleWindow.currentStart {
                previousBillingCycle += cost
            }
            if row.date >= startOfLast30Days {
                last30Days += cost
            }
            if row.date >= startOfPrevious30Days, row.date < startOfLast30Days {
                previous30Days += cost
            }
        }

        next.todaySpend = Pricing.toCents(today)
        next.yesterdaySpend = Pricing.toCents(yesterday)
        next.billingCycleSpend = Pricing.toCents(billingCycle)
        next.last30DaysSpend = Pricing.toCents(last30Days)
        next.previousBillingCycleSpend = Pricing.toCents(previousBillingCycle)
        next.previous30DaysSpend = Pricing.toCents(previous30Days)
        next.rangeSummaries = [
            .today: DashboardRangeSummary(
                totalCents: Pricing.toCents(today),
                comparisonCents: Pricing.toCents(yesterday),
                comparisonLabel: DashboardRange.today.comparisonLabel
            ),
            .yesterday: DashboardRangeSummary(
                totalCents: Pricing.toCents(yesterday),
                comparisonCents: Pricing.toCents(today),
                comparisonLabel: DashboardRange.yesterday.comparisonLabel
            ),
            .billingCycle: DashboardRangeSummary(
                totalCents: Pricing.toCents(billingCycle),
                comparisonCents: Pricing.toCents(previousBillingCycle),
                comparisonLabel: DashboardRange.billingCycle.comparisonLabel
            ),
            .last30Days: DashboardRangeSummary(
                totalCents: Pricing.toCents(last30Days),
                comparisonCents: Pricing.toCents(previous30Days),
                comparisonLabel: DashboardRange.last30Days.comparisonLabel
            )
        ]
        next.modelBreakdowns = ModelBreakdownAggregator.aggregate(
            rows: api.csvRows,
            billingCycleWindow: billingCycleWindow,
            costMode: costMode,
            now: now,
            calendar: calendar
        )

        if let planUsage = api.usage?.planUsage {
            if let auto = planUsage.autoPercentUsed {
                next.autoPercentLeft = max(0, 100 - auto)
            }
            if let apiPercentUsed = planUsage.apiPercentUsed {
                next.apiPercentLeft = max(0, 100 - apiPercentUsed)
            }
        }

        if let endString = api.usage?.billingCycleEnd,
           let end = endString.asUnixMillisDate {
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

        if let name = api.plan?.planInfo?.planName,
           !name.isEmpty {
            next.plan = name
        }

        if let credits = api.credits,
           credits.hasCreditGrants == true {
            let total = Int(credits.totalCents ?? "0") ?? 0
            let used = Int(credits.usedCents ?? "0") ?? 0
            let stripeBonus = max(0, api.stripeBalanceCents)
            next.creditsLeft = max(0, total - used) + api.stripeBalanceCents
            next.creditsTotal = total + stripeBonus
        } else if api.stripeBalanceCents > 0 {
            next.creditsLeft = api.stripeBalanceCents
            next.creditsTotal = api.stripeBalanceCents
        }

        return next
    }
}
