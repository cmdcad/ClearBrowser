import Foundation
import FirebaseFirestore
import FirebaseAuth

struct BrowserSettings: Codable {
    var defaultSearchEngine: SearchEngine = .bing
    var autoScrollSpeed: Double = 0.35
    var lastOpenedURL: String? = nil
    var tabs: [BrowserTab]? = nil
    var activeTabID: UUID? = nil
    var darkModeEnabled: Bool = false
    var invertColorsEnabled: Bool = false
    var highlightVerseEnabled: Bool = true
    var showTextConfirmation: Bool = true
}

struct UserProfileSnapshot: Codable {
    var email: String?
    var displayName: String?
    var remotePhotoURL: String?
    var localPhotoPath: String?
}

final class StorageManager {
    private enum Key {
        static let bookmarks = "ClearBrowser.bookmarks"
        static let history = "ClearBrowser.history"
        static let favorites = "ClearBrowser.favorites"
        static let blockedSchemes = "ClearBrowser.blockedSchemes"
        static let settings = "ClearBrowser.settings"
        static let profile = "ClearBrowser.profile"
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let db = Firestore.firestore()

    // MARK: - Local Storage (UserDefaults)

    func loadBookmarks() -> [BrowserItem] {
        guard let data = defaults.data(forKey: Key.bookmarks),
              let items = try? decoder.decode([BrowserItem].self, from: data) else {
            return []
        }
        return items
    }

    func saveBookmarks(_ items: [BrowserItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: Key.bookmarks)
    }

    func loadHistory() -> [BrowserItem] {
        guard let data = defaults.data(forKey: Key.history),
              let items = try? decoder.decode([BrowserItem].self, from: data) else {
            return []
        }
        return items
    }

    func saveHistory(_ items: [BrowserItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: Key.history)
    }

    func loadFavorites() -> [BrowserItem] {
        guard let data = defaults.data(forKey: Key.favorites),
              let items = try? decoder.decode([BrowserItem].self, from: data) else { return [] }
        return items
    }

    func saveFavorites(_ items: [BrowserItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: Key.favorites)
    }

    func loadSettings() -> BrowserSettings {
        guard let data = defaults.data(forKey: Key.settings),
              let settings = try? decoder.decode(BrowserSettings.self, from: data) else {
            return BrowserSettings()
        }
        return settings
    }

    func saveSettings(_ settings: BrowserSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Key.settings)
    }

    func loadBlockedSchemes() -> [String] {
        guard let data = defaults.data(forKey: Key.blockedSchemes),
              let schemes = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return schemes
    }

    func saveBlockedSchemes(_ schemes: [String]) {
        guard let data = try? encoder.encode(schemes) else { return }
        defaults.set(data, forKey: Key.blockedSchemes)
    }

    func loadProfileSnapshot() -> UserProfileSnapshot? {
        guard let data = defaults.data(forKey: Key.profile),
              let profile = try? decoder.decode(UserProfileSnapshot.self, from: data) else {
            return nil
        }
        return profile
    }

    func saveProfileSnapshot(_ profile: UserProfileSnapshot?) {
        guard let profile else {
            defaults.removeObject(forKey: Key.profile)
            return
        }

        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: Key.profile)
    }

    func saveProfileImageData(_ data: Data, filename: String = "profile-image.jpg") -> String? {
        guard let url = profileImageURL(filename: filename) else { return nil }

        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            print("Error saving profile image locally: \(error.localizedDescription)")
            return nil
        }
    }

    func deleteProfileImage(at path: String?) {
        guard let path else { return }

        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        } catch {
            print("Error deleting profile image: \(error.localizedDescription)")
        }
    }

    private func profileImageURL(filename: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(filename)
    }

    // MARK: - Firebase Sync

    func saveEncryptedAIKey(_ encryptedKey: EncryptedAIKey, userID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("users").document(userID).setData([
                "aiKey": [
                    "version": 1,
                    "salt": encryptedKey.salt,
                    "ciphertext": encryptedKey.ciphertext
                ]
            ], merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func loadEncryptedAIKey(userID: String) async throws -> EncryptedAIKey? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<EncryptedAIKey?, Error>) in
            db.collection("users").document(userID).getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let fields = snapshot?.data()?["aiKey"] as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }

                guard let version = fields["version"] as? Int,
                      version == 1,
                      let salt = fields["salt"] as? String,
                      let ciphertext = fields["ciphertext"] as? String else {
                    continuation.resume(throwing: AIKeyEncryptionError.invalidEncryptedData)
                    return
                }

                continuation.resume(returning: EncryptedAIKey(salt: salt, ciphertext: ciphertext))
            }
        }
    }

    func deleteEncryptedAIKey(userID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("users").document(userID).setData(["aiKey": FieldValue.delete()], merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func syncBookmarksToFirebase(_ items: [BrowserItem]) {
        guard let user = Auth.auth().currentUser else { return }
        
        let userRef = db.collection("users").document(user.uid)
        
        do {
            let booksmarksData = try items.map { item -> [String: Any] in
                return [
                    "id": item.id.uuidString,
                    "title": item.title,
                    "url": item.url.absoluteString,
                    "timestamp": item.timestamp
                ]
            }
            
            userRef.setData(["bookmarks": booksmarksData], merge: true) { error in
                if let error = error {
                    print("Error syncing bookmarks to Firebase: \(error.localizedDescription)")
                } else {
                    print("Bookmarks synced to Firebase successfully")
                }
            }
        } catch {
            print("Error encoding bookmarks: \(error.localizedDescription)")
        }
    }
    
    func syncFavoritesToFirebase(_ items: [BrowserItem]) {
        guard let user = Auth.auth().currentUser else { return }
        
        let userRef = db.collection("users").document(user.uid)
        
        do {
            let favoritesData = try items.map { item -> [String: Any] in
                return [
                    "id": item.id.uuidString,
                    "title": item.title,
                    "url": item.url.absoluteString,
                    "timestamp": item.timestamp
                ]
            }
            
            userRef.setData(["favorites": favoritesData], merge: true) { error in
                if let error = error {
                    print("Error syncing favorites to Firebase: \(error.localizedDescription)")
                } else {
                    print("Favorites synced to Firebase successfully")
                }
            }
        } catch {
            print("Error encoding favorites: \(error.localizedDescription)")
        }
    }
    
    func syncHistoryToFirebase(_ items: [BrowserItem]) {
        guard let user = Auth.auth().currentUser else { return }
        
        let userRef = db.collection("users").document(user.uid)
        
        do {
            let historyData = try items.map { item -> [String: Any] in
                return [
                    "id": item.id.uuidString,
                    "title": item.title,
                    "url": item.url.absoluteString,
                    "timestamp": item.timestamp
                ]
            }
            
            userRef.setData(["history": historyData], merge: true) { error in
                if let error = error {
                    print("Error syncing history to Firebase: \(error.localizedDescription)")
                } else {
                    print("History synced to Firebase successfully")
                }
            }
        } catch {
            print("Error encoding history: \(error.localizedDescription)")
        }
    }
    
    func loadBookmarksFromFirebase(completion: @escaping ([BrowserItem]) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion([])
            return
        }
        
        db.collection("users").document(user.uid).getDocument { snapshot, error in
            if let error = error {
                print("Error loading bookmarks from Firebase: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = snapshot?.data(),
                  let bookmarksData = data["bookmarks"] as? [[String: Any]] else {
                completion([])
                return
            }
            
            let bookmarks = bookmarksData.compactMap { dict -> BrowserItem? in
                guard let id = dict["id"] as? String,
                      let title = dict["title"] as? String,
                      let urlString = dict["url"] as? String,
                      let url = URL(string: urlString),
                      let timestamp = dict["timestamp"] as? Timestamp else {
                    return nil
                }
                
                return BrowserItem(
                    id: UUID(uuidString: id) ?? UUID(),
                    title: title,
                    url: url,
                    timestamp: timestamp.dateValue()
                )
            }
            
            completion(bookmarks)
        }
    }
    
    func loadFavoritesFromFirebase(completion: @escaping ([BrowserItem]) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion([])
            return
        }
        
        db.collection("users").document(user.uid).getDocument { snapshot, error in
            if let error = error {
                print("Error loading favorites from Firebase: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = snapshot?.data(),
                  let favoritesData = data["favorites"] as? [[String: Any]] else {
                completion([])
                return
            }
            
            let favorites = favoritesData.compactMap { dict -> BrowserItem? in
                guard let id = dict["id"] as? String,
                      let title = dict["title"] as? String,
                      let urlString = dict["url"] as? String,
                      let url = URL(string: urlString),
                      let timestamp = dict["timestamp"] as? Timestamp else {
                    return nil
                }
                
                return BrowserItem(
                    id: UUID(uuidString: id) ?? UUID(),
                    title: title,
                    url: url,
                    timestamp: timestamp.dateValue()
                )
            }
            
            completion(favorites)
        }
    }
    
    func loadHistoryFromFirebase(completion: @escaping ([BrowserItem]) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion([])
            return
        }
        
        db.collection("users").document(user.uid).getDocument { snapshot, error in
            if let error = error {
                print("Error loading history from Firebase: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = snapshot?.data(),
                  let historyData = data["history"] as? [[String: Any]] else {
                completion([])
                return
            }
            
            let history = historyData.compactMap { dict -> BrowserItem? in
                guard let id = dict["id"] as? String,
                      let title = dict["title"] as? String,
                      let urlString = dict["url"] as? String,
                      let url = URL(string: urlString),
                      let timestamp = dict["timestamp"] as? Timestamp else {
                    return nil
                }
                
                return BrowserItem(
                    id: UUID(uuidString: id) ?? UUID(),
                    title: title,
                    url: url,
                    timestamp: timestamp.dateValue()
                )
            }
            
            completion(history)
        }
    }
}
