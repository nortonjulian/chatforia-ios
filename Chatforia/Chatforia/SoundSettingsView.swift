import SwiftUI

struct SoundSettingsView: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @State private var upgradePrompt: UpgradePromptData?

    private var currentPlan: AppPlan {
        AppPlan(serverValue: auth.currentUser?.plan)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(appText("sound.volume", languageCode: appLanguage))
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

            Section(appText("sound.textTone", languageCode: appLanguage)) {
                ForEach(AppMessageTones.all) { tone in
                    toneRow(
                        title: appText(tone.localizationKey, languageCode: appLanguage),
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

            Section(appText("sheet_ringtone_title", languageCode: appLanguage)) {
                ForEach(AppRingtones.all) { tone in
                    toneRow(
                        title: appText(tone.localizationKey, languageCode: appLanguage),
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
        .navigationTitle(appText("sound.title", languageCode: appLanguage))
        .sheet(item: $upgradePrompt) { prompt in
            UpgradePromptSheet(
                title: prompt.title,
                message: prompt.message,
                requiredPlan: prompt.requiredPlan,
                onUpgradeTapped: {
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
                        title: appText("sound.premiumTitle", languageCode: appLanguage),
                        message: String(
                            format: appText("sound.upgradePreviewMessage", languageCode: appLanguage),
                            title
                        ),
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
                            Text(
                                appText("sound.requiresPlan", languageCode: appLanguage)
                                + " "
                                + planDisplayName(requiredPlan)
                            )
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
                        title: appText("sound.premiumTitle", languageCode: appLanguage),
                        message: String(
                            format: appText("sound.upgradeUnlockMessage", languageCode: appLanguage),
                            title
                        ),
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

    private func planDisplayName(_ plan: AppPlan) -> String {
        switch plan {
        case .free:
            return appText("billing.free", languageCode: appLanguage)
        case .plus:
            return appText("billing.plus", languageCode: appLanguage)
        case .premium:
            return appText("billing.premium", languageCode: appLanguage)
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
