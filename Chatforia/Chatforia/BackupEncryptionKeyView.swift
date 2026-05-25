import SwiftUI

struct BackupEncryptionKeyView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
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
            .navigationTitle(String(localized: "encryption.backUpKey"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
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

                Text(String(localized: "encryption.backup.headerTitle"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
            }

            Text(String(localized: "encryption.backup.headerSubtitle"))
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "common.howThisWorks"))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            infoRow(
                icon: "key.fill",
                title: String(localized: "encryption.backup.protectedTitle"),
                subtitle: String(localized: "encryption.backup.protectedSubtitle")
            )

            infoRow(
                icon: "iphone.and.arrow.forward",
                title: String(localized: "encryption.backup.restoreDeviceTitle"),
                subtitle: String(localized: "encryption.backup.restoreDeviceSubtitle")
            )

            infoRow(
                icon: "exclamationmark.triangle.fill",
                title: String(localized: "encryption.backup.passwordWarningTitle"),
                subtitle: String(localized: "encryption.backup.passwordWarningSubtitle")
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
            Text(String(localized: "encryptionRecovery.actions.createBackup"))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "encryption.backupPassword"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                ThemedSecureField(
                    title: "encryption.backupPassword",
                    text: $password
                )

                Text(String(localized: "encryption.backup.minimumLength"))
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "auth.confirmPassword"))
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
                        ? String(localized: "encryptionRecovery.messages.creatingBackup")
                        : String(localized: "encryptionRecovery.actions.createBackup")
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
        Text(String(localized: "encryption.backup.footerNote"))
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
            errorMessage = String(localized: "auth.sessionExpired")
            successMessage = nil
            return
        }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPassword.isEmpty else {
            errorMessage = String(localized: "encryption.backup.enterPassword")
            successMessage = nil
            return
        }

        guard trimmedPassword.count >= 6 else {
            errorMessage = String(localized: "encryption.backup.passwordTooShort")
            successMessage = nil
            return
        }

        guard trimmedPassword == trimmedConfirm else {
            errorMessage = String(localized: "auth.passwordsDoNotMatch")
            successMessage = nil
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil

        do {
            try await RemoteKeyBackupService.shared.uploadCurrentDeviceKeyBackup(
                token: token,
                password: trimmedPassword
            )

            successMessage = String(localized: "encryption.backup.success")
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
