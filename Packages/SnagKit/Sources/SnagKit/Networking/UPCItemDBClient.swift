import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProductLookupResult: Sendable, Hashable {
    public var product: Product
    public var offers: [Offer]

    public init(product: Product, offers: [Offer]) {
        self.product = product
        self.offers = offers
    }
}

/// UPCitemdb: barcode → product + multi-merchant offers. The trial endpoint
/// needs no key (rate limited per device IP); a paid key raises limits.
public struct UPCItemDBClient: Sendable {
    let http: HTTPClient
    let apiKey: String?

    public init(http: HTTPClient = URLSessionHTTPClient(), apiKey: String? = nil) {
        self.http = http
        self.apiKey = apiKey
    }

    var base: String { apiKey == nil ? "https://api.upcitemdb.com/prod/trial" : "https://api.upcitemdb.com/prod/v1" }

    public func lookup(gtin: String) async throws -> ProductLookupResult {
        var components = URLComponents(string: base + "/lookup")!
        components.queryItems = [URLQueryItem(name: "upc", value: gtin)]
        let items = try await fetch(components.url!)
        guard let first = items.first else { throw LookupError.notFound }
        return Self.map(first, scannedCode: gtin)
    }

    public func search(_ query: String) async throws -> [ProductLookupResult] {
        var components = URLComponents(string: base + "/search")!
        components.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "match_mode", value: "0"),
            URLQueryItem(name: "type", value: "product"),
        ]
        return try await fetch(components.url!).map { Self.map($0, scannedCode: nil) }
    }

    func fetch(_ url: URL) async throws -> [Item] {
        var request = URLRequest.get(url)
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "user_key")
            request.setValue("3scale", forHTTPHeaderField: "key_type")
        }
        let (data, response) = try await http.data(for: request)
        if response.statusCode == 429 {
            throw LookupError.rateLimited(retryAfter: Self.resetDate(response))
        }
        let decoded = try JSONDecoder().decode(Envelope.self, from: data)
        switch decoded.code {
        case "OK": return decoded.items ?? []
        case "TOO_FAST", "EXCEED_LIMIT": throw LookupError.rateLimited(retryAfter: Self.resetDate(response))
        case "INVALID_UPC", "INVALID_QUERY": throw LookupError.invalidCode
        default:
            if (decoded.items ?? []).isEmpty, response.statusCode == 404 { throw LookupError.notFound }
            throw LookupError.server(decoded.message ?? decoded.code)
        }
    }

    static func resetDate(_ response: HTTPURLResponse) -> Date? {
        (response.value(forHTTPHeaderField: "X-RateLimit-Reset")).flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
    }

    struct Envelope: Decodable {
        var code: String
        var message: String?
        var items: [Item]?
    }

    struct Item: Decodable {
        var ean: String?
        var upc: String?
        var title: String?
        var description: String?
        var brand: String?
        var model: String?
        var category: String?
        var currency: String?
        var lowest_recorded_price: FlexibleDouble?
        var highest_recorded_price: FlexibleDouble?
        var images: [String]?
        var offers: [ItemOffer]?
    }

    struct ItemOffer: Decodable {
        var merchant: String?
        var domain: String?
        var title: String?
        var currency: String?
        var price: FlexibleDouble?
        var shipping: String?
        var condition: String?
        var availability: String?
        var link: String?
        var updated_t: Double?
    }

    static func map(_ item: Item, scannedCode: String?) -> ProductLookupResult {
        let gtin = [scannedCode, item.upc, item.ean].compactMap { $0.flatMap { GTIN.normalize($0) } }.first
        let currency = (item.currency?.isEmpty == false ? item.currency! : "USD").uppercased()
        let product = Product(
            gtin: gtin,
            title: item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Unknown product",
            brand: item.brand?.nonEmpty,
            model: item.model?.nonEmpty,
            category: item.category?.nonEmpty,
            summary: item.description?.nonEmpty,
            imageURLs: (item.images ?? []).compactMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) },
            source: .upcItemDB,
            recordedLow: item.lowest_recorded_price?.value,
            recordedHigh: item.highest_recorded_price?.value
        )
        let offers: [Offer] = (item.offers ?? []).enumerated().compactMap { index, o in
            guard let price = o.price?.value, price > 0 else { return nil }
            let merchant = o.merchant?.nonEmpty ?? o.domain ?? "Shop"
            return Offer(
                id: "upc-\(gtin ?? product.id)-\(index)-\(merchant)",
                merchant: merchant,
                merchantDomain: o.domain?.nonEmpty,
                title: o.title,
                price: price,
                shipping: parseShipping(o.shipping),
                currency: (o.currency?.isEmpty == false ? o.currency! : currency).uppercased(),
                url: o.link.flatMap(URL.init(string:)),
                condition: parseCondition(o.condition),
                inStock: o.availability.flatMap { $0.isEmpty ? nil : !$0.lowercased().contains("out") },
                updatedAt: o.updated_t.map { Date(timeIntervalSince1970: $0) },
                source: "upcitemdb"
            )
        }
        return ProductLookupResult(product: product, offers: offers)
    }

    static func parseShipping(_ s: String?) -> Double? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.lowercased().contains("free") { return 0 }
        return Double(s.filter { $0.isNumber || $0 == "." })
    }

    static func parseCondition(_ s: String?) -> Offer.Condition {
        switch s?.lowercased() {
        case "new": .new
        case "used", "pre-owned": .used
        case "refurbished", "renewed": .refurbished
        default: .unknown
        }
    }
}

extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
