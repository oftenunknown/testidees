import SwiftUI
import OdysseyKit

/// Top-level navigation. One TabView for every device:
/// - iPhone 18 / Duo outer display: Liquid Glass tab bar (on the Duo's outer
///   display iOS 27.1 moves it into the vertical side bar).
/// - Duo inner display and iPad: the same tabs adapt to regular width and each
///   screen lays out in two columns.
/// Selection and the story page live in `AppModel`, so folding or unfolding keeps your place.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Recap", systemImage: "sparkles.rectangle.stack.fill", value: AppTab.recap) {
                RecapHomeView()
            }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: AppTab.insights) {
                InsightsView()
            }
            Tab("Crew", systemImage: "person.2.fill", value: AppTab.crew) {
                CrewView()
            }
            .badge(model.recap?.crew.untaggedGroupIDs.isEmpty == false ? Text("•") : nil)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(DeviceContextReader())
        .overlay(alignment: .top) {
            if let toast = model.toast {
                GlassToast(text: toast)
                    .padding(.top, 6)
                    .padding(.horizontal)
            }
        }
        .fullScreenCover(isPresented: $model.isStoryPresented) {
            StoryPlayerView()
                .environment(model)
                .environment(settings)
                .sheet(isPresented: $model.isShareStudioPresented) {
                    ShareStudioView(initialPage: model.storyPages[safe: model.storyIndex])
                        .environment(model)
                        .environment(settings)
                }
        }
        .sheet(isPresented: Binding(
            get: { model.isShareStudioPresented && !model.isStoryPresented },
            set: { model.isShareStudioPresented = $0 }
        )) {
            ShareStudioView(initialPage: nil)
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !settings.hasOnboarded && !model.hasData },
            set: { if !$0 { settings.hasOnboarded = true } }
        )) {
            ConnectView(isOnboarding: true)
                .environment(model)
                .environment(settings)
        }
        .tint(Palette.ember)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
