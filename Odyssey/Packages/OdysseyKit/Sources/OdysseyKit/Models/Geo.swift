import Foundation

/// A latitude/longitude pair in degrees.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(_ latitude: Double, _ longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && !(latitude == 0 && longitude == 0)
    }
}

public enum Geo {
    /// Mean Earth radius in km.
    public static let earthRadiusKm = 6371.0088

    /// Great-circle distance in km.
    public static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180
        let dLat = la2 - la1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Length of a path through the given points, in km.
    public static func pathLengthKm(_ points: [Coordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distanceKm($1.0, $1.1) }
    }

    /// Point a fraction `t` (0…1) of the way along the great circle from `a` to `b`.
    public static func interpolate(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        let la1 = a.latitude * .pi / 180, lo1 = a.longitude * .pi / 180
        let la2 = b.latitude * .pi / 180, lo2 = b.longitude * .pi / 180
        let d = distanceKm(a, b) / earthRadiusKm
        guard d > 1e-9 else { return a }
        let A = sin((1 - t) * d) / sin(d)
        let B = sin(t * d) / sin(d)
        let x = A * cos(la1) * cos(lo1) + B * cos(la2) * cos(lo2)
        let y = A * cos(la1) * sin(lo1) + B * cos(la2) * sin(lo2)
        let z = A * sin(la1) + B * sin(la2)
        return Coordinate(atan2(z, sqrt(x * x + y * y)) * 180 / .pi, atan2(y, x) * 180 / .pi)
    }

    /// Dense great-circle polyline through `waypoints`, roughly one point per `stepKm`.
    public static func densify(_ waypoints: [Coordinate], stepKm: Double = 60) -> [Coordinate] {
        guard waypoints.count > 1 else { return waypoints }
        var out: [Coordinate] = [waypoints[0]]
        for (a, b) in zip(waypoints, waypoints.dropFirst()) {
            let n = max(1, Int((distanceKm(a, b) / stepKm).rounded(.up)))
            for i in 1...n {
                out.append(interpolate(a, b, Double(i) / Double(n)))
            }
        }
        return out
    }

    /// Point at fraction `t` of the total length along a polyline.
    public static func point(along path: [Coordinate], fraction t: Double) -> Coordinate? {
        guard let first = path.first else { return nil }
        guard path.count > 1 else { return first }
        let total = pathLengthKm(path)
        guard total > 0 else { return first }
        var remaining = min(max(t, 0), 1) * total
        for (a, b) in zip(path, path.dropFirst()) {
            let leg = distanceKm(a, b)
            if remaining <= leg {
                return interpolate(a, b, leg > 0 ? remaining / leg : 0)
            }
            remaining -= leg
        }
        return path.last
    }

    /// Prefix of a polyline covering fraction `t` of its length (for drawing progress).
    public static func prefix(of path: [Coordinate], fraction t: Double) -> [Coordinate] {
        guard path.count > 1 else { return path }
        let total = pathLengthKm(path)
        var remaining = min(max(t, 0), 1) * total
        var out: [Coordinate] = [path[0]]
        for (a, b) in zip(path, path.dropFirst()) {
            let leg = distanceKm(a, b)
            if remaining >= leg {
                out.append(b)
                remaining -= leg
            } else {
                if leg > 0 { out.append(interpolate(a, b, remaining / leg)) }
                break
            }
        }
        return out
    }

    /// Unwraps longitudes so a path crossing the antimeridian stays continuous
    /// (e.g. 179 → -179 becomes 179 → 181).
    public static func unwrapped(_ path: [Coordinate]) -> [Coordinate] {
        guard var previous = path.first else { return path }
        var out = [previous]
        for p in path.dropFirst() {
            var lon = p.longitude
            while lon - previous.longitude > 180 { lon -= 360 }
            while lon - previous.longitude < -180 { lon += 360 }
            let q = Coordinate(p.latitude, lon)
            out.append(q)
            previous = q
        }
        return out
    }
}

/// An equirectangular viewport onto the map, for drawing journeys and route art.
public struct GeoViewport: Hashable, Sendable {
    public var minLon: Double
    public var maxLon: Double
    public var minLat: Double
    public var maxLat: Double

    public init(minLon: Double, maxLon: Double, minLat: Double, maxLat: Double) {
        self.minLon = minLon
        self.maxLon = maxLon
        self.minLat = minLat
        self.maxLat = maxLat
    }

    public static let world = GeoViewport(minLon: -180, maxLon: 180, minLat: -58, maxLat: 80)

    public var lonSpan: Double { maxLon - minLon }
    public var latSpan: Double { maxLat - minLat }

    /// Width / height of the viewport when drawn equirectangularly with a
    /// cos(latitude) correction at the centre, so shapes look right.
    public var aspectRatio: Double {
        let midLat = (minLat + maxLat) / 2 * .pi / 180
        return lonSpan * max(cos(midLat), 0.35) / max(latSpan, 0.0001)
    }

    /// Fits `points` with padding, then widens to `aspect` (width / height).
    public static func fitting(_ points: [Coordinate], aspect: Double, padding: Double = 0.18, minSpanDegrees: Double = 12) -> GeoViewport {
        let path = Geo.unwrapped(points)
        guard let first = path.first else { return .world }
        var minLon = first.longitude, maxLon = first.longitude, minLat = first.latitude, maxLat = first.latitude
        for p in path {
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
        }
        var lonSpan = max(maxLon - minLon, minSpanDegrees)
        var latSpan = max(maxLat - minLat, minSpanDegrees * 0.6)
        let cLon = (minLon + maxLon) / 2, cLat = (minLat + maxLat) / 2
        lonSpan *= 1 + padding * 2
        latSpan *= 1 + padding * 2
        let k = max(cos(cLat * .pi / 180), 0.35)
        // Match the requested aspect.
        if lonSpan * k / latSpan < aspect {
            lonSpan = aspect * latSpan / k
        } else {
            latSpan = lonSpan * k / aspect
        }
        lonSpan = min(lonSpan, 360)
        latSpan = min(latSpan, 150)
        var v = GeoViewport(minLon: cLon - lonSpan / 2, maxLon: cLon + lonSpan / 2, minLat: cLat - latSpan / 2, maxLat: cLat + latSpan / 2)
        if v.maxLat > 85 { v.minLat -= v.maxLat - 85; v.maxLat = 85 }
        if v.minLat < -85 { v.maxLat += -85 - v.minLat; v.minLat = -85 }
        return v
    }

    /// Projects to unit coordinates: x 0…1 left→right, y 0…1 top→bottom.
    public func project(_ c: Coordinate) -> (x: Double, y: Double) {
        var lon = c.longitude
        let mid = (minLon + maxLon) / 2
        while lon - mid > 180 { lon -= 360 }
        while lon - mid < -180 { lon += 360 }
        return ((lon - minLon) / lonSpan, (maxLat - c.latitude) / latSpan)
    }
}
