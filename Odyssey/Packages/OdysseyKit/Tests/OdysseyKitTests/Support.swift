import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OdysseyKit

/// Scripted HTTP client for API tests.
final class MockHTTP: HTTPClient, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (status: Int, headers: [String: String], body: Data)
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    let handler: Handler

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let (status, headers, body) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, response)
    }
}

extension URLRequest {
    var bodyString: String { httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}

/// Builds activities for tests with sensible defaults.
func makeActivity(
    id: Int64, day: LocalDay, hour: Int = 7, minute: Int = 0, sport: Sport = .run, km: Double = 10, minutes: Double = 55,
    climb: Double = 50, name: String = "Morning Run", kudos: Int = 3, athletes: Int = 1, start: Coordinate? = Coordinate(51.5, -0.1),
    hr: Double? = nil, efforts: [BestEffort]? = nil, notes: String? = nil, workoutType: Int? = nil, manual: Bool = false, gear: String? = nil
) -> Activity {
    let local = Floating.date(day, hour: hour, minute: minute)
    return Activity(
        id: id, name: name, sport: sport, start: local, startLocal: local, distance: km * 1000, movingTime: minutes * 60,
        elevationGain: climb, averageHeartrate: hr, kudos: kudos, athleteCount: athletes, startCoordinate: start,
        gearID: gear, isManual: manual, workoutType: workoutType,
        details: efforts.map { ActivityDetails(description: notes, bestEfforts: $0, fetchedAt: Date(timeIntervalSince1970: 0)) }
            ?? notes.map { ActivityDetails(description: $0, fetchedAt: Date(timeIntervalSince1970: 0)) }
    )
}

let enUS = Locale(identifier: "en_US")
