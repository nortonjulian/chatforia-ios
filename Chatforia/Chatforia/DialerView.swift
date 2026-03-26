import SwiftUI
import UIKit

struct DialerView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var callManager: CallManager
    @EnvironmentObject private var themeManager: ThemeManager

    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""
    @State private var pressedDigit: String?

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var body: some View {
        VStack(spacing: 20) {
            header

            numberField

            keypad

            actionRow

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("Dial")
                .font(.title3.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(themeManager.palette.accent)
        }
    }

    private var numberField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Enter number", text: $digits)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(themeManager.palette.primaryText)
                .keyboardType(.phonePad)
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(themeManager.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var keypad: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { digit in
                        digitButton(digit)
                    }
                }
            }
        }
    }

    private func digitButton(_ digit: String) -> some View {
        Button {
            digits.append(digit)
            tapHaptic()
        } label: {
            Text(digit)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(themeManager.palette.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(themeManager.palette.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )
                .scaleEffect(pressedDigit == digit ? 0.96 : 1.0)
                .animation(.easeOut(duration: 0.12), value: pressedDigit)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if pressedDigit != digit {
                        pressedDigit = digit
                    }
                }
                .onEnded { _ in
                    pressedDigit = nil
                }
        )
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                let trimmed = digits.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                callManager.startCall(
                    to: .phoneNumber(trimmed, displayName: trimmed),
                    auth: auth
                )
            } label: {
                Label("Call", systemImage: "phone.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(themeManager.palette.accent)

            Button {
                guard !digits.isEmpty else { return }
                digits.removeLast()
                tapHaptic()
            } label: {
                Image(systemName: "delete.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 56, height: 48)
            }
            .buttonStyle(.bordered)
            .tint(themeManager.palette.accent)
        }
    }

    private func tapHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
