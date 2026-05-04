import SwiftUI

struct SoundSettingsView: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var upgradePrompt: UpgradePromptData?

    private var currentPlan: AppPlan {
        AppPlan(serverValue: auth.currentUser?.plan)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Volume")
                        .font(.headline)

                    Slider(
                        value: Binding(
                            get: { Double(settingsVM.soundVolume) },
                            set: { newValue in
                                settingsVM.soundVolume = Int(newValue)
                                persistLocalSoundSettings()
                            }
                        ),
                        in: 0...100,
                        step: 1
                    )

                    Text("\(settingsVM.soundVolume)%")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Text Tone") {
                ForEach(AppMessageTones.all) { tone in
                    toneRow(
                        title: tone.name,
                        code: tone.code,
                        requiredPlan: tone.requiredPlan,
                        isSelected: settingsVM.messageTone == tone.code,
                        previewAction: {
                            AudioPlayerService.shared.previewMessageTone(
                                filename: tone.code,
                                volume: settingsVM.soundVolume
                            )
                        },
                        selectAction: {
                            settingsVM.messageTone = tone.code
                            persistLocalSoundSettings()
                        }
                    )
                }
            }

            Section("Ringtone") {
                ForEach(AppRingtones.all) { tone in
                    toneRow(
                        title: tone.name,
                        code: tone.code,
                        requiredPlan: tone.requiredPlan,
                        isSelected: settingsVM.ringtone == tone.code,
                        previewAction: {
                            AudioPlayerService.shared.previewRingtone(
                                filename: tone.code,
                                volume: settingsVM.soundVolume
                            )
                        },
                        selectAction: {
                            settingsVM.ringtone = tone.code
                            persistLocalSoundSettings()
                        }
                    )
                }
            }
        }
        .navigationTitle("Sounds")
        .sheet(item: $upgradePrompt) { prompt in
            UpgradePromptSheet(
                title: prompt.title,
                message: prompt.message,
                requiredPlan: prompt.requiredPlan,
                onUpgradeTapped: {
                    // Navigate to upgrade screen if you already have a route.
                    upgradePrompt = nil
                }
            )
            .environmentObject(themeManager)
        }
        .onDisappear {
            AudioPlayerService.shared.stop()
        }
    }

    private func toneRow(
        title: String,
        code: String,
        requiredPlan: AppPlan,
        isSelected: Bool,
        previewAction: @escaping () -> Void,
        selectAction: @escaping () -> Void
    ) -> some View {
        let locked = !currentPlan.canAccess(requiredPlan)

        return HStack(spacing: 12) {
            Button {
                if locked {
                    upgradePrompt = UpgradePromptData(
                        title: "Premium Sound",
                        message: "\(title) is a premium sound. Upgrade to unlock premium text tones and ringtones.",
                        requiredPlan: requiredPlan
                    )
                } else {
                    selectAction()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .foregroundStyle(.primary)

                        if locked {
                            Text("Requires \(requiredPlan.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if locked {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(themeManager.palette.accent)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                if locked {
                    upgradePrompt = UpgradePromptData(
                        title: "Premium Sound",
                        message: "\(title) is a premium sound. Upgrade to preview and use it.",
                        requiredPlan: requiredPlan
                    )
                } else {
                    previewAction()
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(locked ? .secondary : themeManager.palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func persistLocalSoundSettings() {
        AudioPlayerService.shared.save(
            messageTone: settingsVM.messageTone,
            ringtone: settingsVM.ringtone,
            soundVolume: settingsVM.soundVolume
        )
    }
}

private struct UpgradePromptData: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let requiredPlan: AppPlan
}
