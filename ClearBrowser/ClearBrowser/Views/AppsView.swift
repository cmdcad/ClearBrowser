import SwiftUI

struct AppsView: View {
    let onClose: () -> Void
    let onOpenReloCalc: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button(action: onClose) {
                    Label("Browser", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)

                Spacer()
                Text("Apps")
                    .font(.headline)
                Spacer()

                Color.clear
                    .frame(width: 68)
            }

            Text("Explore apps from the developer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                Button(action: onOpenReloCalc) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.teal.gradient, in: RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("ReloCalc")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Plan your relocation budget")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open ReloCalc")
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
