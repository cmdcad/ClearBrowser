import SwiftUI
import WebKit
import Foundation
import UIKit


class StorageManager {
    static let shared = StorageManager()
    
    private let bookmarksKey = "bookmarks"
    private let historyKey = "history"
    private let fileManager = FileManager.default
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private init() {}
    
    // MARK: - Bookmarks
    func saveBookmarks(_ bookmarks: [Bookmark]) {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }
    
    func loadBookmarks() -> [Bookmark] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([Bookmark].self, from: data)
        } catch {
            print("Failed to load bookmarks: \(error)")
            return []
        }
    }
    
    // MARK: - History
    func saveHistory(_ history: [HistoryItem]) {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    func loadHistory() -> [HistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
            return []
        }
    }
    
    // MARK: - Page Content (for future AI extraction)
    func savePageContent(_ content: PageContent) {
        do {
            let data = try JSONEncoder().encode(content)
            let filename = content.url.host ?? "page"
            let fileURL = documentsDirectory.appendingPathComponent("\(filename)-\(Date().timeIntervalSince1970).json")
            try data.write(to: fileURL)
        } catch {
            print("Failed to save page content: \(error)")
        }
    }
    
    func loadPageContent(for url: URL) -> PageContent? {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: nil
            )
            
            let targetHost = url.host ?? ""
            if let file = files.first(where: { $0.lastPathComponent.contains(targetHost) }) {
                let data = try Data(contentsOf: file)
                return try JSONDecoder().decode(PageContent.self, from: data)
            }
        } catch {
            print("Failed to load page content: \(error)")
        }
        
        return nil
    }
    
    func clearOldPageContent() {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            
            let now = Date()
            let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
            
            for file in files where file.lastPathComponent.hasSuffix(".json") {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let modificationDate = attributes[.modificationDate] as? Date,
                   modificationDate < sevenDaysAgo {
                    try fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("Failed to clear old page content: \(error)")
        }
    }
}