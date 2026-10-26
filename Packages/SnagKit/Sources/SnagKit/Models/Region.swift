import Foundation

/// Shopping region. Drives currency, which discount programs apply and which
/// price sources are queried.
public enum Region: String, Codable, CaseIterable, Sendable, Identifiable {
    case us
    case uk
    case eu
    case other

    public var id: String { rawValue }

    public var currencyCode: String {
        switch self {
        case .us, .other: "USD"
        case .uk: "GBP"
        case .eu: "EUR"
        }
    }

    public var displayName: String {
        switch self {
        case .us: "United States"
        case .uk: "United Kingdom"
        case .eu: "Europe"
        case .other: "Elsewhere"
        }
    }

    /// Google-style country code used by shopping search back ends.
    public var countryCode: String {
        switch self {
        case .us, .other: "us"
        case .uk: "gb"
        case .eu: "de"
        }
    }

    /// Best guess from an ISO region identifier such as "GB" or "US".
    public init(regionIdentifier: String?) {
        switch regionIdentifier?.uppercased() {
        case "US", "PR", "CA": self = .us
        case "GB", "UK", "IE", "IM", "JE", "GG": self = .uk
        case "DE", "FR", "ES", "IT", "NL", "BE", "AT", "PT", "FI", "LU", "GR", "SK", "SI", "EE", "LV", "LT", "MT", "CY", "HR":
            self = .eu
        default: self = .other
        }
    }
}
