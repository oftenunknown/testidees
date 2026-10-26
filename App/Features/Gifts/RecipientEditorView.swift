import PhotosUI
import SwiftData
import SwiftUI
import SnagKit

/// Add or edit someone you buy for. Only a name is required; everything
/// else sharpens the ideas.
struct RecipientEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var record: RecipientRecord?

    @State private var profile = RecipientProfile(name: "")
    @State private var hasDate = false
    @State private var dislikesText = ""
    @State private var pastGiftsText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var analyzing = false
    @State private var useTraits = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $profile.name)
                        .font(.title3.weight(.semibold))
                        .textContentType(.name)
                    Picker("Relationship", selection: $profile.relationship) {
                        ForEach(Relationship.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Age", selection: $profile.ageBand) {
                        Text("Not sure").tag(AgeBand?.none)
                        ForEach(AgeBand.allCases) { Text($0.title).tag(AgeBand?.some($0)) }
                    }
                }

                Section("Occasion") {
                    Picker("Occasion", selection: $profile.occasion) {
                        ForEach(Occasion.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Toggle("Has a date", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Date", selection: Binding(get: { profile.occasionDate ?? .now }, set: { profile.occasionDate = $0 }), displayedComponents: .date)
                    }
                }

                Section("Budget") {
                    BudgetPicker(min: $profile.budgetMin, max: $profile.budgetMax, currency: profile.currency)
                }

                Section {
                    InterestPicker(selected: Binding(
                        get: { Set(profile.interests.map(\.interest)) },
                        set: { newValue in
                            let existing = Dictionary(profile.interests.map { ($0.interest, $0) }, uniquingKeysWith: { a, _ in a })
                            profile.interests = newValue.map { existing[$0] ?? WeightedInterest($0, weight: 0.85, sources: [.manual]) }
                                .sorted { $0.weight > $1.weight }
                        }
                    ))
                    let photoTitle = analyzing ? "Reading photos…" : "Learn from their photos or Instagram screenshots"
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                        Label(photoTitle, systemImage: "photo.stack")
                    }
                    .disabled(analyzing)
                } header: {
                    Text("They love")
                } footer: {
                    Text("Photos are analysed on this iPhone and only labels like “cycling” are kept.")
                }

                Section("Their style") {
                    FlowLayout(spacing: 8) {
                        ForEach(Aesthetic.allCases) { a in
                            GlassChip(title: a.title, symbol: nil, isOn: profile.aesthetics.contains(a)) {
                                if let i = profile.aesthetics.firstIndex(of: a) { profile.aesthetics.remove(at: i) } else { profile.aesthetics.append(a) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle("Describe their personality", isOn: $useTraits.animation())
                    if useTraits {
                        TraitSlider(label: ("Homebody", "Life of the party"), value: traitBinding(.extraversion))
                        TraitSlider(label: ("Practical", "Sentimental"), value: traitBinding(.sentimentality))
                        TraitSlider(label: ("Creature of habit", "Adventurous"), value: traitBinding(.openness))
                        TraitSlider(label: ("Keeps it simple", "Loves luxury"), value: traitBinding(.luxury))
                        TraitSlider(label: ("Things", "Experiences"), value: traitBinding(.experiential))
                    }
                }

                Section {
                    TextField("Anything else? “Just moved”, “training for a marathon”…", text: $profile.notes, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Avoid (comma separated)", text: $dislikesText)
                    TextField("Past gifts (comma separated)", text: $pastGiftsText)
                } header: {
                    Text("Notes")
                }
            }
            .scrollContentBackground(.hidden)
            .ambientBackground(tint: Theme.violet, intensity: 0.5)
            .navigationTitle(record == nil ? "New person" : "Edit \(profile.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await analyze(items) }
            }
        }
    }

    private func traitBinding(_ key: PersonaTraits.Key) -> Binding<Double> {
        Binding(
            get: { (profile.traits ?? .neutral)[key] },
            set: { value in
                var traits = profile.traits ?? .neutral
                traits[key] = value
                profile.traits = traits
            }
        )
    }

    private func load() {
        if let record {
            profile = record.profile
        } else if profile.name.isEmpty {
            profile.currency = settings.currency
            let scale = CurrencyHint.fromUSD(1, to: settings.currency)
            profile.budgetMin = (25 * scale).rounded()
            profile.budgetMax = (80 * scale).rounded()
        }
        hasDate = profile.occasionDate != nil
        useTraits = profile.traits != nil
        dislikesText = profile.dislikes.joined(separator: ", ")
        pastGiftsText = profile.pastGifts.joined(separator: ", ")
    }

    private func save() {
        if !hasDate { profile.occasionDate = nil }
        if !useTraits { profile.traits = nil }
        profile.dislikes = split(dislikesText)
        profile.pastGifts = split(pastGiftsText)
        profile.name = profile.name.trimmingCharacters(in: .whitespaces)
        if let record {
            let interestsChanged = record.profile.interests != profile.interests || record.profile.occasion != profile.occasion
            record.profile = profile
            if interestsChanged { record.ideas = [] }
        } else {
            let record = RecipientRecord(profile: profile)
            context.insert(record)
            model.recipientSelection = record.id
        }
        try? context.save()
        Task { await Notifier.scheduleOccasionReminder(for: profile) }
        dismiss()
    }

    private func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func analyze(_ items: [PhotosPickerItem]) async {
        analyzing = true
        var images: [CGImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = ImageLoading.cgImage(from: data) {
                images.append(image)
            }
        }
        let (interests, signals) = await VisionService.interests(from: images)
        profile.interests = InterestMatcher.merge(profile.interests, interests)
        profile.signals = Array((signals + profile.signals).prefix(30))
        profile.sources.insert(.photos)
        photoItems = []
        analyzing = false
    }
}

struct InterestPicker: View {
    @Binding var selected: Set<Interest>
    @State private var showAll = false

    private static let featured: [Interest] = [.coffee, .cooking, .hiking, .travel, .reading, .music, .gaming, .fitness, .fashion, .beauty, .art, .tech, .plants, .dogs, .cats, .wine, .film, .wellness]

    var body: some View {
        let list = showAll ? Interest.allCases : Self.featured + Interest.allCases.filter { selected.contains($0) && !Self.featured.contains($0) }
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(list) { interest in
                    GlassChip(title: interest.title, symbol: interest.symbol, isOn: selected.contains(interest)) {
                        if selected.contains(interest) { selected.remove(interest) } else { selected.insert(interest) }
                    }
                }
            }
            Button(showAll ? "Fewer" : "More interests") { withAnimation(.snappy) { showAll.toggle() } }
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

private struct TraitSlider: View {
    var label: (String, String)
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: $value, in: 0...1)
            HStack {
                Text(label.0)
                Spacer()
                Text(label.1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct BudgetPicker: View {
    @Binding var min: Double
    @Binding var max: Double
    var currency: String

    private var presets: [(Double, Double)] {
        let s = CurrencyHint.fromUSD(1, to: currency)
        return [(10, 25), (25, 50), (50, 100), (100, 250), (250, 600)].map { (($0.0 * s).rounded(), ($0.1 * s).rounded()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(min.money(currency)) – \(max.money(currency))").font(.headline).monospacedDigit()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { preset in
                        GlassChip(title: "\(preset.0.money(currency))–\(preset.1.money(currency))", symbol: nil, isOn: min == preset.0 && max == preset.1) {
                            withAnimation(.snappy) { min = preset.0; max = preset.1 }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}
