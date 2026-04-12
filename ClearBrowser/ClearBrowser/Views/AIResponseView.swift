import SwiftUI

struct AIResponseView: View {
    @Binding var query: String
    let response: String?
    let isWorking: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.vertical, 8)
            HStack {
                TextField("Ask the AI assistant...", text: $query)
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
                        Text(response)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 450)
                    .background(Color(.secondarySystemFill))
                    .cornerRadius(14)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
    }
}
