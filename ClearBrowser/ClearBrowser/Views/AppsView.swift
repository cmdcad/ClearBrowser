import SwiftUI

struct AppsView: View {
    let onClose: () -> Void
    @ObservedObject var model: ReloCalcModel
    @State private var isShowingReloCalc = false

    init(onClose: @escaping () -> Void, model: ReloCalcModel) {
        self.onClose = onClose
        self.model = model
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if isShowingReloCalc {
                // VStack(spacing: 0) {
                //     navigationHeader(title: "ReloCalc", buttonTitle: "Apps") {
                //         isShowingReloCalc = false
                //     }
                    ReloCalcView(model: model , action: onClose)
               // }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    navigationHeader(title: "Apps", buttonTitle: "Browser"
                    , action: onClose)
                    .frame(height: 32)

                    Text("Explore apps from the developer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        Button {
                            isShowingReloCalc = true
                        } label: {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func navigationHeader(
        title: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Button(action: action) {
                Label(buttonTitle, systemImage: "chevron.left")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Spacer()
            Text(title)
                .font(.headline)
            Spacer()

            Color.clear
                .frame(width: buttonTitle == "Browser" ? 68 : 54)
        }
    }
}
