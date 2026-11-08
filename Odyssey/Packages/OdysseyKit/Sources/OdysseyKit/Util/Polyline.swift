import Foundation

/// Google's encoded polyline format (precision 5), which Strava uses for maps.
public enum Polyline {
    public static func decode(_ encoded: String) -> [Coordinate] {
        let bytes = Array(encoded.utf8)
        var index = 0, lat = 0, lon = 0
        var out: [Coordinate] = []
        out.reserveCapacity(bytes.count / 4)
        func next() -> Int? {
            var result = 0, shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            out.append(Coordinate(Double(lat) / 1e5, Double(lon) / 1e5))
        }
        return out
    }

    public static func encode(_ coordinates: [Coordinate]) -> String {
        var out = ""
        var lastLat = 0, lastLon = 0
        func append(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : (value << 1)
            while v >= 0x20 {
                out.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (v & 0x1F)) + 63)))
                v >>= 5
            }
            out.unicodeScalars.append(UnicodeScalar(UInt8(v + 63)))
        }
        for c in coordinates {
            let lat = Int((c.latitude * 1e5).rounded())
            let lon = Int((c.longitude * 1e5).rounded())
            append(lat - lastLat)
            append(lon - lastLon)
            lastLat = lat
            lastLon = lon
        }
        return out
    }

    /// Douglas–Peucker simplification in a local metric projection.
    public static func simplify(_ points: [Coordinate], toleranceMeters: Double) -> [Coordinate] {
        guard points.count > 2 else { return points }
        let lat0 = points[0].latitude * .pi / 180
        let k = cos(lat0)
        let xy = points.map { ($0.longitude * k * 111_320, $0.latitude * 110_540) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let (ax, ay) = xy[a], (bx, by) = xy[b]
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            var maxDist = 0.0, maxIndex = a
            for i in (a + 1)..<b {
                let (px, py) = xy[i]
                var d: Double
                if len2 == 0 {
                    d = hypot(px - ax, py - ay)
                } else {
                    let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
                    d = hypot(px - (ax + t * dx), py - (ay + t * dy))
                }
                if d > maxDist { maxDist = d; maxIndex = i }
            }
            if maxDist > toleranceMeters {
                keep[maxIndex] = true
                stack.append((a, maxIndex))
                stack.append((maxIndex, b))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    /// Drops the first and last `meters` of a route so a shared picture
    /// doesn't point at your front door.
    public static func trimmingEnds(_ points: [Coordinate], meters: Double) -> [Coordinate] {
        guard points.count > 2, meters > 0 else { return points }
        let total = Geo.pathLengthKm(points) * 1000
        guard total > meters * 3 else { return [] }
        var start = 0, walked = 0.0
        while start < points.count - 1, walked < meters {
            walked += Geo.distanceKm(points[start], points[start + 1]) * 1000
            start += 1
        }
        var end = points.count - 1
        walked = 0
        while end > start, walked < meters {
            walked += Geo.distanceKm(points[end - 1], points[end]) * 1000
            end -= 1
        }
        return end > start ? Array(points[start...end]) : []
    }
}
