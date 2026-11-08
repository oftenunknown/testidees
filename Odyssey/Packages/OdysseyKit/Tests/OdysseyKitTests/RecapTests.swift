import Foundation
import Testing
@testable import OdysseyKit

@Suite("Recap")
struct RecapTests {
    static let today = LocalDay(year: 2026, month: 3, day: 31)
    static func d(_ m: Int, _ day: Int, _ y: Int = 2026) -> LocalDay { LocalDay(year: y, month: m, day: day) }
    static let chamonix = Coordinate(45.92, 6.87)

    static let activities: [Activity] = [
        makeActivity(id: 1, day: d(1, 5), km: 10, minutes: 55, efforts: [
            BestEffort(name: "1k", distance: 1000, elapsedTime: 280),
            BestEffort(name: "5k", distance: 5000, elapsedTime: 1500, prRank: 1),
        ]),
        makeActivity(id: 2, day: d(1, 6), hour: 18, km: 5, minutes: 25, name: "Track with Maya & Leo", athletes: 4),
        makeActivity(id: 3, day: d(1, 7), hour: 6, km: 8, minutes: 44, hr: 150),
        makeActivity(id: 4, day: d(1, 10), hour: 9, sport: .ride, km: 60, minutes: 120, climb: 600, name: "Hills with Maya", kudos: 12, athletes: 3),
        makeActivity(id: 5, day: d(1, 20), hour: 20, minute: 30, km: 6, minutes: 33, name: "Night run"),
        makeActivity(id: 6, day: d(2, 2), km: 21.1, minutes: 115, climb: 150, name: "City Half", kudos: 40, efforts: [
            BestEffort(name: "5k", distance: 5000, elapsedTime: 1480, prRank: 1),
            BestEffort(name: "Half-Marathon", distance: 21097.5, elapsedTime: 6900, prRank: 1),
        ], workoutType: 1),
        makeActivity(id: 7, day: d(2, 15), hour: 8, sport: .hike, km: 15, minutes: 300, climb: 1200, name: "Alps", start: chamonix),
        makeActivity(id: 8, day: d(3, 1), hour: 12, sport: .swim, km: 2, minutes: 40, climb: 0, name: "Lunch Swim", start: nil),
        makeActivity(id: 9, day: d(3, 3), hour: 12, sport: .weightTraining, km: 0, minutes: 50, climb: 0, name: "Afternoon Weight Training", start: nil),
        // Previous period (Q4 2025).
        makeActivity(id: 10, day: d(11, 1, 2025), km: 5, minutes: 30),
    ]

    func recap(tags: [Int64: [String]] = [:], hidden: Set<String> = [], filter: SportFilter = .all) -> Recap {
        RecapBuilder.build(
            from: Self.activities,
            range: RecapRange(.quarter(year: 2026, quarter: 1)),
            filter: filter,
            options: RecapOptions(today: Self.today, weightKg: 70, crewTags: tags, hiddenCompanions: hidden)
        )
    }

    @Test func totals() {
        let r = recap()
        #expect(r.totals.count == 9)
        #expect(abs(r.totals.distance - 127_100) < 0.5)
        #expect(r.totals.activeDays == 9)
        #expect(r.totals.groupActivities == 2)
        #expect(r.totals.races == 1)
        #expect(abs(r.totals.runDistance - 50_100) < 0.5)
        #expect(r.totals.energy > 4000)
        #expect(r.totals.energyEstimatedShare == 1)
        #expect(r.sports.first?.family == .walk) // the 5-hour hike dominates moving time
        #expect(r.sports.count == 5)
        #expect(abs(r.sports.reduce(0) { $0 + $1.share } - 1) < 1e-9)
    }

    @Test func comparesWithPreviousPeriod() {
        let r = recap()
        #expect(r.previous?.count == 1)
        #expect(r.previousDays?.start == Self.d(10, 1, 2025))
        #expect(r.previousDays?.last == Self.d(12, 31, 2025))
        let change = r.progression.vsPrevious?.distance
        #expect(abs((change ?? 0) - (127.1 / 5 - 1)) < 1e-6)
    }

    @Test func calendarAndStreaks() {
        let r = recap()
        #expect(r.calendar.activeDays.count == 9)
        #expect(r.calendar.months.count == 3)
        #expect(r.calendar.bestMonth?.start == Self.d(1, 1))
        #expect(r.calendar.bestWeek?.start == Self.d(1, 5))
        #expect(r.streaks.longestDays?.length == 3)
        #expect(r.streaks.longestDays?.start == Self.d(1, 5))
        #expect(r.streaks.longestBreak?.length == 13) // Feb 16 → Feb 28
        #expect(r.progression.granularity == .week)
        #expect(r.progression.buckets.reduce(0) { $0 + $1.count } == 9)
    }

    @Test func rhythm() {
        let r = recap()
        #expect(r.rhythm.weekdayCounts.reduce(0, +) == 9)
        #expect(r.rhythm.earliest?.activityID == 3)
        #expect(r.rhythm.latest?.activityID == 5)
        #expect(r.rhythm.favoriteWeekday == 0 || r.rhythm.favoriteWeekday == 1)
        #expect(abs(r.rhythm.earlyShare - 3.0 / 9.0) < 1e-9)
    }

    @Test func highlights() {
        let r = recap()
        #expect(r.highlight(.longest)?.activityID == 4)
        #expect(r.highlight(.biggestClimb)?.activityID == 7)
        #expect(r.highlight(.fastestRun)?.activityID == 2)
        #expect(r.highlight(.mostKudos)?.activityID == 6)
        #expect(r.highlight(.race)?.activityID == 6)
        #expect(r.highlight(.earliestStart)?.activityID == 3)
        #expect(r.highlight(.latestStart)?.activityID == 5)
        let far = r.highlight(.furthestAway)
        #expect((far?.value ?? 0) > 700)
        #expect(r.places.home == Coordinate(51.5, -0.1))
        #expect(StoryScript.moments(for: r).first?.kind == .race)
        // The half was both the race and a PR; the 5K PR on Feb 2 is the same activity,
        // so the PB moment is skipped as a repeat, but the highlight itself exists.
        let pb = r.highlight(.personalBest)
        #expect(pb?.activityID == 6)
        #expect(pb?.secondary == StandardDistance.k5.meters)
        #expect(Narrator(units: Units(.metric, locale: enUS)).headline(pb!) == "On Mon, Feb 2 you set a 5K PB: 24:40")
    }

    @Test func personalBests() {
        let r = recap()
        let k5 = r.personalBests.items.first { $0.distance == .k5 }
        #expect(k5?.best.time == 1480)
        #expect(k5?.prs.count == 2)
        #expect(k5?.first.time == 1500)
        #expect(k5?.improvement == 20)
        #expect(r.personalBests.prCount == 3)
        #expect(r.personalBests.runsChecked == 2)
        #expect(r.personalBests.runsTotal == 5)
        #expect(r.personalBests.items.map(\.distance) == [.k1, .k5, .half])
    }

    @Test func crewFromMentionsAndTags() {
        let mentioned = recap()
        #expect(mentioned.crew.companions.map(\.name) == ["Maya", "Leo"])
        #expect(mentioned.crew.companions.first?.count == 2)
        #expect(mentioned.crew.groupCount == 2)
        #expect(mentioned.crew.untaggedGroupIDs.isEmpty)

        let tagged = recap(tags: [4: ["Priya"]])
        #expect(tagged.crew.companions.map(\.name) == ["Priya", "Leo", "Maya"])
        #expect(tagged.crew.companions.first?.confirmed == true)

        let hidden = recap(hidden: ["leo"])
        #expect(hidden.crew.companions.map(\.name) == ["Maya"])
    }

    @Test func filterBySport() {
        let runs = recap(filter: .family(.run))
        #expect(runs.totals.count == 5)
        #expect(runs.mainFamily == .run)
        #expect(runs.sports.count == 1)
    }

    @Test func namingAndStory() {
        let r = recap()
        #expect(r.naming.defaultNamed == 4) // 2× Morning Run, Lunch Swim, Afternoon Weight Training
        #expect(r.naming.topDefaultName == "Morning Run")
        #expect(RecapBuilder.isDefaultName("Evening Ride"))
        #expect(!RecapBuilder.isDefaultName("Morning run with Maya"))
        let pages = StoryScript.pages(for: r)
        #expect(pages.first == .intro && pages.last == .outro)
        #expect(pages.contains(.journey))
        #expect(pages.contains(.bests))
        #expect(pages.contains(.crew))
        #expect(pages.contains(.climb))
    }

    @Test func emptyRange() {
        let r = RecapBuilder.build(from: Self.activities, range: RecapRange(.month(year: 2026, month: 6)), options: RecapOptions(today: Self.today))
        #expect(r.isEmpty)
        #expect(StoryScript.pages(for: r) == [.intro, .outro])
    }

    @Test func paceTrend() {
        // Twelve runs getting steadily faster: 6:00/km → 5:00/km.
        let runs = (0..<12).map { i in
            makeActivity(id: Int64(100 + i), day: Self.d(1, 2).adding(days: i * 7), km: 10, minutes: 60 - Double(i) * 10 / 11, hr: 150)
        }
        let r = RecapBuilder.build(from: runs, range: RecapRange(.quarter(year: 2026, quarter: 1)), options: RecapOptions(today: Self.today))
        let trend = r.progression.runPace
        #expect(abs((trend?.start ?? 0) - 0.36) < 0.002)
        #expect(abs((trend?.end ?? 0) - 0.30) < 0.002)
        #expect((r.progression.runEfficiency?.relativeChange ?? 0) > 0.15)
        #expect(r.persona.primary == .speedDemon || r.persona.traits.contains(.speedDemon))
    }
}

@Suite("Crew detection")
struct CrewDetectorTests {
    @Test(arguments: [
        ("Long run with Maya & Leo", ["Maya", "Leo"]),
        ("Track Tuesday w/ Leo, Maya and Sam!", ["Leo", "Maya", "Sam"]),
        ("Easy spin with the club", []),
        ("Run with Coach Dan", ["Dan"]),
        ("Parkrun with Mum and Dad", ["Mum", "Dad"]),
        ("Ran with Anna Smith today", ["Anna Smith"]),
        ("Hills with @jamie_runs and Priya", ["Jamie_runs", "Priya"]),
        ("Morning Run", []),
        ("Run with friends", []),
        ("Coffee ride with Maya ☕️", ["Maya"]),
        ("Sortie avec Chloé et Hugo", ["Chloé", "Hugo"]),
        ("with Maya's sister", ["Maya"]),
        ("Intervals with Leo, Maya", ["Leo", "Maya"]),
    ])
    func detects(_ text: String, _ expected: [String]) {
        #expect(CrewDetector.names(in: text) == expected)
    }
}

@Suite("Persona")
struct PersonaTests {
    @Test func evidenceUsesTheAthletesUnits() {
        let runs = (0..<10).map { i in
            makeActivity(id: Int64(500 + i), day: LocalDay(year: 2026, month: 2, day: 1).adding(days: i * 3), hour: 6, km: 16.0934, minutes: 90)
        }
        let range = RecapRange(.quarter(year: 2026, quarter: 1))
        let today = LocalDay(year: 2026, month: 3, day: 31)
        let metric = RecapBuilder.build(from: runs, range: range, options: RecapOptions(today: today))
        let imperial = RecapBuilder.build(from: runs, range: range, options: RecapOptions(today: today, units: .imperial))
        #expect(metric.persona.reason(for: .longHauler) == "Average run 16.1 km")
        #expect(imperial.persona.reason(for: .longHauler) == "Average run 10.0 mi")
        #expect(metric.persona.primary == .longHauler || metric.persona.primary == .dawnPatrol)
    }
}
