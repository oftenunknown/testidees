import Foundation

public struct RecapOptions: Sendable {
    public var today: LocalDay
    /// ISO weekday index the week starts on (0 = Monday).
    public var firstWeekday: Int
    /// For calorie estimates when Strava has none. Defaults to the athlete's weight, then 70 kg.
    public var weightKg: Double?
    /// Names you tagged per activity; replaces detected mentions for that activity.
    public var crewTags: [Int64: [String]]
    /// Names never to show as companions.
    public var hiddenCompanions: Set<String>
    public var athlete: Athlete?
    /// Whether the previous comparable period has been synced.
    public var previousAvailable: Bool
    public var routeLimit: Int
    /// Trim this much off both ends of each route in route art.
    public var trimRouteEndsMeters: Double

    public init(today: LocalDay, firstWeekday: Int = 0, weightKg: Double? = nil, crewTags: [Int64: [String]] = [:],
                hiddenCompanions: Set<String> = [], athlete: Athlete? = nil, previousAvailable: Bool = true,
                routeLimit: Int = 60, trimRouteEndsMeters: Double = 250) {
        self.today = today
        self.firstWeekday = firstWeekday
        self.weightKg = weightKg
        self.crewTags = crewTags
        self.hiddenCompanions = hiddenCompanions
        self.athlete = athlete
        self.previousAvailable = previousAvailable
        self.routeLimit = routeLimit
        self.trimRouteEndsMeters = trimRouteEndsMeters
    }
}

public enum RecapBuilder {
    public static func build(from all: [Activity], range: RecapRange, filter: SportFilter = .all, options: RecapOptions) -> Recap {
        let days = range.effectiveDays(today: options.today)
        let acts = all.filter { days.contains($0.day) && filter.includes($0.sport) }
            .sorted { $0.startLocal == $1.startLocal ? $0.id < $1.id : $0.startLocal < $1.startLocal }
        let previousDays = range.previousComparable(today: options.today)
        let previousActs = all.filter { previousDays.contains($0.day) && filter.includes($0.sport) }
        let weight = options.weightKg ?? options.athlete?.weight ?? 70

        let totals = Self.totals(acts, weight: weight)
        let previous = options.previousAvailable ? Self.totals(previousActs, weight: weight) : nil
        let sports = Self.sports(acts, totals: totals)
        let calendar = Self.calendar(acts, days: days, firstWeekday: options.firstWeekday)
        let rhythm = Self.rhythm(acts)
        let streaks = Self.streaks(acts, days: days, firstWeekday: options.firstWeekday)
        let progression = Self.progression(acts, days: days, range: range, options: options, totals: totals, previous: previous)
        let crew = CrewDetector.build(activities: acts, tags: options.crewTags, hidden: options.hiddenCompanions)
        let places = Self.places(acts, library: all)
        let bests = Self.personalBests(acts)
        let mainFamily: SportFamily? = {
            if case .family(let f) = filter { return f }
            guard let top = sports.first, top.share >= 0.55 else { return nil }
            return top.family
        }()

        var highlights = Self.highlights(acts, calendar: calendar, rhythm: rhythm, places: places, days: days)
        if let biggest = crew.biggestGroup { highlights.append(biggest) }

        let weeks = calendar.weeks.filter { $0.length == 7 }
        let weekDistances = weeks.map { $0.distance }
        let cv: Double? = {
            guard weekDistances.count >= 4, let m = Stats.mean(weekDistances), m > 0, let sd = Stats.standardDeviation(weekDistances) else { return nil }
            return sd / m
        }()
        let runs = acts.filter { $0.sport.family == .run }
        let rides = acts.filter { $0.sport.family == .ride }
        let persona = PersonaScorer.persona(PersonaScorer.Inputs(
            count: acts.count,
            rhythm: rhythm,
            streaks: streaks,
            weeksInRange: max(1, days.count / 7),
            activeWeeks: calendar.weeks.filter { $0.count > 0 }.count,
            weeklyDistanceCV: cv,
            elevationPerKm: totals.distance > 5000 ? totals.elevationGain / (totals.distance / 1000) : 0,
            averageRunKm: runs.count >= 3 ? totals.runDistance / 1000 / Double(runs.count) : nil,
            averageRideKm: rides.count >= 3 ? totals.rideDistance / 1000 / Double(rides.count) : nil,
            groupShare: crew.share,
            startAreas: places.startAreas,
            familyShares: Dictionary(uniqueKeysWithValues: sports.map { ($0.family, $0.share) }),
            paceImprovement: progression.runPace.map { -$0.relativeChange }
        ))

        return Recap(
            range: range,
            days: days,
            filter: filter,
            athleteFirstName: options.athlete.map(\.firstName).flatMap { $0.isEmpty ? nil : $0 },
            totals: totals,
            previous: previous,
            previousDays: options.previousAvailable ? previousDays : nil,
            sports: sports,
            calendar: calendar,
            rhythm: rhythm,
            streaks: streaks,
            progression: progression,
            highlights: highlights,
            personalBests: bests,
            crew: crew,
            places: places,
            equivalents: EquivalentFinder.all(for: totals, family: mainFamily),
            persona: persona,
            routes: Self.routes(acts, limit: options.routeLimit, trim: options.trimRouteEndsMeters),
            gear: Self.gear(acts, athlete: options.athlete),
            devices: Self.devices(acts),
            naming: Self.naming(acts)
        )
    }

    // MARK: - Totals

    static func totals(_ list: [Activity], weight: Double) -> Totals {
        var t = Totals()
        var days = Set<Int>()
        var estimated = 0.0
        for a in list {
            t.count += 1
            t.distance += a.distance
            t.movingTime += a.movingTime
            t.elevationGain += a.elevationGain
            days.insert(a.day.index)
            t.kudos += a.kudos
            t.comments += a.comments
            t.achievements += a.achievements
            t.prs += a.prCount
            t.photos += a.photoCount
            let energy = Energy.kcal(for: a, weightKg: weight)
            t.energy += energy.kcal
            if energy.estimated { estimated += energy.kcal }
            if a.isCommute { t.commutes += 1 }
            if a.isTrainer || a.sport == .virtualRide || a.sport == .virtualRun { t.indoor += 1 }
            if a.isGroup { t.groupActivities += 1 }
            if a.isRace { t.races += 1 }
            switch a.sport.family {
            case .run:
                t.runDistance += a.distance
                t.footDistance += a.distance
            case .walk:
                t.footDistance += a.distance
            case .ride:
                t.rideDistance += a.distance
            case .swim:
                t.swimDistance += a.distance
            default:
                break
            }
        }
        t.activeDays = days.count
        t.energyEstimatedShare = t.energy > 0 ? estimated / t.energy : 0
        return t
    }

    static func sports(_ list: [Activity], totals: Totals) -> [SportSlice] {
        var by: [SportFamily: SportSlice] = [:]
        for a in list {
            let f = a.sport.family
            var s = by[f] ?? SportSlice(family: f, count: 0, distance: 0, movingTime: 0, elevationGain: 0, share: 0)
            s.count += 1
            s.distance += a.distance
            s.movingTime += a.movingTime
            s.elevationGain += a.elevationGain
            by[f] = s
        }
        let totalTime = max(totals.movingTime, 1)
        return by.values
            .map { var s = $0; s.share = s.movingTime / totalTime; return s }
            .sorted { $0.movingTime == $1.movingTime ? $0.family.rawValue < $1.family.rawValue : $0.movingTime > $1.movingTime }
    }

    // MARK: - Calendar and rhythm

    static func calendar(_ list: [Activity], days: DayRange, firstWeekday: Int) -> CalendarSummary {
        var byDay: [Int: DayTotal] = [:]
        var dayFamilyTime: [Int: [SportFamily: Double]] = [:]
        for a in list {
            let key = a.day.index
            var d = byDay[key] ?? DayTotal(day: a.day, distance: 0, movingTime: 0, elevationGain: 0, count: 0, family: a.sport.family)
            d.distance += a.distance
            d.movingTime += a.movingTime
            d.elevationGain += a.elevationGain
            d.count += 1
            dayFamilyTime[key, default: [:]][a.sport.family, default: 0] += max(a.movingTime, 1)
            d.family = dayFamilyTime[key]!.max { $0.value < $1.value }!.key
            byDay[key] = d
        }
        let active = byDay.values.sorted { $0.day < $1.day }

        var weeks: [PeriodTotal] = []
        if !days.isEmpty {
            var start = days.start.startOfWeek(firstWeekday: firstWeekday)
            while start < days.end {
                weeks.append(PeriodTotal(start: start, length: 7))
                start = start.adding(days: 7)
            }
        }
        var months: [PeriodTotal] = []
        if !days.isEmpty {
            var start = days.start.startOfMonth
            while start < days.end {
                let next = start.adding(months: 1)
                months.append(PeriodTotal(start: start, length: next.index - start.index))
                start = next
            }
        }
        for d in active {
            if let w = weeks.firstIndex(where: { d.day >= $0.start && d.day.index < $0.start.index + 7 }) {
                weeks[w].distance += d.distance
                weeks[w].movingTime += d.movingTime
                weeks[w].elevationGain += d.elevationGain
                weeks[w].count += d.count
            }
            if let m = months.firstIndex(where: { d.day >= $0.start && d.day.index < $0.start.index + $0.length }) {
                months[m].distance += d.distance
                months[m].movingTime += d.movingTime
                months[m].elevationGain += d.elevationGain
                months[m].count += d.count
            }
        }
        let byDistance = list.reduce(0) { $0 + $1.distance } > 1000
        func volume(_ p: PeriodTotal) -> Double { byDistance ? p.distance : p.movingTime }
        let bestWeek = weeks.filter { $0.count > 0 }.max { volume($0) < volume($1) }
        let bestMonth = months.count > 1 ? months.filter { $0.count > 0 }.max { volume($0) < volume($1) } : nil
        let biggestDay = active.max { (byDistance ? $0.distance : $0.movingTime) < (byDistance ? $1.distance : $1.movingTime) }
        return CalendarSummary(activeDays: active, weeks: weeks, months: months, bestWeek: bestWeek, bestMonth: bestMonth, biggestDay: biggestDay)
    }

    static func rhythm(_ list: [Activity]) -> Rhythm {
        var weekday = [Int](repeating: 0, count: 7)
        var hours = [Int](repeating: 0, count: 24)
        var early = 0, late = 0, lunch = 0, weekend = 0, timed = 0
        var earliest: Activity?, latest: Activity?
        func lateKey(_ a: Activity) -> Int {
            let s = a.startSecondsOfDay
            return s < 3 * 3600 ? s + 86_400 : s
        }
        for a in list {
            weekday[a.day.weekday] += 1
            if a.day.isWeekend { weekend += 1 }
            // Manual entries often carry a made-up start time.
            guard !a.isManual else { continue }
            timed += 1
            let s = a.startSecondsOfDay
            hours[s / 3600] += 1
            if s >= 3 * 3600 && s < 8 * 3600 { early += 1 }
            if s >= 19 * 3600 || s < 3 * 3600 { late += 1 }
            if s >= 11 * 3600 + 1800 && s < 14 * 3600 { lunch += 1 }
            if s >= 3 * 3600, s < (earliest?.startSecondsOfDay ?? Int.max) { earliest = a }
            if lateKey(a) > (latest.map(lateKey) ?? -1) { latest = a }
        }
        let n = Double(max(list.count, 1)), nt = Double(max(timed, 1))
        func moment(_ a: Activity?) -> TimeOfDayMoment? {
            a.map { TimeOfDayMoment(activityID: $0.id, day: $0.day, secondsOfDay: $0.startSecondsOfDay, name: $0.name, sport: $0.sport) }
        }
        let favorite = weekday.max().flatMap { m in m > 0 ? weekday.firstIndex(of: m) : nil }
        let peak = hours.max().flatMap { m in m > 0 ? hours.firstIndex(of: m) : nil }
        return Rhythm(
            weekdayCounts: weekday, hourCounts: hours, favoriteWeekday: favorite, peakHour: peak,
            earlyShare: Double(early) / nt, lateShare: Double(late) / nt, lunchShare: Double(lunch) / nt,
            weekendShare: Double(weekend) / n, earliest: moment(earliest), latest: moment(latest)
        )
    }

    static func streaks(_ list: [Activity], days: DayRange, firstWeekday: Int) -> Streaks {
        let active = Array(Set(list.map(\.day.index))).sorted()
        guard let firstDay = active.first else { return Streaks() }
        var best = Streak(length: 1, start: LocalDay(index: firstDay), end: LocalDay(index: firstDay))
        var run = best
        var longestBreak: Streak?
        for (prev, next) in zip(active, active.dropFirst()) {
            if next == prev + 1 {
                run.length += 1
                run.end = LocalDay(index: next)
            } else {
                let gap = next - prev - 1
                if gap > (longestBreak?.length ?? 0) {
                    longestBreak = Streak(length: gap, start: LocalDay(index: prev + 1), end: LocalDay(index: next - 1))
                }
                run = Streak(length: 1, start: LocalDay(index: next), end: LocalDay(index: next))
            }
            if run.length > best.length { best = run }
        }
        // Current streak: still alive if the last active day is the range's last day or the one before.
        var current: Streak?
        if let last = active.last, last >= days.last.index - 1 {
            current = run.end.index == last ? run : nil
        }
        // Weeks.
        let weekStarts = Array(Set(active.map { LocalDay(index: $0).startOfWeek(firstWeekday: firstWeekday).index })).sorted()
        var bestWeeks: Streak?
        if let w0 = weekStarts.first {
            var start = w0, length = 1
            var top = (start: w0, length: 1)
            for (prev, next) in zip(weekStarts, weekStarts.dropFirst()) {
                if next == prev + 7 { length += 1 } else { start = next; length = 1 }
                if length > top.length { top = (start, length) }
            }
            bestWeeks = Streak(length: top.length, start: LocalDay(index: top.start), end: LocalDay(index: top.start + top.length * 7 - 1))
        }
        return Streaks(longestDays: best, longestWeeks: bestWeeks, longestBreak: longestBreak, current: current)
    }

    // MARK: - Progression

    static func progression(_ list: [Activity], days: DayRange, range: RecapRange, options: RecapOptions, totals: Totals, previous: Totals?) -> Progression {
        let granularity = range.granularity(today: options.today)
        var buckets: [Bucket] = []
        if !days.isEmpty {
            var start: LocalDay
            switch granularity {
            case .day: start = days.start
            case .week: start = days.start.startOfWeek(firstWeekday: options.firstWeekday)
            case .month: start = days.start.startOfMonth
            }
            while start < days.end {
                let next: LocalDay
                switch granularity {
                case .day: next = start.adding(days: 1)
                case .week: next = start.adding(days: 7)
                case .month: next = start.adding(months: 1)
                }
                buckets.append(Bucket(start: start, length: next.index - start.index, distance: 0, movingTime: 0, elevationGain: 0, count: 0))
                start = next
            }
        }
        var runTime = [Double](repeating: 0, count: buckets.count)
        var runDistance = [Double](repeating: 0, count: buckets.count)
        for a in list {
            guard let i = buckets.firstIndex(where: { a.day >= $0.start && a.day.index < $0.start.index + $0.length }) else { continue }
            buckets[i].distance += a.distance
            buckets[i].movingTime += a.movingTime
            buckets[i].elevationGain += a.elevationGain
            buckets[i].count += 1
            if a.sport.family == .run, a.distance >= 1000, !a.isManual {
                runTime[i] += a.movingTime
                runDistance[i] += a.distance
            }
        }
        for i in buckets.indices where runDistance[i] > 0 {
            buckets[i].runPace = runTime[i] / runDistance[i]
        }

        let runs = list.filter { $0.sport.family == .run && $0.distance >= 1000 && !$0.isManual && $0.sport != .virtualRun }
        let runPace = trend(runs.compactMap { a in a.pace.flatMap { (0.15...0.75).contains($0) ? (a.day, $0, sqrt(a.distance / 1000)) : nil } })
        let rides = list.filter { $0.sport.family == .ride && !$0.isTrainer && $0.sport != .virtualRide && $0.distance >= 10_000 }
        let rideSpeed = trend(rides.compactMap { a in a.speed.flatMap { (3...20).contains($0) ? (a.day, $0, sqrt(a.distance / 1000)) : nil } })
        let efficiency = trend(runs.compactMap { a -> (LocalDay, Double, Double)? in
            guard let hr = a.averageHeartrate, (90...210).contains(hr), let v = a.speed else { return nil }
            return (a.day, v * 60 / hr, sqrt(a.distance / 1000))
        })

        var longest: [TrendPoint] = []
        var best = 0.0
        for a in list where a.sport.family == .run && a.distance > best {
            best = a.distance
            longest.append(TrendPoint(day: a.day, value: a.distance))
        }

        func rel(_ now: Double, _ before: Double) -> Double? { before > 0 ? (now - before) / before : nil }
        let vsPrevious = previous.map {
            Comparison(distance: rel(totals.distance, $0.distance), movingTime: rel(totals.movingTime, $0.movingTime),
                       count: rel(Double(totals.count), Double($0.count)), elevationGain: rel(totals.elevationGain, $0.elevationGain))
        }
        var halves: Comparison?
        if days.count >= 56 {
            let mid = days.start.adding(days: days.count / 2)
            let first = list.filter { $0.day < mid }, second = list.filter { $0.day >= mid }
            func sum(_ l: [Activity], _ k: (Activity) -> Double) -> Double { l.reduce(0) { $0 + k($1) } }
            halves = Comparison(
                distance: rel(sum(second, \.distance), sum(first, \.distance)),
                movingTime: rel(sum(second, \.movingTime), sum(first, \.movingTime)),
                count: rel(Double(second.count), Double(first.count)),
                elevationGain: rel(sum(second, \.elevationGain), sum(first, \.elevationGain))
            )
        }
        return Progression(granularity: granularity, buckets: buckets, runPace: runPace, rideSpeed: rideSpeed,
                           runEfficiency: efficiency, longestRunSteps: longest, vsPrevious: vsPrevious, halves: halves)
    }

    /// Weighted line through (day, value, weight) samples; needs at least six
    /// samples spread over three weeks to say anything.
    static func trend(_ samples: [(LocalDay, Double, Double)]) -> Trend? {
        guard samples.count >= 6, let first = samples.map(\.0).min(), let last = samples.map(\.0).max(), last.index - first.index >= 21 else { return nil }
        guard let fit = Stats.linearFit(samples.map { (Double($0.0.index), $0.1, $0.2) }) else { return nil }
        let start = fit.slope * Double(first.index) + fit.intercept
        let end = fit.slope * Double(last.index) + fit.intercept
        guard start > 0, end > 0 else { return nil }
        let points = samples.sorted { $0.0 < $1.0 }.map { TrendPoint(day: $0.0, value: $0.1) }
        return Trend(start: start, end: end, samples: samples.count, points: points)
    }

    // MARK: - Highlights

    static func highlights(_ list: [Activity], calendar: CalendarSummary, rhythm: Rhythm, places: Places, days: DayRange) -> [Highlight] {
        var out: [Highlight] = []
        func h(_ kind: Highlight.Kind, _ a: Activity, _ value: Double, _ secondary: Double? = nil) -> Highlight {
            Highlight(kind: kind, day: a.day, activityID: a.id, name: a.name, sport: a.sport, value: value, secondary: secondary)
        }
        let moving = list.filter { $0.sport.isDistanceSport && $0.distance > 0 }
        if let a = moving.max(by: { $0.distance < $1.distance }) {
            out.append(h(.longest, a, a.distance, a.movingTime))
        }
        if let a = list.max(by: { $0.movingTime < $1.movingTime }), a.movingTime >= 1800 {
            out.append(h(.longestDuration, a, a.movingTime, a.distance))
        }
        if let a = list.max(by: { $0.elevationGain < $1.elevationGain }), a.elevationGain >= 150 {
            out.append(h(.biggestClimb, a, a.elevationGain, a.distance))
        }
        let fastRuns = list.filter { $0.sport.family == .run && $0.distance >= 5000 && !$0.isManual && $0.sport != .virtualRun }
        if let a = fastRuns.min(by: { ($0.pace ?? .infinity) < ($1.pace ?? .infinity) }), let pace = a.pace {
            out.append(h(.fastestRun, a, pace, a.distance))
        }
        let fastRides = list.filter { $0.sport.family == .ride && $0.distance >= 20_000 && !$0.isTrainer && $0.sport != .virtualRide }
        if let a = fastRides.max(by: { ($0.speed ?? 0) < ($1.speed ?? 0) }), let speed = a.speed {
            out.append(h(.fastestRide, a, speed, a.distance))
        }
        if let a = list.max(by: { $0.kudos < $1.kudos }), a.kudos >= 5 {
            out.append(h(.mostKudos, a, Double(a.kudos)))
        }
        if let e = rhythm.earliest, e.secondsOfDay < 7 * 3600 {
            out.append(Highlight(kind: .earliestStart, day: e.day, activityID: e.activityID, name: e.name, sport: e.sport, value: Double(e.secondsOfDay)))
        }
        if let l = rhythm.latest, l.secondsOfDay >= 19 * 3600 || l.secondsOfDay < 3 * 3600 {
            out.append(Highlight(kind: .latestStart, day: l.day, activityID: l.activityID, name: l.name, sport: l.sport, value: Double(l.secondsOfDay)))
        }
        if let w = calendar.bestWeek, calendar.weeks.count >= 3 {
            out.append(Highlight(kind: .biggestWeek, day: w.start, value: w.distance > 0 ? w.distance : w.movingTime, secondary: Double(w.count)))
        }
        if let m = calendar.bestMonth {
            out.append(Highlight(kind: .busiestMonth, day: m.start, value: Double(m.count), secondary: m.distance))
        }
        if let a = list.first, days.count >= 28 {
            out.append(h(.firstActivity, a, a.distance, a.movingTime))
        }
        if let far = places.furthest, far.distanceKm >= 80 {
            out.append(Highlight(kind: .furthestAway, day: far.day, activityID: far.activityID, name: far.name, sport: far.sport, value: far.distanceKm))
        }
        if let a = list.filter(\.isRace).max(by: { $0.distance < $1.distance }) {
            out.append(h(.race, a, a.distance, a.movingTime))
        }
        if let a = list.filter({ $0.sport.family == .swim }).max(by: { $0.distance < $1.distance }), a.distance >= 1000 {
            out.append(h(.longestSwim, a, a.distance, a.movingTime))
        }
        return out
    }

    // MARK: - PBs

    static func personalBests(_ list: [Activity]) -> PersonalBests {
        let runs = list.filter { $0.sport.family == .run && !$0.isManual }
        var records: [StandardDistance: [EffortRecord]] = [:]
        for a in runs {
            guard let efforts = a.details?.bestEfforts else { continue }
            for e in efforts {
                guard let standard = e.standard, e.elapsedTime > 0 else { continue }
                records[standard, default: []].append(EffortRecord(
                    distance: standard, time: e.elapsedTime, day: a.day, activityID: a.id, activityName: a.name, wasPR: e.prRank == 1
                ))
            }
        }
        let items: [EffortProgress] = records.compactMap { distance, list in
            let sorted = list.sorted { $0.day == $1.day ? $0.time < $1.time : $0.day < $1.day }
            guard let first = sorted.first, let best = sorted.min(by: { $0.time < $1.time }) else { return nil }
            return EffortProgress(distance: distance, best: best, prs: sorted.filter(\.wasPR), first: first)
        }
        .sorted { $0.distance < $1.distance }
        return PersonalBests(
            items: items,
            prCount: items.reduce(0) { $0 + $1.prs.count },
            runsChecked: runs.filter { $0.details != nil }.count,
            runsTotal: runs.count
        )
    }

    // MARK: - Places

    static func places(_ list: [Activity], library: [Activity]) -> Places {
        func cell(_ c: Coordinate) -> String { "\(Int((c.latitude / 0.01).rounded())):\(Int((c.longitude / 0.015).rounded()))" }
        // Home from the whole library, so a trip-heavy month doesn't move it.
        var counts: [String: (n: Int, lat: Double, lon: Double)] = [:]
        for a in library where !a.isManual {
            guard let c = a.startCoordinate else { continue }
            let k = cell(c)
            let e = counts[k] ?? (0, 0, 0)
            counts[k] = (e.n + 1, e.lat + c.latitude, e.lon + c.longitude)
        }
        let home = counts.max { $0.value.n == $1.value.n ? $0.key > $1.key : $0.value.n < $1.value.n }.map {
            // Rounded to ~1 km: good enough to measure distance, never precise enough to locate a door.
            Coordinate(($0.value.lat / Double($0.value.n) * 100).rounded() / 100, ($0.value.lon / Double($0.value.n) * 100).rounded() / 100)
        }
        let starts = list.filter { !$0.isManual }.compactMap { a in a.startCoordinate.map { (a, $0) } }
        let areas = Set(starts.map { cell($0.1) }).count
        var furthest: FarPoint?
        if let home {
            if let (a, c) = starts.max(by: { Geo.distanceKm(home, $0.1) < Geo.distanceKm(home, $1.1) }) {
                let d = Geo.distanceKm(home, c)
                if d >= 50 {
                    furthest = FarPoint(activityID: a.id, day: a.day, name: a.name, sport: a.sport,
                                        coordinate: Coordinate((c.latitude * 10).rounded() / 10, (c.longitude * 10).rounded() / 10),
                                        distanceKm: d)
                }
            }
        }
        return Places(home: home, startAreas: areas, furthest: furthest)
    }

    // MARK: - Route art

    static func routes(_ list: [Activity], limit: Int, trim: Double) -> [RouteSketch] {
        let withRoutes = list.filter { $0.hasRoute && $0.distance >= 1000 && !$0.isTrainer }
            .sorted { $0.distance > $1.distance }
        var out: [RouteSketch] = []
        for a in withRoutes {
            guard out.count < limit, let encoded = a.polyline else { break }
            var points = Polyline.trimmingEnds(Polyline.decode(encoded), meters: trim)
            guard points.count >= 3 else { continue }
            points = Polyline.simplify(points, toleranceMeters: max(8, a.distance / 400))
            if points.count > 90 {
                let stride = Double(points.count) / 90
                points = (0..<90).map { points[Int(Double($0) * stride)] }
            }
            let lat0 = points[0].latitude * .pi / 180
            let k = cos(lat0)
            let xy = points.map { ($0.longitude * k, -$0.latitude) }
            let minX = xy.map(\.0).min()!, maxX = xy.map(\.0).max()!
            let minY = xy.map(\.1).min()!, maxY = xy.map(\.1).max()!
            let span = max(maxX - minX, maxY - minY)
            guard span > 0 else { continue }
            let ox = (span - (maxX - minX)) / 2, oy = (span - (maxY - minY)) / 2
            let unit = xy.map { RoutePoint(x: Float(($0.0 - minX + ox) / span), y: Float(($0.1 - minY + oy) / span)) }
            out.append(RouteSketch(id: a.id, family: a.sport.family, distance: a.distance, points: unit))
        }
        return out
    }

    // MARK: - Gear, devices, names

    static func gear(_ list: [Activity], athlete: Athlete?) -> [GearUsage] {
        guard let athlete else { return [] }
        let names = Dictionary(athlete.gear.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var usage: [String: GearUsage] = [:]
        for a in list {
            guard let id = a.gearID, let gear = names[id] else { continue }
            var u = usage[id] ?? GearUsage(id: id, name: gear.name, kind: gear.kind, distance: 0, count: 0)
            u.distance += a.distance
            u.count += 1
            usage[id] = u
        }
        return usage.values.sorted { $0.distance > $1.distance }
    }

    static func devices(_ list: [Activity]) -> [DeviceUsage] {
        var counts: [String: Int] = [:]
        for a in list {
            if let d = a.deviceName { counts[d, default: 0] += 1 }
        }
        return counts.map { DeviceUsage(name: $0.key, count: $0.value) }.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    static let defaultPrefixes: Set<String> = ["Morning", "Afternoon", "Evening", "Night", "Lunch"]

    /// Strava's automatic titles: "Morning Run", "Lunch Ride", "Evening Weight Training"…
    public static func isDefaultName(_ name: String) -> Bool {
        let words = name.split(separator: " ")
        guard words.count >= 2, words.count <= 4, let first = words.first, defaultPrefixes.contains(String(first)) else { return false }
        return words.dropFirst().allSatisfy { w in w.allSatisfy { $0.isLetter || $0 == "-" } && (w.first?.isUppercase ?? false) }
    }

    static func naming(_ list: [Activity]) -> NamingStats {
        var counts: [String: Int] = [:]
        var defaults = 0
        for a in list where isDefaultName(a.name) {
            defaults += 1
            counts[a.name, default: 0] += 1
        }
        let top = counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }
        return NamingStats(total: list.count, defaultNamed: defaults, topDefaultName: top?.key, topDefaultCount: top?.value ?? 0)
    }
}

/// Rough energy estimates when Strava has no calorie figure.
enum Energy {
    static func kcal(for a: Activity, weightKg w: Double) -> (kcal: Double, estimated: Bool) {
        if let c = a.details?.calories, c > 0 { return (c, false) }
        // Mechanical work in kJ ≈ kcal burned, at ~24% efficiency.
        if let kj = a.kilojoules, kj > 0 { return (kj, false) }
        let hours = a.movingTime / 3600
        let met: Double
        switch a.sport.family {
        case .run:
            return (w * a.distance / 1000 * 1.0, true)
        case .walk:
            met = a.sport == .hike ? 6 : 3.5
        case .ride:
            let kmh = (a.speed ?? 0) * 3.6
            if a.isTrainer || a.sport == .virtualRide { met = 7 }
            else if kmh < 16 { met = 4 }
            else if kmh < 19 { met = 6.8 }
            else if kmh < 22 { met = 8 }
            else if kmh < 25 { met = 10 }
            else { met = 12 }
        case .swim:
            met = 7
        case .water:
            met = a.sport == .rowing ? 7 : 5
        case .glide:
            met = a.sport.rawValue == "NordicSki" ? 9 : 5.5
        case .gym:
            switch a.sport.rawValue {
            case "Yoga", "Pilates": met = 2.8
            case "HighIntensityIntervalTraining", "Crossfit": met = 8
            default: met = 5
            }
        case .other:
            met = 6
        }
        return (met * w * hours, true)
    }
}
