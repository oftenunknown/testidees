import Charts
import SwiftUI
import OdysseyKit

/// The whole recap as a scrollable dashboard: a magazine grid on wide
/// screens (Duo inner display, iPad), one column on phones.
struct InsightsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                if let recap = model.recap, !recap.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 640), spacing: 16, alignment: .top)], spacing: 16) {
                        totalsCard(recap)
                        progressCard(recap)
                        calendarCard(recap)
                        rhythmCard(recap)
                        sportsCard(recap)
                        if !recap.personalBests.items.isEmpty { bestsCard(recap) }
                        momentsCard(recap)
                        equivalentsCard(recap)
                        if !recap.routes.isEmpty { routesCard(recap) }
                        extrasCard(recap)
                    }
                    .padding()
                    PoweredByStrava().padding(.bottom, 24)
                } else {
                    ContentUnavailableView("Nothing here yet", systemImage: "chart.bar.xaxis", description: Text("Pick a period with activities on the Recap tab."))
                        .padding(.top, 80)
                }
            }
            .background(HomeBackdrop())
            .navigationTitle(model.range.title(format: model.narrator.format))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(RecapRange.presets(today: model.today, firstWeekday: model.settings.firstWeekday)) { preset in
                            Button(preset.title) { model.range = preset.range }
                        }
                    } label: {
                        Label("Period", systemImage: "calendar")
                    }
                }
            }
            .modifier(VerticalBarReader())
        }
    }

    private var units: Units { model.units }
    private var n: Narrator { model.narrator }

    // MARK: Cards

    private func totalsCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Totals", subtitle: r.range.subtitle(format: n.format, today: model.today), symbol: "sum")
                Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                    GridRow {
                        StatTile(value: units.distance(r.totals.distance), label: "distance", symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: Palette.ember)
                        StatTile(value: "\(units.hours(r.totals.movingTime)) h", label: "moving time", symbol: "clock.fill", tint: Palette.sky)
                    }
                    GridRow {
                        StatTile(value: units.elevation(r.totals.elevationGain), label: "climbed", symbol: "mountain.2.fill", tint: Palette.lime)
                        StatTile(value: units.integer(r.totals.count), label: "activities", symbol: "figure.mixed.cardio", tint: Palette.violet)
                    }
                    GridRow {
                        StatTile(value: units.integer(r.totals.activeDays), label: "active days", symbol: "calendar", tint: Palette.mint)
                        StatTile(value: units.integer(r.totals.kudos), label: "kudos", symbol: "hand.thumbsup.fill", tint: Palette.gold)
                    }
                }
                if let vs = r.progression.vsPrevious {
                    HStack(spacing: 8) {
                        if let d = vs.distance { DeltaBadge(relative: d, label: "distance", narrator: n) }
                        if let c = vs.count { DeltaBadge(relative: c, label: "activities", narrator: n) }
                    }
                    Text(n.previousLabel(for: r.range)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func progressCard(_ r: Recap) -> some View {
        let useTime = r.totals.distance < 5000
        let buckets = r.progression.buckets
        let values = buckets.map { useTime ? $0.movingTime / 3600 : units.distanceValue($0.distance) }
        let labels = ChartLabels(buckets: buckets, granularity: r.progression.granularity, format: n.format)
        return ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Progress", subtitle: useTime ? "Hours per \(r.progression.granularity.rawValue)" : "\(units.distanceUnit) per \(r.progression.granularity.rawValue)", symbol: "chart.bar.fill")
                Chart(Array(values.enumerated()), id: \.offset) { i, v in
                    BarMark(x: .value("Period", i), y: .value("Volume", v))
                        .foregroundStyle(Palette.brand)
                        .cornerRadius(3)
                }
                .chartXScale(domain: -0.6...(Double(values.count) - 0.4))
                .chartXAxis {
                    AxisMarks(values: labels.tickIndices) { value in
                        AxisValueLabel { Text(labels.label(value.as(Int.self))) }
                    }
                }
                .frame(height: 170)
                if let pace = r.progression.runPace {
                    Divider()
                    Text("Run pace").font(.subheadline.weight(.semibold))
                    Chart(Array(pace.points.enumerated()), id: \.offset) { _, p in
                        PointMark(x: .value("Day", p.day.index), y: .value("Pace", p.value * (units.isMetric ? 1000 : Units.metersPerMile) / 60))
                            .foregroundStyle(Palette.sky.opacity(0.35))
                            .symbolSize(18)
                    }
                    .chartXAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine()
                            AxisValueLabel { Text(Units.clock((value.as(Double.self) ?? 0) * 60)) }
                        }
                    }
                    .frame(height: 120)
                    Text("\(units.paceNumber(secondsPerMeter: pace.start)) → \(units.pace(secondsPerMeter: pace.end)) (trend)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let eff = r.progression.runEfficiency {
                    Label("\(n.percentChange(eff.relativeChange)) ground covered per heartbeat on runs", systemImage: "heart.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func calendarCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Every day you moved", subtitle: "\(r.totals.activeDays) of \(r.days.count) days", symbol: "square.grid.3x3.fill")
                CalendarHeatmap(days: r.calendar.activeDays, range: r.days, firstWeekday: model.settings.firstWeekday, progress: 1, color: Palette.ember, useTime: r.totals.distance < 5000)
                    .frame(height: r.days.count > 120 ? 110 : 160)
                HStack(spacing: 16) {
                    if let s = r.streaks.longestDays { Label("\(s.length)-day streak", systemImage: "flame.fill") }
                    if let w = r.streaks.longestWeeks { Label("\(w.length) weeks in a row", systemImage: "calendar.badge.checkmark") }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func rhythmCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "When you train", subtitle: r.rhythm.favoriteWeekday.map { "Favourite day: \(n.format.weekdayName($0))" }, symbol: "clock.fill")
                HStack(alignment: .center, spacing: 16) {
                    HourClock(hourCounts: r.rhythm.hourCounts, peak: r.rhythm.peakHour, progress: 1, accent: Palette.ember)
                        .frame(maxWidth: 160)
                        .environment(\.colorScheme, .dark)
                        .padding(10)
                        .background(Palette.midnight, in: .rect(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Before 8am: \(n.percent(r.rhythm.earlyShare))")
                        Text("After 7pm: \(n.percent(r.rhythm.lateShare))")
                        Text("Weekends: \(n.percent(r.rhythm.weekendShare))")
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func sportsCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Sport mix", subtitle: "By moving time", symbol: "chart.pie.fill")
                Chart(r.sports) { slice in
                    SectorMark(angle: .value("Time", slice.movingTime), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(Palette.family(slice.family))
                        .cornerRadius(3)
                }
                .frame(height: 170)
                ForEach(r.sports) { slice in
                    HStack {
                        Circle().fill(Palette.family(slice.family)).frame(width: 10, height: 10)
                        Label(slice.family.title, systemImage: slice.family.symbol)
                        Spacer()
                        Text("\(slice.count) · \(slice.distance >= 1000 ? units.distance(slice.distance) : Units.hoursMinutes(slice.movingTime))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func bestsCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Personal bests", subtitle: "\(r.personalBests.prCount) PRs · from \(r.personalBests.runsChecked) of \(r.personalBests.runsTotal) runs checked", symbol: "medal.fill")
                ForEach(r.personalBests.items) { item in
                    HStack {
                        Text(item.distance.title).font(.subheadline.weight(.semibold)).frame(width: 110, alignment: .leading)
                        Text(Units.clock(item.best.time)).font(.system(.body, design: .rounded, weight: .bold)).monospacedDigit()
                        Spacer()
                        if item.improvement > 0 {
                            Text("−\(Units.clock(item.improvement))").font(.caption.weight(.bold)).foregroundStyle(Palette.mint)
                        }
                        if !item.prs.isEmpty {
                            Image(systemName: "star.fill").foregroundStyle(Palette.gold).font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func momentsCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Highlights", symbol: "star.fill")
                ForEach(r.highlights) { h in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: StoryPageParts.symbol(for: h))
                            .foregroundStyle(Palette.ember)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.headline(h)).font(.subheadline.weight(.semibold))
                            Text(n.detail(h)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func equivalentsCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Put another way", symbol: "globe.europe.africa.fill")
                if let e = r.equivalents.headline {
                    if e.journey.isMappable {
                        JourneyMap(journey: e.journey, progress: 1, completed: e.multiple, accent: Palette.ember)
                            .frame(height: 150)
                            .background(Palette.midnight, in: .rect(cornerRadius: 18))
                            .environment(\.colorScheme, .dark)
                    }
                    Label(n.journeyLine(e), systemImage: e.journey.symbol).font(.subheadline.weight(.semibold))
                    Text(n.journeyDetail(e, totalMeters: r.totals.distance)).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(r.equivalents.more) { e in
                    Label(n.journeyLine(e), systemImage: e.journey.symbol).font(.subheadline)
                }
                if r.equivalents.trackLaps >= 10 {
                    Label(n.trackLaps(r.equivalents.trackLaps), systemImage: "circle.dashed").font(.subheadline)
                }
                if let c = r.equivalents.climb {
                    Label(n.climbLine(c), systemImage: c.landmark.symbol).font(.subheadline)
                }
                ForEach(r.equivalents.time) { t in
                    Text("\(t.emoji) \(n.count(t.count)) \(t.label)").font(.subheadline)
                }
                ForEach(r.equivalents.food) { f in
                    Text("\(f.emoji) \(n.count(f.count)) \(f.label)").font(.subheadline)
                }
                if r.totals.energyEstimatedShare > 0.3 {
                    Text("Energy is estimated where Strava has no calorie figure.").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func routesCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Route art", subtitle: "\(r.routes.count) routes · ends trimmed for privacy", symbol: "scribble.variable")
                RouteArt(routes: Array(r.routes.prefix(48)), progress: 1, columns: 8, lineWidth: 1.4)
                    .frame(height: 240)
                    .padding(8)
                    .background(Palette.midnight, in: .rect(cornerRadius: 18))
            }
        }
    }

    private func extrasCard(_ r: Recap) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Odds and ends", symbol: "sparkles")
                ForEach(r.gear.prefix(3)) { g in
                    Label("\(g.name): \(units.distance(g.distance)) in \(g.count) activities", systemImage: g.kind == .bike ? "bicycle" : "shoeprints.fill")
                }
                if let device = r.devices.first {
                    Label("Recorded on \(device.name), \(device.count) times", systemImage: "applewatch")
                }
                if r.naming.defaultNamed > 0, let top = r.naming.topDefaultName {
                    Label("\(n.percent(r.naming.defaultShare)) of activities kept Strava's default name — “\(top)” × \(r.naming.topDefaultCount)", systemImage: "character.cursor.ibeam")
                }
                if r.totals.commutes > 0 {
                    Label("\(r.totals.commutes) commutes", systemImage: "briefcase.fill")
                }
                if r.totals.photos > 0 {
                    Label("\(r.totals.photos) photos", systemImage: "photo.fill")
                }
            }
            .font(.subheadline)
        }
    }
}
