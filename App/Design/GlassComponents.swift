import SwiftUI
import SnagKit

/// A floating summary surface. Use for hero summaries that sit above
/// content (verdicts, persona card), not for every list row.
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 18
    var interactive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: Theme.cardRadius))
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.18)) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// Plain content surface for rows and sections — quieter than glass.
struct ContentCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary.opacity(0.75), in: .rect(cornerRadius: 22))
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
                Text(title).font(.title3.weight(.semibold))
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

/// Selectable capsule chip used for filters, interests and eligibility.
struct GlassChip: View {
    var title: String
    var symbol: String?
    var isOn: Bool
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
        .glassEffect(isOn ? Glass.regular.tint(Color.accentColor.opacity(0.85)).interactive() : Glass.regular.interactive(), in: .capsule)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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

/// Price with optional strike-through comparison.
struct PriceLabel: View {
    var price: Double
    var currency: String
    var was: Double? = nil
    var font: Font = .title2.weight(.bold)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(price.money(currency))
                .font(font)
                .contentTransition(.numericText(value: price))
                .monospacedDigit()
            if let was, was > price + 0.004 {
                Text(was.money(currency))
                    .font(.subheadline)
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Small coloured badge for a percentage change.
struct DropBadge: View {
    var fraction: Double

    var body: some View {
        let down = fraction > 0
        Label(abs(fraction).percentString, systemImage: down ? "arrow.down.right" : "arrow.up.right")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(down ? Color.green : Theme.coral)
            .background((down ? Color.green : Theme.coral).opacity(0.15), in: .capsule)
            .accessibilityLabel(down ? "Down \(abs(fraction).percentString)" : "Up \(abs(fraction).percentString)")
    }
}

/// Verdict pill shown on rows and history.
struct VerdictPill: View {
    var level: PriceVerdict.Level

    var body: some View {
        Label(level.headline, systemImage: level.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .glassEffect(.regular.tint(Theme.color(for: level).opacity(0.9)), in: .capsule)
    }
}

/// Empty-state block with a glass call to action.
struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.brandGradient)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}

/// Async product image with a calm placeholder.
struct ProductThumbnail: View {
    var url: URL?
    var size: CGFloat = 64
    var symbol: String = "shippingbox.fill"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(.white)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(size * 0.08)
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38))
            .foregroundStyle(Theme.brandGradient)
    }
}

/// Toast that floats above content for confirmations.
struct GlassToast: View {
    var symbol: String
    var text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
