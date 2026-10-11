import XCTest
@testable import BingBot

final class BingBotTests: XCTestCase {
    func testWordParsingKeepsInternalHyphensAndDeduplicates() {
        let preview = BingQueries.preview("Swift, Python and Swift. Machine-learning is useful; Python is popular.", mode: .words, saved: [])
        XCTAssertEqual(preview.previewQueries, ["Swift", "Python", "and", "Machine-learning", "is", "useful", "popular"])
        XCTAssertEqual(preview.duplicateWithinInputCount, 3)
        XCTAssertEqual(BingQueries.preview("don't stop rock‑solid", mode: .words, saved: []).previewQueries, ["don't", "stop", "rock‑solid"])
    }
    func testQuotedPhrasesAndWholeQueryDeduplication() {
        let text = "best Swift tutorials\nhow to learn Python; best Swift tutorials\n\"Miami, Florida travel guide\", machine learning basics"
        let preview = BingQueries.preview(text, mode: .phrases, saved: ["Swift"])
        XCTAssertEqual(preview.previewQueries, ["best Swift tutorials", "how to learn Python", "Miami, Florida travel guide", "machine learning basics"])
        XCTAssertEqual(preview.duplicateWithinInputCount, 1)
        XCTAssertFalse(BingQueries.preview("\"unfinished phrase", mode: .phrases, saved: []).isValid)
        XCTAssertEqual(BingQueries.preview("\"He said \"\"hello\"\"\", next", mode: .phrases, saved: []).previewQueries, ["He said \"hello\"", "next"])
    }
    func testSentenceTokenization() {
        let preview = BingQueries.preview("How does SwiftUI work? What is machine learning? How does SwiftUI work?", mode: .sentences, saved: [])
        XCTAssertEqual(preview.previewQueries, ["How does SwiftUI work", "What is machine learning"])
    }
    func testUnicodeWhitespaceAndCaseNormalization() {
        XCTAssertEqual(BingQueries.unique(["Café", "Cafe\u{301}", "CAFÉ", "HOW   to learn Python", "how to learn python"]), ["Café", "HOW to learn Python"])
        let preview = BingQueries.preview("how to learn Python; Swift; swift", mode: .phrases, saved: ["HOW TO LEARN PYTHON"])
        XCTAssertEqual(preview.previewQueries, ["Swift"])
        XCTAssertEqual(preview.alreadySavedCount, 1)
        XCTAssertEqual(preview.duplicateWithinInputCount, 1)
    }
    func testAlphanumericGenerationIsUniqueAtLargeTarget() {
        let queries = BingQueries.alphanumeric(count: 100)
        XCTAssertEqual(queries.count, 100)
        XCTAssertEqual(Set(queries).count, 100)
        XCTAssertEqual(queries[19], "abcdefghijklmnopqrst")
        XCTAssertEqual(queries[29], "1234567890")
    }
    func testBackupRejectsAdditionalPrivacyFieldsAndInvalidRanges() throws {
        let backup = BingBackup(settings: BingSettings(), queries: ["Swift", "swift"])
        let encoded = try JSONEncoder().encode(backup)
        XCTAssertEqual(try BingBackup.decode(encoded).queries, ["Swift"])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["accounts"] = []
        XCTAssertThrowsError(try BingBackup.decode(JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "accounts")
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        settings["delayMin"] = 60; object["settings"] = settings
        XCTAssertThrowsError(try BingBackup.decode(JSONSerialization.data(withJSONObject: object)))
    }
    @MainActor
    private func fixture() throws -> (BingBotModel, BingStorage, URL, String) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "BingBotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let storage = BingStorage(directory: folder, defaults: defaults)
        try storage.saveLibrary(["Swift", "Python", "Machine learning"])
        var settings = BingSettings(); settings.showNotifications = false; settings.dailyTarget = 2
        try storage.saveSettings(settings)
        return (BingBotModel(storage: storage), storage, folder, suite)
    }
    @MainActor
    func testOnlyMatchingSuccessCountsAndFrozenQueueSurvivesEditing() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { model.stop(); try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        var token: UUID?
        var urls: [URL] = []
        model.navigate = { url, id in urls.append(url); token = id }
        model.setMode(.manual); model.nextSearch()
        let first = try XCTUnwrap(token)
        model.navigationSucceeded(token: UUID())
        XCTAssertEqual(model.state.completedToday, 0)
        try model.editQuery("Python", replacement: "New Python query")
        model.navigationSucceeded(token: first); model.navigationSucceeded(token: first)
        XCTAssertEqual(model.state.completedToday, 1)
        model.nextSearch()
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(urls.last), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "Python")
        model.navigationSucceeded(token: try XCTUnwrap(token))
        XCTAssertEqual(model.state.status, .completed)
        XCTAssertEqual(try storage.loadSettings().completedToday, 2)
        XCTAssertEqual(try storage.loadSettings().lastCompletedDate, BingQueries.localDate())
    }
    @MainActor
    func testStopIgnoresStaleCallbacksAndRelaunchRestoresPartialProgress() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { model.stop(); try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        var token: UUID?
        model.navigate = { _, id in token = id }; model.setMode(.manual); model.nextSearch()
        let stale = try XCTUnwrap(token); model.stop(); model.navigationSucceeded(token: stale)
        XCTAssertEqual(model.state.completedToday, 0)
        model.nextSearch(); model.navigationSucceeded(token: try XCTUnwrap(token))
        model.stop()
        let restored = BingBotModel(storage: storage)
        XCTAssertEqual(restored.state.completedToday, 1)
        XCTAssertEqual(restored.state.currentIndex, 1)
        XCTAssertEqual(restored.state.status, .paused)
    }
    @MainActor
    func testFailureDoesNotCountAndExhaustionIsNotCompletion() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { model.stop(); try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        model.deleteQueries(["Python", "Machine learning"])
        var token: UUID?
        model.navigate = { _, id in token = id }; model.setMode(.manual); model.nextSearch()
        model.navigationFailed(token: try XCTUnwrap(token))
        XCTAssertEqual(model.state.status, .error); XCTAssertEqual(model.state.completedToday, 0)
        model.nextSearch(); model.navigationSucceeded(token: try XCTUnwrap(token))
        XCTAssertEqual(model.state.status, .exhausted)
        XCTAssertNil(model.settings.lastCompletedDate)
    }
    @MainActor
    func testDailyRolloverAndDuplicateEdit() async throws {
        let (_, storage, folder, suite) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        var settings = try storage.loadSettings(); settings.progressDate = "2020-01-01"
        settings.completedToday = 1; settings.frozenQueue = ["Swift"]; settings.currentIndex = 1
        try storage.saveSettings(settings)
        let model = BingBotModel(storage: storage)
        XCTAssertEqual(model.state.completedToday, 0)
        XCTAssertEqual(model.state.totalQueries, 0)
        XCTAssertThrowsError(try model.editQuery("Swift", replacement: "PYTHON"))
        XCTAssertEqual(model.queries.first, "Swift")
    }
    @MainActor
    func testAutoCountdownPauseAndBackgroundIgnoreLateCallbacks() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { model.stop(); try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        model.updateSettings { $0.delayMin = 3; $0.delayMax = 5 }
        var tokens: [UUID] = []
        model.navigate = { _, token in tokens.append(token) }
        model.start()
        model.navigationSucceeded(token: try XCTUnwrap(tokens.last))
        let delay = model.state.countdownSeconds
        XCTAssertTrue((3...5).contains(delay))
        model.pause()
        try await Task.sleep(for: .milliseconds(1_100))
        XCTAssertEqual(model.state.countdownSeconds, delay)
        XCTAssertEqual(tokens.count, 1)
        model.start()
        XCTAssertEqual(model.state.status, .running)
        model.backgrounded()
        XCTAssertEqual(model.state.status, .paused)
        XCTAssertEqual(model.state.countdownSeconds, delay)
        XCTAssertEqual(try storage.loadSettings().remainingDelay, delay)
        model.navigationSucceeded(token: try XCTUnwrap(tokens.last))
        XCTAssertEqual(model.state.completedToday, 1)
    }
    @MainActor
    func testGeneratedPrefixesPreserveDraftAndImportMergesNormalizedQueries() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { model.stop(); try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        model.updateInput(text: "Unsaved paragraph", mode: .words)
        XCTAssertTrue(model.addGeneratedQueries(["what is machine learning", "WHAT  IS machine learning"]))
        XCTAssertEqual(model.input.draftText, "Unsaved paragraph")
        XCTAssertEqual(model.queries.count, 4)
        var preferences = BingSettings(); preferences.showNotifications = false
        let backup = BingBackup(settings: preferences, queries: ["swift", "New query"])
        model.importData(backup, replace: false)
        XCTAssertEqual(model.queries.count, 5)
        XCTAssertEqual(model.queries.first, "Swift")
        XCTAssertEqual(try storage.loadLibrary().queries.last, "New query")
    }
    @MainActor
    func testFailedStorageWriteKeepsDraftAndLibraryIntact() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        try FileManager.default.removeItem(at: folder)
        try Data("not a directory".utf8).write(to: folder)
        model.updateInput(text: "new query", mode: .phrases); model.addInput()
        XCTAssertEqual(model.input.draftText, "new query")
        XCTAssertEqual(model.queries.count, 3)
        XCTAssertNotNil(model.error)
    }
    @MainActor
    func testBrowserRejectsUnsupportedSchemesAndCredentialURLs() async {
        XCTAssertNil(BingBotBrowser.validatedURL("javascript:alert(1)"))
        XCTAssertNil(BingBotBrowser.validatedURL("file:///private/file"))
        XCTAssertNil(BingBotBrowser.validatedURL("https://user:secret@example.com"))
        XCTAssertNil(BingBotBrowser.validatedURL("https://bing.com invalid"))
        XCTAssertEqual(BingBotBrowser.validatedURL("bing.com")?.scheme, "https")
    }
}
