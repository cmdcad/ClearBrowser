import SwiftUI

struct RegisterView: View {
    @ObservedObject var viewModel: HomeViewModel
    var onSuccess: (() -> Void)? = nil
    var onSignIn: (() -> Void)? = nil

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var openAIKey = ""
    @State private var recoveryPassphrase = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".")
    }

    private var isPasswordValid: Bool {
        password.count >= 8 &&
        password == confirmPassword &&
        password.contains(where: { $0.isUppercase }) &&
        password.contains(where: { $0.isLowercase }) &&
        password.contains(where: { $0.isNumber })
    }

    private var isFormValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isEmailValid &&
        isPasswordValid &&
        (openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
         AIKeyEncryption.isValidPassphrase(recoveryPassphrase))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 54))
                        .foregroundColor(Theme.accent)

                    Text("Create your account")
                        .font(.largeTitle.bold())

                    Text("Set up your profile once and keep your browsing experience easier to manage.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                registerCard(
                    title: "Profile",
                    content: {
                        RegisterTextField(title: "Display name", systemImage: "person", text: $displayName)
                    }
                )

                registerCard(
                    title: "Account",
                    content: {
                        VStack(spacing: 16) {
                            RegisterTextField(title: "Email", systemImage: "envelope", text: $email)

                            RegisterSecureField(
                                title: "Password",
                                text: $password,
                                isSecure: !showPassword
                            )

                            RegisterSecureField(
                                title: "Confirm password",
                                text: $confirmPassword,
                                isSecure: !showPassword
                            )

                            Toggle("Show password", isOn: $showPassword)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                            PasswordRequirements(password: password)
                        }
                    }
                )

                registerCard(
                    title: "AI Key",
                    footer: "Optional. To sync the key securely, create a four-word recovery passphrase and keep it safe.",
                    content: {
                        VStack(spacing: 14) {
                            RegisterTextField(title: "OpenAI API key", systemImage: "key", text: $openAIKey)
                                .textInputAutocapitalization(.never)

                            if !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                RegisterSecureField(
                                    title: "Four-word recovery passphrase",
                                    text: $recoveryPassphrase,
                                    isSecure: true
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                            }
                        }
                    }
                )

                Button(action: handleRegister) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("Create Account")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .disabled(!isFormValid || isLoading)
                .background(isFormValid ? Theme.accent : Color.gray.opacity(0.35))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(spacing: 10) {
                    Text("Already have an account?")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button("Sign in instead", action: handleSignIn)
                        .fontWeight(.semibold)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if onSuccess == nil && onSignIn == nil {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Registration Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    private func registerCard<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)

            content()

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func handleRegister() {
        guard !isLoading else { return }

        isLoading = true
        Task {
            do {
                try await viewModel.register(
                    email: email,
                    password: password,
                    displayName: displayName,
                    apiKey: openAIKey,
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

    private func handleSignIn() {
        if let onSignIn {
            onSignIn()
        } else {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                viewModel.accountSheet = .login
            }
        }
    }
}

private struct RegisterTextField: View {
    let title: String
    let systemImage: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)

            TextField(title, text: $text)
                .autocorrectionDisabled(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct RegisterSecureField: View {
    let title: String
    @Binding var text: String
    let isSecure: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .foregroundColor(.secondary)

            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .textInputAutocapitalization(.never)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct PasswordRequirements: View {
    let password: String

    private var requirements: [(String, Bool)] {
        [
            ("At least 8 characters", password.count >= 8),
            ("Contains uppercase letter", password.contains(where: { $0.isUppercase })),
            ("Contains lowercase letter", password.contains(where: { $0.isLowercase })),
            ("Contains number", password.contains(where: { $0.isNumber }))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(requirements, id: \.0) { requirement in
                HStack(spacing: 8) {
                    Image(systemName: requirement.1 ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(requirement.1 ? .green : .secondary)
                    Text(requirement.0)
                        .font(.caption)
                        .foregroundColor(requirement.1 ? .primary : .secondary)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
