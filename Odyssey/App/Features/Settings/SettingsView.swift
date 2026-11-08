import SwiftUI
import OdysseyKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var focusOnStrava = false
    @State private var secret = ""
    @State private var confirmDisconnect = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                accountSection
                stravaAppSection(settings: settings)

                Section("Units & calendar") {
                    Picker("Units", selection: $settings.unitOverride) {
                        Text("From Strava").tag(UnitSystem?.none)
                        Text("Kilometres").tag(UnitSystem?.some(.metric))
                        Text("Miles").tag(UnitSystem?.some(.imperial))
                    }
                    Picker("Week starts on", selection: $settings.firstWeekday) {
                        Text("Monday").tag(0)
                        Text("Sunday").tag(6)
                        Text("Saturday").tag(5)
                    }
                    .onChange(of: settings.firstWeekday) { _, day in
                        model.range.firstWeekday = day
                    }
                }

                Section {
                    Toggle("Auto-advance story pages", isOn: $settings.autoAdvance)
                    Toggle("Trim route starts and ends", isOn: $settings.trimRouteEnds)
                        .onChange(of: settings.trimRouteEnds) { _, _ in model.scheduleRecompute() }
                    Toggle("Companion names in shared images", isOn: $settings.shareCompanionNames)
                    Toggle("Route art in shared images", isOn: $settings.shareRouteArt)
                    if !model.hiddenCompanions.isEmpty {
                        Button("Show \(model.hiddenCompanions.count) hidden companion\(model.hiddenCompanions.count == 1 ? "" : "s") again") {
                            model.hiddenCompanions = []
                        }
                    }
                } header: {
                    Text("Story & privacy")
                } footer: {
                    Text("Route art never shows a map or scale, and trimming hides where your routes start and finish — usually home.")
                }

                Section {
                    Toggle("Use demo data", isOn: Binding(get: { settings.demoMode }, set: { model.setDemoMode($0) }))
                        .accessibilityIdentifier("demo-toggle")
                    Stepper("Detail look-ups per sync: \(settings.detailBudget)", value: $settings.detailBudget, in: 0...90, step: 10)
                    if model.isConnected {
                        Button("Sync now") { Task { await model.sync(force: true) } }
                            .disabled(model.syncState.isBusy)
                        Button("Re-download everything", role: .destructive) { Task { await model.clearCache() } }
                    }
                    if let limit = model.rateLimit {
                        LabeledContent("Strava requests (15 min)", value: "\(limit.readShortUsage ?? limit.shortUsage) of \(limit.readShortLimit ?? limit.shortLimit)")
                        LabeledContent("Strava requests (today)", value: "\(limit.readDailyUsage ?? limit.dailyUsage) of \(limit.readDailyLimit ?? limit.dailyLimit)")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Personal bests and crew names need one extra request per activity. Strava allows 100 reads every 15 minutes and 1,000 a day per app, so Odyssey fetches them a few at a time and remembers them.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Odyssey isn't made by or affiliated with Strava. Activity data is read with your permission, kept on this device, and never sold or uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    PoweredByStrava()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { secret = Vault.clientSecret ?? "" }
            .confirmationDialog("Disconnect Strava?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect and delete synced data", role: .destructive) { Task { await model.disconnect() } }
            } message: {
                Text("Odyssey asks Strava to revoke its access and deletes the activities stored on this device. Your crew tags stay.")
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Strava account") {
            if model.isConnected {
                LabeledContent("Connected as", value: model.athlete?.displayName ?? "Strava athlete")
                if let tokens = model.tokens, !tokens.canReadPrivateActivities {
                    Text("Only public and followers-only activities are visible. Reconnect and allow private activities to include them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            } else {
                ConnectInlineButton()
            }
        }
    }

    private func stravaAppSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            TextField("Client ID", text: $settings.clientID)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("client-id")
            SecureField("Client secret", text: $secret)
                .textContentType(.password)
                .onChange(of: secret) { _, value in Vault.saveClientSecret(value) }
            TextField("Callback domain", text: $settings.callbackDomain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Token server (optional, https://…)", text: $settings.tokenServer)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Link(destination: URL(string: "https://www.strava.com/settings/api")!) {
                Label("Open strava.com/settings/api", systemImage: "safari")
            }
        } header: {
            Text("Strava API app")
        } footer: {
            Text("""
            1. Create an app at strava.com/settings/api (any name and website).
            2. Set "Authorization Callback Domain" to \(settings.callbackDomain.isEmpty ? "localhost" : settings.callbackDomain).
            3. Paste the Client ID and Client Secret here, then tap Connect.
            The secret stays in this iPhone's Keychain. To share Odyssey with friends without handing out the secret, deploy the token server in Odyssey/backend and enter its URL instead.
            """)
        }
    }
}

/// "Connect with Strava" for places outside onboarding.
struct ConnectInlineButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await model.connect(using: webAuthenticationSession) }
            } label: {
                Text("Connect with Strava")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Palette.stravaOrange, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!model.isStravaConfigured)
            if !model.isStravaConfigured {
                Text("Add your Strava API app below first.").font(.footnote).foregroundStyle(.secondary)
            }
            if let error = model.connectError {
                Text(error).font(.footnote).foregroundStyle(Palette.coral)
            }
        }
    }
}
