import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StravaError.badResponse }
        return (data, http)
    }
}

public enum StravaError: Error, Equatable, Sendable {
    case notConfigured
    case notConnected
    case cancelled
    case accessDenied
    case missingActivityScope
    case stateMismatch
    case unauthorized
    case forbidden
    /// Strava's "limit of connected athletes exceeded": the API app is full.
    case athleteLimitReached
    /// The token server only accepts the athletes on its allowlist.
    case athleteNotAllowed
    case notFound
    case rateLimited(RateLimitStatus?)
    case server(status: Int, message: String?)
    case badResponse
    case decoding(String)
}

extension StravaError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Add your Strava API app's Client ID (and secret or token server) in Settings first."
        case .notConnected:
            "Connect your Strava account to load your activities."
        case .cancelled:
            "Connection cancelled."
        case .accessDenied:
            "Strava access was declined."
        case .missingActivityScope:
            "Odyssey needs permission to read your activities. Connect again and keep \"View data about your activities\" ticked."
        case .stateMismatch:
            "That sign-in link didn't come from this app. Please try connecting again."
        case .unauthorized:
            "Your Strava session expired. Please connect again."
        case .forbidden:
            "Strava refused that request. Check the permissions you granted."
        case .athleteLimitReached:
            "This Strava API app can't connect any more athletes yet. Whoever set it up can raise the limit at strava.com/settings/api."
        case .athleteNotAllowed:
            "This copy of Odyssey isn't open to your Strava account. Ask whoever shared it with you to add you."
        case .notFound:
            "Strava couldn't find that."
        case .rateLimited(let status):
            if let status {
                "Strava's request limit is reached (\(status.shortUsage)/\(status.shortLimit) this quarter hour). Syncing resumes automatically."
            } else {
                "Strava's request limit is reached. Syncing resumes automatically."
            }
        case .server(let status, let message):
            "Strava error \(status)\(message.map { ": \($0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))" } ?? "")."
        case .badResponse:
            "Strava sent something unexpected."
        case .decoding(let what):
            "Couldn't read Strava's \(what)."
        }
    }
}

extension URLRequest {
    static func form(_ url: URL, fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    static func json(_ url: URL, body: [String: String]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
}
