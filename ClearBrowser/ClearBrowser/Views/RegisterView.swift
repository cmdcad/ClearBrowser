import SwiftUI

struct RegisterView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var openAIKey = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account Details")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.none)
                    SecureField("Password", text: $password)
                }
                
                Section(header: Text("AI Configuration (Optional)")) {
                    TextField("OpenAI API Key", text: $openAIKey)
                        .autocorrectionDisabled(true)
                }
                
                Button("Register") {
                    viewModel.register(email: email, apiKey: openAIKey)
                    dismiss()
                }
                .disabled(email.isEmpty || password.isEmpty)
            }
            .navigationTitle("Register")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}