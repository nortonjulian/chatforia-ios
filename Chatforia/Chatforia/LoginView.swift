import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @StateObject private var vm: LoginViewModel

    init() {
        _vm = StateObject(wrappedValue: LoginViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text(
                                appText(
                                    vm.hasLoggedInBefore
                                    ? "common.welcomeBack"
                                    : "common.welcomeToChatforia",
                                    languageCode: appLanguage
                                )
                            )
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(themeManager.palette.primaryText)
                            .multilineTextAlignment(.center)

                            Text(
                                appText(
                                    vm.hasLoggedInBefore
                                    ? "login.subtitleReturning"
                                    : "upgrade.auth.signInOrCreateAnAccount",
                                    languageCode: appLanguage
                                )
                            )
                            .font(.subheadline)
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .multilineTextAlignment(.center)
                        }
                        .padding(.top, 28)

                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                ThemedOutlineButton(
                                    title: vm.activeOAuthProvider == "google"
                                    ? "Continue with Google…"
                                    : "Google"
                                ) {
                                    Task { await vm.handleGoogle(auth: auth) }
                                }
                                .disabled(vm.isLoading || vm.activeOAuthProvider != nil)

                                ThemedOutlineButton(
                                    title: vm.activeOAuthProvider == "apple"
                                    ? appText("auth.continueWithApple", languageCode: appLanguage)
                                    : appText("auth.apple", languageCode: appLanguage)
                                ) {
                                    Task { await vm.handleApple(auth: auth) }
                                }
                                .disabled(vm.isLoading || vm.activeOAuthProvider != nil)
                            }

                            HStack {
                                Rectangle()
                                    .fill(themeManager.palette.border)
                                    .frame(height: 1)

                                Text(appText("common.or", languageCode: appLanguage))
                                    .font(.footnote)
                                    .foregroundStyle(themeManager.palette.secondaryText)
                                    .padding(.horizontal, 8)

                                Rectangle()
                                    .fill(themeManager.palette.border)
                                    .frame(height: 1)
                            }

                            HStack {
                                Spacer()

                                NavigationLink(
                                    appText("auth.forgotPasswordQuestion", languageCode: appLanguage)
                                ) {
                                    Text(appText("auth.forgotPassword", languageCode: appLanguage))
                                        .navigationTitle(
                                            appText("auth.forgotPassword", languageCode: appLanguage)
                                        )
                                }
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.accent)
                            }

                            if let errorText = vm.errorText {
                                Text(errorText)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if vm.showResendVerification {
                                Button {
                                    Task {
                                        await vm.resendVerificationEmail(languageCode: appLanguage)
                                    }
                                } label: {
                                    Text(
                                        vm.resendLoading
                                        ? appText("auth.sending", languageCode: appLanguage)
                                        : appText("auth.resendVerificationEmail", languageCode: appLanguage)
                                    )
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(themeManager.palette.accent)
                                }
                                .disabled(vm.resendLoading)
                            }

                            if let resendSuccess = vm.resendSuccess {
                                Text(resendSuccess)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            ThemedTextField(
                                title: appText("auth.emailOrUsername", languageCode: appLanguage),
                                text: $vm.identifier,
                                keyboard: .emailAddress,
                                contentType: .username
                            )

                            ThemedSecureField(
                                title: appText("auth.password", languageCode: appLanguage),
                                text: $vm.password,
                                contentType: .password
                            )

                            ThemedGradientButton(
                                title: vm.isLoading
                                ? appText("auth.loggingIn", languageCode: appLanguage)
                                : appText("auth.logIn", languageCode: appLanguage),
                                action: {
                                    Task {
                                        await vm.login(auth: auth, languageCode: appLanguage)
                                    }
                                },
                                isFullWidth: true,
                                isDisabled: vm.isLoading
                                    || vm.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || vm.password.isEmpty
                            )

                            VStack(spacing: 6) {
                                Text(appText("auth.dontHaveAnAccountYet", languageCode: appLanguage))
                                    .font(.footnote)
                                    .foregroundStyle(themeManager.palette.secondaryText)

                                NavigationLink {
                                    RegisterView()
                                } label: {
                                    Text(appText("auth.createAccount", languageCode: appLanguage))
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
                vm.onAppear()
            }
        }
    }
}
