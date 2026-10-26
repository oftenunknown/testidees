import StoreKit
import SwiftUI

/// Snag Premium: AI gifting persona, unlimited watches, faster checks.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var reason: String?

    var body: some View {
        SubscriptionStoreView(productIDs: EntitlementManager.productIDs) {
            VStack(spacing: 18) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.bounce, options: .nonRepeating)
                    .padding(.top, 24)
                Text("Snag Premium")
                    .font(.largeTitle.weight(.bold))
                if let reason {
                    Text(reason)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                VStack(alignment: .leading, spacing: 12) {
                    perk("wand.and.stars", "AI gift ideas", "Apple Intelligence blends their interests with your personality, using Apple's larger Private Cloud Compute model.")
                    perk("person.crop.square.badge.camera", "Persona from your photos & Instagram", "Learn your style from screenshots or your Instagram data export, plus an AI portrait and avatar.")
                    perk("bell.badge.fill", "Unlimited price watches", "Watch as many items as you like, checked more often.")
                    perk("person.2.fill", "Unlimited people", "Ideas for everyone you buy for, with occasion reminders.")
                }
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .background { AmbientBackground(tint: .orange) }
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                await model.entitlements.refresh()
                dismiss()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if model.entitlements.isTestEnvironment {
                Toggle("Tester unlock (TestFlight only)", isOn: Binding(get: { settings.testerPremium }, set: { settings.testerPremium = $0 }))
                    .font(.footnote)
                    .padding(12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal)
            }
        }
    }

    private func perk(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Presents the paywall from whichever level of the hierarchy is frontmost.
/// Apply to the root and to the root of any sheet that can ask for Premium.
struct PaywallPresenter: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { model.paywallReason != nil }, set: { if !$0 { model.paywallReason = nil } })) {
            PaywallView(reason: model.paywallReason)
        }
    }
}
