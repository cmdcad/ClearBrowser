import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class TextReaderModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var documents: [ReaderDocument] = []
    @Published private(set) var document: ReaderDocument?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var isImporting = false
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var sentences: [ReaderSpan] = []
    @Published private(set) var activeSentence: Int?
    @Published var message: String?
    @Published var followReading = true
    @Published var highlighting = true
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var generation: [Int: Task<ReaderTimings, Error>] = [:]
    private var revision = UUID()
    private var generationRevision = UUID()
    private var lastSaved = Date.distantPast
    @Published private(set) var wantsPlayback = false
    private var interruptions: NSObjectProtocol?

    private struct Position: Codable {
        var page: Int
        var position: Double
        var speed: Float
        var updated: Date
    }

    private var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TextReader", isDirectory: true)
    }
    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func audioURL(_ doc: ReaderDocument, _ page: Int) -> URL { folder(doc.id).appendingPathComponent("\(page).mp3") }
    private func timingURL(_ doc: ReaderDocument, _ page: Int) -> URL { folder(doc.id).appendingPathComponent("\(page).json") }
    var pageText: String {
        guard let document, document.pages.indices.contains(document.page) else { return "" }
        return document.pages[document.page]
    }

    override init() {
        super.init()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for directory in directories {
                let file = directory.appendingPathComponent("document.json")
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                var doc = try JSONDecoder().decode(ReaderDocument.self, from: Data(contentsOf: file))
                if let data = try? Data(contentsOf: directory.appendingPathComponent("position.json")),
                   let position = try? JSONDecoder().decode(Position.self, from: data) {
                    doc.page = min(max(0, position.page), max(0, doc.pages.count - 1))
                    doc.position = max(0, position.position)
                    doc.speed = min(2, max(0.5, position.speed))
                    doc.updated = position.updated
                }
                if !doc.pages.isEmpty { documents.append(doc) }
            }
            documents.sort { $0.updated > $1.updated }
        } catch { message = "Could not load the reading library: \(error.localizedDescription)" }
        interruptions = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
        }
    }

    func importText(_ text: String, title: String, sourceURL: String? = nil) {
        let cleanedText = ReaderText.cleanImported(text)
        guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Paste or import some readable text first."
            return
        }
        let doc = ReaderDocument(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled document" : title, sourceURL: sourceURL, pages: ReaderText.chunks(cleanedText))
        do {
            try FileManager.default.createDirectory(at: folder(doc.id), withIntermediateDirectories: true)
            try JSONEncoder().encode(doc).write(to: folder(doc.id).appendingPathComponent("document.json"), options: .atomic)
            documents.insert(doc, at: 0)
            open(doc)
            play()
        } catch { message = "Could not save this document: \(error.localizedDescription)" }
    }

    func updateDocument(title: String, text: String) -> Bool {
        guard var doc = document else { return false }
        let cleanedText = ReaderText.cleanImported(text)
        guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "A document must contain readable text."
            return false
        }

        let newPages = ReaderText.chunks(cleanedText)
        let textChanged = newPages != doc.pages
        if textChanged {
            pause()
            revision = UUID()
            generationRevision = UUID()
            loadTask?.cancel()
            generation.values.forEach { $0.cancel() }
            generation.removeAll()
            player = nil
            isLoading = false
            duration = 0
            sentences = []
            activeSentence = nil
            doc.pages = newPages
            doc.page = 0
            doc.position = 0
            time = 0
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        doc.title = trimmedTitle.isEmpty ? "Untitled document" : trimmedTitle
        doc.updated = Date()

        do {
            if textChanged {
                for page in doc.pages.indices {
                    for file in [audioURL(doc, page), timingURL(doc, page)] where FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.removeItem(at: file)
                    }
                }
                let positionFile = folder(doc.id).appendingPathComponent("position.json")
                if FileManager.default.fileExists(atPath: positionFile.path) {
                    try FileManager.default.removeItem(at: positionFile)
                }
            }
            try JSONEncoder().encode(doc).write(to: folder(doc.id).appendingPathComponent("document.json"), options: .atomic)
            document = doc
            if let index = documents.firstIndex(where: { $0.id == doc.id }) { documents[index] = doc }
            return true
        } catch {
            message = "Could not save this document: \(error.localizedDescription)"
            return false
        }
    }

    func importURL(_ value: String, title: String) async -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            message = "Enter a complete http or https URL."
            return false
        }
        isImporting = true
        defer { isImporting = false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ReaderAudioService.failure("This page could not be downloaded.")
            }
            let type = response.mimeType?.lowercased() ?? ""
            let text: String
            if type.contains("html") {
                guard var html = String(data: data, encoding: .utf8) else {
                    throw ReaderAudioService.failure("This page's text encoding is unsupported. Try pasting its text.")
                }
                html = html.replacingOccurrences(of: "(?is)<(script|style|nav|header|footer|aside)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
                if let range = html.range(of: "(?is)<(article|main)\\b[^>]*>.*?</\\1\\s*>", options: .regularExpression) {
                    html = String(html[range])
                }
                // Do not load external resources while extracting static article markup.
                html = html.replacingOccurrences(of: "(?is)<(img|link|iframe|object|embed)\\b[^>]*>", with: "", options: .regularExpression)
                let attributed = try NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
                text = attributed.string
            } else if type.hasPrefix("text/") || type == "application/json" {
                guard let decoded = String(data: data, encoding: .utf8) else { throw ReaderAudioService.failure("Could not decode this text. Try pasting it instead.") }
                text = decoded
            } else { throw ReaderAudioService.failure("This URL does not contain a supported text page. Paste the text instead.") }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReaderAudioService.failure("No readable text was found. For pages requiring login or JavaScript, paste the article text.")
            }
            let count = documents.count
            importText(text, title: title.isEmpty ? (url.host ?? "Imported article") : title, sourceURL: url.absoluteString)
            return documents.count > count
        } catch {
            if !Task.isCancelled { message = error.localizedDescription }
            return false
        }
    }

    func open(_ doc: ReaderDocument) {
        pause()
        revision = UUID()
        generationRevision = UUID()
        loadTask?.cancel()
        generation.values.forEach { $0.cancel() }
        generation.removeAll()
        player = nil
        duration = 0
        sentences = []
        activeSentence = nil
        isLoading = false
        document = documents.first(where: { $0.id == doc.id }) ?? doc
        time = document?.position ?? 0
        followReading = true
    }

    func close() {
        pause()
        revision = UUID()
        generationRevision = UUID()
        loadTask?.cancel()
        generation.values.forEach { $0.cancel() }
        generation.removeAll()
        player = nil
        document = nil
        isLoading = false
    }

    func play() {
        guard let doc = document else { return }
        wantsPlayback = true
        if let player {
            do { try AVAudioSession.sharedInstance().setActive(true) }
            catch { message = error.localizedDescription; return }
            if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
            isPlaying = player.play()
            if isPlaying { startTimer() }
            else { wantsPlayback = false; message = "Audio could not start playing. Please retry." }
            return
        }
        guard !isLoading else { return }
        isLoading = true
        let token = revision
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let timings = try await self.prepare(doc, page: doc.page)
                try Task.checkCancellation()
                guard self.revision == token else { return }
                let loaded = try AVAudioPlayer(contentsOf: self.audioURL(doc, doc.page))
                loaded.delegate = self
                loaded.enableRate = true
                loaded.rate = self.document?.speed ?? 1
                loaded.currentTime = min(self.time, max(0, loaded.duration - 0.05))
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                self.player = loaded
                self.duration = loaded.duration
                self.sentences = ReaderSpan.map(timings.sentenceTimings ?? [], to: self.pageText)
                self.isLoading = false
                if self.wantsPlayback { self.play() }
                if doc.pages.indices.contains(doc.page + 1) {
                    // Only one page ahead: audio lives on disk, not in a growing memory queue.
                    Task { [weak self] in _ = try? await self?.prepare(doc, page: doc.page + 1) }
                }
            } catch {
                guard self.revision == token else { return }
                self.isLoading = false
                if !Task.isCancelled { self.message = error.localizedDescription }
            }
        }
    }

    private func prepare(_ doc: ReaderDocument, page: Int) async throws -> ReaderTimings {
        guard document?.id == doc.id else { throw CancellationError() }
        if let task = generation[page] { return try await task.value }
        let audio = audioURL(doc, page), timing = timingURL(doc, page)
        if FileManager.default.fileExists(atPath: audio.path),
           let data = try? Data(contentsOf: timing),
           let cached = try? JSONDecoder().decode(ReaderTimings.self, from: data) { return cached }
        let task = Task { try await ReaderAudioService().generate(text: doc.pages[page], audioURL: audio, timingURL: timing) }
        generation[page] = task
        let token = generationRevision
        do {
            let result = try await task.value
            if generationRevision == token { generation[page] = nil }
            return result
        } catch {
            if generationRevision == token { generation[page] = nil }
            throw error
        }
    }

    func pause() {
        wantsPlayback = false
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
        if let player { time = player.currentTime }
        savePosition()
    }

    func seek(_ value: Double) {
        time = min(max(0, value), duration)
        player?.currentTime = time
        updateHighlight()
        savePosition()
    }

    func setSpeed(_ speed: Float) {
        document?.speed = speed
        player?.rate = speed
        savePosition()
    }

    func goToPage(_ page: Int, autoplay: Bool = false) {
        guard let doc = document, doc.pages.indices.contains(page) else { return }
        let resume = autoplay || isPlaying || wantsPlayback
        pause()
        revision = UUID()
        loadTask?.cancel()
        isLoading = false
        player = nil
        sentences = []
        activeSentence = nil
        duration = 0
        time = 0
        document?.page = page
        document?.position = 0
        savePosition()
        if resume { play() }
    }

    func savePosition() {
        guard var doc = document else { return }
        doc.position = time
        doc.updated = Date()
        document = doc
        if let index = documents.firstIndex(where: { $0.id == doc.id }) { documents[index] = doc }
        do {
            let position = Position(page: doc.page, position: time, speed: doc.speed, updated: doc.updated)
            try JSONEncoder().encode(position).write(to: folder(doc.id).appendingPathComponent("position.json"), options: .atomic)
            lastSaved = Date()
        } catch { message = "Listening position could not be saved: \(error.localizedDescription)" }
    }

    func delete(_ doc: ReaderDocument) {
        if doc.id == document?.id {
            close()
            revision = UUID()
            loadTask?.cancel()
            generation.values.forEach { $0.cancel() }
            generation.removeAll()
        }
        do {
            try FileManager.default.removeItem(at: folder(doc.id))
            documents.removeAll { $0.id == doc.id }
        } catch { message = "Could not delete this document: \(error.localizedDescription)" }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.time = player.currentTime
                self.updateHighlight()
                if Date().timeIntervalSince(self.lastSaved) >= 5 { self.savePosition() }
            }
        }
    }

    private func updateHighlight() {
        activeSentence = sentences.first(where: { time >= $0.start && time < $0.end })?.id
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, player === self.player else { return }
            if flag, let doc = self.document, doc.page + 1 < doc.pages.count {
                self.goToPage(doc.page + 1, autoplay: true)
            } else {
                self.pause()
                if !flag { self.message = "Audio playback stopped unexpectedly. Please retry." }
            }
        }
    }
}
