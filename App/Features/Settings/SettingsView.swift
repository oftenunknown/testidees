import SwiftData
import SwiftUI
import SnagKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Shopping") {
                    Picker("Region", selection: $settings.region) {
                        ForEach(Region.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Include used & refurbished", isOn: $settings.includeUsed)
                    Toggle("Checkout agent tries my codes", isOn: $settings.autoApplyCodes)
                }

                Section {
                    LabeledContent("Status", value: model.isPremium ? "Active" : "Free")
                    Button("See Premium") { model.paywallReason = "Everything in Snag, unlocked." }
                    Button("Restore purchases") { Task { await model.entitlements.restore() } }
                    if model.entitlements.isTestEnvironment {
                        Toggle("Tester unlock (TestFlight only)", isOn: $settings.testerPremium)
                    }
                } header: {
                    Text("Premium")
                }

                Section {
                    LabeledContent("AI engine", value: model.ai.bestEngine(premium: model.isPremium).label)
                    if let reason = model.ai.onDeviceUnavailableReason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Intelligence")
                }

                Section {
                    TextField("https://your-snag-server.example", text: $settings.backendURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("Server key (if you set SNAG_SHARED_SECRET)", text: $settings.backendKey)
                    SecureField("UPCitemdb API key (optional)", text: $settings.upcItemDBKey)
                } header: {
                    Text("Price sources")
                } footer: {
                    Text("Snag works out of the box with free sources (UPCitemdb, Open Food Facts, Open Prices). A Snag server adds live shopping-search prices and round-the-clock alerts with push. See backend/README.md.")
                }

                Section("Data") {
                    Button("Check all prices now") { Task { await model.refreshWatchedPrices(force: true) } }
                    Button("Load sample data") { DemoData.seed(into: context, model: model) }
                    Button("Show welcome again") { settings.hasOnboarded = false; dismiss() }
                    Button("Erase everything", role: .destructive) { confirmReset = true }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–")
                } footer: {
                    Text("Prices come from third-party sources and can change. Discount percentages marked “est.” are typical values — the real saving is confirmed at checkout.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .modifier(PaywallPresenter())
            .confirmationDialog("Erase all watched items, people, scans and your persona?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive, action: eraseAll)
            }
        }
    }

    private func eraseAll() {
        try? context.delete(model: WishItem.self)
        try? context.delete(model: RecipientRecord.self)
        try? context.delete(model: ScanRecord.self)
        try? context.save()
        model.persona = PersonaProfile()
        model.savedCodes = []
        try? FileManager.default.removeItem(at: LocalStore.avatarURL)
    }
}
