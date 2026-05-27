import SwiftUI

struct RotateEncryptionKeyView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss

    let onCompleted: (() async -> Void)? = nil

    @State private var confirmationText = ""
    @State private var isRotating = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let requiredPhrase = "ROTATE"

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        warningCard
                        confirmCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle(appText("encryption.rotate.title", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appText("common.done", languageCode: appLanguage)) {
                        dismiss()
                    }
                    .disabled(isRotating)
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(themeManager.palette.accent)

                Text(appText("encryption.rotate.header", languageCode: appLanguage))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
            }

            Text(appText("encryption.rotate.subtitle", languageCode: appLanguage))
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appText("common.beforeYouContinue", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            warningRow(appText("encryption.rotate.backupWarning", languageCode: appLanguage))

            warningRow(appText("encryption.rotate.messageAccessWarning", languageCode: appLanguage))

            warningRow(appText("encryption.rotate.riskWarning", languageCode: appLanguage))
        }
        .padding(16)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var confirmCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appText("encryption.rotate.typeToContinue", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            TextField(
                appText("encryption.rotate.placeholder", languageCode: appLanguage),
                text: $confirmationText
            )
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)

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

            Button(role: .destructive) {
                Task {
                    await rotateKey()
                }
            } label: {
                HStack {
                    Spacer()

                    if isRotating {
                        ProgressView()
                    }

                    Text(
                        isRotating
                        ? appText("encryptionRecovery.messages.rotating", languageCode: appLanguage)
                        : appText("encryption.rotate.action", languageCode: appLanguage)
                    )
                    .fontWeight(.semibold)

                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .disabled(isRotating || confirmationText != requiredPhrase)
        }
        .padding(16)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func warningRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private func rotateKey() async {
        errorMessage = appText("encryption.rotate.backendNotConnected", languageCode: appLanguage)
        successMessage = nil
    }
}
