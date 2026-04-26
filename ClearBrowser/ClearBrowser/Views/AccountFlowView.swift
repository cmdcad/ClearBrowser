import SwiftUI
import PhotosUI

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
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
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
        .onChange(of: photoPickerItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.uploadProfilePicture(image)
                }
            }
        }
    }

    private var canSaveName: Bool {
        let trimmed = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != viewModel.displayName
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
