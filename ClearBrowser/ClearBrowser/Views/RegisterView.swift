import SwiftUI

struct RegisterView: View {
    @ObservedObject var viewModel: HomeViewModel
    
    // MARK: - State Properties
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var openAIKey = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) var dismiss
    
    // MARK: - Computed Properties
    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".")
    }
    
    private var isPasswordValid: Bool {
        password.count >= 8 && password == confirmPassword
    }
    
    private var isFormValid: Bool {
        isEmailValid && isPasswordValid
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        HeaderSection()
                        
                        Form {
                            AccountDetailsSection(
                                email: $email,
                                password: $password,
                                confirmPassword: $confirmPassword,
                                showPassword: $showPassword
                            )
                            
                            AIConfigurationSection(openAIKey: $openAIKey)
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .padding(.vertical, 16)
                }
                
                if isLoading {
                    ProgressView()
                        .tint(.blue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    RegisterButton(
                        isValid: isFormValid,
                        isLoading: isLoading,
                        action: handleRegister
                    )
                }
            }
            .alert("Registration Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
    }
    
    // MARK: - Actions
    private func handleRegister() {
        guard isFormValid else { return }
        
        isLoading = true
        
        // Simulate async operation
        Task {
            do {
                viewModel.register(email: email, password: password, apiKey: openAIKey)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Subviews
private struct HeaderSection: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(.blue)
            
            Text("Create Your Account")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Join us to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

private struct AccountDetailsSection: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String
    @Binding var showPassword: Bool
    
    var body: some View {
        Section(header: Label("Account Details", systemImage: "person.fill")) {
            VStack(spacing: 12) {
                EmailField(email: $email)
                
                PasswordField(
                    label: "Password",
                    text: $password,
                    isSecure: !showPassword
                )
                
                PasswordField(
                    label: "Confirm Password",
                    text: $confirmPassword,
                    isSecure: !showPassword
                )
                
                HStack {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Show Password", isOn: $showPassword)
                }
                .font(.subheadline)
                
                PasswordRequirements(password: password)
            }
            .padding(.vertical, 8)
        }
    }
}

private struct EmailField: View {
    @Binding var email: String
    
    var isValid: Bool {
        email.contains("@") && email.contains(".")
    }
    
    var body: some View {
        HStack {
            Image(systemName: "envelope")
                .foregroundColor(.secondary)
            
            TextField("Email Address", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.none)
                .autocorrectionDisabled(true)
            
            if !email.isEmpty {
                Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isValid ? .green : .red)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityLabel("Email Address")
        .accessibilityHint("Enter a valid email address")
    }
}

private struct PasswordField: View {
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
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .accessibilityLabel(label)
    }
}

private struct PasswordRequirements: View {
    let password: String
    
    var isLengthValid: Bool { password.count >= 8 }
    var hasUppercase: Bool { password.contains(where: { $0.isUppercase }) }
    var hasLowercase: Bool { password.contains(where: { $0.isLowercase }) }
    var hasNumber: Bool { password.contains(where: { $0.isNumber }) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RequirementRow(
                text: "At least 8 characters",
                isMet: isLengthValid
            )
            RequirementRow(
                text: "Contains uppercase letter",
                isMet: hasUppercase
            )
            RequirementRow(
                text: "Contains lowercase letter",
                isMet: hasLowercase
            )
            RequirementRow(
                text: "Contains number",
                isMet: hasNumber
            )
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

private struct RequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(isMet ? .green : .gray)
            
            Text(text)
                .font(.caption)
                .foregroundColor(isMet ? .primary : .secondary)
        }
    }
}

private struct AIConfigurationSection: View {
    @Binding var openAIKey: String
    @State private var showKeyInfo = false
    
    var body: some View {
        Section {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.secondary)
                
                if openAIKey.isEmpty {
                    TextField("OpenAI API Key (Optional)", text: $openAIKey)
                        .textInputAutocapitalization(.none)
                        .autocorrectionDisabled(true)
                } else {
                    HStack {
                        Text(String(repeating: "•", count: max(openAIKey.count, 1)))
                            .tracking(2)
                        Spacer()
                        Button(action: { openAIKey = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .accessibilityLabel("OpenAI API Key")
            
            Button(action: { showKeyInfo.toggle() }) {
                Label("Where to find your API key?", systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        } header: {
            Label("AI Configuration", systemImage: "sparkles")
        } footer: {
            Text("Optional. You can add this later in settings.")
                .font(.caption)
        }
        .sheet(isPresented: $showKeyInfo) {
            APIKeyInfoSheet()
        }
    }
}

private struct APIKeyInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Getting Your OpenAI API Key")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        StepItem(number: "1", text: "Visit platform.openai.com")
                        StepItem(number: "2", text: "Sign in or create an account")
                        StepItem(number: "3", text: "Go to the API keys section")
                        StepItem(number: "4", text: "Click 'Create new secret key'")
                        StepItem(number: "5", text: "Copy and paste it here")
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Security Note", systemImage: "shield.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Never share your API key. It's secret and personal to your account.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("API Key Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StepItem: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

private struct RegisterButton: View {
    let isValid: Bool
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        if isLoading {
            ProgressView()
        } else {
            Button("Register") {
                action()
            }
            .disabled(!isValid)
        }
    }
}

// MARK: - Preview
#Preview {
    RegisterView(viewModel: HomeViewModel())
}