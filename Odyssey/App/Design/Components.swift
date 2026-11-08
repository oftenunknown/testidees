import SwiftUI
import OdysseyKit

/// Drives a page's entrance animation as a plain 0…1 number, so the same
/// views render live on screen and frame-by-frame into GIFs and videos.
/// The timeline pauses once finished, so the app goes idle (UI tests need that).
struct ProgressClock<Key: Hashable, Content: View>: View {
    var duration: Double
    var animate: Bool
    var key: Key
    @ViewBuilder var content: (Double) -> Content

    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished || !animate)) { context in
            content(progress(at: context.date))
        }
        .task(id: key) {
            start = Date()
            finished = !animate
            guard animate else { return }
            try? await Task.sleep(for: .seconds(duration + 0.05))
            if !Task.isCancelled { finished = true }
        }
    }

    private func progress(at date: Date) -> Double {
        guard animate, !finished else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }
}

/// Story and export backdrop: a deep gradient with two soft glows.
struct PageBackground: View {
    var theme: PageTheme

    var body: some View {
        ZStack {
            theme.gradient
            RadialGradient(colors: [theme.glow.opacity(0.42), .clear], center: .topTrailing, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [theme.accent.opacity(0.22), .clear], center: .bottomLeading, startRadius: 0, endRadius: 520)
        }
    }
}

/// A floating summary surface in Liquid Glass.
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 18
    var interactive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: 28))
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.22)) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// Quieter surface for dashboard cards.
struct ContentCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary.opacity(0.8), in: .rect(cornerRadius: 24))
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A number with a caption: "3,496 km / distance".
struct StatTile: View {
    var value: String
    var label: String
    var symbol: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.display(24))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Selectable capsule chip for filters and names.
struct Chip: View {
    var title: String
    var symbol: String? = nil
    var isOn: Bool
    var tint: Color = .accentColor
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? Glass.regular.tint(tint.opacity(0.9)).interactive() : Glass.regular.interactive(), in: .capsule)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "+23%" pill.
struct DeltaBadge: View {
    var relative: Double
    var label: String? = nil
    var narrator: Narrator

    var body: some View {
        let up = relative >= 0
        HStack(spacing: 4) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text(narrator.percentChange(relative)).monospacedDigit()
            if let label { Text(label).fontWeight(.regular) }
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(up ? Palette.mint : Palette.coral)
        .background((up ? Palette.mint : Palette.coral).opacity(0.16), in: .capsule)
        .fixedSize()
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Toast that floats above content for confirmations.
struct GlassToast: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Strava's guidelines ask for attribution wherever Strava data is shown.
struct PoweredByStrava: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Powered by")
            Text("STRAVA").fontWeight(.black).tracking(1.2)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Powered by Strava")
    }
}

/// The "Odyssey" wordmark.
struct Wordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.25) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: size * 0.8, weight: .bold))
            Text("Odyssey")
                .font(.system(size: size, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(Palette.brand)
        .accessibilityElement(children: .combine)
    }
}
