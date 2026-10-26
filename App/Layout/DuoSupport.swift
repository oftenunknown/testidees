import SwiftUI

/// Feeds window traits into `AppModel.layout`: size class everywhere, plus the
/// iOS 27.1 iPhone Duo signals — which edge the vertical bar sits on (outer
/// display) and the hinge state (book / tabletop poses).
struct DeviceContextReader: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .modifier(HingeReader())
            .onChange(of: horizontalSizeClass, initial: true) { _, size in
                withAnimation(.smooth(duration: 0.45)) {
                    model.layout.isWide = size == .regular
                }
            }
    }
}

private struct HingeReader: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                let next: LayoutContext.Hinge
                if let hinge = context.hinge {
                    switch hinge.status {
                    case .closed: next = .closed
                    case .partiallyOpen: next = .partiallyOpen
                    case .fullyOpen: next = .fullyOpen
                    default: next = .none
                    }
                    model.layout.hingeAngleDegrees = hinge.angle.degrees
                } else {
                    next = .none
                    model.layout.hingeAngleDegrees = nil
                }
                if next != model.layout.hinge {
                    withAnimation(.spring(duration: 0.5)) { model.layout.hinge = next }
                }
            }
        } else {
            content
        }
    }
}

/// Reads the vertical-bar edge where toolbars actually live (inside a
/// navigation stack) and records it, so we can move primary actions into the
/// iPhone Duo outer display's side bar.
struct VerticalBarReader: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(VerticalBarReader271())
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalBarReader271: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var edge
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.onChange(of: edge, initial: true) { _, edge in
            if model.layout.verticalBarEdge != edge {
                model.layout.verticalBarEdge = edge
            }
        }
    }
}

extension View {
    /// Which bar gives way when the Duo's side bar runs out of room.
    @ViewBuilder
    func sideBarPriority(toolbarItems: Bool) -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalCompressionBehavior(toolbarItems ? .prefersToolbarItems : .prefersTabBar)
        } else {
            self
        }
    }
}

/// Two panes side by side on wide displays. On iOS 27.1 this is an
/// `ArrangementView`, which keeps each pane off the iPhone Duo's fold and
/// re-flows when the device is half-folded.
struct FoldAwareSplit<Primary: View, Secondary: View>: View {
    var ratio: CGFloat? = nil
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        if #available(iOS 27.1, *) {
            ArrangementView {
                primary.splitArrangementLayoutRatio(ratio)
            } secondary: {
                secondary
            }
            .arrangementViewStyle(.split)
        } else {
            HStack(spacing: 0) {
                primary.frame(maxWidth: .infinity)
                Divider()
                secondary.frame(maxWidth: .infinity)
            }
        }
    }
}

/// Stacks vertically on compact screens and side by side on wide ones,
/// animating between the two when iPhone Duo is unfolded (AnyLayout keeps
/// view identity, so content glides rather than reloads).
struct AdaptiveStack<Content: View>: View {
    var isWide: Bool
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        layout { content }
    }
}
