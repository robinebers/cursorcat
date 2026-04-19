import SwiftUI

struct DashboardHeaderView: View {
    @Binding var selectedRange: DashboardRange
    let summary: DashboardRangeSummary?

    var body: some View {
        VStack(spacing: 10) {
            rangePicker

            VStack(spacing: 0) {
                if let summary {
                    Text(Money.format(cents: summary.totalCents))
                        .font(.system(size: 34,
                                      weight: .semibold,
                                      design: .rounded))
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 8)
                }

                if let summary {
                    DeltaRow(summary: summary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rangePicker: some View {
        Menu {
            ForEach(DashboardRange.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.title)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedRange.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

private struct DeltaRow: View {
    let summary: DashboardRangeSummary

    var body: some View {
        let diff = summary.totalCents - summary.comparisonCents
        if diff == 0 {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: "triangle.fill")
                    .rotationEffect(.degrees(diff > 0 ? 0 : 180))
                    .font(.system(size: 8))
                    .foregroundStyle(tint)
                Text(Money.format(cents: abs(diff)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(summary.comparisonLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tint: Color {
        summary.totalCents > summary.comparisonCents ? .red : .green
    }
}
