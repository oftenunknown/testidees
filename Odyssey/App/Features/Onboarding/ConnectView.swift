import AuthenticationServices
import SwiftUI
import OdysseyKit

/// First run and "not connected" state: connect Strava or explore demo data.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.dismiss) private var dismiss
    var isOnboarding: Bool
    @State private var showSetup = false
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header
                features
                actions
                Text("Your activities stay on this device. Odyssey reads them from Strava and never uploads them anywhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PoweredByStrava()
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(isOnboarding ? AnyView(HomeBackdrop()) : AnyView(Color.clear))
        .sheet(isPresented: $showSetup) {
            SettingsView(focusOnStrava: true)
                .environment(model)
                .environment(settings)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.brand).frame(width: 96, height: 96).blur(radius: 24).opacity(0.7)
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Palette.brand, in: .rect(cornerRadius: 26))
            }
            Wordmark(size: 34)
            Text("Your year in motion — turned into a story worth sharing.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            feature("sparkles.rectangle.stack.fill", "An animated recap", "Totals, progress, PBs and the days you'll remember — for a year, quarter, month, week or any dates.", Palette.ember)
            feature("globe.europe.africa.fill", "Distance, made tangible", "Paris → New York, the Silk Road, laps of a track: see how far you really went.", Palette.sky)
            feature("person.2.fill", "Your crew", "Who you trained with most, and how far you went together.", Palette.mint)
            feature("square.and.arrow.up.fill", "Share it", "A story card, a long image, an animated GIF or a video.", Palette.violet)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if model.isStravaConfigured {
                Button {
                    Task {
                        isConnecting = true
                        await model.connect(using: webAuthenticationSession)
                        isConnecting = false
                        if model.isConnected, isOnboarding { dismiss() }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isConnecting { ProgressView().tint(.white) }
                        Text("Connect with Strava").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Palette.stravaOrange, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isConnecting)
                .accessibilityIdentifier("connect-strava")
                if model.canUseStravaApp {
                    Button("Approve in the Strava app instead") { model.connectWithStravaApp() }
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Button {
                    showSetup = true
                } label: {
                    Label("Set up your Strava API app", systemImage: "key.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Text("Strava needs a Client ID and secret from strava.com/settings/api (takes two minutes).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let error = model.connectError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.coral)
                    .multilineTextAlignment(.leading)
            }
            Button {
                model.setDemoMode(true)
                settings.hasOnboarded = true
                if isOnboarding { dismiss() }
            } label: {
                Label("Explore with demo data", systemImage: "wand.and.stars")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityIdentifier("try-demo")
        }
    }
}
