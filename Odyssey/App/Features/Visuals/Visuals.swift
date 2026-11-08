import SwiftUI
import OdysseyKit

/// Mountains (or towers) filling up with your climbing: one per summit.
struct ClimbStack: View {
    var multiple: Double
    var kind: Landmark.Kind
    var progress: Double
    var accent: Color = Palette.lime

    var body: some View {
        let shown = max(1, min(6, Int(multiple.rounded(.up))))
        let filled = Easing.outCubic(progress) * min(multiple, Double(shown))
        let accent = accent
        let isTower = kind == .building
        Canvas { context, size in
            let n = CGFloat(shown)
            let gap: CGFloat = isTower ? 10 : -size.width * 0.06
            let width = (size.width - gap * (n - 1)) / n
            for i in 0..<shown {
                let x0 = CGFloat(i) * (width + gap)
                let heightScale: CGFloat = isTower ? 1 : (i % 2 == 0 ? 1 : 0.86)
                let top = size.height * (1 - heightScale) + 4
                let shape = isTower
                    ? ClimbShapes.tower(in: CGRect(x: x0 + width * 0.18, y: top, width: width * 0.64, height: size.height - top))
                    : ClimbShapes.mountain(in: CGRect(x: x0, y: top, width: width, height: size.height - top))
                context.fill(shape, with: .color(.white.opacity(0.12)))
                context.stroke(shape, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
                let level = min(max(filled - Double(i), 0), 1)
                guard level > 0 else { continue }
                var clipped = context
                let fillTop = top + (size.height - top) * (1 - level)
                clipped.clip(to: Path(CGRect(x: x0 - 4, y: fillTop, width: width + 8, height: size.height - fillTop)))
                clipped.fill(shape, with: .linearGradient(
                    Gradient(colors: [accent, accent.opacity(0.55)]),
                    startPoint: CGPoint(x: x0, y: top), endPoint: CGPoint(x: x0, y: size.height)))
                if level >= 1, !isTower {
                    // Snow cap on summited peaks.
                    let cap = ClimbShapes.snowCap(in: CGRect(x: x0, y: top, width: width, height: size.height - top))
                    context.fill(cap, with: .color(.white.opacity(0.95)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

nonisolated enum ClimbShapes {
    static func mountain(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.32, y: r.minY + r.height * 0.42))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.52))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.04, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.72, y: r.minY + r.height * 0.38))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.8, y: r.minY + r.height * 0.33))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }

    static func snowCap(in r: CGRect) -> Path {
        var p = Path()
        let peak = CGPoint(x: r.midX + r.width * 0.04, y: r.minY)
        p.move(to: peak)
        p.addLine(to: CGPoint(x: peak.x - r.width * 0.11, y: r.minY + r.height * 0.2))
        p.addLine(to: CGPoint(x: peak.x - r.width * 0.04, y: r.minY + r.height * 0.17))
        p.addLine(to: CGPoint(x: peak.x + r.width * 0.01, y: r.minY + r.height * 0.23))
        p.addLine(to: CGPoint(x: peak.x + r.width * 0.06, y: r.minY + r.height * 0.16))
        p.addLine(to: CGPoint(x: peak.x + r.width * 0.12, y: r.minY + r.height * 0.19))
        p.closeSubpath()
        return p
    }

    static func tower(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX - r.width * 0.06, y: r.minY + r.height * 0.18), control: CGPoint(x: r.minX + r.width * 0.32, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.06, y: r.minY + r.height * 0.18))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.maxX - r.width * 0.32, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.3, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.3, y: r.maxY), control: CGPoint(x: r.midX, y: r.maxY - r.height * 0.22))
        p.closeSubpath()
        return p
    }
}

/// GitHub-style calendar: one column per week, one row per weekday.
struct CalendarHeatmap: View {
    var days: [DayTotal]
    var range: DayRange
    var firstWeekday: Int
    var progress: Double
    var color: Color = Palette.mint
    var useTime = false

    var body: some View {
        let start = range.start.startOfWeek(firstWeekday: firstWeekday)
        let weeks = max(1, Int((Double(range.end.index - start.index) / 7).rounded(.up)))
        let values = days.map { useTime ? $0.movingTime : $0.distance }
        let cap = max(values.sorted().dropLast(max(0, values.count / 12)).last ?? 1, 1)
        let lookup = Dictionary(days.map { ($0.day.index, useTime ? $0.movingTime : $0.distance) }, uniquingKeysWith: +)
        let reveal = Easing.segment(progress, 0, 0.85)
        let color = color
        let rangeStart = range.start.index, rangeEnd = range.end.index
        Canvas { context, size in
            let gap: CGFloat = weeks > 30 ? 1.5 : 3
            let cell = min((size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks), (size.height - gap * 6) / 7)
            let total = CGFloat(weeks) * (cell + gap) - gap
            let x0 = (size.width - total) / 2
            let y0 = (size.height - (cell * 7 + gap * 6)) / 2
            for w in 0..<weeks {
                let columnReveal = Double(w) / Double(weeks)
                guard columnReveal <= reveal else { break }
                for d in 0..<7 {
                    let index = start.index + w * 7 + d
                    guard index >= rangeStart, index < rangeEnd else { continue }
                    let rect = CGRect(x: x0 + CGFloat(w) * (cell + gap), y: y0 + CGFloat(d) * (cell + gap), width: cell, height: cell)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.25)
                    if let v = lookup[index], v > 0 {
                        let intensity = 0.35 + 0.65 * min(1, v / cap)
                        context.fill(path, with: .color(color.opacity(intensity)))
                    } else if lookup[index] != nil {
                        context.fill(path, with: .color(color.opacity(0.35)))
                    } else {
                        context.fill(path, with: .color(.white.opacity(0.08)))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 24-hour radial histogram of start times.
struct HourClock: View {
    var hourCounts: [Int]
    var peak: Int?
    var progress: Double
    var accent: Color = Palette.gold

    var body: some View {
        let maxCount = Double(max(hourCounts.max() ?? 1, 1))
        let counts = hourCounts
        let grow = Easing.outCubic(progress)
        let accent = accent
        let peak = peak
        ZStack {
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                let inner = radius * 0.38
                context.stroke(Path(ellipseIn: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)), with: .color(.white.opacity(0.25)), lineWidth: 1)
                for h in 0..<24 {
                    let angle = (Double(h) / 24) * 2 * .pi - .pi / 2
                    let length = (radius - inner - 6) * CGFloat(Double(counts[h]) / maxCount * grow)
                    let a = CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner)
                    let b = CGPoint(x: c.x + cos(angle) * (inner + max(2, length)), y: c.y + sin(angle) * (inner + max(2, length)))
                    var bar = Path()
                    bar.move(to: a)
                    bar.addLine(to: b)
                    let isPeak = h == peak
                    context.stroke(bar, with: .color(isPeak ? accent : .white.opacity(counts[h] > 0 ? 0.75 : 0.18)),
                                   style: StrokeStyle(lineWidth: max(4, radius * 0.07), lineCap: .round))
                }
            }
            GeometryReader { proxy in
                let r = min(proxy.size.width, proxy.size.height) / 2
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    let angle = (Double(h) / 24) * 2 * .pi - .pi / 2
                    Text(h == 0 ? "0h" : "\(h)h")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .position(x: proxy.size.width / 2 + cos(angle) * r * 0.24, y: proxy.size.height / 2 + sin(angle) * r * 0.24)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Seven bars, one per weekday, in the athlete's week order.
struct WeekdayBars: View {
    var counts: [Int]
    var firstWeekday: Int
    var progress: Double
    var accent: Color = Palette.mint
    var format = DayFormat()

    var body: some View {
        let order = (0..<7).map { ($0 + firstWeekday) % 7 }
        let maxCount = Double(max(counts.max() ?? 1, 1))
        let best = counts.max()
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(order, id: \.self) { d in
                VStack(spacing: 6) {
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(counts[d] == best ? accent : .white.opacity(0.55))
                                .frame(height: max(6, proxy.size.height * Double(counts[d]) / maxCount * Easing.outCubic(progress)))
                        }
                    }
                    Text(format.weekdayNameShort(d).prefix(2))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Donut of moving time by sport.
struct SportsRing: View {
    var slices: [SportSlice]
    var progress: Double

    var body: some View {
        let shares = slices.map { ($0.family, $0.share) }
        let sweep = Easing.outCubic(progress)
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 12
            var start = -Double.pi / 2
            for (family, share) in shares {
                let end = start + share * 2 * .pi * sweep
                var arc = Path()
                arc.addArc(center: c, radius: radius, startAngle: .radians(start + 0.03), endAngle: .radians(max(start + 0.03, end - 0.03)), clockwise: false)
                context.stroke(arc, with: .color(Palette.family(family)), style: StrokeStyle(lineWidth: radius * 0.32, lineCap: .butt))
                start = end
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Your routes as a wall of line drawings: no map, no scale, ends trimmed.
struct RouteArt: View {
    var routes: [RouteSketch]
    var progress: Double
    var columns: Int = 6
    var lineWidth: CGFloat = 1.6

    var body: some View {
        let items = routes
        let cols = max(columns, 1)
        let rows = max(1, Int((Double(items.count) / Double(cols)).rounded(.up)))
        let t = progress
        let lineWidth = lineWidth
        Canvas { context, size in
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let x0 = (size.width - cell * CGFloat(cols)) / 2
            let y0 = (size.height - cell * CGFloat(rows)) / 2
            for (i, route) in items.enumerated() {
                let appear = min(1, max(0, t * 1.6 - Double(i) / Double(max(items.count, 1)) * 0.6))
                guard appear > 0, route.points.count > 1 else { continue }
                let col = i % cols, row = i / cols
                let pad = cell * 0.12
                let box = CGRect(x: x0 + CGFloat(col) * cell + pad, y: y0 + CGFloat(row) * cell + pad, width: cell - pad * 2, height: cell - pad * 2)
                let count = max(2, Int(Double(route.points.count) * appear))
                var path = Path()
                for (j, p) in route.points.prefix(count).enumerated() {
                    let point = CGPoint(x: box.minX + CGFloat(p.x) * box.width, y: box.minY + CGFloat(p.y) * box.height)
                    if j == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(Palette.family(route.family).opacity(0.95)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// You in the middle, your crew around you; thicker lines for more time together.
struct CrewConstellation: View {
    var companions: [Companion]
    var initialsOfYou: String
    var progress: Double
    var accent: Color = Palette.mint

    var body: some View {
        let people = Array(companions.prefix(6))
        let maxCount = Double(max(people.first?.count ?? 1, 1))
        GeometryReader { proxy in
            let size = proxy.size
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36
            let nodes: [(Companion, CGPoint)] = people.enumerated().map { i, person in
                let angle = -Double.pi / 2 + Double(i) / Double(max(people.count, 1)) * 2 * .pi
                return (person, CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius))
            }
            let grow = Easing.outCubic(progress)
            ZStack {
                Canvas { context, _ in
                    for (person, point) in nodes {
                        var line = Path()
                        line.move(to: c)
                        line.addLine(to: CGPoint(x: c.x + (point.x - c.x) * grow, y: c.y + (point.y - c.y) * grow))
                        context.stroke(line, with: .color(.white.opacity(0.5)),
                                       style: StrokeStyle(lineWidth: 1.5 + 6 * Double(person.count) / maxCount, lineCap: .round))
                    }
                }
                bubble(initialsOfYou, size: 64, fill: accent)
                    .position(c)
                ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                    let appear = Easing.segment(progress, 0.25 + Double(i) * 0.08, 0.55 + Double(i) * 0.08)
                    VStack(spacing: 4) {
                        bubble(Self.initials(node.0.name), size: 46 + 10 * Double(node.0.count) / maxCount, fill: .white.opacity(0.92), ink: .black)
                        Text(node.0.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .opacity(appear)
                    .scaleEffect(0.6 + 0.4 * appear)
                    .position(node.1)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func bubble(_ text: String, size: CGFloat, fill: Color, ink: Color = .white) -> some View {
        Text(text)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(fill, in: .circle)
            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// The persona's symbol in glowing rings.
struct PersonaEmblem: View {
    var archetype: Archetype
    var progress: Double

    var body: some View {
        let color = Palette.persona(archetype)
        let p = Easing.outBack(Easing.segment(progress, 0, 0.7))
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .stroke(color.opacity(0.5 - Double(ring) * 0.14), lineWidth: 2)
                    .scaleEffect(0.55 + Double(ring) * 0.22 * Easing.outCubic(progress))
            }
            Circle()
                .fill(RadialGradient(colors: [color, color.opacity(0.25)], center: .center, startRadius: 4, endRadius: 120))
                .scaleEffect(0.5 * p)
                .blur(radius: 1)
            Image(systemName: archetype.symbol)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(p)
                .shadow(color: color, radius: 16)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A wall calendar: one small month per block, laid out to fill whatever
/// space it gets (3 × 4 in a tall pane, 6 × 2 in a wide one).
struct MonthGridHeatmap: View {
    var days: [DayTotal]
    var range: DayRange
    var firstWeekday: Int
    var progress: Double
    var color: Color = Palette.mint
    var useTime = false
    var format = DayFormat()

    var body: some View {
        let months = Self.months(in: range)
        let values = days.map { useTime ? $0.movingTime : $0.distance }
        let cap = max(values.sorted().dropLast(max(0, values.count / 12)).last ?? 1, 1)
        let lookup = Dictionary(days.map { ($0.day.index, useTime ? $0.movingTime : $0.distance) }, uniquingKeysWith: +)
        GeometryReader { proxy in
            let layout = Self.layout(count: months.count, in: proxy.size)
            let cell = layout.cell
            VStack(alignment: .leading, spacing: cell) {
                ForEach(0..<layout.rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: cell * 1.2) {
                        ForEach(0..<layout.columns, id: \.self) { column in
                            let index = row * layout.columns + column
                            if index < months.count {
                                let appear = Easing.segment(progress, Double(index) / Double(months.count) * 0.7, Double(index) / Double(months.count) * 0.7 + 0.3)
                                VStack(alignment: .leading, spacing: cell * 0.4) {
                                    Text(format.monthShort(months[index]))
                                        .font(.system(size: max(9, cell * 1.1), weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .frame(height: cell * 1.2)
                                    MonthCells(month: months[index], range: range, firstWeekday: firstWeekday, lookup: lookup, cap: cap, color: color, cell: cell)
                                        .frame(width: cell * 7, height: cell * 6)
                                }
                                .opacity(appear)
                                .scaleEffect(0.9 + 0.1 * appear, anchor: .topLeading)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    static func months(in range: DayRange) -> [LocalDay] {
        guard !range.isEmpty else { return [] }
        var out: [LocalDay] = []
        var m = range.start.startOfMonth
        while m < range.end {
            out.append(m)
            m = m.adding(months: 1)
        }
        return out
    }

    /// Columns, rows and cell size that make the months as big as possible.
    static func layout(count: Int, in size: CGSize) -> (columns: Int, rows: Int, cell: CGFloat) {
        guard count > 0 else { return (1, 1, 8) }
        var best = (columns: 1, rows: count, cell: CGFloat(0))
        for columns in 1...min(6, count) {
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            // A month is 7 cells (+ gaps) wide and a label plus 6 weeks tall.
            let width = size.width / (CGFloat(columns) * 7 + CGFloat(columns - 1) * 1.2)
            let height = size.height / (CGFloat(rows) * 8.6 + CGFloat(rows - 1))
            let cell = min(width, height)
            if cell > best.cell { best = (columns, rows, cell) }
        }
        return (best.columns, best.rows, max(best.cell, 3))
    }
}

/// The day squares of one month.
private struct MonthCells: View {
    var month: LocalDay
    var range: DayRange
    var firstWeekday: Int
    var lookup: [Int: Double]
    var cap: Double
    var color: Color
    var cell: CGFloat

    var body: some View {
        let first = month.startOfMonth
        let next = first.adding(months: 1)
        let offset = ((first.weekday - firstWeekday) % 7 + 7) % 7
        let start = range.start.index, end = range.end.index
        let lookup = lookup, cap = cap, color = color
        Canvas { context, size in
            let pitch = size.width / 7
            let side = pitch * 0.82
            var day = first
            while day < next {
                let i = day.index - first.index + offset
                let rect = CGRect(x: CGFloat(i % 7) * pitch, y: CGFloat(i / 7) * pitch, width: side, height: side)
                let path = Path(roundedRect: rect, cornerRadius: side * 0.25)
                if day.index >= start, day.index < end {
                    if let v = lookup[day.index] {
                        context.fill(path, with: .color(color.opacity(0.35 + 0.65 * min(1, v / cap))))
                    } else {
                        context.fill(path, with: .color(.white.opacity(0.09)))
                    }
                } else {
                    context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                }
                day = day.adding(days: 1)
            }
        }
    }
}
