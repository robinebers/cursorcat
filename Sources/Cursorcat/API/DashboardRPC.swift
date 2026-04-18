import Foundation

/// Connect RPC POSTs to Cursor's Dashboard service. Bearer auth.
actor DashboardRPC {
    static let baseURL = URL(string: "https://api2.cursor.sh")!

    private let session: URLSession
    private(set) var lastRaw: [String: String] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func getCurrentPeriodUsage(token: String) async throws -> GetCurrentPeriodUsageResponse {
        try await post(path: "/aiserver.v1.DashboardService/GetCurrentPeriodUsage", token: token)
    }

    func getPlanInfo(token: String) async throws -> GetPlanInfoResponse {
        try await post(path: "/aiserver.v1.DashboardService/GetPlanInfo", token: token)
    }

    func getCreditGrantsBalance(token: String) async throws -> GetCreditGrantsBalanceResponse {
        try await post(path: "/aiserver.v1.DashboardService/GetCreditGrantsBalance", token: token)
    }

    func snapshotRaw() -> [String: String] { lastRaw }

    private func post<T: Decodable>(path: String, token: String) async throws -> T {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 15

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
        if let body = String(data: data, encoding: .utf8) {
            lastRaw[path] = body
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Log.api.error("decode failed for \(path): \(String(describing: error))")
            throw error
        }
    }
}

enum HTTPError: Error, CustomStringConvertible {
    case unauthorized(Int)
    case status(Int)

    var description: String {
        switch self {
        case .unauthorized(let s): return "Unauthorized (HTTP \(s))"
        case .status(let s): return "HTTP \(s)"
        }
    }

    var isAuth: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}
