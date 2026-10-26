import SwiftUI
import SnagKit

/// Three quick steps: where you shop, which perks you have, notifications.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @Namespace private var glass

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcome.tag(0)
                perks.tag(1)
                alerts.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.spring(duration: 0.5), value: step)

            Button {
                if step < 2 { withAnimation { step += 1 } } else { finish() }
            } label: {
                Text(step < 2 ? "Continue" : "Start snagging")
                    .font(.headline)
                    .frame(maxWidth: 360)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding()
        }
        .background { AmbientBackground() }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "tag.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.brandGradient)
                .frame(width: 128, height: 128)
                .glassEffect(.regular, in: .circle)
            Text("Never overpay again").font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text("Scan anything in a shop to see if it's a good price, watch things you want, and find gifts that feel like they came from you.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Picker("I shop in", selection: Binding(get: { settings.region }, set: { settings.region = $0 })) {
                ForEach(Region.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
            Spacer()
        }
        .padding()
    }

    private var perks: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Any of these you?").font(.largeTitle.weight(.bold))
            Text("We'll fold your discounts into every price and try your codes at checkout.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 10) {
                FlowLayout(spacing: 10) {
                    ForEach(Eligibility.relevant(in: settings.region)) { e in
                        GlassChip(title: e.title, symbol: e.symbol, isOn: settings.eligibilities.contains(e)) {
                            withAnimation(.snappy) {
                                if settings.eligibilities.contains(e) { settings.eligibilities.remove(e) } else { settings.eligibilities.insert(e) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 520)
            Spacer()
        }
        .padding()
    }

    private var alerts: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.coral)
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.5)))
                .frame(width: 128, height: 128)
                .glassEffect(.regular, in: .circle)
            Text("Get told when prices drop").font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text("Watch anything and pick a target price or a percentage. We'll keep checking so you don't have to.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Allow notifications", systemImage: "bell") {
                Task { await Notifier.requestAuthorization() }
            }
            .buttonStyle(.glass)
            Spacer()
        }
        .padding()
    }

    private func finish() {
        settings.hasOnboarded = true
        dismiss()
    }
}
