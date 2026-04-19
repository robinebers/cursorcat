import SwiftUI

struct DashboardModelsView: View {
    let rows: [ModelBreakdownRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private var columnHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("Model")
                .font(.caption2)
                .fontWeight(.medium)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Cost")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Text("Tokens")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
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
        HStack(alignment: .top, spacing: 10) {
            Text(row.displayName)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(costLabel)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text(tokenLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .help(tooltipText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.displayName), \(costAccessibilityLabel), \(tokenAccessibilityLabel)")
    }

    private var costLabel: String {
        row.isUnpriced ? "—" : Money.format(cents: row.totalCostCents)
    }

    private var costAccessibilityLabel: String {
        row.isUnpriced ? "unpriced" : Money.format(cents: row.totalCostCents)
    }

    private var tokenLabel: String {
        TokenCountFormatter.format(row.totalTokens)
    }

    private var tokenAccessibilityLabel: String {
        "\(row.totalTokens) tokens"
    }

    private var tooltipText: String {
        row.variants
            .map { variant in
                "\(variant.model) - \(variantCostLabel(for: variant))"
            }
            .joined(separator: "\n")
    }

    private func variantCostLabel(for variant: ModelBreakdownRow.Variant) -> String {
        variant.isUnpriced ? "—" : Money.format(cents: variant.totalCostCents)
    }
}
