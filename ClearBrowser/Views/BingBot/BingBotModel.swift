import Foundation
import Combine
import UserNotifications

enum BingRunMode: String, CaseIterable, Hashable { case auto = "Auto", manual = "Manual" }
enum BingRunStatus: String { case idle = "Idle", running = "Running", paused = "Paused", completed = "Completed", exhausted = "Exhausted", error = "Error" }

struct SearchState {
    var mode: BingRunMode = .auto
    var status: BingRunStatus = .idle
    var currentIndex = 0
    var totalQueries = 0
    var dailyTarget = 20
    var completedToday = 0
    var countdownSeconds = 0
    var initialDelay = 0
    var isNavigating = false
    var activeQuery: String?
    var lastError: String?
}

@MainActor
final class BingBotModel: ObservableObject {
    @Published private(set) var state = SearchState()
    @Published private(set) var settings = BingSettings()
    @Published private(set) var queries: [String] = []
    @Published var input = QueryInputState()
    @Published var toast: String?
    @Published var error: String?
    @Published var completionSerial = 0
    @Published private(set) var loadingLibraryFailed = false
    private let storage: BingStorage
    private var queue: [String] = []
    private var pendingToken: UUID?
    private var timer: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    // Browser operations are injected, making the engine testable without network traffic.
    var navigate: ((URL, UUID) -> Void)?
    var stopBrowser: (() -> Void)?

    init(storage: BingStorage = BingStorage()) {
        self.storage = storage
        do { settings = try storage.loadSettings() } catch { self.error = "Saved preferences could not be read." }
        do { queries = try storage.loadLibrary().queries }
        catch { loadingLibraryFailed = true; self.error = "Saved queries could not be read. Import a backup or explicitly reset BingBot data." }
        input.parsingMode = settings.defaultParsingMode
        queue = settings.frozenQueue
        state.currentIndex = settings.currentIndex
        state.totalQueries = queue.count
        state.countdownSeconds = settings.remainingDelay
        state.initialDelay = settings.remainingDelay
        refreshDay()
        state.status = state.completedToday >= settings.dailyTarget ? .completed : queue.isEmpty ? .idle : .paused
    }
    var progress: Double { min(1, Double(state.completedToday) / Double(settings.dailyTarget)) }
    var queriesRemaining: Int { max(0, queue.count - state.currentIndex) }
    var unusedCount: Int {
        let used = Set(settings.usedQueryKeys)
        return queries.filter { !used.contains(BingQueries.key($0)) }.count
    }
    func refreshDay() {
        let today = BingQueries.localDate()
        if settings.progressDate != today {
            invalidateNavigation()
            settings.progressDate = today; settings.completedToday = 0
            settings.usedQueryKeys = []; queue = []; state.currentIndex = 0; state.totalQueries = 0
            state.countdownSeconds = 0; state.status = .idle
            persistProgress()
        }
        state.completedToday = settings.completedToday
        state.dailyTarget = settings.dailyTarget
    }
    func showToast(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }; self?.toast = nil
        }
    }
    func updateInput(text: String? = nil, mode: BingParsingMode? = nil) {
        if let text { input.draftText = text }
        if let mode { input.parsingMode = mode }
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            self.input = BingQueries.preview(self.input.draftText, mode: self.input.parsingMode, saved: self.queries)
        }
    }
    func clearInput() { previewTask?.cancel(); input = QueryInputState(parsingMode: input.parsingMode) }
    func addInput() {
        previewTask?.cancel()
        input = BingQueries.preview(input.draftText, mode: input.parsingMode, saved: queries)
        guard input.isValid else { return }
        let additions = input.previewQueries
        guard !additions.isEmpty else { showToast("No new queries to add."); return }
        guard queries.count + additions.count <= 10_000 else { error = "The library supports up to 10,000 queries."; return }
        let skipped = input.duplicateWithinInputCount + input.alreadySavedCount
        do {
            let next = queries + additions
            try storage.saveLibrary(next); queries = next; loadingLibraryFailed = false; clearInput()
            showToast("Added \(additions.count) queries. Skipped \(skipped) duplicates. \(queries.count) queries saved.")
        } catch { self.error = BingDataError.storage.localizedDescription }
    }
    func editQuery(_ original: String, replacement: String) throws {
        let value = BingQueries.normalize(replacement)
        guard !value.isEmpty, value.count <= 500 else { throw BingDataError.invalid }
        guard !queries.contains(where: { $0 != original && BingQueries.key($0) == BingQueries.key(value) }) else { throw BingDataError.duplicate }
        let next = queries.map { $0 == original ? value : $0 }
        try storage.saveLibrary(next); queries = next
        updateInput(); showToast("Query updated. Active runs keep their original queue.")
    }
    @discardableResult
    func addGeneratedQueries(_ generated: [String]) -> Bool {
        let normalized = BingQueries.unique(generated)
        let existing = Set(queries.map(BingQueries.key))
        let additions = normalized.filter { !existing.contains(BingQueries.key($0)) }
        guard !additions.isEmpty else { showToast("No new queries to add."); return false }
        guard additions.allSatisfy({ $0.count <= 500 }), queries.count + additions.count <= 10_000 else {
            error = "Queries must be at most 500 characters, with at most 10,000 saved entries."; return false
        }
        do {
            let next = queries + additions
            try storage.saveLibrary(next); queries = next; updateInput()
            showToast("Added \(additions.count) queries. Skipped \(generated.count - additions.count) duplicates. \(queries.count) queries saved.")
            return true
        } catch { self.error = BingDataError.storage.localizedDescription; return false }
    }
    func deleteQueries(_ selected: Set<String>) {
        do {
            let next = queries.filter { !selected.contains($0) }
            try storage.saveLibrary(next); queries = next; loadingLibraryFailed = false; updateInput()
            showToast("Queries deleted.")
        } catch { self.error = BingDataError.storage.localizedDescription }
    }
    func updateSettings(_ edit: (inout BingSettings) -> Void) {
        var next = settings; edit(&next); next.delayMax = max(next.delayMax, next.delayMin)
        do {
            try next.validate(); try storage.saveSettings(next); settings = next
            state.dailyTarget = settings.dailyTarget
            if state.status == .running && state.completedToday >= settings.dailyTarget { complete() }
        } catch { self.error = "Preferences could not be saved." }
    }
    func setMode(_ mode: BingRunMode) {
        if mode != state.mode, state.status == .running { pause() }
        state.mode = mode
    }
    func start(runAgain: Bool = false) {
        refreshDay()
        guard !state.isNavigating else { return }
        if runAgain { resetProgress() }
        guard state.completedToday < settings.dailyTarget else { state.status = .completed; return }
        if queue.isEmpty || state.currentIndex >= queue.count || state.status == .exhausted {
            let used = Set(settings.usedQueryKeys)
            let source = settings.querySource == "alphanumeric" ? BingQueries.alphanumeric(count: settings.dailyTarget) : queries
            queue = source.filter { !used.contains(BingQueries.key($0)) }
            state.currentIndex = 0
        }
        state.totalQueries = queue.count
        guard !queue.isEmpty else {
            state.status = .exhausted
            showToast("No unused queries. Add more unique queries to continue."); return
        }
        state.status = .running; state.lastError = nil
        persistProgress()
        if state.mode == .auto {
            if state.countdownSeconds > 0 { beginCountdown() } else { executeNext() }
        }
    }
    func nextSearch() {
        if state.status != .running { start() }
        guard state.mode == .manual, state.status == .running, !state.isNavigating else { return }
        executeNext()
    }
    private func executeNext() {
        refreshDay()
        guard state.status == .running, pendingToken == nil else { return }
        guard state.completedToday < settings.dailyTarget else { complete(); return }
        guard state.currentIndex < queue.count else { exhausted(); return }
        guard let navigate else { fail("The browser is not ready. Open Browser and retry."); return }
        let query = queue[state.currentIndex]
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { fail("The search URL could not be created."); return }
        let token = UUID(); pendingToken = token
        state.activeQuery = query; state.isNavigating = true; state.countdownSeconds = 0
        navigate(url, token)
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.pendingToken == token else { return }
            self.stopBrowser?(); self.navigationFailed(token: token)
        }
    }
    func navigationSucceeded(token: UUID) {
        guard token == pendingToken, state.status == .running else { return }
        pendingToken = nil; timeout?.cancel(); timeout = nil; state.isNavigating = false
        guard settings.progressDate == BingQueries.localDate() else { refreshDay(); return }
        if let query = state.activeQuery { settings.usedQueryKeys.append(BingQueries.key(query)) }
        state.currentIndex += 1; settings.completedToday += 1; state.completedToday = settings.completedToday
        persistProgress(); showToast("Search completed.")
        if state.completedToday >= settings.dailyTarget { complete() }
        else if state.currentIndex >= queue.count { exhausted() }
        else if state.mode == .auto {
            state.initialDelay = Int.random(in: settings.delayMin...settings.delayMax)
            state.countdownSeconds = state.initialDelay
            persistProgress(); beginCountdown()
        }
    }
    func navigationFailed(token: UUID) {
        guard token == pendingToken else { return }
        fail("Search navigation failed. Check your connection or complete any website prompt, then retry.")
    }
    private func beginCountdown() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.state.status == .running else { return }
                if self.settings.progressDate != BingQueries.localDate() { self.refreshDay(); return }
                self.state.countdownSeconds = max(0, self.state.countdownSeconds - 1)
                self.persistProgress()
                if self.state.countdownSeconds == 0 { self.executeNext(); return }
            }
        }
    }
    private func invalidateNavigation() {
        timer?.cancel(); timer = nil; timeout?.cancel(); timeout = nil
        pendingToken = nil; state.isNavigating = false; stopBrowser?()
    }
    func pause() {
        guard state.status == .running else { return }
        invalidateNavigation(); state.status = .paused; persistProgress(); showToast("Paused.")
    }
    func stop() {
        invalidateNavigation(); state.status = .idle; state.activeQuery = nil
        persistProgress(); showToast("Stopped. Queue position preserved.")
    }
    private func exhausted() {
        invalidateNavigation(); state.status = .exhausted; persistProgress()
        showToast("Completed \(state.completedToday) of \(settings.dailyTarget) searches. Add more unique queries to continue.")
    }
    private func complete() {
        invalidateNavigation(); state.status = .completed
        settings.lastCompletedDate = BingQueries.localDate(); persistProgress(); completionSerial += 1
        notify("BingBot: Today’s search target is complete.")
    }
    private func fail(_ message: String) {
        invalidateNavigation(); state.status = .error; state.lastError = message
        persistProgress(); showToast("Navigation error.")
        notify("BingBot: Search automation encountered an error.")
    }
    func backgrounded() {
        if state.status == .running {
            pause(); notify("BingBot: \(max(0, settings.dailyTarget - state.completedToday)) searches remaining in today’s target.")
        }
    }
    func resetProgress() {
        invalidateNavigation(); queue = []; state.currentIndex = 0; state.totalQueries = 0
        state.countdownSeconds = 0; state.activeQuery = nil; state.status = .idle
        settings.completedToday = 0; state.completedToday = 0; settings.usedQueryKeys = []
        settings.progressDate = BingQueries.localDate(); persistProgress()
    }
    private func persistProgress() {
        settings.frozenQueue = queue; settings.currentIndex = state.currentIndex
        settings.remainingDelay = state.countdownSeconds
        do { try storage.saveSettings(settings) } catch { self.error = "Progress could not be saved." }
    }
    func requestNotifications() {
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                showToast(allowed ? "Completion alerts enabled." : "Notifications are disabled. BingBot still works.")
            } catch { showToast("Notification permission could not be requested.") }
        }
    }
    private func notify(_ message: String) {
        guard settings.showNotifications else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let permission = await center.notificationSettings().authorizationStatus
            guard permission == .authorized || permission == .provisional else { return }
            let content = UNMutableNotificationContent(); content.title = "BingBot"; content.body = message; content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "bingbot.\(UUID().uuidString)", content: content, trigger: nil))
        }
    }
    func exportData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(BingBackup(settings: settings, queries: queries))
    }
    func importData(_ backup: BingBackup, replace: Bool) {
        let next = replace ? backup.queries : BingQueries.unique(queries + backup.queries)
        guard next.count <= 10_000 else { error = "The library supports up to 10,000 queries."; return }
        do {
            // Atomic library write first: a failed write leaves the active run and editor intact.
            try storage.saveLibrary(next)
            invalidateNavigation(); queries = next; settings = backup.settings
            try storage.saveSettings(settings)
            queue = settings.frozenQueue; state = SearchState(mode: state.mode)
            state.currentIndex = settings.currentIndex; state.totalQueries = queue.count
            state.countdownSeconds = settings.remainingDelay; state.initialDelay = settings.remainingDelay
            refreshDay(); state.status = state.completedToday >= settings.dailyTarget ? .completed : .paused
            loadingLibraryFailed = false; updateInput(); showToast("Backup imported.")
        } catch { self.error = BingDataError.storage.localizedDescription }
    }
    func resetData() {
        do {
            try storage.saveLibrary([])
            invalidateNavigation(); queries = []; settings = BingSettings(); state = SearchState(); queue = []
            try storage.saveSettings(settings); refreshDay(); clearInput(); loadingLibraryFailed = false
            showToast("BingBot data reset.")
        } catch { self.error = BingDataError.storage.localizedDescription }
    }
}
