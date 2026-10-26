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
        guard let http = response as? HTTPURLResponse else { throw LookupError.badResponse }
        return (data, http)
    }
}

public enum LookupError: Error, Equatable, Sendable {
    case notFound
    case rateLimited(retryAfter: Date?)
    case badResponse
    case invalidCode
    case server(String)
    case notConfigured
}

extension LookupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound: "We couldn't find that product."
        case .rateLimited: "Price lookups are busy right now. Try again in a minute."
        case .badResponse: "The price service sent something unexpected."
        case .invalidCode: "That barcode doesn't look valid."
        case .server(let message): message
        case .notConfigured: "This feature needs the Snag server, which isn't set up."
        }
    }
}

/// Decodes a number that some APIs send as a number and others as a string.
struct FlexibleDouble: Decodable, Sendable {
    var value: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            value = nil
        } else if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self) {
            value = Double(s.filter { $0.isNumber || $0 == "." })
        } else {
            value = nil
        }
    }
}

extension URLRequest {
    static func get(_ url: URL, timeout: TimeInterval = 12) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Snag/1.0 (iOS; price comparison)", forHTTPHeaderField: "User-Agent")
        return request
    }
}
