import SwiftUI

struct ImportPhoneContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager

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
                            title: "Loading phone contacts…",
                            subtitle: "Reading contacts from your iPhone."
                        )
                    } else if let errorText = vm.errorText, !errorText.isEmpty, vm.contacts.isEmpty {
                        EmptyStateView(
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            title: "Couldn’t load contacts",
                            subtitle: errorText,
                            buttonTitle: "Try Again",
                            buttonAction: {
                                Task { await vm.loadContacts() }
                            }
                        )
                    } else if vm.contacts.isEmpty {
                        EmptyStateView(
                            systemImage: "person.crop.circle.badge.plus",
                            title: "No phone contacts found",
                            subtitle: "There are no importable contacts available."
                        )
                    } else {
                        List {
                            Section {
                                HStack {
                                    Button("Select All") {
                                        vm.selectAll()
                                    }
                                    .foregroundStyle(themeManager.palette.accent)

                                    Spacer()

                                    Button("Clear") {
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
            .navigationTitle("Import Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.palette.accent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(vm.isImporting ? "Importing..." : "Import") {
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
