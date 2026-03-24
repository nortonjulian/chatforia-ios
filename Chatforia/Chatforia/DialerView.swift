import SwiftUI

struct DialerView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var callManager: CallManager
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var digits = ""

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("Calls")
                .font(.headline.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Enter number", text: $digits)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .keyboardType(.phonePad)

            VStack(spacing: 10) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { digit in
                            Button {
                                digits.append(digit)
                            } label: {
                                Text(digit)
                                    .font(.title2.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 64)
                                    .background(themeManager.palette.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    guard !digits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    callManager.startCall(
                        to: .phoneNumber(digits, displayName: digits),
                        auth: auth
                    )
                } label: {
                    Label("Call", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    guard !digits.isEmpty else { return }
                    digits.removeLast()
                } label: {
                    Image(systemName: "delete.left")
                        .frame(width: 52, height: 44)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(16)
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
    }
}
