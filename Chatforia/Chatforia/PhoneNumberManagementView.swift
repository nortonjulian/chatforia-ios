import SwiftUI

struct PhoneNumberManagementView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

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
                            String(localized: "phoneNumber.assigned")
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
                                    format: String(
                                        localized: "phoneNumber.releaseWarningFormat"
                                    ),
                                    String(days),
                                    days == 1
                                        ? ""
                                        : String(localized: "phoneNumber.pluralS")
                                )
                            )
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                        }
                    }

                    Button(
                        String(localized: "phoneNumber.replaceNumber")
                    ) {
                        showPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }

            } else {

                Text(
                    String(localized: "phoneNumber.noNumberAssigned")
                )
                .foregroundStyle(.secondary)

                Button(
                    vm.currentNumber == nil
                        ? String(localized: "phoneNumber.pickNumber")
                        : String(localized: "phoneNumber.replaceNumber")
                ) {
                    showPicker = true
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
        .navigationTitle(
            String(localized: "phoneNumber.title")
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
