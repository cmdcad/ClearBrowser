import SwiftUI
import PhotosUI
import UIKit

struct AccountFlowView: View {
    @ObservedObject var viewModel: HomeViewModel
    let startDestination: AccountSheetDestination

    @State private var path: [AccountRoute] = []
    @Environment(\.dismiss) private var dismiss

    enum AccountRoute: Hashable {
        case login
        case register
        case profile
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootView
                .navigationDestination(for: AccountRoute.self) { route in
                    switch route {
                    case .login:
                        LoginView(
                            viewModel: viewModel,
                            onSuccess: { path = [.profile] },
                            onCreateAccount: { path.append(.register) }
                        )
                    case .register:
                        RegisterView(
                            viewModel: viewModel,
                            onSuccess: { path = [.profile] },
                            onSignIn: { path.append(.login) }
                        )
                    case .profile:
                        ProfileView(viewModel: viewModel) {
                            dismiss()
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch startDestination {
        case .login:
            LoginView(
                viewModel: viewModel,
                onSuccess: { path = [.profile] },
                onCreateAccount: { path.append(.register) }
            )
        case .register:
            RegisterView(
                viewModel: viewModel,
                onSuccess: { path = [.profile] },
                onSignIn: { path.append(.login) }
            )
        case .profile:
            ProfileView(viewModel: viewModel) {
                dismiss()
            }
        case .hub:
            AccountHubView(viewModel: viewModel) { route in
                path.append(route)
            }
        }
    }
}

private struct AccountHubView: View {
    @ObservedObject var viewModel: HomeViewModel
    let openRoute: (AccountFlowView.AccountRoute) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    ProfileAvatarView(viewModel: viewModel, size: 92)

                    Text(viewModel.displayName ?? "Your account")
                        .font(.title2.bold())

                    Text(viewModel.currentUserEmail ?? "Sign in to sync bookmarks, favorites, history, and your profile.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)

                VStack(spacing: 14) {
                    accountActionCard(
                        title: viewModel.isLoggedIn ? "View profile" : "Open profile",
                        subtitle: "See and edit your name, photo, and saved account details.",
                        systemImage: "person.crop.circle",
                        action: { openRoute(.profile) }
                    )

                    accountActionCard(
                        title: "Log in",
                        subtitle: "Return to an existing account and restore synced data.",
                        systemImage: "person.badge.key",
                        action: { openRoute(.login) }
                    )

                    accountActionCard(
                        title: "Register",
                        subtitle: "Create a new account with a display name and optional AI key.",
                        systemImage: "person.crop.circle.badge.plus",
                        action: { openRoute(.register) }
                    )
                }

                HStack(spacing: 12) {
                    StatPill(value: "\(viewModel.bookmarks.count)", label: "Bookmarks")
                    StatPill(value: "\(viewModel.favorites.count)", label: "Favorites")
                    StatPill(value: "\(viewModel.history.count)", label: "History")
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func accountActionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(18)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileView: View {
    @ObservedObject var viewModel: HomeViewModel
    var onDone: (() -> Void)? = nil

    @State private var editedDisplayName: String = ""
    @State private var photoPickerError: String?
    @State private var isShowingLegacyPhotoPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Group {
                        if #available(iOS 16.0, *) {
                            ModernProfilePhotoPicker(
                                viewModel: viewModel,
                                onError: { photoPickerError = $0 }
                            )
                        } else {
                            Button {
                                isShowingLegacyPhotoPicker = true
                            } label: {
                                profilePhotoButton
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .sheet(isPresented: $isShowingLegacyPhotoPicker) {
                        LegacyProfilePhotoPicker { result in
                            switch result {
                            case .success(let image):
                                viewModel.uploadProfilePicture(image)
                            case .failure(let error):
                                photoPickerError = error.localizedDescription
                            }
                        }
                    }

                    VStack(spacing: 4) {
                        Text(viewModel.displayName ?? "Your profile")
                            .font(.title2.bold())

                        Text(viewModel.currentUserEmail ?? "This profile is stored on this device until you sign in.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Profile details")
                        .font(.headline)

                    TextField("Display name", text: $editedDisplayName)
                        .textFieldStyle(.roundedBorder)

                    Button("Save name") {
                        viewModel.updateProfile(name: editedDisplayName)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canSaveName ? Theme.accent : Color.gray.opacity(0.35))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(!canSaveName)
                }
                .padding(20)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 16) {
                    Text("Saved data")
                        .font(.headline)

                    HStack(spacing: 12) {
                        StatPill(value: "\(viewModel.bookmarks.count)", label: "Bookmarks")
                        StatPill(value: "\(viewModel.favorites.count)", label: "Favorites")
                        StatPill(value: "\(viewModel.history.count)", label: "History")
                    }

                    Text("Profile photo and name stay available on this device, and logged-in users also sync through Firebase.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                if viewModel.isLoggedIn {
                    Button(role: .destructive) {
                        viewModel.logout()
                    } label: {
                        Label("Log Out", systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let onDone {
                    Button("Done", action: onDone)
                }
            }
        }
        .onAppear {
            editedDisplayName = viewModel.displayName ?? ""
        }
        .alert("Couldn't load photo", isPresented: Binding(
            get: { photoPickerError != nil },
            set: { if !$0 { photoPickerError = nil } }
        )) {
            Button("OK") { photoPickerError = nil }
        } message: {
            Text(photoPickerError ?? "")
        }
    }

    private var profilePhotoButton: some View {
        ZStack(alignment: .bottomTrailing) {
            ProfileAvatarView(viewModel: viewModel, size: 112)
            Image(systemName: "camera.fill")
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(9)
                .background(Theme.accent)
                .clipShape(Circle())
        }
    }

    private var canSaveName: Bool {
        let trimmed = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != viewModel.displayName
    }
}

@available(iOS 16.0, *)
private struct ModernProfilePhotoPicker: View {
    @ObservedObject var viewModel: HomeViewModel
    let onError: (String) -> Void
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarView(viewModel: viewModel, size: 112)
                Image(systemName: "camera.fill")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(9)
                    .background(Theme.accent)
                    .clipShape(Circle())
            }
        }
        .onChange(of: photoPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    viewModel.uploadProfilePicture(image)
                } catch {
                    onError(error.localizedDescription)
                }
            }
        }
    }
}

private struct LegacyProfilePhotoPicker: UIViewControllerRepresentable {
    let onComplete: (Result<UIImage, Error>) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: LegacyProfilePhotoPicker

        init(parent: LegacyProfilePhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.presentationMode.wrappedValue.dismiss()
                return
            }
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                let onComplete = parent.onComplete
                parent.presentationMode.wrappedValue.dismiss()
                DispatchQueue.main.async {
                    onComplete(.failure(CocoaError(.fileReadCorruptFile)))
                }
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let result: Result<UIImage, Error>
                    if let error {
                        result = .failure(error)
                    } else if let image = object as? UIImage {
                        result = .success(image)
                    } else {
                        result = .failure(CocoaError(.fileReadCorruptFile))
                    }
                    self.parent.presentationMode.wrappedValue.dismiss()
                    DispatchQueue.main.async {
                        self.parent.onComplete(result)
                    }
                }
            }
        }
    }
}

private struct ProfileAvatarView: View {
    @ObservedObject var viewModel: HomeViewModel
    let size: CGFloat

    var body: some View {
        Group {
            if let localPath = viewModel.localProfileImagePath,
               let image = UIImage(contentsOfFile: localPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = viewModel.profileImageUrl {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Theme.accent)
                    .padding(size * 0.12)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .frame(width: size, height: size)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(Circle())
    }
}

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(Theme.accent)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
