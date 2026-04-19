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

enum TokenCountFormatter {
    static func format(_ tokens: Int) -> String {
        let value = Double(tokens)
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""

        let scaled: Double
        let suffix: String
        switch absValue {
        case 1_000_000_000...:
            scaled = absValue / 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            scaled = absValue / 1_000_000
            suffix = "M"
        case 1_000...:
            scaled = absValue / 1_000
            suffix = "K"
        default:
            return "\(tokens) tokens"
        }

        let formatted = String(format: scaled >= 100 ? "%.0f" : "%.1f", scaled)
        let cleaned = formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
        return "\(sign)\(cleaned)\(suffix) tokens"
    }
}
