import ImagePlayground
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import SnagKit

/// Builds the giver's persona from whatever the user is happy to share:
/// a ten-tap quiz, photos/Instagram screenshots, their Instagram data export,
/// an order-history export, and what they already watch in Snag. Everything
/// is analysed on device (or Apple's Private Cloud Compute for premium).
struct PersonaBuilderView: View {
    enum ImportMode { case instagram, orders }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Query private var watched: [WishItem]
    @Query private var scans: [ScanRecord]

    @State private var showQuiz = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var analyzing: String?
    @State private var importMode: ImportMode?
    @State private var showAvatarSheet = false
    @State private var avatarPrompt = ""
    @State private var lastPhotos: [CGImage] = []
    @State private var avatarVersion = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PersonaCardView(persona: model.persona) { showQuiz = true }
                        .id(avatarVersion)

                    source(
                        symbol: "checklist", color: Theme.teal,
                        title: "Quick quiz", detail: model.persona.sources.contains(.quiz) ? "Done — retake any time" : "Ten taps, under a minute",
                        done: model.persona.sources.contains(.quiz), premium: false
                    ) { showQuiz = true }

                    let photosLabel = sourceLabel(
                        symbol: "photo.stack.fill", color: Theme.coral,
                        title: "Photos or Instagram screenshots", detail: "Pick your grid or favourite photos. We read them on device.",
                        done: model.persona.sources.contains(.photos), premium: true
                    )
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                        photosLabel
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isPremium)
                    .overlay { premiumTapCatcher("Learn your style from your photos and Instagram with Premium.") }

                    source(
                        symbol: "square.and.arrow.down.on.square.fill", color: Theme.violet,
                        title: "Instagram data export", detail: "Instagram app → Accounts Centre → Download your information → JSON. Then pick the files here.",
                        done: model.persona.sources.contains(.instagramExport), premium: true
                    ) { requirePremium { importMode = .instagram } }

                    source(
                        symbol: "bag.fill", color: .orange,
                        title: "Shopping habits", detail: "Use what you watch and scan in Snag, plus an order-history CSV if you have one.",
                        done: model.persona.sources.contains(.orderHistory) || model.persona.sources.contains(.wishlist), premium: false
                    ) {
                        importHabits(.success([]))
                        importMode = .orders
                    }

                    if model.persona.completeness > 0 {
                        aiSection
                    }

                    if let analyzing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(analyzing).font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular, in: .capsule)
                    }

                    privacyNote
                }
                .padding()
            }
            .ambientBackground(tint: Theme.violet)
            .navigationTitle("Your gifting persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showQuiz) {
                PersonaQuizView()
            }
            .modifier(PaywallPresenter())
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await analyzePhotos(items) }
            }
            .fileImporter(
                isPresented: Binding(get: { importMode != nil }, set: { if !$0 { importMode = nil } }),
                allowedContentTypes: importMode == .instagram ? [.json] : [.commaSeparatedText, .plainText],
                allowsMultipleSelection: true
            ) { result in
                let mode = importMode
                importMode = nil
                switch mode {
                case .instagram:
                    if case .success(let urls) = result { importInstagram(urls) }
                case .orders:
                    importHabits(result)
                case nil:
                    break
                }
            }
            .imagePlaygroundSheet(
                isPresented: $showAvatarSheet,
                concepts: [.text(avatarPrompt), .text(model.persona.archetype.name)]
            ) { url in
                saveAvatar(from: url)
            }
        }
    }

    // MARK: - Sections

    private var aiSection: some View {
        GlassCard(tint: Theme.violet) {
            VStack(alignment: .leading, spacing: 12) {
                Label("AI portrait", systemImage: "wand.and.stars").font(.headline)
                if let signature = model.persona.signature {
                    Text("“\(signature)”").font(.subheadline.italic())
                }
                Text("Apple Intelligence writes a short portrait of you as a gift-giver and can illustrate an avatar for your persona card.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.persona.summary == nil ? "Write my portrait" : "Rewrite", systemImage: "text.quote") {
                        requirePremium { Task { await writePortrait() } }
                    }
                    .buttonStyle(.glassProminent)
                    if supportsImagePlayground {
                        Button("Avatar", systemImage: "person.crop.circle.badge.plus") {
                            requirePremium {
                                if avatarPrompt.isEmpty { avatarPrompt = defaultAvatarPrompt }
                                showAvatarSheet = true
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private var defaultAvatarPrompt: String {
        let interests = model.persona.topInterests.prefix(3).map { $0.title.lowercased() }.joined(separator: ", ")
        let style = model.persona.aesthetics.first?.title.lowercased() ?? "warm"
        return "a \(style) illustrated character who loves \(interests.isEmpty ? "giving thoughtful gifts" : interests)"
    }

    private var privacyNote: some View {
        Label("Photos and files are analysed on this iPhone. Only labels like “hiking” or “coffee” are kept — never the images. Premium AI uses Apple's Private Cloud Compute, which Apple can't read.", systemImage: "lock.shield.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func source(symbol: String, color: Color, title: String, detail: String, done: Bool, premium: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sourceLabel(symbol: symbol, color: color, title: title, detail: detail, done: done, premium: premium)
        }
        .buttonStyle(.plain)
    }

    private func sourceLabel(symbol: String, color: Color, title: String, detail: String, done: Bool, premium: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(color.gradient, in: .rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if premium && !model.isPremium {
                        Image(systemName: "crown.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(done ? Color.green : Color.secondary)
        }
        .padding(14)
        .contentShape(.rect)
        .background(.background.secondary.opacity(0.75), in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private func premiumTapCatcher(_ reason: String) -> some View {
        if !model.isPremium {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { model.paywallReason = reason }
        }
    }

    private func requirePremium(_ action: () -> Void) {
        if model.isPremium { action() } else { model.paywallReason = "Deeper persona learning and AI portraits are part of Premium." }
    }

    // MARK: - Learning

    private func analyzePhotos(_ items: [PhotosPickerItem]) async {
        analyzing = "Looking at \(items.count) photo\(items.count == 1 ? "" : "s")…"
        var images: [CGImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = ImageLoading.cgImage(from: data) {
                images.append(image)
            }
        }
        let (interests, signals) = await VisionService.interests(from: images)
        var persona = model.persona
        persona.interests = InterestMatcher.merge(persona.interests, interests)
        persona.signals = Array((signals + persona.signals).prefix(40))
        persona.sources.insert(.photos)
        persona.updatedAt = .now
        model.persona = persona
        lastPhotos = Array(images.prefix(6))
        photoItems = []
        analyzing = nil
        model.showToast("Learned \(interests.count) interests from your photos", symbol: "sparkles")
    }

    private func importInstagram(_ urls: [URL]) {
        var files: [(name: String, data: Data)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { files.append((url.lastPathComponent, data)) }
        }
        let parsed = InstagramExportParser.parse(files: files)
        let interests = InstagramExportParser.interests(from: parsed)
        var persona = model.persona
        persona.interests = InterestMatcher.merge(persona.interests, interests)
        persona.signals = Array((parsed.topics + persona.signals).prefix(40))
        persona.sources.insert(.instagramExport)
        model.persona = persona
        model.showToast(interests.isEmpty ? "Couldn't find interests in those files" : "Learned \(interests.count) interests from Instagram", symbol: "sparkles")
    }

    private func importHabits(_ result: Result<[URL], Error>) {
        var titles = watched.map(\.title) + scans.map(\.title)
        var sources: Set<SignalSource> = titles.isEmpty ? [] : [.wishlist]
        if case .success(let urls) = result {
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    titles += OrderHistoryParser.parse(csv: text).productNames
                    sources.insert(.orderHistory)
                }
            }
        }
        let interests = InterestMatcher.interests(from: titles.map { ($0, 0.6) }, source: .orderHistory)
        var persona = model.persona
        persona.interests = InterestMatcher.merge(persona.interests, interests)
        persona.sources.formUnion(sources)
        model.persona = persona
        model.showToast(interests.isEmpty ? "Not enough shopping history yet" : "Learned \(interests.count) interests from your shopping", symbol: "bag.fill")
    }

    private func writePortrait() async {
        analyzing = "Writing your portrait…"
        if let portrait = await model.ai.portrait(for: model.persona, photos: lastPhotos, premium: model.isPremium) {
            var persona = model.persona
            persona.summary = portrait.summary
            persona.signature = portrait.signature
            let extra = InterestMatcher.interests(fromTexts: portrait.extraInterests, source: .ai).map { WeightedInterest($0.interest, weight: 0.45, sources: [.ai]) }
            persona.interests = InterestMatcher.merge(persona.interests, extra)
            model.persona = persona
            avatarPrompt = portrait.avatarPrompt
        } else {
            model.showToast(model.ai.onDeviceUnavailableReason ?? "Couldn't write a portrait right now", symbol: "exclamationmark.triangle")
        }
        analyzing = nil
    }

    private func saveAvatar(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        try? data.write(to: LocalStore.avatarURL, options: .atomic)
        avatarVersion += 1
        model.showToast("Avatar saved", symbol: "person.crop.circle.fill")
    }
}

/// One question at a time, glass answer tiles, automatic advance.
struct PersonaQuizView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var answers: [String: [String]] = [:]
    @Namespace private var tiles

    private let quiz = PersonaQuiz.standard

    var body: some View {
        let question = quiz.questions[index]
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                ProgressView(value: Double(index), total: Double(quiz.questions.count))
                    .tint(Theme.violet)
                Text(question.prompt)
                    .font(.title2.weight(.bold))
                    .id(question.id)
                    .transition(.push(from: .trailing))
                if question.allowsMultiple {
                    Text("Pick all that apply").font(.subheadline).foregroundStyle(.secondary)
                }
                ScrollView {
                    GlassEffectContainer(spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(question.choices) { choice in
                                let picked = answers[question.id, default: []].contains(choice.id)
                                Button { pick(choice, in: question) } label: {
                                    VStack(spacing: 10) {
                                        Image(systemName: choice.symbol).font(.title2)
                                        Text(choice.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 104)
                                    .padding(10)
                                    .foregroundStyle(picked ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(picked ? .regular.tint(Theme.violet.opacity(0.85)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 22))
                                .glassEffectID(choice.id, in: tiles)
                                .sensoryFeedback(.selection, trigger: picked)
                            }
                        }
                    }
                    .id(question.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
                if question.allowsMultiple {
                    Button(index == quiz.questions.count - 1 ? "See my persona" : "Next") { advance() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(answers[question.id, default: []].isEmpty)
                }
            }
            .padding()
            .ambientBackground(tint: Theme.violet)
            .navigationTitle("Question \(index + 1) of \(quiz.questions.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if index > 0 {
                    ToolbarItem(placement: .navigation) {
                        Button("Back", systemImage: "chevron.left") { withAnimation(.snappy) { index -= 1 } }
                    }
                }
            }
        }
        .onAppear {
            answers = model.persona.quizAnswers.mapValues { $0.split(separator: ",").map(String.init) }
        }
    }

    private func pick(_ choice: PersonaQuiz.Choice, in question: PersonaQuiz.Question) {
        if question.allowsMultiple {
            var current = answers[question.id, default: []]
            if let i = current.firstIndex(of: choice.id) { current.remove(at: i) } else { current.append(choice.id) }
            answers[question.id] = current
        } else {
            answers[question.id] = [choice.id]
            Task {
                try? await Task.sleep(for: .milliseconds(260))
                advance()
            }
        }
    }

    private func advance() {
        if index < quiz.questions.count - 1 {
            withAnimation(.spring(duration: 0.45)) { index += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        let result = quiz.evaluate(answers)
        var persona = model.persona
        // Quiz sets the baseline; other sources keep their interests.
        persona.traits = result.traits
        persona.aesthetics = result.aesthetics
        persona.interests = InterestMatcher.merge(persona.interests.filter { !$0.sources.isSubset(of: [.quiz]) }, result.interests)
        persona.sources.insert(.quiz)
        persona.quizAnswers = answers.mapValues { $0.joined(separator: ",") }
        persona.updatedAt = .now
        model.persona = persona
        model.showToast("You're \(persona.archetype.name)!", symbol: persona.archetype.symbol)
        dismiss()
    }
}
