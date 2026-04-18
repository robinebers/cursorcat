import Foundation

/// Per-model token pricing entry. Rates are USD per million tokens.
struct PricingEntry {
    let displayName: String
    let provider: String
    let inputPerMillion: Double
    let cacheWritePerMillion: Double
    let cacheReadPerMillion: Double
    let outputPerMillion: Double
    let applyMaxModeUplift: Bool
    let longContextInputThreshold: Int?
    let longContextInputMultiplier: Double?
    let longContextOutputMultiplier: Double?
    let longContextCachedInputMultiplier: Double?

    init(displayName: String,
         provider: String,
         input: Double,
         cacheWrite: Double,
         cacheRead: Double,
         output: Double,
         applyMaxModeUplift: Bool,
         longContextInputThreshold: Int? = nil,
         longContextInputMultiplier: Double? = nil,
         longContextOutputMultiplier: Double? = nil,
         longContextCachedInputMultiplier: Double? = nil) {
        self.displayName = displayName
        self.provider = provider
        self.inputPerMillion = input
        self.cacheWritePerMillion = cacheWrite
        self.cacheReadPerMillion = cacheRead
        self.outputPerMillion = output
        self.applyMaxModeUplift = applyMaxModeUplift
        self.longContextInputThreshold = longContextInputThreshold
        self.longContextInputMultiplier = longContextInputMultiplier
        self.longContextOutputMultiplier = longContextOutputMultiplier
        self.longContextCachedInputMultiplier = longContextCachedInputMultiplier
    }
}

/// Token counts for a single usage event.
struct TokenUsage {
    let inputCacheWrite: Int
    let inputNoCacheWrite: Int
    let cacheRead: Int
    let output: Int
}

/// Source of truth for per-model pricing and canonical model name resolution.
/// Ported from cstats/src/pricing-manifest.ts (retrieved 2026-03-17).
enum Pricing {
    static let maxModeUplift: Double = 1.2

    /// Canonical model name → pricing entry.
    static let manifest: [String: PricingEntry] = [
        "auto": PricingEntry(
            displayName: "Auto", provider: "cursor",
            input: 1.25, cacheWrite: 1.25, cacheRead: 0.25, output: 6.0,
            applyMaxModeUplift: false),
        "composer-1": PricingEntry(
            displayName: "Composer 1", provider: "cursor",
            input: 1.25, cacheWrite: 1.25, cacheRead: 0.125, output: 10.0,
            applyMaxModeUplift: false),
        "composer-1.5": PricingEntry(
            displayName: "Composer 1.5", provider: "cursor",
            input: 3.5, cacheWrite: 3.5, cacheRead: 0.35, output: 17.5,
            applyMaxModeUplift: false),
        "composer-2": PricingEntry(
            displayName: "Composer 2", provider: "cursor",
            input: 0.5, cacheWrite: 0.5, cacheRead: 0.2, output: 2.5,
            applyMaxModeUplift: false),
        "composer-2-fast": PricingEntry(
            displayName: "Composer 2 Fast", provider: "cursor",
            input: 1.5, cacheWrite: 1.5, cacheRead: 0.6, output: 7.5,
            applyMaxModeUplift: false),
        "claude-4.5-haiku": PricingEntry(
            displayName: "Claude 4.5 Haiku", provider: "anthropic",
            input: 1.0, cacheWrite: 1.25, cacheRead: 0.1, output: 5.0,
            applyMaxModeUplift: true),
        "claude-4.5-opus": PricingEntry(
            displayName: "Claude 4.5 Opus", provider: "anthropic",
            input: 5.0, cacheWrite: 6.25, cacheRead: 0.5, output: 25.0,
            applyMaxModeUplift: true),
        "claude-4-sonnet": PricingEntry(
            displayName: "Claude 4 Sonnet", provider: "anthropic",
            input: 3.0, cacheWrite: 3.75, cacheRead: 0.3, output: 15.0,
            applyMaxModeUplift: true),
        "claude-4.5-sonnet": PricingEntry(
            displayName: "Claude 4.5 Sonnet", provider: "anthropic",
            input: 3.0, cacheWrite: 3.75, cacheRead: 0.3, output: 15.0,
            applyMaxModeUplift: true,
            longContextInputThreshold: 200_000,
            longContextInputMultiplier: 2.0,
            longContextOutputMultiplier: 1.5,
            longContextCachedInputMultiplier: 2.0),
        "claude-4.6-opus": PricingEntry(
            displayName: "Claude 4.6 Opus", provider: "anthropic",
            input: 5.0, cacheWrite: 6.25, cacheRead: 0.5, output: 25.0,
            applyMaxModeUplift: false),
        "claude-4.6-opus-fast": PricingEntry(
            displayName: "Claude 4.6 Opus (Fast)", provider: "anthropic",
            input: 30.0, cacheWrite: 37.5, cacheRead: 3.0, output: 150.0,
            applyMaxModeUplift: false),
        "claude-4.7-opus": PricingEntry(
            displayName: "Claude 4.7 Opus", provider: "anthropic",
            input: 5.0, cacheWrite: 6.25, cacheRead: 0.5, output: 25.0,
            applyMaxModeUplift: false),
        "claude-4.7-opus-fast": PricingEntry(
            displayName: "Claude 4.7 Opus (Fast)", provider: "anthropic",
            input: 30.0, cacheWrite: 37.5, cacheRead: 3.0, output: 150.0,
            applyMaxModeUplift: false),
        "gemini-3-flash": PricingEntry(
            displayName: "Gemini 3 Flash", provider: "google",
            input: 0.5, cacheWrite: 0.5, cacheRead: 0.05, output: 3.0,
            applyMaxModeUplift: true),
        "gemini-3-pro": PricingEntry(
            displayName: "Gemini 3 Pro", provider: "google",
            input: 2.0, cacheWrite: 2.0, cacheRead: 0.2, output: 12.0,
            applyMaxModeUplift: true),
        "gemini-3.1-pro": PricingEntry(
            displayName: "Gemini 3.1 Pro", provider: "google",
            input: 2.0, cacheWrite: 2.0, cacheRead: 0.2, output: 12.0,
            applyMaxModeUplift: true),
        "gemini-3.1-pro-preview": PricingEntry(
            displayName: "Gemini 3.1 Pro Preview", provider: "google",
            input: 2.0, cacheWrite: 2.0, cacheRead: 0.2, output: 12.0,
            applyMaxModeUplift: true),
        "gpt-5-mini": PricingEntry(
            displayName: "GPT-5 Mini", provider: "openai",
            input: 0.25, cacheWrite: 0.25, cacheRead: 0.025, output: 2.0,
            applyMaxModeUplift: true),
        "grok-4-20-thinking": PricingEntry(
            displayName: "Grok 4.20 (Thinking)", provider: "xai",
            input: 2.0, cacheWrite: 2.0, cacheRead: 0.5, output: 6.0,
            applyMaxModeUplift: true),
        "gpt-5.1-codex": PricingEntry(
            displayName: "GPT-5.1 Codex", provider: "openai",
            input: 1.25, cacheWrite: 1.25, cacheRead: 0.125, output: 10.0,
            applyMaxModeUplift: true),
        "gpt-5.2-codex": PricingEntry(
            displayName: "GPT-5.2 Codex", provider: "openai",
            input: 1.75, cacheWrite: 1.75, cacheRead: 0.175, output: 14.0,
            applyMaxModeUplift: true),
        "gpt-5.3-codex": PricingEntry(
            displayName: "GPT-5.3 Codex", provider: "openai",
            input: 1.75, cacheWrite: 1.75, cacheRead: 0.175, output: 14.0,
            applyMaxModeUplift: true),
        "gpt-5.3-codex-spark": PricingEntry(
            displayName: "GPT-5.3 Codex Spark", provider: "openai",
            input: 1.75, cacheWrite: 1.75, cacheRead: 0.175, output: 14.0,
            applyMaxModeUplift: true),
        "gpt-5.4": PricingEntry(
            displayName: "GPT-5.4", provider: "openai",
            input: 2.5, cacheWrite: 2.5, cacheRead: 0.25, output: 15.0,
            applyMaxModeUplift: true,
            longContextInputThreshold: 272_000,
            longContextInputMultiplier: 2.0,
            longContextOutputMultiplier: 1.5,
            longContextCachedInputMultiplier: 2.0),
        "gpt-5.4-fast": PricingEntry(
            displayName: "GPT-5.4 Fast", provider: "openai",
            input: 5.0, cacheWrite: 5.0, cacheRead: 0.5, output: 30.0,
            applyMaxModeUplift: true),
        "kimi-k2.5": PricingEntry(
            displayName: "Kimi K2.5", provider: "moonshot",
            input: 0.6, cacheWrite: 0.6, cacheRead: 0.1, output: 3.0,
            applyMaxModeUplift: true),
    ]

    /// Regex → canonical name. Order matters: first match wins.
    /// Ported from cstats alias_rules. Compiled once lazily.
    private struct AliasRule {
        let regex: NSRegularExpression
        let canonical: String
    }

    private static let aliasRules: [AliasRule] = {
        let raw: [(String, String)] = [
            ("^agent_review$", "gpt-5.4"),
            ("^auto$", "auto"),
            ("^composer-1$", "composer-1"),
            ("^composer-1\\.5$", "composer-1.5"),
            ("^composer-2$", "composer-2"),
            ("^composer-2-fast$", "composer-2-fast"),
            ("^claude-4\\.5-haiku(?:-thinking)?$", "claude-4.5-haiku"),
            ("^claude-4\\.5-opus-(?:low|medium|high)(?:-thinking)?$", "claude-4.5-opus"),
            ("^claude-4-sonnet$", "claude-4-sonnet"),
            ("^claude-4\\.5-sonnet(?:-thinking)?$", "claude-4.5-sonnet"),
            // Fast must be matched BEFORE the non-fast variant because the non-fast
            // regex also matches strings ending in "-fast" (the suffix isn't anchored).
            ("^claude-4\\.6-opus-(?:low|medium|high|max)(?:-thinking)?-fast$", "claude-4.6-opus-fast"),
            ("^claude-4\\.6-opus-(?:low|medium|high|max)(?:-thinking)?$", "claude-4.6-opus"),
            ("^claude-opus-4-7(?:-thinking)?(?:-(?:low|medium|high|max))?-fast$", "claude-4.7-opus-fast"),
            ("^claude-opus-4-7(?:-thinking)?(?:-(?:low|medium|high|max))?$", "claude-4.7-opus"),
            ("^gemini-3-flash(?:-preview)?$", "gemini-3-flash"),
            ("^gemini-3-pro-preview$", "gemini-3-pro"),
            ("^gemini-3\\.1-pro$", "gemini-3.1-pro"),
            ("^gemini-3\\.1-pro-preview$", "gemini-3.1-pro-preview"),
            ("^gpt-5-mini$", "gpt-5-mini"),
            ("^grok-4-20-thinking$", "grok-4-20-thinking"),
            ("^gpt-5\\.1-codex(?:-max)?(?:-(?:high|xhigh))?(?:-fast)?$", "gpt-5.1-codex"),
            ("^gpt-5\\.2(?:-codex)?(?:-(?:high|xhigh))?(?:-fast)?$", "gpt-5.2-codex"),
            ("^gpt-5\\.3-codex-spark-preview-xhigh$", "gpt-5.3-codex-spark"),
            ("^gpt-5\\.3-codex(?:-(?:high|xhigh))?-fast$", "gpt-5.3-codex"),
            ("^gpt-5\\.3-codex(?:-(?:high|xhigh))?$", "gpt-5.3-codex"),
            ("^gpt-5\\.4-(?:high|medium|xhigh)-fast$", "gpt-5.4-fast"),
            ("^gpt-5\\.4-(?:high|medium|xhigh)$", "gpt-5.4"),
            ("^kimi-k2\\.5$", "kimi-k2.5"),
            ("^kimi-k2p5$", "kimi-k2.5"),
            ("^[Pp]remium \\((?:[Gg][Pp][Tt]-5\\.3-[Cc]odex|[Cc]odex 5\\.3)\\)$", "gpt-5.3-codex"),
        ]
        return raw.compactMap { (pattern, canonical) in
            (try? NSRegularExpression(pattern: pattern))
                .map { AliasRule(regex: $0, canonical: canonical) }
        }
    }()

    static func canonicalModel(for model: String) -> String? {
        let range = NSRange(model.startIndex..<model.endIndex, in: model)
        for rule in aliasRules {
            if rule.regex.firstMatch(in: model, range: range) != nil {
                return rule.canonical
            }
        }
        return nil
    }

    static func pricingEntry(for model: String) -> PricingEntry? {
        guard let canonical = canonicalModel(for: model) else { return nil }
        return manifest[canonical]
    }

    /// Estimate the USD cost (dollars, not cents) for one usage row, applying
    /// long-context multipliers and MAX_MODE uplift where applicable.
    /// Returns 0 for unpriced/unknown models.
    static func estimatedCostDollars(model: String, maxMode: Bool, tokens: TokenUsage) -> Double {
        guard let entry = pricingEntry(for: model) else { return 0 }

        let totalInput = tokens.inputCacheWrite + tokens.inputNoCacheWrite + tokens.cacheRead
        var inputMult = 1.0
        var outputMult = 1.0
        var cachedInputMult = 1.0
        if let threshold = entry.longContextInputThreshold, totalInput > threshold {
            inputMult = entry.longContextInputMultiplier ?? 1.0
            outputMult = entry.longContextOutputMultiplier ?? 1.0
            cachedInputMult = entry.longContextCachedInputMultiplier ?? inputMult
        }

        var cost =
            Double(tokens.inputCacheWrite) / 1_000_000 * entry.cacheWritePerMillion * inputMult +
            Double(tokens.inputNoCacheWrite) / 1_000_000 * entry.inputPerMillion * inputMult +
            Double(tokens.cacheRead) / 1_000_000 * entry.cacheReadPerMillion * cachedInputMult +
            Double(tokens.output) / 1_000_000 * entry.outputPerMillion * outputMult

        if maxMode && entry.applyMaxModeUplift {
            cost *= maxModeUplift
        }
        return cost
    }

    /// Convert a dollar amount to integer cents, rounded to nearest. Preserves
    /// sign. Intended for summing many rows without double-drift.
    static func toCents(_ dollars: Double) -> Int {
        Int((dollars * 100).rounded())
    }
}
