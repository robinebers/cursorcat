import SwiftUI

/// Small uppercase section heading above each group of rows. Reads as
/// metadata, not a title — `.caption2` + tracked + secondary foreground.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.medium)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Standard money/value row: sans-serif label on the left, monospaced
/// value on the right, optional secondary subtitle beneath the value
/// (used for `resets in 12d`). Both columns are `.callout` so the
/// vertical rhythm stays consistent across Spend and Quotas rows.
struct StatRow: View {
    let label: String
    let value: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .fontWeight(.semibold)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.callout)
                    .monospacedDigit()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Quota row: sans-serif label on the top-left, monospaced value on
/// the top-right, full-width monochrome progress bar underneath.
/// Label/value typography matches `StatRow` so the Spend and Quotas
/// sections feel like one type ramp.
struct QuotaRow: View {
    let label: String
    /// Fraction of the bar that is FILLED. 0 = empty bar, 1 = full bar.
    /// Bars are filled to represent what is left (e.g., 72% left →
    /// `fraction: 0.72`).
    let fraction: Double
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer(minLength: 12)
                Text(value)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            MonoBar(fraction: fraction)
                .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }
}

/// Capsule progress bar filled in the user's system accent color. One
/// color for all bars — no traffic-light semantics (no red for low,
/// green for high). This matches the macOS convention used by Finder
/// download bars, Mail progress, and system gauges.
struct MonoBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * clamped)
            }
        }
    }

    private var clamped: CGFloat {
        CGFloat(max(0, min(1, fraction)))
    }
}

/// Non-interactive plan badge. Inverted for maximum contrast — fill
/// uses `.primary` (black in light mode, near-white in dark mode) and
/// the text uses the window background color, so the pill always reads
/// as the opposite of whatever material sits behind it.
struct PlanPill: View {
    let plan: String

    var body: some View {
        Text(plan)
            .font(.caption2)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary)
            )
            .accessibilityLabel("Plan: \(plan)")
    }
}

/// Compact error banner surfaced above the dashboard rows. Monochrome;
/// the triangle glyph carries the semantic — no red tint.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
        )
    }
}
