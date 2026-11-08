import Foundation

/// Strava's `sport_type` (e.g. "Run", "TrailRun", "GravelRide"). Kept as the raw
/// string so new sport types Strava adds still decode.
public struct Sport: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let run = Sport("Run")
    public static let trailRun = Sport("TrailRun")
    public static let virtualRun = Sport("VirtualRun")
    public static let ride = Sport("Ride")
    public static let virtualRide = Sport("VirtualRide")
    public static let gravelRide = Sport("GravelRide")
    public static let mountainBikeRide = Sport("MountainBikeRide")
    public static let swim = Sport("Swim")
    public static let walk = Sport("Walk")
    public static let hike = Sport("Hike")
    public static let weightTraining = Sport("WeightTraining")
    public static let yoga = Sport("Yoga")
    public static let workout = Sport("Workout")
    public static let rowing = Sport("Rowing")
    public static let alpineSki = Sport("AlpineSki")

    public var description: String { rawValue }

    public var family: SportFamily {
        switch rawValue {
        case "Run", "TrailRun", "VirtualRun": .run
        case "Ride", "VirtualRide", "MountainBikeRide", "GravelRide", "EBikeRide", "EMountainBikeRide", "Velomobile", "Handcycle": .ride
        case "Swim": .swim
        case "Walk", "Hike", "Snowshoe", "Wheelchair": .walk
        case "AlpineSki", "BackcountrySki", "NordicSki", "Snowboard", "RollerSki", "IceSkate", "InlineSkate", "Skateboard": .glide
        case "Rowing", "VirtualRow", "Kayaking", "Canoeing", "StandUpPaddling", "Surfing", "Kitesurf", "Windsurf", "Sail": .water
        case "WeightTraining", "Crossfit", "HighIntensityIntervalTraining", "Workout", "Elliptical", "StairStepper", "Pilates", "Yoga", "PhysicalTherapy": .gym
        default: .other
        }
    }

    /// Distance-based sports, where km and pace make sense.
    public var isDistanceSport: Bool {
        switch family {
        case .run, .ride, .swim, .walk, .water, .glide: true
        case .gym, .other: false
        }
    }

    /// "Trail run", "Gravel ride", "Weight training"…
    public var displayName: String {
        switch rawValue {
        case "TrailRun": return "Trail run"
        case "VirtualRun": return "Treadmill run"
        case "VirtualRide": return "Indoor ride"
        case "MountainBikeRide": return "Mountain bike ride"
        case "GravelRide": return "Gravel ride"
        case "EBikeRide": return "E-bike ride"
        case "EMountainBikeRide": return "E-MTB ride"
        case "WeightTraining": return "Weight training"
        case "HighIntensityIntervalTraining": return "HIIT"
        case "AlpineSki": return "Ski"
        case "BackcountrySki": return "Backcountry ski"
        case "NordicSki": return "Nordic ski"
        case "StandUpPaddling": return "Paddleboard"
        case "RockClimbing": return "Climb"
        case "StairStepper": return "Stair stepper"
        case "VirtualRow": return "Indoor row"
        case "IceSkate": return "Ice skate"
        case "InlineSkate": return "Inline skate"
        default:
            // Split CamelCase: "TableTennis" → "Table tennis".
            var out = ""
            for (i, ch) in rawValue.enumerated() {
                if i > 0, ch.isUppercase { out.append(" ") ; out.append(Character(ch.lowercased())) } else { out.append(ch) }
            }
            return out
        }
    }

    /// Verb for sentences: "you ran", "you rode", "you swam".
    public var pastVerb: String {
        switch family {
        case .run: "ran"
        case .ride: "rode"
        case .swim: "swam"
        case .walk: rawValue == "Hike" ? "hiked" : "walked"
        case .water: rawValue == "Rowing" || rawValue == "VirtualRow" ? "rowed" : "paddled"
        case .glide: rawValue.contains("Ski") ? "skied" : "glided"
        case .gym, .other: "trained"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch rawValue {
        case "Run", "VirtualRun": return "figure.run"
        case "TrailRun": return "figure.run.circle"
        case "Ride", "GravelRide", "EBikeRide", "Velomobile": return "figure.outdoor.cycle"
        case "MountainBikeRide", "EMountainBikeRide": return "bicycle"
        case "VirtualRide": return "figure.indoor.cycle"
        case "Swim": return "figure.pool.swim"
        case "Walk": return "figure.walk"
        case "Hike", "Snowshoe": return "figure.hiking"
        case "Wheelchair", "Handcycle": return "figure.roll"
        case "AlpineSki", "BackcountrySki": return "figure.skiing.downhill"
        case "NordicSki", "RollerSki": return "figure.skiing.crosscountry"
        case "Snowboard": return "figure.snowboarding"
        case "IceSkate", "InlineSkate", "Skateboard": return "figure.skating"
        case "Rowing", "VirtualRow", "Canoeing", "Kayaking": return "figure.rower"
        case "Surfing", "Kitesurf", "Windsurf", "StandUpPaddling": return "figure.surfing"
        case "Sail": return "sailboat.fill"
        case "WeightTraining", "Crossfit": return "figure.strengthtraining.traditional"
        case "HighIntensityIntervalTraining": return "figure.highintensity.intervaltraining"
        case "Yoga": return "figure.yoga"
        case "Pilates": return "figure.pilates"
        case "Elliptical": return "figure.elliptical"
        case "StairStepper": return "figure.stair.stepper"
        case "RockClimbing": return "figure.climbing"
        case "Golf": return "figure.golf"
        case "Soccer": return "figure.soccer"
        case "Tennis", "Padel", "Pickleball", "Squash", "Badminton", "TableTennis", "Racquetball": return "figure.tennis"
        case "Basketball": return "figure.basketball"
        case "Volleyball": return "figure.volleyball"
        case "Dance": return "figure.dance"
        default: return family.symbol
        }
    }
}

/// Coarse groups used for filters, colours and the sport mix.
public enum SportFamily: String, CaseIterable, Codable, Sendable, Identifiable {
    case run, ride, swim, walk, water, glide, gym, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .run: "Run"
        case .ride: "Ride"
        case .swim: "Swim"
        case .walk: "Walk & hike"
        case .water: "Paddle & row"
        case .glide: "Snow & skate"
        case .gym: "Strength & mobility"
        case .other: "Other sports"
        }
    }

    public var shortTitle: String {
        switch self {
        case .run: "Run"
        case .ride: "Ride"
        case .swim: "Swim"
        case .walk: "Walk"
        case .water: "Water"
        case .glide: "Snow"
        case .gym: "Gym"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .run: "figure.run"
        case .ride: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .walk: "figure.hiking"
        case .water: "figure.rower"
        case .glide: "figure.skiing.downhill"
        case .gym: "figure.strengthtraining.traditional"
        case .other: "figure.mixed.cardio"
        }
    }

    /// Plural noun: "runs", "rides".
    public var noun: String {
        switch self {
        case .run: "runs"
        case .ride: "rides"
        case .swim: "swims"
        case .walk: "walks & hikes"
        case .water: "paddles"
        case .glide: "snow days"
        case .gym: "sessions"
        case .other: "sessions"
        }
    }

    /// Hue (0…1) so the app and exports colour sports consistently.
    public var hue: Double {
        switch self {
        case .run: 0.04
        case .ride: 0.58
        case .swim: 0.50
        case .walk: 0.30
        case .water: 0.62
        case .glide: 0.70
        case .gym: 0.83
        case .other: 0.12
        }
    }
}

/// Which activities a recap includes.
public enum SportFilter: Hashable, Codable, Sendable, Identifiable {
    case all
    case family(SportFamily)

    public var id: String {
        switch self {
        case .all: "all"
        case .family(let f): f.rawValue
        }
    }

    public var title: String {
        switch self {
        case .all: "All sports"
        case .family(let f): f.title
        }
    }

    public func includes(_ sport: Sport) -> Bool {
        switch self {
        case .all: true
        case .family(let f): sport.family == f
        }
    }
}
