import SwiftUI
import OdysseyKit

/// Your training partners.
///
/// Strava's API reports how many athletes were on a group activity, but not
/// who. Odyssey reads names from titles and descriptions ("Long run with
/// Maya") and lets you tag the rest; tags stay on this device.
struct CrewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tagging: Activity?

    var body: some View {
        NavigationStack {
            Group {
                if let recap = model.recap, !recap.isEmpty {
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 0) {
                            companionsList(recap)
                                .frame(maxWidth: .infinity)
                            Divider()
                            untaggedList(recap)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        List {
                            summarySection(recap)
                            companionsSection(recap)
                            untaggedSection(recap)
                        }
                    }
                } else {
                    ContentUnavailableView("No activities in this period", systemImage: "person.2", description: Text("Pick another period on the Recap tab."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(HomeBackdrop())
            .navigationTitle("Crew")
            .modifier(VerticalBarReader())
            .sheet(item: $tagging) { activity in
                TagCompanionsView(activity: activity)
            }
        }
    }

    private var n: Narrator { model.narrator }

    private func companionsList(_ recap: Recap) -> some View {
        List {
            summarySection(recap)
            companionsSection(recap)
        }
    }

    private func untaggedList(_ recap: Recap) -> some View {
        List {
            untaggedSection(recap)
        }
    }

    @ViewBuilder
    private func summarySection(_ recap: Recap) -> some View {
        let crew = recap.crew
        Section {
            HStack(spacing: 16) {
                StatTile(value: "\(crew.groupCount)", label: "with others", symbol: "person.3.fill", tint: Palette.mint)
                StatTile(value: n.percent(crew.share), label: "of activities", symbol: "chart.pie.fill", tint: Palette.violet)
                StatTile(value: model.units.distance(crew.groupDistance, decimals: 0), label: "together", symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: Palette.ember)
            }
            if let biggest = crew.biggestGroup {
                Label("Biggest group: \(Int(biggest.value)) athletes — \(biggest.name ?? "")", systemImage: "person.3.sequence.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func companionsSection(_ recap: Recap) -> some View {
        Section {
            if recap.crew.companions.isEmpty {
                Text("No companions yet. Tag who you trained with below, or mention them in an activity title, like “Long run with Maya”.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(recap.crew.companions.enumerated()), id: \.element.id) { rank, companion in
                CompanionRow(rank: rank + 1, companion: companion, units: model.units, narrator: n)
                    .swipeActions {
                        Button("Hide", systemImage: "eye.slash", role: .destructive) { model.hideCompanion(companion.name) }
                    }
            }
        } header: {
            Text("Best companions")
        } footer: {
            Text("Names come from your titles and descriptions, plus the tags you add. Swipe to hide a name.")
        }
    }

    @ViewBuilder
    private func untaggedSection(_ recap: Recap) -> some View {
        let untagged = recap.crew.untaggedGroupIDs.compactMap { model.activity($0) }.sorted { $0.start > $1.start }
        let tagged = model.crewTags.keys.compactMap { model.activity($0) }.filter { recap.days.contains($0.day) }.sorted { $0.start > $1.start }
        Section {
            if untagged.isEmpty {
                Label("Every group activity has a name on it.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.secondary)
            }
            ForEach(untagged) { activity in
                ActivityTagRow(activity: activity, tags: [], units: model.units, format: n.format) { tagging = activity }
            }
        } header: {
            Text("Who were you with?")
        } footer: {
            Text("Strava says other athletes were with you on these, but not who. Tap one to add names.")
        }
        if !tagged.isEmpty {
            Section("Tagged by you") {
                ForEach(tagged) { activity in
                    ActivityTagRow(activity: activity, tags: model.crewTags[activity.id] ?? [], units: model.units, format: n.format) { tagging = activity }
                }
            }
        }
    }
}

struct CompanionRow: View {
    var rank: Int
    var companion: Companion
    var units: Units
    var narrator: Narrator

    var body: some View {
        HStack(spacing: 14) {
            Text(CrewConstellation.initials(companion.name))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Palette.brand, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(rank). \(companion.name)").font(.headline)
                    if !companion.confirmed {
                        Text("from titles").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: .capsule)
                    }
                }
                Text(narrator.companionLine(companion)).font(.subheadline).foregroundStyle(.secondary)
                if let e = EquivalentFinder.headline(forKm: companion.distance / 1000), companion.distance >= 5000 {
                    Label("≈ \(narrator.journeyLine(e))", systemImage: e.journey.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(companion.families.prefix(3)) { family in
                    Image(systemName: family.symbol).foregroundStyle(Palette.family(family))
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ActivityTagRow: View {
    var activity: Activity
    var tags: [String]
    var units: Units
    var format: DayFormat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: activity.sport.symbol)
                    .foregroundStyle(Palette.family(activity.sport.family))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(format.weekdayShort(activity.day)) · \(activity.distance > 0 ? units.distance(activity.distance) : Units.hoursMinutes(activity.movingTime)) · \(activity.athleteCount) athletes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !tags.isEmpty {
                        Text(tags.joined(separator: ", ")).font(.caption.weight(.semibold)).foregroundStyle(Palette.mint)
                    }
                }
                Spacer()
                Image(systemName: tags.isEmpty ? "person.badge.plus" : "pencil")
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Add or edit the names on one activity.
struct TagCompanionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var activity: Activity
    @State private var names: [String] = []
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activity.name).font(.headline)
                        Text("\(model.narrator.format.weekdayLong(activity.day)) · \(activity.athleteCount) athletes on Strava's group")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("With") {
                    if names.isEmpty {
                        Text("No one yet").foregroundStyle(.secondary)
                    }
                    FlowLayout {
                        ForEach(names, id: \.self) { name in
                            Chip(title: name, symbol: "xmark", isOn: true, tint: Palette.violet) {
                                names.removeAll { $0 == name }
                            }
                        }
                    }
                    HStack {
                        TextField("Add a name", text: $draft)
                            .textContentType(.name)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        FlowLayout {
                            ForEach(suggestions, id: \.self) { name in
                                Chip(title: name, symbol: "plus", isOn: false) { names.append(name) }
                            }
                        }
                    }
                }
                if model.crewTags[activity.id] != nil {
                    Section {
                        Button("Remove my tags", role: .destructive) {
                            model.clearTags(for: activity.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Who was there?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        add()
                        model.setTags(names, for: activity.id)
                        dismiss()
                    }
                }
            }
            .onAppear {
                names = model.crewTags[activity.id] ?? (CrewDetector.names(in: activity.name) + CrewDetector.names(in: activity.notes ?? ""))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var suggestions: [String] {
        let taken = Set(names.map { $0.lowercased() })
        return (model.recap?.crew.companions.map(\.name) ?? []).filter { !taken.contains($0.lowercased()) }.prefix(12).map { $0 }
    }

    private func add() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { draft = ""; return }
        names.append(name)
        draft = ""
    }
}
