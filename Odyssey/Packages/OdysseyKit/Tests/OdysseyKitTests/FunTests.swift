import Foundation
import Testing
@testable import OdysseyKit

@Suite("Equivalents")
struct EquivalentsTests {
    @Test func journeyCatalogIsSane() {
        let ids = JourneyCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let parisNYC = JourneyCatalog.journey("paris-nyc")
        #expect(parisNYC?.lengthKm == 5837)
        #expect(JourneyCatalog.journey("london-paris")?.lengthKm == 344)
        #expect(JourneyCatalog.journey("columbus")?.lengthKm == 7090)
        for j in JourneyCatalog.all where j.isMappable {
            let drawn = Geo.pathLengthKm(j.waypoints)
            switch j.kind {
            case .city, .flight, .crossing, .voyage:
                // Lengths are the drawn great circles.
                #expect(abs(drawn - j.lengthKm) / j.lengthKm < 0.01, "\(j.id): drawn \(drawn) vs \(j.lengthKm)")
            default:
                // Winding routes are drawn through a few waypoints, so the
                // sketch is shorter than the real thing, never longer.
                #expect(drawn > j.lengthKm * 0.2 && drawn < j.lengthKm * 1.25, "\(j.id): drawn \(drawn) vs \(j.lengthKm)")
            }
        }
    }

    @Test func headlinePicksLongestCompletedTrip() {
        #expect(EquivalentFinder.headline(forKm: 5900)?.journey.id == "paris-nyc")
        #expect(EquivalentFinder.headline(forKm: 4000)?.journey.id == "appalachian")
        #expect(EquivalentFinder.headline(forKm: 3496)?.journey.id == "appalachian")
        #expect(EquivalentFinder.headline(forKm: 400)?.journey.id == "london-paris")
        #expect(EquivalentFinder.headline(forKm: 330)?.journey.id == "nyc-boston")
        #expect(EquivalentFinder.headline(forKm: 90)?.journey.id == "channel")
        let short = EquivalentFinder.headline(forKm: 12)
        #expect(short?.journey.id == "manhattan")
        #expect((short?.multiple ?? 2) < 1)
        let huge = EquivalentFinder.headline(forKm: 90_000)
        #expect(huge?.journey.id == "equator")
        #expect(abs((huge?.multiple ?? 0) - 90_000 / 40_075) < 1e-9)
    }

    @Test func climbs() {
        let (big, more) = EquivalentFinder.climb(forMeters: 12_000)
        #expect(big?.landmark.id == "everest")
        #expect(abs((big?.multiple ?? 0) - 12_000 / 8849) < 1e-9)
        #expect(more.contains { $0.landmark.id == "eiffel" })
        let (small, _) = EquivalentFinder.climb(forMeters: 500)
        #expect(small?.landmark.id == "empire")
        let (tiny, _) = EquivalentFinder.climb(forMeters: 40)
        #expect(tiny?.landmark.id == "liberty")
        #expect((tiny?.multiple ?? 1) < 1)
    }

    @Test func narratorLines() {
        let n = Narrator(units: Units(.metric, locale: enUS))
        let paris = DistanceEquivalent(journey: JourneyCatalog.journey("paris-nyc")!, multiple: 6237.0 / 5837.0)
        #expect(n.journeyLine(paris) == "Paris → New York")
        #expect(n.journeyDetail(paris, totalMeters: 6_237_000) == "the transatlantic flight — with 400 km to spare")
        let manhattan = DistanceEquivalent(journey: JourneyCatalog.journey("manhattan")!, multiple: 0.5)
        #expect(n.journeyLine(manhattan) == "50% of the way from Battery Park to Inwood")
        let trail = DistanceEquivalent(journey: JourneyCatalog.journey("appalachian")!, multiple: 0.99)
        #expect(n.journeyLine(trail) == "99% of the Appalachian Trail")
        let moon = DistanceEquivalent(journey: JourneyCatalog.journey("moon")!, multiple: 0.0123)
        #expect(n.journeyLine(moon) == "1.2% of the way to the Moon")
        #expect(n.percentChange(0.234) == "+23%")
        #expect(n.percentChange(-0.08) == "−8%")
        #expect(n.multiple(1.26) == "1.3×")
        let everest = ClimbEquivalent(landmark: Landmark.landmark("everest")!, multiple: 1.36)
        #expect(n.climbLine(everest) == "1.4 Everests")
        #expect(n.trackLaps(3210.4) == "3,210 laps of a 400 m track")

        let imperial = Narrator(units: Units(.imperial, locale: enUS))
        let h = Highlight(kind: .longest, day: LocalDay(year: 2026, month: 4, day: 12), activityID: 1, name: "Long one", sport: .run, value: 32_186.88)
        #expect(imperial.headline(h) == "On Sun, Apr 12 you ran 20.0 mi")
        #expect(imperial.detail(h) == "Your longest run — “Long one”")
        #expect(n.previousLabel(for: RecapRange(.year(2026))) == "vs 2025")
        #expect(n.previousLabel(for: RecapRange(.quarter(year: 2026, quarter: 1))) == "vs Q4 2025")
        #expect(n.previousLabel(for: RecapRange(.month(year: 2026, month: 3))) == "vs February")
    }

    @Test func units() {
        let metric = Units(.metric, locale: enUS)
        let imperial = Units(.imperial, locale: enUS)
        #expect(metric.distance(1_234_567) == "1,235 km")
        #expect(metric.distance(12_400) == "12.4 km")
        #expect(imperial.distance(16_093.44) == "10.0 mi")
        #expect(metric.pace(secondsPerMeter: 0.272) == "4:32 /km")
        #expect(imperial.pace(secondsPerMeter: 0.272) == "7:18 /mi")
        #expect(metric.elevation(1240) == "1,240 m")
        #expect(imperial.elevation(1000) == "3,281 ft")
        #expect(metric.speed(10) == "36.0 km/h")
        #expect(Units.clock(3753) == "1:02:33")
        #expect(Units.clock(2535) == "42:15")
        #expect(Units.hoursMinutes(11_100) == "3h 05m")
        #expect(metric.swimPace(secondsPerMeter: 1.12) == "1:52 /100m")
    }
}

@Suite("Demo data")
struct DemoTests {
    @Test func isDeterministicAndRich() {
        let a = DemoData.activities()
        let b = DemoData.activities()
        #expect(a == b)
        #expect(a.count > 400)
        #expect(a.allSatisfy { $0.day <= DemoData.anchor })
        #expect(Set(a.map(\.id)).count == a.count)
    }

    @Test func tellsAGoodStoryFor2026() {
        let library = DemoData.library()
        let recap = RecapBuilder.build(
            from: library.activities, range: RecapRange(.year(2026)),
            options: RecapOptions(today: DemoData.anchor, athlete: DemoData.athlete)
        )
        #expect(recap.totals.count > 200)
        #expect(recap.totals.distance > 3_000_000 && recap.totals.distance < 9_000_000)
        #expect(recap.totals.elevationGain > 8000)
        #expect(recap.equivalents.headline?.journey.isMappable == true)
        #expect(recap.highlight(.race)?.name?.contains("Berlin") == true)
        #expect(recap.highlight(.furthestAway) != nil)
        #expect(recap.highlight(.earliestStart)?.name?.contains("Sunrise") == true)
        #expect(recap.highlight(.latestStart)?.name?.contains("Midsummer") == true)
        let topCrew = recap.crew.companions.prefix(2).map(\.name)
        #expect(Set(topCrew) == ["Maya", "Leo"])
        #expect(recap.crew.companions.contains { $0.name == "Sam" })
        #expect(recap.crew.companions.contains { $0.name == "Dad" } == false) // Christmas 2025 is outside 2026
        let half = recap.personalBests.items.first { $0.distance == .half }
        #expect(half?.prs.isEmpty == false)
        #expect(recap.personalBests.items.contains { $0.distance == .marathon })
        #expect(recap.progression.runPace.map { $0.end < $0.start } == true)
        #expect(recap.routes.count >= 20)
        #expect(recap.gear.first?.name == "Road bike")
        #expect(recap.devices.first?.name == "Apple Watch Ultra 3")
        let pages = StoryScript.pages(for: recap)
        #expect(pages == StoryPage.allCases)
    }
}
