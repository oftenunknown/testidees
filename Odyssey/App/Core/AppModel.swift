import AuthenticationServices
import Foundation
import Observation
import SwiftUI
import UIKit
import OdysseyKit

enum AppTab: String, Hashable, CaseIterable {
    case recap, insights, crew
}

/// What the current window looks like, so views can adapt to iPhone Duo's
/// outer display (vertical side bar), inner display (regular width), the
/// hinge, and big iPhones in landscape.
struct LayoutContext: Equatable {
    enum Hinge: Equatable {
        case none, closed, partiallyOpen, fullyOpen
    }

    var isWide = false
    /// Edge the system put the vertical bar on (Duo outer display), if any.
    var verticalBarEdge: HorizontalEdge?
    var hinge: Hinge = .none
    var hingeAngleDegrees: Double?

    var hasSideBar: Bool { verticalBarEdge != nil }
    /// Half-folded and propped up: split content across the fold.
    var isTabletop: Bool { hinge == .partiallyOpen }
}

enum SyncState: Equatable {
    case idle
    case syncing(String)
    case enriching(done: Int, total: Int)
    case rateLimited(until: Date)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .syncing, .enriching: true
        default: false
        }
    }
}

/// App-wide state. Navigation lives here (not in views) so folding or
/// unfolding iPhone Duo keeps you on the same story page and selection.
@Observable
final class AppModel {
    let settings: AppSettings
    let launch: LaunchOptions

    // MARK: Data
    private(set) var library: ActivityLibrary
    private(set) var activities: [Activity] = []
    private(set) var tokens: StravaTokens?
    var crewTags: [Int64: [String]] { didSet { LocalStore.save(crewTags, named: "crew-tags"); scheduleRecompute() } }
    var hiddenCompanions: Set<String> { didSet { LocalStore.save(hiddenCompanions, named: "hidden-companions"); scheduleRecompute() } }
    var rateLimit: RateLimitStatus?

    // MARK: Selection
    var range: RecapRange { didSet { if range != oldValue { scheduleRecompute(); Task { await syncIfNeededForRange() } } } }
    var filter: SportFilter = .all { didSet { if filter != oldValue { scheduleRecompute() } } }
    private(set) var recap: Recap?
    private(set) var isComputing = false

    // MARK: Navigation
    var selectedTab: AppTab = .recap
    var isStoryPresented = false
    var storyIndex = 0
    var isShareStudioPresented = false
    var isSettingsPresented = false
    var layout = LayoutContext()

    // MARK: Status
    var syncState: SyncState = .idle
    var connectError: String?
    var toast: String?

    @ObservationIgnored private var session: StravaSession?
    @ObservationIgnored private var pendingOAuthState: String?
    @ObservationIgnored private var computeTask: Task<Void, Never>?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var demoLibrary: ActivityLibrary?
    @ObservationIgnored private var started = false

    init(settings: AppSettings, launch: LaunchOptions) {
        self.settings = settings
        self.launch = launch
        let today = (launch.isUITesting || settings.demoMode) ? DemoData.anchor : LocalDay.today()
        range = RecapRange(.year(today.year), firstWeekday: settings.firstWeekday)
        library = launch.isUITesting ? ActivityLibrary() : (LocalStore.load(ActivityLibrary.self, named: "library") ?? ActivityLibrary())
        crewTags = launch.isUITesting ? [:] : (LocalStore.load([Int64: [String]].self, named: "crew-tags") ?? [:])
        hiddenCompanions = launch.isUITesting ? [] : (LocalStore.load(Set<String>.self, named: "hidden-companions") ?? [])
        tokens = launch.isUITesting ? nil : Vault.tokens
        if let tag = launch.tab { selectedTab = tag }
    }

    // MARK: - Derived

    var today: LocalDay { (launch.isUITesting || settings.demoMode) ? DemoData.anchor : LocalDay.today() }
    var isConnected: Bool { tokens != nil }
    var hasData: Bool { settings.demoMode || isConnected }
    var athlete: Athlete? { settings.demoMode ? DemoData.athlete : (library.athlete ?? tokens?.athlete) }

    var units: Units {
        Units(settings.unitOverride ?? ((athlete?.prefersImperial ?? false) ? .imperial : .metric))
    }

    var narrator: Narrator { Narrator(units: units) }
    var storyPages: [StoryPage] { recap.map { StoryScript.pages(for: $0) } ?? [.intro] }

    /// Sport families with activities in the selected range (for the filter chips).
    var availableFamilies: [SportFamily] {
        let days = range.effectiveDays(today: today)
        var counts: [SportFamily: Int] = [:]
        for a in activities where days.contains(a.day) { counts[a.sport.family, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    var isAutoAdvanceEnabled: Bool { settings.autoAdvance && !launch.isUITesting }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        if let tokens { makeSession(tokens) }
        await reloadData()
        if launch.openStory {
            storyIndex = launch.storyPage ?? 0
            isStoryPresented = true
        }
        await sync()
    }

    /// Switches between demo data and your synced library.
    func reloadData() async {
        if settings.demoMode {
            if demoLibrary == nil {
                demoLibrary = await Task.detached(priority: .userInitiated) { DemoData.library() }.value
            }
            activities = demoLibrary?.activities ?? []
        } else {
            activities = library.activities
        }
        range.firstWeekday = settings.firstWeekday
        scheduleRecompute()
    }

    func setDemoMode(_ on: Bool) {
        guard settings.demoMode != on else { return }
        settings.demoMode = on
        range = RecapRange(.year(today.year), firstWeekday: settings.firstWeekday)
        filter = .all
        storyIndex = 0
        Task { await reloadData() }
    }

    // MARK: - Recap

    var recapOptions: RecapOptions {
        RecapOptions(
            today: today,
            firstWeekday: settings.firstWeekday,
            crewTags: crewTags,
            hiddenCompanions: hiddenCompanions,
            athlete: athlete,
            previousAvailable: previousPeriodAvailable,
            trimRouteEndsMeters: settings.trimRouteEnds ? 300 : 0,
            units: units.system
        )
    }

    private var previousPeriodAvailable: Bool {
        if settings.demoMode { return true }
        let previous = range.previousComparable(today: today)
        return library.missing(TimeSpan.covering(previous)).isEmpty
    }

    func scheduleRecompute() {
        computeTask?.cancel()
        let activities = activities, range = range, filter = filter, options = recapOptions
        isComputing = true
        computeTask = Task {
            let built = await Task.detached(priority: .userInitiated) {
                RecapBuilder.build(from: activities, range: range, filter: filter, options: options)
            }.value
            guard !Task.isCancelled else { return }
            recap = built
            isComputing = false
            if storyIndex >= storyPages.count { storyIndex = max(0, storyPages.count - 1) }
        }
    }

    func playStory(from page: Int = 0) {
        storyIndex = min(page, max(0, storyPages.count - 1))
        isStoryPresented = true
    }

    func activity(_ id: Int64) -> Activity? {
        activities.first { $0.id == id }
    }

    // MARK: - Crew

    func setTags(_ names: [String], for activityID: Int64) {
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        crewTags[activityID] = cleaned
    }

    func clearTags(for activityID: Int64) {
        crewTags[activityID] = nil
    }

    func hideCompanion(_ name: String) {
        hiddenCompanions.insert(name.lowercased())
    }

    // MARK: - Strava connection

    private func makeExchanger() -> (any TokenExchanger)? {
        if let server = settings.tokenServerURL { return ServerTokenExchanger(baseURL: server) }
        let id = settings.effectiveClientID
        guard !id.isEmpty, let secret = Vault.clientSecret else { return nil }
        return DirectTokenExchanger(clientID: id, clientSecret: secret)
    }

    var isStravaConfigured: Bool { settings.stravaConfig.isValid && makeExchanger() != nil }

    private func makeSession(_ tokens: StravaTokens) {
        guard let exchanger = makeExchanger() else { return }
        session = StravaSession(tokens: tokens, exchanger: exchanger) { [weak self] fresh in
            Vault.save(fresh)
            Task { @MainActor in self?.tokens = fresh }
        }
    }

    /// Signs in through Strava's web page in a secure browser sheet.
    func connect(using webAuthentication: WebAuthenticationSession) async {
        connectError = nil
        let config = settings.stravaConfig
        guard config.isValid, isStravaConfigured else {
            connectError = StravaError.notConfigured.localizedDescription
            return
        }
        let state = UUID().uuidString
        pendingOAuthState = state
        do {
            let callback = try await webAuthentication.authenticate(
                using: config.authorizeURL(state: state),
                callbackURLScheme: config.callbackScheme,
                preferredBrowserSession: .shared
            )
            try await completeConnection(callback: callback)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            pendingOAuthState = nil
        } catch {
            connectError = error.localizedDescription
        }
    }

    var canUseStravaApp: Bool {
        guard let url = URL(string: "strava://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Hands off to the Strava app's own approval screen; it calls back via `odysseyrecap://`.
    func connectWithStravaApp() {
        connectError = nil
        let config = settings.stravaConfig
        guard config.isValid, isStravaConfigured else {
            connectError = StravaError.notConfigured.localizedDescription
            return
        }
        let state = UUID().uuidString
        pendingOAuthState = state
        UIApplication.shared.open(config.authorizeURL(state: state, viaStravaApp: true))
    }

    func handle(url: URL) {
        guard url.scheme?.lowercased() == settings.stravaConfig.callbackScheme else { return }
        Task {
            do {
                try await completeConnection(callback: url)
            } catch {
                connectError = error.localizedDescription
            }
        }
    }

    private func completeConnection(callback: URL) async throws {
        guard let exchanger = makeExchanger() else { throw StravaError.notConfigured }
        let (code, scopes) = try settings.stravaConfig.parseCallback(callback, expectedState: pendingOAuthState)
        pendingOAuthState = nil
        let fresh = try await exchanger.exchange(code: code, scopes: scopes)
        Vault.save(fresh)
        tokens = fresh
        if let athlete = fresh.athlete { library.athlete = athlete }
        makeSession(fresh)
        settings.hasOnboarded = true
        if settings.demoMode {
            settings.demoMode = false
            range = RecapRange(.year(today.year), firstWeekday: settings.firstWeekday)
        }
        await reloadData()
        showToast("Connected to Strava")
        await sync(force: true)
    }

    func disconnect() async {
        if let session { try? await session.revoke() }
        Vault.deleteTokens()
        tokens = nil
        session = nil
        library.removeAll()
        LocalStore.delete(named: "library")
        syncState = .idle
        await reloadData()
    }

    // MARK: - Sync

    func syncIfStale() async {
        guard !settings.demoMode, isConnected else { return }
        if let last = library.lastSync, last > Date(timeIntervalSinceNow: -10 * 60) { return }
        await sync()
    }

    /// Ranges this view needs: the selected one and the period before it (for comparisons).
    private var wantedRanges: [DayRange] {
        [range.effectiveDays(today: today), range.previousComparable(today: today)]
    }

    /// Whether any wanted range has never been fetched (ignores the routine refresh of recent days).
    private var hasGaps: Bool {
        let now = Date()
        return wantedRanges.contains { days in
            let span = TimeSpan.covering(days)
            return !library.missing(TimeSpan(start: span.start, end: min(span.end, now))).isEmpty
        }
    }

    private func syncIfNeededForRange() async {
        guard !settings.demoMode, isConnected, !syncState.isBusy, hasGaps else { return }
        await sync()
    }

    /// Fetches whatever the selected range (and the period before it) still
    /// needs, then spends a small budget on activity details for PBs and crew.
    func sync(force: Bool = false) async {
        guard !settings.demoMode, let session, !syncState.isBusy else { return }
        if case .rateLimited(let until) = syncState, until > Date(), !force { return }
        let client = StravaClient(
            token: { try await session.accessToken() },
            observeRateLimit: { [weak self] status in Task { @MainActor in self?.rateLimit = status } }
        )
        do {
            if force || library.athlete == nil || library.lastSync.map({ $0 < Date(timeIntervalSinceNow: -86_400) }) ?? true {
                syncState = .syncing("Reading your profile…")
                library.athlete = try await client.athlete()
            }
            let plan = library.syncPlan(for: wantedRanges, now: Date())
            for (i, span) in plan.enumerated() {
                syncState = .syncing(plan.count > 1 ? "Fetching activities (\(i + 1)/\(plan.count))…" : "Fetching activities…")
                let fetched = try await client.allActivities(after: span.start, before: span.end)
                library.merge(fetched, covering: span)
                activities = library.activities
                scheduleRecompute()
            }
            library.lastSync = Date()
            persistLibrary()
            try await enrichDetails(client: client)
            syncState = .idle
            // The range may have changed while we were busy.
            if hasGaps { await sync() }
        } catch StravaError.rateLimited(let status) {
            let until = status?.resumeDate(needing: 10, at: Date()) ?? RateLimitStatus.nextShortWindow(after: Date())
            syncState = .rateLimited(until: until)
            publishLibrary()
            scheduleResume(at: until)
        } catch StravaError.unauthorized {
            syncState = .failed("Strava signed you out. Connect again in Settings.")
            Vault.deleteTokens()
            tokens = nil
            self.session = nil
        } catch {
            syncState = .failed(error.localizedDescription)
            publishLibrary()
        }
    }

    /// Shows and saves whatever has been fetched so far.
    private func publishLibrary() {
        activities = library.activities
        scheduleRecompute()
        persistLibrary()
    }

    private func enrichDetails(client: StravaClient) async throws {
        let inRange = library.activities(in: range.effectiveDays(today: today))
        let remaining = rateLimit.map { min($0.shortRemaining(at: Date()), $0.dailyRemaining(at: Date())) - 10 } ?? 60
        let ids = DetailPlanner.candidates(in: inRange, limit: max(0, min(settings.detailBudget, remaining)))
        guard !ids.isEmpty else { return }
        for (i, id) in ids.enumerated() {
            syncState = .enriching(done: i, total: ids.count)
            do {
                let (_, details) = try await client.detailedActivity(id: id)
                library.attach(details, to: id)
            } catch StravaError.notFound, StravaError.forbidden {
                // Deleted or hidden since the list was fetched: remember, don't retry forever.
                library.attach(ActivityDetails(), to: id)
            }
            if i % 8 == 7 {
                activities = library.activities
                scheduleRecompute()
            }
            if let limit = rateLimit, limit.shortRemaining(at: Date()) < 6 {
                throw StravaError.rateLimited(limit)
            }
        }
        publishLibrary()
    }

    private func scheduleResume(at date: Date) {
        resumeTask?.cancel()
        resumeTask = Task {
            try? await Task.sleep(for: .seconds(max(5, date.timeIntervalSinceNow + 5)))
            guard !Task.isCancelled else { return }
            syncState = .idle
            await sync()
        }
    }

    private func persistLibrary() {
        let snapshot = library
        Task.detached(priority: .utility) { LocalStore.save(snapshot, named: "library") }
    }

    func clearCache() async {
        library.removeAll()
        LocalStore.delete(named: "library")
        await reloadData()
        await sync(force: true)
    }

    // MARK: - Feedback

    func showToast(_ text: String) {
        withAnimation(.spring(duration: 0.4)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.3)) { if toast == text { toast = nil } }
        }
    }
}
