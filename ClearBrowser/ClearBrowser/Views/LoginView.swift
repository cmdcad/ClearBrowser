import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) var dismiss

    private var isFormValid: Bool {
        !email.isEmpty && email.contains("@") && password.count >= 6
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LoginHeaderSection()
                        .listRowBackground(Color.clear)
                }

                Section(header: Text("Sign in with Email")) {
                    LoginEmailField(email: $email)
                    
                    LoginPasswordField(
                        label: "Password",
                        text: $password,
                        isSecure: !showPassword
                    )
                    
                    Toggle("Show Password", isOn: $showPassword)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: handleEmailLogin) {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                    }
                    .disabled(!isFormValid || isLoading)
                    .listRowBackground(isFormValid ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                }

                Section(header: Text("Other Options")) {
                    Button(action: { handleGoogleLogin() }) {
                        HStack {
                            Image(systemName: "g.circle.fill")
                            Text("Continue with Google")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .foregroundColor(.primary)
                }
                
                Section {
                    Text("By continuing, you agree to our Terms of Service.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Log In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView()
                            .padding(20)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
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
    }

    private func handleEmailLogin() {
        isLoading = true
        viewModel.login(email: email, password: password)
        isLoading = false
        dismiss()
    }

    private func handleGoogleLogin() {
        isLoading = true
        Task {
            viewModel.loginWithGoogle()
            isLoading = false
            dismiss()
        }
    }
}

// MARK: - Helper Subviews

private struct LoginHeaderSection: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)
            
            Text("Welcome Back")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Sign in to your account")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct LoginEmailField: View {
    @Binding var email: String
    var body: some View {
        HStack {
            Image(systemName: "envelope")
                .foregroundColor(.secondary)
            TextField("Email Address", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.none)
                .autocorrectionDisabled(true)
        }
    }
}

private struct LoginPasswordField: View {
    let label: String
    @Binding var text: String
    let isSecure: Bool
    var body: some View {
        HStack {
            Image(systemName: "lock")
                .foregroundColor(.secondary)
            if isSecure {
                SecureField(label, text: $text)
            } else {
                TextField(label, text: $text)
                    .textInputAutocapitalization(.none)
            }
        }
    }
}