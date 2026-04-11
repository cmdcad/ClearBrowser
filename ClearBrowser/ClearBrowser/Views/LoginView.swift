import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                LoginHeaderSection()
                
                VStack(spacing: 16) {
                    Button(action: {
                        handleGoogleLogin()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                            Text("Continue with Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 30)
                    
                    Text("By continuing, you agree to our Terms of Service.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                Spacer()
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