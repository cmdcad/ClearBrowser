import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: HomeViewModel
    var onSuccess: (() -> Void)? = nil
    var onCreateAccount: (() -> Void)? = nil

    @State private var email = ""
    @State private var password = ""
    @State private var recoveryPassphrase = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    private var isFormValid: Bool {
        !email.isEmpty && email.contains("@") && password.count >= 6
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 54))
                        .foregroundColor(Theme.accent)

                    Text("Welcome back")
                        .font(.largeTitle.bold())

                    Text("Pick up where you left off with your profile, bookmarks, and history.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 16) {
                    LoginInputField(
                        title: "Email",
                        systemImage: "envelope",
                        text: $email,
                        isSecure: false
                    )

                    LoginInputField(
                        title: "Password",
                        systemImage: "lock",
                        text: $password,
                        isSecure: !showPassword
                    )

                    LoginInputField(
                        title: "AI recovery passphrase (four words, optional)",
                        systemImage: "key",
                        text: $recoveryPassphrase,
                        isSecure: true
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                    Toggle("Show password", isOn: $showPassword)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 12) {
                    Button(action: handleEmailLogin) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            Text("Log In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .disabled(!isFormValid || isLoading)
                    .background(isFormValid ? Theme.accent : Color.gray.opacity(0.35))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button(action: handleGoogleLogin) {
                        Label("Continue with Google", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                }

                VStack(spacing: 10) {
                    Text("New here?")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button("Create an account", action: handleCreateAccount)
                        .fontWeight(.semibold)
                }

                Text("Your account keeps profile info and synced browsing data easier to manage in one place.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if onSuccess == nil && onCreateAccount == nil {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Login Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    private func handleEmailLogin() {
        guard !isLoading else { return }

        isLoading = true
        Task {
            do {
                try await viewModel.login(
                    email: email,
                    password: password,
                    recoveryPassphrase: recoveryPassphrase
                )
                await MainActor.run {
                    isLoading = false
                    if let onSuccess {
                        onSuccess()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func handleGoogleLogin() {
        guard !isLoading else { return }

        isLoading = true
        viewModel.loginWithGoogle(recoveryPassphrase: recoveryPassphrase) { success in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    if let onSuccess {
                        onSuccess()
                    } else {
                        dismiss()
                    }
                } else {
                    errorMessage = "Google sign-in did not complete. Please try again."
                }
            }
        }
    }

    private func handleCreateAccount() {
        if let onCreateAccount {
            onCreateAccount()
        } else {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                viewModel.accountSheet = .register
            }
        }
    }
}

private struct LoginInputField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let isSecure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)

                Group {
                    if isSecure {
                        SecureField(title, text: $text)
                    } else {
                        TextField(title, text: $text)
                            .textInputAutocapitalization(.never)
                    }
                }
                .autocorrectionDisabled(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
