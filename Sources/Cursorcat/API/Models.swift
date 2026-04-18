import Foundation

// Connect RPC response shapes. Fields may be absent; all optional.

struct PlanUsage: Decodable {
    var totalSpend: Double?        // cents
    var limit: Double?             // cents
    var remaining: Double?
    var autoPercentUsed: Double?
    var apiPercentUsed: Double?
    var totalPercentUsed: Double?
    var bonusSpend: Double?
}

struct SpendLimitUsage: Decodable {
    var individualLimit: Double?
    var individualRemaining: Double?
    var pooledLimit: Double?
    var pooledRemaining: Double?
    var limitType: String?
}

struct GetCurrentPeriodUsageResponse: Decodable {
    /// Unix ms string. Parse defensively.
    var billingCycleStart: String?
    var billingCycleEnd: String?
    var planUsage: PlanUsage?
    var spendLimitUsage: SpendLimitUsage?
    var enabled: Bool?
}

struct GetPlanInfoResponse: Decodable {
    struct PlanInfo: Decodable {
        var planName: String?
    }
    var planInfo: PlanInfo?
}

struct GetCreditGrantsBalanceResponse: Decodable {
    var hasCreditGrants: Bool?
    var totalCents: String?
    var usedCents: String?
}

struct StripeResponse: Decodable {
    /// Negative means credit on file.
    var customerBalance: Double?
}

extension String {
    /// Parse a Unix ms string sent as a string (RPC convention) into a Date.
    var asUnixMillisDate: Date? {
        guard let ms = Double(self) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
