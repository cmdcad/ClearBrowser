import SwiftUI

struct DrawerContentView: View {
    @ObservedObject var viewModel: HomeViewModel
    
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
                    drawerList(title: "All Sites", items: viewModel.bookmarks, onAdd: viewModel.addBookmark, onOpen: viewModel.openBookmark, onDelete: viewModel.removeBookmark, showBlockedIndicator: true)
                } else {
                    drawerList(title: "Favorited Pages", items: viewModel.favorites, onAdd: viewModel.addFavorite, onOpen: viewModel.openFavorite, onDelete: viewModel.removeFavorite, showBlockedIndicator: true)
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
        onClear: (() -> Void)? = nil,
        showBlockedIndicator: Bool = false
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
                        rowView(for: item, onOpen: onOpen, onDelete: onDelete, showBlockedIndicator: showBlockedIndicator)
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
    private func rowView(for item: BrowserItem, onOpen: @escaping (BrowserItem) -> Void, onDelete: @escaping (BrowserItem) -> Void, showBlockedIndicator: Bool) -> some View {
        Button(action: { onOpen(item) }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty || item.title == "Untitled" ? (item.url.host ?? item.url.absoluteString) : item.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text(item.url.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if showBlockedIndicator && viewModel.isBrowserItemForcedInApp(item) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
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
            if let entity = viewModel.forceableEntity(from: item.url) {
                Button {
                    withAnimation { viewModel.toggleForceInApp(for: item) }
                } label: {
                    Label("Always open \(entity) in app", systemImage: viewModel.isBrowserItemForcedInApp(item) ? "checkmark.circle.fill" : "circle")
                }
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
                    accountSection
                }
            }
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.horizontal, 20)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(viewModel.isLoggedIn
                 ? "Open your dedicated profile view to update your name, photo, and account details."
                 : "Open the account center to sign in, register, and manage your profile in dedicated screens.")
                .font(.footnote)
                .foregroundColor(.secondary)

            Button(action: {
                viewModel.accountSheet = viewModel.isLoggedIn ? .profile : .hub
            }) {
                Label(viewModel.isLoggedIn ? "Open Profile" : "Open Account Center",
                      systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Theme.accent).foregroundColor(.white).cornerRadius(8)
            }
        }
    }
}
