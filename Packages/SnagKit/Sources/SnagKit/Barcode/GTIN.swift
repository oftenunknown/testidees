import Foundation

/// Global Trade Item Number helpers: validation, UPC-E expansion and
/// normalisation so the same product scanned as UPC-A or EAN-13 matches.
public enum GTIN {
    /// Returns a validated GTIN (8, 12, 13 or 14 digits) or `nil`.
    /// UPC-E codes are expanded to UPC-A. Pass `isUPCE` when the scanner
    /// reported the symbology, since an 8-digit code can be valid as both.
    public static func normalize(_ raw: String, isUPCE: Bool = false) -> String? {
        let digits = raw.filter(\.isASCII).filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        if isUPCE, (6...8).contains(digits.count) {
            return expandUPCE(digits).flatMap { isValid($0) ? $0 : nil }
        }

        switch digits.count {
        case 8:
            if isValid(digits) { return digits } // EAN-8
            return expandUPCE(digits).flatMap { isValid($0) ? $0 : nil }
        case 6, 7:
            return expandUPCE(digits).flatMap { isValid($0) ? $0 : nil }
        case 12, 13, 14:
            return isValid(digits) ? digits : nil
        default:
            return nil
        }
    }

    /// 14-digit form used to compare codes regardless of how they were printed.
    public static func gtin14(_ code: String) -> String? {
        guard let n = normalize(code) else { return nil }
        return String(repeating: "0", count: 14 - n.count) + n
    }

    /// Two codes refer to the same item (e.g. UPC-A 012345678905 vs EAN-13 0012345678905).
    public static func sameItem(_ a: String, _ b: String) -> Bool {
        guard let x = gtin14(a), let y = gtin14(b) else { return false }
        return x == y
    }

    /// Mod-10 check digit validation used by all GTIN lengths.
    public static func isValid(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, [8, 12, 13, 14].contains(values.count) else { return false }
        return checkDigit(for: Array(values.dropLast())) == values.last
    }

    public static func checkDigit(for payload: [Int]) -> Int {
        var sum = 0
        for (offset, digit) in payload.reversed().enumerated() {
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    /// Expands a UPC-E code (6, 7 or 8 digits) to its 12-digit UPC-A form.
    public static func expandUPCE(_ code: String) -> String? {
        var digits = code.compactMap(\.wholeNumberValue)
        var numberSystem = 0
        var check: Int?

        switch digits.count {
        case 6: break
        case 7:
            numberSystem = digits.removeFirst()
        case 8:
            numberSystem = digits.removeFirst()
            check = digits.removeLast()
        default:
            return nil
        }
        guard numberSystem == 0 || numberSystem == 1, digits.count == 6 else { return nil }

        let d = digits
        let manufacturer: [Int]
        let product: [Int]
        switch d[5] {
        case 0, 1, 2:
            manufacturer = [d[0], d[1], d[5], 0, 0]
            product = [0, 0, d[2], d[3], d[4]]
        case 3:
            manufacturer = [d[0], d[1], d[2], 0, 0]
            product = [0, 0, 0, d[3], d[4]]
        case 4:
            manufacturer = [d[0], d[1], d[2], d[3], 0]
            product = [0, 0, 0, 0, d[4]]
        default:
            manufacturer = [d[0], d[1], d[2], d[3], d[4]]
            product = [0, 0, 0, 0, d[5]]
        }

        let payload = [numberSystem] + manufacturer + product
        let computed = checkDigit(for: payload)
        if let check, check != computed { return nil }
        return (payload + [computed]).map(String.init).joined()
    }

    /// Books carry EAN-13 codes starting 978/979.
    public static func isBook(_ code: String) -> Bool {
        guard let n = normalize(code), n.count == 13 else { return false }
        return n.hasPrefix("978") || n.hasPrefix("979")
    }

    /// Grocery-ish GS1 prefixes are a hint to try Open Food Facts first.
    /// Restricted-circulation (in-store) codes start with 02 or 2.
    public static func isInStoreCode(_ code: String) -> Bool {
        guard let n = normalize(code) else { return false }
        if n.count == 12 { return n.hasPrefix("2") }
        if n.count == 13 { return n.hasPrefix("02") || n.hasPrefix("2") }
        return false
    }
}
