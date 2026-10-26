import SwiftUI
import WebKit
import SnagKit

/// In-app browser with a shopping agent. You shop and pay as normal; the
/// agent watches for the promo-code box, tries your codes, keeps the best one,
/// fills discount-scheme logins on their own sites, and saves codes you copy.
struct CheckoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var request: CheckoutRequest

    @State private var agent = CheckoutAgent()

    var body: some View {
        NavigationStack {
            WebView(agent: agent, url: request.url)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) { agentPanel }
                .navigationTitle(agent.pageTitle.isEmpty ? request.merchant : agent.pageTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Back", systemImage: "chevron.backward") { agent.webView?.goBack() }
                            .disabled(!agent.canGoBack)
                        Button("Open in Safari", systemImage: "safari") {
                            if let url = agent.webView?.url { openURL(url) }
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if agent.isLoading {
                        ProgressView(value: agent.progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.teal)
                    }
                }
        }
        .onAppear {
            agent.configure(model: model, settings: settings, request: request)
        }
    }

    private var agentPanel: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: agent.statusSymbol)
                        .font(.title3)
                        .foregroundStyle(Theme.teal)
                        .symbolEffect(.pulse, isActive: agent.isWorking)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.status).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if let detail = agent.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !agent.actions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(agent.actions) { action in
                                if action.prominent {
                                    Button(action.title, systemImage: action.symbol) { agent.perform(action) }
                                        .buttonStyle(.glassProminent)
                                } else {
                                    Button(action.title, systemImage: action.symbol) { agent.perform(action) }
                                        .buttonStyle(.glass)
                                }
                            }
                        }
                        .controlSize(.small)
                        .disabled(agent.isWorking)
                    }
                }
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(.spring(duration: 0.35), value: agent.status)
    }
}

/// The agent's brain and the WKWebView's delegate.
@Observable
final class CheckoutAgent: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    struct Action: Identifiable, Equatable {
        enum Kind: Equatable { case tryCodes, fillLogin(String), saveCode(String), findSchemeCode(URL) }
        var id: String
        var title: String
        var symbol: String
        var prominent: Bool
        var kind: Kind
    }

    var status = "Shopping assistant ready"
    var detail: String?
    var statusSymbol = "wand.and.sparkles"
    var isWorking = false
    var isLoading = false
    var progress = 0.0
    var pageTitle = ""
    var canGoBack = false
    var actions: [Action] = []

    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var request: CheckoutRequest?
    @ObservationIgnored private var triedOnHost: Set<String> = []
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    func configure(model: AppModel, settings: AppSettings, request: CheckoutRequest) {
        self.model = model
        self.settings = settings
        self.request = request
        if let price = request.expectedPrice {
            detail = "Expected \(price.money(request.currency)) at \(request.merchant)"
        }
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
                let value = web.estimatedProgress
                Task { @MainActor in self?.progress = value }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] web, _ in
                let loading = web.isLoading
                Task { @MainActor in self?.isLoading = loading }
            },
        ]
    }

    private var host: String { webView?.url?.host().map(Offer.normalizedDomain) ?? "" }

    private var codesForHost: [String] {
        guard let model else { return [] }
        let h = host
        let specific = model.savedCodes.filter { code in
            code.isUsable() && (code.merchantDomain.map { h == $0 || h.hasSuffix("." + $0) } ?? false)
        }
        let generic = model.savedCodes.filter { $0.isUsable() && $0.merchantDomain == nil }.prefix(2)
        return (specific.sorted { ($0.lastSaving ?? 0) > ($1.lastSaving ?? 0) } + generic).map(\.code)
    }

    private var schemeForHost: DiscountProgram? {
        DiscountCatalog.standard.programs.first { program in
            guard let h = program.homepage.host().map(Offer.normalizedDomain) else { return false }
            return host == h || host.hasSuffix("." + h)
        }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageTitle = webView.title ?? ""
        canGoBack = webView.canGoBack
        Task { await inspectPage() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Let shops open payment apps (Apple Pay, PayPal, Klarna) normally.
        if let url = navigationAction.request.url, let scheme = url.scheme, !["http", "https", "about", "blob", "data"].contains(scheme) {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "progress":
            if let code = body["code"] as? String { detail = "Trying \(code)…" }
        case "copied":
            if let code = body["code"] as? String {
                let domain = schemeForHost == nil ? host : request?.merchantDomain
                actions.removeAll { if case .saveCode = $0.kind { true } else { false } }
                actions.insert(Action(id: "save-\(code)", title: "Save \(code)", symbol: "square.and.arrow.down", prominent: true, kind: .saveCode(code)), at: 0)
                status = "Copied a code"
                detail = "Save it and Snag will try it at \(domain ?? "checkout") automatically."
                statusSymbol = "doc.on.clipboard"
            }
        default:
            break
        }
    }

    // MARK: Agent

    private func inspectPage() async {
        guard let webView else { return }
        let probe = try? await webView.callAsyncJavaScript(CheckoutScripts.probe, arguments: [:], in: nil, contentWorld: .defaultClient) as? [String: Any]
        let hasCodeBox = probe?["hasCodeBox"] as? Bool ?? false
        let total = probe?["total"] as? Double
        let pageCodes = probe?["codes"] as? [String] ?? []
        var next: [Action] = []

        if let scheme = schemeForHost {
            status = "On \(scheme.name)"
            statusSymbol = "checkmark.shield.fill"
            detail = "Generate a code for \(request?.merchant ?? "your shop"), then copy it — Snag saves it for checkout."
            if KeychainStore.credential(for: scheme.id) != nil {
                next.append(Action(id: "login", title: "Fill my login", symbol: "person.badge.key.fill", prominent: true, kind: .fillLogin(scheme.id)))
            }
            for code in pageCodes.prefix(2) {
                next.append(Action(id: "save-\(code)", title: "Save \(code)", symbol: "square.and.arrow.down", prominent: false, kind: .saveCode(code)))
            }
        } else if hasCodeBox {
            let codes = codesForHost
            statusSymbol = "ticket.fill"
            if let total, let request {
                status = "At checkout · \(total.money(request.currency))"
            } else {
                status = "Found the promo code box"
            }
            if codes.isEmpty {
                detail = "No codes saved for this shop yet."
            } else {
                next.append(Action(id: "try", title: "Try \(codes.count) code\(codes.count == 1 ? "" : "s")", symbol: "wand.and.sparkles", prominent: true, kind: .tryCodes))
                if settings?.autoApplyCodes == true, !triedOnHost.contains(host) {
                    actions = next
                    await tryCodes()
                    return
                }
            }
        } else {
            statusSymbol = "wand.and.sparkles"
            status = "Shopping assistant ready"
            if detail == nil || detail?.hasPrefix("Trying") == true { detail = "Head to the basket — I'll look for the promo box." }
        }

        // Point to schemes that might have a code for this shop.
        if schemeForHost == nil, let settings, let merchant = request?.merchant {
            let programs = settings.eligibilities.flatMap { DiscountCatalog.standard.programs(for: $0, in: settings.region) }
            for program in Set(programs).sorted(by: { $0.name < $1.name }).prefix(2) {
                if let url = program.lookupURL(for: merchant) {
                    next.append(Action(id: "scheme-\(program.id)", title: "\(program.name) code", symbol: "magnifyingglass", prominent: false, kind: .findSchemeCode(url)))
                }
            }
        }
        actions = next
    }

    func perform(_ action: Action) {
        switch action.kind {
        case .tryCodes:
            Task { await tryCodes() }
        case .fillLogin(let programID):
            guard let credential = KeychainStore.credential(for: programID) else { return }
            // Only fill on the scheme's own domain.
            guard host == Offer.normalizedDomain(credential.domain) || host.hasSuffix("." + Offer.normalizedDomain(credential.domain)) else {
                status = "Login not filled"
                detail = "This page isn't on \(credential.domain)."
                return
            }
            Task {
                _ = try? await webView?.callAsyncJavaScript(CheckoutScripts.fillLogin(user: credential.username, password: credential.password), arguments: [:], in: nil, contentWorld: .defaultClient)
                status = "Login filled"
                detail = "Check it and tap sign in."
            }
        case .saveCode(let code):
            let domain = schemeForHost == nil ? host : request?.merchantDomain
            model?.saveCode(code, domain: domain, source: .captured)
            actions.removeAll { $0.id == action.id }
            status = "Saved \(code)"
            detail = "Snag will try it at \(domain ?? "checkout")."
            statusSymbol = "checkmark.circle.fill"
        case .findSchemeCode(let url):
            webView?.load(URLRequest(url: url))
        }
    }

    private func tryCodes() async {
        guard let webView, let model else { return }
        let codes = codesForHost
        guard !codes.isEmpty else { return }
        triedOnHost.insert(host)
        isWorking = true
        status = "Trying your codes…"
        statusSymbol = "wand.and.sparkles"
        defer { isWorking = false }

        let result = try? await webView.callAsyncJavaScript(CheckoutScripts.tryCodes(codes), arguments: [:], in: nil, contentWorld: .defaultClient) as? [String: Any]
        guard let result, result["found"] as? Bool == true else {
            status = "Couldn't find the promo box"
            detail = "Open the basket or checkout page and try again."
            return
        }
        let results = result["results"] as? [[String: Any]] ?? []
        let currency = request?.currency ?? model.settings.currency
        if let winner = result["winner"] as? [String: Any], let code = winner["code"] as? String, let saving = winner["saving"] as? Double {
            model.saveCode(code, domain: host, source: .captured, saving: saving)
            status = "Applied \(code) — saved \(saving.money(currency))"
            detail = "Best of \(results.count) code\(results.count == 1 ? "" : "s") tried."
            statusSymbol = "checkmark.seal.fill"
        } else {
            status = "None of your codes worked here"
            detail = "Check a discount scheme below for a fresh one."
            statusSymbol = "xmark.seal"
            for r in results {
                if let code = r["code"] as? String, let i = model.savedCodes.firstIndex(where: { $0.code == code }) {
                    model.savedCodes[i].failures += 1
                }
            }
        }
        actions.removeAll { $0.kind == .tryCodes }
    }
}

/// WKWebView with a persistent store so scheme sign-ins stick.
private struct WebView: UIViewRepresentable {
    var agent: CheckoutAgent
    var url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let controller = WKUserContentController()
        controller.add(agent, contentWorld: .defaultClient, name: "snag")
        controller.addUserScript(WKUserScript(source: CheckoutScripts.bootstrap, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = agent
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        agent.attach(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: ()) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }
}

/// Presents the checkout agent from the frontmost level (root or a sheet).
struct CheckoutPresenter: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content.sheet(item: $model.checkout) { request in
            CheckoutView(request: request)
        }
    }
}
