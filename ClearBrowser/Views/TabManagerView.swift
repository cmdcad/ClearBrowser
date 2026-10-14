import SwiftUI

struct TabManagerView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.tabs) { tab in
                        TabCard(tab: tab,
                                preview: viewModel.tabPreviews[tab.id],
                                isActive: viewModel.activeTabID == tab.id,
                                onSelect: {
                                    viewModel.switchTab(to: tab.id)
                                    dismiss()
                                },
                                onClose: {
                                    viewModel.closeTab(id: tab.id)
                                })
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear { viewModel.captureTabPreview() }
            .navigationTitle("Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(action: {
                        viewModel.createNewTab()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("New Tab")
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

struct TabCard: View {
    let tab: BrowserTab
    let preview: UIImage?
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tab.title)
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            Group {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color(uiColor: .tertiarySystemBackground)
                        Image(systemName: "globe").font(.largeTitle).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(preview == nil ? "Preview unavailable" : "Last viewed page preview")

            Text(tab.url.host ?? tab.url.absoluteString)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(height: 205)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.blue : Color.clear, lineWidth: 3)
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .onTapGesture(perform: onSelect)
    }
}

#Preview {
    TabManagerView(viewModel: HomeViewModel())
}