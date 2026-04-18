import Foundation

/// Integer-cents → display string helpers. All money inside the app is
/// stored as `Int` cents to avoid `Double` drift, and formatted to a
/// `String` only at render time.
enum Money {
    static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func format(cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    /// Compact dollar formatter that swaps in `k` / `M` / `B` for large
    /// amounts to keep rows narrow. Small amounts (< $1,000) fall back
    /// to the full two-decimal currency format so cents-level spend
    /// stays legible. Negative numbers preserve the sign.
    static func formatCompact(cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let absDollars = abs(dollars)
        let sign = dollars < 0 ? "-" : ""

        if absDollars < 1_000 {
            return format(cents: cents)
        }

        let (value, suffix): (Double, String)
        switch absDollars {
        case 1_000_000_000...:
            (value, suffix) = (absDollars / 1_000_000_000, "B")
        case 1_000_000...:
            (value, suffix) = (absDollars / 1_000_000, "M")
        default:
            (value, suffix) = (absDollars / 1_000, "k")
        }

        // One decimal when the number is under 100 of its unit (e.g.
        // $19.3k, $1.2M); zero decimals above that ($193k, $12M) so the
        // string stays tight. Trailing `.0` is stripped so whole-unit
        // values render as `$19k` rather than `$19.0k`.
        let formatted: String
        if value < 100 {
            let oneDecimal = String(format: "%.1f", value)
            formatted = oneDecimal.hasSuffix(".0")
                ? String(oneDecimal.dropLast(2))
                : oneDecimal
        } else {
            formatted = String(format: "%.0f", value)
        }
        return "\(sign)$\(formatted)\(suffix)"
    }
}

/// Human-readable countdown formatter. Renders a `Date` relative to
/// `now` as `30d 17h 12m`, dropping leading zero components. Anything
/// under 5 minutes collapses to `"Shortly"` so the view never flickers
/// at `0m` for sub-minute windows.
enum Countdown {
    static func format(resetsAt: Date, now: Date = Date()) -> String {
        let seconds = Int(resetsAt.timeIntervalSince(now))
        if seconds < 5 * 60 { return "Shortly" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 || days > 0 { parts.append("\(hours)h") }
        parts.append("\(minutes)m")
        return parts.joined(separator: " ")
    }
}
