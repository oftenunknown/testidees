import SwiftData
import SwiftUI
import SnagKit

/// Your gifting persona on top, the people you buy for below. On the Duo inner
/// display: people list on one side, the selected person's ideas on the other.
struct GiftStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \RecipientRecord.name) private var recipients: [RecipientRecord]
    @State private var editing: RecipientRecord?
    @State private var addingRecipient = false
    @State private var showPersonaBuilder = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.recipientSelection) {
                Section {
                    PersonaCardView(persona: model.persona) { showPersonaBuilder = true }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(recipients) { record in
                        RecipientRow(record: record)
                            .tag(record.id)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = record }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(record) }
                            }
                            .swipeActions {
                                Button(role: .destructive) { delete(record) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    Button {
                        addingRecipient = true
                    } label: {
                        Label("Add someone", systemImage: "person.crop.circle.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                } header: {
                    Text("People you buy for")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ambientBackground(tint: Theme.violet, intensity: 0.6)
            .navigationTitle("Gifts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add person", systemImage: "plus") { addingRecipient = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("My persona", systemImage: "person.crop.circle") { showPersonaBuilder = true }
                }
            }
            .modifier(VerticalBarReader())
        } detail: {
            if let id = model.recipientSelection, let record = recipients.first(where: { $0.id == id }) {
                NavigationStack {
                    RecipientDetailView(record: record) { editing = record }
                }
                .id(record.id)
            } else {
                EmptyStateView(
                    symbol: "gift",
                    title: recipients.isEmpty ? "Who are you shopping for?" : "Pick someone",
                    message: "Add the people you buy for. We blend their interests with your personality to find gifts that feel personal — then find the best price.",
                    actionTitle: recipients.isEmpty ? "Add someone" : nil
                ) { addingRecipient = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ambientBackground(tint: Theme.violet, intensity: 0.6)
            }
        }
        .sheet(isPresented: $addingRecipient) {
            RecipientEditorView(record: nil)
        }
        .sheet(item: $editing) { record in
            RecipientEditorView(record: record)
        }
        .sheet(isPresented: $showPersonaBuilder) {
            PersonaBuilderView()
        }
    }

    private func delete(_ record: RecipientRecord) {
        if model.recipientSelection == record.id { model.recipientSelection = nil }
        context.delete(record)
        try? context.save()
    }
}

private struct RecipientRow: View {
    var record: RecipientRecord

    var body: some View {
        let profile = record.profile
        HStack(spacing: 12) {
            Text(String(profile.name.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Theme.brandGradient, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name).font(.headline)
                HStack(spacing: 4) {
                    Text(profile.relationship.title)
                    Text("·")
                    Text(profile.occasion.title)
                    if let days = profile.daysUntilOccasion() {
                        Text("· \(days == 0 ? "today" : "in \(days)d")").foregroundStyle(days <= 14 ? Theme.coral : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !profile.interests.isEmpty {
                    Text(profile.interests.prefix(4).map(\.interest.title).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The headline of your persona: archetype, traits and AI portrait.
struct PersonaCardView: View {
    var persona: PersonaProfile
    var onEdit: () -> Void

    var body: some View {
        let archetype = persona.archetype
        let color = Theme.color(for: archetype)
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    PersonaAvatar(symbol: archetype.symbol, color: color, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(persona.completeness > 0 ? "YOU'RE" : "DISCOVER YOUR GIFTING STYLE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(persona.completeness > 0 ? archetype.name : "Build your persona")
                            .font(.title2.weight(.bold))
                        Text(persona.completeness > 0 ? archetype.tagline : "Quiz, photos or Instagram — a minute or two.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if let summary = persona.summary {
                    Text(summary).font(.subheadline)
                }
                if persona.completeness > 0 {
                    FlowLayout(spacing: 6) {
                        ForEach(persona.traits.dominant(3), id: \.self) { trait in
                            Text(trait.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(color.opacity(0.18), in: .capsule)
                        }
                        ForEach(persona.topInterests.prefix(4)) { interest in
                            Label(interest.title, systemImage: interest.symbol)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.background.opacity(0.4), in: .capsule)
                        }
                    }
                }
                ProgressView(value: persona.completeness) {
                    Text(persona.completeness >= 1 ? "Persona complete" : "Persona \(Int(persona.completeness * 100))% — add more for sharper ideas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(color)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(color.opacity(0.22)).interactive(), in: .rect(cornerRadius: Theme.cardRadius))
    }
}

/// Generated avatar if there is one, otherwise the archetype symbol.
struct PersonaAvatar: View {
    var symbol: String
    var color: Color
    var size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: LocalStore.avatarURL.path(percentEncoded: false)) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [color, color.opacity(0.6), Theme.indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
        .shadow(color: color.opacity(0.4), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}
