import Foundation

struct JWTPayload: Decodable {
    let sub: String?
    let exp: Double?
}

enum JWT {
    /// Decode a JWT payload by splitting on `.`, base64url-decoding the middle segment,
    /// then parsing as JSON. Returns nil on any failure.
    static func decodePayload(_ token: String) -> JWTPayload? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payload = parts[1]
        guard let data = base64URLDecode(String(payload)) else { return nil }
        return try? JSONDecoder().decode(JWTPayload.self, from: data)
    }

    static func expirationDate(_ token: String) -> Date? {
        guard let exp = decodePayload(token)?.exp else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Derive the user id portion used in the session cookie.
    /// Cursor's JWT `sub` looks like `google-oauth2|user_abc`; strip the provider prefix.
    static func userID(from token: String) -> String? {
        guard let sub = decodePayload(token)?.sub, !sub.isEmpty else { return nil }
        let parts = sub.split(separator: "|", maxSplits: 1)
        let id = parts.count > 1 ? String(parts[1]) : String(parts[0])
        return id.isEmpty ? nil : id
    }

    private static func base64URLDecode(_ s: String) -> Data? {
        var normalized = s.replacingOccurrences(of: "-", with: "+")
                          .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - normalized.count % 4) % 4
        normalized.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: normalized)
    }
}
