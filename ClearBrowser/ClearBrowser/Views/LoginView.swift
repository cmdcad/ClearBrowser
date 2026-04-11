import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) var dismiss

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".")
    }

    private var isFormValid: Bool {
        isEmailValid && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section {
                        LoginHeaderSection()
                            .listRowBackground(Color.clear)
                    }

                    Section(header: Label("Credentials", systemImage: "lock.fill")) {
                        VStack(spacing: 12) {
                            LoginEmailField(email: $email)

                            LoginPasswordField(
                                label: "Password",
                                text: $password,
                                isSecure: !showPassword
                            )

                            HStack {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Toggle("Show Password", isOn: $showPassword)
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 8)
                    }

                    Section {
                        Button("Forgot Password?") {
                            // Implementation for forgot password can go here
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        Button(action: {
                            viewModel.loginWithGoogle()
                        }) {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                Text("Sign in with Google")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
                .scrollContentBackground(.hidden)

                if isLoading {
                    ProgressView()
                        .tint(.blue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
            .navigationTitle("Log In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    LoginButton(
                        isValid: isFormValid,
                        isLoading: isLoading,
                        action: handleLogin
                    )
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
    }

    private func handleLogin() {
        guard isFormValid else { return }
        isLoading = true

        Task {
            // Simulate network delay for UI feedback
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                viewModel.login(email: email, password: password)
                isLoading = false
                dismiss()
            }
        }
    }
}

// Header and helper subviews omitted for brevity but would be moved here as well...