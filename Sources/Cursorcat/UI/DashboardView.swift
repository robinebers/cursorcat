import SwiftUI

/// Actions the dashboard can invoke. `StatusItemController` wires real
/// implementations; keeping the view agnostic of AppKit lets it stay a
/// plain SwiftUI `View`.
struct DashboardActions {
    var refresh: () -> Void
    var openCursor: () -> Void
    var interact: (CatAnimation) -> Void
    var quit: () -> Void
}

/// The popover contents: header + SPEND + QUOTAS + footer, or a
/// logged-out card when no tokens are present. Branches on the live
/// `UsageStore` snapshot.
struct DashboardView: View {
    /// Fixed popover body width. Shared with `StatusItemController` so
    /// the AppKit-side `NSPopover.contentSize` can't drift from the
    /// SwiftUI `.frame(width:)` — if they disagree, the popover lays out
    /// around the larger size and the arrow ends up visually off-center
    /// even when AppKit's geometry is technically correct.
    static let width: CGFloat = 280

    @ObservedObject var store: UsageStore
    let actions: DashboardActions

    var body: some View {
        Group {
            if !store.snapshot.isLoggedIn {
                LoggedOutCard(actions: actions)
            } else if store.snapshot.lastUpdated == nil && store.snapshot.todaySpend == nil {
                LoadingCard()
            } else {
                DashboardContent(snapshot: store.snapshot, actions: actions)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.width)
    }
}

// MARK: - Loaded dashboard

private struct DashboardContent: View {
    let snapshot: UsageSnapshot
    let actions: DashboardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(
                today: snapshot.todaySpend,
                yesterday: snapshot.yesterdaySpend
            )

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

            Footer(plan: snapshot.plan, refresh: actions.refresh)
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
            || (snapshot.requestsUsed != nil && snapshot.requestsLimit != nil)
            || (snapshot.onDemandLimit ?? 0) > 0
            || (snapshot.creditsLeft ?? 0) > 0
    }
}

// MARK: - Header

private struct Header: View {
    let today: Int?
    let yesterday: Int?

    var body: some View {
        VStack(spacing: 2) {
            Text("Today's spend")
                .font(.caption2)
                .fontWeight(.medium)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                if let today {
                    Text(Money.format(cents: today))
                        .font(.system(size: 34,
                                      weight: .semibold,
                                      design: .rounded))
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 8)
                }

                if let today, let yesterday {
                    DeltaRow(today: today, yesterday: yesterday)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Compact "▲ $X.XX vs. yesterday" row beneath the hero number. Uses
/// a single semantic color on the delta glyph + amount (red when spend
/// is up, green when down); the "vs. yesterday" suffix stays neutral.
/// Hidden when today and yesterday match exactly.
private struct DeltaRow: View {
    let today: Int
    let yesterday: Int

    var body: some View {
        let diff = today - yesterday
        if diff == 0 {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: "triangle.fill")
                    .rotationEffect(.degrees(diff > 0 ? 0 : 180))
                    .font(.system(size: 8))
                    .foregroundStyle(tint)
                Text(Money.formatCompact(cents: abs(diff)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text("vs. yesterday")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tint: Color {
        today > yesterday ? .red : .green
    }
}

// MARK: - Spend

private struct SpendSection: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cents = snapshot.yesterdaySpend {
                StatRow(label: "Yesterday",
                        value: Money.formatCompact(cents: cents))
            }
            if let cents = snapshot.billingCycleSpend {
                StatRow(label: "This billing cycle",
                        value: Money.formatCompact(cents: cents))
            }
            if let resetsAt = snapshot.billingCycleResetsAt {
                StatRow(label: "Resets in",
                        value: Countdown.format(resetsAt: resetsAt))
            }
        }
    }
}

// MARK: - Quotas

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
            if let used = snapshot.requestsUsed,
               let limit = snapshot.requestsLimit,
               limit > 0 {
                let fraction = Double(max(0, limit - used)) / Double(limit)
                QuotaRow(label: "Requests",
                         fraction: fraction,
                         value: "\(Int((fraction * 100).rounded()))% left")
            }
            if let limit = snapshot.onDemandLimit, limit > 0 {
                let remaining = snapshot.onDemandRemaining ?? 0
                let fraction = Double(remaining) / Double(limit)
                QuotaRow(
                    label: "On-demand",
                    fraction: fraction,
                    value: "\(Money.formatCompact(cents: remaining)) / \(Money.formatCompact(cents: limit)) left"
                )
            }
            if let credits = snapshot.creditsLeft, credits > 0,
               let total = snapshot.creditsTotal, total > 0 {
                QuotaRow(
                    label: "Credits",
                    fraction: Double(credits) / Double(total),
                    value: "\(Money.formatCompact(cents: credits)) / \(Money.formatCompact(cents: total)) left"
                )
            } else if let credits = snapshot.creditsLeft, credits > 0 {
                StatRow(label: "Credits",
                        value: "\(Money.formatCompact(cents: credits)) left")
            }
        }
    }
}

// MARK: - Footer

private struct Footer: View {
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

// MARK: - Empty states

private struct LoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today")
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LoggedOutCard: View {
    let actions: DashboardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not logged in")
                .font(.headline)
            Text("Log in to Cursor to see your spend, quotas, and billing cycle.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Cursor to log in", action: actions.openCursor)
                    .buttonStyle(.glassProminent)
                Spacer()
                Button("Quit", action: actions.quit)
                    .buttonStyle(.glass)
            }
        }
    }
}
