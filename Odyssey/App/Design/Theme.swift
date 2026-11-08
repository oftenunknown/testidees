import SwiftUI
import OdysseyKit

/// Brand colours. `nonisolated` so drawing code (Canvas, exports) can use them anywhere.
nonisolated enum Palette {
    static let midnight = Color(red: 0.047, green: 0.039, blue: 0.149)
    static let night = Color(red: 0.09, green: 0.06, blue: 0.22)
    static let ember = Color(red: 1.00, green: 0.45, blue: 0.24)
    static let magenta = Color(red: 0.94, green: 0.26, blue: 0.55)
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.00)
    static let mint = Color(red: 0.34, green: 0.93, blue: 0.76)
    static let sky = Color(red: 0.40, green: 0.75, blue: 1.00)
    static let gold = Color(red: 1.00, green: 0.81, blue: 0.30)
    static let lime = Color(red: 0.74, green: 0.96, blue: 0.36)
    static let coral = Color(red: 1.00, green: 0.50, blue: 0.47)
    /// Strava's brand orange, used only on the "Connect with Strava" button.
    static let stravaOrange = Color(red: 0.988, green: 0.322, blue: 0.0)

    static let brand = LinearGradient(colors: [ember, magenta, violet], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func family(_ f: SportFamily) -> Color {
        Color(hue: f.hue, saturation: 0.66, brightness: 1.0)
    }

    static func persona(_ a: Archetype) -> Color {
        Color(hue: a.hue, saturation: 0.62, brightness: 0.98)
    }
}

/// Colours for one story page.
nonisolated struct PageTheme: Sendable {
    var top: Color
    var bottom: Color
    var glow: Color
    var accent: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static func page(_ page: StoryPage, persona: Archetype? = nil) -> PageTheme {
        let h = persona?.hue ?? 0.75
        return switch page {
        case .intro: PageTheme(top: Palette.midnight, bottom: rgb(0.30, 0.09, 0.42), glow: Palette.magenta, accent: Palette.ember)
        case .totals: PageTheme(top: rgb(0.42, 0.06, 0.12), bottom: rgb(0.86, 0.33, 0.13), glow: Palette.gold, accent: Palette.gold)
        case .journey: PageTheme(top: rgb(0.02, 0.05, 0.16), bottom: rgb(0.04, 0.19, 0.33), glow: Palette.sky, accent: Palette.ember)
        case .climb: PageTheme(top: rgb(0.03, 0.14, 0.15), bottom: rgb(0.08, 0.36, 0.28), glow: Palette.lime, accent: Palette.lime)
        case .time: PageTheme(top: rgb(0.17, 0.04, 0.30), bottom: rgb(0.47, 0.10, 0.45), glow: Palette.sky, accent: Palette.sky)
        case .rhythm: PageTheme(top: rgb(0.02, 0.16, 0.19), bottom: rgb(0.03, 0.36, 0.36), glow: Palette.mint, accent: Palette.mint)
        case .clock: PageTheme(top: rgb(0.04, 0.06, 0.22), bottom: rgb(0.13, 0.22, 0.50), glow: Palette.gold, accent: Palette.gold)
        case .sports: PageTheme(top: rgb(0.30, 0.05, 0.18), bottom: rgb(0.70, 0.18, 0.24), glow: Palette.sky, accent: Palette.sky)
        case .progress: PageTheme(top: rgb(0.02, 0.15, 0.09), bottom: rgb(0.04, 0.34, 0.27), glow: Palette.lime, accent: Palette.lime)
        case .bests: PageTheme(top: rgb(0.26, 0.12, 0.02), bottom: rgb(0.62, 0.33, 0.05), glow: Palette.gold, accent: Palette.gold)
        case .moments: PageTheme(top: rgb(0.26, 0.03, 0.09), bottom: rgb(0.60, 0.09, 0.18), glow: Palette.ember, accent: Palette.gold)
        case .crew: PageTheme(top: rgb(0.22, 0.05, 0.28), bottom: rgb(0.55, 0.14, 0.48), glow: Palette.mint, accent: Palette.mint)
        case .routes: PageTheme(top: rgb(0.02, 0.02, 0.05), bottom: rgb(0.07, 0.07, 0.13), glow: Palette.ember, accent: Palette.ember)
        case .persona:
            PageTheme(top: Color(hue: h, saturation: 0.75, brightness: 0.22), bottom: Color(hue: h, saturation: 0.78, brightness: 0.55),
                      glow: Color(hue: h, saturation: 0.5, brightness: 1), accent: Color(hue: h, saturation: 0.35, brightness: 1))
        case .outro: PageTheme(top: Palette.midnight, bottom: rgb(0.36, 0.10, 0.30), glow: Palette.ember, accent: Palette.ember)
        }
    }

    /// Export themes reuse a fixed palette so a long image feels like one poster.
    static func share(_ theme: ShareTheme) -> PageTheme {
        switch theme {
        case .sunset: PageTheme(top: rgb(0.10, 0.04, 0.20), bottom: rgb(0.48, 0.10, 0.32), glow: Palette.ember, accent: Palette.ember)
        case .ocean: PageTheme(top: rgb(0.01, 0.07, 0.18), bottom: rgb(0.02, 0.30, 0.42), glow: Palette.sky, accent: Palette.mint)
        case .aurora: PageTheme(top: rgb(0.02, 0.10, 0.10), bottom: rgb(0.20, 0.10, 0.40), glow: Palette.mint, accent: Palette.lime)
        case .mono: PageTheme(top: rgb(0.06, 0.06, 0.07), bottom: rgb(0.16, 0.16, 0.18), glow: .white, accent: .white)
        }
    }
}

extension Font {
    /// Big rounded numbers for stats.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

nonisolated enum Easing {
    static func outCubic(_ t: Double) -> Double {
        let c = min(max(t, 0), 1) - 1
        return c * c * c + 1
    }

    static func outBack(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    /// Progress of a sub-animation that runs from `start` to `end` of the page's 0…1 clock.
    static func segment(_ t: Double, _ start: Double, _ end: Double) -> Double {
        guard end > start else { return t >= end ? 1 : 0 }
        return min(max((t - start) / (end - start), 0), 1)
    }
}
