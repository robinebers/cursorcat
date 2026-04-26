import Foundation

/// Per-model token pricing entry. Rates are USD per million tokens.
struct PricingEntry {
    let displayName: String
    let provider: String
    let familyID: String
    let familyDisplayName: String
    let inputPerMillion: Double
    let cacheWritePerMillion: Double
    let cacheReadPerMillion: Double
    let outputPerMillion: Double
    let applyMaxModeUplift: Bool
    let longContextInputThreshold: Int?
    let longContextInputMultiplier: Double?
    let longContextOutputMultiplier: Double?
    let longContextCachedInputMultiplier: Double?

    init(manifestEntry: ModelManifestPricingEntry) {
        self.displayName = manifestEntry.displayName
        self.provider = manifestEntry.provider
        self.familyID = manifestEntry.familyID
        self.familyDisplayName = manifestEntry.familyDisplayName
        self.inputPerMillion = manifestEntry.inputPerMillion
        self.cacheWritePerMillion = manifestEntry.cacheWritePerMillion
        self.cacheReadPerMillion = manifestEntry.cacheReadPerMillion
        self.outputPerMillion = manifestEntry.outputPerMillion
        self.applyMaxModeUplift = manifestEntry.applyMaxModeUplift
        self.longContextInputThreshold = manifestEntry.longContextInputThreshold
        self.longContextInputMultiplier = manifestEntry.longContextInputMultiplier
        self.longContextOutputMultiplier = manifestEntry.longContextOutputMultiplier
        self.longContextCachedInputMultiplier = manifestEntry.longContextCachedInputMultiplier
    }
}

/// Token counts for a single usage event.
struct TokenUsage {
    let inputCacheWrite: Int
    let inputNoCacheWrite: Int
    let cacheRead: Int
    let output: Int
}

enum Pricing {
    struct ModelFamily {
        let id: String
        let displayName: String
    }

    private static let manifestSource: ModelManifestSource = BundledModelManifestSource()
    private static let modelManifest: ModelManifest = {
        do {
            return try manifestSource.loadManifest()
        } catch {
            Log.app.error("failed to load model manifest: \(error.localizedDescription)")
            return .empty
        }
    }()

    static let manifest: [String: PricingEntry] = modelManifest.pricing.mapValues(PricingEntry.init(manifestEntry:))

    /// Regex → canonical name. Order matters: first match wins.
    /// Ported from cstats alias_rules. Compiled once lazily.
    private struct AliasRule {
        let regex: NSRegularExpression
        let canonical: String
    }

    private static let aliasRules: [AliasRule] = {
        modelManifest.aliasRules.compactMap { rule in
            (try? NSRegularExpression(pattern: rule.pattern))
                .map { AliasRule(regex: $0, canonical: rule.canonical) }
        }
    }()

    private static func resolve(model: String) -> (canonical: String, entry: PricingEntry)? {
        guard let canonical = canonicalModel(for: model),
              let entry = manifest[canonical] else {
            return nil
        }
        return (canonical, entry)
    }

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
        resolve(model: model)?.entry
    }

    static func family(for model: String) -> ModelFamily? {
        guard let entry = resolve(model: model)?.entry else { return nil }
        return ModelFamily(id: entry.familyID, displayName: entry.familyDisplayName)
    }

    /// Estimate the USD cost (dollars, not cents) for one dashboard CSV row.
    ///
    /// Cursor's CSV rows are aggregates, not individual model requests: a single
    /// row can contain more tokens than a model's context window. Because
    /// long-context pricing thresholds apply per request, not to an aggregate
    /// row total, we cannot infer those multipliers from the CSV safely.
    /// Current Cursor individual plans bill Max Mode at the model API rate.
    /// Legacy request-based plans may have had a surcharge, but the CSV does not
    /// expose enough plan context to apply one reliably.
    /// Returns 0 for unpriced/unknown models.
    static func estimatedCostDollars(model: String, maxMode _: Bool, tokens: TokenUsage) -> Double {
        guard let entry = pricingEntry(for: model) else { return 0 }

        let cost =
            Double(tokens.inputCacheWrite) / 1_000_000 * entry.cacheWritePerMillion +
            Double(tokens.inputNoCacheWrite) / 1_000_000 * entry.inputPerMillion +
            Double(tokens.cacheRead) / 1_000_000 * entry.cacheReadPerMillion +
            Double(tokens.output) / 1_000_000 * entry.outputPerMillion

        return cost
    }

    /// Convert a dollar amount to integer cents, rounded to nearest. Preserves
    /// sign. Intended for summing many rows without double-drift.
    static func toCents(_ dollars: Double) -> Int {
        Int((dollars * 100).rounded())
    }
}
