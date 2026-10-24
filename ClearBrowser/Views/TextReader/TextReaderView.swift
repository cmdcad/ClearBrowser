import SwiftUI

@MainActor
struct TextReaderView: View {
    let onClose: () -> Void
    @StateObject private var model = TextReaderModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var editing = false
    @State private var title = ""
    @State private var editedTitle = ""
    @State private var editedText = ""
    @State private var pastedText = ""
    @State private var url = ""
    @State private var useURL = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { model.close(); onClose() }) { Label("Apps", systemImage: "chevron.left") }
                Spacer()
                Text("Text Reader").font(.headline)
                Spacer()
                Button { importing = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Import text")
            }.padding()
            if let doc = model.document {
                reader(doc)
            } else {
                library
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.document != nil { miniPlayer }
        }
        .sheet(isPresented: $importing) { importSheet }
        .sheet(isPresented: $editing) { editSheet }
        .alert("Text Reader", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.savePosition() }
        }
        .onDisappear { model.pause() }
    }

    private var library: some View {
        List {
            if model.documents.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "text.book.closed").font(.largeTitle).foregroundStyle(.blue)
                    Text("Bring something to read").font(.title2.bold())
                    Text("Paste text or import an article link. Listen while the reader highlights and follows each sentence.")
                        .foregroundStyle(.secondary)
                    Button("Import text") { importing = true }.buttonStyle(.borderedProminent)
                }.padding(.vertical)
            }
            ForEach(model.documents.sorted { $0.updated > $1.updated }) { doc in
                Button { model.open(doc) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(doc.title).font(.headline).foregroundStyle(.primary)
                        Text("Page \(doc.page + 1) of \(doc.pages.count) · \(clock(doc.position))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { model.delete(doc) }
                }
            }
        }.listStyle(.insetGrouped)
    }

    private func reader(_ doc: ReaderDocument) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Button { beginEditing(doc) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(doc.title).font(.title3.bold()).lineLimit(2)
                        Text("Page \(doc.page + 1) of \(doc.pages.count)").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityHint("Tap to edit the title or text")
                Menu {
                    Toggle("Sentence highlighting", isOn: $model.highlighting)
                    Toggle("Follow reading", isOn: $model.followReading)
                    Button("Edit text") { beginEditing(doc) }
                    Button("Library") { model.close() }
                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                    .accessibilityLabel("Reading options")
            }.padding(.horizontal).padding(.bottom)
            if !model.followReading {
                Button("Follow reading") { model.followReading = true }
                    .font(.caption).padding(.bottom, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 1).id("page-top")
                        if model.sentences.isEmpty {
                            Text(model.pageText).frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .onTapGesture { beginEditing(doc) }
                        } else {
                            ForEach(segments) { segment in
                                Text(segment.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, segment.id >= 0 ? 5 : 0)
                                    .background(model.highlighting && model.activeSentence == segment.id ? Color.yellow.opacity(0.3) : .clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .id(segment.id)
                                    .textSelection(.enabled)
                                    .onTapGesture { beginEditing(doc) }
                            }
                        }
                    }.font(.system(size: 20)).lineSpacing(7).padding(20)
                }
                .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in model.followReading = false })
                .onChange(of: model.activeSentence) { _, active in
                    guard model.followReading, let active else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(active, anchor: .center) }
                }
                .onChange(of: model.followReading) { _, follows in
                    if follows, let active = model.activeSentence {
                        withAnimation { proxy.scrollTo(active, anchor: .center) }
                    }
                }
                .onChange(of: doc.page) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
            }
        }
    }

    private struct Segment: Identifiable { let id: Int; let text: String }
    private var segments: [Segment] {
        let text = model.pageText
        var cursor = text.startIndex
        var result: [Segment] = []
        for span in model.sentences {
            if cursor < span.range.lowerBound {
                result.append(Segment(id: -span.id - 1, text: String(text[cursor..<span.range.lowerBound])))
            }
            result.append(Segment(id: span.id, text: String(text[span.range])))
            cursor = span.range.upperBound
        }
        if cursor < text.endIndex { result.append(Segment(id: Int.min, text: String(text[cursor...]))) }
        return result
    }

    private var miniPlayer: some View {
        VStack(spacing: 10) {
            if model.isLoading {
                HStack { ProgressView(); Text("Preparing page audio…").font(.caption); Spacer() }
            } else if model.duration > 0 && model.sentences.isEmpty {
                Text("Audio ready · Highlighting unavailable for this page")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.duration > 0 {
                Slider(value: Binding(get: { model.time }, set: { model.seek($0) }), in: 0...max(0.01, model.duration))
                    .accessibilityLabel("Playback position")
                HStack {
                    Text(clock(model.time)); Spacer(); Text(clock(model.duration))
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 28) {
                Button { model.goToPage((model.document?.page ?? 0) - 1) } label: { Image(systemName: "backward.end.fill") }
                    .disabled((model.document?.page ?? 0) == 0).accessibilityLabel("Previous page")
                Button {
                    if model.isPlaying || model.wantsPlayback { model.pause() } else { model.play() }
                } label: {
                    Image(systemName: model.isPlaying || model.wantsPlayback ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 42))
                }.accessibilityLabel(model.isPlaying || model.wantsPlayback ? "Pause" : "Play")
                Button { model.goToPage((model.document?.page ?? 0) + 1) } label: { Image(systemName: "forward.end.fill") }
                    .disabled((model.document?.page ?? 0) + 1 >= (model.document?.pages.count ?? 0))
                    .accessibilityLabel("Next page")
                Spacer(minLength: 0)
                Menu {
                    ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { speed in
                        Button("\(speed.formatted())×") { model.setSpeed(speed) }
                    }
                } label: { Text("\((model.document?.speed ?? 1).formatted())×").font(.subheadline.bold()) }
                    .accessibilityLabel("Playback speed")
            }
        }.padding().background(.regularMaterial)
    }

    private var importSheet: some View {
        NavigationStack {
            Form {
                TextField("Document title (optional)", text: $title)
                Picker("Source", selection: $useURL) {
                    Text("Paste text").tag(false)
                    Text("URL").tag(true)
                }.pickerStyle(.segmented)
                if useURL {
                    TextField("https://example.com/article", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Supports static articles and text files. For pages requiring login or JavaScript, paste the text.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TextEditor(text: $pastedText).frame(minHeight: 260).accessibilityLabel("Text to read")
                }
                Text("Audio generation sends this text to your configured local audio server, or the cloud service when unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.isImporting { ProgressView("Importing text…") }
            }
            .navigationTitle("Import text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { importing = false }.disabled(model.isImporting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Read") {
                        if useURL {
                            Task {
                                if await model.importURL(url, title: title) { resetImport() }
                            }
                        } else {
                            let count = model.documents.count
                            model.importText(pastedText, title: title)
                            if model.documents.count > count { resetImport() }
                        }
                    }.disabled(model.isImporting || (useURL ? url : pastedText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(model.isImporting)
            .alert("Import text", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("OK") { model.message = nil }
            } message: { Text(model.message ?? "") }
        }
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                TextField("Document title", text: $editedTitle)
                TextEditor(text: $editedText)
                    .frame(minHeight: 300)
                    .accessibilityLabel("Document text")
            }
            .navigationTitle("Edit document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editing = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.updateDocument(title: editedTitle, text: editedText) { editing = false }
                    }
                }
            }
            .alert("Edit document", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("OK") { model.message = nil }
            } message: { Text(model.message ?? "") }
        }
    }

    private func beginEditing(_ doc: ReaderDocument) {
        editedTitle = doc.title
        editedText = doc.pages.joined()
        editing = true
    }

    private func resetImport() { importing = false; pastedText = ""; title = ""; url = "" }
    private func clock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
