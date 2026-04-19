import Foundation

enum UsageSnapshotProjector {
    static func project(
        api: APISnapshot,
        previous: UsageSnapshot,
        costMode: CostMode,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        var next = previous
        next.isLoggedIn = true
        next.lastError = nil
        next.lastUpdated = now

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let cycleStart = api.usage?.billingCycleStart?.asUnixMillisDate ?? api.csvStart

        var today = 0.0
        var yesterday = 0.0
        var cycle = 0.0

        for row in api.csvRows {
            let cost = row.costDollars(for: costMode)
            if row.date >= startOfToday {
                today += cost
            }
            if row.date >= startOfYesterday, row.date < startOfToday {
                yesterday += cost
            }
            if row.date >= cycleStart {
                cycle += cost
            }
        }

        next.todaySpend = Pricing.toCents(today)
        next.yesterdaySpend = Pricing.toCents(yesterday)
        next.billingCycleSpend = Pricing.toCents(cycle)
        next.modelBreakdowns = ModelBreakdownAggregator.aggregate(
            rows: api.csvRows,
            cycleStart: cycleStart,
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
        } else {
            next.creditsLeft = nil
            next.creditsTotal = nil
        }

        return next
    }
}
