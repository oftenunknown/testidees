import Foundation

enum Stats {
    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let m = mean(values) else { return nil }
        return sqrt(values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1))
    }

    /// Weighted least-squares line through (x, y) points. Returns (slope, intercept).
    static func linearFit(_ points: [(x: Double, y: Double, w: Double)]) -> (slope: Double, intercept: Double)? {
        let total = points.reduce(0) { $0 + $1.w }
        guard points.count >= 2, total > 0 else { return nil }
        let mx = points.reduce(0) { $0 + $1.x * $1.w } / total
        let my = points.reduce(0) { $0 + $1.y * $1.w } / total
        var sxx = 0.0, sxy = 0.0
        for p in points {
            sxx += p.w * (p.x - mx) * (p.x - mx)
            sxy += p.w * (p.x - mx) * (p.y - my)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        return (slope, my - slope * mx)
    }
}

/// Small deterministic PRNG (SplitMix64) for demo data and tests.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    public mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    public mutating func range(_ r: ClosedRange<Double>) -> Double {
        r.lowerBound + unit() * (r.upperBound - r.lowerBound)
    }

    public mutating func chance(_ p: Double) -> Bool { unit() < p }

    /// Roughly normal (sum of uniforms).
    public mutating func normal(mean: Double, sd: Double) -> Double {
        let s = (0..<6).reduce(0.0) { acc, _ in acc + unit() } - 3
        return mean + s * sd / 0.7071
    }

    public mutating func pick<T>(_ items: [T]) -> T {
        items[Int(unit() * Double(items.count)) % items.count]
    }
}
