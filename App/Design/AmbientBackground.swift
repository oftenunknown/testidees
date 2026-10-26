import SwiftUI

/// Slowly drifting mesh gradient behind content so Liquid Glass has
/// something to refract. Static when Reduce Motion is on.
struct AmbientBackground: View {
    var tint: Color = Theme.teal
    var intensity: Double = 1
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3, height: 3,
                points: points(t),
                colors: colors
            )
        }
        .opacity(intensity)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let dark = colorScheme == .dark
        let base = dark ? Color(red: 0.05, green: 0.05, blue: 0.12) : Color(red: 0.95, green: 0.96, blue: 0.99)
        let a = Theme.indigo.opacity(dark ? 0.85 : 0.35)
        let b = tint.opacity(dark ? 0.75 : 0.30)
        let c = Theme.mint.opacity(dark ? 0.55 : 0.28)
        let d = Theme.violet.opacity(dark ? 0.55 : 0.22)
        return [a, base, d,
                base, b, base,
                c, base, a]
    }

    private func points(_ t: TimeInterval) -> [SIMD2<Float>] {
        func wobble(_ phase: Double, _ amount: Double) -> Float { Float(sin(t * 0.18 + phase) * amount) }
        return [
            [0, 0], [0.5 + wobble(0, 0.08), 0], [1, 0],
            [0, 0.5 + wobble(1.3, 0.07)], [0.5 + wobble(2.1, 0.12), 0.5 + wobble(0.7, 0.12)], [1, 0.5 + wobble(2.9, 0.07)],
            [0, 1], [0.5 + wobble(3.7, 0.08), 1], [1, 1],
        ]
    }
}

extension View {
    /// Places the ambient mesh behind a screen.
    func ambientBackground(tint: Color = Theme.teal, intensity: Double = 1) -> some View {
        background { AmbientBackground(tint: tint, intensity: intensity) }
    }
}
