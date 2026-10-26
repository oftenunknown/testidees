import Foundation

/// A product we can price. Identified by GTIN when we know it, otherwise by a
/// stable slug of its title so keyword-only finds can still be watched.
public struct Product: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var gtin: String?
    public var title: String
    public var brand: String?
    public var model: String?
    public var category: String?
    public var summary: String?
    public var imageURLs: [URL]
    public var source: Source
    /// Lowest/highest price the data source has ever recorded, if it tracks that.
    public var recordedLow: Double?
    public var recordedHigh: Double?

    public enum Source: String, Codable, Sendable {
        case upcItemDB, openFoodFacts, backend, manual, ai, demo
    }

    public init(
        id: String? = nil,
        gtin: String? = nil,
        title: String,
        brand: String? = nil,
        model: String? = nil,
        category: String? = nil,
        summary: String? = nil,
        imageURLs: [URL] = [],
        source: Source,
        recordedLow: Double? = nil,
        recordedHigh: Double? = nil
    ) {
        self.id = id ?? gtin ?? Product.slug(for: title)
        self.gtin = gtin
        self.title = title
        self.brand = brand
        self.model = model
        self.category = category
        self.summary = summary
        self.imageURLs = imageURLs
        self.source = source
        self.recordedLow = recordedLow
        self.recordedHigh = recordedHigh
    }

    /// Query string that gives shopping search the best chance of matching
    /// the exact item rather than accessories for it.
    public var searchQuery: String {
        var parts: [String] = []
        if let brand, !title.localizedCaseInsensitiveContains(brand) { parts.append(brand) }
        parts.append(title)
        if let model, !model.isEmpty, !title.localizedCaseInsensitiveContains(model) { parts.append(model) }
        return parts.joined(separator: " ")
    }

    /// Top-level category, e.g. "Electronics" from "Electronics > Audio > Headphones".
    public var rootCategory: String? {
        guard let category else { return nil }
        let first = category.split(separator: ">").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return first?.isEmpty == false ? first : nil
    }

    public static func slug(for title: String) -> String {
        let allowed = title.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let collapsed = String(allowed).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return "q-" + String(collapsed.prefix(80))
    }
}
