import Foundation

/// Turns recap numbers into the sentences the story and share cards use.
public struct Narrator: Sendable {
    public var units: Units
    public var format: DayFormat

    public init(units: Units, format: DayFormat? = nil) {
        self.units = units
        self.format = format ?? DayFormat(locale: units.locale)
    }

    // MARK: - Numbers

    /// "1.3×", "12×".
    public func multiple(_ x: Double) -> String {
        x >= 10 ? "\(units.number(x.rounded()))×" : "\(units.number(x, decimals: 1))×"
    }

    /// Counts for "1,234 laps" / "12 matches" / "2.5 days".
    public func count(_ x: Double) -> String {
        if x >= 10 { return units.number(x.rounded()) }
        if x >= 1 { return units.number(x, decimals: 1) }
        return units.number(x, decimals: 2)
    }

    /// "+23%" / "−8%".
    public func percentChange(_ relative: Double) -> String {
        let pct = Int((relative * 100).rounded())
        if pct == 0 { return "±0%" }
        return pct > 0 ? "+\(pct)%" : "−\(abs(pct))%"
    }

    public func percent(_ fraction: Double) -> String {
        let p = fraction * 100
        if p < 0.1 { return "\(units.number(p, decimals: 2))%" }
        return p < 10 ? "\(units.number(p, decimals: 1))%" : "\(Int(p.rounded()))%"
    }

    // MARK: - Equivalents

    /// "That's Paris → New York — and 1,200 km more."
    public func journeyLine(_ e: DistanceEquivalent) -> String {
        let j = e.journey
        if j.kind == .space {
            return "\(percent(e.multiple)) of the way to the Moon"
        }
        if e.multiple < 1 {
            switch j.kind {
            case .trail, .road, .rail, .voyage:
                let title = j.title.hasPrefix("The ") ? "the " + j.title.dropFirst(4) : j.title
                return "\(percent(e.multiple)) of \(title)"
            default:
                if let from = j.from, let to = j.to {
                    return "\(percent(e.multiple)) of the way from \(from) to \(to)"
                }
                return "\(percent(e.multiple)) of \(j.title)"
            }
        }
        if j.kind == .planet {
            return e.multiple < 1.05 ? "Once around the Equator" : "\(count(e.multiple)) times around the Equator"
        }
        if e.multiple >= 1.95 {
            return "\(j.title), \(count(e.multiple)) times over"
        }
        return "\(j.title)"
    }

    /// Second line under the journey: "…and 1,234 km more" / "as the crow flies".
    public func journeyDetail(_ e: DistanceEquivalent, totalMeters: Double) -> String {
        let j = e.journey
        if e.multiple >= 1, e.multiple < 1.95, j.kind != .space, j.kind != .planet {
            let extra = totalMeters - j.lengthKm * 1000
            if extra >= 1000 {
                return "\(j.subtitle) — with \(units.distance(extra, decimals: 0)) to spare"
            }
        }
        return "\(j.subtitle) · ≈ \(units.distance(j.lengthKm * 1000, decimals: 0))"
    }

    /// "1.4 Everests" / "62% of the way up Kilimanjaro".
    public func climbLine(_ e: ClimbEquivalent) -> String {
        if e.multiple < 1 {
            return e.landmark.kind == .sky
                ? "\(percent(e.multiple)) of the way to \(e.landmark.name)"
                : "\(percent(e.multiple)) of the way up \(e.landmark.name)"
        }
        if e.multiple < 1.05 { return "\(e.landmark.name.prefix(1).uppercased() + e.landmark.name.dropFirst()), summited" }
        return "\(count(e.multiple)) \(e.landmark.plural)"
    }

    public func trackLaps(_ laps: Double) -> String {
        "\(units.number(laps.rounded())) laps of a 400 m track"
    }

    // MARK: - Periods

    /// "vs 2025", "vs Q2 2026", "vs September".
    public func previousLabel(for range: RecapRange) -> String {
        switch range.period {
        case .year(let y): return "vs \(y - 1)"
        case .quarter:
            if case .quarter(let y, let q) = range.shifted(-1).period { return "vs Q\(q) \(y)" }
            return "vs last quarter"
        case .month: return "vs \(format.month(range.shifted(-1).days.start))"
        case .week: return "vs the week before"
        case .rolling(let n, _): return "vs the \(n) days before"
        case .custom(let r): return "vs the \(r.count) days before"
        }
    }

    // MARK: - Highlights

    private func quoted(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "" }
        return "“\(name)”"
    }

    private func verb(_ h: Highlight) -> String { h.sport?.pastVerb ?? "moved" }

    public func headline(_ h: Highlight) -> String {
        let date = format.weekdayShort(h.day)
        switch h.kind {
        case .longest:
            return "On \(date) you \(verb(h)) \(units.distance(h.value))"
        case .longestDuration:
            return "On \(date) you kept going for \(Units.hoursMinutes(h.value))"
        case .biggestClimb:
            return "On \(date) you climbed \(units.elevation(h.value))"
        case .fastestRun:
            return "On \(date) you flew at \(units.pace(secondsPerMeter: h.value))"
        case .fastestRide:
            return "On \(date) you averaged \(units.speed(h.value))"
        case .mostKudos:
            return "\(quoted(h.name)) got \(Int(h.value)) kudos"
        case .earliestStart:
            return "Up and out at \(format.time(Floating.date(h.day, hour: 0, second: Int(h.value))))"
        case .latestStart:
            return "Still going at \(format.time(Floating.date(h.day, hour: 0, second: Int(h.value))))"
        case .biggestWeek:
            let volume = h.value > 3000 ? units.distance(h.value) : Units.hoursMinutes(h.value)
            return "Your biggest week: \(volume)"
        case .busiestMonth:
            return "\(format.month(h.day)) was your busiest month"
        case .firstActivity:
            return "It all started on \(date)"
        case .furthestAway:
            return "Your furthest adventure: \(units.distance(h.value * 1000, decimals: 0)) from home"
        case .biggestGroup:
            let others = Int(h.value) - 1
            return "You \(verb(h)) with \(others) other\(others == 1 ? "" : "s")"
        case .race:
            return "Race day: \(units.distance(h.value)) in \(Units.clock(h.secondary ?? 0))"
        case .longestSwim:
            return "On \(date) you swam \(units.swimDistance(h.value))"
        }
    }

    public func detail(_ h: Highlight) -> String {
        let date = format.weekdayShort(h.day)
        let name = quoted(h.name)
        switch h.kind {
        case .longest:
            let noun = h.sport.map { $0.displayName.lowercased() } ?? "activity"
            return "Your longest \(noun) — \(name)"
        case .longestDuration, .longestSwim:
            return name
        case .biggestClimb:
            let towers = h.value / 330
            return "\(name) — that's \(count(towers)) Eiffel Towers in one go"
        case .fastestRun, .fastestRide:
            return "over \(units.distance(h.secondary ?? 0)) — \(name)"
        case .mostKudos:
            return "Your most-loved activity, on \(date)"
        case .earliestStart, .latestStart, .biggestGroup, .race:
            return "\(date) — \(name)"
        case .biggestWeek:
            return "\(Int(h.secondary ?? 0)) activities in the week of \(format.short(h.day))"
        case .busiestMonth:
            return "\(Int(h.value)) activities, \(units.distance(h.secondary ?? 0))"
        case .firstActivity:
            return "with \(name)"
        case .furthestAway:
            return "\(name) on \(date)"
        }
    }

    // MARK: - People

    public func companionLine(_ c: Companion) -> String {
        let times = c.count == 1 ? "once" : "\(c.count) times"
        if c.distance >= 1000 {
            return "\(times) together · \(units.distance(c.distance))"
        }
        return "\(times) together · \(Units.hoursMinutes(c.movingTime))"
    }
}
