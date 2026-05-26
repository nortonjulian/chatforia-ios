import SwiftUI

struct ImportPhoneContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"

    @StateObject private var vm = ImportPhoneContactsViewModel()

    let onImportFinished: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.screenBackground
                    .ignoresSafeArea()

                Group {
                    if vm.isLoading {
                        LoadingStateView(
                            title:
                                appText(
                                    "contacts.loadingPhoneContacts",
                                    languageCode: appLanguage
                                ),
                            subtitle:
                                appText(
                                    "contacts.readingContactsFromIPhone",
                                    languageCode: appLanguage
                                )
                        )
                    } else if let errorText = vm.errorText, !errorText.isEmpty, vm.contacts.isEmpty {
                        EmptyStateView(
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            title: appText(
                                "ios.couldn_t_load_contacts",
                                languageCode: appLanguage
                            ),
                            subtitle: errorText,
                            buttonTitle: appText(
                                "common.tryAgain",
                                languageCode: appLanguage
                            ),
                            buttonAction: {
                                Task { await vm.loadContacts() }
                            }
                        )
                    } else if vm.contacts.isEmpty {
                        EmptyStateView(
                            systemImage: "person.crop.circle.badge.plus",
                            title:
                                appText(
                                    "contacts.noPhoneContactsFound",
                                    languageCode: appLanguage
                                ),

                        subtitle:
                                appText(
                                    "contacts.noImportableContacts",
                                    languageCode: appLanguage
                                )
                        )
                    } else {
                        List {
                            Section {
                                HStack {
                                    Button(
                                        appText(
                                            "common.selectAll",
                                            languageCode: appLanguage
                                        )
                                ) {
                                        vm.selectAll()
                                    }
                                    .foregroundStyle(themeManager.palette.accent)

                                    Spacer()

                                    Button(appText(
                                        "common.clear",
                                        languageCode: appLanguage
                                    )) {
                                        vm.clearSelection()
                                    }
                                    .foregroundStyle(themeManager.palette.accent)
                                }
                            }
                            .listRowBackground(themeManager.palette.cardBackground)

                            ForEach(vm.contacts) { contact in
                                Button {
                                    vm.toggle(contact)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: vm.selectedIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(vm.selectedIDs.contains(contact.id) ? themeManager.palette.accent : themeManager.palette.secondaryText)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(contact.displayName)
                                                .foregroundStyle(themeManager.palette.primaryText)

                                            Text(contact.phoneNumber)
                                                .font(.footnote)
                                                .foregroundStyle(themeManager.palette.secondaryText)
                                        }

                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(themeManager.palette.cardBackground)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle(
                appText(
                    "contacts.importContacts",
                    languageCode: appLanguage
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(
                        appText(
                            "common.close",
                            languageCode: appLanguage
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        vm.isImporting
                            ? appText(
                                "common.importing",
                                languageCode: appLanguage
                              )
                            : appText(
                                "common.import",
                                languageCode: appLanguage
                              )
                    ) {
                        Task { await importSelected() }
                    }
                    .disabled(vm.isImporting || vm.selectedIDs.isEmpty)
                    .foregroundStyle(themeManager.palette.accent)
                }
            }
            .task {
                await vm.loadContacts()
            }
        }
    }

    private func importSelected() async {
        do {
            let importedCount = try await vm.importSelected(token: auth.currentToken)
            if importedCount > 0 {
                onImportFinished()
                dismiss()
            }
        } catch {
            vm.errorText = error.localizedDescription
        }
    }
}
