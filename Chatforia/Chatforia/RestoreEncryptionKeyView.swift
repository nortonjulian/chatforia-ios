import SwiftUI

struct RestoreEncryptionKeyView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss

    let onCompleted: (() async -> Void)? = nil

    @State private var recoveryPasscode = ""
    @State private var confirmRecoveryPasscode = ""

    @State private var isRestoring = false
    @State private var isCreatingBackup = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var hasRemoteBackup: Bool?
    @State private var isCheckingBackup = false

    @State private var showStartFreshConfirm = false
    @State private var startFreshConfirmationText = ""
    @State private var isResetting = false

    private let startFreshPhrase = "START FRESH"

    private var canRestoreFromBackup: Bool {
        hasRemoteBackup == true
    }

    var body: some View {
        ZStack {
            themeManager.palette.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    titleSection

                    VStack(alignment: .leading, spacing: 16) {
                        if isCheckingBackup {
                            ProgressView("Checking secure message recovery…")
                        } else if canRestoreFromBackup {
                            restoreSection
                        } else if canCreateBackupFromThisDevice {
                            createBackupSection
                        } else {
                            noRecoverySection
                        }
                    }
                    .padding()

                    Divider()

                    resetSection
                }
                .padding(.horizontal, 20)
            }
        }
        .task {
            await checkBackup()
        }
        .confirmationDialog(
            "Start fresh with secure messages?",
            isPresented: $showStartFreshConfirm,
            titleVisibility: .visible
        ) {
            Button("Start Fresh", role: .destructive) {
                Task { await resetEncryption() }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This creates a new secure message key for your account. Older app-to-app secure messages may no longer be readable on any device. SMS/text message conversations are not affected.")
        }
    }

    private var titleSection: some View {
        VStack(spacing: 10) {
            Text(canRestoreFromBackup ? "Restore secure messages" : "Secure message recovery")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(themeManager.palette.primaryText)
                .padding(.top, 24)

            Text("Use your Secure Messages Passcode to protect or restore secure messages across devices.")
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Secure Messages Passcode")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text("Enter the Secure Messages Passcode you created on another trusted device.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            SecureField("Secure Messages Passcode", text: $recoveryPasscode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            statusMessages

            Button {
                Task { await restoreKey() }
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("Restore secure messages")
                        .fontWeight(.semibold)
                }
            }
            .disabled(isRestoring || recoveryPasscode.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var createBackupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Secure Messages Passcode")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text("This iPhone can already read your secure messages. Create a Secure Messages Passcode so you can restore them on the website, Android, or another iPhone.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            SecureField("Secure Messages Passcode", text: $recoveryPasscode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Confirm Secure Messages Passcode", text: $confirmRecoveryPasscode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            statusMessages

            Button {
                Task { await createRecoveryBackup() }
            } label: {
                if isCreatingBackup {
                    ProgressView()
                } else {
                    Text("Create Recovery Backup")
                        .fontWeight(.semibold)
                }
            }
            .disabled(isCreatingBackup || !canSubmitCreateBackup)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var noRecoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No recovery backup found")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text("This device does not have the correct secure message key, and no account recovery backup exists yet.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            Text("Open Chatforia on a device that can already read your secure messages, then create a Secure Messages Passcode there.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            statusMessages
        }
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("I can’t recover my secure messages")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text("Only use this as a last resort. This creates a new secure message key for your account. Older app-to-app secure messages may no longer be readable on any device. SMS/text message conversations are not affected.")
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)

            TextField("Type START FRESH to continue", text: $startFreshConfirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Button(role: .destructive) {
                showStartFreshConfirm = true
            } label: {
                if isResetting {
                    ProgressView()
                } else {
                    Text("Start fresh with secure messages")
                }
            }
            .disabled(
                isRestoring ||
                isCreatingBackup ||
                isResetting ||
                startFreshConfirmationText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased() != startFreshPhrase
            )
        }
    }

    private var statusMessages: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        }
    }

    private var canSubmitCreateBackup: Bool {
        let passcode = recoveryPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirm = confirmRecoveryPasscode.trimmingCharacters(in: .whitespacesAndNewlines)

        return passcode.count >= 8 && passcode == confirm
    }
    
    private var canCreateBackupFromThisDevice: Bool {
        hasRemoteBackup == false && hasLocalAccountKey()
    }

    private func hasLocalAccountKey() -> Bool {
        guard let userId = auth.currentUser?.id else { return false }

        let localPublicKey = AccountKeyManager.shared.publicKeyBase64(userId: userId)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let localPrivateKey = AccountKeyManager.shared.privateKeyBase64(userId: userId)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return !localPublicKey.isEmpty && !localPrivateKey.isEmpty
    }

    private func checkBackup() async {
        guard let token = auth.currentToken, !token.isEmpty else { return }

        isCheckingBackup = true
        hasRemoteBackup = await RemoteKeyBackupService.shared.hasRemoteBackup(token: token)
        isCheckingBackup = false
    }

    private func createRecoveryBackup() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            errorMessage = "Your session expired. Please sign in again."
            return
        }

        guard canSubmitCreateBackup else {
            errorMessage = "Secure Messages Passcodes must match and be at least 8 characters."
            return
        }

        guard let userId = auth.currentUser?.id else {
            errorMessage = "Missing user account."
            return
        }

        guard hasLocalAccountKey() else {
            errorMessage = "This device does not have a secure message key to back up."
            return
        }

        isCreatingBackup = true
        errorMessage = nil
        successMessage = nil

        do {
            try await RemoteKeyBackupService.shared.uploadCurrentDeviceKeyBackup(
                token: token,
                userId: userId,
                password: recoveryPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            hasRemoteBackup = true
            successMessage = "Recovery backup created. You can now use this Secure Messages Passcode on the website, Android, or another iPhone."
            confirmRecoveryPasscode = ""

            await auth.refreshCurrentUser()
            auth.markKeyRestoreComplete()

            await onCompleted?()

            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreatingBackup = false
    }

    private func restoreKey() async {
        guard hasRemoteBackup == true else {
            errorMessage = "No recovery backup found."
            return
        }

        guard let token = auth.currentToken, !token.isEmpty else {
            errorMessage = "Your session expired. Please sign in again."
            successMessage = nil
            return
        }

        guard recoveryPasscode.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 else {
            errorMessage = "Enter your Secure Messages Passcode."
            return
        }

        isRestoring = true
        errorMessage = nil
        successMessage = nil

        do {
            guard let userId = auth.currentUser?.id else {
                throw RemoteKeyBackupError.invalidKeyMaterial
            }

            try await RemoteKeyBackupService.shared.restoreAccountKeysFromRemoteBackup(
                token: token,
                userId: userId,
                password: recoveryPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            await auth.refreshCurrentUser()

            successMessage = "Secure messages restored."
            recoveryPasscode = ""

            await onCompleted?()

            try? await Task.sleep(nanoseconds: 700_000_000)

            if hasMatchingAccountKey() {
                auth.markKeyRestoreComplete()
                dismiss()
            } else {
                auth.forceKeyRestore(message: "The restored secure message key does not match this account.")
                errorMessage = "The restored secure message key does not match this account."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isRestoring = false
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
            guard let userId = auth.currentUser?.id else {
                throw RemoteKeyBackupError.invalidKeyMaterial
            }

            try await AccountKeyManager.shared.resetAccountEncryption(
                userId: userId,
                token: token
            )

            await auth.refreshCurrentUser()

            try? await Task.sleep(nanoseconds: 500_000_000)

            if hasMatchingAccountKey() {
                successMessage = "Fresh secure messages are ready."
                auth.markKeyRestoreComplete()
                dismiss()
            } else {
                auth.forceKeyRestore(message: "This device does not have the new secure message key.")
                errorMessage = "This device does not have the new secure message key."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isResetting = false
    }

    private func hasMatchingAccountKey() -> Bool {
        let serverKey = auth.currentUser?.publicKey?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let localKey = auth.currentUser.flatMap {
            AccountKeyManager.shared.publicKeyBase64(userId: $0.id)
        }?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return !serverKey.isEmpty && !localKey.isEmpty && serverKey == localKey
    }
}
