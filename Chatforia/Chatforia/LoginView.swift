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

    @State private var hasGoogle = false
    @State private var hasApple = false

    private let loginFlagKey = "chatforiaHasLoggedIn"
    private let lastIdentifierKey = "chatforia.lastIdentifier"

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text(hasLoggedInBefore ? "Welcome back" : "Continue to Chatforia")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(themeManager.palette.primaryText)
                                .multilineTextAlignment(.center)

                            Text("Log in to your Chatforia account")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.palette.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 28)

                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                ThemedOutlineButton(title: "Google") {}
                                    .disabled(!hasGoogle)

                                ThemedOutlineButton(title: "Apple") {}
                                    .disabled(!hasApple)
                            }

                            if !hasGoogle && !hasApple {
                                Text("Single-sign-on is currently unavailable. Use username and password instead.")
                                    .font(.footnote)
                                    .foregroundStyle(themeManager.palette.secondaryText)
                                    .multilineTextAlignment(.center)
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

                            if let errorText {
                                Text(errorText)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            ThemedGradientButton(
                                title: isLoading ? "Logging in..." : "Log In",
                                action: { Task { await login() } },
                                isFullWidth: true,
                                isDisabled: isLoading || identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
                            )
                            
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

            UserDefaults.standard.set(true, forKey: loginFlagKey)
            UserDefaults.standard.set(trimmedIdentifier, forKey: lastIdentifierKey)
            hasLoggedInBefore = true

            await auth.setTokenAndLoadUser(resp.token)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
