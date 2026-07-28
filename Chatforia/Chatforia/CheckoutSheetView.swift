import SwiftUI

struct CheckoutSheetView: View {
    let pack: DataPackOption
    let onConfirm: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        VStack(spacing: 20) {
            Text(appText("upgrade.confirmPurchase", languageCode: appLanguage))
                .font(.title2.bold())
                .foregroundStyle(themeManager.palette.primaryText)

            VStack(spacing: 10) {
                Text(pack.title(languageCode: appLanguage))
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(pack.displayDataAmount(languageCode: appLanguage))
                    .font(.title3.bold())
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(pack.description(languageCode: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Divider()

            VStack(spacing: 12) {
                feature(
                    appText(
                        "ios.activates_automatically_on_first_data_connection",
                        languageCode: appLanguage,
                        fallback:
                            "Activates automatically on first data connection"
                    )
                )

                feature(
                    appText(
                        "ios.valid_for_30_days_from_first_data_connection",
                        languageCode: appLanguage,
                        fallback:
                            "Valid for 30 days from first data connection"
                    )
                )

                feature(
                    appText(
                        "ios.one_time_purchase_with_no_contract",
                        languageCode: appLanguage,
                        fallback:
                            "One-time purchase with no contract"
                    )
                )

                feature(
                    appText(
                        "ios.top_up_anytime",
                        languageCode: appLanguage,
                        fallback: "Top up anytime"
                    )
                )
            }

            Spacer()

            Button {
                onConfirm()
            } label: {
                Text(
                    appText(
                        "upgrade.checkout.buyDataPack",
                        languageCode: appLanguage,
                        fallback: "Buy data pack"
                    )
                )
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.buttonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [
                                themeManager.palette.buttonStart,
                                themeManager.palette.buttonEnd
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(appText("button_cancel", languageCode: appLanguage)) {
                dismiss()
            }
            .font(.footnote)
            .foregroundStyle(themeManager.palette.secondaryText)
        }
        .padding()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .background(themeManager.palette.screenBackground)
    }

    private func feature(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(themeManager.palette.accent)

            Text(text)
                .foregroundStyle(themeManager.palette.primaryText)

            Spacer()
        }
    }
}
