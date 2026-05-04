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
            .navigationTitle("Back Up Encryption Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
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

                Text("Protect Access to Your Messages")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
            }

            Text("Create a password-protected backup of your encryption key so you can restore access on a new device.")
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How this works")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            infoRow(
                icon: "key.fill",
                title: "Your encryption key stays protected",
                subtitle: "The backup is encrypted with the password you choose."
            )

            infoRow(
                icon: "iphone.and.arrow.forward",
                title: "Restore on another device",
                subtitle: "Use this backup later if this device is lost, replaced, or reset."
            )

            infoRow(
                icon: "exclamationmark.triangle.fill",
                title: "Don’t lose your backup password",
                subtitle: "Chatforia cannot recover it for you."
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
            Text("Create backup")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("Backup password")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                ThemedSecureField(
                    title: "Backup password",
                    text: $password
                )

                Text("Use at least 6 characters.")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm password")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                ThemedSecureField(
                    title: "Confirm password",
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

                    Text(isSaving ? "Creating Backup..." : "Create Backup")
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
        Text("This backup helps you restore your encrypted messages later. Keep your password somewhere safe.")
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
            errorMessage = "Your session expired. Please sign in again."
            successMessage = nil
            return
        }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPassword.isEmpty else {
            errorMessage = "Enter a backup password."
            successMessage = nil
            return
        }

        guard trimmedPassword.count >= 6 else {
            errorMessage = "Your backup password must be at least 6 characters."
            successMessage = nil
            return
        }

        guard trimmedPassword == trimmedConfirm else {
            errorMessage = "Passwords do not match."
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

            successMessage = "Your encryption key backup was created successfully."
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
