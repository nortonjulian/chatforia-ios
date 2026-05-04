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
            .navigationTitle("Rotate Encryption Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
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

                Text("Rotate Your Encryption Key")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)
            }

            Text("This creates a new encryption key for your account.")
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before you continue")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            warningRow("Back up your current key first.")
            warningRow("Older encrypted messages may become inaccessible unless migration support exists.")
            warningRow("Only do this if you understand the risk.")
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
            Text("Type ROTATE to continue")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            TextField("ROTATE", text: $confirmationText)
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
                    Text(isRotating ? "Rotating..." : "Rotate Encryption Key")
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
        errorMessage = "Rotation backend not connected yet."
        successMessage = nil
    }
}
