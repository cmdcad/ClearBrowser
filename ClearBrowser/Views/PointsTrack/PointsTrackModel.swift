import Foundation
import Combine

@MainActor
final class PointsTrackModel: ObservableObject {
    @Published private(set) var categories: [PointsCategory] = []
    @Published var error: String?
    private var readable = true
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PointsTrack", isDirectory: true).appendingPathComponent("categories.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let decoded = try JSONDecoder().decode([PointsCategory].self, from: Data(contentsOf: self.fileURL))
            guard decoded.allSatisfy(\.isValid), Set(decoded.map(\.id)).count == decoded.count else {
                throw NSError(domain: "PointsTrack", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved categories contain invalid data."])
            }
            categories = decoded
        } catch {
            readable = false
            self.error = "Could not load your saved categories. Your saved file has been preserved. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(_ category: PointsCategory) -> Bool {
        guard category.isValid else { error = "Enter a name, nonnegative point balances, and a positive reward conversion."; return false }
        var updated = categories
        if let index = updated.firstIndex(where: { $0.id == category.id }) { updated[index] = category }
        else { updated.append(category) }
        return persist(updated)
    }

    func delete(_ category: PointsCategory) { _ = persist(categories.filter { $0.id != category.id }) }

    private func persist(_ updated: [PointsCategory]) -> Bool {
        guard readable else { error = "The saved library could not be read. Restart after recovering its file to avoid overwriting your data."; return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
            categories = updated
            return true
        } catch { self.error = "Changes could not be saved: \(error.localizedDescription)"; return false }
    }
}
