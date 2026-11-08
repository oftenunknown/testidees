import Foundation

public enum UnitSystem: String, Codable, CaseIterable, Sendable, Identifiable {
    case metric, imperial
    public var id: String { rawValue }
    public var title: String { self == .metric ? "Kilometres" : "Miles" }
}

/// Formats distances, climbs, paces and durations in the athlete's units.
public struct Units: Hashable, Sendable {
    public var system: UnitSystem
    public var locale: Locale

    public init(_ system: UnitSystem = .metric, locale: Locale = .autoupdatingCurrent) {
        self.system = system
        self.locale = locale
    }

    public static let metersPerMile = 1609.344
    public static let feetPerMeter = 3.28084

    public var isMetric: Bool { system == .metric }
    public var distanceUnit: String { isMetric ? "km" : "mi" }
    public var elevationUnit: String { isMetric ? "m" : "ft" }
    public var paceUnit: String { isMetric ? "/km" : "/mi" }
    public var speedUnit: String { isMetric ? "km/h" : "mph" }

    public func distanceValue(_ meters: Double) -> Double {
        isMetric ? meters / 1000 : meters / Self.metersPerMile
    }

    public func elevationValue(_ meters: Double) -> Double {
        isMetric ? meters : meters * Self.feetPerMeter
    }

    public func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    public func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Sensible decimals: 0.8, 12.4, 1,234.
    public func distanceNumber(_ meters: Double, decimals: Int? = nil) -> String {
        let v = distanceValue(meters)
        let d = decimals ?? (v < 100 ? 1 : 0)
        return number(v, decimals: d)
    }

    /// "12.4 km", "1,234 km".
    public func distance(_ meters: Double, decimals: Int? = nil) -> String {
        "\(distanceNumber(meters, decimals: decimals)) \(distanceUnit)"
    }

    /// "1,240 m" / "4,068 ft".
    public func elevation(_ meters: Double) -> String {
        "\(number(elevationValue(meters))) \(elevationUnit)"
    }

    /// Pool-friendly: "2,000 m" / "2,187 yd".
    public func swimDistance(_ meters: Double) -> String {
        isMetric ? "\(number(meters)) m" : "\(number(meters * 1.09361)) yd"
    }

    /// "4:32" (no unit).
    public func paceNumber(secondsPerMeter: Double) -> String {
        let perUnit = secondsPerMeter * (isMetric ? 1000 : Self.metersPerMile)
        return Self.clock(perUnit)
    }

    /// "4:32 /km".
    public func pace(secondsPerMeter: Double) -> String {
        "\(paceNumber(secondsPerMeter: secondsPerMeter)) \(paceUnit)"
    }

    /// "1:52 /100m".
    public func swimPace(secondsPerMeter: Double) -> String {
        isMetric ? "\(Self.clock(secondsPerMeter * 100)) /100m" : "\(Self.clock(secondsPerMeter * 91.44)) /100yd"
    }

    /// "28.4 km/h".
    public func speed(_ metersPerSecond: Double) -> String {
        let v = isMetric ? metersPerSecond * 3.6 : metersPerSecond * 3600 / Self.metersPerMile
        return "\(number(v, decimals: 1)) \(speedUnit)"
    }

    /// The natural speed/pace text for a sport.
    public func effort(for sport: Sport, distance: Double, movingTime: Double) -> String? {
        guard distance > 0, movingTime > 0 else { return nil }
        switch sport.family {
        case .run, .walk: return pace(secondsPerMeter: movingTime / distance)
        case .swim: return swimPace(secondsPerMeter: movingTime / distance)
        case .ride, .water, .glide: return speed(distance / movingTime)
        case .gym, .other: return nil
        }
    }

    /// "1:02:33" or "42:15".
    public static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// "212h 14m", "3h 05m", "47m".
    public static func hoursMinutes(_ seconds: Double) -> String {
        let total = Int((seconds / 60).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return String(format: "%dh %02dm", h, m)
    }

    /// "212" hours, rounded, with grouping.
    public func hours(_ seconds: Double) -> String {
        let h = seconds / 3600
        return number(h, decimals: h < 10 ? 1 : 0)
    }
}
