import SwiftUI

struct DashboardHeaderView: View {
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

                if let today,
                   let yesterday {
                    DeltaRow(today: today, yesterday: yesterday)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

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
