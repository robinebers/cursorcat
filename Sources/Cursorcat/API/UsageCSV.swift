import Foundation

/// One parsed row from Cursor's CSV export. Cost is the *imputed* dollar
/// amount (dollars, not cents) — what the user would have been charged if
/// the usage weren't covered by a plan. Rows with unknown models produce 0.
struct UsageCSVRow {
    var date: Date
    var model: String
    var canonicalModel: String?
    var maxMode: Bool
    var tokens: TokenUsage
    var imputedCostDollars: Double
    var csvCost: String
}

extension TokenUsage {
    var totalTokens: Int {
        inputCacheWrite + inputNoCacheWrite + cacheRead + output
    }
}

/// GET https://cursor.com/api/dashboard/export-usage-events-csv — Cookie auth.
actor UsageCSVClient {
    static let exportURL = URL(string: "https://cursor.com/api/dashboard/export-usage-events-csv")!

    private let session: URLSession
    private(set) var lastRawCSV: String = ""

    init(session: URLSession = .shared) {
        self.session = session
    }

    func snapshotRawCSV() -> String { lastRawCSV }

    func fetch(sessionToken: String, start: Date, end: Date) async throws -> [UsageCSVRow] {
        var comps = URLComponents(url: Self.exportURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "startDate", value: String(Int(start.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "endDate", value: String(Int(end.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "strategy", value: "tokens")
        ]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("WorkosCursorSessionToken=\(sessionToken)", forHTTPHeaderField: "Cookie")
        req.setValue("text/csv", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw HTTPError.unauthorized(http.statusCode)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(http.statusCode)
        }
        guard let csv = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        lastRawCSV = csv
        return Self.parse(csv: csv)
    }

    /// Expose parser for tests and debug menu. Pure function.
    static func parse(csv: String) -> [UsageCSVRow] {
        let records = CSVParser.parseRecords(csv)
        let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let iso: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        return records.compactMap { r in
            guard let dateStr = r["Date"]?.trimmingCharacters(in: .whitespaces),
                  !dateStr.isEmpty,
                  let date = parseDate(dateStr, iso: iso, isoFractional: isoFractional)
            else { return nil }

            let model = (r["Model"] ?? "").trimmingCharacters(in: .whitespaces)
            let maxMode = (r["Max Mode"] ?? "").trimmingCharacters(in: .whitespaces).lowercased() == "yes"
            let tokens = TokenUsage(
                inputCacheWrite: parseIntValue(r["Input (w/ Cache Write)"] ?? ""),
                inputNoCacheWrite: parseIntValue(r["Input (w/o Cache Write)"] ?? ""),
                cacheRead: parseIntValue(r["Cache Read"] ?? ""),
                output: parseIntValue(r["Output Tokens"] ?? "")
            )
            let canonical = Pricing.canonicalModel(for: model)
            let imputed = Pricing.estimatedCostDollars(model: model, maxMode: maxMode, tokens: tokens)

            return UsageCSVRow(
                date: date,
                model: model,
                canonicalModel: canonical,
                maxMode: maxMode,
                tokens: tokens,
                imputedCostDollars: imputed,
                csvCost: (r["Cost"] ?? "").trimmingCharacters(in: .whitespaces)
            )
        }
    }

    private static func parseDate(
        _ raw: String,
        iso: ISO8601DateFormatter,
        isoFractional: ISO8601DateFormatter
    ) -> Date? {
        if let d = isoFractional.date(from: raw) { return d }
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: raw)
    }

    private static func parseIntValue(_ raw: String) -> Int {
        let normalized = raw.replacingOccurrences(of: ",", with: "")
                            .trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty { return 0 }
        return Int(normalized) ?? 0
    }
}
