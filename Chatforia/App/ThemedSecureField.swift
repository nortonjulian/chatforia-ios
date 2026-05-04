import SwiftUI
import UIKit

struct ThemedSecureField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType? = nil

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        SecureField(title, text: $text)
            .textContentType(contentType)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(themeManager.palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(themeManager.palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(themeManager.palette.primaryText)
    }
}
