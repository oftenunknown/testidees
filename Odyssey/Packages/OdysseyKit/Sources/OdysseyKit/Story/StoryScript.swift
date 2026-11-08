import Foundation

/// The pages of the animated recap, in order.
public enum StoryPage: String, Codable, Sendable, CaseIterable, Identifiable {
    case intro, totals, journey, climb, time, rhythm, clock, sports, progress, bests, moments, crew, routes, persona, outro

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .intro: "Intro"
        case .totals: "The numbers"
        case .journey: "How far"
        case .climb: "How high"
        case .time: "How long"
        case .rhythm: "Consistency"
        case .clock: "When"
        case .sports: "Sport mix"
        case .progress: "Progress"
        case .bests: "Personal bests"
        case .moments: "Big moments"
        case .crew: "Your crew"
        case .routes: "Your routes"
        case .persona: "Your persona"
        case .outro: "Summary"
        }
    }
}

public enum StoryScript {
    /// Pages worth showing for this recap; quiet periods get a shorter story.
    public static func pages(for recap: Recap) -> [StoryPage] {
        let t = recap.totals
        guard t.count > 0 else { return [.intro, .outro] }
        var pages: [StoryPage] = [.intro, .totals]
        if t.distance >= 1000 { pages.append(.journey) }
        if t.elevationGain >= 50 { pages.append(.climb) }
        if t.movingTime >= 3600 { pages.append(.time) }
        if t.activeDays >= 3 && recap.days.count >= 7 { pages.append(.rhythm) }
        if t.count >= 5 { pages.append(.clock) }
        if recap.sports.filter({ $0.share >= 0.03 }).count >= 2 { pages.append(.sports) }
        let p = recap.progression
        if p.buckets.filter({ $0.count > 0 }).count >= 3 && (p.runPace != nil || p.vsPrevious?.distance != nil || p.runEfficiency != nil || p.halves != nil) {
            pages.append(.progress)
        }
        if !recap.personalBests.items.isEmpty { pages.append(.bests) }
        if moments(for: recap).count >= 2 { pages.append(.moments) }
        if recap.crew.groupCount > 0 || !recap.crew.companions.isEmpty { pages.append(.crew) }
        if recap.routes.count >= 4 { pages.append(.routes) }
        if t.count >= 5 { pages.append(.persona) }
        pages.append(.outro)
        return pages
    }

    /// The highlights for the "big moments" page, best first, without repeats
    /// of the same activity.
    public static func moments(for recap: Recap, limit: Int = 4) -> [Highlight] {
        let order: [Highlight.Kind] = [.race, .longest, .biggestClimb, .fastestRun, .furthestAway, .mostKudos, .fastestRide, .earliestStart, .longestSwim, .biggestGroup, .latestStart, .longestDuration]
        var out: [Highlight] = []
        var used = Set<Int64>()
        for kind in order {
            guard out.count < limit, let h = recap.highlight(kind) else { continue }
            if let id = h.activityID {
                guard !used.contains(id) else { continue }
                used.insert(id)
            }
            out.append(h)
        }
        return out
    }
}
