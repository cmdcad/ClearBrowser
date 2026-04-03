import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var email = ""
    @State private var password = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Credentials")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.none)
                    SecureField("Password", text: $password)
                }
                
                Button("Log In") {
                    viewModel.login(email: email)
                    dismiss()
                }
                .disabled(email.isEmpty || password.isEmpty)
            }
            .navigationTitle("Login")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}