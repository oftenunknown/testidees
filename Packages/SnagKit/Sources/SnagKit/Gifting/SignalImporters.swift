import Foundation

/// Reads the JSON files from Instagram's "Download your information" export.
/// The format changes often, so rather than decode fixed schemas we walk the
/// JSON and pull out the human-readable values Instagram stores in
/// `string_map_data` / `string_list_data` / `title` fields.
public enum InstagramExportParser {
    public struct Result: Sendable, Equatable {
        /// Instagram's own inferred topics ("your_topics"), the strongest signal.
        public var topics: [String]
        /// Accounts followed or liked — handles carry interest hints.
        public var accounts: [String]
        /// Other free-text values (saved collection names, captions).
        public var other: [String]

        public var all: [String] { topics + accounts + other }
    }

    public static func parse(files: [(name: String, data: Data)]) -> Result {
        var result = Result(topics: [], accounts: [], other: [])
        for file in files {
            guard let json = try? JSONSerialization.jsonObject(with: file.data) else { continue }
            let lowerName = file.name.lowercased()
            var values: [String] = []
            collect(json, into: &values)
            if lowerName.contains("topic") {
                result.topics += values
            } else if lowerName.contains("follow") || lowerName.contains("liked") || lowerName.contains("like") {
                result.accounts += values.filter(isHandle)
                result.other += values.filter { !isHandle($0) }
            } else {
                result.other += values
            }
        }
        result.topics = dedupe(result.topics)
        result.accounts = dedupe(result.accounts)
        result.other = dedupe(result.other).filter { $0.count <= 80 }
        return result
    }

    public static func interests(from result: Result) -> [WeightedInterest] {
        let signals: [(text: String, confidence: Double)] =
            result.topics.map { ($0, 1.0) } + result.accounts.map { ($0, 0.35) } + result.other.map { ($0, 0.2) }
        return InterestMatcher.interests(from: signals, source: .instagramExport)
    }

    static func collect(_ node: Any, into values: inout [String]) {
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                switch key {
                case "string_map_data":
                    if let map = value as? [String: Any] {
                        for (_, entry) in map {
                            if let e = entry as? [String: Any], let v = e["value"] as? String, isMeaningful(v) { values.append(v) }
                        }
                    }
                case "string_list_data":
                    if let list = value as? [[String: Any]] {
                        for e in list {
                            if let v = e["value"] as? String, isMeaningful(v) { values.append(v) }
                        }
                    }
                case "title", "name":
                    if let v = value as? String, isMeaningful(v) { values.append(v) }
                    else { collect(value, into: &values) }
                default:
                    collect(value, into: &values)
                }
            }
        } else if let array = node as? [Any] {
            for item in array { collect(item, into: &values) }
        }
    }

    static func isMeaningful(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, !t.hasPrefix("http") else { return false }
        return t.contains { $0.isLetter }
    }

    static func isHandle(_ s: String) -> Bool {
        !s.contains(" ") && s.count <= 30 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    }

    static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}

/// Reads order-history CSV exports (Amazon, eBay, Etsy and most shops) and
/// returns the product names, plus simple spending habits.
public enum OrderHistoryParser {
    public struct Result: Sendable, Equatable {
        public var productNames: [String]
        public var averageOrderValue: Double?
        public var orderCount: Int
    }

    static let nameHeaders = ["product name", "title", "item name", "item title", "product", "description", "item", "name"]
    static let priceHeaders = ["item total", "total owed", "unit price", "price", "total", "amount", "item subtotal"]

    public static func parse(csv: String) -> Result {
        let rows = parseCSV(csv)
        guard let header = rows.first else { return Result(productNames: [], averageOrderValue: nil, orderCount: 0) }
        let lowered = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        let nameIndex = nameHeaders.lazy.compactMap { h in lowered.firstIndex(of: h) ?? lowered.firstIndex { $0.contains(h) } }.first
        let priceIndex = priceHeaders.lazy.compactMap { h in lowered.firstIndex(of: h) ?? lowered.firstIndex { $0.contains(h) } }.first

        var names: [String] = []
        var prices: [Double] = []
        for row in rows.dropFirst() {
            if let i = nameIndex, i < row.count {
                let name = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { names.append(name) }
            }
            if let i = priceIndex, i < row.count, let p = parseAmount(row[i]), p > 0 {
                prices.append(p)
            }
        }
        let average = prices.isEmpty ? nil : prices.reduce(0, +) / Double(prices.count)
        return Result(productNames: names, averageOrderValue: average, orderCount: max(names.count, prices.count))
    }

    public static func interests(from result: Result) -> [WeightedInterest] {
        InterestMatcher.interests(from: result.productNames.map { ($0, 0.6) }, source: .orderHistory)
    }

    static func parseAmount(_ s: String) -> Double? {
        let cleaned = s.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned)
    }

    /// RFC 4180-ish CSV: quoted fields, escaped quotes, newlines in quotes.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = iterator.next()

        while let ch = pending {
            pending = iterator.next()
            if inQuotes {
                if ch == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
                continue
            }
            switch ch {
            case "\"": inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default:
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
