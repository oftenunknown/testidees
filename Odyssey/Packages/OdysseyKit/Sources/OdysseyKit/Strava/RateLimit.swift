import Foundation

/// Strava's per-app request budget, read from response headers.
///
/// Defaults: 200 requests / 15 min and 2,000 / day overall; 100 / 15 min and
/// 1,000 / day for reads. The 15-minute windows reset on the quarter hour and
/// the daily window at midnight UTC.
public struct RateLimitStatus: Hashable, Codable, Sendable {
    public var shortLimit: Int
    public var shortUsage: Int
    public var dailyLimit: Int
    public var dailyUsage: Int
    public var readShortLimit: Int?
    public var readShortUsage: Int?
    public var readDailyLimit: Int?
    public var readDailyUsage: Int?
    public var observedAt: Date

    public init(shortLimit: Int, shortUsage: Int, dailyLimit: Int, dailyUsage: Int,
                readShortLimit: Int? = nil, readShortUsage: Int? = nil, readDailyLimit: Int? = nil, readDailyUsage: Int? = nil,
                observedAt: Date) {
        self.shortLimit = shortLimit
        self.shortUsage = shortUsage
        self.dailyLimit = dailyLimit
        self.dailyUsage = dailyUsage
        self.readShortLimit = readShortLimit
        self.readShortUsage = readShortUsage
        self.readDailyLimit = readDailyLimit
        self.readDailyUsage = readDailyUsage
        self.observedAt = observedAt
    }

    /// Reads `X-RateLimit-*` and `X-ReadRateLimit-*` ("15min,daily" pairs).
    public init?(header: (String) -> String?, at date: Date) {
        func pair(_ name: String) -> (Int, Int)? {
            guard let raw = header(name) else { return nil }
            let parts = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
        guard let limit = pair("X-RateLimit-Limit"), let usage = pair("X-RateLimit-Usage") else { return nil }
        let readLimit = pair("X-ReadRateLimit-Limit"), readUsage = pair("X-ReadRateLimit-Usage")
        self.init(
            shortLimit: limit.0, shortUsage: usage.0, dailyLimit: limit.1, dailyUsage: usage.1,
            readShortLimit: readLimit?.0, readShortUsage: readUsage?.0, readDailyLimit: readLimit?.1, readDailyUsage: readUsage?.1,
            observedAt: date
        )
    }

    /// Requests left in the current 15-minute window for reads.
    public func shortRemaining(at date: Date) -> Int {
        guard date < Self.nextShortWindow(after: observedAt) else { return readShortLimit ?? shortLimit }
        let overall = shortLimit - shortUsage
        let read = (readShortLimit ?? Int.max) - (readShortUsage ?? 0)
        return max(0, min(overall, read))
    }

    public func dailyRemaining(at date: Date) -> Int {
        guard date < Self.nextDailyReset(after: observedAt) else { return readDailyLimit ?? dailyLimit }
        let overall = dailyLimit - dailyUsage
        let read = (readDailyLimit ?? Int.max) - (readDailyUsage ?? 0)
        return max(0, min(overall, read))
    }

    /// When it's safe to make `count` more requests.
    public func resumeDate(needing count: Int = 1, at date: Date) -> Date {
        if dailyRemaining(at: date) < count { return Self.nextDailyReset(after: observedAt) }
        if shortRemaining(at: date) < count { return Self.nextShortWindow(after: observedAt) }
        return date
    }

    public static func nextShortWindow(after date: Date) -> Date {
        let t = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: ((t / 900).rounded(.down) + 1) * 900)
    }

    public static func nextDailyReset(after date: Date) -> Date {
        let t = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: ((t / 86_400).rounded(.down) + 1) * 86_400)
    }
}
