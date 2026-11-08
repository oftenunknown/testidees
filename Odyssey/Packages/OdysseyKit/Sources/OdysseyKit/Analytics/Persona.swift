import Foundation

/// A playful "training personality" derived from when, how and with whom you move.
public enum Archetype: String, Codable, Sendable, CaseIterable, Identifiable {
    case dawnPatrol, nightOwl, lunchBreaker, weekendWarrior, metronome, mountainGoat
    case longHauler, socialButterfly, explorer, streaker, multisport, speedDemon, allRounder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dawnPatrol: "The Dawn Patrol"
        case .nightOwl: "The Night Owl"
        case .lunchBreaker: "The Lunch-Break Legend"
        case .weekendWarrior: "The Weekend Warrior"
        case .metronome: "The Metronome"
        case .mountainGoat: "The Mountain Goat"
        case .longHauler: "The Long Hauler"
        case .socialButterfly: "The Social Butterfly"
        case .explorer: "The Explorer"
        case .streaker: "The Streak Machine"
        case .multisport: "The Multisport Maverick"
        case .speedDemon: "The Speed Demon"
        case .allRounder: "The All-Rounder"
        }
    }

    public var tagline: String {
        switch self {
        case .dawnPatrol: "Out the door before the city wakes up."
        case .nightOwl: "Streetlights are your spotlights."
        case .lunchBreaker: "Meetings can wait. Miles can't."
        case .weekendWarrior: "Saturdays and Sundays are sacred."
        case .metronome: "Week in, week out — rock steady."
        case .mountainGoat: "Flat routes? Never heard of them."
        case .longHauler: "Why stop when you can keep going?"
        case .socialButterfly: "Better together, every time."
        case .explorer: "New streets, new trails, new places."
        case .streaker: "Rest days are a rumour."
        case .multisport: "Run, ride, swim — why choose?"
        case .speedDemon: "Faster every month."
        case .allRounder: "A bit of everything, done well."
        }
    }

    public var symbol: String {
        switch self {
        case .dawnPatrol: "sunrise.fill"
        case .nightOwl: "moon.stars.fill"
        case .lunchBreaker: "fork.knife"
        case .weekendWarrior: "calendar.badge.clock"
        case .metronome: "metronome.fill"
        case .mountainGoat: "mountain.2.fill"
        case .longHauler: "road.lanes"
        case .socialButterfly: "person.3.fill"
        case .explorer: "map.fill"
        case .streaker: "flame.fill"
        case .multisport: "figure.mixed.cardio"
        case .speedDemon: "bolt.fill"
        case .allRounder: "star.fill"
        }
    }

    /// Hue (0…1) for the persona card.
    public var hue: Double {
        switch self {
        case .dawnPatrol: 0.08
        case .nightOwl: 0.68
        case .lunchBreaker: 0.13
        case .weekendWarrior: 0.95
        case .metronome: 0.55
        case .mountainGoat: 0.30
        case .longHauler: 0.02
        case .socialButterfly: 0.88
        case .explorer: 0.45
        case .streaker: 0.04
        case .multisport: 0.75
        case .speedDemon: 0.15
        case .allRounder: 0.60
        }
    }
}

public struct Persona: Hashable, Codable, Sendable {
    public var primary: Archetype
    public var traits: [Archetype]
    /// Why: one line per archetype, e.g. "62% of starts before 8am".
    public var evidence: [String: String]

    public func reason(for archetype: Archetype) -> String? { evidence[archetype.rawValue] }
}

enum PersonaScorer {
    struct Inputs {
        var count: Int
        var rhythm: Rhythm
        var streaks: Streaks
        var weeksInRange: Int
        var activeWeeks: Int
        var weeklyDistanceCV: Double?
        var elevationPerKm: Double
        var averageRunKm: Double?
        var averageRideKm: Double?
        var groupShare: Double
        var startAreas: Int
        var familyShares: [SportFamily: Double]
        var paceImprovement: Double?
        var units: UnitSystem = .metric
    }

    static func persona(_ i: Inputs) -> Persona {
        var scores: [Archetype: Double] = [:]
        var evidence: [String: String] = [:]
        func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

        guard i.count >= 3 else {
            return Persona(primary: .allRounder, traits: [], evidence: [:])
        }
        scores[.dawnPatrol] = i.rhythm.earlyShare / 0.45
        evidence[Archetype.dawnPatrol.rawValue] = "\(pct(i.rhythm.earlyShare)) of starts before 8am"
        scores[.nightOwl] = i.rhythm.lateShare / 0.35
        evidence[Archetype.nightOwl.rawValue] = "\(pct(i.rhythm.lateShare)) of starts after 7pm"
        scores[.lunchBreaker] = i.rhythm.lunchShare / 0.35
        evidence[Archetype.lunchBreaker.rawValue] = "\(pct(i.rhythm.lunchShare)) of starts around lunch"
        scores[.weekendWarrior] = i.rhythm.weekendShare / 0.55
        evidence[Archetype.weekendWarrior.rawValue] = "\(pct(i.rhythm.weekendShare)) of activities on weekends"
        if i.weeksInRange >= 4 {
            let consistency = Double(i.activeWeeks) / Double(i.weeksInRange)
            let steadiness = i.weeklyDistanceCV.map { max(0, 1 - $0) } ?? 0.5
            scores[.metronome] = (consistency >= 0.85 ? 1 : consistency) * (0.5 + steadiness * 0.6)
            evidence[Archetype.metronome.rawValue] = "Active in \(i.activeWeeks) of \(i.weeksInRange) weeks"
        }
        scores[.mountainGoat] = i.elevationPerKm / 18
        evidence[Archetype.mountainGoat.rawValue] = i.units == .metric
            ? "\(Int(i.elevationPerKm.rounded())) m of climbing per km"
            : "\(Int((i.elevationPerKm * Units.feetPerMeter * Units.metersPerMile / 1000).rounded())) ft of climbing per mile"
        var haul = 0.0
        if let run = i.averageRunKm { haul = max(haul, run / 13) }
        if let ride = i.averageRideKm { haul = max(haul, ride / 65) }
        scores[.longHauler] = haul
        if let run = i.averageRunKm {
            let value = i.units == .metric ? run : run * 1000 / Units.metersPerMile
            evidence[Archetype.longHauler.rawValue] = "Average run \(String(format: "%.1f", value)) \(i.units == .metric ? "km" : "mi")"
        }
        scores[.socialButterfly] = i.groupShare / 0.35
        evidence[Archetype.socialButterfly.rawValue] = "\(pct(i.groupShare)) of activities with others"
        scores[.explorer] = Double(i.startAreas) / max(Double(i.count) * 0.5, 12)
        evidence[Archetype.explorer.rawValue] = "Started from \(i.startAreas) different places"
        if let streak = i.streaks.longestDays?.length {
            scores[.streaker] = Double(streak) / 21
            evidence[Archetype.streaker.rawValue] = "A \(streak)-day streak"
        }
        let meaningful = i.familyShares.values.filter { $0 >= 0.12 }.count
        scores[.multisport] = meaningful >= 3 ? 1.1 : meaningful == 2 ? 0.75 : 0
        evidence[Archetype.multisport.rawValue] = "\(meaningful) sports in regular rotation"
        if let gain = i.paceImprovement {
            scores[.speedDemon] = gain / 0.05
            evidence[Archetype.speedDemon.rawValue] = "Pace improved \(pct(gain))"
        }

        let ranked = scores.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
        guard let top = ranked.first, top.value >= 0.8 else {
            return Persona(primary: .allRounder, traits: ranked.prefix(2).filter { $0.value >= 0.5 }.map(\.key), evidence: evidence)
        }
        let traits = ranked.dropFirst().prefix(2).filter { $0.value >= 0.6 }.map(\.key)
        return Persona(primary: top.key, traits: traits, evidence: evidence)
    }
}
