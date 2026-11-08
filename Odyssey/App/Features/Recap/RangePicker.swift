import SwiftUI
import OdysseyKit

/// Choose any slice of your history: a year, quarter, month or week (with
/// ‹ › to step back and forth), a rolling window, or exact dates.
struct RangePicker: View {
    @Environment(AppModel.self) private var model
    @State private var customStart = Date()
    @State private var customEnd = Date()

    private let kinds: [RangeKind] = [.year, .quarter, .month, .week, .custom]

    var body: some View {
        let range = model.range
        let format = model.narrator.format
        VStack(alignment: .leading, spacing: 14) {
            Picker("Period", selection: kindBinding) {
                ForEach(kinds) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("range-kind")

            if range.kind == .custom {
                customEditor
            } else {
                HStack(spacing: 12) {
                    Button("Previous", systemImage: "chevron.left") { step(-1) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("range-previous")
                    VStack(spacing: 2) {
                        Text(range.title(format: format))
                            .font(.title2.weight(.heavy))
                            .fontDesign(.rounded)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(range.subtitle(format: format, today: model.today))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    Button("Next", systemImage: "chevron.right") { step(1) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .disabled(range.shifted(1).isFuture(today: model.today))
                        .accessibilityIdentifier("range-next")
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(RecapRange.presets(today: model.today, firstWeekday: model.settings.firstWeekday)) { preset in
                        Chip(title: preset.title, isOn: preset.range == range) {
                            withAnimation(.snappy) { model.range = preset.range }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { syncCustomDates() }
        .onChange(of: model.range) { _, _ in syncCustomDates() }
    }

    private var kindBinding: Binding<RangeKind> {
        Binding(
            get: { model.range.kind == .rolling ? .custom : model.range.kind },
            set: { kind in
                withAnimation(.snappy) {
                    if kind == .custom {
                        let current = model.range.effectiveDays(today: model.today)
                        model.range = RecapRange(.custom(current.isEmpty ? model.range.days : current), firstWeekday: model.settings.firstWeekday)
                    } else {
                        model.range = anchoredRange(kind)
                    }
                }
            }
        )
    }

    /// Switching from "2025" to Quarter shows Q4 2025, not this quarter.
    private func anchoredRange(_ kind: RangeKind) -> RecapRange {
        let anchor = min(model.range.effectiveDays(today: model.today).last, model.today)
        return RecapRange.current(kind, today: anchor, firstWeekday: model.settings.firstWeekday)
    }

    private func step(_ delta: Int) {
        withAnimation(.snappy) { model.range = model.range.shifted(delta) }
    }

    // MARK: Custom dates

    private var customEditor: some View {
        HStack {
            DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                .labelsHidden()
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            DatePicker("To", selection: $customEnd, in: customStart...max(customStart, today), displayedComponents: .date)
                .labelsHidden()
            Spacer(minLength: 0)
        }
        .onChange(of: customStart) { _, _ in applyCustom() }
        .onChange(of: customEnd) { _, _ in applyCustom() }
    }

    private var today: Date { Self.date(model.today) }

    private func syncCustomDates() {
        let days = model.range.days
        let start = Self.date(days.start), end = Self.date(days.last)
        if customStart != start { customStart = start }
        if customEnd != end { customEnd = end }
    }

    private func applyCustom() {
        guard model.range.kind == .custom || model.range.kind == .rolling else { return }
        let first = Self.day(customStart), last = Self.day(customEnd)
        guard first <= last else { return }
        let range = DayRange(first: first, last: last)
        if model.range.days != range {
            model.range = RecapRange(.custom(range), firstWeekday: model.settings.firstWeekday)
        }
    }

    /// DatePicker works in local time; convert at noon to dodge DST edges.
    static func date(_ day: LocalDay) -> Date {
        Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date()
    }

    static func day(_ date: Date) -> LocalDay {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return LocalDay(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1)
    }
}

/// Sport filter chips, only for sports in the range.
struct SportFilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let families = model.availableFamilies
        if families.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Chip(title: "All sports", symbol: "square.grid.2x2.fill", isOn: model.filter == .all) {
                        withAnimation(.snappy) { model.filter = .all }
                    }
                    ForEach(families) { family in
                        Chip(title: family.shortTitle, symbol: family.symbol, isOn: model.filter == .family(family), tint: Palette.family(family)) {
                            withAnimation(.snappy) { model.filter = model.filter == .family(family) ? .all : .family(family) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}
