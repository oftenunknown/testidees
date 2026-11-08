import SwiftUI
import OdysseyKit

/// Fixed-size compositions for exported images. They reuse the story's views
/// (with a fixed animation clock), so what you share looks like what you saw.
enum ExportLayout {
    /// 9:16 in points; rendered at 2.7× for 1080 × 1920.
    static let page = CGSize(width: 400, height: 711)
    static let longWidth: CGFloat = 400
}

/// One story page as a 9:16 frame with a small footer.
struct ExportPage: View {
    var page: StoryPage
    var env: StoryEnvironment
    var progress: Double

    var body: some View {
        StoryPageView(page: page, env: env, progress: progress, mode: .portrait)
            .padding(.top, 18)
            .background(PageBackground(theme: PageTheme.page(page, persona: env.recap.persona.primary)))
            .overlay(alignment: .bottom) { ExportFooter() }
            .frame(width: ExportLayout.page.width, height: ExportLayout.page.height)
            .clipped()
    }
}

struct ExportFooter: View {
    var body: some View {
        HStack {
            Wordmark(size: 13)
            Spacer()
            PoweredByStrava()
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .environment(\.colorScheme, .dark)
    }
}

/// The single shareable summary card (Instagram story size).
struct StoryCardPoster: View {
    var recap: Recap
    var env: StoryEnvironment
    var theme: PageTheme

    var body: some View {
        let t = recap.totals
        let units = env.units, n = env.narrator
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Wordmark(size: 18)
                Spacer()
                Text(recap.range.title(format: n.format))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(recap.athleteFirstName.map { "\($0)'s" } ?? "My")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Text(recap.range.kind == .year ? "year in motion" : "\(recap.range.title(format: n.format)) in motion")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(units.distanceNumber(t.distance, decimals: t.distance < 100_000 ? 1 : 0))
                    .font(.system(size: 92, weight: .black, design: .rounded))
                    .fontWidth(.compressed)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Palette.brand)
                Text(units.distanceUnit).font(.system(size: 30, weight: .heavy, design: .rounded))
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile(units.integer(t.count), "activities", "figure.mixed.cardio")
                    tile("\(units.hours(t.movingTime)) h", "on the move", "clock.fill")
                }
                GridRow {
                    tile(units.elevation(t.elevationGain), "climbed", "mountain.2.fill")
                    tile(units.integer(t.activeDays), "active days", "calendar")
                }
            }
            if let e = recap.equivalents.headline {
                VStack(alignment: .leading, spacing: 6) {
                    if e.journey.isMappable {
                        JourneyMap(journey: e.journey, progress: 1, completed: e.multiple, accent: theme.accent, showLabels: false)
                            .frame(height: 96)
                    }
                    Label(n.journeyLine(e), systemImage: e.journey.symbol)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(2)
                }
                .padding(12)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 18))
            }
            HStack(spacing: 10) {
                if let c = recap.equivalents.climb {
                    pill(n.climbLine(c), c.landmark.symbol)
                }
                pill(recap.persona.primary.title.replacingOccurrences(of: "The ", with: ""), recap.persona.primary.symbol)
            }
            if env.showNames, let top = recap.crew.companions.first {
                Label("Most miles with \(top.name) — \(n.companionLine(top))", systemImage: "person.2.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(2)
            } else if let moment = StoryScript.moments(for: recap, limit: 1).first {
                Label(n.headline(moment), systemImage: StoryPageParts.symbol(for: moment))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack {
                Text(recap.range.subtitle(format: n.format, today: recap.days.last))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                PoweredByStrava()
            }
        }
        .padding(24)
        .frame(width: ExportLayout.page.width, height: ExportLayout.page.height, alignment: .topLeading)
        .background(PageBackground(theme: theme))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func tile(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.accent)
            Text(value).font(.system(size: 24, weight: .black, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: .rect(cornerRadius: 16))
    }

    private func pill(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.14), in: .capsule)
    }
}

/// Everything in one tall image: the "long pic".
struct LongPoster: View {
    var recap: Recap
    var env: StoryEnvironment
    var theme: PageTheme

    var body: some View {
        let t = recap.totals
        let units = env.units, n = env.narrator
        VStack(alignment: .leading, spacing: 26) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Wordmark(size: 20)
                Text(recap.range.title(format: n.format))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .fontWidth(.compressed)
                    .foregroundStyle(Palette.brand)
                Text("\(recap.athleteFirstName.map { "\($0) · " } ?? "")\(recap.range.subtitle(format: n.format, today: recap.days.last))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }

            section("The numbers", "sum") {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        stat(units.distance(t.distance), "distance")
                        stat("\(units.hours(t.movingTime)) h", "moving")
                    }
                    GridRow {
                        stat(units.elevation(t.elevationGain), "climbed")
                        stat(units.integer(t.count), "activities")
                    }
                    GridRow {
                        stat(units.integer(t.activeDays), "active days")
                        stat(units.integer(t.kudos), "kudos")
                    }
                }
                if let change = recap.progression.vsPrevious?.distance {
                    DeltaBadge(relative: change, label: n.previousLabel(for: recap.range), narrator: n)
                }
            }

            if let e = recap.equivalents.headline {
                section("How far", "globe.europe.africa.fill") {
                    if e.journey.isMappable || e.journey.kind == .planet {
                        JourneyMap(journey: e.journey, progress: 1, completed: e.multiple, accent: theme.accent)
                            .frame(height: 210)
                    }
                    Text(n.journeyLine(e)).font(.system(size: 24, weight: .heavy, design: .rounded))
                    Text(n.journeyDetail(e, totalMeters: t.distance)).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    ForEach(recap.equivalents.more) { more in
                        Label(n.journeyLine(more), systemImage: more.journey.symbol).font(.system(size: 15, weight: .semibold))
                    }
                    if recap.equivalents.trackLaps >= 25 {
                        Label(n.trackLaps(recap.equivalents.trackLaps), systemImage: "circle.dashed").font(.system(size: 15, weight: .semibold))
                    }
                }
            }

            if let c = recap.equivalents.climb, t.elevationGain >= 50 {
                section("How high", "mountain.2.fill") {
                    ClimbStack(multiple: c.multiple, kind: c.landmark.kind, progress: 1, accent: theme.accent)
                        .frame(height: 110)
                    Text(n.climbLine(c)).font(.system(size: 22, weight: .heavy, design: .rounded))
                }
            }

            if !recap.equivalents.time.isEmpty {
                section("How long", "clock.fill") {
                    ForEach(recap.equivalents.time) { item in
                        Text("\(item.emoji)  \(n.count(item.count)) \(item.label)").font(.system(size: 16, weight: .semibold))
                    }
                    ForEach(recap.equivalents.food.prefix(2)) { item in
                        Text("\(item.emoji)  \(n.count(item.count)) \(item.label)").font(.system(size: 16, weight: .semibold))
                    }
                }
            }

            section("Every day you moved", "square.grid.3x3.fill") {
                CalendarHeatmap(days: recap.calendar.activeDays, range: recap.days, firstWeekday: env.firstWeekday, progress: 1, color: theme.accent, useTime: t.distance < 5000)
                    .frame(height: recap.days.count > 120 ? 90 : 150)
                if let streak = recap.streaks.longestDays {
                    Label("Longest streak: \(streak.length) days", systemImage: "flame.fill").font(.system(size: 15, weight: .semibold))
                }
            }

            section("When", "sunrise.fill") {
                HStack(spacing: 16) {
                    HourClock(hourCounts: recap.rhythm.hourCounts, peak: recap.rhythm.peakHour, progress: 1, accent: theme.accent)
                        .frame(width: 150)
                    WeekdayBars(counts: recap.rhythm.weekdayCounts, firstWeekday: env.firstWeekday, progress: 1, accent: theme.accent, format: n.format)
                        .frame(height: 120)
                }
            }

            if recap.sports.count > 1 {
                section("Your mix", "chart.pie.fill") {
                    HStack(spacing: 18) {
                        SportsRing(slices: recap.sports, progress: 1).frame(width: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(recap.sports.prefix(5)) { slice in
                                HStack(spacing: 8) {
                                    Circle().fill(Palette.family(slice.family)).frame(width: 9, height: 9)
                                    Text("\(slice.count) \(slice.family.noun)").font(.system(size: 14, weight: .semibold))
                                }
                            }
                        }
                    }
                }
            }

            if !recap.personalBests.items.isEmpty {
                section("Personal bests", "medal.fill") {
                    ForEach(recap.personalBests.items.filter { $0.distance.isHeadline || $0.distance == .k1 }) { item in
                        HStack {
                            Text(item.distance.title).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(Units.clock(item.best.time)).font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
                            if !item.prs.isEmpty { Image(systemName: "star.fill").foregroundStyle(theme.accent).font(.system(size: 12)) }
                        }
                    }
                }
            }

            section("Big moments", "star.fill") {
                ForEach(StoryScript.moments(for: recap, limit: 4)) { h in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.headline(h)).font(.system(size: 16, weight: .heavy, design: .rounded))
                        Text(n.detail(h)).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                    }
                }
            }

            if env.showNames, !recap.crew.companions.isEmpty {
                section("Your crew", "person.2.fill") {
                    ForEach(recap.crew.companions.prefix(3)) { c in
                        Text("\(c.name) — \(n.companionLine(c))").font(.system(size: 15, weight: .semibold))
                    }
                }
            }

            if env.showRoutes, recap.routes.count >= 4 {
                section("Your routes", "scribble.variable") {
                    RouteArt(routes: Array(recap.routes.prefix(42)), progress: 1, columns: 7, lineWidth: 1.4)
                        .frame(height: 230)
                }
            }

            section("Your persona", recap.persona.primary.symbol) {
                Text(recap.persona.primary.title).font(.system(size: 28, weight: .black, design: .rounded))
                Text(recap.persona.primary.tagline).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }

            ExportFooter().padding(.horizontal, -18)
        }
        .padding(24)
        .frame(width: ExportLayout.longWidth, alignment: .leading)
        .background(PageBackground(theme: theme))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func section<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(theme.accent)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 22))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 24, weight: .black, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
