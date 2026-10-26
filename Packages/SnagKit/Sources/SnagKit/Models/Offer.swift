import Foundation

/// One seller's price for a product.
public struct Offer: Codable, Hashable, Sendable, Identifiable {
    public enum Condition: String, Codable, Sendable, CaseIterable {
        case new, used, refurbished, unknown
    }

    public enum Channel: String, Codable, Sendable {
        /// Buyable online with a link.
        case online
        /// Crowd-sourced shelf price from a physical shop.
        case inStore
    }

    public var id: String
    public var merchant: String
    public var merchantDomain: String?
    public var title: String?
    public var price: Double
    /// `nil` when unknown, `0` when free.
    public var shipping: Double?
    public var currency: String
    public var url: URL?
    public var condition: Condition
    public var channel: Channel
    public var inStock: Bool?
    public var updatedAt: Date?
    public var location: String?
    public var source: String

    public init(
        id: String = UUID().uuidString,
        merchant: String,
        merchantDomain: String? = nil,
        title: String? = nil,
        price: Double,
        shipping: Double? = nil,
        currency: String,
        url: URL? = nil,
        condition: Condition = .new,
        channel: Channel = .online,
        inStock: Bool? = nil,
        updatedAt: Date? = nil,
        location: String? = nil,
        source: String
    ) {
        self.id = id
        self.merchant = merchant
        self.merchantDomain = merchantDomain.map(Offer.normalizedDomain)
        self.title = title
        self.price = price
        self.shipping = shipping
        self.currency = currency
        self.url = url
        self.condition = condition
        self.channel = channel
        self.inStock = inStock
        self.updatedAt = updatedAt
        self.location = location
        self.source = source
    }

    /// Price including known delivery cost.
    public var totalPrice: Double { price + (shipping ?? 0) }

    /// Days since the source last saw this price, if known.
    public func ageInDays(now: Date = .now) -> Double? {
        updatedAt.map { now.timeIntervalSince($0) / 86_400 }
    }

    public static func normalizedDomain(_ raw: String) -> String {
        var d = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: d), let host = url.host { d = host }
        for prefix in ["https://", "http://", "www.", "m."] where d.hasPrefix(prefix) {
            d.removeFirst(prefix.count)
        }
        if let slash = d.firstIndex(of: "/") { d = String(d[..<slash]) }
        return d
    }
}

/// A dated observation of a product's best available price.
public struct PricePoint: Codable, Hashable, Sendable {
    public var date: Date
    public var price: Double
    public var merchant: String?

    public init(date: Date, price: Double, merchant: String? = nil) {
        self.date = date
        self.price = price
        self.merchant = merchant
    }
}
