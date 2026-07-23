import SwiftUI

struct AccessibilitySettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("chatforia_language") private var appLanguage = "en"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionCardView(title: appText("accessibility_title", languageCode: appLanguage)) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker(
                            appText("accessibility_interface_font_size", languageCode: appLanguage),
                            selection: $vm.a11yUiFont
                        ) {
                            ForEach(A11yFontSize.allCases) { size in
                                Text(appText(size.labelKey, languageCode: appLanguage))
                                    .tag(size.rawValue)
                            }
                        }

                        Text(appText("accessibility_interface_font_size_help", languageCode: appLanguage))
                            .font(.caption)
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }
                }

                SectionCardView(title: appText("accessibility_notifications", languageCode: appLanguage)) {
                    VStack(spacing: 14) {
                        ThemedToggleRow(
                            title: appText("accessibility_visual_alerts", languageCode: appLanguage),
                            isOn: $vm.a11yVisualAlerts
                        )

                        ThemedToggleRow(
                            title: appText("accessibility_vibrate_on_new", languageCode: appLanguage),
                            isOn: $vm.a11yVibrate
                        )

                        ThemedToggleRow(
                            title: appText("accessibility_flash_on_call", languageCode: appLanguage),
                            isOn: Binding(
                                get: { reduceMotion ? false : vm.a11yFlashOnCall },
                                set: { vm.a11yFlashOnCall = reduceMotion ? false : $0 }
                            )
                        )

                        if reduceMotion {
                            Text(appText("accessibility_flash_disabled_reduce_motion", languageCode: appLanguage))
                                .font(.caption)
                                .foregroundStyle(themeManager.palette.secondaryText)
                        }
                    }
                }

                SectionCardView(title: appText("accessibility_live_captions", languageCode: appLanguage)) {
                    VStack(alignment: .leading, spacing: 14) {
                        ThemedToggleRow(
                            title: appText("accessibility_enable_live_captions", languageCode: appLanguage),
                            isOn: $vm.a11yLiveCaptions
                        )

                        Picker(
                            appText("accessibility_caption_font_size", languageCode: appLanguage),
                            selection: $vm.a11yCaptionFont
                        ) {
                            ForEach(A11yFontSize.allCases) { size in
                                Text(appText(size.labelKey, languageCode: appLanguage))
                                    .tag(size.rawValue)
                            }
                        }

                        Picker(
                            appText("accessibility_caption_background", languageCode: appLanguage),
                            selection: $vm.a11yCaptionBg
                        ) {
                            ForEach(A11yCaptionBackground.allCases) { bg in
                                Text(appText(bg.labelKey, languageCode: appLanguage))
                                    .tag(bg.rawValue)
                            }
                        }
                    }
                }

                SectionCardView(title: appText("accessibility_voice_notes", languageCode: appLanguage)) {
                    ThemedToggleRow(
                        title: appText("accessibility_auto_transcribe_voice_notes", languageCode: appLanguage),
                        isOn: $vm.a11yVoiceNoteSTT
                    )
                }

                ThemedGradientButton(
                    title: appText(
                        "button_save_settings",
                        languageCode: appLanguage
                    ),
                    action: {
                        Task {
                            await saveAccessibility()
                        }
                    },
                    horizontalPadding: 24,
                    isDisabled: vm.isSaving
                )

                if let error = vm.saveError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(themeManager.palette.screenBackground)
        .navigationTitle(appText("accessibility_title", languageCode: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveAccessibility() async {
        guard let token = auth.currentToken, !token.isEmpty else {
            auth.handleInvalidSession()
            return
        }

        do {
            vm.isSaving = true
            vm.saveError = nil

            let updatedUser = try await SettingsService.shared.updateAccessibility(
                SettingsService.AccessibilitySettingsUpdateRequest(
                    a11yUiFont: vm.a11yUiFont,
                    a11yVisualAlerts: vm.a11yVisualAlerts,
                    a11yVibrate: vm.a11yVibrate,
                    a11yFlashOnCall: vm.a11yFlashOnCall,
                    a11yLiveCaptions: vm.a11yLiveCaptions,
                    a11yVoiceNoteSTT: vm.a11yVoiceNoteSTT,
                    a11yCaptionFont: vm.a11yCaptionFont,
                    a11yCaptionBg: vm.a11yCaptionBg
                ),
                token: token
            )

            auth.replaceCurrentUser(updatedUser)
            vm.load(from: updatedUser)
            vm.isSaving = false
        } catch {
            vm.isSaving = false
            vm.saveError = error.localizedDescription
        }
    }
    
}

