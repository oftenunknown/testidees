import PhotosUI
import SwiftData
import SwiftUI
import SnagKit

/// Point the camera at a barcode or a shelf tag. That's it — the barcode is
/// looked up and the shelf price is read automatically, and the verdict
/// appears without pressing anything.
struct ScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var session = ScanSession()
    @State private var capture = CameraScanner.CaptureTrigger()
    @State private var showResult = false
    @State private var showManualEntry = false
    @State private var manualQuery = ""
    @State private var manualPrice = ""
    @State private var photoItem: PhotosPickerItem?
    @Namespace private var glass

    private var isActive: Bool { model.selectedTab == .scan }
    private var useSplit: Bool { model.layout.isWide || model.layout.isTabletop }

    var body: some View {
        NavigationStack {
            Group {
                if useSplit {
                    FoldAwareSplit(ratio: 0.5) {
                        cameraPane
                    } secondary: {
                        NavigationStack { resultPane }
                    }
                } else {
                    cameraPane
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .modifier(VerticalBarReader())
            .sideBarPriority(toolbarItems: true)
        }
        .sheet(isPresented: $showResult, onDismiss: { session.reset() }) {
            NavigationStack { resultPane }
                .modifier(CheckoutPresenter())
                .modifier(PaywallPresenter())
                .presentationDetents([.fraction(0.55), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.55)))
                .presentationDragIndicator(.visible)
        }
        .onChange(of: session.phase) { _, phase in
            let wantsSheet = phase != .idle && !useSplit
            if wantsSheet != showResult { showResult = wantsSheet }
        }
        .onChange(of: useSplit) { _, split in
            // Unfolding mid-scan moves the result from the sheet into the side pane.
            if split { showResult = false } else if session.phase != .idle { showResult = true }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    session.identify(image: image, model: model)
                }
                photoItem = nil
            }
        }
        .alert("Look something up", isPresented: $showManualEntry) {
            TextField("Barcode or product name", text: $manualQuery)
            TextField("Price you see (optional)", text: $manualPrice)
                .keyboardType(.decimalPad)
            Button("Check") { runManualEntry() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type the number under the barcode, or a product name.")
        }
        .sensoryFeedback(.success, trigger: session.result?.product.id)
    }

    // MARK: - Camera

    private var cameraPane: some View {
        ZStack {
            if CameraScanner.isAvailable {
                CameraScanner(
                    isActive: isActive,
                    onBarcode: { code, isUPCE in session.lookup(code: code, isUPCE: isUPCE, model: model, context: context) },
                    onText: { session.observe(text: $0, currency: model.settings.currency) },
                    capture: capture
                )
                .ignoresSafeArea()
            } else {
                CameraUnavailableView(onSample: { code, price in
                    session.manualPrice = price
                    session.lookup(code: code, model: model, context: context)
                }, onType: { showManualEntry = true })
                .ambientBackground()
            }

            VStack {
                statusChips
                Spacer()
                if CameraScanner.isAvailable { captureControls }
            }
            .padding()
        }
    }

    /// Live status that morphs as the camera understands more.
    private var statusChips: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Label(statusText, systemImage: statusSymbol)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("status", in: glass)
                    .contentTransition(.symbolEffect(.replace))

                if let price = session.shelfPrice {
                    Button {
                        manualPrice = String(format: "%.2f", price)
                        manualQuery = session.scannedCode ?? ""
                        showManualEntry = true
                    } label: {
                        Label(price.money(model.settings.currency), systemImage: "tag.fill")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(Theme.teal.opacity(0.5)).interactive(), in: .capsule)
                    .glassEffectID("price", in: glass)
                    .accessibilityLabel("Shelf price \(price.money(model.settings.currency)). Tap to edit.")
                }
            }
        }
        .animation(.spring(duration: 0.45), value: session.shelfPrice)
        .animation(.spring(duration: 0.45), value: statusText)
    }

    private var statusText: String {
        switch session.phase {
        case .idle: session.shelfPrice == nil ? "Point at a barcode or price tag" : "Got the price — now the barcode"
        case .looking(let message): message
        case .found: session.result?.product.brand ?? "Found it"
        case .choosing: "Pick the right one"
        case .failed: "Try again"
        }
    }

    private var statusSymbol: String {
        switch session.phase {
        case .idle: "barcode.viewfinder"
        case .looking: "magnifyingglass"
        case .found: "checkmark.circle.fill"
        case .choosing: "list.bullet"
        case .failed: "exclamationmark.circle"
        }
    }

    private var captureControls: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: 18) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Identify from a photo")

                Button {
                    Task {
                        if let image = await capture.photo() { session.identify(image: image, model: model) }
                    }
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.title)
                        .frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.teal.opacity(0.6)).interactive(), in: .circle)
                .accessibilityLabel("No barcode? Identify what's in view")

                Button { showManualEntry = true } label: {
                    Image(systemName: "keyboard")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Type a barcode or name")
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Result

    @ViewBuilder
    private var resultPane: some View {
        switch session.phase {
        case .idle:
            ScanTipsView(onType: { showManualEntry = true })
        case .looking(let message):
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(message).font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyStateView(symbol: "questionmark.app.dashed", title: "No luck", message: message, actionTitle: "Type it in") { showManualEntry = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .choosing:
            List(session.candidates, id: \.product.id) { candidate in
                Button { session.choose(candidate, model: model) } label: {
                    HStack(spacing: 12) {
                        ProductThumbnail(url: candidate.product.imageURLs.first, size: 48)
                        VStack(alignment: .leading) {
                            Text(candidate.product.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            if let best = candidate.offers.first {
                                Text("from \(best.totalPrice.money(best.currency))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Which one?")
        case .found:
            if let result = session.result {
                PriceCheckView(
                    product: result.product,
                    offers: result.offers,
                    history: session.history,
                    degradedSources: result.degradedSources,
                    shelfPrice: Binding(get: { session.shelfPrice }, set: { session.manualPrice = $0 })
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Type", systemImage: "keyboard") { showManualEntry = true }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Photo", systemImage: "photo")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Start over", systemImage: "arrow.counterclockwise") {
                showResult = false
                session.reset()
            }
            .disabled(session.phase == .idle)
        }
    }

    private func runManualEntry() {
        let price = Double(manualPrice.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." })
        if let price { session.manualPrice = price }
        let query = manualQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty, query != session.scannedCode {
            session.search(query: query, model: model)
        }
        manualQuery = ""
        manualPrice = ""
    }
}

/// Shown where there's no camera (Simulator, Mac, permission denied).
private struct CameraUnavailableView: View {
    @Environment(AppSettings.self) private var settings
    var onSample: (String, Double) -> Void
    var onType: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundStyle(Theme.brandGradient)
            Text("Camera isn't available here")
                .font(.title3.weight(.semibold))
            Text("Type a barcode or product name instead, or try a sample.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Type a barcode or name", systemImage: "keyboard", action: onType)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            VStack(spacing: 10) {
                Text("Samples").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(DemoData.sampleScans(currency: settings.currency), id: \.code) { sample in
                            Button(sample.title) { onSample(sample.code, sample.shelfPrice) }
                                .buttonStyle(.glass)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Idle state for the result pane on wide screens.
private struct ScanTipsView: View {
    var onType: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("How it works").font(.title2.weight(.bold))
                tip("barcode.viewfinder", "Point at the barcode", "We identify the product and check prices across shops instantly.")
                tip("tag.fill", "Include the shelf tag", "We read the price you're being charged and tell you if it's a good deal.")
                tip("camera.viewfinder", "No barcode?", "Tap the shutter and we'll recognise the product from its packaging.")
                tip("ticket.fill", "Your perks apply", "Student, NHS and other discounts are factored into every price.")
                Button("Type a barcode instead", systemImage: "keyboard", action: onType)
                    .buttonStyle(.glass)
            }
            .padding(24)
        }
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.brandGradient)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
