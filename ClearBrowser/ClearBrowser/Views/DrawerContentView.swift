import SwiftUI
import PhotosUI

struct DrawerContentView: View {
    @ObservedObject var viewModel: HomeViewModel
    
    // Profile editing state
    @State private var editedDisplayName: String = ""
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var selectedItemForInfo: BrowserItem?
    @State private var searchText: String = ""

    private enum BookmarkFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case favorites = "Favorites"
        var id: Self { self }
        var icon: String {
            switch self {
            case .all: return "bookmark.fill"
            case .favorites: return "star.fill"
            }
        }
    }
    @State private var bookmarkFilter: BookmarkFilter = .all

    var body: some View {
        switch viewModel.selectedDrawer {
        case .bookmarks:
            VStack(spacing: 0) {
                Picker("Filter", selection: $bookmarkFilter) {
                    ForEach(BookmarkFilter.allCases) { filter in
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                            Text(filter.rawValue)
                        }
                        .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                if bookmarkFilter == .all {
                    drawerList(title: "All Bookmarks", items: viewModel.bookmarks, onAdd: viewModel.addBookmark, onOpen: viewModel.openBookmark, onDelete: viewModel.removeBookmark)
                } else {
                    drawerList(title: "Favorited Pages", items: viewModel.favorites, onAdd: viewModel.addFavorite, onOpen: viewModel.openFavorite, onDelete: viewModel.removeFavorite)
                }
            }
            .onAppear { searchText = "" }
            
        case .history:
            drawerList(title: "Recent History", items: viewModel.history, onAdd: nil, onOpen: viewModel.openHistory, onDelete: viewModel.removeHistoryItem, onClear: viewModel.clearHistory)
                .onAppear { searchText = "" }
            
        case .settings:
            settingsContent
            
        case .none:
            EmptyView()
        }
    }

    // MARK: - Reusable List Builder
    @ViewBuilder
    private func drawerList(
        title: String,
        items: [BrowserItem],
        onAdd: (() -> Void)?,
        onOpen: @escaping (BrowserItem) -> Void,
        onDelete: @escaping (BrowserItem) -> Void,
        onClear: (() -> Void)? = nil
    ) -> some View {
        let filteredItems = items.filter { item in
            searchText.isEmpty || 
            item.title.lowercased().contains(searchText.lowercased()) ||
            item.url.absoluteString.lowercased().contains(searchText.lowercased())
        }
        
        VStack(alignment: .leading, spacing: 16) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search title or URL", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let onClear = onClear {
                    Button("Clear") { withAnimation { onClear() } }.buttonStyle(.bordered)
                }
                if let onAdd = onAdd {
                    Button(action: onAdd) { Image(systemName: "plus") }.buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 20)

            if filteredItems.isEmpty {
                Text(searchText.isEmpty ? "No items here." : "No results found.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredItems) { item in
                        rowView(for: item, onOpen: onOpen, onDelete: onDelete)
                    }
                }
                .listStyle(.plain)
            }
        }
        .alert(item: $selectedItemForInfo) { item in
            Alert(
                title: Text("Item Info"),
                message: Text("Title: \(item.title)\nURL: \(item.url.absoluteString)"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func rowView(for item: BrowserItem, onOpen: @escaping (BrowserItem) -> Void, onDelete: @escaping (BrowserItem) -> Void) -> some View {
        Button(action: { onOpen(item) }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(item.url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { withAnimation { onDelete(item) } } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button { selectedItemForInfo = item } label: {
                Label("Show Info", systemImage: "info.circle")
            }
            Button(role: .destructive) { withAnimation { onDelete(item) } } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Settings Content
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SettingsSection(title: "Search") {
                    Picker("Search Engine", selection: $viewModel.defaultSearchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsSection(title: "Appearance") {
                    Picker("Toolbar Position", selection: $viewModel.toolbarPosition) {
                        ForEach(ToolbarPosition.allCases) { pos in
                            Text(pos.title).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsSection(title: "Auto-Scroll") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Label("Scroll Speed", systemImage: "gauge.with.needle.fill")
                            Spacer()
                            Text(String(format: "%.2f", viewModel.autoScrollSpeed)).monospacedDigit()
                        }
                        Slider(value: $viewModel.autoScrollSpeed, in: 0.1...1.0)
                    }
                }

                if viewModel.isLoggedIn {
                    SettingsSection(title: "AI Configuration") {
                        SecureField("OpenAI API Key", text: $viewModel.openAIKey)
                            .textInputAutocapitalization(.none)
                            .autocorrectionDisabled(true)
                        Text("Stored securely in Keychain.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }

                SettingsSection(title: viewModel.isLoggedIn ? "Profile" : "Account") {
                    if viewModel.isLoggedIn {
                        profileSection
                    } else {
                        loginPrompt
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.horizontal, 20)
        }
    }

    private var profileSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Profile Header Card
            VStack(spacing: Theme.Spacing.md) {
                // Profile Picture with Edit Overlay
                ZStack(alignment: .bottomTrailing) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        if let url = viewModel.profileImageUrl {
                            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
                                .frame(width: 100, height: 100).clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill").resizable()
                                .frame(width: 100, height: 100).foregroundColor(Theme.accent)
                        }
                    }
                    
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Theme.accent)
                        .clipShape(Circle())
                        .offset(x: 8, y: 8)
                }
                .onChange(of: photoPickerItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            viewModel.uploadProfilePicture(image)
                        }
                    }
                }
                
                // Display Name
                if let displayName = viewModel.displayName {
                    Text(displayName)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
                
                // Email
                if let email = viewModel.currentUserEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
            
            // Display Name Edit
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Display Name", systemImage: "pencil.circle.fill")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("Enter display name", text: $editedDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { editedDisplayName = viewModel.displayName ?? "" }
                    
                    Button(action: { viewModel.updateProfile(name: editedDisplayName) }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                    }
                    .disabled(editedDisplayName == viewModel.displayName || editedDisplayName.isEmpty)
                }
            }
            
            Divider()
            
            // Profile Stats (optional)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Profile Stats", systemImage: "chart.bar.xaxis")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                HStack(spacing: Theme.Spacing.lg) {
                    VStack(alignment: .center, spacing: 4) {
                        Text("\(viewModel.bookmarks.count)")
                            .font(.headline)
                            .foregroundColor(Theme.accent)
                        Text("Bookmarks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .center, spacing: 4) {
                        Text("\(viewModel.favorites.count)")
                            .font(.headline)
                            .foregroundColor(Theme.accent)
                        Text("Favorites")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .center, spacing: 4) {
                        Text("\(viewModel.history.count)")
                            .font(.headline)
                            .foregroundColor(Theme.accent)
                        Text("History")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            Button(role: .destructive, action: viewModel.logout) {
                Label("Log Out", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var loginPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Sync your bookmarks and history across devices.")
                .font(.footnote).foregroundColor(.secondary)
            Button(action: { viewModel.authSheet = .login }) {
                Label("Sign In / Register", systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Theme.accent).foregroundColor(.white).cornerRadius(8)
            }
        }
    }
}