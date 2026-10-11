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
    func testCopyDoesNotCountOrAdvanceUntilMatchingCompletedSearch() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(model.nextQueryToCopy(), "Swift")
        XCTAssertEqual(model.nextQueryToCopy(), "Swift")
        XCTAssertEqual(model.state.completedToday, 0)
        XCTAssertEqual(model.state.currentIndex, 0)
        model.searchCompleted(query: "Unrelated typed query")
        XCTAssertEqual(model.state.completedToday, 1)
        XCTAssertEqual(model.nextQueryToCopy(), "Swift")
        model.searchCompleted(query: "swift")
        XCTAssertEqual(model.state.currentIndex, 1)
        XCTAssertNil(model.state.activeQuery)
        XCTAssertEqual(model.state.completedToday, 2)
        XCTAssertEqual(model.state.status, .completed)
    }
    @MainActor
    func testDuplicateCompletionAndRelaunchPreserveDailyCount() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        _ = model.nextQueryToCopy()
        model.searchCompleted(query: "Swift")
        model.searchCompleted(query: "SWIFT")
        XCTAssertEqual(model.state.completedToday, 1)
        let restored = BingBotModel(storage: storage)
        restored.searchCompleted(query: "Swift")
        XCTAssertEqual(restored.state.completedToday, 1)
        XCTAssertEqual(restored.nextQueryToCopy(), "Python")
        restored.searchCompleted(query: "Python")
        XCTAssertEqual(restored.state.completedToday, 2)
        XCTAssertEqual(try storage.loadSettings().lastCompletedDate, BingQueries.localDate())
    }
    @MainActor
    func testDailyRolloverAndDuplicateEdit() async throws {
        let (_, storage, folder, suite) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        var settings = try storage.loadSettings(); settings.progressDate = "2020-01-01"
        settings.completedToday = 1; settings.usedQueryKeys = ["swift"]; settings.frozenQueue = ["Swift"]; settings.currentIndex = 1
        try storage.saveSettings(settings)
        let model = BingBotModel(storage: storage)
        XCTAssertEqual(model.state.completedToday, 0)
        XCTAssertEqual(model.nextQueryToCopy(), "Swift")
        XCTAssertThrowsError(try model.editQuery("Swift", replacement: "PYTHON"))
    }
    func testURLChangesOnlyCountSuccessfulDistinctBingSearches() throws {
        var tracker = BingSearchURLTracker()
        let swift = try XCTUnwrap(URL(string: "https://www.bing.com/search?q=Swift"))
        let python = try XCTUnwrap(URL(string: "https://www.bing.com/search?q=Python"))
        XCTAssertNil(tracker.finished(url: swift, succeeded: false, historyOrReload: false))
        XCTAssertEqual(tracker.finished(url: swift, succeeded: true, historyOrReload: false), "Swift")
        XCTAssertNil(tracker.finished(url: swift, succeeded: true, historyOrReload: false))
        XCTAssertNil(tracker.finished(url: try XCTUnwrap(URL(string: "https://www.bing.com/search?q=Swift&first=11")), succeeded: true, historyOrReload: false))
        XCTAssertEqual(tracker.finished(url: python, succeeded: true, historyOrReload: false), "Python")
        XCTAssertNil(tracker.finished(url: swift, succeeded: true, historyOrReload: true))
        XCTAssertNil(tracker.finished(url: try XCTUnwrap(URL(string: "https://example.com/search?q=new")), succeeded: true, historyOrReload: false))
        XCTAssertNil(tracker.finished(url: try XCTUnwrap(URL(string: "https://www.bing.com/search?q=")), succeeded: true, historyOrReload: false))
        XCTAssertEqual(tracker.finished(url: swift, succeeded: true, historyOrReload: false, on: "2030-01-01"), "Swift")
    }
    @MainActor
    func testFrozenQueryQueueAndExhaustionWithoutCountingCopies() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        model.updateSettings { $0.dailyTarget = 5 }
        XCTAssertEqual(model.nextQueryToCopy(), "Swift")
        try model.editQuery("Python", replacement: "New Python query")
        model.searchCompleted(query: "Swift")
        XCTAssertEqual(model.nextQueryToCopy(), "Python")
        model.searchCompleted(query: "Python")
        _ = model.nextQueryToCopy(); model.searchCompleted(query: "Machine learning")
        // Edits take effect when the old queue is consumed; the new query is unused today.
        XCTAssertEqual(model.nextQueryToCopy(), "New Python query")
        model.searchCompleted(query: "New Python query")
        XCTAssertNil(model.nextQueryToCopy())
        XCTAssertEqual(model.state.status, .exhausted)
        XCTAssertEqual(model.state.completedToday, 4)
        XCTAssertNil(model.settings.lastCompletedDate)
    }
    @MainActor
    func testGeneratedPrefixesPreserveDraftAndImportMergesNormalizedQueries() async throws {
        let (model, storage, folder, suite) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder); storage.defaults.removePersistentDomain(forName: suite) }
        model.updateInput(text: "Unsaved paragraph", mode: .words)
        XCTAssertTrue(model.addGeneratedQueries(["what is machine learning", "WHAT  IS machine learning"]))
        XCTAssertEqual(model.input.draftText, "Unsaved paragraph")
        var preferences = BingSettings(); preferences.showNotifications = false
        model.importData(BingBackup(settings: preferences, queries: ["swift", "New query"]), replace: false)
        XCTAssertEqual(model.queries.count, 5)
        XCTAssertEqual(model.queries.first, "Swift")
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
