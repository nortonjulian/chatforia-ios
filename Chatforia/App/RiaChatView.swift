import SwiftUI

struct RiaChatView: View {
    @StateObject private var vm = RiaChatViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var draft = ""
    @State private var memoryEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            header

            if let aiDisabledReason = vm.aiDisabledReason, !aiDisabledReason.isEmpty {
                Text(aiDisabledReason)
                    .font(.footnote)
                    .foregroundStyle(themeManager.palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(themeManager.palette.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            } else if let lastError = vm.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        systemIntroPill

                        ForEach(vm.messages) { msg in
                            HStack {
                                if msg.role == "assistant" {
                                    Text(msg.content)
                                        .font(.body)
                                        .foregroundStyle(themeManager.palette.primaryText)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(themeManager.palette.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    Spacer(minLength: 40)
                                } else {
                                    Spacer(minLength: 40)
                                    Text(msg.content)
                                        .font(.body)
                                        .foregroundStyle(themeManager.palette.composerButtonForeground)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            LinearGradient(
                                                colors: [
                                                    themeManager.palette.composerButtonStart,
                                                    themeManager.palette.composerButtonEnd
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }
                            .id(msg.id)
                        }

                        if vm.isLoading {
                            HStack {
                                ProgressView()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(themeManager.palette.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                }
                .background(themeManager.palette.screenBackground)
                .onChange(of: vm.messages.count) { _, _ in
                    if let lastId = vm.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            composer
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .navigationTitle("Ria")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let user = auth.currentUser {
                settingsVM.load(from: user)
            }
            settingsVM.loadLocalAISettings()
            memoryEnabled = settingsVM.foriaRemember
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Ria")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text("AI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(themeManager.palette.cardBackground)
                    .clipShape(Capsule())
            }

            Text("Chat with Ria anytime — separate from random human matching.")
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.cardBackground)
        .overlay(
            Rectangle()
                .fill(themeManager.palette.border.opacity(0.8))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var systemIntroPill: some View {
        Text("YOU'RE NOW CHATTING WITH RIA.")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(themeManager.palette.secondaryText.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(themeManager.palette.cardBackground)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Ria...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(themeManager.palette.primaryText)
                .lineLimit(1...5)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .background(themeManager.palette.composerFieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(themeManager.palette.composerBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                let text = draft
                draft = ""

                Task {
                    await vm.sendMessage(
                        token: auth.currentToken,
                        text: text,
                        memoryEnabled: memoryEnabled,
                        filterProfanity: settingsVM.maskAIProfanity
                    )
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.palette.composerButtonStart,
                                    themeManager.palette.composerButtonEnd
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    if vm.isLoading {
                        ProgressView()
                            .tint(themeManager.palette.composerButtonForeground)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(themeManager.palette.composerButtonForeground)
                    }
                }
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(themeManager.palette.composerBackground)
    }
}
