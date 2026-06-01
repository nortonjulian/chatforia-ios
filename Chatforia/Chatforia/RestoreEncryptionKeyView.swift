import SwiftUI

struct RestoreEncryptionKeyView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss

    let onCompleted: (() async -> Void)? = nil

    @State private var backupPassword = ""
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var hasRemoteBackup: Bool?
    @State private var isCheckingBackup = false
    
    @State private var showResetConfirm = false
    @State private var isResetting = false

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text(
                        appText(
                            "encryption.restore.title",
                            languageCode: appLanguage
                        )
                    )
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(themeManager.palette.primaryText)
                        .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(appText("encryption.restore.instructions", languageCode: appLanguage))
                            .font(.subheadline)
                            .foregroundStyle(themeManager.palette.secondaryText)

                        if isCheckingBackup {
                            ProgressView(
                                appText(
                                    "encryption.checkingBackup",
                                    languageCode: appLanguage
                                )
                            )
                        } else if hasRemoteBackup == false || hasRemoteBackup == nil {
                            Text(appText("encryption.restore.noBackup", languageCode: appLanguage))
                                .font(.footnote)
                                .foregroundStyle(themeManager.palette.secondaryText)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            if let successMessage {
                                Text(successMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }

                            Button(
                                appText(
                                    "common.done",
                                    languageCode: appLanguage
                                )
                            ) {
                                Task {
                                    await auth.refreshCurrentUser()

                                    if hasMatchingAccountKey() {
                                        auth.markKeyRestoreComplete()
                                        dismiss()
                                    } else {
                                        let message = appText(
                                            "encryption.restore.correctKeyMissing",
                                            languageCode: appLanguage
                                        )

                                        auth.forceKeyRestore(message: message)
                                        errorMessage = message
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        } else {
                            SecureField(
                                appText(
                                    "encryption.backupPassword",
                                    languageCode: appLanguage
                                ),
                                text: $backupPassword
                            )

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            if let successMessage {
                                Text(successMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }

                            Button {
                                Task { await restoreKey() }
                            } label: {
                                if isRestoring {
                                    ProgressView()
                                } else {
                                    Text(appText("encryption.restore.restoreKey", languageCode: appLanguage))
                                }
                            }
                            .disabled(isRestoring || backupPassword.isEmpty)
                        }
                    }
                    .padding()
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(appText(
                            "encryption.reset.title",
                            languageCode: appLanguage
                        ))
                            .font(.headline)
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text(appText(
                            "encryption.reset.description",
                            languageCode: appLanguage
                        ))
                            .font(.footnote)
                            .foregroundStyle(themeManager.palette.secondaryText)

                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            if isResetting {
                                ProgressView()
                            } else {
                                Text(
                            String(
                                localized:
                                "encryption.reset.title"
                            )
                        )
                            }
                        }
                        .disabled(isRestoring || isResetting)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .task {
            guard let token = auth.currentToken, !token.isEmpty else { return }
            isCheckingBackup = true
            hasRemoteBackup = await RemoteKeyBackupService.shared.hasRemoteBackup(token: token)
            isCheckingBackup = false
        }
        .confirmationDialog(
            appText(
                "encryption.reset.confirmationTitle",
                languageCode: appLanguage
            ),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(
                appText(
                    "encryption.reset.title",
                    languageCode: appLanguage
                ),
                role: .destructive
            ) {
                Task { await resetEncryption() }
            }
            Button(appText(
                "button_cancel",
                languageCode: appLanguage
            ), role: .cancel) {}
        } message: {
            Text(
                appText(
                    "encryption.reset.confirmationMessage",
                    languageCode: appLanguage
                )
            )
        }
    }
    
    private func resetEncryption() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            errorMessage = appText(
                "auth.sessionExpired",
                languageCode: appLanguage
            )
            return
        }

        isResetting = true
        errorMessage = nil
        successMessage = nil

        do {
            guard let userId = auth.currentUser?.id else {
                throw RemoteKeyBackupError.invalidKeyMaterial
            }

            try await AccountKeyManager.shared.resetAccountEncryption(
                userId: userId,
                token: token
            )

            try? await Task.sleep(nanoseconds: 500_000_000)

            if hasMatchingAccountKey() {
                successMessage = appText(
                    "encryption.reset.success",
                    languageCode: appLanguage
                )
                auth.markKeyRestoreComplete()
                dismiss()
            } else {
                auth.forceKeyRestore(message: appText(
                    "encryption.reset.deviceMismatch",
                    languageCode: appLanguage
                ))
                errorMessage =
                appText(
                    "encryption.reset.localFailure",
                    languageCode: appLanguage
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isResetting = false
    }

    private func hasMatchingAccountKey() -> Bool {
        let serverKey = auth.currentUser?.publicKey?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let localKey =
            auth.currentUser.flatMap {
                AccountKeyManager.shared.publicKeyBase64(userId: $0.id)
            }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return !serverKey.isEmpty && !localKey.isEmpty && serverKey == localKey
    }

    private func restoreKey() async {
        guard hasRemoteBackup == true else {
            errorMessage = appText(
                "encryption.restore.noBackupFirst",
                languageCode: appLanguage
            )
            return
        }

        guard let token = auth.currentToken, !token.isEmpty else {
            errorMessage =
            appText(
                "auth.sessionExpiredSignInAgain",
                languageCode: appLanguage
            )
            successMessage = nil
            return
        }

        isRestoring = true
        errorMessage = nil
        successMessage = nil

        do {
            guard let userId = auth.currentUser?.id else {
                throw RemoteKeyBackupError.invalidKeyMaterial
            }

            try await RemoteKeyBackupService.shared
                .restoreAccountKeysFromRemoteBackup(
                    token: token,
                    userId: userId,
                    password: backupPassword
                )

            successMessage = appText(
                "encryption.restore.success",
                languageCode: appLanguage
            )
            backupPassword = ""

            await onCompleted?()

            try? await Task.sleep(nanoseconds: 700_000_000)

            if hasMatchingAccountKey() {
                auth.markKeyRestoreComplete()
                dismiss()
            } else {
                auth.forceKeyRestore(message: appText(
                    "encryption.restore.deviceMismatch",
                    languageCode: appLanguage
                ))
                errorMessage =
                appText(
                    "encryption.restore.localFailure",
                    languageCode: appLanguage
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isRestoring = false
    }
}
