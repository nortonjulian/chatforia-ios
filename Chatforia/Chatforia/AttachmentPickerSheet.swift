import SwiftUI

struct AttachmentPickerSheet: View {
    let onPhoto: () -> Void
    let onGIF: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .frame(width: 40, height: 5)
                .foregroundColor(.gray.opacity(0.4))
                .padding(.top, 10)

            HStack(spacing: 30) {
                attachmentButton(
                    icon: "photo",
                    label: "Photo",
                    action: onPhoto
                )

                attachmentButton(
                    icon: "sparkles",
                    label: "GIF",
                    action: onGIF
                )
            }

            Spacer()
        }
        .padding()
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
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundColor(.orange)
                    )

                Text(label)
                    .font(.caption)
            }
        }
    }
}
