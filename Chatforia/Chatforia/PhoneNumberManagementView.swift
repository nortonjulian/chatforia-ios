import SwiftUI

struct PhoneNumberManagementView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @StateObject private var vm = PhoneNumberViewModel()
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 20) {

            if vm.isLoadingCurrent {
                ProgressView()

            } else if let number = vm.currentNumber {

                VStack(spacing: 12) {

                    VStack(spacing: 6) {

                        Text(number.e164)
                            .font(.title2.bold())

                        Text(
                            number.status ??
                            appText("phoneNumber.assigned", languageCode: appLanguage)
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(themeManager.palette.cardBackground)
                        .clipShape(Capsule())

                        if let days = vm.daysUntilRelease,
                           number.keepLocked != true {

                            Text(
                                String(
                                    format: appText("phoneNumber.releaseWarningFormat", languageCode: appLanguage),
                                    String(days),
                                    days == 1
                                        ? ""
                                        : appText("phoneNumber.pluralS", languageCode: appLanguage)
                                )
                            )
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                        }
                    }

                    ThemedGradientButton(
                        title: appText(
                            "phoneNumber.replaceNumber",
                            languageCode: appLanguage
                        ),
                        action: {
                            showPicker = true
                        }
                    )
                }

            } else {

                Text(
                    appText("phoneNumber.noNumberAssigned", languageCode: appLanguage)
                )
                .foregroundStyle(.secondary)

                ThemedGradientButton(
                    title: appText(
                        "phoneNumber.pickNumber",
                        languageCode: appLanguage
                    ),
                    action: {
                        showPicker = true
                    }
                )
            }

            Spacer()
        }
        .padding()
        .navigationTitle(
            appText("phoneNumber.title", languageCode: appLanguage)
        )
        .task {
            await vm.loadCurrentNumber(token: auth.currentToken)
        }
        .sheet(isPresented: $showPicker) {
            PickNumberSheet(vm: vm)
                .environmentObject(auth)
                .environmentObject(themeManager)
        }
    }
}
