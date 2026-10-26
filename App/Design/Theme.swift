import SwiftUI
import SnagKit

/// Visual language: deep indigo → teal brand gradient (matches the icon),
/// content on a softly moving mesh, controls and summaries in Liquid Glass.
enum Theme {
    static let indigo = Color(red: 0.24, green: 0.20, blue: 0.62)
    static let teal = Color(red: 0.10, green: 0.56, blue: 0.70)
    static let mint = Color(red: 0.30, green: 0.86, blue: 0.76)
    static let violet = Color(red: 0.55, green: 0.40, blue: 0.98)
    static let coral = Color(red: 1.00, green: 0.45, blue: 0.42)

    static let brandGradient = LinearGradient(colors: [indigo, teal, mint], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardRadius: CGFloat = 28
    static let chipRadius: CGFloat = 18

    static func color(for level: PriceVerdict.Level) -> Color {
        switch level {
        case .steal: mint
        case .great: .green
        case .good: teal
        case .fair: .orange
        case .high: coral
        case .unknown: .gray
        }
    }

    static func color(for archetype: Archetype) -> Color {
        Color(hue: archetype.hue, saturation: 0.62, brightness: 0.88)
    }
}

extension PriceVerdict.Level {
    var headline: String {
        switch self {
        case .steal: "Steal"
        case .great: "Great price"
        case .good: "Good price"
        case .fair: "Fair price"
        case .high: "Too high"
        case .unknown: "Not sure yet"
        }
    }

    var symbol: String {
        switch self {
        case .steal: "bolt.heart.fill"
        case .great: "checkmark.seal.fill"
        case .good: "hand.thumbsup.fill"
        case .fair: "equal.circle.fill"
        case .high: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

extension Double {
    /// Currency string with cents only when needed: $99.99, $120.
    func money(_ currency: String) -> String {
        let hasCents = (self * 100).rounded().truncatingRemainder(dividingBy: 100) != 0
        return formatted(.currency(code: currency).precision(.fractionLength(hasCents ? 2 : 0)))
    }

    var percentString: String {
        formatted(.percent.precision(.fractionLength(0)))
    }
}

extension Date {
    var relativeShort: String {
        formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
