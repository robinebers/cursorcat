import SwiftUI

struct DashboardContent: View {
    let snapshot: UsageSnapshot
    let actions: DashboardActions

    @State private var selectedTab: DashboardTab = .overview
    @State private var selectedRange: ModelBreakdownRange = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DashboardHeaderView(
                today: snapshot.todaySpend,
                yesterday: snapshot.yesterdaySpend
            )

            DashboardTabSwitcher(selectedTab: $selectedTab)

            switch selectedTab {
            case .overview:
                OverviewTabContent(snapshot: snapshot)
            case .models:
                DashboardModelsView(
                    selectedRange: $selectedRange,
                    rows: snapshot.modelBreakdowns[selectedRange] ?? []
                )
            }

            Divider()
            DashboardFooter(plan: snapshot.plan, refresh: actions.refresh)
        }
    }

    private var hasSpendSection: Bool {
        snapshot.yesterdaySpend != nil
            || snapshot.billingCycleSpend != nil
            || snapshot.billingCycleResetsAt != nil
    }

    private var hasQuotasSection: Bool {
        snapshot.autoPercentLeft != nil
            || snapshot.apiPercentLeft != nil
            || (snapshot.onDemandLimit ?? 0) > 0
            || (snapshot.creditsLeft ?? 0) > 0
    }
}

private struct OverviewTabContent: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = snapshot.lastError {
                ErrorBanner(message: error)
            }

            if hasSpendSection {
                SpendSection(snapshot: snapshot)
            }

            if hasSpendSection && hasQuotasSection {
                Divider()
            }

            if hasQuotasSection {
                QuotasSection(snapshot: snapshot)
            }
        }
    }

    private var hasSpendSection: Bool {
        snapshot.yesterdaySpend != nil
            || snapshot.billingCycleSpend != nil
            || snapshot.billingCycleResetsAt != nil
    }

    private var hasQuotasSection: Bool {
        snapshot.autoPercentLeft != nil
            || snapshot.apiPercentLeft != nil
            || (snapshot.onDemandLimit ?? 0) > 0
            || (snapshot.creditsLeft ?? 0) > 0
    }
}

private struct SpendSection: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cents = snapshot.yesterdaySpend {
                StatRow(label: "Yesterday",
                        value: Money.formatCompact(cents: cents))
            }
            if let cents = snapshot.billingCycleSpend {
                StatRow(label: "Billing cycle",
                        value: Money.formatCompact(cents: cents))
            }
            if let resetsAt = snapshot.billingCycleResetsAt {
                StatRow(label: "Resets in",
                        value: Countdown.format(resetsAt: resetsAt))
            }
        }
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
                    value: "\(Money.formatCompact(cents: remaining)) / \(Money.formatCompact(cents: limit)) left"
                )
            }
            if let credits = snapshot.creditsLeft,
               credits > 0,
               let total = snapshot.creditsTotal,
               total > 0 {
                QuotaRow(
                    label: "Credits",
                    fraction: Double(credits) / Double(total),
                    value: "\(Money.formatCompact(cents: credits)) / \(Money.formatCompact(cents: total)) left"
                )
            } else if let credits = snapshot.creditsLeft,
                      credits > 0 {
                StatRow(label: "Credits",
                        value: "\(Money.formatCompact(cents: credits)) left")
            }
        }
    }
}

private struct DashboardFooter: View {
    let plan: String?
    let refresh: () -> Void

    @State private var refreshSpins: Int = 0

    var body: some View {
        HStack(alignment: .center) {
            if let plan {
                PlanPill(plan: plan)
            }
            Spacer(minLength: 8)
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
        }
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
