import SwiftUI
import SnagKit

/// Your discount wallet: who you are (student, NHS…), the schemes that
/// verify you, and codes Snag can try for you at checkout.
struct PerksView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var newCode = ""
    @State private var newCodeShop = ""
    @State private var connecting: DiscountProgram?
    @State private var browsing: CheckoutRequest?
    @State private var connected: Set<String> = []

    private var catalog: DiscountCatalog { .standard }

    private var programs: [DiscountProgram] {
        let mine = settings.eligibilities
        return catalog.programs.filter { program in
            program.regions.contains(settings.region) && !Set(program.eligibility).isDisjoint(with: mine)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    eligibilitySection
                    if !programs.isEmpty { programsSection }
                    codesSection
                    agentSection
                }
                .padding()
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .ambientBackground(tint: Theme.mint)
            .navigationTitle("Perks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Region", selection: Binding(get: { settings.region }, set: { settings.region = $0 })) {
                            ForEach(Region.allCases) { Text($0.displayName).tag($0) }
                        }
                    } label: {
                        Label(settings.region.displayName, systemImage: "globe")
                    }
                }
            }
            .modifier(VerticalBarReader())
            .onAppear { connected = KeychainStore.connectedProgramIDs(among: catalog.programs) }
            .sheet(item: $connecting, onDismiss: { connected = KeychainStore.connectedProgramIDs(among: catalog.programs) }) { program in
                ProgramConnectView(program: program)
            }
            .sheet(item: $browsing) { request in
                CheckoutView(request: request)
            }
        }
    }

    private var eligibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "I'm a…", subtitle: "We'll apply these discounts to every price", symbol: "person.text.rectangle.fill")
            GlassEffectContainer(spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(Eligibility.relevant(in: settings.region)) { e in
                        GlassChip(title: e.title, symbol: e.symbol, isOn: settings.eligibilities.contains(e)) {
                            withAnimation(.snappy) {
                                if settings.eligibilities.contains(e) { settings.eligibilities.remove(e) } else { settings.eligibilities.insert(e) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your discount schemes", subtitle: "Connect once; Snag fills your login and finds codes for you", symbol: "checkmark.shield.fill")
            ForEach(programs) { program in
                let isConnected = connected.contains(program.id)
                ContentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(program.name).font(.headline)
                                Text(program.eligibility.filter { settings.eligibilities.contains($0) }.map(\.title).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isConnected {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(program.blurb).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button(isConnected ? "Manage" : "Connect", systemImage: isConnected ? "person.badge.key.fill" : "link") {
                                connecting = program
                            }
                            .buttonStyle(.glassProminent)
                            Button("Browse offers", systemImage: "safari") {
                                browsing = CheckoutRequest(url: program.homepage, merchant: program.name, merchantDomain: program.homepage.host(), productTitle: "", expectedPrice: nil, currency: settings.currency)
                            }
                            .buttonStyle(.glass)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var codesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your codes", subtitle: "Snag tries these automatically at the right shop", symbol: "ticket.fill")
            ContentCard {
                VStack(spacing: 10) {
                    HStack {
                        TextField("Code", text: $newCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                        PasteButton(payloadType: String.self) { strings in
                            if let s = strings.first { newCode = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                    }
                    HStack {
                        TextField("Shop website (e.g. nike.com)", text: $newCodeShop)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                        Button("Add") {
                            model.saveCode(newCode, domain: newCodeShop.isEmpty ? nil : newCodeShop, source: .manual)
                            newCode = ""
                            newCodeShop = ""
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(newCode.trimmingCharacters(in: .whitespaces).count < 3)
                    }
                }
            }
            if model.savedCodes.isEmpty {
                Text("Codes you add or that Snag captures while you shop show up here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.savedCodes) { code in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(code.code).font(.headline.monospaced())
                        Text([code.merchantDomain ?? "Any shop", code.lastSaving.map { "saved \($0.money(settings.currency))" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !code.isUsable() {
                        Text("Not working").font(.caption2).foregroundStyle(Theme.coral)
                    }
                    Button(role: .destructive) {
                        model.savedCodes.removeAll { $0.id == code.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(code.code)")
                }
                .padding(12)
                .background(.background.secondary.opacity(0.7), in: .rect(cornerRadius: 16))
            }
        }
    }

    private var agentSection: some View {
        GlassCard(tint: Theme.mint) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { settings.autoApplyCodes }, set: { settings.autoApplyCodes = $0 })) {
                    Label("Checkout agent", systemImage: "wand.and.sparkles")
                        .font(.headline)
                }
                Text("When you buy through Snag, the agent finds the promo box, tries your codes and keeps the one that saves the most. It fills scheme logins only on that scheme's own site, and never touches payment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Save a scheme login to the Keychain, or just sign in on the scheme's site.
struct ProgramConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    var program: DiscountProgram

    @State private var username = ""
    @State private var password = ""
    @State private var signingIn: CheckoutRequest?
    @State private var existing: ProgramCredential?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(program.blurb).foregroundStyle(.secondary)
                    Button("Sign in on \(program.name)", systemImage: "safari") {
                        signingIn = CheckoutRequest(url: program.homepage, merchant: program.name, merchantDomain: program.homepage.host(), productTitle: "", expectedPrice: nil, currency: settings.currency)
                    }
                } footer: {
                    Text("Signing in once inside Snag keeps you signed in, so code pages open ready to go.")
                }
                Section {
                    TextField("Email or username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Let Snag fill your login (optional)")
                } footer: {
                    Text("Stored in your iPhone's Keychain on this device only, and only ever filled on \(program.homepage.host() ?? program.name).")
                }
                if existing != nil {
                    Section {
                        Button("Forget saved login", role: .destructive) {
                            KeychainStore.delete(programID: program.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(program.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        KeychainStore.save(ProgramCredential(programID: program.id, username: username, password: password, domain: program.homepage.host() ?? ""))
                        dismiss()
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                }
            }
            .onAppear {
                existing = KeychainStore.credential(for: program.id)
                username = existing?.username ?? ""
                password = existing?.password ?? ""
            }
            .sheet(item: $signingIn) { request in
                CheckoutView(request: request)
            }
        }
    }
}
