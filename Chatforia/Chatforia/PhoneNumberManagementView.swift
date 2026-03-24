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

                        Text(number.status ?? "Assigned")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(themeManager.palette.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(themeManager.palette.cardBackground)  
                            .clipShape(Capsule())
                    }

                    Button("Replace Number") {
                        showPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("No Chatforia number assigned")
                    .foregroundStyle(.secondary)

                Button(vm.currentNumber == nil ? "Pick a Number" : "Replace Number") {
                    showPicker = true
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Phone Number")
        .task {
            await vm.loadCurrentNumber(token: auth.currentToken)
        }
        .sheet(isPresented: $showPicker) {
            PickNumberSheet(vm: vm)
                .environmentObject(auth)
        }
    }
}
