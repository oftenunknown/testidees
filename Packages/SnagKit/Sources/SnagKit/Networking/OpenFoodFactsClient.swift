import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Open Food Facts (and its beauty/product siblings) for groceries and
/// toiletries that general UPC databases miss. Free, no key.
public struct OpenFoodFactsClient: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    static let hosts = ["world.openfoodfacts.org", "world.openbeautyfacts.org", "world.openproductsfacts.org"]

    public func lookup(gtin: String) async throws -> Product {
        for host in Self.hosts {
            let url = URL(string: "https://\(host)/api/v2/product/\(gtin).json?fields=code,product_name,brands,image_front_url,categories,quantity,generic_name")!
            guard let (data, response) = try? await http.data(for: .get(url)), response.statusCode == 200 else { continue }
            guard let decoded = try? JSONDecoder().decode(Envelope.self, from: data), decoded.status == 1, let p = decoded.product,
                  let name = p.product_name?.nonEmpty ?? p.generic_name?.nonEmpty else { continue }
            let title = [name, p.quantity.flatMap(Self.cleanQuantity)].compactMap { $0 }.joined(separator: " · ")
            return Product(
                gtin: GTIN.normalize(p.code ?? gtin) ?? gtin,
                title: title,
                brand: p.brands?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) },
                category: p.categories?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) },
                imageURLs: p.image_front_url.flatMap(URL.init(string:)).map { [$0] } ?? [],
                source: .openFoodFacts
            )
        }
        throw LookupError.notFound
    }

    /// "400 g e" / "400 g ℮" → "400 g".
    static func cleanQuantity(_ raw: String) -> String? {
        var q = raw.replacingOccurrences(of: "℮", with: "").trimmingCharacters(in: .whitespaces)
        if q.hasSuffix(" e") { q.removeLast(2) }
        return q.nonEmpty
    }

    struct Envelope: Decodable {
        var status: Int?
        var product: Item?
    }

    struct Item: Decodable {
        var code: String?
        var product_name: String?
        var generic_name: String?
        var brands: String?
        var image_front_url: String?
        var categories: String?
        var quantity: String?
    }
}

/// Open Prices: crowd-sourced shelf prices from real shops, perfect for
/// "is this a good price in store?" on everyday items.
public struct OpenPricesClient: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public func recentPrices(gtin: String, currency: String?, countryCode: String?, limit: Int = 40) async throws -> [Offer] {
        var components = URLComponents(string: "https://prices.openfoodfacts.org/api/v1/prices")!
        var query = [
            URLQueryItem(name: "product_code", value: gtin),
            URLQueryItem(name: "order_by", value: "-date"),
            URLQueryItem(name: "size", value: String(limit)),
        ]
        if let currency { query.append(URLQueryItem(name: "currency", value: currency.uppercased())) }
        components.queryItems = query
        let (data, response) = try await http.data(for: .get(components.url!))
        guard response.statusCode == 200 else { throw LookupError.badResponse }
        let decoded = try JSONDecoder().decode(Page.self, from: data)
        let wantedCountry = countryCode?.uppercased()
        return decoded.items.compactMap { item in
            guard let price = item.price, price > 0, let currency = item.currency else { return nil }
            if let wantedCountry, let country = item.location?.osm_address_country_code?.uppercased() {
                // Open Prices uses "GB" while our region uses "gb"; both upper-cased here.
                if country != wantedCountry { return nil }
            }
            let shop = item.location?.osm_brand?.nonEmpty ?? item.location?.osm_name?.nonEmpty ?? "Local shop"
            return Offer(
                id: "op-\(item.id)",
                merchant: shop,
                title: item.product_name,
                price: price,
                shipping: 0,
                currency: currency,
                condition: .new,
                channel: .inStore,
                updatedAt: item.date.flatMap(Self.parseDay),
                location: item.location?.osm_address_city,
                source: "openprices"
            )
        }
    }

    /// Parses "yyyy-MM-dd" as a UTC date.
    static func parseDay(_ s: String) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    struct Page: Decodable {
        var items: [Item]
    }

    struct Item: Decodable {
        var id: Int
        var price: Double?
        var currency: String?
        var date: String?
        var product_name: String?
        var location: Location?
    }

    struct Location: Decodable {
        var osm_name: String?
        var osm_brand: String?
        var osm_address_city: String?
        var osm_address_country_code: String?
    }
}
