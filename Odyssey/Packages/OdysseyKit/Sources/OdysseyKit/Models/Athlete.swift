import Foundation

/// The signed-in athlete.
public struct Athlete: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64
    public var firstName: String
    public var lastName: String
    public var city: String?
    public var country: String?
    public var profileImageURL: URL?
    /// "meters" or "feet".
    public var measurementPreference: String?
    /// Kilograms.
    public var weight: Double?
    public var createdAt: Date?
    public var gear: [Gear]

    public init(
        id: Int64, firstName: String, lastName: String = "", city: String? = nil, country: String? = nil,
        profileImageURL: URL? = nil, measurementPreference: String? = nil, weight: Double? = nil,
        createdAt: Date? = nil, gear: [Gear] = []
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.city = city
        self.country = country
        self.profileImageURL = profileImageURL
        self.measurementPreference = measurementPreference
        self.weight = weight
        self.createdAt = createdAt
        self.gear = gear
    }

    public var displayName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public var prefersImperial: Bool { measurementPreference == "feet" }
}

/// Shoes or a bike.
public struct Gear: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case shoes, bike }

    public var id: String
    public var name: String
    public var kind: Kind
    /// Lifetime distance in metres, as Strava reports it.
    public var distance: Double

    public init(id: String, name: String, kind: Kind, distance: Double = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.distance = distance
    }
}
