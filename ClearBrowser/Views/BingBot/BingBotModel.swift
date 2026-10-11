import Foundation
import Combine
import UserNotifications

enum BingRunStatus: String { case idle = "Ready", running = "Query copied", completed = "Target reached", exhausted = "No unused queries", error = "Error" }

struct SearchState {
    var status: BingRunStatus = .idle
    var currentIndex = 0
    var totalQueries = 0
    var dailyTarget = 20
    var completedToday = 0
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
    private var previewTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    init(storage: BingStorage = BingStorage()) {
        self.storage = storage
        do { settings = try storage.loadSettings() } catch { self.error = "Saved preferences could not be read." }
        do { queries = try storage.loadLibrary().queries }
        catch { loadingLibraryFailed = true; self.error = "Saved queries could not be read. Import a backup or explicitly reset BingBot data." }
        input.parsingMode = settings.defaultParsingMode
        queue = settings.frozenQueue
        state.currentIndex = settings.currentIndex
        state.totalQueries = queue.count
        refreshDay()
        state.status = state.completedToday >= settings.dailyTarget ? .completed : .idle
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
            settings.progressDate = today; settings.completedToday = 0
            settings.usedQueryKeys = []; queue = []; state.currentIndex = 0; state.totalQueries = 0
            state.activeQuery = nil; state.status = .idle
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
        updateInput(); showToast("Query updated. The current query queue keeps its original entries.")
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
            if state.completedToday >= settings.dailyTarget { state.status = .completed }
        } catch { self.error = "Preferences could not be saved." }
    }
    /// Copying is a staging action. It never navigates or increments progress.
    func nextQueryToCopy() -> String? {
        refreshDay()
        guard state.completedToday < settings.dailyTarget else {
            state.status = .completed; showToast("Today’s target is complete. Reset today’s progress to begin again."); return nil
        }
        let used = Set(settings.usedQueryKeys)
        if queue.isEmpty || state.currentIndex >= queue.count {
            let source = settings.querySource == "alphanumeric" ? BingQueries.alphanumeric(count: settings.dailyTarget) : queries
            queue = source.filter { !used.contains(BingQueries.key($0)) }; state.currentIndex = 0
        }
        while state.currentIndex < queue.count && used.contains(BingQueries.key(queue[state.currentIndex])) {
            state.currentIndex += 1
        }
        state.totalQueries = queue.count
        guard state.currentIndex < queue.count else {
            state.status = .exhausted; showToast("Add more unique queries to continue."); persistProgress(); return nil
        }
        let query = queue[state.currentIndex]
        state.activeQuery = query; state.status = .running
        persistProgress()
        return query
    }
    /// Called only by the browser's matching, successfully finished main-frame navigation.
    /// Daily query keys suppress reloads, pagination and returning to previously counted searches.
    func searchCompleted(query: String) {
        refreshDay()
        let normalized = BingQueries.normalize(query), key = BingQueries.key(query)
        guard !normalized.isEmpty, normalized.count <= 500, !settings.usedQueryKeys.contains(key), settings.completedToday < 100 else { return }
        settings.usedQueryKeys.append(key)
        settings.completedToday += 1; state.completedToday = settings.completedToday
        if let copied = state.activeQuery, BingQueries.key(copied) == key { state.activeQuery = nil }
        let used = Set(settings.usedQueryKeys)
        while state.currentIndex < queue.count && used.contains(BingQueries.key(queue[state.currentIndex])) { state.currentIndex += 1 }
        if state.completedToday >= settings.dailyTarget {
            state.status = .completed
            settings.lastCompletedDate = BingQueries.localDate()
            if state.completedToday == settings.dailyTarget {
                completionSerial += 1; notify("BingBot: Today’s search target is complete.")
            }
        } else {
            state.status = state.activeQuery == nil ? .idle : .running
        }
        persistProgress(); showToast("Search completed. \(state.completedToday) today.")
    }
    func resetProgress() {
        queue = []; state.currentIndex = 0; state.totalQueries = 0
        state.activeQuery = nil; state.status = .idle
        settings.completedToday = 0; state.completedToday = 0; settings.usedQueryKeys = []
        settings.progressDate = BingQueries.localDate(); persistProgress()
    }
    private func persistProgress() {
        settings.frozenQueue = queue; settings.currentIndex = state.currentIndex
        settings.remainingDelay = 0
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
            queries = next; settings = backup.settings
            try storage.saveSettings(settings)
            queue = settings.frozenQueue; state = SearchState()
            state.currentIndex = settings.currentIndex; state.totalQueries = queue.count
            refreshDay(); state.status = state.completedToday >= settings.dailyTarget ? .completed : .idle
            loadingLibraryFailed = false; updateInput(); showToast("Backup imported.")
        } catch { self.error = BingDataError.storage.localizedDescription }
    }
    func resetData() {
        do {
            try storage.saveLibrary([])
            queries = []; settings = BingSettings(); state = SearchState(); queue = []
            try storage.saveSettings(settings); refreshDay(); clearInput(); loadingLibraryFailed = false
            showToast("BingBot data reset.")
        } catch { self.error = BingDataError.storage.localizedDescription }
    }
}
