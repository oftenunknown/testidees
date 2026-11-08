import Foundation

/// A believable, deterministic training history for a fictional athlete, so
/// the app can be explored (and screenshotted in CI) without a Strava account.
///
/// Alex trains in East London: early runs, track nights with Leo and Maya,
/// summer rides, lunchtime swims, a spring half marathon PR, an August trip to
/// Chamonix and a first marathon in Berlin in September 2026.
public enum DemoData {
    /// "Today" for demo mode and UI tests.
    public static let anchor = LocalDay(year: 2026, month: 11, day: 7)
    public static let home = Coordinate(51.5362, -0.0398)

    public static let athlete = Athlete(
        id: 4_242,
        firstName: "Alex",
        lastName: "Rivera",
        city: "London",
        country: "United Kingdom",
        measurementPreference: "meters",
        weight: 68,
        createdAt: Date(timeIntervalSince1970: 1_420_070_400),
        gear: [
            Gear(id: "g1", name: "Daily trainers", kind: .shoes, distance: 1_480_000),
            Gear(id: "g2", name: "Carbon racers", kind: .shoes, distance: 310_000),
            Gear(id: "b1", name: "Road bike", kind: .bike, distance: 5_200_000),
        ]
    )

    public static func library(through end: LocalDay = anchor, seed: UInt64 = 2026) -> ActivityLibrary {
        let acts = activities(through: end, seed: seed)
        let start = LocalDay(year: end.year - 1, month: 1, day: 1)
        return ActivityLibrary(
            activities: acts,
            coverage: [TimeSpan.covering(DayRange(start: start, end: end.adding(days: 1)))],
            athlete: athlete,
            lastSync: end.date
        )
    }

    public static func activities(through end: LocalDay = anchor, seed: UInt64 = 2026) -> [Activity] {
        var g = Generator(seed: seed)
        var day = LocalDay(year: end.year - 1, month: 1, day: 1)
        while day <= end {
            g.generate(day)
            day = day.adding(days: 1)
        }
        return g.out
    }

    // MARK: - Generator

    struct Generator {
        var rng: SeededRandom
        var out: [Activity] = []
        var nextID: Int64 = 12_000_000_000
        // Lifetime bests before the demo starts (seconds).
        var bests: [StandardDistance: Double] = [.k1: 236, .mile: 392, .k5: 1388, .k10: 2950, .half: 7140]

        static let berlin = Coordinate(52.5163, 13.3777)
        static let chamonix = Coordinate(45.9237, 6.8694)
        static let verbier = Coordinate(46.0961, 7.2286)
        static let centralPark = Coordinate(40.7812, -73.9665)
        static let track = Coordinate(51.5262, -0.0291)

        init(seed: UInt64) {
            rng = SeededRandom(seed: seed)
        }

        /// 0 in Jan 2025 → 1 on marathon day, easing off afterwards.
        func fitness(_ d: LocalDay) -> Double {
            let start = LocalDay(year: 2025, month: 1, day: 1).index
            let peak = LocalDay(year: 2026, month: 9, day: 27).index
            if d.index <= peak {
                var f = Double(d.index - start) / Double(peak - start)
                // Holiday dip.
                if d.month == 12, d.day >= 20 { f -= 0.05 }
                return max(0, min(1, f))
            }
            return max(0.88, 1 - Double(d.index - peak) / 400)
        }

        func isSummer(_ d: LocalDay) -> Bool { (5...9).contains(d.month) }

        /// Distance of the Sunday long run, building to the marathon.
        func longRunKm(_ d: LocalDay) -> Double {
            let marathon = LocalDay(year: 2026, month: 9, day: 27)
            let weeksOut = Double(marathon.index - d.index) / 7
            if d.year == 2026, weeksOut >= 2, weeksOut <= 18 {
                return 32 - max(0, weeksOut - 3) * 1.15
            }
            return 12 + fitness(d) * 7
        }

        mutating func generate(_ d: LocalDay) {
            if special(d) { return }
            let wd = d.weekday
            let f = fitness(d)
            let taper = d >= LocalDay(year: 2026, month: 9, day: 14) && d < LocalDay(year: 2026, month: 9, day: 27)
            let recovery = d > LocalDay(year: 2026, month: 9, day: 27) && d < LocalDay(year: 2026, month: 10, day: 12)
            let holiday = d.month == 12 && d.day >= 22
            if holiday && !rng.chance(0.35) { return }
            switch wd {
            case 0:
                if rng.chance(0.45) { swim(d, hour: 12, minute: 30) } else if rng.chance(0.3) { gym(d, sport: .yoga, hour: 19, name: "Yoga") }
            case 1:
                if !recovery && rng.chance(0.68) {
                    trackSession(d, f: f)
                } else if rng.chance(0.5) {
                    easyRun(d, f: f, km: rng.range(6...9))
                }
            case 2:
                if rng.chance(recovery ? 0.4 : 0.78) { easyRun(d, f: f, km: rng.range(7...11) * (taper ? 0.7 : 1)) }
                if isSummer(d) && rng.chance(0.45) { commute(d) }
            case 3:
                if !recovery && rng.chance(0.55) { tempoRun(d, f: f) }
                if rng.chance(0.32) { gym(d, sport: .weightTraining, hour: 19, name: rng.chance(0.5) ? "Weight Training" : "Leg day 🦵") }
            case 4:
                if rng.chance(0.38) { swim(d, hour: 12, minute: 40) } else if rng.chance(0.3) { easyRun(d, f: f, km: rng.range(5...6.5)) }
                if isSummer(d) && rng.chance(0.4) { commute(d) }
            case 5:
                if isSummer(d) || recovery {
                    if rng.chance(0.62) { longRide(d) }
                } else if rng.chance(0.3) {
                    indoorRide(d)
                }
                if !taper && rng.chance(0.38) { parkrun(d, f: f) }
            default:
                if recovery {
                    if rng.chance(0.5) { easyRun(d, f: f * 0.9, km: rng.range(8...12)) }
                } else if rng.chance(0.86) {
                    longRun(d, f: f, km: taper ? 16 : longRunKm(d))
                }
            }
        }

        // MARK: Special days

        mutating func special(_ d: LocalDay) -> Bool {
            switch (d.year, d.month, d.day) {
            case (2025, 11, 1):
                run(d, at: (7, 35), km: 9.7, pace: 335, hr: 146, name: "Central Park loop 🗽", place: Self.centralPark, utcOffset: -4, shape: .loop)
                return true
            case (2025, 11, 2):
                walk(d, at: (9, 50), km: 12.4, name: "Cheering at the marathon 📣", place: Self.centralPark, utcOffset: -5)
                return true
            case (2025, 12, 25):
                run(d, at: (9, 5), km: 8.2, pace: 352, hr: 140, name: "Christmas Day run with Dad 🎄", athletes: 2, shape: .loop)
                return true
            case (2026, 2, 14), (2026, 2, 15), (2026, 2, 16), (2026, 2, 17):
                ski(d)
                return true
            case (2026, 4, 26):
                race(d, km: 21.0975, seconds: 6290, name: "City Half 🏅 new PB!", place: nil, athletes: 140, kudos: 47)
                return true
            case (2026, 6, 20):
                run(d, at: (22, 41), km: 7.3, pace: 330, hr: 150, name: "Midsummer night run 🌙", shape: .loop)
                return true
            case (2026, 7, 14):
                run(d, at: (4, 52), km: 10.2, pace: 320, hr: 147, name: "Sunrise run before the heat", shape: .loop)
                return true
            case (2026, 8, 10...16):
                alps(d)
                return true
            case (2026, 9, 27):
                race(d, km: 42.195, seconds: 13_290, name: "Berlin Marathon 🇩🇪 first marathon!", place: Self.berlin, athletes: 310, kudos: 96)
                return true
            default:
                return false
            }
        }

        // MARK: Workouts

        mutating func easyRun(_ d: LocalDay, f: Double, km: Double) {
            let pace = 368 - 45 * f + rng.normal(mean: 0, sd: 6)
            let names = ["Morning Run", "Morning Run", "Morning Run", "Easy miles", "Recovery jog", "Canal loop"]
            run(d, at: (6, Int(rng.range(0...35))), km: km, pace: pace, hr: 148 - 6 * f + rng.normal(mean: 0, sd: 3), name: rng.pick(names), shape: .loop)
        }

        mutating func tempoRun(_ d: LocalDay, f: Double) {
            let km = rng.range(8...12)
            let pace = 312 - 28 * f + rng.normal(mean: 0, sd: 5)
            run(d, at: (6, Int(rng.range(10...30))), km: km, pace: pace, hr: 164 + rng.normal(mean: 0, sd: 3),
                name: rng.chance(0.5) ? "Tempo Thursday" : "Morning Run", gear: "g2", shape: .outAndBack, effortBoost: 0.96)
        }

        mutating func trackSession(_ d: LocalDay, f: Double) {
            let crew: [String] = rng.pick([["Leo", "Maya"], ["Leo"], ["Maya", "Leo"], ["Maya"], ["Leo", "Maya", "Sam"]])
            let names = [
                "Track Tuesday w/ \(crew.joined(separator: " & "))",
                "Intervals with \(crew.joined(separator: ", "))",
                "Track night with \(crew[0])",
            ]
            let pace = 318 - 30 * f
            run(d, at: (18, 45), km: rng.range(8.5...11), pace: pace, hr: 160, name: rng.pick(names),
                athletes: Int(rng.range(4...9)), gear: "g2", place: Self.track, shape: .track, effortBoost: 0.82,
                notes: rng.chance(0.3) ? "6 x 800m, great session." : nil)
        }

        mutating func longRun(_ d: LocalDay, f: Double, km: Double) {
            let withMaya = rng.chance(0.42)
            let pace = 380 - 45 * f + rng.normal(mean: 0, sd: 6)
            let name = withMaya ? rng.pick(["Long run with Maya", "Sunday long run with Maya ☕️", "LSD with Maya"]) : rng.pick(["Sunday long run", "Morning Run", "Long run"])
            run(d, at: (7, Int(rng.range(10...45))), km: km * rng.range(0.95...1.05), pace: pace, hr: 151 - 4 * f,
                name: name, athletes: withMaya ? 2 : 1, shape: .outAndBack, effortBoost: 0.98,
                notes: withMaya && rng.chance(0.25) ? "Sam joined for the last 8k." : nil)
        }

        mutating func parkrun(_ d: LocalDay, f: Double) {
            let pace = 300 - 26 * f + rng.normal(mean: 0, sd: 5)
            run(d, at: (9, 0), km: 5.0, pace: pace, hr: 170, name: rng.chance(0.3) ? "parkrun with Maya" : "parkrun 🌳",
                athletes: Int(rng.range(180...420)), shape: .loop, effortBoost: 1.0, kudosBonus: 4)
        }

        mutating func commute(_ d: LocalDay) {
            for (h, m, name) in [(8, 5, "Morning Ride"), (18, 10, "Evening Ride")] {
                ride(d, at: (h, m + Int(rng.range(0...15))), km: rng.range(7.6...8.6), speed: rng.range(21...25), name: name,
                     commute: true, athletes: 1, shape: .outAndBack)
            }
        }

        mutating func longRide(_ d: LocalDay) {
            let withMaya = rng.chance(0.45)
            let km = rng.range(45...112)
            let name = withMaya ? rng.pick(["Coffee ride with Maya ☕️", "Hills with Maya & Leo", "Saturday spin with Maya"]) : rng.pick(["Morning Ride", "Essex lanes", "Saturday spin"])
            ride(d, at: (8, Int(rng.range(0...40))), km: km, speed: rng.range(25...29.5), name: name, athletes: withMaya ? Int(rng.range(2...6)) : 1, shape: .bigLoop)
        }

        mutating func indoorRide(_ d: LocalDay) {
            let minutes = rng.range(45...75)
            let speed = rng.range(29...32) / 3.6
            emit(Activity(
                id: newID(), name: rng.pick(["Indoor intervals", "Evening Ride", "Turbo session"]), sport: .virtualRide,
                start: d.date, startLocal: Floating.date(d, hour: 19, minute: 15), timezone: "Europe/London",
                distance: speed * minutes * 60, movingTime: minutes * 60, elevationGain: rng.range(150...450),
                averageSpeed: speed, averageHeartrate: 145, averageWatts: rng.range(185...215), kilojoules: rng.range(550...900),
                kudos: Int(rng.range(1...7)), deviceName: "Garmin Edge 1050", gearID: "b1", isTrainer: true
            ), utcOffset: 0)
        }

        mutating func swim(_ d: LocalDay, hour: Int, minute: Int) {
            let meters = (rng.range(1500...2600) / 50).rounded() * 50
            let pace = rng.range(1.05...1.25) // s per m
            emit(Activity(
                id: newID(), name: rng.pick(["Lunch Swim", "Lunch Swim", "Pool session", "Lengths"]), sport: .swim,
                start: d.date, startLocal: Floating.date(d, hour: hour, minute: minute), timezone: "Europe/London",
                distance: meters, movingTime: meters * pace, elevationGain: 0, averageSpeed: 1 / pace,
                averageHeartrate: 132, kudos: Int(rng.range(1...6)), deviceName: "Apple Watch Ultra 3"
            ), utcOffset: offset(d))
        }

        mutating func gym(_ d: LocalDay, sport: Sport, hour: Int, name: String) {
            let minutes = rng.range(40...60)
            emit(Activity(
                id: newID(), name: name, sport: sport, start: d.date, startLocal: Floating.date(d, hour: hour, minute: Int(rng.range(0...20))),
                timezone: "Europe/London", distance: 0, movingTime: minutes * 60, averageHeartrate: sport == .yoga ? 95 : 118,
                kudos: Int(rng.range(0...4)), deviceName: "Apple Watch Ultra 3"
            ), utcOffset: offset(d))
        }

        mutating func walk(_ d: LocalDay, at time: (Int, Int), km: Double, name: String, place: Coordinate, utcOffset: Int) {
            let start = place
            let points = shape(.loop, around: start, km: km)
            emit(Activity(
                id: newID(), name: name, sport: .walk, start: d.date, startLocal: Floating.date(d, hour: time.0, minute: time.1),
                timezone: "America/New_York", distance: km * 1000, movingTime: km * 720, elevationGain: 40,
                kudos: 9, startCoordinate: points.first, endCoordinate: points.last, polyline: Polyline.encode(points),
                deviceName: "Apple Watch Ultra 3"
            ), utcOffset: utcOffset)
        }

        mutating func ski(_ d: LocalDay) {
            let km = rng.range(32...48)
            let points = shape(.bigLoop, around: Self.verbier, km: km / 3)
            emit(Activity(
                id: newID(), name: d.day == 14 ? "First tracks in Verbier ⛷️" : rng.pick(["Afternoon Alpine Ski", "Powder day", "Morning Alpine Ski"]),
                sport: .alpineSki, start: d.date, startLocal: Floating.date(d, hour: 9, minute: 30), timezone: "Europe/Zurich",
                distance: km * 1000, movingTime: rng.range(3.2...4.6) * 3600, elevationGain: rng.range(180...420),
                maxSpeed: rng.range(18...24), averageHeartrate: 121, kudos: Int(rng.range(6...14)), athleteCount: 3,
                startCoordinate: points.first, endCoordinate: points.last, polyline: Polyline.encode(points), deviceName: "Apple Watch Ultra 3"
            ), utcOffset: 1)
        }

        mutating func alps(_ d: LocalDay) {
            switch d.day {
            case 10, 13, 15:
                let km = rng.range(14...24)
                let climb = rng.range(950...1650)
                let points = shape(.outAndBack, around: Self.chamonix, km: km)
                emit(Activity(
                    id: newID(), name: d.day == 15 ? "Lac Blanc hike with Maya 🏔️" : rng.pick(["Hike up to the glacier", "Grand Balcon Sud", "Afternoon Hike"]),
                    sport: .hike, start: d.date, startLocal: Floating.date(d, hour: 8, minute: 40), timezone: "Europe/Paris",
                    distance: km * 1000, movingTime: km * 1000 * 0.82, elevationGain: d.day == 15 ? 1840 : climb, averageHeartrate: 128,
                    kudos: Int(rng.range(10...24)), athleteCount: d.day == 15 ? 2 : 1, photoCount: 4,
                    startCoordinate: points.first, endCoordinate: points.last, polyline: Polyline.encode(points), deviceName: "Apple Watch Ultra 3"
                ), utcOffset: 2)
            case 11, 14:
                run(d, at: (7, 15), km: rng.range(12...19), pace: 520, hr: 155, name: "Chamonix trail run", place: Self.chamonix,
                    utcOffset: 2, sport: .trailRun, climb: rng.range(800...1350), shape: .outAndBack)
            default:
                break
            }
        }

        mutating func race(_ d: LocalDay, km: Double, seconds: Double, name: String, place: Coordinate?, athletes: Int, kudos: Int) {
            run(d, at: (9, 30), km: km, pace: seconds / km, hr: km > 30 ? 166 : 173, name: name, athletes: athletes, gear: "g2",
                place: place, utcOffset: place == nil ? 1 : 2, shape: .bigLoop, race: true, effortBoost: 0.985, kudosBonus: kudos,
                notes: km > 30 ? "Couldn't have done it without Maya and Leo's long runs. Sub 3:45!" : nil)
        }

        enum Shape { case loop, outAndBack, track, bigLoop }

        mutating func run(_ d: LocalDay, at time: (Int, Int), km: Double, pace: Double, hr: Double, name: String,
                          athletes: Int = 1, gear: String = "g1", place: Coordinate? = nil, utcOffset: Int? = nil,
                          sport: Sport = .run, climb: Double? = nil, shape kind: Shape, race: Bool = false,
                          effortBoost: Double = 0.985, kudosBonus: Int = 0, notes: String? = nil) {
            let meters = km * 1000
            let moving = meters / 1000 * pace
            let origin = place ?? DemoData.home
            let points = shape(kind, around: origin, km: km)
            var efforts: [BestEffort] = []
            for standard in [StandardDistance.k1, .mile, .k5, .k10, .half, .k30, .marathon] where standard.meters <= meters + 1 {
                // Fastest stretch inside the run: intervals make short efforts quick.
                let factor = standard.meters <= 1700 ? effortBoost : max(effortBoost, 0.95)
                let t = (standard.meters / 1000 * pace * factor * rng.range(0.985...1.03)).rounded()
                var rank: Int?
                if let best = bests[standard] {
                    if t < best { rank = 1; bests[standard] = t } else if t < best * 1.02 { rank = 2 }
                } else if standard.meters >= 30_000 {
                    rank = 1
                    bests[standard] = t
                }
                efforts.append(BestEffort(name: standard.title, distance: standard.meters, elapsedTime: t, movingTime: t, prRank: rank))
            }
            let prs = efforts.filter { $0.prRank == 1 }.count
            let base = Int(rng.range(2...9)) + Int(km / 6) + (athletes > 1 ? 4 : 0)
            emit(Activity(
                id: newID(), name: name, sport: sport, start: d.date, startLocal: Floating.date(d, hour: time.0, minute: time.1),
                timezone: place == nil ? "Europe/London" : "Local", distance: meters, movingTime: moving, elapsedTime: moving * (race ? 1.0 : 1.04),
                elevationGain: climb ?? (km * rng.range(3...9)), averageSpeed: 1000 / pace, maxSpeed: 1000 / pace * 1.35,
                averageHeartrate: hr, maxHeartrate: hr + 14, sufferScore: km * 6,
                kudos: base + kudosBonus, comments: race ? 12 : Int(rng.range(0...2)), achievements: prs + Int(rng.range(0...2)), prCount: prs,
                athleteCount: athletes, photoCount: race ? 3 : (rng.chance(0.08) ? 1 : 0),
                startCoordinate: points.first, endCoordinate: points.last, polyline: Polyline.encode(points),
                deviceName: "Apple Watch Ultra 3", gearID: gear, workoutType: race ? 1 : nil,
                details: ActivityDetails(description: notes, calories: nil, bestEfforts: efforts, fetchedAt: d.date)
            ), utcOffset: utcOffset ?? offset(d))
        }

        mutating func ride(_ d: LocalDay, at time: (Int, Int), km: Double, speed kmh: Double, name: String, commute: Bool = false, athletes: Int, shape kind: Shape) {
            let meters = km * 1000
            let v = kmh / 3.6
            let points = shape(kind, around: DemoData.home, km: kind == .bigLoop ? km : km)
            emit(Activity(
                id: newID(), name: name, sport: .ride, start: d.date, startLocal: Floating.date(d, hour: time.0, minute: time.1),
                timezone: "Europe/London", distance: meters, movingTime: meters / v, elapsedTime: meters / v * 1.08,
                elevationGain: km * rng.range(4...9), averageSpeed: v, maxSpeed: v * 1.8, averageHeartrate: 138,
                averageWatts: commute ? nil : rng.range(170...205), kilojoules: commute ? nil : meters / v * rng.range(0.17...0.2),
                kudos: Int(rng.range(1...6)) + (athletes > 1 ? 5 : 0) + Int(km / 25), achievements: Int(rng.range(0...3)),
                athleteCount: athletes, startCoordinate: points.first, endCoordinate: points.last, polyline: Polyline.encode(points),
                deviceName: "Garmin Edge 1050", gearID: "b1", isCommute: commute
            ), utcOffset: offset(d))
        }

        // MARK: Helpers

        mutating func newID() -> Int64 {
            nextID += Int64(rng.range(900...4000))
            return nextID
        }

        /// UK summer time, roughly.
        func offset(_ d: LocalDay) -> Int { (4...10).contains(d.month) ? 1 : 0 }

        mutating func emit(_ activity: Activity, utcOffset: Int) {
            var a = activity
            a.start = a.startLocal.addingTimeInterval(TimeInterval(-utcOffset * 3600))
            out.append(a)
        }

        /// A plausible route shape starting at `origin`.
        mutating func shape(_ kind: Shape, around origin: Coordinate, km: Double) -> [Coordinate] {
            let kLon = 1 / (111.32 * cos(origin.latitude * .pi / 180))
            let kLat = 1 / 110.54
            let heading = rng.range(0...(2 * .pi))
            var points: [Coordinate] = []
            switch kind {
            case .track:
                // 400 m oval near the track, a few laps' worth of points.
                for i in 0..<36 {
                    let t = Double(i) / 36 * 2 * .pi
                    let x = cos(t) * 0.085, y = sin(t) * 0.037
                    points.append(Coordinate(origin.latitude + y * kLat, origin.longitude + x * kLon))
                }
                points.append(points[0])
            case .loop, .bigLoop:
                // Wobbly loop whose perimeter is about `km`.
                let radius = km / (2 * .pi) * (kind == .bigLoop ? 0.9 : 1)
                let cx = origin.longitude + cos(heading) * radius * kLon
                let cy = origin.latitude + sin(heading) * radius * kLat
                let n = 48
                let a1 = rng.range(0.08...0.22), a2 = rng.range(0.04...0.12), p1 = rng.range(0...6), p2 = rng.range(0...6)
                for i in 0...n {
                    let t = heading + .pi + Double(i) / Double(n) * 2 * .pi
                    let r = radius * (1 + a1 * sin(3 * t + p1) + a2 * sin(5 * t + p2))
                    let rr = i == 0 || i == n ? radius : r
                    points.append(Coordinate(cy + sin(t) * rr * kLat, cx + cos(t) * rr * kLon))
                }
            case .outAndBack:
                // Along a winding "river", out and back on a slightly offset line.
                let half = km / 2
                let n = 30
                var out: [Coordinate] = []
                for i in 0...n {
                    let s = Double(i) / Double(n) * half
                    let wiggle = sin(s * 1.3 + heading) * 0.35
                    let x = cos(heading) * s - sin(heading) * wiggle
                    let y = sin(heading) * s + cos(heading) * wiggle
                    out.append(Coordinate(origin.latitude + y * kLat, origin.longitude + x * kLon))
                }
                let back = out.reversed().map { Coordinate($0.latitude + 0.0004, $0.longitude + 0.0004) }
                points = out + back
            }
            return points
        }
    }
}
