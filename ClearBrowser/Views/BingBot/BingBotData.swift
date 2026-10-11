import Foundation
import NaturalLanguage

enum BingParsingMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case words, phrases, sentences
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct QueryLibrary: Codable {
    var schemaVersion = 1
    var queries: [String] = []
}

struct QueryInputState {
    var draftText = ""
    var parsingMode: BingParsingMode = .words
    var previewQueries: [String] = []
    var parsedCount = 0
    var duplicateWithinInputCount = 0
    var alreadySavedCount = 0
    var newQueryCount: Int { previewQueries.count }
    var warnings: [String] = []
    var isValid = true
}

enum BingQueries {
    static func normalize(_ query: String) -> String {
        query.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func key(_ query: String) -> String {
        normalize(query).folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func unique(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        return queries.compactMap {
            let value = normalize($0)
            return !value.isEmpty && seen.insert(key(value)).inserted ? value : nil
        }
    }
    static func preview(_ text: String, mode: BingParsingMode, saved: [String]) -> QueryInputState {
        var result = QueryInputState(draftText: text, parsingMode: mode)
        var tokens: [String] = []
        switch mode {
        case .words:
            let wordText = text.precomposedStringWithCanonicalMapping
            // Keep internal apostrophes and hyphens, including typographic forms.
            let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{M}\p{N}]*(?:['’\-‐‑][\p{L}\p{N}][\p{L}\p{M}\p{N}]*)*"#)
            let range = NSRange(wordText.startIndex..., in: wordText)
            tokens = regex.matches(in: wordText, range: range).compactMap {
                Range($0.range, in: wordText).map { String(wordText[$0]) }
            }
        case .phrases:
            var quoted = false, buffer = ""
            let characters = Array(text)
            var index = 0
            while index < characters.count {
                let character = characters[index]
                if character == "\"" || character == "“" || character == "”" {
                    if character == "\"", quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                        buffer.append("\""); index += 1
                    } else { quoted.toggle() }
                } else if character.isNewline || (!quoted && [",", ";", "\t"].contains(character)) {
                    tokens.append(buffer); buffer = ""
                } else { buffer.append(character) }
                index += 1
            }
            tokens.append(buffer)
            if quoted {
                result.isValid = false
                result.warnings.append("Close the quotation marks before adding these phrases.")
            }
            if tokens.filter({ !normalize($0).isEmpty }).count == 1, !normalize(text).isEmpty {
                result.warnings.append("This text is currently one phrase. Choose Words or Sentences to split the paragraph further.")
            }
        case .sentences:
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = text
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                tokens.append(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".!?。！？")))
                return true
            }
        }
        let nonempty = tokens.map(normalize).filter { !$0.isEmpty }
        let deduplicated = unique(nonempty)
        let existing = Set(saved.map(key))
        result.parsedCount = nonempty.count
        result.duplicateWithinInputCount = nonempty.count - deduplicated.count
        result.alreadySavedCount = deduplicated.filter { existing.contains(key($0)) }.count
        result.previewQueries = deduplicated.filter { !existing.contains(key($0)) }
        if result.previewQueries.contains(where: { $0.count > 500 }) {
            result.isValid = false
            result.warnings.append("Each query must be at most 500 characters. Split longer text into words or sentences.")
        }
        return result
    }
    static func alphanumeric(count: Int) -> [String] {
        let letters = "abcdefghijklmnopqrst", numbers = "1234567890"
        var result = (1...letters.count).map { String(letters.prefix($0)) }
            + (1...numbers.count).map { String(numbers.prefix($0)) }
        var suffix = 1
        while result.count < count {
            result.append("\(letters) \(suffix)"); suffix += 1
        }
        return Array(result.prefix(max(30, count)))
    }
    static func localDate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct BingSettings: Codable {
    var querySource = "custom"
    var defaultParsingMode: BingParsingMode = .words
    var delayMin = 8
    var delayMax = 15
    #if os(macOS)
    var dailyTarget = 30
    #else
    var dailyTarget = 20
    #endif
    var progressDate = BingQueries.localDate()
    var completedToday = 0
    var lastCompletedDate: String?
    var autoCloseOnComplete = false
    var showNotifications = true
    var startupCountdownSeconds = 3
    // These are query strings only, never navigation URLs or browser session data.
    var frozenQueue: [String] = []
    var currentIndex = 0
    var usedQueryKeys: [String] = []
    var remainingDelay = 0

    func validate() throws {
        guard ["custom", "alphanumeric"].contains(querySource), (3...30).contains(delayMin),
              (5...60).contains(delayMax), delayMax >= delayMin, (1...100).contains(dailyTarget),
              (3...5).contains(startupCountdownSeconds), (0...100).contains(completedToday),
              (0...frozenQueue.count).contains(currentIndex), (0...60).contains(remainingDelay),
              frozenQueue.count <= 10_000, usedQueryKeys.count <= 10_000,
              frozenQueue.allSatisfy({ !BingQueries.normalize($0).isEmpty && $0.count <= 500 }),
              validDate(progressDate), lastCompletedDate.map(validDate) ?? true else { throw BingDataError.invalid }
    }
    private func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

enum BingDataError: LocalizedError {
    case invalid, privacy, storage, duplicate
    var errorDescription: String? {
        switch self {
        case .invalid: return "This is not valid BingBot 1.0 app data, or a setting is outside its supported range."
        case .privacy: return "This backup contains unsupported account, credential, or browser data. Only BingBot query data and approved preferences can be imported."
        case .storage: return "App data could not be saved. Your input is still available; try again."
        case .duplicate: return "That query already exists in the library."
        }
    }
}

struct BingBackup: Codable {
    var version = "1.0"
    var app = "BingBot"
    var exportedAt = ISO8601DateFormatter().string(from: Date())
    var settings: BingSettings
    var queries: [String]

    static func decode(_ data: Data) throws -> BingBackup {
        guard data.count <= 8_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let preferences = root["settings"] as? [String: Any] else { throw BingDataError.invalid }
        let topKeys: Set<String> = ["version", "app", "exportedAt", "settings", "queries"]
        let settingKeys: Set<String> = ["querySource", "defaultParsingMode", "delayMin", "delayMax", "dailyTarget",
            "progressDate", "completedToday", "lastCompletedDate", "autoCloseOnComplete", "showNotifications",
            "startupCountdownSeconds", "frozenQueue", "currentIndex", "usedQueryKeys", "remainingDelay"]
        guard Set(root.keys).isSubset(of: topKeys), Set(preferences.keys).isSubset(of: settingKeys) else { throw BingDataError.privacy }
        var backup = try JSONDecoder().decode(BingBackup.self, from: data)
        guard backup.version == "1.0", backup.app == "BingBot", backup.queries.count <= 10_000,
              backup.queries.allSatisfy({ $0.count <= 500 }) else { throw BingDataError.invalid }
        try backup.settings.validate()
        backup.queries = BingQueries.unique(backup.queries)
        backup.settings.frozenQueue = BingQueries.unique(backup.settings.frozenQueue)
        backup.settings.usedQueryKeys = BingQueries.unique(backup.settings.usedQueryKeys).map(BingQueries.key)
        backup.settings.currentIndex = min(backup.settings.currentIndex, backup.settings.frozenQueue.count)
        return backup
    }
}

struct BingStorage {
    let directory: URL
    let defaults: UserDefaults
    static let settingsKey = "bingbot.settings.v1"
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BingBot", isDirectory: true)
        self.defaults = defaults
    }
    func loadLibrary() throws -> QueryLibrary {
        let url = directory.appendingPathComponent("queries.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return QueryLibrary() }
        let library = try JSONDecoder().decode(QueryLibrary.self, from: Data(contentsOf: url))
        guard library.schemaVersion == 1, library.queries.count <= 10_000,
              library.queries.allSatisfy({ $0.count <= 500 }) else { throw BingDataError.invalid }
        return QueryLibrary(queries: BingQueries.unique(library.queries))
    }
    func saveLibrary(_ queries: [String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(QueryLibrary(queries: queries)).write(to: directory.appendingPathComponent("queries.json"), options: .atomic)
    }
    func loadSettings() throws -> BingSettings {
        guard let data = defaults.data(forKey: Self.settingsKey) else { return BingSettings() }
        let settings = try JSONDecoder().decode(BingSettings.self, from: data)
        try settings.validate(); return settings
    }
    func saveSettings(_ settings: BingSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.settingsKey)
    }
}
