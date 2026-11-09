import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OdysseyKit

let summaryJSON = """
[
  {
    "resource_state": 2, "athlete": {"id": 134815, "resource_state": 1},
    "name": "Sunday long run with Maya", "distance": 24931.4, "moving_time": 7712, "elapsed_time": 8005,
    "total_elevation_gain": 112.5, "type": "Run", "sport_type": "Run", "workout_type": null,
    "id": 15432198765, "start_date": "2026-03-01T08:02:13Z", "start_date_local": "2026-03-01T08:02:13Z",
    "timezone": "(GMT+00:00) Europe/London", "utc_offset": 0, "location_city": null,
    "achievement_count": 4, "kudos_count": 19, "comment_count": 2, "athlete_count": 2, "photo_count": 0,
    "map": {"id": "a15432198765", "summary_polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@", "resource_state": 2},
    "trainer": false, "commute": false, "manual": false, "private": false, "flagged": false,
    "gear_id": "g12345", "start_latlng": [51.53, -0.04], "end_latlng": [51.531, -0.041],
    "average_speed": 3.233, "max_speed": 5.1, "has_heartrate": true, "average_heartrate": 148.2,
    "max_heartrate": 171.0, "pr_count": 2, "total_photo_count": 1, "suffer_score": 88.0, "device_name": "Apple Watch Ultra 3"
  },
  {
    "id": 15432198766, "name": "Pool", "sport_type": "Swim", "type": "Swim",
    "start_date": "2026-03-02T11:30:00Z", "start_date_local": "2026-03-02T12:30:00Z",
    "distance": 2000, "moving_time": 2400, "elapsed_time": 2700, "total_elevation_gain": 0,
    "start_latlng": [], "end_latlng": [], "map": {"summary_polyline": null}, "athlete_count": 1, "kudos_count": 2
  },
  { "id": "not-a-number", "name": "Broken" }
]
"""

let detailJSON = """
{
  "id": 15432198765, "name": "Sunday long run with Maya", "sport_type": "Run", "distance": 24931.4,
  "moving_time": 7712, "elapsed_time": 8005, "start_date": "2026-03-01T08:02:13Z", "start_date_local": "2026-03-01T08:02:13Z",
  "description": "  Last 8k with Sam, felt great  ", "calories": 1650.5,
  "best_efforts": [
    {"id": 1, "name": "1k", "distance": 1000, "elapsed_time": 271, "moving_time": 271, "pr_rank": null},
    {"id": 2, "name": "5k", "distance": 5000, "elapsed_time": 1442, "moving_time": 1442, "pr_rank": 1},
    {"id": 3, "name": "Half-Marathon", "distance": 21097, "elapsed_time": 6511, "moving_time": 6500, "pr_rank": 2}
  ]
}
"""

@Suite("Strava API")
struct StravaTests {
    @Test func decodesSummaryActivitiesLeniently() async throws {
        let http = MockHTTP { _ in (200, ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "3,150"], Data(summaryJSON.utf8)) }
        let client = StravaClient(http: http, token: { "abc" })
        let list = try await client.activities(after: Date(timeIntervalSince1970: 1_700_000_000), page: 1, perPage: 50)
        #expect(list.count == 2)
        let run = try #require(list.first)
        #expect(run.id == 15_432_198_765)
        #expect(run.sport == .run)
        #expect(run.distance == 24_931.4)
        #expect(run.athleteCount == 2)
        #expect(run.isGroup)
        #expect(run.prCount == 2)
        #expect(run.photoCount == 1)
        #expect(run.startCoordinate == Coordinate(51.53, -0.04))
        #expect(run.deviceName == "Apple Watch Ultra 3")
        #expect(run.day == LocalDay(year: 2026, month: 3, day: 1))
        #expect(Floating.hour(run.startLocal) == 8)

        let swim = try #require(list.last)
        #expect(swim.startCoordinate == nil)
        #expect(swim.polyline == nil)
        // Local time is an hour ahead of UTC here.
        #expect(Floating.hour(swim.startLocal) == 12)
        #expect(swim.start.timeIntervalSince(swim.startLocal) == -3600)

        let url = try #require(http.requests.first?.url?.absoluteString)
        #expect(url.contains("athlete/activities"))
        #expect(url.contains("after=1700000000"))
        #expect(url.contains("per_page=50"))
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func decodesDetailsAndBestEfforts() async throws {
        let http = MockHTTP { _ in (200, [:], Data(detailJSON.utf8)) }
        let client = StravaClient(http: http, token: { "t" })
        let (activity, details) = try await client.detailedActivity(id: 15_432_198_765)
        #expect(activity.details == details)
        #expect(details.description == "Last 8k with Sam, felt great")
        #expect(details.calories == 1650.5)
        #expect(details.bestEfforts.count == 3)
        #expect(details.bestEfforts[1].standard == .k5)
        #expect(details.bestEfforts[1].prRank == 1)
        #expect(details.bestEfforts[2].standard == .half)
    }

    @Test func mapsErrorsAndRateLimits() async {
        let limited = MockHTTP { _ in (429, ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "201,900", "X-ReadRateLimit-Limit": "100,1000", "X-ReadRateLimit-Usage": "101,600"], Data("{\"message\":\"Rate Limit Exceeded\"}".utf8)) }
        let observed = Observed()
        let client = StravaClient(http: limited, token: { "t" }, observeRateLimit: { observed.set($0) })
        await #expect(throws: StravaError.self) { _ = try await client.athlete() }
        let status = observed.value
        #expect(status != nil)
        #expect(status?.shortUsage == 201)
        #expect(status?.readShortLimit == 100)
        #expect(status?.shortRemaining(at: status!.observedAt) == 0)

        let expired = MockHTTP { _ in (401, [:], Data()) }
        do {
            _ = try await StravaClient(http: expired, token: { "t" }).athlete()
            Issue.record("expected an error")
        } catch {
            #expect(error as? StravaError == .unauthorized)
        }
    }

    @Test func followsPages() async throws {
        let http = MockHTTP { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            let count = page == "1" ? 2 : 1
            let items = (0..<count).map { i in
                "{\"id\": \(Int(page)! * 10 + i), \"name\": \"Run\", \"sport_type\": \"Run\", \"start_date\": \"2026-01-0\(i + 1)T07:00:00Z\", \"start_date_local\": \"2026-01-0\(i + 1)T07:00:00Z\", \"distance\": 5000, \"moving_time\": 1500}"
            }
            return (200, [:], Data("[\(items.joined(separator: ","))]".utf8))
        }
        let client = StravaClient(http: http, token: { "t" })
        let all = try await client.allActivities(after: Date(timeIntervalSince1970: 0), before: Date(), perPage: 2)
        #expect(all.map(\.id) == [10, 11, 20])
        #expect(http.requests.count == 2)
    }

    @Test func rateLimitWindows() {
        let t = Date(timeIntervalSince1970: 1_793_000_000) // 07:33:20 UTC
        #expect(RateLimitStatus.nextShortWindow(after: t).timeIntervalSince1970 == 1_793_000_700)
        let status = RateLimitStatus(shortLimit: 200, shortUsage: 199, dailyLimit: 2000, dailyUsage: 500, readShortLimit: 100, readShortUsage: 60, observedAt: t)
        #expect(status.shortRemaining(at: t) == 1)
        #expect(status.resumeDate(needing: 5, at: t) == RateLimitStatus.nextShortWindow(after: t))
        // A new window restores the budget.
        #expect(status.shortRemaining(at: t.addingTimeInterval(900)) == 100)
    }

    @Test func authorizeURLs() throws {
        let config = StravaAppConfig(clientID: " 12345 ")
        #expect(config.isValid)
        #expect(config.redirectURI == "odysseyrecap://localhost/strava")
        let web = config.authorizeURL(state: "xyz")
        #expect(web.host == "www.strava.com")
        #expect(web.path == "/oauth/mobile/authorize")
        let items = URLComponents(url: web, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first { $0.name == "client_id" }?.value == "12345")
        #expect(items.first { $0.name == "scope" }?.value == "read,activity:read_all,profile:read_all")
        #expect(items.first { $0.name == "state" }?.value == "xyz")
        #expect(items.first { $0.name == "redirect_uri" }?.value == "odysseyrecap://localhost/strava")
        let app = config.authorizeURL(state: "xyz", viaStravaApp: true)
        #expect(app.scheme == "strava")
        #expect(app.absoluteString.hasPrefix("strava://oauth/mobile/authorize?"))
        #expect(!StravaAppConfig(clientID: "abc").isValid)
    }

    @Test func parsesCallbacks() throws {
        let config = StravaAppConfig(clientID: "1")
        let ok = try config.parseCallback(URL(string: "odysseyrecap://localhost/strava?state=s1&code=abc123&scope=read,activity:read_all")!, expectedState: "s1")
        #expect(ok.code == "abc123")
        #expect(ok.scopes.contains("activity:read_all"))
        #expect(throws: StravaError.accessDenied) {
            try config.parseCallback(URL(string: "odysseyrecap://localhost/strava?state=s1&error=access_denied")!, expectedState: "s1")
        }
        #expect(throws: StravaError.stateMismatch) {
            try config.parseCallback(URL(string: "odysseyrecap://localhost/strava?state=evil&code=abc")!, expectedState: "s1")
        }
        #expect(throws: StravaError.missingActivityScope) {
            try config.parseCallback(URL(string: "odysseyrecap://localhost/strava?state=s1&code=abc&scope=read")!, expectedState: "s1")
        }
    }

    @Test func exchangesAndRefreshesDirectly() async throws {
        let http = MockHTTP { request in
            let body = request.bodyString
            if body.contains("grant_type=authorization_code") {
                return (200, [:], Data("""
                {"token_type":"Bearer","access_token":"a1","refresh_token":"r1","expires_at":1793000000,"expires_in":21600,
                 "athlete":{"id":7,"firstname":"Alex","lastname":"R","profile":"avatar/athlete/large.png"}}
                """.utf8))
            }
            #expect(body.contains("refresh_token=r1"))
            return (200, [:], Data("{\"access_token\":\"a2\",\"refresh_token\":\"r2\",\"expires_at\":1793021600}".utf8))
        }
        let exchanger = DirectTokenExchanger(clientID: "1", clientSecret: "s3cret", http: http)
        let tokens = try await exchanger.exchange(code: "abc", scopes: ["activity:read_all"])
        #expect(tokens.accessToken == "a1")
        #expect(tokens.athlete?.firstName == "Alex")
        #expect(tokens.athlete?.profileImageURL == nil)
        #expect(http.requests[0].bodyString.contains("client_secret=s3cret"))

        // Expired: the session refreshes once, even for concurrent callers.
        let updates = Observed()
        let session = StravaSession(tokens: tokens, exchanger: exchanger, onUpdate: { updates.set(tokens: $0) })
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        async let first = session.accessToken(at: now)
        async let second = session.accessToken(at: now)
        let results = try await [first, second]
        #expect(results == ["a2", "a2"])
        #expect(http.requests.count == 2)
        #expect(updates.tokens?.refreshToken == "r2")
        #expect(await session.current.athlete?.firstName == "Alex")
    }

    @Test func usesTokenServer() async throws {
        let http = MockHTTP { request in
            #expect(request.url?.path == "/v1/strava/token")
            #expect(request.bodyString.contains("\"code\":\"abc\""))
            return (200, [:], Data("{\"access_token\":\"a1\",\"refresh_token\":\"r1\",\"expires_at\":1793000000}".utf8))
        }
        let exchanger = ServerTokenExchanger(baseURL: URL(string: "https://odyssey.example.workers.dev")!, http: http)
        let tokens = try await exchanger.exchange(code: "abc", scopes: [])
        #expect(tokens.refreshToken == "r1")
    }

    @Test func explainsRefusedSignIns() async {
        let full = MockHTTP { _ in
            (403, [:], Data(#"{"message":"Forbidden","errors":[{"resource":"Athlete","field":"","code":"limit of connected athletes exceeded"}]}"#.utf8))
        }
        await #expect(throws: StravaError.athleteLimitReached) {
            try await DirectTokenExchanger(clientID: "1", clientSecret: "s", http: full).exchange(code: "abc", scopes: [])
        }
        // The token server passes Strava's answer through unchanged.
        let server = URL(string: "https://odyssey.example.workers.dev")!
        await #expect(throws: StravaError.athleteLimitReached) {
            try await ServerTokenExchanger(baseURL: server, http: full).exchange(code: "abc", scopes: [])
        }
        let notListed = MockHTTP { _ in
            (403, [:], Data(#"{"message":"This Odyssey server isn't open to your Strava account.","code":"athlete_not_allowed"}"#.utf8))
        }
        await #expect(throws: StravaError.athleteNotAllowed) {
            try await ServerTokenExchanger(baseURL: server, http: notListed).exchange(code: "abc", scopes: [])
        }
        let other = MockHTTP { _ in (403, [:], Data(#"{"message":"Forbidden."}"#.utf8)) }
        await #expect(throws: StravaError.server(status: 403, message: "Forbidden.")) {
            try await ServerTokenExchanger(baseURL: server, http: other).exchange(code: "abc", scopes: [])
        }
        #expect(StravaError.server(status: 403, message: "Forbidden.").localizedDescription == "Strava error 403: Forbidden.")
    }

    @Test func parsesAthlete() async throws {
        let http = MockHTTP { _ in (200, [:], Data("""
        {"id": 99, "firstname": "Alex", "lastname": "Rivera", "measurement_preference": "feet", "weight": 68.5,
         "profile": "https://dgalywyr863hv.cloudfront.net/pictures/athletes/99/large.jpg",
         "shoes": [{"id": "g1", "name": "Daily trainers", "distance": 812000.0, "primary": true}],
         "bikes": [{"id": "b1", "name": "Road bike", "distance": 5000000.0}]}
        """.utf8)) }
        let athlete = try await StravaClient(http: http, token: { "t" }).athlete()
        #expect(athlete.displayName == "Alex Rivera")
        #expect(athlete.prefersImperial)
        #expect(athlete.gear.count == 2)
        #expect(athlete.gear.first?.kind == .shoes)
        #expect(athlete.profileImageURL != nil)
    }
}

final class Observed: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: RateLimitStatus?
    private var _tokens: StravaTokens?

    func set(_ v: RateLimitStatus) { lock.lock(); _value = v; lock.unlock() }
    func set(tokens: StravaTokens) { lock.lock(); _tokens = tokens; lock.unlock() }
    var value: RateLimitStatus? { lock.lock(); defer { lock.unlock() }; return _value }
    var tokens: StravaTokens? { lock.lock(); defer { lock.unlock() }; return _tokens }
}
