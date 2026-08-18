import SwiftUI

struct AIResponseView: View {
    @Binding var query: String
    let response: String?
    let isWorking: Bool
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ClearBrowser")
                    .font(.headline)
                    .background(Color(.tertiarySystemFill))

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Dismiss AI")
                .buttonStyle(.plain)
            }
            .padding(.top)

            HStack {
                TextField("Ask the AI - Zooma...", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)

                Button(action: onSubmit) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }

            if isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.85, anchor: .center)
                    Text("Thinking...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            if let response {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI response")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "AI returned an empty response."
                             : response)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 600)
                    .background(Color(.secondarySystemFill))
                    .cornerRadius(14)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 18, y: -4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height > 80 {
                        onDismiss()
                    }
                }
        )
    }
}
