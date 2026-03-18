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

    @State private var identifier = ""
    @State private var password = ""
    @State private var rememberMe = true
    @State private var isLoading = false
    @State private var errorText: String?

    @State private var hasLoggedInBefore = false

    // OAuth placeholders (match web UX)
    @State private var hasGoogle = false
    @State private var hasApple = false

    private let loginFlagKey = "chatforiaHasLoggedIn"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // MARK: Title Section
                    VStack(spacing: 6) {
                        Text(hasLoggedInBefore ? "Welcome back" : "Continue to Chatforia")
                            .font(.largeTitle.bold())
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("Log in to your Chatforia account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 4)

                    // MARK: OAuth Section
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                // TODO: Google sign-in
                            } label: {
                                Text("Google")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!hasGoogle)

                            Button {
                                // TODO: Apple sign-in
                            } label: {
                                Text("Apple")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!hasApple)
                        }

                        if !hasGoogle && !hasApple {
                            Text("Single-sign-on is currently unavailable. Use username and password instead.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        HStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(height: 1)

                            Text("or")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)

                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(height: 1)
                        }
                    }

                    // MARK: Inputs
                    VStack(spacing: 12) {
                        TextField("Email or username", text: $identifier)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }

                    // MARK: Options Row
                    HStack(alignment: .center) {
                        Toggle("Keep me signed in", isOn: $rememberMe)
                            .font(.footnote)

                        Spacer()

                        NavigationLink("Forgot password?") {
                            Text("Forgot Password")
                                .navigationTitle("Forgot Password")
                        }
                        .font(.footnote)
                    }

                    // MARK: Error
                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // MARK: Login Button
                    Button(isLoading ? "Logging in..." : "Log In") {
                        Task { await login() }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(
                        isLoading ||
                        identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        password.isEmpty
                    )

                    // MARK: Create Account
                    Text("Don’t have an account yet?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    NavigationLink {
                        RegisterView()
                    } label: {
                        Text("Create Account")
                            .font(.footnote.weight(.semibold))
                    }

                    // MARK: Debug
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
                    .padding(.top, 4)

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                hasLoggedInBefore = UserDefaults.standard.bool(forKey: loginFlagKey)
            }
        }
    }

    // MARK: Login Logic
    private func login() async {
        errorText = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let enteredPassword = password
            let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

            let body = try JSONEncoder().encode(
                LoginRequest(identifier: trimmedIdentifier, password: enteredPassword)
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

            // MARK: Key Restore
            do {
                try await RemoteKeyBackupService.shared.restoreAccountKeysFromRemoteBackup(
                    token: resp.token,
                    password: enteredPassword
                )
            } catch {
                print("⚠️ Remote key restore failed:", error.localizedDescription)
            }

            do {
                let serverPub = resp.user.publicKey
                let localPub = AccountKeyManager.shared.publicKeyBase64()

                if let serverPub,
                   let localPub,
                   !serverPub.isEmpty,
                   !localPub.isEmpty,
                   serverPub == localPub {
                    try await RemoteKeyBackupService.shared.uploadCurrentDeviceKeyBackup(
                        token: resp.token,
                        password: enteredPassword
                    )
                }
            } catch {
                print("⚠️ Remote key backup upload failed:", error.localizedDescription)
            }

            // MARK: Persist "has logged in"
            UserDefaults.standard.set(true, forKey: loginFlagKey)
            hasLoggedInBefore = true

            await auth.setTokenAndLoadUser(resp.token)

        } catch {
            errorText = error.localizedDescription
        }
    }
}
