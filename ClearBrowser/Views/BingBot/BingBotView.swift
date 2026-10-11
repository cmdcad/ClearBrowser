import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum BingDestination: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", browser = "Browser", queries = "Queries", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: return "gauge.open.with.lines.needle.33percent"
        case .browser: return "globe"
        case .queries: return "text.word.spacing"
        case .settings: return "gearshape.fill"
        }
    }
}

private struct BingJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct BingBotView: View {
    var onClose: () -> Void = {}
    @StateObject private var model = BingBotModel()
    @StateObject private var browser = BingBotBrowser()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: BingDestination = .dashboard
    @State private var showAddressRow = false
    @State private var startup = true
    @State private var startupRemaining = 3
    @State private var startupDuration = 3
    @State private var showRunAgain = false
    @State private var clearSession = false
    @State private var clearLibrary = false
    @State private var resetToday = false
    @State private var resetApp = false
    @State private var searchFilter = ""
    @State private var selectedQueries = Set<String>()
    @State private var editingQuery: String?
    @State private var editedText = ""
    @State private var editWarning: String?
    @State private var prefix = "what is"
    @State private var prefixPreview: [String] = []
    @State private var showPrefixPreview = false
    @State private var exporting = false
    @State private var document = BingJSONDocument(data: Data())
    @State private var importing = false
    @State private var imported: BingBackup?
    @State private var confirmReplace = false
    #if os(macOS)
    @State private var closeCountdown: Int?
    @State private var closeTask: Task<Void, Never>?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            #if os(macOS)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(BingDestination.allCases) { item in
                        Button { destination = item } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(destination == item ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(12).frame(width: 180)
                Divider()
                content
            }
            #else
            content
            HStack(spacing: 0) {
                ForEach(BingDestination.allCases) { item in
                    Button { destination = item } label: {
                        VStack(spacing: 5) { Image(systemName: item.symbol).font(.system(size: 20)); Text(item.rawValue).font(.caption2) }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(destination == item ? Color.blue : Color.secondary)
                            .background(destination == item ? Color.blue.opacity(0.08) : .clear)
                    }.buttonStyle(.plain).accessibilityAddTraits(destination == item ? .isSelected : [])
                }
            }.background(.bar)
            #endif
        }
        .background(Self.pageBackground)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast).font(.footnote).multilineTextAlignment(.center).padding(12)
                    .foregroundStyle(.white).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16).padding(.bottom, 70).allowsHitTesting(false)
            }
        }
        .overlay { if startup { startupOverlay } }
        .task {
            browser.onSearchCompleted = { [weak model] query in model?.searchCompleted(query: query) }
            startupDuration = model.settings.startupCountdownSeconds; startupRemaining = startupDuration
            while startup && startupRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                startupRemaining = max(0, startupRemaining - 1)
            }
            startup = false
            if model.state.status == .completed { showRunAgain = true }
        }
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            if phase == .active { model.refreshDay() }
            #else
            if phase == .active { model.refreshDay() }
            #endif
        }
        .onDisappear {
            browser.stopLoading()
            #if os(macOS)
            closeTask?.cancel()
            #endif
        }
        .onChange(of: model.completionSerial) { _, _ in
            #if os(macOS)
            if model.settings.autoCloseOnComplete { scheduleClose() }
            #endif
        }
        .alert("Run again?", isPresented: $showRunAgain) {
            Button("Dismiss", role: .cancel) {}
            Button("Reset Today") { model.resetProgress(); browser.resetSearchTracking(); destination = .browser }
        } message: { Text("Today’s search target is already complete. Resetting starts a new daily tally; it does not confirm external rewards.") }
        .alert("Clear Browser Session?", isPresented: $clearSession) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Session", role: .destructive) { browser.resetSession(); model.showToast("Browser session cleared.") }
        } message: { Text("Sign out of websites and clear BingBot’s saved website data. Your queries and preferences are kept.") }
        .alert("Clear Saved Queries?", isPresented: $clearLibrary) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { model.deleteQueries(Set(model.queries)); selectedQueries = [] }
        }
        .alert("Reset Today’s Progress?", isPresented: $resetToday) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetProgress(); browser.resetSearchTracking() }
        }
        .alert("Reset BingBot Data?", isPresented: $resetApp) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetData(); browser.resetSession(); selectedQueries = [] }
        } message: { Text("Only BingBot queries, preferences, and progress will be reset.") }
        .alert("BingBot", isPresented: Binding(get: { model.error != nil || browser.message != nil }, set: { if !$0 { model.error = nil; browser.message = nil } })) {
            Button("OK") { model.error = nil; browser.message = nil }
        } message: { Text(model.error ?? browser.message ?? "") }
        .sheet(isPresented: Binding(get: { editingQuery != nil }, set: { if !$0 { editingQuery = nil } })) { queryEditor }
        .sheet(isPresented: $showPrefixPreview) { prefixSheet }
        .sheet(isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } })) { importPreview }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                imported = try BingBackup.decode(Data(contentsOf: url))
            } catch { model.error = (error as? BingDataError)?.localizedDescription ?? "The backup could not be read or validated." }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "BingBot-\(BingQueries.localDate())") { result in
            switch result {
            case .success: model.showToast("App data exported.")
            case .failure: model.error = "The backup could not be exported."
            }
        }
    }

    private static var pageBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
    private var header: some View {
        HStack(spacing: 16) {
            #if os(iOS)
            Button(action: onClose) { Label("Apps", systemImage: "chevron.left").frame(minHeight: 44) }
            #endif
            Image(systemName: "magnifyingglass").font(.title2)
            VStack(alignment: .leading, spacing: 2) { Text("BingBot").font(.headline); Text("Manual Search Helper").font(.caption) }
            Spacer()
        }.foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 12)
            .background(LinearGradient(colors: [Color(red: 0.10, green: 0.45, blue: 0.91), Color(red: 0.05, green: 0.28, blue: 0.63)], startPoint: .leading, endPoint: .trailing))
    }
    @ViewBuilder private var content: some View {
        if destination == .browser { browserScreen }
        else {
            ScrollView {
                VStack(spacing: 16) {
                    switch destination {
                    case .dashboard: dashboard
                    case .queries: queriesScreen
                    case .settings: settingsScreen
                    case .browser: EmptyView()
                    }
                }.frame(maxWidth: 640).frame(maxWidth: .infinity).padding(16)
            }
        }
    }
    private var statusColor: Color {
        switch model.state.status {
        case .running: return .blue
        case .completed: return .green
        case .error: return .red
        case .exhausted: return .orange
        case .idle: return .secondary
        }
    }
    private var dashboard: some View {
        Group {
            BingPanel(title: "Status") {
                HStack {
                    Label(model.state.status.rawValue, systemImage: model.state.status == .error ? "exclamationmark.triangle.fill" : "circle.fill").foregroundStyle(statusColor)
                    Spacer()
                    Text("Manual").font(.caption.bold()).padding(7).background(Color.orange.opacity(0.12), in: Capsule())
                }
                Text("Last completed: \(model.settings.lastCompletedDate ?? "Never")").font(.caption).foregroundStyle(.secondary)
                if let query = model.state.activeQuery { Text(query).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled) }
                if let error = model.state.lastError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            BingPanel(title: "Today’s app progress") {
                HStack(spacing: 24) {
                    ZStack {
                        Circle().stroke(.blue.opacity(0.12), lineWidth: 8)
                        Circle().trim(from: 0, to: model.progress).stroke(.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .easeInOut, value: model.progress)
                        Text("\(Int(model.progress * 100))%").monospacedDigit().font(.headline)
                    }.frame(width: 90, height: 90).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(model.state.completedToday) / \(model.settings.dailyTarget)").font(.system(size: 30, weight: .bold, design: .monospaced))
                        Text("Searches completed today").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: model.progress).tint(.blue)
                    .accessibilityLabel("Searches completed today").accessibilityValue("\(model.state.completedToday) of \(model.settings.dailyTarget)")
                Text("App progress counts successful search navigations, not confirmed rewards or points.").font(.caption).foregroundStyle(.secondary)
            }
            BingPanel(title: "Search in Browser") {
                Text("Copy the next query in the Browser screen, paste it into Bing, and submit. Copying alone never changes the daily count.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Open Browser") { destination = .browser }.buttonStyle(.borderedProminent)
                if model.state.status == .exhausted {
                    Button("Add More Queries") { destination = .queries }.buttonStyle(.bordered)
                }
            }
            HStack {
                stat("Loaded", value: "\(model.settings.querySource == "custom" ? model.queries.count : max(30, model.settings.dailyTarget))")
                stat("Today", value: "\(model.state.completedToday)")
                stat("Remaining", value: "\(model.queriesRemaining)")
            }
            #if os(macOS)
            if let seconds = closeCountdown {
                BingPanel(title: "Close on completion") {
                    Text("Closing BingBot in \(seconds) seconds.")
                    Button("Cancel") { closeTask?.cancel(); closeCountdown = nil }.buttonStyle(.bordered)
                }
            }
            #endif
        }
    }
    private func stat(_ title: String, value: String) -> some View {
        BingPanel(title: title) { Text(value).font(.system(.headline, design: .monospaced)).frame(maxWidth: .infinity) }
    }
    private var browserScreen: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        guard let query = model.nextQueryToCopy() else { return }
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(query, forType: .string)
                        #else
                        UIPasteboard.general.string = query
                        #endif
                        model.showToast("Query copied. Paste it into Bing and submit.")
                    } label: {
                        Label("Copy Next Query", systemImage: "doc.on.doc").font(.caption).frame(minHeight: 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(browser.isLoading || browser.isClearingSession || model.state.completedToday >= model.settings.dailyTarget)
                    Spacer()
                    Text("\(model.state.completedToday) / \(model.settings.dailyTarget)").monospacedDigit().font(.headline)
                }
                if let copied = model.state.activeQuery {
                    Text(copied).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                // Text("Paste into Bing’s search box. Progress updates only after a new search finishes loading.")
                //     .font(.caption).foregroundStyle(.secondary)
                if model.state.completedToday >= model.settings.dailyTarget {
                    Button("Reset Today’s Progress") { resetToday = true }.font(.caption)
                }
            }.padding(.horizontal, 12).padding(.top, 8)
            if showAddressRow {
              HStack(spacing: 8) {
                Button { browser.goBack() } label: { Image(systemName: "chevron.left").frame(minWidth: 36, minHeight: 44) }
                    .disabled(!browser.canGoBack).accessibilityLabel("Back")
                TextField("HTTP or HTTPS address", text: $browser.address).font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder).onSubmit { browser.go(browser.address) }
                Button("Go") { browser.go(browser.address) }.frame(minHeight: 44)
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 36, minHeight: 44) }.accessibilityLabel("Refresh")
              }.padding(.horizontal, 12)
            }
            HStack {
                Button("Bing") { browser.go("https://www.bing.com") }
                Button("Rewards") { browser.go("https://rewards.bing.com") }
                Button("Redeem") { browser.go("https://rewards.bing.com/redeem") }
                Spacer()
                Button {
                    withAnimation { showAddressRow.toggle() }
                } label: {
                    Image(systemName: showAddressRow ? "chevron.up" : "link")
                        .frame(minWidth: 36, minHeight: 44)
                }
                .accessibilityLabel(showAddressRow ? "Hide address bar" : "Show address bar")
                .accessibilityValue(showAddressRow ? "Expanded" : "Collapsed")
                Button { clearSession = true } label: { Image(systemName: "trash").frame(minWidth: 36, minHeight: 44) }.accessibilityLabel("Clear browser session")
            }.font(.caption).padding(.horizontal, 12)
            if browser.isLoading { ProgressView(value: browser.progress).progressViewStyle(.linear) }
            BingBotWebView(webView: browser.webView).id(ObjectIdentifier(browser.webView))
                .allowsHitTesting(!browser.isClearingSession)
            Text("Today’s count updates after a new Bing search finishes loading.")
                .font(.caption2).foregroundStyle(.secondary).padding(8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var queriesScreen: some View {
        Group {
            BingPanel(title: "Query source") {
                sourcePicker
                Text("Switching sources preserves your custom library. Changes apply to the next run.").font(.caption).foregroundStyle(.secondary)
            }
            BingPanel(title: "Paste & parse") {
                Text("Paste a paragraph, a block of words, or a list of phrases. Choose how to split it, preview the results, then add them to your library.").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { model.input.draftText }, set: { model.updateInput(text: $0) }))
                    .frame(minHeight: 150).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
                    .accessibilityLabel("Temporary query input")
                Picker("Parsing Mode", selection: Binding(get: { model.input.parsingMode }, set: { model.updateInput(mode: $0) })) {
                    ForEach(BingParsingMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                ViewThatFits(in: .horizontal) {
                    HStack { pasteButton; addButton; Button("Clear Input") { model.clearInput() } }
                    VStack(alignment: .leading) { pasteButton; addButton; Button("Clear Input") { model.clearInput() } }
                }
                ForEach(model.input.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                Text("Parsed: \(model.input.parsedCount) · Repeated: \(model.input.duplicateWithinInputCount) · Already saved: \(model.input.alreadySavedCount) · New: \(model.input.newQueryCount)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if !model.input.previewQueries.isEmpty {
                    Text("Exact entries to add").font(.caption.bold())
                    ForEach(Array(model.input.previewQueries.prefix(100).enumerated()), id: \.offset) { _, query in Text(query).font(.subheadline).textSelection(.enabled) }
                    if model.input.previewQueries.count > 100 { Text("Showing first 100 of \(model.input.newQueryCount) entries.").font(.caption) }
                }
            }
            BingPanel(title: "Saved library · \(model.queries.count)") {
                TextField("Filter saved queries", text: $searchFilter).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Select All") { selectedQueries = Set(filteredQueries) }
                    Button("Delete Selected (\(selectedQueries.count))", role: .destructive) {
                        model.deleteQueries(selectedQueries); selectedQueries = []
                    }.disabled(selectedQueries.isEmpty)
                }.font(.caption)
                if model.queries.isEmpty { Text("No saved queries. Paste text above to begin.").foregroundStyle(.secondary) }
                LazyVStack(spacing: 8) {
                    ForEach(filteredQueries, id: \.self) { query in
                        HStack {
                            Button {
                                if selectedQueries.contains(query) { selectedQueries.remove(query) } else { selectedQueries.insert(query) }
                            } label: { Image(systemName: selectedQueries.contains(query) ? "checkmark.square.fill" : "square").frame(width: 44, height: 44) }
                                .accessibilityLabel("Select query").accessibilityValue(selectedQueries.contains(query) ? "Selected" : "Not selected")
                            Text(query).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            Button { editingQuery = query; editedText = query; editWarning = nil } label: { Image(systemName: "pencil").frame(width: 36, height: 44) }.accessibilityLabel("Edit query")
                            Button(role: .destructive) { model.deleteQueries([query]); selectedQueries.remove(query) } label: { Image(systemName: "trash").frame(width: 36, height: 44) }.accessibilityLabel("Delete query")
                        }
                        Divider()
                    }
                }
                Button("Clear Library", role: .destructive) { clearLibrary = true }
            }
            BingPanel(title: "Optional prefix") {
                Picker("Preset", selection: $prefix) {
                    ForEach(["what is", "how to", "best", "define", "why does"], id: \.self) { Text($0).tag($0) }
                    if !["what is", "how to", "best", "define", "why does"].contains(prefix) { Text("Custom").tag(prefix) }
                }
                TextField("Custom prefix", text: $prefix).textFieldStyle(.roundedBorder)
                Button("Preview Selected Queries") {
                    prefixPreview = BingQueries.unique(model.queries.filter { selectedQueries.contains($0) }.map { BingQueries.normalize(prefix) + " " + $0 })
                        .filter { candidate in !model.queries.contains { BingQueries.key($0) == BingQueries.key(candidate) } }
                    showPrefixPreview = true
                }.disabled(selectedQueries.isEmpty || BingQueries.normalize(prefix).isEmpty)
                Text("Prefixes apply to whole selected queries. Original queries remain in the library.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var filteredQueries: [String] { model.queries.filter { searchFilter.isEmpty || $0.localizedCaseInsensitiveContains(searchFilter) } }
    private var pasteButton: some View {
        Button("Paste from Clipboard") {
            #if os(macOS)
            let text = NSPasteboard.general.string(forType: .string)
            #else
            let text = UIPasteboard.general.string
            #endif
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { model.showToast("Clipboard is empty."); return }
            model.updateInput(text: text)
        }.buttonStyle(.bordered)
    }
    private var addButton: some View {
        Button("Add Queries") { model.addInput() }.buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(!model.input.isValid)
    }
    private var sourcePicker: some View {
        Picker("Query Source", selection: setting(\.querySource)) {
            Text("Custom Library").tag("custom"); Text("Alphanumeric").tag("alphanumeric")
        }.pickerStyle(.segmented)
    }
    private func setting<Value>(_ path: WritableKeyPath<BingSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: path] }, set: { value in model.updateSettings { $0[keyPath: path] = value } })
    }
    private var settingsScreen: some View {
        Group {
            BingPanel(title: "Daily target") {
                Stepper("Daily app target: \(model.settings.dailyTarget)", value: setting(\.dailyTarget), in: 1...100)
                Text("This is the app’s search target, not a guaranteed external rewards allocation.").font(.caption).foregroundStyle(.secondary)
                Stepper("Startup countdown: \(model.settings.startupCountdownSeconds)s", value: setting(\.startupCountdownSeconds), in: 3...5)
            }
            BingPanel(title: "Completion") {
                Toggle("Show completion notifications", isOn: setting(\.showNotifications)).tint(.blue)
                Text("Allow notifications to receive a daily target completion alert. BingBot works without permission.").font(.caption).foregroundStyle(.secondary)
                Button("Enable Notifications") { model.requestNotifications() }.buttonStyle(.bordered)
                #if os(macOS)
                Toggle("Close on completion (5-second countdown)", isOn: setting(\.autoCloseOnComplete))
                #endif
            }
            BingPanel(title: "Query preferences") {
                Picker("Default Parsing", selection: setting(\.defaultParsingMode)) { ForEach(BingParsingMode.allCases) { Text($0.title).tag($0) } }
                sourcePicker
                Button("Clear Saved Queries", role: .destructive) { clearLibrary = true }
            }
            BingPanel(title: "Data management") {
                Text("Last completed: \(model.settings.lastCompletedDate ?? "Never")").font(.caption)
                Button("Reset Today’s Progress", role: .destructive) { resetToday = true }
                Button("Export App Data") {
                    do { document = BingJSONDocument(data: try model.exportData()); exporting = true }
                    catch { model.error = "App data could not be exported." }
                }.buttonStyle(.bordered)
                Button("Import App Data") { importing = true }.buttonStyle(.bordered)
                Button("Reset App Data", role: .destructive) { resetApp = true }
                Text("Backups contain saved queries, preferences, and progress only. Website login data and raw paste drafts are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            BingPanel(title: "About") {
                Text("BingBot · Version 1.0.0").font(.headline)
                Text("Part of the ReloCalc Suite").font(.caption).foregroundStyle(.secondary)
                Text("Query editing works offline. Searches need internet. Website login sessions are saved until you clear them or the website expires them.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var queryEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Query").font(.headline)
            TextField("Query", text: $editedText).textFieldStyle(.roundedBorder)
            if let editWarning { Text(editWarning).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { editingQuery = nil }
                Spacer()
                Button("Save") {
                    guard let original = editingQuery else { return }
                    do {
                        try model.editQuery(original, replacement: editedText)
                        selectedQueries.remove(original); editingQuery = nil
                    } catch { editWarning = (error as? BingDataError)?.localizedDescription ?? "This query could not be saved." }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(minWidth: 280, idealWidth: 420)
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
    private var prefixSheet: some View {
        VStack(spacing: 16) {
            Text("Prefix Preview · \(prefixPreview.count) new queries").font(.headline)
            if prefixPreview.contains(where: { $0.count > 500 }) {
                Text("Some prefixed queries exceed 500 characters. Shorten the prefix or selected queries.").font(.caption).foregroundStyle(.orange)
            }
            ScrollView { VStack(alignment: .leading) { ForEach(prefixPreview, id: \.self) { Text($0).padding(.vertical, 3) } }.frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Cancel") { showPrefixPreview = false }
                Spacer()
                Button("Add Queries") {
                    if model.addGeneratedQueries(prefixPreview) { showPrefixPreview = false }
                }.buttonStyle(.borderedProminent).disabled(prefixPreview.isEmpty || prefixPreview.contains(where: { $0.count > 500 }))
            }
        }.padding(24).frame(minWidth: 280, idealWidth: 460, minHeight: 300)
    }
    private var importPreview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import App Data").font(.headline)
            if let imported {
                let newCount = imported.queries.filter { candidate in !model.queries.contains { BingQueries.key($0) == BingQueries.key(candidate) } }.count
                Text("\(newCount) new queries · \(imported.queries.count - newCount) already saved")
                Text("Merge keeps your saved library and imports the backup’s preferences and progress. Replace removes your current library.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { self.imported = nil }
                    Button("Merge") { model.importData(imported, replace: false); self.imported = nil }.buttonStyle(.borderedProminent)
                    Button("Replace", role: .destructive) { confirmReplace = true }
                }
            }
        }.padding(24).frame(minWidth: 280, idealWidth: 460)
            .alert("Replace Saved Queries?", isPresented: $confirmReplace) {
                Button("Cancel", role: .cancel) {}
                Button("Replace", role: .destructive) {
                    if let imported { model.importData(imported, replace: true) }; imported = nil; selectedQueries = []
                }
            }
    }
    private var startupOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            BingPanel(title: "BingBot · 1.0.0") {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(.blue.opacity(0.12), lineWidth: 6)
                        Circle().trim(from: 0, to: 1 - Double(startupRemaining) / Double(max(1, startupDuration)))
                            .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .linear(duration: 1), value: startupRemaining)
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.blue)
                    }.frame(width: 80, height: 80)
                    Text("Preparing query library and saved browser session…").font(.caption).multilineTextAlignment(.center)
                    Text("\(startupRemaining)").font(.system(.title, design: .monospaced))
                    Button("Skip") { startup = false }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity)
            }.frame(maxWidth: 340).padding(24)
        }.accessibilityAddTraits(.isModal)
    }
    #if os(macOS)
    private func scheduleClose() {
        closeTask?.cancel(); closeCountdown = 5; destination = .dashboard
        closeTask = Task {
            for remaining in stride(from: 5, through: 1, by: -1) {
                guard !Task.isCancelled else { return }; closeCountdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }; NSApplication.shared.terminate(nil)
        }
    }
    #endif
}

private struct BingPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption2.bold()).tracking(1.2).foregroundStyle(.secondary)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.12)))
            .shadow(color: .black.opacity(0.025), radius: 4, y: 2)
    }
    private var background: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}
