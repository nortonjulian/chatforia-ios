import SwiftUI

struct LoginResponse: Decodable {
    let message: String
    let token: String
    let user: UserDTO
}

struct LoginRequest: Encodable {
    let identifier: String
    let password: String
}

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Username or Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                }

                Button(isLoading ? "Logging in..." : "Log In") {
                    Task { await login() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || email.isEmpty || password.isEmpty)

                // 👇 ADD THIS TEST BUTTON
                Button("TEST: Call /auth/me (with token)") {
                    Task {
                        let token = TokenStore.shared.read()
                        do {
                            let me: UserDTO = try await APIClient.shared.send(
                                APIRequest(path: "auth/me", method: .GET, requiresAuth: true),
                                token: token
                            )
                            errorText = "✅ Token works. Hello \(me.username)"
                        } catch {
                            errorText = "❌ Token test failed: \(error.localizedDescription)"
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Login")
        }
    }
    private func login() async {
        errorText = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let body = try JSONEncoder().encode(
                LoginRequest(identifier: email, password: password)
            )

            let resp: LoginResponse = try await APIClient.shared.send(
                APIRequest(
                    path: "auth/login",
                    method: .POST,
                    body: body,
                    requiresAuth: false
                ),
                token: nil
            )

            await auth.setTokenAndLoadUser(resp.token)
        } catch {
            errorText = error.localizedDescription
        }
    }
}


