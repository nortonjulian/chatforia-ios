import SwiftUI

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @StateObject private var vm: AddContactViewModel

    let onSaved: (ContactDTO) -> Void

    init(
        initialMode: AddContactMode = .username,
        initialUsername: String = "",
        initialPhoneNumber: String = "",
        initialExternalName: String = "",
        initialAlias: String = "",
        initialFavorite: Bool = false,
        onSaved: @escaping (ContactDTO) -> Void
    ) {
        _vm = StateObject(
            wrappedValue: AddContactViewModel(
                mode: initialMode,
                username: initialUsername,
                phoneNumber: initialPhoneNumber,
                externalName: initialExternalName,
                alias: initialAlias,
                favorite: initialFavorite
            )
        )
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {

                        Picker(
                            appText(
                                "contacts.mode",
                                languageCode: appLanguage
                            ),
                            selection: $vm.mode
                        ) {
                            ForEach(AddContactMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: vm.mode) { _, _ in
                            vm.errorText = nil
                            vm.successText = nil
                        }

                        VStack(spacing: 14) {

                            if vm.mode == .username {

                                ThemedTextField(
                                    title: appText(
                                        "auth.username",
                                        languageCode: appLanguage
                                    ),
                                    text: $vm.username,
                                    contentType: .username
                                )

                            } else {

                                ThemedTextField(
                                    title: appText(
                                        "contacts.phoneNumber",
                                        languageCode: appLanguage
                                    ),
                                    text: $vm.phoneNumber,
                                    keyboard: .phonePad,
                                    contentType: .telephoneNumber
                                )

                                ThemedTextField(
                                    title: appText(
                                        "common.name",
                                        languageCode: appLanguage
                                    ),
                                    text: $vm.externalName
                                )
                            }

                            ThemedTextField(
                                title: appText(
                                    "contacts.aliasOptional",
                                    languageCode: appLanguage
                                ),
                                text: $vm.alias
                            )

                            ThemedToggleRow(
                                title: appText(
                                    "contacts.favorite",
                                    languageCode: appLanguage
                                ),
                                subtitle: appText(
                                    "contacts.favoriteSubtitle",
                                    languageCode: appLanguage
                                ),
                                isOn: $vm.favorite
                            )

                            if vm.mode == .username {

                                Text(
                                    appText(
                                        "contacts.usernameModeHelp",
                                        languageCode: appLanguage
                                    )
                                )
                                .font(.footnote)
                                .foregroundStyle(
                                    themeManager.palette.secondaryText
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )

                            } else {

                                Text(
                                    appText(
                                        "contacts.phoneModeHelp",
                                        languageCode: appLanguage
                                    )
                                )
                                .font(.footnote)
                                .foregroundStyle(
                                    themeManager.palette.secondaryText
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                            }

                            if let errorText = vm.errorText,
                               !errorText.isEmpty {

                                Text(errorText)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                            }

                            if let successText = vm.successText,
                               !successText.isEmpty {

                                Text(successText)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                            }
                        }
                        .padding(18)
                        .background(themeManager.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 20,
                                style: .continuous
                            )
                            .stroke(
                                themeManager.palette.border,
                                lineWidth: 1
                            )
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 20,
                                style: .continuous
                            )
                        )

                        ThemedGradientButton(
                            title:
                                vm.isSaving
                                ? appText(
                                    "common.saving",
                                    languageCode: appLanguage
                                )
                                : appText(
                                    "contacts.saveContact",
                                    languageCode: appLanguage
                                ),

                            action: {
                                Task { await save() }
                            },

                            isFullWidth: true,
                            isDisabled:
                                vm.isSaving || !vm.canSave
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle(
                appText(
                    "contacts.addContact",
                    languageCode: appLanguage
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(
                        appText(
                            "button_cancel",
                            languageCode: appLanguage
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
        }
    }

    private func save() async {
        do {
            let contact = try await vm.save(token: auth.currentToken)
            onSaved(contact)
            dismiss()
        } catch {
            vm.errorText = error.localizedDescription
        }
    }
}
