import SwiftUI

struct AttachmentPickerSheet: View {
    let onPhoto: () -> Void
    let onGIF: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .frame(width: 40, height: 5)
                .foregroundStyle(themeManager.palette.border.opacity(0.8))
                .padding(.top, 10)

            HStack(spacing: 30) {
                attachmentButton(
                    icon: "photo",
                    label: appText(
                        "messages.mediaPhoto",
                        languageCode: appLanguage
                    ),
                    action: onPhoto
                )
                
                attachmentButton(
                    icon: "video",
                    label: appText(
                        "messages.mediaVideo",
                        languageCode: appLanguage
                    ),
                    action: onPhoto // reuse same picker
                )

                attachmentButton(
                    icon: "sparkles",
                    label: appText(
                        "media.gif",
                        languageCode: appLanguage
                    ),
                    action: onGIF
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .background(themeManager.palette.cardBackground)
        .presentationDetents([.height(180)])
    }

    private func attachmentButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(themeManager.palette.accent.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(themeManager.palette.accent)
                    )

                Text(label)
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.primaryText)
            }
        }
        .buttonStyle(.plain)
    }
}
