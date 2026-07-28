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

    @State private var hasRemoteBackup: Bool?
    @State private var isCheckingBackupStatus = true
    @State private var localKeyMatchesAccount = false

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
            .navigationTitle(backupNavigationTitle)
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
            .task {
                await loadBackupStatus()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(themeManager.palette.accent)

                Text(backupHeaderTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
            }

            Text(backupHeaderSubtitle)
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
            if isCheckingBackupStatus {
                HStack(spacing: 10) {
                    ProgressView()

                    Text("Checking recovery backup…")
                        .font(.subheadline)
                        .foregroundStyle(
                            themeManager.palette.secondaryText
                        )
                }
            }

            Text(backupFormTitle)
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
                            .tint(themeManager.palette.buttonForeground)
                    }

                    Text(
                        isSaving
                        ? backupSavingTitle
                        : backupActionTitle
                    )
                    .fontWeight(.semibold)

                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [
                            themeManager.palette.buttonStart,
                            themeManager.palette.buttonEnd
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(themeManager.palette.buttonForeground)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving || saveDisabled)
            .opacity(isSaving || saveDisabled ? 0.65 : 1)
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

    private var backupNavigationTitle: String {
        hasRemoteBackup == true
        ? "Update Secure Message Backup"
        : appText(
            "encryption.backUpKey",
            languageCode: appLanguage
        )
    }

    private var backupHeaderTitle: String {
        hasRemoteBackup == true
        ? "Update your recovery backup"
        : appText(
            "encryption.backup.headerTitle",
            languageCode: appLanguage
        )
    }

    private var backupHeaderSubtitle: String {
        if hasRemoteBackup == true {
            return "A recovery backup is already saved. Enter a new Secure Messages Passcode only when you want to replace the existing backup."
        }

        return appText(
            "encryption.backup.headerSubtitle",
            languageCode: appLanguage
        )
    }

    private var backupFormTitle: String {
        hasRemoteBackup == true
        ? "Update backup"
        : appText(
            "encryptionRecovery.actions.createBackup",
            languageCode: appLanguage
        )
    }

    private var backupActionTitle: String {
        hasRemoteBackup == true
        ? "Update backup"
        : appText(
            "encryptionRecovery.actions.createBackup",
            languageCode: appLanguage
        )
    }

    private var backupSavingTitle: String {
        hasRemoteBackup == true
        ? "Updating backup…"
        : appText(
            "encryptionRecovery.messages.creatingBackup",
            languageCode: appLanguage
        )
    }

    private var saveDisabled: Bool {
        let trimmedPassword =
            password.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let trimmedConfirm =
            confirmPassword.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return
            isCheckingBackupStatus ||
            !localKeyMatchesAccount ||
            trimmedPassword.count < 8 ||
            trimmedConfirm.count < 8 ||
            trimmedPassword != trimmedConfirm
    }

    private func loadBackupStatus() async {
        guard
            let token = auth.currentToken,
            !token.isEmpty
        else {
            isCheckingBackupStatus = false
            errorMessage =
                SecureMessagesErrorPresenter.message(
                    for: RemoteKeyBackupError.sessionExpired
                )
            return
        }

        isCheckingBackupStatus = true
        errorMessage = nil

        await auth.refreshCurrentUser()

        localKeyMatchesAccount =
            hasMatchingAccountKey()

        do {
            let response =
                try await RemoteKeyBackupService.shared
                    .fetchRemoteKeyBackupResponse(
                        token: token
                    )

            hasRemoteBackup =
                response.hasBackup
                ?? (response.keys?
                    .encryptedPrivateKeyBundle != nil)

            if !localKeyMatchesAccount {
                errorMessage =
                    "This iPhone’s secure message key does not match the account key. Restore secure messages before creating or updating the recovery backup."
            }

        } catch {
            hasRemoteBackup = nil
            errorMessage =
                SecureMessagesErrorPresenter.message(
                    for: error
                )
        }

        isCheckingBackupStatus = false
    }

    private func hasMatchingAccountKey() -> Bool {
        guard let user = auth.currentUser else {
            return false
        }

        let serverPublicKey =
            user.publicKey?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        let localPublicKey =
            AccountKeyManager.shared
                .publicKeyBase64(userId: user.id)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        let localPrivateKey =
            AccountKeyManager.shared
                .privateKeyBase64(userId: user.id)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

        return
            !serverPublicKey.isEmpty &&
            !localPublicKey.isEmpty &&
            !localPrivateKey.isEmpty &&
            serverPublicKey == localPublicKey
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

        guard trimmedPassword.count >= 8 else {
            errorMessage = "Secure Messages Passcode must be at least 8 characters."
            successMessage = nil
            return
        }

        guard trimmedPassword == trimmedConfirm else {
            errorMessage = appText(
                "auth.passwordsDoNotMatch",
                languageCode: appLanguage
            )
            successMessage = nil
            return
        }

        guard localKeyMatchesAccount else {
            errorMessage =
                "This iPhone’s secure message key does not match the account key. Restore secure messages before changing the recovery backup."
            successMessage = nil
            return
        }

        let wasUpdatingExistingBackup =
            hasRemoteBackup == true

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

            let verification =
                try await RemoteKeyBackupService.shared
                    .fetchRemoteKeyBackupResponse(
                        token: token
                    )

            let backupExists =
                verification.hasBackup
                ?? (verification.keys?
                    .encryptedPrivateKeyBundle != nil)

            guard backupExists else {
                throw RemoteKeyBackupError.requestFailed
            }

            hasRemoteBackup = true

            successMessage =
                wasUpdatingExistingBackup
                ? "Recovery backup updated."
                : appText(
                    "encryption.backup.success",
                    languageCode: appLanguage
                )

            password = ""
            confirmPassword = ""

            await onCompleted?()
        } catch {
            errorMessage =
                SecureMessagesErrorPresenter.message(
                    for: error
                )
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
