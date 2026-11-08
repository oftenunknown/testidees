import SwiftUI
import OdysseyKit

/// Home: pick a period, see the headline numbers, and play the story.
/// Two columns on the Duo's inner display and iPad; one on phones.
struct RecapHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                if !model.hasData {
                    ConnectView(isOnboarding: false)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 18) {
                            controls
                            hero
                            status
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 18) {
                            glance
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                } else {
                    VStack(spacing: 18) {
                        controls
                        hero
                        glance
                        status
                    }
                    .padding()
                }
            }
            .background(HomeBackdrop())
            .navigationTitle(model.athlete.map { "Hi, \($0.firstName)" } ?? "Odyssey")
            .refreshable { await model.sync(force: true) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Share", systemImage: "square.and.arrow.up") { model.isShareStudioPresented = true }
                        .disabled(model.recap?.isEmpty ?? true)
                        .accessibilityIdentifier("home-share")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Settings", systemImage: "gearshape") { model.isSettingsPresented = true }
                        .accessibilityIdentifier("home-settings")
                }
            }
            .modifier(VerticalBarReader())
            .sideBarPriority(toolbarItems: false)
        }
    }

    private var controls: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                RangePicker()
                SportFilterBar()
            }
        }
    }

    // MARK: Hero

    @ViewBuilder
    private var hero: some View {
        if let recap = model.recap {
            HeroCard(recap: recap, units: model.units, narrator: model.narrator, isComputing: model.isComputing) {
                model.playStory()
            }
        } else {
            ProgressView().frame(height: 260)
        }
    }

    // MARK: Glance

    @ViewBuilder
    private var glance: some View {
        if let recap = model.recap, !recap.isEmpty {
            let n = model.narrator, units = model.units
            let pages = StoryScript.pages(for: recap)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                if let e = recap.equivalents.headline {
                    GlanceTile(title: "How far", value: n.journeyLine(e), symbol: e.journey.symbol, tint: Palette.sky) {
                        if e.journey.isMappable {
                            JourneyMap(journey: e.journey, progress: 1, completed: e.multiple, accent: Palette.ember, dotColor: .primary, showLabels: false)
                                .frame(height: 70)
                        }
                    } action: { open(.journey, in: pages) }
                }
                if let c = recap.equivalents.climb {
                    GlanceTile(title: "How high", value: n.climbLine(c), symbol: "mountain.2.fill", tint: Palette.lime) {
                        Text(units.elevation(recap.totals.elevationGain)).font(.footnote).foregroundStyle(.secondary)
                    } action: { open(.climb, in: pages) }
                }
                if let streak = recap.streaks.longestDays {
                    GlanceTile(title: "Longest streak", value: "\(streak.length) days in a row", symbol: "flame.fill", tint: Palette.ember) {
                        Text("\(units.integer(recap.totals.activeDays)) active days").font(.footnote).foregroundStyle(.secondary)
                    } action: { open(.rhythm, in: pages) }
                }
                if let top = recap.crew.companions.first {
                    GlanceTile(title: "Top companion", value: top.name, symbol: "person.2.fill", tint: Palette.mint) {
                        Text(n.companionLine(top)).font(.footnote).foregroundStyle(.secondary)
                    } action: { open(.crew, in: pages) }
                } else if recap.crew.groupCount > 0 {
                    GlanceTile(title: "Together", value: "\(recap.crew.groupCount) group activities", symbol: "person.3.fill", tint: Palette.mint) {
                        Text("Tag your crew in the Crew tab").font(.footnote).foregroundStyle(.secondary)
                    } action: { model.selectedTab = .crew }
                }
                if recap.personalBests.prCount > 0 {
                    GlanceTile(title: "Personal bests", value: "\(recap.personalBests.prCount) PRs", symbol: "medal.fill", tint: Palette.gold) {
                        if let best = recap.personalBests.headline.last {
                            Text("\(best.distance.title) \(Units.clock(best.best.time))").font(.footnote).foregroundStyle(.secondary)
                        }
                    } action: { open(.bests, in: pages) }
                }
                GlanceTile(title: "Persona", value: recap.persona.primary.title.replacingOccurrences(of: "The ", with: ""), symbol: recap.persona.primary.symbol, tint: Palette.persona(recap.persona.primary)) {
                    Text(recap.persona.primary.tagline).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                } action: { open(.persona, in: pages) }
            }
        }
    }

    private func open(_ page: StoryPage, in pages: [StoryPage]) {
        model.playStory(from: pages.firstIndex(of: page) ?? 0)
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        VStack(spacing: 10) {
            if model.settings.demoMode {
                GlassCard(tint: Palette.violet, padding: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars").font(.title3).foregroundStyle(Palette.violet)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You're looking at demo data").font(.subheadline.weight(.semibold))
                            Text("Connect Strava in Settings to see your own story.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Set up") { model.isSettingsPresented = true }
                            .buttonStyle(.glass)
                    }
                }
            } else {
                SyncStatusRow()
            }
            PoweredByStrava()
        }
    }
}

/// The big "play" card.
struct HeroCard: View {
    var recap: Recap
    var units: Units
    var narrator: Narrator
    var isComputing: Bool
    var play: () -> Void

    var body: some View {
        let t = recap.totals
        let theme = PageTheme.page(.intro)
        Button(action: play) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(recap.range.title(format: narrator.format))
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                    Spacer()
                    if isComputing { ProgressView().tint(.white) }
                }
                if recap.isEmpty {
                    Text("No activities in this period yet.")
                        .font(.title3.weight(.semibold))
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(units.distanceNumber(t.distance, decimals: t.distance < 100_000 ? 1 : 0))
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .fontWidth(.compressed)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: t.distance))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(units.distanceUnit).font(.title2.weight(.heavy)).foregroundStyle(.white.opacity(0.8))
                    }
                    HStack(spacing: 18) {
                        mini("\(units.integer(t.count))", "activities")
                        mini(units.hours(t.movingTime), "hours")
                        mini(units.number(units.elevationValue(t.elevationGain)), units.elevationUnit)
                    }
                    if let change = recap.progression.vsPrevious?.distance {
                        DeltaBadge(relative: change, label: narrator.previousLabel(for: recap.range), narrator: narrator)
                    }
                }
                HStack {
                    Label("Play your recap", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.tint(Palette.ember.opacity(0.8)).interactive(), in: .capsule)
                    Spacer()
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(Palette.gold)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background {
                PageBackground(theme: theme)
                    .clipShape(.rect(cornerRadius: 30))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("play-recap")
        .accessibilityLabel("Play your \(recap.range.title(format: narrator.format)) recap")
    }

    private func mini(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.75))
        }
    }
}

/// A tappable summary tile that opens the matching story page.
struct GlanceTile<Extra: View>: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color
    @ViewBuilder var extra: Extra
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                extra
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}

/// "Synced 2 min ago · 1,204 activities" with progress and rate-limit state.
struct SyncStatusRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            switch model.syncState {
            case .syncing(let text):
                ProgressView()
                Text(text)
            case .enriching(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(width: 60)
                Text("Reading details for PBs and crew (\(done)/\(total))")
            case .rateLimited(let until):
                Image(systemName: "hourglass").foregroundStyle(Palette.gold)
                Text("Strava's limit reached — resuming \(until.formatted(.relative(presentation: .named)))")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.coral)
                Text(message).lineLimit(2)
            case .idle:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint)
                if let last = model.library.lastSync {
                    Text("Synced \(last.formatted(.relative(presentation: .named))) · \(model.library.count) activities")
                } else {
                    Text("Not synced yet")
                }
            }
            Spacer(minLength: 0)
            if !model.syncState.isBusy, model.isConnected {
                Button("Sync", systemImage: "arrow.clockwise") { Task { await model.sync(force: true) } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// Soft brand glow behind the home screen.
struct HomeBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.55, 0.45], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: colors)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let dark = scheme == .dark
        let base = dark ? Palette.midnight : Color(red: 0.97, green: 0.96, blue: 0.99)
        return [
            Palette.ember.opacity(dark ? 0.45 : 0.22), base, Palette.violet.opacity(dark ? 0.5 : 0.2),
            base, base, base,
            Palette.magenta.opacity(dark ? 0.35 : 0.14), base, Palette.sky.opacity(dark ? 0.35 : 0.16),
        ]
    }
}
