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
                themeManager.palette.screenBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        Picker(appText("contacts.mode", languageCode: appLanguage), selection: $vm.mode) {
                            ForEach(AddContactMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: vm.mode) { _, _ in
                            vm.errorText = nil
                            vm.successText = nil
                            vm.searchResults = []
                            vm.selectedUser = nil
                        }

                        VStack(spacing: 14) {
                            if vm.mode == .username {
                                if let selected = vm.selectedUser {
                                    selectedUserCard(selected)
                                } else {
                                    ThemedTextField(
                                        title: "Name or username",
                                        text: $vm.username,
                                        contentType: .username
                                    )
                                    .onChange(of: vm.username) { _, _ in
                                        vm.usernameChanged(token: auth.currentToken)
                                    }

                                    if !vm.username.isEmpty && vm.username.count < 3 {
                                        Text("Enter at least 3 characters to search people.")
                                            .font(.footnote)
                                            .foregroundStyle(themeManager.palette.secondaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    if vm.isSearching {
                                        ProgressView()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    ForEach(vm.searchResults) { person in
                                        Button {
                                            vm.selectUser(person)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Circle()
                                                    .fill(themeManager.palette.border)
                                                    .frame(width: 42, height: 42)
                                                    .overlay(
                                                        Text(String(person.resolvedDisplayName.prefix(1)).uppercased())
                                                            .fontWeight(.semibold)
                                                            .foregroundStyle(themeManager.palette.primaryText)
                                                    )

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(person.resolvedDisplayName)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(themeManager.palette.primaryText)
                                                    if let username = person.username {
                                                        Text("@\(username)")
                                                            .font(.footnote)
                                                            .foregroundStyle(themeManager.palette.secondaryText)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(12)
                                            .background(themeManager.palette.screenBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            } else {
                                ThemedTextField(
                                    title: appText("contacts.phoneNumber", languageCode: appLanguage),
                                    text: $vm.phoneNumber,
                                    keyboard: .phonePad,
                                    contentType: .telephoneNumber
                                )

                                ThemedTextField(
                                    title: appText("common.name", languageCode: appLanguage),
                                    text: $vm.externalName
                                )
                            }

                            ThemedTextField(
                                title: appText("contacts.aliasOptional", languageCode: appLanguage),
                                text: $vm.alias
                            )

                            ThemedToggleRow(
                                title: appText("contacts.favorite", languageCode: appLanguage),
                                subtitle: appText("contacts.favoriteSubtitle", languageCode: appLanguage),
                                isOn: $vm.favorite
                            )

                            if let errorText = vm.errorText, !errorText.isEmpty {
                                Text(errorText)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(18)
                        .background(themeManager.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(themeManager.palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        ThemedGradientButton(
                            title: vm.isSaving
                                ? appText("common.saving", languageCode: appLanguage)
                                : appText("contacts.saveContact", languageCode: appLanguage),
                            action: { Task { await save() } },
                            isFullWidth: true,
                            isDisabled: vm.isSaving || !vm.canSave
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle(appText("contacts.addContact", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(appText("button_cancel", languageCode: appLanguage)) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func selectedUserCard(_ person: PeopleSearchItemDTO) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(themeManager.palette.border)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(person.resolvedDisplayName.prefix(1)).uppercased())
                        .fontWeight(.bold)
                        .foregroundStyle(themeManager.palette.primaryText)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(person.resolvedDisplayName)
                    .fontWeight(.bold)
                    .foregroundStyle(themeManager.palette.primaryText)
                if let username = person.username {
                    Text("@\(username)")
                        .font(.footnote)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
            }
            Spacer()
            Button("Change") {
                vm.clearSelectedUser()
            }
            .foregroundStyle(themeManager.palette.accent)
        }
        .padding(12)
        .background(themeManager.palette.screenBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
