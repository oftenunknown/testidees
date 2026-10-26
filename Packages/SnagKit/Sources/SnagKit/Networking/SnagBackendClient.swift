import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Optional Snag server (see `/backend`). Adds live shopping-search prices,
/// cloud gift ideas and server-side price watching with push. Everything in
/// the app still works without it.
public struct SnagBackendClient: Sendable {
    public let baseURL: URL
    let http: HTTPClient
    let deviceID: String
    /// Matches the server's optional SNAG_SHARED_SECRET.
    let sharedKey: String?

    public init(baseURL: URL, deviceID: String, sharedKey: String? = nil, http: HTTPClient = URLSessionHTTPClient()) {
        self.baseURL = baseURL
        self.deviceID = deviceID
        self.sharedKey = sharedKey
        self.http = http
    }

    public func offers(query: String, gtin: String?, region: Region) async throws -> [Offer] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/offers"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "country", value: region.countryCode),
            URLQueryItem(name: "currency", value: region.currencyCode),
        ] + (gtin.map { [URLQueryItem(name: "gtin", value: $0)] } ?? [])
        let response: OffersResponse = try await send(.get(components.url!))
        return response.offers
    }

    public func giftIdeas(_ request: GiftRequest) async throws -> [GiftIdea] {
        let response: GiftResponse = try await send(post("v1/gifts", body: request, timeout: 60))
        return response.ideas
    }

    public func registerWatch(_ watch: WatchRegistration) async throws {
        let _: Empty = try await send(post("v1/watch", body: watch))
    }

    public func removeWatch(productID: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/watch/\(productID)"))
        request.httpMethod = "DELETE"
        let _: Empty = try await send(request)
    }

    // MARK: - DTOs

    public struct OffersResponse: Codable, Sendable {
        public var offers: [Offer]
    }

    public struct GiftRequest: Codable, Sendable {
        public var recipient: RecipientProfile
        public var giver: PersonaProfile
        public var prompt: String
        public var count: Int

        public init(recipient: RecipientProfile, giver: PersonaProfile, count: Int = 6, avoid: [String] = []) {
            self.recipient = recipient
            self.giver = giver
            self.count = count
            self.prompt = GiftPromptBuilder.prompt(recipient: recipient, giver: giver, count: count, avoid: avoid)
        }
    }

    public struct GiftResponse: Codable, Sendable {
        public var ideas: [GiftIdea]
    }

    public struct WatchRegistration: Codable, Sendable {
        public var productID: String
        public var gtin: String?
        public var query: String
        public var region: Region
        public var rule: PriceAlertRule
        public var apnsToken: String?

        public init(productID: String, gtin: String?, query: String, region: Region, rule: PriceAlertRule, apnsToken: String?) {
            self.productID = productID
            self.gtin = gtin
            self.query = query
            self.region = region
            self.rule = rule
            self.apnsToken = apnsToken
        }
    }

    struct Empty: Codable {}

    // MARK: - Plumbing

    func post<Body: Encodable>(_ path: String, body: Body, timeout: TimeInterval = 20) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        return request
    }

    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.setValue(deviceID, forHTTPHeaderField: "X-Snag-Device")
        if let sharedKey, !sharedKey.isEmpty { request.setValue(sharedKey, forHTTPHeaderField: "X-Snag-Key") }
        let (data, response) = try await http.data(for: request)
        switch response.statusCode {
        case 200..<300:
            if T.self == Empty.self, data.isEmpty, let empty = Empty() as? T { return empty }
            return try Self.decoder.decode(T.self, from: data)
        case 404: throw LookupError.notFound
        case 429: throw LookupError.rateLimited(retryAfter: nil)
        case 501, 503: throw LookupError.notConfigured
        default:
            throw LookupError.server(String(data: data, encoding: .utf8)?.prefix(200).description ?? "Server error \(response.statusCode)")
        }
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
