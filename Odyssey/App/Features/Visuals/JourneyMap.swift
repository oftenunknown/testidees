import SwiftUI
import OdysseyKit

/// Precomputed geometry for drawing one journey on the dot-matrix map.
nonisolated struct JourneyGeometry: Sendable {
    var viewport: GeoViewport
    var dots: [WorldMap.Dot]
    var dotSpacing: Double
    /// Projected path in unit coordinates.
    var path: [CGPoint]
    /// Cumulative fraction of length at each path point.
    var cumulative: [Double]

    init(journey: Journey, aspect: Double, targetColumns: Int = 70) {
        let route: [Coordinate]
        if journey.kind == .planet {
            route = journey.waypoints
        } else {
            route = Geo.unwrapped(Geo.densify(journey.waypoints, stepKm: max(20, journey.lengthKm / 120)))
        }
        let viewport = journey.kind == .planet
            ? GeoViewport.fitting([Coordinate(-50, -170), Coordinate(70, 170)], aspect: aspect, padding: 0.02)
            : GeoViewport.fitting(route, aspect: aspect, padding: 0.22, minSpanDegrees: 14)
        self.viewport = viewport
        let grid = WorldMap.dots(in: viewport, targetColumns: targetColumns)
        dots = grid.dots
        dotSpacing = grid.spacing
        path = route.map { let p = viewport.project($0); return CGPoint(x: p.x, y: p.y) }
        var acc: [Double] = [0]
        var total = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            total += hypot(b.x - a.x, b.y - a.y)
            acc.append(total)
        }
        cumulative = total > 0 ? acc.map { $0 / total } : acc
    }

    /// Path prefix up to `t` and the point at `t`.
    func prefix(_ t: Double) -> (points: [CGPoint], head: CGPoint?) {
        guard path.count > 1 else { return (path, path.first) }
        var out: [CGPoint] = [path[0]]
        for i in 1..<path.count {
            if cumulative[i] <= t {
                out.append(path[i])
            } else {
                let span = cumulative[i] - cumulative[i - 1]
                let f = span > 0 ? (t - cumulative[i - 1]) / span : 0
                let a = path[i - 1], b = path[i]
                let head = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                out.append(head)
                return (out, head)
            }
        }
        return (out, path.last)
    }
}

/// Geometry is the same for every frame of an animation; keep it.
enum JourneyGeometryCache {
    private static var store: [String: JourneyGeometry] = [:]

    static func geometry(for journey: Journey, aspect: Double, columns: Int) -> JourneyGeometry {
        let key = "\(journey.id)|\(Int((aspect * 50).rounded()))|\(columns)"
        if let cached = store[key] { return cached }
        let made = JourneyGeometry(journey: journey, aspect: aspect, targetColumns: columns)
        if store.count > 48 { store.removeAll() }
        store[key] = made
        return made
    }
}

/// A dot-matrix world map with your journey drawing itself across it.
/// Pure SwiftUI drawing: no tiles, so it renders identically in exports.
struct JourneyMap: View {
    var journey: Journey
    /// 0…1 animation clock.
    var progress: Double
    /// How much of the journey you've covered (can exceed 1).
    var completed: Double
    var accent: Color = Palette.ember
    var dotColor: Color = .white
    var showLabels = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let aspect = Double(max(size.width, 1) / max(size.height, 1))
            let geometry = JourneyGeometryCache.geometry(for: journey, aspect: aspect, columns: size.width > 500 ? 90 : 64)
            let reveal = Easing.segment(progress, 0, 0.35)
            let draw = Easing.outCubic(Easing.segment(progress, 0.15, 0.95)) * min(1, completed)
            let laps = completed >= 1.95 ? Easing.segment(progress, 0.85, 1) : 0
            let accent = accent, dotColor = dotColor

            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    let w = canvasSize.width, h = canvasSize.height
                    let r = max(1.1, geometry.dotSpacing * w * 0.32)
                    // Land dots fade in from the left.
                    for dot in geometry.dots {
                        let appear = min(1, max(0, (reveal * 1.6 - dot.x * 0.6)))
                        guard appear > 0 else { continue }
                        let rect = CGRect(x: dot.x * w - r, y: dot.y * h - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor.opacity(0.10 + 0.22 * appear)))
                    }
                    let (points, head) = geometry.prefix(draw)
                    guard points.count > 1 else { return }
                    var line = Path()
                    line.move(to: CGPoint(x: points[0].x * w, y: points[0].y * h))
                    for p in points.dropFirst() { line.addLine(to: CGPoint(x: p.x * w, y: p.y * h)) }
                    // Glow, then the bright line.
                    var glow = context
                    glow.addFilter(.blur(radius: 6))
                    glow.stroke(line, with: .color(accent.opacity(0.85)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    // Start ring and moving head.
                    let s = CGPoint(x: points[0].x * w, y: points[0].y * h)
                    context.stroke(Path(ellipseIn: CGRect(x: s.x - 6, y: s.y - 6, width: 12, height: 12)), with: .color(accent), lineWidth: 2.5)
                    if let head {
                        let hp = CGPoint(x: head.x * w, y: head.y * h)
                        var halo = context
                        halo.addFilter(.blur(radius: 8))
                        halo.fill(Path(ellipseIn: CGRect(x: hp.x - 10, y: hp.y - 10, width: 20, height: 20)), with: .color(accent))
                        context.fill(Path(ellipseIn: CGRect(x: hp.x - 5.5, y: hp.y - 5.5, width: 11, height: 11)), with: .color(.white))
                    }
                    // Extra laps: a second, fainter pass.
                    if laps > 0, geometry.path.count > 1 {
                        let (again, _) = geometry.prefix(laps)
                        var second = Path()
                        second.move(to: CGPoint(x: again[0].x * w, y: again[0].y * h + 5))
                        for p in again.dropFirst() { second.addLine(to: CGPoint(x: p.x * w, y: p.y * h + 5)) }
                        context.stroke(second, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))
                    }
                }

                if showLabels, let first = geometry.path.first, let last = geometry.path.last, journey.kind != .planet {
                    label(journey.from, at: first, in: size, leading: first.x <= last.x)
                        .opacity(Easing.segment(progress, 0.15, 0.35))
                    label(journey.to, at: last, in: size, leading: last.x < first.x)
                        .opacity(Easing.segment(progress, 0.8, 1))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(journey.title)
    }

    @ViewBuilder
    private func label(_ text: String?, at point: CGPoint, in size: CGSize, leading: Bool) -> some View {
        if let text {
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: .capsule)
                .fixedSize()
                .position(
                    x: min(max(point.x * size.width + (leading ? -18 : 18), 50), size.width - 50),
                    y: min(max(point.y * size.height + 22, 14), size.height - 14)
                )
        }
    }
}

/// A 400 m track with a runner lapping it.
struct TrackLaps: View {
    var laps: Double
    var progress: Double
    var accent: Color = Palette.ember

    var body: some View {
        let shownLaps = min(laps, 5)
        let t = Easing.outCubic(progress) * shownLaps
        Canvas { context, size in
            let w = size.width, h = size.height
            let inset: CGFloat = 10
            let rect = CGRect(x: inset, y: inset, width: w - inset * 2, height: h - inset * 2)
            let outer = Path(roundedRect: rect, cornerRadius: rect.height / 2)
            let laneWidth = rect.height * 0.16
            let inner = Path(roundedRect: rect.insetBy(dx: laneWidth, dy: laneWidth), cornerRadius: (rect.height - laneWidth * 2) / 2)
            context.fill(outer, with: .color(Color(red: 0.75, green: 0.27, blue: 0.20)))
            context.fill(inner, with: .color(Color(red: 0.16, green: 0.42, blue: 0.24)))
            for lane in 1..<4 {
                let d = laneWidth * CGFloat(lane) / 4
                let lanePath = Path(roundedRect: rect.insetBy(dx: d, dy: d), cornerRadius: (rect.height - d * 2) / 2)
                context.stroke(lanePath, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
            }
            // Runner position along the middle of the first lane.
            let mid = rect.insetBy(dx: laneWidth / 2, dy: laneWidth / 2)
            let frac = t - t.rounded(.down)
            let p = Self.point(on: mid, fraction: frac)
            var halo = context
            halo.addFilter(.blur(radius: 6))
            halo.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(accent))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
        }
        .accessibilityHidden(true)
    }

    /// Point on a stadium (rounded rect with semicircle ends) by perimeter fraction.
    nonisolated static func point(on rect: CGRect, fraction: Double) -> CGPoint {
        let r = rect.height / 2
        let straight = rect.width - 2 * r
        let perimeter = 2 * straight + 2 * .pi * r
        var d = fraction * perimeter
        // Start bottom-left of the home straight, run anticlockwise like a real track.
        if d < straight { return CGPoint(x: rect.minX + r + d, y: rect.maxY) }
        d -= straight
        if d < .pi * r {
            let a = .pi / 2 - d / r
            return CGPoint(x: rect.maxX - r + cos(a) * r, y: rect.midY + sin(a) * r)
        }
        d -= .pi * r
        if d < straight { return CGPoint(x: rect.maxX - r - d, y: rect.minY) }
        d -= straight
        let a = -.pi / 2 - d / r
        return CGPoint(x: rect.minX + r + cos(a) * r, y: rect.midY + sin(a) * r)
    }
}
