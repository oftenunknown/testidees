import Foundation

/// "That's Paris → New York, 1.2 times."
public struct DistanceEquivalent: Hashable, Codable, Sendable, Identifiable {
    public var journey: Journey
    /// Your distance divided by the journey's length.
    public var multiple: Double
    public var id: String { journey.id }

    /// Whole trips completed plus how far into the next one.
    public var completedTrips: Int { Int(multiple.rounded(.down)) }
    public var remainderFraction: Double { multiple - multiple.rounded(.down) }
}

public struct ClimbEquivalent: Hashable, Codable, Sendable, Identifiable {
    public var landmark: Landmark
    public var multiple: Double
    public var id: String { landmark.id }
}

public struct TimeEquivalent: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var emoji: String
    public var count: Double
}

public struct FoodEquivalent: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var emoji: String
    public var count: Double
}

public struct Equivalents: Hashable, Codable, Sendable {
    /// The journey for the map animation.
    public var headline: DistanceEquivalent?
    public var more: [DistanceEquivalent]
    /// Laps of a 400 m track, from running distance (or all foot distance).
    public var trackLaps: Double
    public var marathons: Double
    public var climb: ClimbEquivalent?
    public var climbMore: [ClimbEquivalent]
    public var time: [TimeEquivalent]
    public var food: [FoodEquivalent]
}

public enum EquivalentFinder {
    /// Picks the journey that best tells the story of `km`: ideally one you've
    /// just completed (1–1.5×), otherwise one you've almost finished.
    public static func headline(forKm km: Double) -> DistanceEquivalent? {
        guard km > 0 else { return nil }
        // Long distances get map-worthy trips; short ones anything on Earth.
        let pool = km >= 200
            ? JourneyCatalog.all.filter { $0.isMappable || $0.kind == .planet }
            : JourneyCatalog.all.filter { $0.kind != .space }
        func score(_ j: Journey) -> Double {
            let m = km / j.lengthKm
            var s = abs(log(m) - log(1.15))
            if m < 1 { s += 0.1 }          // finishing beats almost finishing
            if m < 0.85 { s += 1 }          // "40% of the way" is a weaker story
            return s
        }
        guard let best = pool.min(by: { score($0) < score($1) }) else { return nil }
        return DistanceEquivalent(journey: best, multiple: km / best.lengthKm)
    }

    /// A second and third comparison of a different flavour than the headline.
    static func more(forKm km: Double, excluding headline: Journey?, family: SportFamily?) -> [DistanceEquivalent] {
        guard km > 0 else { return [] }
        var out: [DistanceEquivalent] = []
        let historic: Set<Journey.Kind> = [.voyage, .road, .trail, .rail]
        // Closest historic route (on a log scale) to 1×.
        let candidates = JourneyCatalog.all.filter { historic.contains($0.kind) && $0.id != headline?.id }
        if let best = candidates.min(by: { abs(log(km / $0.lengthKm)) < abs(log(km / $1.lengthKm)) }) {
            out.append(DistanceEquivalent(journey: best, multiple: km / best.lengthKm))
        }
        // Something small, repeated: Channel crossings for swimmers, Manhattans otherwise.
        let smallID = family == .swim ? "channel" : "manhattan"
        if let small = JourneyCatalog.journey(smallID), small.id != headline?.id, km >= small.lengthKm * 2 {
            out.append(DistanceEquivalent(journey: small, multiple: km / small.lengthKm))
        }
        // The Moon, for scale.
        if km >= 300, let moon = JourneyCatalog.journey("moon") {
            out.append(DistanceEquivalent(journey: moon, multiple: km / moon.lengthKm))
        }
        return out
    }

    public static func climb(forMeters meters: Double) -> (ClimbEquivalent?, [ClimbEquivalent]) {
        guard meters > 0 else { return (nil, []) }
        let all = Landmark.all
        // Prefer Everest once you've climbed it; otherwise the tallest thing you've topped.
        let everest = all.first { $0.id == "everest" }!
        let main: Landmark
        if meters >= everest.heightMeters {
            main = everest
        } else {
            main = all.filter { $0.kind != .sky && $0.heightMeters <= meters }.max(by: { $0.heightMeters < $1.heightMeters })
                ?? all.min(by: { $0.heightMeters < $1.heightMeters })!
        }
        var more: [ClimbEquivalent] = []
        if let eiffel = all.first(where: { $0.id == "eiffel" }), main.id != "eiffel" {
            more.append(ClimbEquivalent(landmark: eiffel, multiple: meters / eiffel.heightMeters))
        }
        if meters >= 2000, main.id != "everest" {
            more.append(ClimbEquivalent(landmark: everest, multiple: meters / everest.heightMeters))
        }
        if let space = all.first(where: { $0.id == "space" }), meters >= 5000 {
            more.append(ClimbEquivalent(landmark: space, multiple: meters / space.heightMeters))
        }
        return (ClimbEquivalent(landmark: main, multiple: meters / main.heightMeters), more)
    }

    public static func time(forSeconds seconds: Double) -> [TimeEquivalent] {
        guard seconds > 0 else { return [] }
        let hours = seconds / 3600
        var out: [TimeEquivalent] = []
        if hours >= 24 {
            out.append(TimeEquivalent(id: "days", label: "full days, non-stop", emoji: "☀️", count: hours / 24))
        }
        out.append(TimeEquivalent(id: "football", label: "football matches", emoji: "⚽️", count: hours / 1.5))
        out.append(TimeEquivalent(id: "films", label: "feature films", emoji: "🍿", count: hours / 2))
        if hours >= 8 {
            out.append(TimeEquivalent(id: "flights", label: "Paris → New York flights", emoji: "✈️", count: hours / 8))
        }
        return out
    }

    public static func food(forKcal kcal: Double) -> [FoodEquivalent] {
        guard kcal > 0 else { return [] }
        return [
            FoodEquivalent(id: "pizza", label: "slices of pizza", emoji: "🍕", count: kcal / 285),
            FoodEquivalent(id: "croissant", label: "croissants", emoji: "🥐", count: kcal / 230),
            FoodEquivalent(id: "banana", label: "bananas", emoji: "🍌", count: kcal / 105),
        ]
    }

    public static func all(for totals: Totals, family: SportFamily?) -> Equivalents {
        let km = totals.distance / 1000
        let headline = headline(forKm: km)
        let lapsBase = totals.runDistance > 0 ? totals.runDistance : totals.footDistance
        let (climb, climbMore) = climb(forMeters: totals.elevationGain)
        return Equivalents(
            headline: headline,
            more: more(forKm: km, excluding: headline?.journey, family: family),
            trackLaps: lapsBase / 400,
            marathons: (totals.runDistance > 0 ? totals.runDistance : totals.distance) / StandardDistance.marathon.meters,
            climb: climb,
            climbMore: climbMore,
            time: time(forSeconds: totals.movingTime),
            food: food(forKcal: totals.energy)
        )
    }
}
