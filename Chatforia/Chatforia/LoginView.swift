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
            print("🧨 cleared account + device keychain entries")

            let enteredPassword = password

            let body = try JSONEncoder().encode(
                LoginRequest(identifier: email, password: enteredPassword)
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

            print("LOGIN user.publicKey =", resp.user.publicKey ?? "nil")
            print("LOCAL account publicKey before restore =", AccountKeyManager.shared.publicKeyBase64() ?? "nil")
            print("LOCAL device publicKey before restore =", (try? DeviceKeyManager.shared.publicKeyBase64()) ?? "nil")

            do {
                try await RemoteKeyBackupService.shared.restoreAccountKeysFromRemoteBackup(
                    token: resp.token,
                    password: enteredPassword
                )
                print("✅ Restored account keys from remote backup")
            } catch {
                print("⚠️ Remote key restore failed:", error.localizedDescription)
            }

            do {
                let serverPub = resp.user.publicKey
                let localPub = AccountKeyManager.shared.publicKeyBase64()

                print("LOGIN server publicKey =", serverPub ?? "nil")
                print("LOGIN local account publicKey after restore =", localPub ?? "nil")

                if let serverPub, let localPub, !serverPub.isEmpty, !localPub.isEmpty, serverPub == localPub {
                    try await RemoteKeyBackupService.shared.uploadCurrentDeviceKeyBackup(
                        token: resp.token,
                        password: enteredPassword
                    )
                    print("✅ Uploaded remote key backup")
                } else {
                    print("⚠️ Skipping backup upload because local/server account keys do not match")
                }
            } catch {
                print("⚠️ Remote key backup upload failed:", error.localizedDescription)
            }

            await auth.setTokenAndLoadUser(resp.token)
        } catch {
            errorText = error.localizedDescription
        }
    }
}


