import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Your Strava API application (strava.com/settings/api).
public struct StravaAppConfig: Hashable, Codable, Sendable {
    public var clientID: String
    /// Custom URL scheme the app registers for the OAuth redirect.
    public var callbackScheme: String
    /// Must match "Authorization Callback Domain" in Strava's API settings.
    /// `localhost` is always allowed by Strava.
    public var callbackDomain: String
    public var scopes: [String]

    public static let defaultScopes = ["read", "activity:read_all", "profile:read_all"]

    public init(clientID: String, callbackScheme: String = "odysseyrecap", callbackDomain: String = "localhost", scopes: [String] = defaultScopes) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.callbackScheme = callbackScheme
        self.callbackDomain = callbackDomain.isEmpty ? "localhost" : callbackDomain
        self.scopes = scopes
    }

    public var isValid: Bool { !clientID.isEmpty && clientID.allSatisfy(\.isNumber) }

    public var redirectURI: String { "\(callbackScheme)://\(callbackDomain)/strava" }

    /// Authorisation page. `viaStravaApp` uses the `strava://` scheme, which
    /// opens the Strava app's own approval screen when it's installed.
    public func authorizeURL(state: String, viaStravaApp: Bool = false) -> URL {
        var components = URLComponents()
        if viaStravaApp {
            components.scheme = "strava"
            components.host = "oauth"
            components.path = "/mobile/authorize"
        } else {
            components.scheme = "https"
            components.host = "www.strava.com"
            components.path = "/oauth/mobile/authorize"
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: ",")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Validates the redirect and returns the authorisation code and granted scopes.
    public func parseCallback(_ url: URL, expectedState: String?) throws -> (code: String, scopes: Set<String>) {
        guard url.scheme?.lowercased() == callbackScheme.lowercased() else { throw StravaError.badResponse }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? StravaError.accessDenied : StravaError.server(status: 400, message: error)
        }
        if let expectedState, value("state") != expectedState { throw StravaError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw StravaError.badResponse }
        let scopes = Set((value("scope") ?? "").split(separator: ",").map(String.init))
        if !scopes.isEmpty, !scopes.contains("activity:read"), !scopes.contains("activity:read_all") {
            throw StravaError.missingActivityScope
        }
        return (code, scopes)
    }
}

/// OAuth tokens for one athlete.
public struct StravaTokens: Hashable, Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scopes: Set<String>
    public var athlete: Athlete?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scopes: Set<String> = [], athlete: Athlete? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.athlete = athlete
    }

    /// Strava access tokens last six hours; refresh a little early.
    public func needsRefresh(at date: Date, margin: TimeInterval = 300) -> Bool {
        expiresAt.timeIntervalSince(date) < margin
    }

    public var canReadPrivateActivities: Bool { scopes.isEmpty || scopes.contains("activity:read_all") }

    static func from(_ data: Data, scopes: Set<String> = []) throws -> StravaTokens {
        guard let dto = try? JSONDecoder().decode(TokenResponseDTO.self, from: data) else {
            throw StravaError.decoding("sign-in response")
        }
        return StravaTokens(
            accessToken: dto.accessToken,
            refreshToken: dto.refreshToken,
            expiresAt: Date(timeIntervalSince1970: dto.expiresAt),
            scopes: scopes,
            athlete: dto.athlete?.athlete
        )
    }
}

/// Turns authorisation codes into tokens and keeps them fresh. Strava has no
/// PKCE, so this needs the client secret — either on the device (your own API
/// app, for personal testing) or on a small token server.
public protocol TokenExchanger: Sendable {
    func exchange(code: String, scopes: Set<String>) async throws -> StravaTokens
    func refresh(_ tokens: StravaTokens) async throws -> StravaTokens
    func revoke(_ tokens: StravaTokens) async throws
}

extension TokenExchanger {
    func check(_ response: HTTPURLResponse, _ data: Data) throws {
        switch response.statusCode {
        case 200..<300: return
        case 400, 401:
            let message = (try? JSONDecoder().decode(FaultDTO.self, from: data))?.message
            throw message?.localizedCaseInsensitiveContains("invalid") == true || response.statusCode == 401
                ? StravaError.unauthorized
                : StravaError.server(status: response.statusCode, message: message)
        case 403:
            let fault = try? JSONDecoder().decode(FaultDTO.self, from: data)
            if fault?.code == "athlete_not_allowed" { throw StravaError.athleteNotAllowed }
            // Strava: {"message":"Forbidden","errors":[{"code":"limit of connected athletes exceeded",…}]}
            if String(decoding: data.prefix(4000), as: UTF8.self).localizedCaseInsensitiveContains("connected athletes") {
                throw StravaError.athleteLimitReached
            }
            throw StravaError.server(status: 403, message: fault?.message)
        case 429: throw StravaError.rateLimited(nil)
        default: throw StravaError.server(status: response.statusCode, message: String(data: data.prefix(200), encoding: .utf8))
        }
    }
}

/// Talks to strava.com directly with a client secret stored on the device.
public struct DirectTokenExchanger: TokenExchanger {
    public static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    public static let revokeURL = URL(string: "https://www.strava.com/oauth/revoke")!
    public static let deauthorizeURL = URL(string: "https://www.strava.com/oauth/deauthorize")!

    let clientID: String
    let clientSecret: String
    let http: any HTTPClient

    public init(clientID: String, clientSecret: String, http: any HTTPClient = URLSessionHTTPClient()) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.http = http
    }

    public func exchange(code: String, scopes: Set<String>) async throws -> StravaTokens {
        let request = URLRequest.form(Self.tokenURL, fields: [
            ("client_id", clientID), ("client_secret", clientSecret), ("code", code), ("grant_type", "authorization_code"),
        ])
        let (data, response) = try await http.data(for: request)
        try check(response, data)
        return try StravaTokens.from(data, scopes: scopes)
    }

    public func refresh(_ tokens: StravaTokens) async throws -> StravaTokens {
        let request = URLRequest.form(Self.tokenURL, fields: [
            ("client_id", clientID), ("client_secret", clientSecret), ("grant_type", "refresh_token"), ("refresh_token", tokens.refreshToken),
        ])
        let (data, response) = try await http.data(for: request)
        try check(response, data)
        var fresh = try StravaTokens.from(data, scopes: tokens.scopes)
        fresh.athlete = fresh.athlete ?? tokens.athlete
        return fresh
    }

    public func revoke(_ tokens: StravaTokens) async throws {
        var request = URLRequest.form(Self.revokeURL, fields: [("token", tokens.refreshToken), ("token_type_hint", "refresh_token")])
        let basic = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await http.data(for: request)
        if (200..<300).contains(response.statusCode) { return }
        // Fall back to the legacy endpoint (supported until June 2027).
        let legacy = URLRequest.form(Self.deauthorizeURL, fields: [("access_token", tokens.accessToken)])
        let (legacyData, legacyResponse) = try await http.data(for: legacy)
        try check(legacyResponse, legacyData)
    }
}

/// Talks to Odyssey's optional token server (Odyssey/backend), which holds the secret.
public struct ServerTokenExchanger: TokenExchanger {
    let baseURL: URL
    let http: any HTTPClient

    public init(baseURL: URL, http: any HTTPClient = URLSessionHTTPClient()) {
        self.baseURL = baseURL
        self.http = http
    }

    public func exchange(code: String, scopes: Set<String>) async throws -> StravaTokens {
        let (data, response) = try await http.data(for: .json(baseURL.appendingPathComponent("v1/strava/token"), body: ["code": code]))
        try check(response, data)
        return try StravaTokens.from(data, scopes: scopes)
    }

    public func refresh(_ tokens: StravaTokens) async throws -> StravaTokens {
        let (data, response) = try await http.data(for: .json(baseURL.appendingPathComponent("v1/strava/refresh"), body: ["refresh_token": tokens.refreshToken]))
        try check(response, data)
        var fresh = try StravaTokens.from(data, scopes: tokens.scopes)
        fresh.athlete = fresh.athlete ?? tokens.athlete
        return fresh
    }

    public func revoke(_ tokens: StravaTokens) async throws {
        let (data, response) = try await http.data(for: .json(baseURL.appendingPathComponent("v1/strava/revoke"), body: ["token": tokens.refreshToken]))
        try check(response, data)
    }
}

/// Hands out a valid access token, refreshing once when several requests
/// need one at the same time.
public actor StravaSession {
    private var tokens: StravaTokens
    private let exchanger: any TokenExchanger
    private let onUpdate: @Sendable (StravaTokens) -> Void
    private var refreshing: Task<StravaTokens, Error>?

    public init(tokens: StravaTokens, exchanger: any TokenExchanger, onUpdate: @escaping @Sendable (StravaTokens) -> Void) {
        self.tokens = tokens
        self.exchanger = exchanger
        self.onUpdate = onUpdate
    }

    public var current: StravaTokens { tokens }

    public func accessToken(at date: Date = Date()) async throws -> String {
        guard tokens.needsRefresh(at: date) else { return tokens.accessToken }
        if let refreshing { return try await refreshing.value.accessToken }
        let exchanger = exchanger
        let snapshot = tokens
        let task = Task { try await exchanger.refresh(snapshot) }
        refreshing = task
        do {
            let fresh = try await task.value
            tokens = fresh
            refreshing = nil
            onUpdate(fresh)
            return fresh.accessToken
        } catch {
            refreshing = nil
            throw error
        }
    }

    public func revoke() async throws {
        try await exchanger.revoke(tokens)
    }
}
