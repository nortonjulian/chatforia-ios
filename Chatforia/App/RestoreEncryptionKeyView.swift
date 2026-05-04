import SwiftUI

struct RestoreEncryptionKeyView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
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
                    Text("Restore Encryption Key")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(themeManager.palette.primaryText)
                        .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter the backup password you created when you saved your encryption key.")
                            .font(.subheadline)
                            .foregroundStyle(themeManager.palette.secondaryText)

                        if isCheckingBackup {
                            ProgressView("Checking backup…")
                        } else if hasRemoteBackup == false || hasRemoteBackup == nil {
                            Text("No backup found. Create one to protect your messages.")
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

                            Button("Done") {
                                Task {
                                    await auth.refreshCurrentUser()

                                    if hasMatchingAccountKey() {
                                        auth.markKeyRestoreComplete()
                                        dismiss()
                                    } else {
                                        auth.forceKeyRestore(message: "This device still does not have the correct encryption key.")
                                        errorMessage = "This device still does not have the correct encryption key."
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        } else {
                            SecureField("Backup password", text: $backupPassword)

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
                                    Text("Restore Key")
                                }
                            }
                            .disabled(isRestoring || backupPassword.isEmpty)
                        }
                    }
                    .padding()
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reset Encryption")
                            .font(.headline)
                            .foregroundStyle(themeManager.palette.primaryText)

                        Text("This will generate a new encryption key for your account. Older encrypted messages may become unreadable unless you restore your original key.")
                            .font(.footnote)
                            .foregroundStyle(themeManager.palette.secondaryText)

                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            if isResetting {
                                ProgressView()
                            } else {
                                Text("Reset Encryption")
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
            "Reset encryption?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Encryption", role: .destructive) {
                Task { await resetEncryption() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your encryption key. Older encrypted messages may not be readable unless you restore your original key.")
        }
    }
    
    private func resetEncryption() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            errorMessage = "Your session expired. Please sign in again."
            return
        }

        isResetting = true
        errorMessage = nil
        successMessage = nil

        do {
            try await AccountKeyManager.shared.resetAccountEncryption(token: token)

            try? await Task.sleep(nanoseconds: 500_000_000)

            if hasMatchingAccountKey() {
                successMessage = "Encryption was reset successfully."
                auth.markKeyRestoreComplete()
                dismiss()
            } else {
                auth.forceKeyRestore(message: "Encryption reset did not complete correctly on this device.")
                errorMessage = "Encryption reset did not complete correctly on this device."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isResetting = false
    }

    private func hasMatchingAccountKey() -> Bool {
        let serverKey = auth.currentUser?.publicKey?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let localKey = AccountKeyManager.shared.publicKeyBase64()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return !serverKey.isEmpty && !localKey.isEmpty && serverKey == localKey
    }

    private func restoreKey() async {
        guard hasRemoteBackup == true else {
            errorMessage = "No backup found. Please create a backup first."
            return
        }

        guard let token = auth.currentToken, !token.isEmpty else {
            errorMessage = "Your session expired. Please sign in again."
            successMessage = nil
            return
        }

        isRestoring = true
        errorMessage = nil
        successMessage = nil

        do {
            try await RemoteKeyBackupService.shared.restoreAccountKeysFromRemoteBackup(
                token: token,
                password: backupPassword
            )

            successMessage = "Your encryption key was restored successfully."
            backupPassword = ""

            await onCompleted?()

            try? await Task.sleep(nanoseconds: 700_000_000)

            if hasMatchingAccountKey() {
                auth.markKeyRestoreComplete()
                dismiss()
            } else {
                auth.forceKeyRestore(message: "Key restore did not complete correctly on this device.")
                errorMessage = "Key restore did not complete correctly on this device."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isRestoring = false
    }
}
