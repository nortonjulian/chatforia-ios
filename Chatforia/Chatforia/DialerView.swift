import SwiftUI
import UIKit

struct DialerView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var callManager: CallManager
    @EnvironmentObject private var themeManager: ThemeManager
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var digits = ""
    @State private var pressedDigit: String?
    @State private var isCalling = false
    @State private var savedContacts: [ContactDTO] = []
    
    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]
    
    var body: some View {
        GeometryReader { geo in
            let metrics = layoutMetrics(for: geo.size.height)

            VStack(spacing: 0) {
                VStack(spacing: metrics.stackSpacing) {
                    header
                    numberField
                }

                Spacer(minLength: 0)

                VStack(spacing: metrics.stackSpacing) {
                    keypad(buttonHeight: metrics.keyHeight)

                    callButtonRow(
                        buttonWidth: metrics.callButtonWidth,
                        buttonHeight: metrics.callButtonHeight
                    )
                }
                .padding(.bottom, metrics.bottomZoneBottomPadding)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                LinearGradient(
                    colors: [
                        themeManager.palette.screenBackground,
                        themeManager.palette.screenBackground.opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .task {
                await loadDialerContacts()
            }
        }
    }
    
    private var header: some View {
        HStack {
            Text("Dial")
                .font(.title2.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(themeManager.palette.accent)
        }
    }
    
    // MARK: - Display-only number field (no system keyboard)
    
    private var numberField: some View {
        HStack(spacing: 10) {
            Text(digits.isEmpty ? "Enter number" : formattedDisplayDigits)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(
                    digits.isEmpty
                    ? themeManager.palette.primaryText.opacity(0.28)
                    : themeManager.palette.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
            Spacer()
            
            if !digits.isEmpty {
                Button {
                    deleteLastDigit()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(themeManager.palette.primaryText.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            clearDigits()
                        }
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(themeManager.palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeManager.palette.border.opacity(0.9), lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(0.04),
            radius: 8,
            x: 0,
            y: 3
        )
        .animation(.easeOut(duration: 0.16), value: digits.isEmpty)
    }
    
    private var normalizedDialedNumber: String? {
        PhoneContactsService.normalizePhone(digits)
    }

    private var matchedContacts: [ContactDTO] {
        let typedDigits = digits.filter(\.isNumber)
        guard !typedDigits.isEmpty else { return [] }

        return savedContacts.filter { contact in
            guard let phone = contact.externalPhone else { return false }
            let contactDigits = phone.filter(\.isNumber)

            return contactDigits.contains(typedDigits)
        }
    }
    
    private func digitsOnly(_ value: String) -> String {
        value.filter(\.isNumber)
    }
    
    private func loadDialerContacts() async {
        guard let token = auth.currentToken, !token.isEmpty else { return }

        do {
            let response = try await ContactsService.shared.fetchContacts(token: token)
            savedContacts = response.items
        } catch {
            print("❌ Failed to load contacts for dialer:", error)
        }
    }

    private func displayName(for contact: ContactDTO) -> String {
        if let alias = contact.alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
            return alias
        }

        if let username = contact.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username
        }

        if let externalName = contact.externalName?.trimmingCharacters(in: .whitespacesAndNewlines), !externalName.isEmpty {
            return externalName
        }

        if let externalPhone = contact.externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !externalPhone.isEmpty {
            return externalPhone
        }

        return "Unknown Contact"
    }
    
    private var primaryMatch: ContactDTO? {
        matchedContacts.first
    }
    
    private var formattedDisplayDigits: String {
        if let primaryMatch {
            return displayName(for: primaryMatch)
        }
        return digits
    }
    
    // MARK: - Keypad
    
    private func keypad(buttonHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit in
                        digitButton(digit, buttonHeight: buttonHeight)
                    }
                }
            }
        }
    }
    
    private func digitButton(_ digit: String, buttonHeight: CGFloat) -> some View {
        Button {
            digits.append(digit)
            tapHaptic()
        } label: {
            VStack(spacing: 2) {
                Text(digit)
                    .font(.system(size: 29, weight: .medium, design: .rounded))
                    .foregroundStyle(themeManager.palette.primaryText)
                
                if let letters = letters(for: digit) {
                    Text(letters)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(themeManager.palette.primaryText.opacity(0.55))
                } else if digit == "0" {
                    Text("+")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(themeManager.palette.primaryText.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(themeManager.palette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(themeManager.palette.border.opacity(0.9), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(0.035),
                radius: 6,
                x: 0,
                y: 2
            )
            .scaleEffect(pressedDigit == digit ? 0.96 : 1.0)
            .brightness(pressedDigit == digit ? -0.02 : 0)
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
    
    // MARK: - Call button
    
    private func callButtonRow(buttonWidth: CGFloat, buttonHeight: CGFloat) -> some View {
        HStack {
            Spacer()
            
            Button {
                let trimmed = digits.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                
                isCalling = true
                tapHaptic()
                
                callManager.startCall(
                    to: .phoneNumber(trimmed, displayName: trimmed),
                    auth: auth
                )
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                    Text(isCalling ? "Calling..." : "Call")
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(themeManager.palette.buttonForeground)
                .frame(width: buttonWidth, height: buttonHeight)
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
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(
                    color: themeManager.palette.buttonEnd.opacity(0.20),
                    radius: 10,
                    x: 0,
                    y: 4
                )
            }
            .buttonStyle(.plain)
            .disabled(digits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(digits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.65 : 1.0)
            
            Spacer()
        }
        .padding(.top, 2)
    }
    
    // MARK: - Helpers
    
    private func deleteLastDigit() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
        tapHaptic()
    }
    
    private func clearDigits() {
        guard !digits.isEmpty else { return }
        digits.removeAll()
        tapHaptic()
    }
    
    private func letters(for digit: String) -> String? {
        switch digit {
        case "2": return "ABC"
        case "3": return "DEF"
        case "4": return "GHI"
        case "5": return "JKL"
        case "6": return "MNO"
        case "7": return "PQRS"
        case "8": return "TUV"
        case "9": return "WXYZ"
        default: return nil
        }
    }
    
    private func tapHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // MARK: - Device-tuned layout
    
    private func layoutMetrics(for height: CGFloat) -> DialerLayoutMetrics {
        switch height {
        case ..<700:
            return .init(
                stackSpacing: 14,
                keyHeight: 54,
                callButtonWidth: 210,
                callButtonHeight: 50,
                bottomZoneBottomPadding: 28
            )
        case 700..<850:
            return .init(
                stackSpacing: 16,
                keyHeight: 58,
                callButtonWidth: 220,
                callButtonHeight: 52,
                bottomZoneBottomPadding: 36
            )
        default:
            return .init(
                stackSpacing: 16,
                keyHeight: 60,
                callButtonWidth: 228,
                callButtonHeight: 54,
                bottomZoneBottomPadding: 44
            )
        }
    }
    
    private struct DialerLayoutMetrics {
        let stackSpacing: CGFloat
        let keyHeight: CGFloat
        let callButtonWidth: CGFloat
        let callButtonHeight: CGFloat
        let bottomZoneBottomPadding: CGFloat
    }
}
