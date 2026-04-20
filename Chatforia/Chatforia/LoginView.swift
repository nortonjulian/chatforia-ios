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
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var identifier = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorText: String?

    @State private var hasLoggedInBefore = false
    @State private var isOAuthLoading = false

    private let oauth = OAuthService()
    private let apple = AppleSignInCoordinator()

    private let loginFlagKey = "chatforiaHasLoggedIn"
    private let lastIdentifierKey = "chatforia.lastIdentifier"
    
    @MainActor
    private func handleGoogle() async {
        errorText = nil
        isOAuthLoading = true
        defer { isOAuthLoading = false }

        do {
            let idToken = try await oauth.signInWithGoogle()
            let response = try await oauth.exchangeGoogleToken(idToken)

            await auth.setTokenAndLoadUser(response.token)

        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func handleApple() async {
        errorText = nil
        isOAuthLoading = true
        defer { isOAuthLoading = false }

        do {
            let result = try await apple.start()

            let response = try await oauth.exchangeAppleToken(
                identityToken: result.token,
                nonce: result.nonce,
                firstName: result.name?.givenName,
                lastName: result.name?.familyName
            )

            await auth.setTokenAndLoadUser(response.token)

        } catch {
            errorText = error.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text(hasLoggedInBefore ? "Welcome back" : "Welcome to Chatforia")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(themeManager.palette.primaryText)
                                .multilineTextAlignment(.center)

                            Text(hasLoggedInBefore ? "Log in to your Chatforia account" : "Sign in or create an account")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.palette.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 28)

                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                ThemedOutlineButton(title: "Google") {
                                    Task { await handleGoogle() }
                                }
                                .disabled(isLoading || isOAuthLoading)
                                    

                                ThemedOutlineButton(title: "Apple") {
                                    Task { await handleApple() }
                                }
                                .disabled(isLoading || isOAuthLoading)
                            }

                            HStack {
                                Rectangle()
                                    .fill(themeManager.palette.border)
                                    .frame(height: 1)

                                Text("or")
                                    .font(.footnote)
                                    .foregroundStyle(themeManager.palette.secondaryText)
                                    .padding(.horizontal, 8)

                                Rectangle()
                                    .fill(themeManager.palette.border)
                                    .frame(height: 1)
                            }


                            HStack {
                                Spacer()

                                NavigationLink("Forgot password?") {
                                    Text("Forgot Password")
                                        .navigationTitle("Forgot Password")
                                }
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.accent)
                            }

                            if let errorText, (!identifier.isEmpty || !password.isEmpty) {
                                Text(errorText)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            ThemedTextField(
                                title: "Email or username",
                                text: $identifier,
                                keyboard: .emailAddress,
                                contentType: .username
                            )

                            ThemedSecureField(
                                title: "Password",
                                text: $password,
                                contentType: .password
                            )

                            ThemedGradientButton(
                                title: isLoading ? "Logging in..." : "Log In",
                                action: { Task { await login() } },
                                isFullWidth: true,
                                isDisabled: isLoading || identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
                            )

                            VStack(spacing: 6) {
                                Text("Don’t have an account yet?")
                                    .font(.footnote)
                                    .foregroundStyle(themeManager.palette.secondaryText)

                                NavigationLink {
                                    RegisterView()
                                } label: {
                                    Text("Create Account")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(themeManager.palette.accent)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(20)
                        .background(themeManager.palette.cardBackground.opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(themeManager.palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                errorText = nil
                hasLoggedInBefore = UserDefaults.standard.bool(forKey: loginFlagKey)
                identifier = UserDefaults.standard.string(forKey: lastIdentifierKey) ?? ""
            }
            .onAppear {
                print("🔐 LOGINVIEW APPEARED")
                errorText = nil
                hasLoggedInBefore = UserDefaults.standard.bool(forKey: loginFlagKey)
                identifier = UserDefaults.standard.string(forKey: lastIdentifierKey) ?? ""
            }
        }
    }

    private func login() async {
        errorText = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let enteredPassword = password

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

            // Clear any stale UI error once credential auth succeeds
            errorText = nil

            UserDefaults.standard.set(true, forKey: loginFlagKey)
            UserDefaults.standard.set(trimmedIdentifier, forKey: lastIdentifierKey)
            hasLoggedInBefore = true

            await auth.setTokenAndLoadUser(resp.token)

            // Clear again after bootstrap succeeds
            errorText = nil

        } catch {
            errorText = error.localizedDescription
        }
    }
}
