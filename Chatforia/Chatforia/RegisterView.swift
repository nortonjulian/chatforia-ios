import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @StateObject private var vm = RegisterViewModel()

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    formCard
                }
                .padding()
            }
        }
        .navigationTitle(appText("common.register", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(appText("auth.createYourAccount", languageCode: appLanguage))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .multilineTextAlignment(.center)

            Text(appText("auth.signupSubtitle", languageCode: appLanguage))
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 28)
    }

    private var formCard: some View {
        VStack(spacing: 16) {
            oauthButtons
            divider

            ThemedTextField(
                title: appText("auth.username", languageCode: appLanguage),
                text: $vm.username,
                contentType: .username
            )

            ThemedTextField(
                title: appText("auth.email", languageCode: appLanguage),
                text: $vm.email,
                keyboard: .emailAddress,
                contentType: .emailAddress
            )

            ThemedSecureField(
                title: appText("auth.password", languageCode: appLanguage),
                text: $vm.password,
                contentType: .newPassword
            )

            ThemedSecureField(
                title: appText("auth.confirmPassword", languageCode: appLanguage),
                text: $vm.confirmPassword,
                contentType: .newPassword
            )

            ThemedTextField(
                title: appText("auth.phoneOptional", languageCode: appLanguage),
                text: $vm.phone,
                keyboard: .phonePad,
                contentType: .telephoneNumber
            )

            if !vm.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ThemedToggleRow(
                    title: appText("auth.smsConsent", languageCode: appLanguage),
                    subtitle: appText("auth.smsConsentSubtitle", languageCode: appLanguage),
                    isOn: $vm.smsConsent
                )
            }

            messagesSection

            ThemedGradientButton(
                title: vm.isSubmitting
                    ? appText("auth.creatingAccount", languageCode: appLanguage)
                    : appText("auth.createAccount", languageCode: appLanguage),
                action: {
                    Task {
                        await vm.submit(auth: auth, languageCode: appLanguage)
                    }
                },
                isFullWidth: true,
                isDisabled: vm.isSubmitting || vm.isOAuthLoading
            )

            footerSection
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

    private var oauthButtons: some View {
        HStack(spacing: 12) {
            ThemedOutlineButton(
                title: vm.isOAuthLoading
                    ? appText("auth.continueWithGoogle", languageCode: appLanguage)
                    : appText("auth.google", languageCode: appLanguage)
            ) {
                Task {
                    await vm.handleGoogle(auth: auth)
                }
            }
            .disabled(vm.isSubmitting || vm.isOAuthLoading)

            ThemedOutlineButton(
                title: vm.isOAuthLoading
                    ? appText("auth.continueWithApple", languageCode: appLanguage)
                    : appText("auth.apple", languageCode: appLanguage)
            ) {
                Task {
                    await vm.handleApple(auth: auth)
                }
            }
            .disabled(vm.isSubmitting || vm.isOAuthLoading)
        }
    }

    private var divider: some View {
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
    }

    private var messagesSection: some View {
        VStack(spacing: 8) {
            if let errorMessage = vm.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let successMessage = vm.successMessage {
                Text(successMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text(appText("auth.alreadyHaveAnAccount", languageCode: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)

                Text(appText("auth.loginPreviousScreen", languageCode: appLanguage))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(themeManager.palette.accent)
            }
            .padding(.top, 4)

            Text(appText("auth.termsAgreement", languageCode: appLanguage))
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }
}
