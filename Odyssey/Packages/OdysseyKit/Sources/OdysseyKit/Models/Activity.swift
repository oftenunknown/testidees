import Foundation

/// One workout, normalised from Strava's SummaryActivity (and optionally its
/// DetailedActivity). Units are SI: metres, seconds, m/s.
public struct Activity: Hashable, Codable, Identifiable, Sendable {
    public var id: Int64
    public var name: String
    public var sport: Sport
    /// Real start instant.
    public var start: Date
    /// Wall-clock start as a floating date (see `LocalDay`).
    public var startLocal: Date
    public var timezone: String?
    public var distance: Double
    public var movingTime: Double
    public var elapsedTime: Double
    public var elevationGain: Double
    public var averageSpeed: Double?
    public var maxSpeed: Double?
    public var averageHeartrate: Double?
    public var maxHeartrate: Double?
    public var averageWatts: Double?
    public var kilojoules: Double?
    public var sufferScore: Double?
    public var kudos: Int
    public var comments: Int
    public var achievements: Int
    public var prCount: Int
    /// Athletes in the group activity, including you (1 = solo).
    public var athleteCount: Int
    public var photoCount: Int
    public var startCoordinate: Coordinate?
    public var endCoordinate: Coordinate?
    /// Google-encoded summary polyline.
    public var polyline: String?
    public var deviceName: String?
    public var gearID: String?
    public var isCommute: Bool
    public var isTrainer: Bool
    public var isManual: Bool
    public var isPrivate: Bool
    public var workoutType: Int?
    /// Filled in lazily from the detailed endpoint.
    public var details: ActivityDetails?

    public init(
        id: Int64, name: String, sport: Sport, start: Date, startLocal: Date, timezone: String? = nil,
        distance: Double, movingTime: Double, elapsedTime: Double? = nil, elevationGain: Double = 0,
        averageSpeed: Double? = nil, maxSpeed: Double? = nil, averageHeartrate: Double? = nil, maxHeartrate: Double? = nil,
        averageWatts: Double? = nil, kilojoules: Double? = nil, sufferScore: Double? = nil,
        kudos: Int = 0, comments: Int = 0, achievements: Int = 0, prCount: Int = 0, athleteCount: Int = 1, photoCount: Int = 0,
        startCoordinate: Coordinate? = nil, endCoordinate: Coordinate? = nil, polyline: String? = nil,
        deviceName: String? = nil, gearID: String? = nil, isCommute: Bool = false, isTrainer: Bool = false,
        isManual: Bool = false, isPrivate: Bool = false, workoutType: Int? = nil, details: ActivityDetails? = nil
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.start = start
        self.startLocal = startLocal
        self.timezone = timezone
        self.distance = distance
        self.movingTime = movingTime
        self.elapsedTime = elapsedTime ?? movingTime
        self.elevationGain = elevationGain
        self.averageSpeed = averageSpeed
        self.maxSpeed = maxSpeed
        self.averageHeartrate = averageHeartrate
        self.maxHeartrate = maxHeartrate
        self.averageWatts = averageWatts
        self.kilojoules = kilojoules
        self.sufferScore = sufferScore
        self.kudos = kudos
        self.comments = comments
        self.achievements = achievements
        self.prCount = prCount
        self.athleteCount = athleteCount
        self.photoCount = photoCount
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.polyline = polyline
        self.deviceName = deviceName
        self.gearID = gearID
        self.isCommute = isCommute
        self.isTrainer = isTrainer
        self.isManual = isManual
        self.isPrivate = isPrivate
        self.workoutType = workoutType
        self.details = details
    }

    public var day: LocalDay { LocalDay(startLocal) }
    public var startSecondsOfDay: Int { Floating.secondsOfDay(startLocal) }
    public var isGroup: Bool { athleteCount > 1 }

    /// Seconds per metre, for distance sports with real movement.
    public var pace: Double? {
        guard distance > 50, movingTime > 0 else { return nil }
        return movingTime / distance
    }

    /// Metres per second.
    public var speed: Double? {
        if let averageSpeed, averageSpeed > 0 { return averageSpeed }
        guard movingTime > 0, distance > 0 else { return nil }
        return distance / movingTime
    }

    /// Strava's race workout type for runs (1) and rides (11).
    public var isRace: Bool { workoutType == 1 || workoutType == 11 }

    /// Activities with a GPS route.
    public var hasRoute: Bool { !(polyline ?? "").isEmpty }

    /// The activity's description text, once details are fetched.
    public var notes: String? { details?.description }
}

/// Extra fields from `GET /activities/{id}`.
public struct ActivityDetails: Hashable, Codable, Sendable {
    public var description: String?
    public var calories: Double?
    public var bestEfforts: [BestEffort]
    public var fetchedAt: Date

    public init(description: String? = nil, calories: Double? = nil, bestEfforts: [BestEffort] = [], fetchedAt: Date = Date()) {
        self.description = description
        self.calories = calories
        self.bestEfforts = bestEfforts
        self.fetchedAt = fetchedAt
    }
}

/// A best effort Strava found inside a run (fastest 5K within it, etc.).
public struct BestEffort: Hashable, Codable, Sendable {
    public var name: String
    public var distance: Double
    public var elapsedTime: Double
    public var movingTime: Double
    /// 1 = PR when uploaded, 2 = second best, 3 = third best.
    public var prRank: Int?

    public init(name: String, distance: Double, elapsedTime: Double, movingTime: Double? = nil, prRank: Int? = nil) {
        self.name = name
        self.distance = distance
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime ?? elapsedTime
        self.prRank = prRank
    }

    public var standard: StandardDistance? { StandardDistance.matching(meters: distance) }
}

/// The distances Strava reports best efforts for.
public enum StandardDistance: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case m400, halfMile, k1, mile, twoMile, k5, k10, k15, tenMile, k20, half, k30, marathon, k50

    public var id: String { rawValue }

    public var meters: Double {
        switch self {
        case .m400: 400
        case .halfMile: 804.672
        case .k1: 1000
        case .mile: 1609.344
        case .twoMile: 3218.688
        case .k5: 5000
        case .k10: 10_000
        case .k15: 15_000
        case .tenMile: 16_093.44
        case .k20: 20_000
        case .half: 21_097.5
        case .k30: 30_000
        case .marathon: 42_195
        case .k50: 50_000
        }
    }

    public var title: String {
        switch self {
        case .m400: "400 m"
        case .halfMile: "½ mile"
        case .k1: "1K"
        case .mile: "1 mile"
        case .twoMile: "2 miles"
        case .k5: "5K"
        case .k10: "10K"
        case .k15: "15K"
        case .tenMile: "10 miles"
        case .k20: "20K"
        case .half: "Half marathon"
        case .k30: "30K"
        case .marathon: "Marathon"
        case .k50: "50K"
        }
    }

    /// The ones worth a headline in a recap.
    public var isHeadline: Bool {
        switch self {
        case .mile, .k5, .k10, .half, .marathon: true
        default: false
        }
    }

    public static func matching(meters: Double) -> StandardDistance? {
        allCases.first { abs($0.meters - meters) / $0.meters < 0.015 }
    }

    public static func < (lhs: StandardDistance, rhs: StandardDistance) -> Bool { lhs.meters < rhs.meters }
}
