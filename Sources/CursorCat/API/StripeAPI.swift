import Foundation

/// GET https://cursor.com/api/auth/stripe — Cookie auth. Optional.
actor StripeAPI {
    static let url = URL(string: "https://cursor.com/api/auth/stripe")!

    private let session: URLSession
    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns the absolute credit balance in cents (0 if no credit on file).
    /// Stripe stores credits as a negative customer balance.
    func creditBalanceCents(sessionToken: String) async throws -> Int {
        var req = URLRequest(url: Self.url)
        req.httpMethod = "GET"
        req.setValue("WorkosCursorSessionToken=\(sessionToken)", forHTTPHeaderField: "Cookie")
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

        let stripe = try JSONDecoder().decode(StripeResponse.self, from: data)
        guard let balance = stripe.customerBalance else { return 0 }
        return balance < 0 ? Int(abs(balance).rounded()) : 0
    }
}
