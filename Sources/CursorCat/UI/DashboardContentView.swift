import AppKit
import SwiftUI

struct DashboardContent: View {
    let snapshot: UsageSnapshot
    @ObservedObject var settings: UserSettings
    @ObservedObject var scheduler: PollScheduler
    @ObservedObject var updater: AppUpdater
    @ObservedObject var presentation: DashboardPresentationState
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

            if updater.installState.isPending {
                UpdateInstallButton(state: updater.installState, install: actions.installUpdate)
            }

            Divider()
            DashboardFooter(
                plan: snapshot.plan,
                scheduler: scheduler,
                isVisible: presentation.isPopoverVisible,
                refresh: actions.refresh
            )
        }
        .background(
            DashboardKeyboardShortcuts(
                previousTab: cycleTab(by: -1),
                nextTab: cycleTab(by: 1),
                previousRange: cycleRange(by: -1),
                nextRange: cycleRange(by: 1)
            )
        )
    }

    private func cycleTab(by delta: Int) -> () -> Void {
        {
            let tabs = DashboardTab.allCases
            guard let currentIndex = tabs.firstIndex(of: selectedTab) else { return }
            let nextIndex = (currentIndex + delta + tabs.count) % tabs.count
            selectedTab = tabs[nextIndex]
        }
    }

    private func cycleRange(by delta: Int) -> () -> Void {
        {
            let ranges = DashboardRange.allCases
            guard let currentIndex = ranges.firstIndex(of: selectedRange) else { return }
            let nextIndex = (currentIndex + delta + ranges.count) % ranges.count
            selectedRange = ranges[nextIndex]
        }
    }
}

private struct UpdateInstallButton: View {
    let state: AppUpdater.InstallState
    let install: () -> Void

    var body: some View {
        Button(action: install) {
            HStack(spacing: 8) {
                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(state.buttonTitle)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(!state.isInstallEnabled)
        .accessibilityLabel(state.buttonTitle)
    }
}

private struct OverviewTabContent: View {
    let snapshot: UsageSnapshot
    @EnvironmentObject private var presentation: DashboardPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = snapshot.lastError {
                ErrorBanner(message: error)
            }

            if hasQuotasSection {
                QuotasSection(snapshot: snapshot)
            }
            if let resetsAt = snapshot.billingCycleResetsAt {
                SubscriptionResetText(
                    resetsAt: resetsAt,
                    isVisible: presentation.isPopoverVisible
                )
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
    let isVisible: Bool

    var body: some View {
        Group {
            if isVisible {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    bodyContent(now: context.date)
                }
            } else {
                bodyContent(now: Date())
            }
        }
    }

    @ViewBuilder
    private func bodyContent(now: Date) -> some View {
        Text("Your subscription resets in \(Countdown.format(resetsAt: resetsAt, now: now))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct DashboardFooter: View {
    let plan: String?
    @ObservedObject var scheduler: PollScheduler
    let isVisible: Bool
    let refresh: () -> Void

    @State private var refreshSpins: Int = 0

    var body: some View {
        Group {
            if isVisible {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    bodyContent(now: context.date)
                }
            } else {
                bodyContent(now: Date())
            }
        }
    }

    @ViewBuilder
    private func bodyContent(now: Date) -> some View {
        HStack(alignment: .center) {
            if let plan {
                PlanPill(plan: plan)
            }
            Spacer(minLength: 8)
            Text(refreshStatus(now: now))
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
            .disabled(isRefreshDisabled(now: now))
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
        SegmentedTabBar(
            tabs: DashboardTab.allCases,
            selection: $selectedTab,
            title: { $0.title }
        )
    }
}

private struct SegmentedTabBar<Tab: Hashable>: NSViewRepresentable {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: tabs.map(title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.segmentChanged(_:))
        )
        control.segmentStyle = .texturedSquare
        control.segmentDistribution = .fillEqually
        control.controlSize = .regular
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if nsView.segmentCount != tabs.count {
            nsView.segmentCount = tabs.count
        }
        for (index, tab) in tabs.enumerated() where nsView.label(forSegment: index) != title(tab) {
            nsView.setLabel(title(tab), forSegment: index)
        }
        if let index = tabs.firstIndex(of: selection), nsView.selectedSegment != index {
            nsView.selectedSegment = index
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SegmentedTabBar

        init(_ parent: SegmentedTabBar) {
            self.parent = parent
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard parent.tabs.indices.contains(index) else { return }
            let tab = parent.tabs[index]
            if parent.selection != tab {
                parent.selection = tab
            }
        }
    }
}

private struct DashboardKeyboardShortcuts: View {
    let previousTab: () -> Void
    let nextTab: () -> Void
    let previousRange: () -> Void
    let nextRange: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: previousTab) { EmptyView() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button(action: nextTab) { EmptyView() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button(action: previousRange) { EmptyView() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button(action: nextRange) { EmptyView() }
                .keyboardShortcut(.downArrow, modifiers: .command)
        }
        .buttonStyle(.plain)
        .labelsHidden()
        .frame(width: 0, height: 0)
        .clipped()
        .accessibilityHidden(true)
    }
}
