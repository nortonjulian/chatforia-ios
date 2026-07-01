import SwiftUI
import UIKit

struct ActiveCallView: View {
    @EnvironmentObject private var callManager: CallManager
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var isShowingCallOptions = false
    @State private var isShowingAddParticipant = false
    
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @State private var isShowingKeypad = false

    private var stateLabel: String {
        callManager.state.label
    }

    var body: some View {
        let session = callManager.activeSession

        ZStack {
            LinearGradient(
                colors: [
                    themeManager.palette.screenBackground,
                    themeManager.palette.cardBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Text(
                        session?.displayName ??
                        appText(
                            "calls.call",
                            languageCode: appLanguage
                        )
                    )
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(themeManager.palette.primaryText)
                        .multilineTextAlignment(.center)

                    Text(stateLabel)
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }

                Spacer()

                HStack(spacing: 12) {
                    CallControlButton(
                        systemName: (session?.isMuted ?? false) ? "mic.slash.fill" : "mic.fill",
                        title: (session?.isMuted ?? false) ? "Unmute" : "Mute",
                        isActive: session?.isMuted ?? false
                    ) {
                        callManager.toggleMute()
                    }

                    CallControlButton(
                        systemName: (session?.isSpeakerOn ?? false) ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
                        title: "Speaker",
                        isActive: session?.isSpeakerOn ?? false
                    ) {
                        callManager.toggleSpeaker()
                    }

                    CallControlButton(
                        systemName: "ellipsis",
                        title: "More"
                    ) {
                        isShowingCallOptions = true
                    }

                    CallControlButton(
                        systemName: "phone.down.fill",
                        title: "End",
                        isDestructive: true
                    ) {
                        callManager.hangup()
                    }
                }
                .padding(.bottom, 46)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $isShowingKeypad) {
            InCallKeypadSheet { digit in
                callManager.sendDigit(digit)
            }
            .environmentObject(themeManager)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingCallOptions) {
            InCallOptionsSheet(
                canAddParticipant: session?.canAddParticipant ?? false,
                onAddParticipant: {
                    isShowingCallOptions = false
                    isShowingAddParticipant = true
                },
                onKeypad: {
                    isShowingCallOptions = false
                    isShowingKeypad = true
                }
            )
            .environmentObject(themeManager)
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingAddParticipant) {
            InCallAddParticipantSheet { contact in
                Task {
                    await callManager.addParticipant(contact: contact)
                }
            }
            .environmentObject(themeManager)
        }
    }
}

private struct CallControlButton: View {
    let systemName: String
    let title: String
    var isActive: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 62, height: 62)
                    .background(backgroundColor)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }

            Text(title)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
    }

    private var backgroundColor: Color {
        if isDestructive { return .red }
        if isActive { return .blue }
        return Color.black.opacity(0.72)
    }
}

private struct InCallOptionsSheet: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    let canAddParticipant: Bool
    let onAddParticipant: () -> Void
    let onKeypad: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Call Options")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Button {
                onAddParticipant()
            } label: {
                optionRow(
                    icon: "person.badge.plus",
                    title: "Add Participant",
                    subtitle: canAddParticipant ? "Invite someone into this call" : "Limit reached"
                )
            }
            .disabled(!canAddParticipant)
            .opacity(canAddParticipant ? 1 : 0.45)

            Button {
                onKeypad()
            } label: {
                optionRow(
                    icon: "circle.grid.3x3.fill",
                    title: "Keypad",
                    subtitle: "Send dial tones"
                )
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
    }


    private func optionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(themeManager.palette.cardBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer()
        }
        .foregroundStyle(themeManager.palette.primaryText)
        .padding(.vertical, 10)
    }
}

    private struct InCallAddParticipantSheet: View {
        @EnvironmentObject private var auth: AuthStore
        @EnvironmentObject private var themeManager: ThemeManager
        @Environment(\.dismiss) private var dismiss

        @StateObject private var vm = ContactsViewModel()

        let onPick: (ContactDTO) -> Void

        var body: some View {
            NavigationStack {
                ZStack {
                    themeManager.palette.screenBackground
                        .ignoresSafeArea()

                    List {
                        ForEach(vm.contacts.filter { ($0.user?.id ?? $0.userId) != nil }) { contact in
                            Button {
                                onPick(contact)
                                dismiss()
                            } label: {
                                ContactRowView(
                                    title: vm.displayName(for: contact),
                                    subtitle: vm.subtitle(for: contact),
                                    favorite: contact.favorite ?? false
                                )
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .navigationTitle("Add Participant")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $vm.searchText)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(themeManager.palette.accent)
                    }
                }
                .task {
                    await vm.loadContacts(token: auth.currentToken)
                }
                .onChange(of: vm.searchText) { _, _ in
                    Task {
                        await vm.loadContacts(token: auth.currentToken)
                    }
                }
            }
        }
    }

private struct InCallKeypadSheet: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""

    let onDigit: (String) -> Void

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text("Keypad")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(themeManager.palette.accent)
            }

            Text(digits.isEmpty ? "Enter digits" : digits)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(
                    digits.isEmpty
                    ? themeManager.palette.secondaryText.opacity(0.55)
                    : themeManager.palette.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 42)

            VStack(spacing: 12) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { digit in
                            digitButton(digit)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
    }

    private func digitButton(_ digit: String) -> some View {
        Button {
            digits.append(digit)
            onDigit(digit)

            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            VStack(spacing: 3) {
                Text(digit)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(themeManager.palette.primaryText)

                if let letters = letters(for: digit) {
                    Text(letters)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(themeManager.palette.secondaryText)
                } else {
                    Text(" ")
                        .font(.system(size: 10))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(themeManager.palette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(themeManager.palette.border.opacity(0.9), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
}