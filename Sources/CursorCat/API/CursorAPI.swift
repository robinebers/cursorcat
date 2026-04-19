import Foundation

/// Full data snapshot from one successful poll cycle.
struct APISnapshot {
    var usage: GetCurrentPeriodUsageResponse?
    var plan: GetPlanInfoResponse?
    var credits: GetCreditGrantsBalanceResponse?
    var csvRows: [UsageCSVRow]
    var stripeBalanceCents: Int
    /// The CSV window actually fetched. Useful for menu footer / debugging.
    var csvStart: Date
    var csvEnd: Date

}

/// Orchestrates one fan-out poll: RPC trio + CSV + Stripe.
/// Retries once on auth failure after refreshing the access token.
actor CursorAPI {
    private let auth: CursorAuth
    private let rpc: DashboardRPC
    private let csv: UsageCSVClient
    private let stripe: StripeAPI

    init(auth: CursorAuth,
         rpc: DashboardRPC = DashboardRPC(),
         csv: UsageCSVClient = UsageCSVClient(),
         stripe: StripeAPI = StripeAPI()) {
        self.auth = auth
        self.rpc = rpc
        self.csv = csv
        self.stripe = stripe
    }

    func collectRawDump() async -> String {
        let rpcRaw = await rpc.snapshotRaw()
        let csvRaw = await csv.snapshotRawCSV()
        var parts: [String] = []
        for (path, body) in rpcRaw.sorted(by: { $0.key < $1.key }) {
            parts.append("=== RPC \(path) ===\n\(body)")
        }
        parts.append("=== CSV (\(csvRaw.count) bytes) ===\n\(csvRaw.prefix(4000))")
        // Also surface date-range metadata.
        let lines = csvRaw.split(separator: "\n")
        let dataLines = lines.dropFirst()
        let firstDate = dataLines.first.map { String($0.prefix(40)) } ?? "n/a"
        let lastDate = dataLines.last.map { String($0.prefix(40)) } ?? "n/a"
        parts.append("=== CSV date range ===\nfirst: \(firstDate)\nlast:  \(lastDate)\nrows:  \(dataLines.count)")
        return parts.joined(separator: "\n\n")
    }

    /// Fetch RPC trio first so we know the current and previous billing-cycle
    /// bounds, then fetch enough CSV to cover the shared dashboard ranges and
    /// comparisons. Falls back to trailing 63 days if the RPC doesn't return a
    /// usable cycle window.
    func fetchSnapshot() async throws -> APISnapshot {
        return try await retryingOnAuth {
            let token = try await self.auth.accessToken()
            let (userID, sessionToken) = try await self.auth.buildSessionToken(token)
            _ = userID

            async let usage = self.rpc.getCurrentPeriodUsage(token: token)
            async let plan = self.rpc.getPlanInfo(token: token)
            async let credits = self.rpc.getCreditGrantsBalance(token: token)
            async let stripeCents = self.stripe.creditBalanceCents(sessionToken: sessionToken)

            let usageVal = try await usage
            let planVal = try? await plan
            let creditsVal = try? await credits

            let (start, end) = Self.csvWindow(usage: usageVal)

            async let rows = self.csv.fetch(sessionToken: sessionToken, start: start, end: end)
            let rowsVal = (try? await rows) ?? []
            let stripeVal = (try? await stripeCents) ?? 0

            return APISnapshot(
                usage: usageVal,
                plan: planVal,
                credits: creditsVal,
                csvRows: rowsVal,
                stripeBalanceCents: stripeVal,
                csvStart: start,
                csvEnd: end
            )
        }
    }

    /// Run `work`. On the first auth failure (401/403), force-refresh and retry once.
    private func retryingOnAuth(_ work: @Sendable () async throws -> APISnapshot) async throws -> APISnapshot {
        do {
            return try await work()
        } catch let err as HTTPError where err.isAuth {
            Log.api.info("received auth error, force-refreshing token and retrying once")
            await auth.invalidate()
            _ = try await auth.accessToken(forceRefresh: true)
            return try await work()
        }
    }

    /// CSV window: from the previous billing cycle start (if known and within
    /// 63 days) to end-of-today, else trailing 63 days.
    static func csvWindow(usage: GetCurrentPeriodUsageResponse?,
                          now: Date = Date(),
                          calendar: Calendar = .current) -> (Date, Date) {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)?
            .addingTimeInterval(-1) ?? now

        let fallbackStart = calendar.date(byAdding: .day, value: -63, to: startOfToday)
            ?? startOfToday

        guard let cycleStart = usage?.billingCycleStart?.asUnixMillisDate else {
            return (fallbackStart, endOfToday)
        }

        let cycleEnd = usage?.billingCycleEnd?.asUnixMillisDate
        let billingCycleWindow = BillingCycleWindow.resolve(
            start: cycleStart,
            end: cycleEnd,
            now: now,
            calendar: calendar
        )

        let earliest = calendar.date(byAdding: .day, value: -63, to: startOfToday) ?? startOfToday
        let start = billingCycleWindow.previousStart < earliest ? fallbackStart : billingCycleWindow.previousStart
        return (start, endOfToday)
    }
}
