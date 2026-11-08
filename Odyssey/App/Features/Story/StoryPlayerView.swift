import SwiftUI
import OdysseyKit

/// Full-screen animated recap.
///
/// - Phones and the Duo's outer display: one page at a time, text over picture.
///   On the Duo the close/share/pause buttons are toolbar items, so iOS 27.1
///   moves them into the outer display's vertical side bar.
/// - Duo inner display, iPad, big phones in landscape: a two-page spread, words
///   on one side of the fold and the picture on the other (`ArrangementView`).
/// - Duo half-folded (tabletop): picture above the hinge, words and controls below.
///
/// The page index lives in `AppModel`, so folding or unfolding mid-story keeps
/// you on the same page instead of restarting.
struct StoryPlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isPaused = false
    @State private var direction: Edge = .trailing

    static let pageDuration: Double = 7

    var body: some View {
        NavigationStack {
            Group {
                if let recap = model.recap {
                    player(recap)
                } else {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Palette.midnight)
                }
            }
            .toolbar { toolbar }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(VerticalBarReader())
            .sideBarPriority(toolbarItems: true)
        }
        .statusBarHidden(!model.layout.hasSideBar)
        .preferredColorScheme(.dark)
    }

    // MARK: - Player

    private func player(_ recap: Recap) -> some View {
        let pages = StoryScript.pages(for: recap)
        let index = min(model.storyIndex, pages.count - 1)
        let page = pages[index]
        return GeometryReader { proxy in
            let mode = layoutMode(for: proxy.size)
            // UI tests screenshot the settled page; skipping the entrance animation keeps the app idle.
            ProgressClock(duration: 2.2, animate: !reduceMotion && !model.launch.isUITesting, key: page) { progress in
                StoryPageView(page: page, env: environment(recap), progress: progress, mode: mode)
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: direction).combined(with: .opacity),
                removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
            ))
            .contentShape(Rectangle())
            .onTapGesture { location in
                if location.x < proxy.size.width * 0.28 { previous() } else { next(count: pages.count) }
            }
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.height > 120, abs(value.translation.width) < 80 {
                            dismiss()
                        } else if value.translation.width < -60 {
                            next(count: pages.count)
                        } else if value.translation.width > 60 {
                            previous()
                        }
                    }
            )
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 20) {
                isPaused.toggle()
            }
            .animation(.smooth(duration: 0.45), value: page)
            .animation(.smooth(duration: 0.5), value: mode)
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .top, spacing: 0) {
            segments(count: pages.count, index: index)
        }
        .background(PageBackground(theme: PageTheme.page(page, persona: recap.persona.primary)).ignoresSafeArea())
        .task(id: AutoAdvanceKey(page: index, paused: isPaused)) {
            guard model.isAutoAdvanceEnabled, !isPaused, index < pages.count - 1 else { return }
            try? await Task.sleep(for: .seconds(Self.pageDuration))
            if !Task.isCancelled { next(count: pages.count) }
        }
        .sensoryFeedback(.selection, trigger: model.storyIndex)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Next page") { next(count: pages.count) }
        .accessibilityAction(named: "Previous page") { previous() }
    }

    private struct AutoAdvanceKey: Hashable {
        var page: Int
        var paused: Bool
    }

    private func layoutMode(for size: CGSize) -> StoryLayoutMode {
        if model.layout.isTabletop { return .tabletop }
        if size.width > size.height * 1.05 { return .spread }
        if sizeClass == .regular, size.width >= 600 { return .spread }
        return .portrait
    }

    private func environment(_ recap: Recap) -> StoryEnvironment {
        StoryEnvironment(
            recap: recap, units: model.units, narrator: model.narrator, firstWeekday: model.settings.firstWeekday,
            showNames: true, showRoutes: true, isExport: false,
            onShare: { model.isShareStudioPresented = true }
        )
    }

    private func next(count: Int) {
        guard model.storyIndex < count - 1 else { return }
        direction = .trailing
        withAnimation(.smooth(duration: 0.45)) { model.storyIndex += 1 }
    }

    private func previous() {
        guard model.storyIndex > 0 else { return }
        direction = .leading
        withAnimation(.smooth(duration: 0.45)) { model.storyIndex -= 1 }
    }

    // MARK: - Chrome

    private func segments(count: Int, index: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        if i < index {
                            Capsule().fill(.white)
                        } else if i == index {
                            ProgressClock(duration: Self.pageDuration, animate: model.isAutoAdvanceEnabled && !isPaused && i < count - 1, key: AutoAdvanceKey(page: i, paused: isPaused)) { p in
                                Capsule().fill(.white)
                                    .frame(width: proxy.size.width * (model.isAutoAdvanceEnabled && i < count - 1 ? p : 1))
                            }
                        }
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .accessibilityIdentifier("story-close")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.isAutoAdvanceEnabled {
                Button(isPaused ? "Play" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill") { isPaused.toggle() }
            }
            Button("Share", systemImage: "square.and.arrow.up") { model.isShareStudioPresented = true }
                .accessibilityIdentifier("story-share-toolbar")
        }
    }
}
