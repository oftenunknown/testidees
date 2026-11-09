import Foundation

/// Parses Strava's ISO-8601 timestamps ("2026-03-01T07:12:34Z").
enum StravaDate {
    /// Real instant, honouring any zone designator.
    static func instant(_ string: String?) -> Date? {
        guard let string, let parts = parse(string) else { return nil }
        return parts.floating.addingTimeInterval(-TimeInterval(parts.offsetSeconds))
    }

    /// Wall-clock time, ignoring the zone designator (Strava's start_date_local
    /// is local time written with a "Z").
    static func floating(_ string: String?) -> Date? {
        guard let string else { return nil }
        return parse(string)?.floating
    }

    private static func parse(_ s: String) -> (floating: Date, offsetSeconds: Int)? {
        let chars = Array(s.utf8)
        func int(_ from: Int, _ len: Int) -> Int? {
            guard from + len <= chars.count else { return nil }
            var v = 0
            for c in chars[from..<(from + len)] {
                guard c >= 48 && c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard let y = int(0, 4), let mo = int(5, 2), let d = int(8, 2) else { return nil }
        var seconds = 0
        var index = 10
        if chars.count > 10, chars[10] == UInt8(ascii: "T") || chars[10] == UInt8(ascii: " ") {
            guard let h = int(11, 2), let mi = int(14, 2) else { return nil }
            let sec = int(17, 2) ?? 0
            seconds = h * 3600 + mi * 60 + sec
            index = chars.count > 16 && chars[16] == UInt8(ascii: ":") ? 19 : 16
            // Fractional seconds.
            if index < chars.count, chars[index] == UInt8(ascii: ".") {
                index += 1
                while index < chars.count, chars[index] >= 48 && chars[index] <= 57 { index += 1 }
            }
        }
        var offset = 0
        if index < chars.count {
            let sign = chars[index]
            if sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-"), let oh = int(index + 1, 2) {
                let om = int(index + 4, 2) ?? int(index + 3, 2) ?? 0
                offset = (oh * 3600 + om * 60) * (sign == UInt8(ascii: "-") ? -1 : 1)
            }
        }
        let day = LocalDay(year: y, month: mo, day: d)
        return (day.date.addingTimeInterval(TimeInterval(seconds)), offset)
    }
}

/// Lenient decoder for SummaryActivity / DetailedActivity.
struct ActivityDTO: Decodable {
    var id: Int64
    var name: String?
    var sportType: String?
    var type: String?
    var startDate: String?
    var startDateLocal: String?
    var timezone: String?
    var distance: Double?
    var movingTime: Double?
    var elapsedTime: Double?
    var totalElevationGain: Double?
    var averageSpeed: Double?
    var maxSpeed: Double?
    var averageHeartrate: Double?
    var maxHeartrate: Double?
    var averageWatts: Double?
    var kilojoules: Double?
    var sufferScore: Double?
    var kudosCount: Int?
    var commentCount: Int?
    var achievementCount: Int?
    var prCount: Int?
    var athleteCount: Int?
    var photoCount: Int?
    var totalPhotoCount: Int?
    var startLatlng: [Double]?
    var endLatlng: [Double]?
    var map: MapDTO?
    var deviceName: String?
    var gearID: String?
    var commute: Bool?
    var trainer: Bool?
    var manual: Bool?
    var isPrivate: Bool?
    var workoutType: Int?
    var description: String?
    var calories: Double?
    var bestEfforts: [BestEffortDTO]?

    struct MapDTO: Decodable {
        var summaryPolyline: String?
        enum CodingKeys: String, CodingKey { case summaryPolyline = "summary_polyline" }
    }

    struct BestEffortDTO: Decodable {
        var name: String?
        var distance: Double?
        var elapsedTime: Double?
        var movingTime: Double?
        var prRank: Int?

        enum CodingKeys: String, CodingKey {
            case name, distance
            case elapsedTime = "elapsed_time"
            case movingTime = "moving_time"
            case prRank = "pr_rank"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, timezone, distance, map, commute, trainer, manual, kilojoules, description, calories
        case sportType = "sport_type"
        case startDate = "start_date"
        case startDateLocal = "start_date_local"
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case averageWatts = "average_watts"
        case sufferScore = "suffer_score"
        case kudosCount = "kudos_count"
        case commentCount = "comment_count"
        case achievementCount = "achievement_count"
        case prCount = "pr_count"
        case athleteCount = "athlete_count"
        case photoCount = "photo_count"
        case totalPhotoCount = "total_photo_count"
        case startLatlng = "start_latlng"
        case endLatlng = "end_latlng"
        case deviceName = "device_name"
        case gearID = "gear_id"
        case isPrivate = "private"
        case workoutType = "workout_type"
        case bestEfforts = "best_efforts"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        func lenient<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        name = lenient(String.self, .name)
        sportType = lenient(String.self, .sportType)
        type = lenient(String.self, .type)
        startDate = lenient(String.self, .startDate)
        startDateLocal = lenient(String.self, .startDateLocal)
        timezone = lenient(String.self, .timezone)
        distance = lenient(Double.self, .distance)
        movingTime = lenient(Double.self, .movingTime)
        elapsedTime = lenient(Double.self, .elapsedTime)
        totalElevationGain = lenient(Double.self, .totalElevationGain)
        averageSpeed = lenient(Double.self, .averageSpeed)
        maxSpeed = lenient(Double.self, .maxSpeed)
        averageHeartrate = lenient(Double.self, .averageHeartrate)
        maxHeartrate = lenient(Double.self, .maxHeartrate)
        averageWatts = lenient(Double.self, .averageWatts)
        kilojoules = lenient(Double.self, .kilojoules)
        sufferScore = lenient(Double.self, .sufferScore)
        kudosCount = lenient(Int.self, .kudosCount)
        commentCount = lenient(Int.self, .commentCount)
        achievementCount = lenient(Int.self, .achievementCount)
        prCount = lenient(Int.self, .prCount)
        athleteCount = lenient(Int.self, .athleteCount)
        photoCount = lenient(Int.self, .photoCount)
        totalPhotoCount = lenient(Int.self, .totalPhotoCount)
        startLatlng = lenient([Double].self, .startLatlng)
        endLatlng = lenient([Double].self, .endLatlng)
        map = lenient(MapDTO.self, .map)
        deviceName = lenient(String.self, .deviceName)
        gearID = lenient(String.self, .gearID)
        commute = lenient(Bool.self, .commute)
        trainer = lenient(Bool.self, .trainer)
        manual = lenient(Bool.self, .manual)
        isPrivate = lenient(Bool.self, .isPrivate)
        workoutType = lenient(Int.self, .workoutType)
        description = lenient(String.self, .description)
        calories = lenient(Double.self, .calories)
        bestEfforts = lenient([BestEffortDTO].self, .bestEfforts)
    }

    var activity: Activity? {
        guard let start = StravaDate.instant(startDate) else { return nil }
        let local = StravaDate.floating(startDateLocal) ?? start
        func coordinate(_ pair: [Double]?) -> Coordinate? {
            guard let pair, pair.count == 2 else { return nil }
            let c = Coordinate(pair[0], pair[1])
            return c.isValid ? c : nil
        }
        let polyline = map?.summaryPolyline.flatMap { $0.isEmpty ? nil : $0 }
        return Activity(
            id: id,
            name: name ?? "Activity",
            sport: Sport(sportType ?? type ?? "Workout"),
            start: start,
            startLocal: local,
            timezone: timezone,
            distance: max(0, distance ?? 0),
            movingTime: max(0, movingTime ?? elapsedTime ?? 0),
            elapsedTime: max(0, elapsedTime ?? movingTime ?? 0),
            elevationGain: max(0, totalElevationGain ?? 0),
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            averageHeartrate: averageHeartrate,
            maxHeartrate: maxHeartrate,
            averageWatts: averageWatts,
            kilojoules: kilojoules,
            sufferScore: sufferScore,
            kudos: kudosCount ?? 0,
            comments: commentCount ?? 0,
            achievements: achievementCount ?? 0,
            prCount: prCount ?? 0,
            athleteCount: max(1, athleteCount ?? 1),
            photoCount: totalPhotoCount ?? photoCount ?? 0,
            startCoordinate: coordinate(startLatlng),
            endCoordinate: coordinate(endLatlng),
            polyline: polyline,
            deviceName: deviceName.flatMap { $0.isEmpty ? nil : $0 },
            gearID: gearID,
            isCommute: commute ?? false,
            isTrainer: trainer ?? false,
            isManual: manual ?? false,
            isPrivate: isPrivate ?? false,
            workoutType: workoutType
        )
    }

    func details(fetchedAt: Date) -> ActivityDetails {
        let efforts = (bestEfforts ?? []).compactMap { dto -> BestEffort? in
            guard let distance = dto.distance, let elapsed = dto.elapsedTime, elapsed > 0 else { return nil }
            return BestEffort(name: dto.name ?? "", distance: distance, elapsedTime: elapsed, movingTime: dto.movingTime, prRank: dto.prRank)
        }
        let text = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ActivityDetails(
            description: (text?.isEmpty ?? true) ? nil : text,
            calories: calories.flatMap { $0 > 0 ? $0 : nil },
            bestEfforts: efforts,
            fetchedAt: fetchedAt
        )
    }
}

struct AthleteDTO: Decodable {
    var id: Int64
    var firstname: String?
    var lastname: String?
    var city: String?
    var country: String?
    var profile: String?
    var measurementPreference: String?
    var weight: Double?
    var createdAt: String?
    var shoes: [GearDTO]?
    var bikes: [GearDTO]?

    struct GearDTO: Decodable {
        var id: String
        var name: String?
        var distance: Double?
    }

    enum CodingKeys: String, CodingKey {
        case id, firstname, lastname, city, country, profile, weight, shoes, bikes
        case measurementPreference = "measurement_preference"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        firstname = (try? c.decodeIfPresent(String.self, forKey: .firstname)) ?? nil
        lastname = (try? c.decodeIfPresent(String.self, forKey: .lastname)) ?? nil
        city = (try? c.decodeIfPresent(String.self, forKey: .city)) ?? nil
        country = (try? c.decodeIfPresent(String.self, forKey: .country)) ?? nil
        profile = (try? c.decodeIfPresent(String.self, forKey: .profile)) ?? nil
        measurementPreference = (try? c.decodeIfPresent(String.self, forKey: .measurementPreference)) ?? nil
        weight = (try? c.decodeIfPresent(Double.self, forKey: .weight)) ?? nil
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil
        shoes = (try? c.decodeIfPresent([GearDTO].self, forKey: .shoes)) ?? nil
        bikes = (try? c.decodeIfPresent([GearDTO].self, forKey: .bikes)) ?? nil
    }

    var athlete: Athlete {
        let gear = (shoes ?? []).map { Gear(id: $0.id, name: $0.name ?? "Shoes", kind: .shoes, distance: $0.distance ?? 0) }
            + (bikes ?? []).map { Gear(id: $0.id, name: $0.name ?? "Bike", kind: .bike, distance: $0.distance ?? 0) }
        // Strava uses relative placeholder paths ("avatar/athlete/large.png") when there's no photo.
        let imageURL = profile.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }
        return Athlete(
            id: id,
            firstName: firstname ?? "",
            lastName: lastname ?? "",
            city: city.flatMap { $0.isEmpty ? nil : $0 },
            country: country.flatMap { $0.isEmpty ? nil : $0 },
            profileImageURL: imageURL,
            measurementPreference: measurementPreference,
            weight: weight.flatMap { $0 > 0 ? $0 : nil },
            createdAt: StravaDate.instant(createdAt),
            gear: gear
        )
    }
}

struct TokenResponseDTO: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double
    var athlete: AthleteDTO?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }
}

struct FaultDTO: Decodable {
    var message: String?
    /// Set by Odyssey's token server on its own refusals.
    var code: String?
}
