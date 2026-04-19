import SwiftUI

struct DashboardContent: View {
    let snapshot: UsageSnapshot
    @ObservedObject var settings: UserSettings
    @ObservedObject var scheduler: PollScheduler
    let actions: DashboardActions

    @State private var selectedTab: DashboardTab = .overview
    @State private var selectedRange: DashboardRange = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DashboardHeaderView(
                selectedRange: $selectedRange,
                summary: snapshot.rangeSummaries[selectedRange]
            )

            DashboardTabSwitcher(selectedTab: $selectedTab)

            switch selectedTab {
            case .overview:
                OverviewTabContent(snapshot: snapshot)
            case .models:
                DashboardModelsView(rows: snapshot.modelBreakdowns[selectedRange] ?? [])
            case .settings:
                DashboardSettingsView(settings: settings)
            }

            Divider()
            DashboardFooter(plan: snapshot.plan, scheduler: scheduler, refresh: actions.refresh)
        }
    }
}

private struct OverviewTabContent: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = snapshot.lastError {
                ErrorBanner(message: error)
            }

            if hasQuotasSection {
                QuotasSection(snapshot: snapshot)
            }
            if let resetsAt = snapshot.billingCycleResetsAt {
                SubscriptionResetText(resetsAt: resetsAt)
            }
        }
    }

    private var hasQuotasSection: Bool {
        snapshot.autoPercentLeft != nil
            || snapshot.apiPercentLeft != nil
            || (snapshot.onDemandLimit ?? 0) > 0
            || (snapshot.creditsLeft ?? 0) > 0
    }
}

private struct QuotasSection: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pct = snapshot.autoPercentLeft {
                QuotaRow(label: "Auto",
                         fraction: pct / 100.0,
                         value: "\(Int(pct.rounded()))% left")
            }
            if let pct = snapshot.apiPercentLeft {
                QuotaRow(label: "API",
                         fraction: pct / 100.0,
                         value: "\(Int(pct.rounded()))% left")
            }
            if let limit = snapshot.onDemandLimit,
               limit > 0 {
                let remaining = snapshot.onDemandRemaining ?? 0
                let fraction = Double(remaining) / Double(limit)
                QuotaRow(
                    label: "On-demand",
                    fraction: fraction,
                    value: "\(Money.format(cents: remaining)) / \(Money.format(cents: limit)) left"
                )
            }
            if let credits = snapshot.creditsLeft,
               credits > 0,
               let total = snapshot.creditsTotal,
               total > 0 {
                QuotaRow(
                    label: "Credits",
                    fraction: Double(credits) / Double(total),
                    value: "\(Money.format(cents: credits)) / \(Money.format(cents: total)) left"
                )
            } else if let credits = snapshot.creditsLeft,
                      credits > 0 {
                StatRow(label: "Credits",
                        value: "\(Money.format(cents: credits)) left")
            }
        }
    }
}

private struct SubscriptionResetText: View {
    let resetsAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text("Your subscription resets in \(Countdown.format(resetsAt: resetsAt, now: context.date))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct DashboardFooter: View {
    let plan: String?
    @ObservedObject var scheduler: PollScheduler
    let refresh: () -> Void

    @State private var refreshSpins: Int = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .center) {
                if let plan {
                    PlanPill(plan: plan)
                }
                Spacer(minLength: 8)
                Text(refreshStatus(now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    refreshSpins += 1
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .symbolEffect(.rotate, value: refreshSpins)
                }
                .buttonStyle(.plain)
                .help("Refresh now")
                .accessibilityLabel("Refresh")
                .disabled(isRefreshDisabled(now: context.date))
            }
        }
    }

    private func isRefreshDisabled(now: Date) -> Bool {
        scheduler.isRefreshing
            || (scheduler.manualRefreshLockedUntil.map { now < $0 } ?? false)
    }

    private func refreshStatus(now: Date) -> String {
        if scheduler.isRefreshing {
            return "Updates now..."
        }
        guard let nextRefreshAt = scheduler.nextRefreshAt else {
            return "Updates now..."
        }

        let remaining = Int(nextRefreshAt.timeIntervalSince(now))
        if remaining <= 0 {
            return "Updates now..."
        }
        if remaining < 60 {
            return "Updates in \(remaining)s"
        }
        let minutes = remaining / 60
        return "Updates in \(minutes)m"
    }
}

private struct DashboardTabSwitcher: View {
    @Binding var selectedTab: DashboardTab

    var body: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(DashboardTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}
