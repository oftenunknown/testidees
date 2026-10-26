import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SnagKit

/// Serves canned responses keyed by URL host+path.
struct StubHTTP: HTTPClient {
    var routes: [String: (Int, String)]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let key = (url.host ?? "") + url.path
        guard let (status, body) = routes.first(where: { key.hasPrefix($0.key) })?.value else {
            return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Networking")
struct NetworkingTests {
    static let upcBody = """
    {"code":"OK","total":1,"offset":0,"items":[{"ean":"0885909950805","title":"Apple iPhone 6, Space Gray, 64 GB","upc":"885909950805","brand":"Apple","model":"MG5A2LL/A","category":"Electronics > Phones","currency":"","lowest_recorded_price":3.79,"highest_recorded_price":8500,"images":["http://img.example.com/a.jpg"],"offers":[
      {"merchant":"Newegg.com","domain":"newegg.com","title":"iPhone 6","currency":"","list_price":"","price":64.99,"shipping":"0.01","condition":"New","availability":"","link":"https://www.upcitemdb.com/norob/alink/?id=1","updated_t":1648599067},
      {"merchant":"Rakuten","domain":"rakuten.com","title":"iPhone 6","currency":"","list_price":"","price":299.99,"shipping":"Free Shipping","condition":"New","availability":"","link":"https://www.upcitemdb.com/norob/alink/?id=2","updated_t":1498082079},
      {"merchant":"eBay","domain":"ebay.com","title":"iPhone 6 used","currency":"","list_price":"","price":"55.00","shipping":"","condition":"Used","availability":"Out of stock","link":"https://www.upcitemdb.com/norob/alink/?id=3","updated_t":1498082079}
    ]}]}
    """

    @Test func decodesUPCItemDB() async throws {
        let client = UPCItemDBClient(http: StubHTTP(routes: ["api.upcitemdb.com/prod/trial/lookup": (200, Self.upcBody)]))
        let result = try await client.lookup(gtin: "885909950805")
        #expect(result.product.title.hasPrefix("Apple iPhone 6"))
        #expect(result.product.gtin == "885909950805")
        #expect(result.product.imageURLs.first?.scheme == "https")
        #expect(result.offers.count == 3)
        #expect(result.offers[0].shipping == 0.01)
        #expect(result.offers[1].shipping == 0)
        #expect(result.offers[2].price == 55)
        #expect(result.offers[2].condition == .used)
        #expect(result.offers[2].inStock == false)
        #expect(result.offers.allSatisfy { $0.currency == "USD" })
    }

    @Test func rateLimitIsReported() async {
        let client = UPCItemDBClient(http: StubHTTP(routes: ["api.upcitemdb.com": (429, #"{"code":"TOO_FAST","message":"slow down"}"#)]))
        await #expect(throws: LookupError.self) { try await client.lookup(gtin: "885909950805") }
    }

    @Test func fallsBackToOpenFoodFacts() async throws {
        let food = #"{"code":"3017620422003","product":{"product_name":"Nutella","brands":"Nutella, Ferrero","quantity":"400 g e","image_front_url":"https://images.openfoodfacts.org/x.jpg"},"status":1}"#
        let prices = #"{"items":[{"id":1,"price":3.5,"currency":"GBP","date":"2026-10-06","product_name":"NUTELLA","location":{"osm_name":"Tesco Express","osm_brand":"Tesco","osm_address_city":"London","osm_address_country_code":"GB"}},{"id":2,"price":4.45,"currency":"GBP","date":"2026-10-01","location":{"osm_name":"Carrefour","osm_address_country_code":"FR"}}]}"#
        let http = StubHTTP(routes: [
            "api.upcitemdb.com": (200, #"{"code":"OK","total":0,"items":[]}"#),
            "world.openfoodfacts.org": (200, food),
            "prices.openfoodfacts.org": (200, prices),
        ])
        let service = PriceSearchService(upc: .init(http: http), food: .init(http: http), openPrices: .init(http: http))
        let result = try await service.lookup(code: "3017620422003", region: .uk)
        #expect(result.product.title == "Nutella · 400 g")
        #expect(result.product.brand == "Nutella")
        #expect(result.offers.count == 1)
        #expect(result.offers.first?.merchant == "Tesco")
        #expect(result.offers.first?.channel == .inStore)
        #expect(result.offers.first?.updatedAt != nil)
    }

    @Test func rejectsInvalidBarcodes() async {
        let service = PriceSearchService(upc: .init(http: StubHTTP(routes: [:])))
        await #expect(throws: LookupError.invalidCode) { try await service.lookup(code: "123", region: .us) }
    }

    @Test func dedupeKeepsCheapestPerMerchant() {
        let offers = [
            Offer(id: "a", merchant: "Amazon", merchantDomain: "amazon.com", price: 20, currency: "USD", source: "x"),
            Offer(id: "b", merchant: "Amazon", merchantDomain: "amazon.com", price: 18, currency: "USD", source: "y"),
            Offer(id: "c", merchant: "Target", merchantDomain: "target.com", price: 19, currency: "USD", source: "x"),
        ]
        let deduped = PriceSearchService.dedupe(offers)
        #expect(deduped.map(\.id) == ["b", "c"])
    }

    @Test func refreshesNameOnlyProductsByTitleMatch() async {
        let body = """
        {"code":"OK","total":2,"items":[
          {"title":"Sony WH-1000XM6 Wireless Headphones Black","offers":[{"merchant":"Best Buy","domain":"bestbuy.com","price":329.99,"shipping":"Free Shipping","condition":"New"}]},
          {"title":"Ear pads for Sony headphones","offers":[{"merchant":"eBay","domain":"ebay.com","price":12.0,"condition":"New"}]}
        ]}
        """
        let service = PriceSearchService(upc: .init(http: StubHTTP(routes: ["api.upcitemdb.com/prod/trial/search": (200, body)])))
        let product = Product(title: "Sony WH-1000XM6 Wireless Headphones", source: .upcItemDB)
        let offers = await service.refreshOffers(for: product, region: .us)
        #expect(offers.map(\.merchant) == ["Best Buy"])

        let unrelated = Product(title: "Garden hose 50ft", source: .upcItemDB)
        #expect(await service.refreshOffers(for: unrelated, region: .us).isEmpty)
    }

    @Test func backendRoundTripsDates() throws {
        let rule = PriceAlertRule(trigger: .percentDrop(0.1), baselinePrice: 100, currency: "USD", lastNotifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try SnagBackendClient.encoder.encode(rule)
        let back = try SnagBackendClient.decoder.decode(PriceAlertRule.self, from: data)
        #expect(back == rule)
    }
}
