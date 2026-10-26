import SwiftUI
import SnagKit

/// The "is this a good price?" answer at a glance: a coloured arc showing
/// where the shelf price sits between the cheapest and dearest we've seen.
struct VerdictGauge: View {
    var verdict: PriceVerdict
    var compact = false
    @State private var shown = false

    var body: some View {
        let color = Theme.color(for: verdict.level)
        VStack(spacing: compact ? 6 : 12) {
            ZStack {
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(
                        AngularGradient(colors: [Theme.mint, .green, .yellow, .orange, Theme.coral], center: .center, startAngle: .degrees(133), endAngle: .degrees(407)),
                        style: StrokeStyle(lineWidth: compact ? 8 : 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .opacity(0.9)

                // Needle dot travels along the arc.
                Circle()
                    .fill(.white)
                    .stroke(color, lineWidth: compact ? 3 : 5)
                    .frame(width: compact ? 14 : 24, height: compact ? 14 : 24)
                    .shadow(color: color.opacity(0.6), radius: 6)
                    .offset(y: -(compact ? 38 : 70))
                    .rotationEffect(.degrees(-137 + 274 * (shown ? verdict.position : 0)))

                VStack(spacing: 2) {
                    Image(systemName: verdict.level.symbol)
                        .font(compact ? .title3 : .largeTitle)
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: shown)
                    if !compact {
                        Text(verdict.userPrice.money(verdict.currency))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    }
                }
            }
            .frame(width: compact ? 84 : 156, height: compact ? 84 : 156)

            if !compact {
                Text(verdict.level.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.1)) { shown = true }
        }
        .onChange(of: verdict.position) { _, _ in
            shown = false
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { shown = true }
        }
        .sensoryFeedback(verdict.level.isBuySignal ? .success : .warning, trigger: shown) { _, new in new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(verdict.level.headline) at \(verdict.userPrice.money(verdict.currency))")
    }
}

/// One-line explanation under the gauge.
struct VerdictExplanation: View {
    var verdict: PriceVerdict

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.headline)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                Text("Based on \(verdict.comparableCount) price\(verdict.comparableCount == 1 ? "" : "s")")
                Text("·")
                Text(confidenceText)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    private var headline: String {
        let c = verdict.currency
        switch verdict.level {
        case .steal:
            return "Lowest price we've seen. Buy it."
        case .great:
            return "That's as good as it gets online."
        case .good:
            if let median = verdict.medianPrice {
                return "\((median - verdict.userPrice).money(c)) under the typical price."
            }
            return "Cheaper than most places."
        case .fair:
            if verdict.potentialSaving > 0.5, let best = verdict.bestOffer {
                return "OK, but \(best.merchant) has it for \(best.totalPrice.money(c))."
            }
            return "About what everyone charges."
        case .high:
            if let best = verdict.bestOffer {
                return "Save \(verdict.potentialSaving.money(c)) at \(best.merchant)."
            }
            return "You can do better elsewhere."
        case .unknown:
            return "Not enough prices to judge yet."
        }
    }

    private var detail: String? {
        guard let low = verdict.lowestEver, let high = verdict.highestSeen, high > low else { return nil }
        return "Seen between \(low.money(verdict.currency)) and \(high.money(verdict.currency))."
    }

    private var confidenceText: String {
        switch verdict.confidence {
        case 0.7...: "High confidence"
        case 0.35..<0.7: "Medium confidence"
        default: "Low confidence"
        }
    }
}
