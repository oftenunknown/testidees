import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only Strava API v3 client.
public struct StravaClient: Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String
    public typealias RateLimitObserver = @Sendable (RateLimitStatus) -> Void

    public static let baseURL = URL(string: "https://www.strava.com/api/v3/")!

    let http: any HTTPClient
    let token: TokenProvider
    let observeRateLimit: RateLimitObserver?
    let now: @Sendable () -> Date

    public init(http: any HTTPClient = URLSessionHTTPClient(), token: @escaping TokenProvider,
                observeRateLimit: RateLimitObserver? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.token = token
        self.observeRateLimit = observeRateLimit
        self.now = now
    }

    /// `GET /athlete`
    public func athlete() async throws -> Athlete {
        let data = try await get("athlete")
        do {
            return try JSONDecoder().decode(AthleteDTO.self, from: data).athlete
        } catch {
            throw StravaError.decoding("profile")
        }
    }

    /// `GET /athlete/activities` — one page, newest first unless `after` is set.
    public func activities(after: Date? = nil, before: Date? = nil, page: Int = 1, perPage: Int = 200) async throws -> [Activity] {
        var query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: String(perPage))]
        if let after { query.append(URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970)))) }
        if let before { query.append(URLQueryItem(name: "before", value: String(Int(before.timeIntervalSince1970)))) }
        let data = try await get("athlete/activities", query: query)
        do {
            let dtos = try JSONDecoder().decode([LossyElement<ActivityDTO>].self, from: data)
            return dtos.compactMap { $0.value?.activity }
        } catch {
            throw StravaError.decoding("activity list")
        }
    }

    /// Every activity between two instants, following pages.
    public func allActivities(after: Date, before: Date, perPage: Int = 200, maxPages: Int = 50,
                              onPage: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [Activity] {
        var all: [Activity] = []
        for page in 1...maxPages {
            let batch = try await activities(after: after, before: before, page: page, perPage: perPage)
            all += batch
            onPage?(page, all.count)
            if batch.count < perPage { break }
        }
        return all
    }

    /// `GET /activities/{id}` — the activity plus description, calories and best efforts.
    public func detailedActivity(id: Int64) async throws -> (activity: Activity, details: ActivityDetails) {
        let data = try await get("activities/\(id)", query: [URLQueryItem(name: "include_all_efforts", value: "false")])
        do {
            let dto = try JSONDecoder().decode(ActivityDTO.self, from: data)
            guard var activity = dto.activity else { throw StravaError.decoding("activity") }
            let details = dto.details(fetchedAt: now())
            activity.details = details
            return (activity, details)
        } catch let error as StravaError {
            throw error
        } catch {
            throw StravaError.decoding("activity")
        }
    }

    // MARK: - Transport

    func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        guard var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw StravaError.badResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw StravaError.badResponse }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        let status = RateLimitStatus(header: { response.value(forHTTPHeaderField: $0) }, at: now())
        if let status { observeRateLimit?(status) }
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw StravaError.unauthorized
        case 403:
            throw StravaError.forbidden
        case 404:
            throw StravaError.notFound
        case 429:
            throw StravaError.rateLimited(status)
        default:
            let message = (try? JSONDecoder().decode(FaultDTO.self, from: data))?.message
            throw StravaError.server(status: response.statusCode, message: message)
        }
    }
}

/// Decodes array elements one by one, skipping any that fail.
struct LossyElement<T: Decodable>: Decodable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
