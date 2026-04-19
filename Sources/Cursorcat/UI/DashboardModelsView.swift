import SwiftUI

struct DashboardModelsView: View {
    @Binding var selectedRange: ModelBreakdownRange
    let rows: [ModelBreakdownRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rangePicker
            columnHeader

            if rows.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        ModelBreakdownListRow(row: row)
                    }
                }
            }
        }
    }

    private var rangePicker: some View {
        Menu {
            ForEach(ModelBreakdownRange.allCases) { range in
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

    private var columnHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Model")
                .font(.caption2)
                .fontWeight(.medium)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text("Cost")
                .font(.caption2)
                .fontWeight(.medium)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }

    private var emptyState: some View {
        Text("No model usage for this range.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

private struct ModelBreakdownListRow: View {
    let row: ModelBreakdownRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.displayName)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Text(costLabel)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.displayName), \(costAccessibilityLabel)")
    }

    private var costLabel: String {
        row.isUnpriced ? "—" : Money.formatCompact(cents: row.totalCostCents)
    }

    private var costAccessibilityLabel: String {
        row.isUnpriced ? "unpriced" : Money.format(cents: row.totalCostCents)
    }
}
