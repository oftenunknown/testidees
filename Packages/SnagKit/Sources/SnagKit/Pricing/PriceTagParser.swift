import Foundation

/// Pulls the price a shopper is being asked to pay out of OCR'd shelf-tag text.
public enum PriceTagParser {
    public struct Candidate: Hashable, Sendable {
        public var amount: Double
        public var currency: String?
        /// Higher is more likely to be the price that matters.
        public var score: Double
        public var raw: String
    }

    /// Best guess at the shelf price, preferring promotional "now" prices
    /// over "was" prices and ignoring per-unit prices.
    public static func bestPrice(in text: String, defaultCurrency: String) -> Candidate? {
        candidates(in: text, defaultCurrency: defaultCurrency).first
    }

    public static func candidates(in text: String, defaultCurrency: String) -> [Candidate] {
        var results: [Candidate] = []
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        for line in lines where !line.isEmpty {
            let lower = line.lowercased()
            for match in matches(in: line) {
                var score = 1.0
                if match.currency != nil { score += 2 }
                if match.hasDecimals { score += 1 }
                if lower.contains("now") || lower.contains("only") || lower.contains("sale") || lower.contains("offer") { score += 1.5 }
                if lower.contains("was") || lower.contains("rrp") || lower.contains("msrp") || lower.contains("reg") { score -= 2.5 }
                if lower.contains("save") { score -= 2 }
                if isUnitPrice(lower, after: match.range, in: line) { score -= 4 }
                if match.amount < 0.05 || match.amount > 100_000 { score -= 10 }
                results.append(Candidate(
                    amount: match.amount,
                    currency: match.currency ?? defaultCurrency,
                    score: score,
                    raw: String(line[match.range])
                ))
            }
        }
        return results.sorted { $0.score == $1.score ? $0.amount > $1.amount : $0.score > $1.score }
    }

    struct Match {
        var amount: Double
        var currency: String?
        var hasDecimals: Bool
        var range: Range<String.Index>
    }

    static let symbolMap: [String: String] = ["$": "USD", "£": "GBP", "€": "EUR", "¥": "JPY"]

    static func matches(in line: String) -> [Match] {
        var found: [Match] = []
        // Optional currency symbol, number with optional thousands separators and
        // 2-digit decimals (dot or comma), optional trailing symbol or "p" for pence.
        let pattern = #"([$£€¥])?\s?(\d{1,3}(?:[,.\s]\d{3})*|\d+)(?:([.,])(\d{2}))?\s?([$£€¥]|p\b|USD|GBP|EUR)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = line as NSString
        for result in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            guard let whole = Range(result.range, in: line) else { continue }
            func group(_ i: Int) -> String? {
                let r = result.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            let leading = group(1)
            let integer = group(2) ?? ""
            let decimals = group(4)
            let trailing = group(5)

            let integerDigits = integer.filter(\.isNumber)
            guard let intValue = Double(integerDigits) else { continue }
            var amount = intValue
            if let decimals, let d = Double(decimals) { amount += d / 100 }

            var currency: String?
            if let leading { currency = symbolMap[leading] }
            if let trailing {
                let t = trailing.uppercased()
                if t == "P" {
                    // "99p" means pence.
                    if decimals == nil { amount = intValue / 100 }
                    currency = "GBP"
                } else {
                    currency = symbolMap[trailing] ?? t
                }
            }
            // Bare integers without a currency are usually quantities, sizes or codes.
            if currency == nil && decimals == nil { continue }
            found.append(Match(amount: amount, currency: currency, hasDecimals: decimals != nil, range: whole))
        }
        return found
    }

    static func isUnitPrice(_ lowerLine: String, after range: Range<String.Index>, in line: String) -> Bool {
        let tail = line[range.upperBound...].lowercased().prefix(14)
        let markers = ["/kg", "/100g", "/l", "/ml", "/100ml", "per kg", "per 100", "per l", "/ea", "per each", "/lb", "/oz", "per lb", "per oz", "/ct", "per ct"]
        if markers.contains(where: { tail.trimmingCharacters(in: .whitespaces).hasPrefix($0) }) { return true }
        return lowerLine.contains("unit price") || lowerLine.contains("price per")
    }
}
