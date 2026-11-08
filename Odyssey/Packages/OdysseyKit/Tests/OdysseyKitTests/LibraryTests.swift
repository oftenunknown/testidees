import Foundation
import Testing
@testable import OdysseyKit

@Suite("Library and sync planning")
struct LibraryTests {
    let jan1 = LocalDay(year: 2026, month: 1, day: 1)

    @Test func mergeReplacesWindowAndKeepsDetails() {
        let a = makeActivity(id: 1, day: jan1, efforts: [BestEffort(name: "5k", distance: 5000, elapsedTime: 1500, prRank: 1)])
        let b = makeActivity(id: 2, day: jan1.adding(days: 1))
        let c = makeActivity(id: 3, day: jan1.adding(days: 40))
        var library = ActivityLibrary()
        let window = TimeSpan(start: jan1.date, end: jan1.adding(days: 10).date)
        library.merge([a, b], covering: window)
        library.merge([c], covering: TimeSpan(start: jan1.adding(days: 35).date, end: jan1.adding(days: 45).date))
        #expect(library.count == 3)

        // Re-sync the first window: activity 2 was deleted on Strava, 1 was renamed.
        var renamed = a
        renamed.name = "Renamed"
        renamed.details = nil
        library.merge([renamed], covering: window)
        #expect(library.count == 2)
        #expect(library.byID[1]?.name == "Renamed")
        #expect(library.byID[1]?.details?.bestEfforts.count == 1)
        #expect(library.byID[2] == nil)
        #expect(library.coverage.count == 2)
    }

    @Test func findsGaps() {
        let library = ActivityLibrary(coverage: [
            TimeSpan(start: jan1.date, end: jan1.adding(days: 10).date),
            TimeSpan(start: jan1.adding(days: 20).date, end: jan1.adding(days: 30).date),
        ])
        let gaps = library.missing(TimeSpan(start: jan1.adding(days: -5).date, end: jan1.adding(days: 40).date))
        #expect(gaps.count == 3)
        #expect(gaps[0].end == jan1.date)
        #expect(gaps[1].start == jan1.adding(days: 10).date)
        #expect(gaps[1].end == jan1.adding(days: 20).date)
        #expect(gaps[2].start == jan1.adding(days: 30).date)
        #expect(library.missing(TimeSpan(start: jan1.adding(days: 2).date, end: jan1.adding(days: 8).date)).isEmpty)
    }

    @Test func planIncludesRecentRefresh() {
        let now = jan1.adding(days: 60).date
        var library = ActivityLibrary(coverage: [TimeSpan(start: jan1.adding(days: -400).date, end: now)])
        #expect(library.syncPlan(for: [DayRange(first: jan1, last: jan1.adding(days: 59))], now: now).isEmpty)
        library.lastSync = jan1.adding(days: 59).date
        let plan = library.syncPlan(for: [DayRange(first: jan1, last: jan1.adding(days: 59))], now: now)
        #expect(plan.count == 1)
        #expect(plan[0].start == jan1.adding(days: 56).date)
    }

    @Test func coveringPadsForTimeZones() {
        let span = TimeSpan.covering(DayRange(first: jan1, last: jan1))
        #expect(span.start < jan1.date)
        #expect(span.end > jan1.adding(days: 1).date)
    }

    @Test func detailPlannerPrioritisesPRsAndGroups() {
        var pr = makeActivity(id: 1, day: jan1)
        pr.prCount = 2
        pr.details = nil
        var group = makeActivity(id: 2, day: jan1.adding(days: 1), athletes: 3)
        group.details = nil
        var long = makeActivity(id: 3, day: jan1.adding(days: 2), km: 21)
        long.details = nil
        let done = makeActivity(id: 4, day: jan1.adding(days: 3), efforts: [])
        var ride = makeActivity(id: 5, day: jan1.adding(days: 4), sport: .ride, km: 40)
        ride.details = nil
        let ids = DetailPlanner.candidates(in: [ride, long, group, pr, done], limit: 10)
        #expect(ids == [1, 2, 3])
        #expect(DetailPlanner.candidates(in: [ride, long, group, pr, done], limit: 1) == [1])
    }
}

@Suite("Polylines")
struct PolylineTests {
    @Test func decodesGoogleExample() {
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(points.count == 3)
        #expect(points[0] == Coordinate(38.5, -120.2))
        #expect(points[1] == Coordinate(40.7, -120.95))
        #expect(points[2] == Coordinate(43.252, -126.453))
        #expect(Polyline.encode(points) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    }

    @Test func roundTripsAndSimplifies() {
        let line = (0...100).map { Coordinate(51.5 + Double($0) * 0.0001, -0.1 + Double($0) * 0.0001) }
        let decoded = Polyline.decode(Polyline.encode(line))
        #expect(decoded.count == 101)
        #expect(abs(decoded[50].latitude - 51.505) < 1e-6)
        // A straight line simplifies to its ends.
        #expect(Polyline.simplify(line, toleranceMeters: 5).count == 2)
    }

    @Test func trimsEnds() {
        let line = (0...100).map { Coordinate(51.5 + Double($0) * 0.001, -0.1) } // ~11 km
        let trimmed = Polyline.trimmingEnds(line, meters: 500)
        #expect(Geo.distanceKm(line[0], trimmed[0]) >= 0.5)
        #expect(Geo.distanceKm(line[100], trimmed.last!) >= 0.5)
        #expect(Polyline.trimmingEnds(Array(line.prefix(5)), meters: 500).isEmpty)
    }
}

@Suite("Geography")
struct GeoTests {
    @Test func greatCircle() {
        let paris = Coordinate(48.8566, 2.3522), nyc = Coordinate(40.7128, -74.0060)
        #expect(abs(Geo.distanceKm(paris, nyc) - 5837) < 2)
        let mid = Geo.interpolate(paris, nyc, 0.5)
        #expect(abs(Geo.distanceKm(paris, mid) - Geo.distanceKm(mid, nyc)) < 1)
        // The great circle bows north of both cities.
        #expect(mid.latitude > 48.8566)
        let path = Geo.densify([paris, nyc], stepKm: 100)
        #expect(abs(Geo.pathLengthKm(path) - 5837) < 3)
        let half = Geo.prefix(of: path, fraction: 0.5)
        #expect(abs(Geo.pathLengthKm(half) - 2918) < 5)
    }

    @Test func viewportFitsAndProjects() {
        let points = [Coordinate(48.8566, 2.3522), Coordinate(40.7128, -74.0060)]
        let v = GeoViewport.fitting(points, aspect: 1.5)
        #expect(abs(v.aspectRatio - 1.5) < 0.01)
        for p in points {
            let xy = v.project(p)
            #expect((0...1).contains(xy.x) && (0...1).contains(xy.y))
        }
        // Across the antimeridian stays compact.
        let pacific = GeoViewport.fitting([Coordinate(35.6762, 139.6503), Coordinate(21.3069, -157.8583)], aspect: 1.5)
        #expect(pacific.lonSpan < 180)
    }

    @Test func worldMapKnowsLand() {
        #expect(WorldMap.isLand(Coordinate(51.5, -0.12)))     // London
        #expect(WorldMap.isLand(Coordinate(-25, 134)))        // Australia
        #expect(!WorldMap.isLand(Coordinate(40, -40)))        // mid-Atlantic
        #expect(!WorldMap.isLand(Coordinate(0, -150)))        // Pacific
        let world = WorldMap.dots(in: .world, targetColumns: 90)
        #expect(world.dots.count > 800)
        #expect(world.dots.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }
}
