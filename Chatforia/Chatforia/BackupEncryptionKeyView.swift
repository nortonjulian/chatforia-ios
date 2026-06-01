import SwiftUI

struct BackupEncryptionKeyView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss

    let onCompleted: (() async -> Void)? = nil

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        explanationCard
                        formCard
                        footerNote
                    }
                    .padding(20)
                }
            }
            .navigationTitle(
                appText(
                    "encryption.backUpKey",
                    languageCode: appLanguage
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        appText(
                            "common.done",
                            languageCode: appLanguage
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                    .disabled(isSaving)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(themeManager.palette.accent)

                Text(appText("encryption.backup.headerTitle", languageCode: appLanguage))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
            }

            Text(appText("encryption.backup.headerSubtitle", languageCode: appLanguage))
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appText("common.howThisWorks", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            infoRow(
                icon: "key.fill",
                title: appText("encryption.backup.protectedTitle", languageCode: appLanguage),
                subtitle: appText("encryption.backup.protectedSubtitle", languageCode: appLanguage)
            )

            infoRow(
                icon: "iphone.and.arrow.forward",
                title: appText("encryption.backup.restoreDeviceTitle", languageCode: appLanguage),
                subtitle: appText("encryption.backup.restoreDeviceSubtitle", languageCode: appLanguage)
            )

            infoRow(
                icon: "exclamationmark.triangle.fill",
                title: appText("encryption.backup.passwordWarningTitle", languageCode: appLanguage),
                subtitle: appText("encryption.backup.passwordWarningSubtitle", languageCode: appLanguage)
            )
        }
        .padding(16)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appText("encryptionRecovery.actions.createBackup", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text(appText("encryption.backupPassword", languageCode: appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                ThemedSecureField(
                    title: "encryption.backupPassword",
                    text: $password
                )

                Text(appText("encryption.backup.minimumLength", languageCode: appLanguage))
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(appText("auth.confirmPassword", languageCode: appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                ThemedSecureField(
                    title: "auth.confirmPassword",
                    text: $confirmPassword
                )
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let successMessage, !successMessage.isEmpty {
                Text(successMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            Button {
                Task {
                    await backupKey()
                }
            } label: {
                HStack {
                    Spacer()

                    if isSaving {
                        ProgressView()
                    }

                    Text(
                        isSaving
                        ? appText("encryptionRecovery.messages.creatingBackup", languageCode: appLanguage)
                        : appText("encryptionRecovery.actions.createBackup", languageCode: appLanguage)
                    )
                    .fontWeight(.semibold)

                    Spacer()
                }
                .padding(.vertical, 14)
                .background(themeManager.palette.accent)
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isSaving || saveDisabled)
        }
        .padding(16)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var footerNote: some View {
        Text(appText(
            "encryption.backup.footerNote",
            languageCode: appLanguage
        ))
            .font(.footnote)
            .foregroundStyle(themeManager.palette.secondaryText)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 2)
    }

    private var saveDisabled: Bool {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedPassword.count < 6 || trimmedConfirm.count < 6
    }

    private func backupKey() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            errorMessage = appText("auth.sessionExpired", languageCode: appLanguage)
            successMessage = nil
            return
        }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPassword.isEmpty else {
            errorMessage = appText("encryption.backup.enterPassword", languageCode: appLanguage)
            successMessage = nil
            return
        }

        guard trimmedPassword.count >= 6 else {
            errorMessage = appText("encryption.backup.passwordTooShort", languageCode: appLanguage)
            successMessage = nil
            return
        }

        guard trimmedPassword == trimmedConfirm else {
            errorMessage = appText("auth.passwordsDoNotMatch", languageCode: appLanguage)
            successMessage = nil
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil

        do {
            guard let userId = auth.currentUser?.id else {
                throw RemoteKeyBackupError.invalidKeyMaterial
            }

            try await RemoteKeyBackupService.shared.uploadCurrentDeviceKeyBackup(
                token: token,
                userId: userId,
                password: trimmedPassword
            )

            successMessage = appText("encryption.backup.success", languageCode: appLanguage)
            password = ""
            confirmPassword = ""

            await onCompleted?()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func infoRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer()
        }
    }
}
