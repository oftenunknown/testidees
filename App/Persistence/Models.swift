import Foundation
import SwiftData
import SnagKit

/// JSON helpers so SwiftData can store SnagKit value types as blobs.
/// Blobs keep the schema stable while the value types evolve.
nonisolated enum Blob {
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

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

/// Something the user is watching or wants.
@Model
final class WishItem {
    @Attribute(.unique) var productID: String
    var title: String
    var brand: String?
    var imageURLString: String?
    var gtin: String?
    var productData: Data
    var offersData: Data
    var historyData: Data
    var alertData: Data?
    var bestPrice: Double?
    var bestMerchant: String?
    var bestURLString: String?
    var currency: String
    /// Best price when first added; drops are shown relative to it.
    var addedPrice: Double?
    var createdAt: Date
    var lastCheckedAt: Date?
    var lastAlertAt: Date?
    var note: String
    var recipientID: UUID?
    var isPurchased: Bool

    init(product: Product, offers: [Offer], currency: String, alert: PriceAlertRule? = nil, recipientID: UUID? = nil) {
        productID = product.id
        title = product.title
        brand = product.brand
        imageURLString = product.imageURLs.first?.absoluteString
        gtin = product.gtin
        productData = Blob.encode(product)
        offersData = Blob.encode(offers)
        historyData = Blob.encode([PricePoint]())
        alertData = alert.map(Blob.encode)
        self.currency = currency
        createdAt = .now
        note = ""
        self.recipientID = recipientID
        isPurchased = false
        apply(offers: offers, at: .now)
        addedPrice = bestPrice
    }

    var product: Product {
        get { Blob.decode(Product.self, from: productData) ?? Product(id: productID, title: title, source: .manual) }
        set {
            productData = Blob.encode(newValue)
            title = newValue.title
            brand = newValue.brand
            imageURLString = newValue.imageURLs.first?.absoluteString ?? imageURLString
        }
    }

    var offers: [Offer] {
        get { Blob.decode([Offer].self, from: offersData) ?? [] }
        set { offersData = Blob.encode(newValue) }
    }

    var history: [PricePoint] {
        get { Blob.decode([PricePoint].self, from: historyData) ?? [] }
        set { historyData = Blob.encode(newValue) }
    }

    var alert: PriceAlertRule? {
        get { Blob.decode(PriceAlertRule.self, from: alertData) }
        set { alertData = newValue.map(Blob.encode) }
    }

    var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }

    /// Fraction below the price when added (positive = cheaper now).
    var dropSinceAdded: Double? {
        guard let addedPrice, let bestPrice, addedPrice > 0 else { return nil }
        let d = (addedPrice - bestPrice) / addedPrice
        return abs(d) < 0.005 ? nil : d
    }

    /// Updates offers, best price and history from a fresh lookup.
    func apply(offers newOffers: [Offer], at date: Date) {
        guard !newOffers.isEmpty else {
            lastCheckedAt = date
            return
        }
        offers = newOffers
        let comparable = PriceAnalyzer.comparableOffers(newOffers.filter { $0.channel == .online }, currency: currency)
        if let best = comparable.min(by: { $0.totalPrice < $1.totalPrice }) {
            bestPrice = best.totalPrice
            bestMerchant = best.merchant
            bestURLString = best.url?.absoluteString
            history = PriceHistory.appending(PricePoint(date: date, price: best.totalPrice, merchant: best.merchant), to: history)
        }
        lastCheckedAt = date
    }
}

/// Someone the user buys for, plus their latest ideas.
@Model
final class RecipientRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var profileData: Data
    var ideasData: Data
    var savedIdeasData: Data
    var occasionDate: Date?
    var updatedAt: Date
    var ideasGeneratedAt: Date?

    init(profile: RecipientProfile) {
        id = profile.id
        name = profile.name
        profileData = Blob.encode(profile)
        ideasData = Blob.encode([GiftIdea]())
        savedIdeasData = Blob.encode([GiftIdea]())
        occasionDate = profile.occasionDate
        updatedAt = .now
    }

    var profile: RecipientProfile {
        get { Blob.decode(RecipientProfile.self, from: profileData) ?? RecipientProfile(id: id, name: name) }
        set {
            profileData = Blob.encode(newValue)
            name = newValue.name
            occasionDate = newValue.occasionDate
            updatedAt = .now
        }
    }

    var ideas: [GiftIdea] {
        get { Blob.decode([GiftIdea].self, from: ideasData) ?? [] }
        set { ideasData = Blob.encode(newValue) }
    }

    var savedIdeas: [GiftIdea] {
        get { Blob.decode([GiftIdea].self, from: savedIdeasData) ?? [] }
        set { savedIdeasData = Blob.encode(newValue) }
    }
}

/// A past scan, for "recent scans" and quick re-checks.
@Model
final class ScanRecord {
    var id: UUID
    var code: String?
    var title: String
    var imageURLString: String?
    var userPrice: Double?
    var bestPrice: Double?
    var currency: String
    var verdictRaw: String?
    var date: Date
    var productData: Data?

    init(product: Product, code: String?, userPrice: Double?, bestPrice: Double?, currency: String, verdict: PriceVerdict.Level?) {
        id = UUID()
        self.code = code
        title = product.title
        imageURLString = product.imageURLs.first?.absoluteString
        self.userPrice = userPrice
        self.bestPrice = bestPrice
        self.currency = currency
        verdictRaw = verdict?.rawValue
        date = .now
        productData = Blob.encode(product)
    }

    var verdict: PriceVerdict.Level? { verdictRaw.flatMap(PriceVerdict.Level.init(rawValue:)) }
    var product: Product? { Blob.decode(Product.self, from: productData) }
    var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }
}

enum SnagStore {
    static let schema = Schema([WishItem.self, RecipientRecord.self, ScanRecord.self])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // A corrupt or incompatible store shouldn't brick the app; start fresh in memory.
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
    }
}
