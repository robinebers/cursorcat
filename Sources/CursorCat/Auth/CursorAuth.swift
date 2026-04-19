import Foundation

/// Cursor auth error surfaced to the app layer.
enum CursorAuthError: Error, CustomStringConvertible {
    case notLoggedIn
    case sessionExpired
    case refreshFailed(status: Int)
    case invalidRefreshResponse
    case missingUserID

    var description: String {
        switch self {
        case .notLoggedIn: return "Not logged in"
        case .sessionExpired: return "Session expired"
        case .refreshFailed(let status): return "Token refresh failed (HTTP \(status))"
        case .invalidRefreshResponse: return "Token refresh returned an invalid response"
        case .missingUserID: return "Access token missing a user id"
        }
    }

    var shouldLogOut: Bool {
        switch self {
        case .notLoggedIn, .sessionExpired: return true
        default: return false
        }
    }
}

enum AuthSource: String {
    case sqlite
    case keychain
}

struct AuthState {
    var accessToken: String?
    var refreshToken: String?
    var source: AuthSource?
}

private struct RefreshResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let shouldLogout: Bool?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case shouldLogout
    }
}

/// Orchestrator: loadAuth → refreshIfNeeded → access token.
/// Adapted from robinebers/openusage:
/// https://github.com/robinebers/openusage
/// Thread-safe via actor isolation.
actor CursorAuth {
    static let accessTokenKey = "cursorAuth/accessToken"
    static let refreshTokenKey = "cursorAuth/refreshToken"
    static let membershipTypeKey = "cursorAuth/stripeMembershipType"
    static let keychainAccessService = "cursor-access-token"
    static let keychainRefreshService = "cursor-refresh-token"

    private static let refreshURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    private static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    private static let refreshBuffer: TimeInterval = 5 * 60

    private var cached: AuthState?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Load auth state. Prefers SQLite but falls back to (or prefers) keychain
    /// when SQLite indicates a free account AND keychain has a different subject.
    func loadAuthState(forceReload: Bool = false) -> AuthState {
        if let cached, !forceReload { return cached }

        let sqliteAccess = CursorSQLite.readValue(for: Self.accessTokenKey)
        let sqliteRefresh = CursorSQLite.readValue(for: Self.refreshTokenKey)
        let sqliteMembershipRaw = CursorSQLite.readValue(for: Self.membershipTypeKey)
        let sqliteMembership = sqliteMembershipRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
                                                   .lowercased()

        let keychainAccess = CursorKeychain.read(service: Self.keychainAccessService)
        let keychainRefresh = CursorKeychain.read(service: Self.keychainRefreshService)

        let sqliteSubject = sqliteAccess.flatMap { JWT.decodePayload($0)?.sub }
        let keychainSubject = keychainAccess.flatMap { JWT.decodePayload($0)?.sub }
        let differentSubjects = sqliteSubject != nil && keychainSubject != nil && sqliteSubject != keychainSubject
        let sqliteLooksFree = sqliteMembership == "free"

        let state: AuthState
        if sqliteAccess != nil || sqliteRefresh != nil {
            if (keychainAccess != nil || keychainRefresh != nil) && sqliteLooksFree && differentSubjects {
                Log.auth.info("sqlite looks free and differs from keychain; preferring keychain")
                state = AuthState(accessToken: keychainAccess, refreshToken: keychainRefresh, source: .keychain)
            } else {
                state = AuthState(accessToken: sqliteAccess, refreshToken: sqliteRefresh, source: .sqlite)
            }
        } else if keychainAccess != nil || keychainRefresh != nil {
            state = AuthState(accessToken: keychainAccess, refreshToken: keychainRefresh, source: .keychain)
        } else {
            state = AuthState(accessToken: nil, refreshToken: nil, source: nil)
        }

        cached = state
        return state
    }

    /// Return a valid access token, refreshing if needed. Throws on logged-out states.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        var state = loadAuthState(forceReload: forceRefresh)
        if state.accessToken == nil && state.refreshToken == nil {
            throw CursorAuthError.notLoggedIn
        }

        if forceRefresh || needsRefresh(state.accessToken) {
            state = try await performRefresh(state: state)
            cached = state
        }

        guard let token = state.accessToken, !needsRefresh(token) else {
            throw CursorAuthError.notLoggedIn
        }
        return token
    }

    func invalidate() {
        cached = nil
    }

    private func needsRefresh(_ accessToken: String?) -> Bool {
        guard let token = accessToken else { return true }
        guard let exp = JWT.expirationDate(token) else { return true }
        return exp.timeIntervalSinceNow < Self.refreshBuffer
    }

    /// POST to /oauth/token and persist rotated credentials back to their source.
    private func performRefresh(state: AuthState) async throws -> AuthState {
        guard let refreshToken = state.refreshToken else {
            Log.auth.warning("refresh skipped: no refresh token")
            throw CursorAuthError.sessionExpired
        }

        var req = URLRequest(url: Self.refreshURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CursorAuthError.invalidRefreshResponse
        }

        let payload = try? JSONDecoder().decode(RefreshResponse.self, from: data)

        if http.statusCode == 400 || http.statusCode == 401 {
            let shouldLogout = payload?.shouldLogout == true
            Log.auth.error("refresh failed status=\(http.statusCode) shouldLogout=\(shouldLogout)")
            throw shouldLogout ? CursorAuthError.sessionExpired
                               : CursorAuthError.refreshFailed(status: http.statusCode)
        }

        if !(200..<300).contains(http.statusCode) {
            Log.auth.warning("refresh unexpected status: \(http.statusCode)")
            throw CursorAuthError.refreshFailed(status: http.statusCode)
        }

        guard let payload else {
            throw CursorAuthError.invalidRefreshResponse
        }

        if payload.shouldLogout == true {
            throw CursorAuthError.sessionExpired
        }

        guard let newAccess = payload.accessToken, !newAccess.isEmpty else {
            throw CursorAuthError.invalidRefreshResponse
        }

        let nextState = AuthState(
            accessToken: newAccess,
            refreshToken: payload.refreshToken ?? state.refreshToken,
            source: state.source
        )
        try persist(state: nextState)
        Log.auth.info("refresh succeeded and persisted to \(state.source?.rawValue ?? "unknown")")
        return nextState
    }

    private func persist(state: AuthState) throws {
        switch state.source {
        case .keychain:
            guard let accessToken = state.accessToken,
                  CursorKeychain.write(accessToken, service: Self.keychainAccessService) else {
                throw CursorAuthError.invalidRefreshResponse
            }
            if let refreshToken = state.refreshToken,
               !CursorKeychain.write(refreshToken, service: Self.keychainRefreshService) {
                throw CursorAuthError.invalidRefreshResponse
            }
        case .sqlite:
            guard let accessToken = state.accessToken,
                  CursorSQLite.writeValue(accessToken, for: Self.accessTokenKey) else {
                throw CursorAuthError.invalidRefreshResponse
            }
            if let refreshToken = state.refreshToken,
               !CursorSQLite.writeValue(refreshToken, for: Self.refreshTokenKey) {
                throw CursorAuthError.invalidRefreshResponse
            }
        case .none:
            throw CursorAuthError.invalidRefreshResponse
        }
    }

    /// Build `{userId, sessionToken}` from an access token.
    /// Session token is `<userId>%3A%3A<accessToken>`.
    func buildSessionToken(_ accessToken: String) throws -> (userID: String, sessionToken: String) {
        guard let userID = JWT.userID(from: accessToken) else {
            throw CursorAuthError.missingUserID
        }
        return (userID, "\(userID)%3A%3A\(accessToken)")
    }
}
