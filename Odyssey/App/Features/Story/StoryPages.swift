import Charts
import SwiftUI
import OdysseyKit

/// Everything a story page needs besides its 0…1 animation clock.
struct StoryEnvironment {
    var recap: Recap
    var units: Units
    var narrator: Narrator
    var firstWeekday: Int
    var showNames: Bool = true
    var showRoutes: Bool = true
    /// Interactive extras (buttons) only make sense on screen, not in exports.
    var isExport: Bool = false
    var onShare: (() -> Void)? = nil
}

enum StoryLayoutMode: Equatable {
    /// Phones and the Duo's outer display: text above, picture below.
    case portrait
    /// Wide screens and the Duo's inner display: text and picture side by side, off the fold.
    case spread
    /// Duo half-folded: picture above the hinge, words and controls below.
    case tabletop
}

/// One page of the story in any layout.
struct StoryPageView: View {
    var page: StoryPage
    var env: StoryEnvironment
    var progress: Double
    var mode: StoryLayoutMode

    var body: some View {
        let theme = PageTheme.page(page, persona: env.recap.persona.primary)
        let parts = StoryPageParts(page: page, env: env, progress: progress, theme: theme)
        ZStack {
            PageBackground(theme: theme)
                .ignoresSafeArea()
            switch mode {
            case .portrait:
                GeometryReader { proxy in
                    let scale = StoryMetrics.scale(for: proxy.size)
                    VStack(alignment: .leading, spacing: 18 * scale) {
                        parts.narrative(scale: scale)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        parts.visual(scale: scale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 24 * scale)
                    .padding(.vertical, 16 * scale)
                }
            case .spread:
                FoldAwareSplit(ratio: 0.5) {
                    GeometryReader { proxy in
                        let scale = StoryMetrics.scale(for: proxy.size, spread: true)
                        parts.narrative(scale: scale)
                            .padding(32 * scale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                } secondary: {
                    GeometryReader { proxy in
                        let scale = StoryMetrics.scale(for: proxy.size, spread: true)
                        parts.visual(scale: scale)
                            .padding(28 * scale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            case .tabletop:
                FoldAwareSplit(ratio: 0.5) {
                    GeometryReader { proxy in
                        parts.visual(scale: StoryMetrics.scale(for: proxy.size, spread: true))
                            .padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } secondary: {
                    GeometryReader { proxy in
                        parts.narrative(scale: StoryMetrics.scale(for: proxy.size, spread: true) * 0.9)
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

enum StoryMetrics {
    /// 1.0 on a 402-pt-wide phone; smaller on the Duo's short outer display, bigger on wide screens.
    static func scale(for size: CGSize, spread: Bool = false) -> CGFloat {
        let byWidth = size.width / (spread ? 420 : 400)
        let byHeight = size.height / (spread ? 640 : 820)
        return min(max(min(byWidth, byHeight), 0.62), 1.45)
    }
}

/// The text half and the picture half of each page.
struct StoryPageParts {
    var page: StoryPage
    var env: StoryEnvironment
    var progress: Double
    var theme: PageTheme

    private var recap: Recap { env.recap }
    private var units: Units { env.units }
    private var n: Narrator { env.narrator }
    private var t: Totals { recap.totals }

    /// Fades and lifts an element in during part of the page's clock.
    private func reveal(_ start: Double, _ end: Double) -> Double { Easing.outCubic(Easing.segment(progress, start, end)) }

    // MARK: - Shared text styles

    private func kicker(_ text: String, scale: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(theme.accent)
    }

    private func big(_ text: String, unit: String? = nil, scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
            Text(text)
                .font(.system(size: 76 * scale, weight: .black, design: .rounded))
                .fontWidth(.compressed)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let unit {
                Text(unit)
                    .font(.system(size: 28 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func line(_ text: String, scale: CGFloat, weight: Font.Weight = .semibold, opacity: Double = 1) -> some View {
        Text(text)
            .font(.system(size: 19 * scale, weight: weight, design: .rounded))
            .foregroundStyle(.white.opacity(opacity))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func headline(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 30 * scale, weight: .heavy, design: .rounded))
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func appear<V: View>(_ view: V, _ start: Double, _ end: Double) -> some View {
        let r = reveal(start, end)
        return view.opacity(r).offset(y: (1 - r) * 18)
    }

    private func count(_ value: Double, start: Double = 0, end: Double = 0.7) -> Double {
        value * Easing.outCubic(Easing.segment(progress, start, end))
    }

    // MARK: - Narrative

    @ViewBuilder
    func narrative(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            switch page {
            case .intro: introText(scale)
            case .totals: totalsText(scale)
            case .journey: journeyText(scale)
            case .climb: climbText(scale)
            case .time: timeText(scale)
            case .rhythm: rhythmText(scale)
            case .clock: clockText(scale)
            case .sports: sportsText(scale)
            case .progress: progressText(scale)
            case .bests: bestsText(scale)
            case .moments: momentsText(scale)
            case .crew: crewText(scale)
            case .routes: routesText(scale)
            case .persona: personaText(scale)
            case .outro: outroText(scale)
            }
        }
    }

    @ViewBuilder
    private func introText(_ s: CGFloat) -> some View {
        appear(Wordmark(size: 22 * s), 0, 0.3)
        appear(line(recap.athleteFirstName.map { "\($0), this was" } ?? "This was", scale: s, opacity: 0.8), 0.1, 0.4)
        appear(
            Text(recap.range.title(format: n.format))
                .font(.system(size: 92 * s, weight: .black, design: .rounded))
                .fontWidth(.compressed)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .foregroundStyle(Palette.brand),
            0.15, 0.55
        )
        appear(line(introSubtitle, scale: s * 1.15, weight: .heavy), 0.35, 0.7)
        appear(line(recap.range.subtitle(format: n.format, today: recap.days.last), scale: s * 0.85, weight: .medium, opacity: 0.7), 0.45, 0.8)
        if recap.isEmpty {
            appear(line("Nothing recorded in this period yet. Pick another range, or go make some memories.", scale: s, opacity: 0.85), 0.5, 0.9)
        }
    }

    private var introSubtitle: String {
        switch recap.range.kind {
        case .year: "your year in motion"
        case .quarter: "your quarter in motion"
        case .month: "your month in motion"
        case .week: "your week in motion"
        case .rolling, .custom: "in motion"
        }
    }

    @ViewBuilder
    private func totalsText(_ s: CGFloat) -> some View {
        kicker("The numbers", scale: s)
        appear(line("You moved \(units.integer(t.count)) times and covered", scale: s), 0, 0.25)
        big(units.distanceNumber(count(t.distance), decimals: t.distance < 100_000 ? 1 : 0), unit: units.distanceUnit, scale: s)
        if let change = recap.progression.vsPrevious?.distance {
            appear(DeltaBadge(relative: change, label: n.previousLabel(for: recap.range), narrator: n), 0.6, 0.9)
        }
        appear(statRow("clock.fill", "\(units.hours(count(t.movingTime, start: 0.2, end: 0.8))) hours moving", s), 0.2, 0.5)
        appear(statRow("mountain.2.fill", "\(units.elevation(count(t.elevationGain, start: 0.3, end: 0.9))) climbed", s), 0.3, 0.6)
        appear(statRow("calendar", "\(units.integer(t.activeDays)) active days", s), 0.4, 0.7)
        if t.kudos > 0 {
            appear(statRow("hand.thumbsup.fill", "\(units.integer(t.kudos)) kudos received", s), 0.5, 0.8)
        }
    }

    private func statRow(_ symbol: String, _ text: String, _ s: CGFloat) -> some View {
        Label {
            Text(text).monospacedDigit()
        } icon: {
            Image(systemName: symbol).foregroundStyle(theme.accent)
        }
        .font(.system(size: 20 * s, weight: .bold, design: .rounded))
    }

    @ViewBuilder
    private func journeyText(_ s: CGFloat) -> some View {
        kicker("How far", scale: s)
        appear(line("You covered", scale: s, opacity: 0.85), 0, 0.2)
        big(units.distanceNumber(count(t.distance, end: 0.5), decimals: t.distance < 100_000 ? 1 : 0), unit: units.distanceUnit, scale: s)
        if let e = recap.equivalents.headline {
            appear(line("That's", scale: s, opacity: 0.85), 0.45, 0.65)
            appear(headline(n.journeyLine(e), scale: s), 0.5, 0.75)
            appear(line(n.journeyDetail(e, totalMeters: t.distance), scale: s * 0.85, weight: .medium, opacity: 0.75), 0.6, 0.85)
        }
        if recap.equivalents.trackLaps >= 25, recap.totals.runDistance > 0 {
            appear(Label(n.trackLaps(recap.equivalents.trackLaps), systemImage: "circle.dashed")
                .font(.system(size: 17 * s, weight: .semibold, design: .rounded)), 0.75, 0.95)
        }
    }

    @ViewBuilder
    private func climbText(_ s: CGFloat) -> some View {
        kicker("How high", scale: s)
        appear(line("You climbed", scale: s, opacity: 0.85), 0, 0.2)
        big(units.number(units.elevationValue(count(t.elevationGain, end: 0.55))), unit: units.elevationUnit, scale: s)
        if let c = recap.equivalents.climb {
            appear(headline(n.climbLine(c), scale: s), 0.45, 0.7)
        }
        ForEach(Array(recap.equivalents.climbMore.prefix(2).enumerated()), id: \.offset) { i, more in
            appear(Label(n.climbLine(more), systemImage: more.landmark.symbol)
                .font(.system(size: 17 * s, weight: .semibold, design: .rounded)), 0.6 + Double(i) * 0.1, 0.85 + Double(i) * 0.1)
        }
    }

    @ViewBuilder
    private func timeText(_ s: CGFloat) -> some View {
        kicker("How long", scale: s)
        appear(line("Time on the move", scale: s, opacity: 0.85), 0, 0.2)
        big(units.hours(count(t.movingTime, end: 0.55)), unit: "hours", scale: s)
        if let days = recap.equivalents.time.first(where: { $0.id == "days" }) {
            appear(headline("That's \(n.count(days.count)) days, non-stop", scale: s), 0.45, 0.7)
        } else {
            appear(headline("Every minute counted", scale: s), 0.45, 0.7)
        }
        if t.energy > 0 {
            appear(line("≈ \(units.integer(Int(t.energy.rounded()))) kcal burned\(t.energyEstimatedShare > 0.5 ? " (estimated)" : "")", scale: s * 0.9, weight: .medium, opacity: 0.8), 0.65, 0.9)
        }
    }

    @ViewBuilder
    private func rhythmText(_ s: CGFloat) -> some View {
        kicker("Consistency", scale: s)
        appear(line("You showed up on", scale: s, opacity: 0.85), 0, 0.2)
        big(units.integer(Int(count(Double(t.activeDays), end: 0.5).rounded())), unit: "days", scale: s)
        if let streak = recap.streaks.longestDays, streak.length >= 2 {
            appear(headline("\(streak.length) days in a row", scale: s), 0.4, 0.65)
            appear(line("\(n.format.short(streak.start)) – \(n.format.short(streak.end)), your longest streak", scale: s * 0.85, weight: .medium, opacity: 0.75), 0.5, 0.75)
        }
        if let weeks = recap.streaks.longestWeeks, weeks.length >= 3 {
            appear(Label("\(weeks.length) weeks without missing one", systemImage: "flame.fill")
                .font(.system(size: 17 * s, weight: .semibold, design: .rounded)), 0.65, 0.9)
        }
    }

    @ViewBuilder
    private func clockText(_ s: CGFloat) -> some View {
        let r = recap.rhythm
        kicker("When", scale: s)
        if let day = r.favoriteWeekday {
            appear(headline("\(n.format.weekdayName(day))s are your day", scale: s * 1.1), 0, 0.3)
        }
        if r.earlyShare >= 0.25 {
            appear(line("\(n.percent(r.earlyShare)) of your starts were before 8am. The early bird gets the miles.", scale: s), 0.2, 0.5)
        } else if r.lateShare >= 0.25 {
            appear(line("\(n.percent(r.lateShare)) of your starts were after 7pm. Night moves.", scale: s), 0.2, 0.5)
        } else if let peak = r.peakHour {
            appear(line("Your favourite time to start: around \(peak):00.", scale: s), 0.2, 0.5)
        }
        if let early = recap.highlight(.earliestStart) {
            appear(Label(n.headline(early), systemImage: "sunrise.fill").font(.system(size: 17 * s, weight: .semibold, design: .rounded)), 0.45, 0.7)
        }
        if let late = recap.highlight(.latestStart) {
            appear(Label(n.headline(late), systemImage: "moon.stars.fill").font(.system(size: 17 * s, weight: .semibold, design: .rounded)), 0.55, 0.8)
        }
    }

    @ViewBuilder
    private func sportsText(_ s: CGFloat) -> some View {
        kicker("Your mix", scale: s)
        if let top = recap.sports.first {
            appear(headline("\(n.percent(top.share)) of your time: \(top.family.title.lowercased())", scale: s * 1.05), 0, 0.3)
        }
        ForEach(Array(recap.sports.prefix(5).enumerated()), id: \.offset) { i, slice in
            appear(HStack(spacing: 10 * s) {
                Circle().fill(Palette.family(slice.family)).frame(width: 12 * s, height: 12 * s)
                Image(systemName: slice.family.symbol)
                Text("\(units.integer(slice.count)) \(slice.family.noun)")
                Spacer(minLength: 6)
                Text(slice.distance >= 1000 ? units.distance(slice.distance) : Units.hoursMinutes(slice.movingTime))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
            .font(.system(size: 17 * s, weight: .semibold, design: .rounded)), 0.2 + Double(i) * 0.08, 0.5 + Double(i) * 0.08)
        }
    }

    @ViewBuilder
    private func progressText(_ s: CGFloat) -> some View {
        let p = recap.progression
        kicker("Progress", scale: s)
        if let pace = p.runPace, pace.end < pace.start * 0.995 {
            appear(headline("Your runs got faster", scale: s * 1.1), 0, 0.3)
            appear(line("Average pace \(units.paceNumber(secondsPerMeter: pace.start)) → \(units.pace(secondsPerMeter: pace.end))", scale: s), 0.2, 0.45)
        } else if let change = p.vsPrevious?.distance {
            appear(headline(change >= 0 ? "More than ever" : "A different rhythm", scale: s * 1.1), 0, 0.3)
        } else {
            appear(headline("Building, week by week", scale: s * 1.1), 0, 0.3)
        }
        if let change = p.vsPrevious?.distance {
            appear(DeltaBadge(relative: change, label: "distance \(n.previousLabel(for: recap.range))", narrator: n), 0.3, 0.55)
        }
        if let eff = p.runEfficiency, eff.relativeChange > 0.01 {
            appear(Label("\(n.percentChange(eff.relativeChange)) more ground per heartbeat", systemImage: "heart.fill")
                .font(.system(size: 17 * s, weight: .semibold, design: .rounded)), 0.45, 0.7)
        }
        if let first = p.longestRunSteps.first, let last = p.longestRunSteps.last, p.longestRunSteps.count >= 3 {
            appear(Label("Longest run: \(units.distance(first.value)) → \(units.distance(last.value))", systemImage: "arrow.up.forward")
                .font(.system(size: 17 * s, weight: .semibold, design: .rounded)), 0.55, 0.8)
        }
    }

    @ViewBuilder
    private func bestsText(_ s: CGFloat) -> some View {
        let pb = recap.personalBests
        kicker("Personal bests", scale: s)
        if pb.prCount > 0 {
            big(units.integer(Int(count(Double(pb.prCount), end: 0.4).rounded())), unit: pb.prCount == 1 ? "PR" : "PRs", scale: s)
            appear(line("set in this period", scale: s, opacity: 0.8), 0.2, 0.4)
        } else {
            appear(headline("Your fastest efforts", scale: s), 0, 0.3)
        }
        if let star = pb.headline.max(by: { $0.improvement < $1.improvement }), star.improvement > 0 {
            appear(headline("\(star.distance.title): \(Units.clock(star.first.time)) → \(Units.clock(star.best.time))", scale: s * 0.85), 0.35, 0.6)
        }
        if pb.runsChecked < pb.runsTotal, !env.isExport {
            appear(line("Checked \(pb.runsChecked) of \(pb.runsTotal) runs so far", scale: s * 0.75, weight: .medium, opacity: 0.6), 0.6, 0.9)
        }
    }

    @ViewBuilder
    private func momentsText(_ s: CGFloat) -> some View {
        kicker("Big moments", scale: s)
        appear(headline("The days you'll remember", scale: s * 1.1), 0, 0.3)
    }

    @ViewBuilder
    private func crewText(_ s: CGFloat) -> some View {
        let crew = recap.crew
        kicker("Your crew", scale: s)
        if let top = crew.companions.first, env.showNames {
            let second = crew.companions.dropFirst().first
            appear(headline(second.map { "\(top.name) & \($0.name)" } ?? top.name, scale: s * 1.15), 0, 0.3)
            appear(line(second == nil ? "your training partner" : "your best companions", scale: s, opacity: 0.8), 0.1, 0.35)
            appear(line("\(top.name): \(n.companionLine(top))", scale: s), 0.3, 0.55)
            if let second {
                appear(line("\(second.name): \(n.companionLine(second))", scale: s), 0.4, 0.65)
            }
            if let e = EquivalentFinder.headline(forKm: top.distance / 1000) {
                appear(Label("Together with \(top.name): \(n.journeyLine(e))", systemImage: e.journey.symbol)
                    .font(.system(size: 16 * s, weight: .semibold, design: .rounded)), 0.6, 0.85)
            }
        } else {
            big(units.integer(crew.groupCount), unit: "together", scale: s)
            appear(line("activities with others — \(n.percent(crew.share)) of everything you did", scale: s), 0.3, 0.6)
            if !env.isExport, !crew.untaggedGroupIDs.isEmpty {
                appear(line("Tag who you were with in the Crew tab to see your top companions.", scale: s * 0.8, weight: .medium, opacity: 0.7), 0.6, 0.9)
            }
        }
    }

    @ViewBuilder
    private func routesText(_ s: CGFloat) -> some View {
        kicker("Your routes", scale: s)
        appear(headline("\(units.integer(recap.routes.count)) of your routes, drawn", scale: s * 1.05), 0, 0.3)
        if recap.places.startAreas > 1 {
            appear(line("from \(units.integer(recap.places.startAreas)) different starting points", scale: s, opacity: 0.8), 0.2, 0.45)
        }
        if let far = recap.highlight(.furthestAway) {
            appear(Label(n.headline(far), systemImage: "airplane").font(.system(size: 16 * s, weight: .semibold, design: .rounded)), 0.4, 0.7)
        }
    }

    @ViewBuilder
    private func personaText(_ s: CGFloat) -> some View {
        let persona = recap.persona
        kicker("Your training persona", scale: s)
        appear(
            Text(persona.primary.title)
                .font(.system(size: 46 * s, weight: .black, design: .rounded))
                .fontWidth(.condensed)
                .lineLimit(2)
                .minimumScaleFactor(0.6),
            0.1, 0.4
        )
        appear(line(persona.primary.tagline, scale: s * 1.05, weight: .bold), 0.25, 0.5)
        if let why = persona.reason(for: persona.primary) {
            appear(line(why, scale: s * 0.85, weight: .medium, opacity: 0.75), 0.35, 0.6)
        }
        if !persona.traits.isEmpty {
            appear(HStack(spacing: 8) {
                ForEach(persona.traits) { trait in
                    Label(trait.title.replacingOccurrences(of: "The ", with: ""), systemImage: trait.symbol)
                        .font(.system(size: 13 * s, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.16), in: .capsule)
                }
            }, 0.5, 0.8)
        }
    }

    @ViewBuilder
    private func outroText(_ s: CGFloat) -> some View {
        kicker("That's a wrap", scale: s)
        appear(headline(recap.isEmpty ? "Your next chapter starts now" : "What a \(recap.range.kind == .year ? "year" : "stretch")\(recap.athleteFirstName.map { ", \($0)" } ?? "")", scale: s * 1.1), 0, 0.3)
        if !recap.isEmpty {
            appear(line("\(units.distance(t.distance)) · \(units.hours(t.movingTime)) h · \(units.elevation(t.elevationGain))", scale: s), 0.2, 0.45)
        }
        if let onShare = env.onShare, !env.isExport {
            appear(Button(action: onShare) {
                Label("Share your Odyssey", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.ember)
            .controlSize(.large)
            .accessibilityIdentifier("story-share"), 0.4, 0.7)
        }
        if env.isExport {
            appear(Wordmark(size: 18 * s), 0.5, 0.8)
        }
    }

    // MARK: - Visuals

    @ViewBuilder
    func visual(scale s: CGFloat) -> some View {
        switch page {
        case .intro: introVisual(s)
        case .totals: totalsVisual(s)
        case .journey: journeyVisual(s)
        case .climb:
            if let c = recap.equivalents.climb {
                ClimbStack(multiple: c.multiple, kind: c.landmark.kind, progress: Easing.segment(progress, 0.25, 1), accent: theme.accent)
                    .padding(.top, 10)
            }
        case .time: timeVisual(s)
        case .rhythm:
            CalendarHeatmap(days: recap.calendar.activeDays, range: recap.days, firstWeekday: env.firstWeekday,
                            progress: Easing.segment(progress, 0.1, 1), color: theme.accent, useTime: t.distance < 5000)
        case .clock:
            VStack(spacing: 18 * s) {
                HourClock(hourCounts: recap.rhythm.hourCounts, peak: recap.rhythm.peakHour, progress: progress, accent: theme.accent)
                WeekdayBars(counts: recap.rhythm.weekdayCounts, firstWeekday: env.firstWeekday, progress: Easing.segment(progress, 0.3, 1),
                            accent: theme.accent, format: env.narrator.format)
                    .frame(height: 90 * s)
            }
        case .sports:
            SportsRing(slices: recap.sports, progress: Easing.segment(progress, 0.1, 0.9))
                .overlay {
                    VStack(spacing: 2) {
                        Text(units.integer(t.count)).font(.system(size: 40 * s, weight: .black, design: .rounded)).monospacedDigit()
                        Text("activities").font(.system(size: 14 * s, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
        case .progress: progressVisual(s)
        case .bests: bestsVisual(s)
        case .moments: momentsVisual(s)
        case .crew: crewVisual(s)
        case .routes:
            if env.showRoutes {
                RouteArt(routes: Array(recap.routes.prefix(36)), progress: progress, columns: 6, lineWidth: 1.6 * s)
            } else {
                Image(systemName: "eye.slash").font(.largeTitle).foregroundStyle(.white.opacity(0.5))
            }
        case .persona:
            PersonaEmblem(archetype: recap.persona.primary, progress: progress)
                .padding(20 * s)
        case .outro: outroVisual(s)
        }
    }

    @ViewBuilder
    private func introVisual(_ s: CGFloat) -> some View {
        let families = recap.sports.prefix(6).map(\.family)
        GeometryReader { proxy in
            let c = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let r = min(proxy.size.width, proxy.size.height) * 0.36
            ZStack {
                Circle()
                    .stroke(Palette.brand, lineWidth: 3)
                    .frame(width: r * 2, height: r * 2)
                    .scaleEffect(0.6 + 0.4 * reveal(0, 0.5))
                    .opacity(0.8)
                    .position(c)
                Text(units.integer(t.count))
                    .font(.system(size: 64 * s, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .opacity(reveal(0.3, 0.7))
                    .position(x: c.x, y: c.y - 8 * s)
                Text("activities")
                    .font(.system(size: 15 * s, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(reveal(0.4, 0.8))
                    .position(x: c.x, y: c.y + 34 * s)
                ForEach(Array(families.enumerated()), id: \.offset) { i, family in
                    let angle = -Double.pi / 2 + Double(i) / Double(max(families.count, 1)) * 2 * .pi
                    let appear = reveal(0.2 + Double(i) * 0.08, 0.6 + Double(i) * 0.08)
                    Image(systemName: family.symbol)
                        .font(.system(size: 24 * s, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54 * s, height: 54 * s)
                        .background(Palette.family(family).opacity(0.85), in: .circle)
                        .scaleEffect(appear)
                        .position(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
                }
            }
        }
    }

    @ViewBuilder
    private func totalsVisual(_ s: CGFloat) -> some View {
        VStack(spacing: 10 * s) {
            ForEach(Array(recap.sports.prefix(4).enumerated()), id: \.offset) { i, slice in
                let r = reveal(0.25 + Double(i) * 0.1, 0.6 + Double(i) * 0.1)
                HStack {
                    Image(systemName: slice.family.symbol)
                        .font(.system(size: 26 * s, weight: .bold))
                        .frame(width: 44 * s)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(units.integer(slice.count)) \(slice.family.noun)")
                            .font(.system(size: 20 * s, weight: .heavy, design: .rounded))
                        Text(slice.distance >= 1000 ? units.distance(slice.distance) : Units.hoursMinutes(slice.movingTime))
                            .font(.system(size: 14 * s, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .monospacedDigit()
                    }
                    Spacer()
                }
                .padding(12 * s)
                .background(Palette.family(slice.family).opacity(0.28), in: .rect(cornerRadius: 18 * s))
                .opacity(r)
                .offset(x: (1 - r) * 40)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func journeyVisual(_ s: CGFloat) -> some View {
        if let e = recap.equivalents.headline, e.journey.isMappable || e.journey.kind == .planet {
            JourneyMap(journey: e.journey, progress: Easing.segment(progress, 0.2, 1), completed: e.multiple, accent: theme.accent)
        } else {
            VStack(spacing: 12 * s) {
                TrackLaps(laps: recap.equivalents.trackLaps, progress: progress, accent: theme.accent)
                    .aspectRatio(1.9, contentMode: .fit)
                Text(n.trackLaps(recap.equivalents.trackLaps * Easing.outCubic(progress)))
                    .font(.system(size: 18 * s, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func timeVisual(_ s: CGFloat) -> some View {
        let items: [(String, String, String)] =
            recap.equivalents.time.filter { $0.id != "days" }.map { ($0.emoji, n.count($0.count), $0.label) }
            + recap.equivalents.food.prefix(2).map { ($0.emoji, n.count($0.count), $0.label) }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10 * s), GridItem(.flexible(), spacing: 10 * s)], spacing: 10 * s) {
            ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { i, item in
                let r = reveal(0.3 + Double(i) * 0.1, 0.65 + Double(i) * 0.1)
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text(item.0).font(.system(size: 34 * s))
                    Text(item.1)
                        .font(.system(size: 30 * s, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.2)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
                .padding(14 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 20 * s))
                .scaleEffect(0.85 + 0.15 * r)
                .opacity(r)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func progressVisual(_ s: CGFloat) -> some View {
        let buckets = recap.progression.buckets
        let useTime = t.distance < 5000
        let grow = Easing.outCubic(Easing.segment(progress, 0.1, 0.9))
        let values = buckets.map { useTime ? $0.movingTime / 3600 : units.distanceValue($0.distance) }
        let labels = ChartLabels(buckets: buckets, granularity: recap.progression.granularity, format: n.format)
        let accent = theme.accent
        VStack(alignment: .leading, spacing: 10 * s) {
            Chart(Array(values.enumerated()), id: \.offset) { i, v in
                BarMark(x: .value("Period", i), y: .value("Volume", v * grow))
                    .foregroundStyle(accent.gradient)
                    .cornerRadius(3)
            }
            .chartYScale(domain: 0...max(1, values.max() ?? 1))
            .chartXScale(domain: -0.6...(Double(values.count) - 0.4))
            .chartXAxis {
                AxisMarks(values: labels.tickIndices) { value in
                    AxisValueLabel {
                        Text(labels.label(value.as(Int.self))).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel().foregroundStyle(.white.opacity(0.7))
                }
            }
            Text(useTime ? "Hours per \(recap.progression.granularity.rawValue)" : "\(units.distanceUnit) per \(recap.progression.granularity.rawValue)")
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private func bestsVisual(_ s: CGFloat) -> some View {
        let items = Array(recap.personalBests.items.filter { $0.distance.isHeadline || $0.distance == .k1 }.prefix(5))
        VStack(spacing: 10 * s) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let r = reveal(0.25 + Double(i) * 0.1, 0.6 + Double(i) * 0.1)
                HStack(alignment: .center, spacing: 12 * s) {
                    Text(item.distance.title)
                        .font(.system(size: 15 * s, weight: .bold, design: .rounded))
                        .frame(width: 92 * s, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Units.clock(item.best.time))
                            .font(.system(size: 24 * s, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Text(item.improvement > 0 ? "−\(Units.clock(item.improvement)) since \(n.format.short(item.first.day))" : n.format.short(item.best.day))
                            .font(.system(size: 12 * s, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    if !item.prs.isEmpty {
                        Text(item.prs.count == 1 ? "PR" : "\(item.prs.count) PRs")
                            .font(.system(size: 12 * s, weight: .heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.accent, in: .capsule)
                            .foregroundStyle(.black)
                    }
                }
                .padding(12 * s)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 18 * s))
                .opacity(r)
                .offset(x: (1 - r) * 30)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func momentsVisual(_ s: CGFloat) -> some View {
        let moments = StoryScript.moments(for: recap, limit: 4)
        VStack(spacing: 10 * s) {
            ForEach(Array(moments.enumerated()), id: \.offset) { i, h in
                let r = reveal(0.15 + Double(i) * 0.15, 0.5 + Double(i) * 0.15)
                HStack(alignment: .top, spacing: 12 * s) {
                    Image(systemName: Self.symbol(for: h))
                        .font(.system(size: 20 * s, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 30 * s)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.headline(h))
                            .font(.system(size: 17 * s, weight: .heavy, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(n.detail(h))
                            .font(.system(size: 13 * s, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12 * s)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 18 * s))
                .opacity(r)
                .offset(y: (1 - r) * 24)
            }
            Spacer(minLength: 0)
        }
    }

    static func symbol(for h: Highlight) -> String {
        switch h.kind {
        case .race: "medal.fill"
        case .longest: h.sport?.symbol ?? "figure.run"
        case .biggestClimb: "mountain.2.fill"
        case .fastestRun, .fastestRide: "bolt.fill"
        case .furthestAway: "airplane"
        case .mostKudos: "hand.thumbsup.fill"
        case .earliestStart: "sunrise.fill"
        case .latestStart: "moon.stars.fill"
        case .longestSwim: "figure.pool.swim"
        case .biggestGroup: "person.3.fill"
        case .longestDuration: "hourglass"
        case .biggestWeek, .busiestMonth, .firstActivity: "calendar"
        }
    }

    @ViewBuilder
    private func crewVisual(_ s: CGFloat) -> some View {
        if env.showNames, !recap.crew.companions.isEmpty {
            CrewConstellation(companions: recap.crew.companions, initialsOfYou: recap.athleteFirstName.map { CrewConstellation.initials($0) } ?? "You",
                              progress: progress, accent: theme.accent)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 64 * s, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .scaleEffect(0.7 + 0.3 * reveal(0, 0.6))
                if let biggest = recap.crew.biggestGroup {
                    Text("Biggest group: \(Int(biggest.value)) athletes")
                        .font(.system(size: 16 * s, weight: .semibold))
                        .opacity(reveal(0.4, 0.8))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func outroVisual(_ s: CGFloat) -> some View {
        VStack(spacing: 14 * s) {
            HStack(spacing: 12 * s) {
                miniStat(units.distanceNumber(t.distance, decimals: 0), units.distanceUnit, s)
                miniStat(units.hours(t.movingTime), "hours", s)
            }
            HStack(spacing: 12 * s) {
                miniStat(units.integer(t.count), "activities", s)
                miniStat(units.number(units.elevationValue(t.elevationGain)), units.elevationUnit, s)
            }
            if let e = recap.equivalents.headline {
                Label(n.journeyLine(e), systemImage: e.journey.symbol)
                    .font(.system(size: 16 * s, weight: .bold, design: .rounded))
                    .padding(12 * s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 16 * s))
            }
            Label(recap.persona.primary.title, systemImage: recap.persona.primary.symbol)
                .font(.system(size: 16 * s, weight: .bold, design: .rounded))
                .padding(12 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.persona(recap.persona.primary).opacity(0.3), in: .rect(cornerRadius: 16 * s))
            Spacer(minLength: 0)
            PoweredByStrava()
                .foregroundStyle(.white.opacity(0.6))
        }
        .opacity(reveal(0.2, 0.7))
    }

    private func miniStat(_ value: String, _ label: String, _ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30 * s, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 13 * s, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(14 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: .rect(cornerRadius: 18 * s))
    }
}

/// Axis labels for progression charts, thinned so they never collide.
struct ChartLabels {
    var buckets: [Bucket]
    var granularity: Granularity
    var format: DayFormat

    var tickIndices: [Int] {
        let n = buckets.count
        guard n > 0 else { return [] }
        let step: Int
        switch granularity {
        case .month: step = n > 6 ? 2 : 1
        case .week: step = max(1, Int((Double(n) / 5).rounded(.up)))
        case .day: step = n > 10 ? 7 : 1
        }
        return Array(stride(from: 0, to: n, by: step))
    }

    func label(_ index: Int?) -> String {
        guard let index, buckets.indices.contains(index) else { return "" }
        let day = buckets[index].start
        switch granularity {
        case .month: return format.monthShort(day)
        case .week: return format.short(day)
        case .day: return format.weekdayNameShort(day.weekday)
        }
    }
}
