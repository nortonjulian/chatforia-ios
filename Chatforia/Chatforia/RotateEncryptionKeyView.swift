import SwiftUI

struct RotateEncryptionKeyView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
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
            .navigationTitle(
                String(localized: "encryption.rotate.title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
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

                Text(
                    String(localized: "encryption.rotate.header")
                )
                .font(.title3.weight(.bold))
                .foregroundStyle(themeManager.palette.primaryText)
            }

            Text(
                String(localized: "encryption.rotate.subtitle")
            )
            .font(.subheadline)
            .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "common.beforeYouContinue"))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            warningRow(
                String(localized: "encryption.rotate.backupWarning")
            )

            warningRow(
                String(localized: "encryption.rotate.messageAccessWarning")
            )

            warningRow(
                String(localized: "encryption.rotate.riskWarning")
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

    private var confirmCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                String(localized: "encryption.rotate.typeToContinue")
            )
            .font(.headline)
            .foregroundStyle(themeManager.palette.primaryText)

            TextField(
                String(localized: "encryption.rotate.placeholder"),
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
                        ? String(localized: "encryptionRecovery.messages.rotating")
                        : String(localized: "encryption.rotate.action")
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
        errorMessage = String(
            localized: "encryption.rotate.backendNotConnected"
        )
        successMessage = nil
    }
}