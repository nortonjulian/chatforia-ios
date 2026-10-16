import SwiftUI

struct VoicemailInboxView: View {
    @Binding var isEditingVoicemails: Bool

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var callManager: CallManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @StateObject private var viewModel = VoicemailInboxViewModel()

    @State private var selectedVoicemailIds: Set<String> = []
    @State private var showDeleteSelectedConfirmation = false
    @State private var showClearAllConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.isLoading && viewModel.voicemails.isEmpty {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage, viewModel.voicemails.isEmpty {
                    errorView(errorMessage)
                } else if viewModel.voicemails.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }

            if isEditingVoicemails &&
                !viewModel.voicemails.isEmpty {

                Divider()

                HStack(spacing: 18) {
                    Button(
                        selectedVoicemailIds.count ==
                            viewModel.voicemails.count
                        ? "Deselect All"
                        : "Select All"
                    ) {
                        if selectedVoicemailIds.count ==
                            viewModel.voicemails.count {
                            selectedVoicemailIds.removeAll()
                        } else {
                            selectedVoicemailIds =
                                Set(viewModel.voicemails.map(\.id))
                        }
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showDeleteSelectedConfirmation = true
                    } label: {
                        Text(
                            selectedVoicemailIds.isEmpty
                            ? "Delete"
                            : "Delete (\(selectedVoicemailIds.count))"
                        )
                    }
                    .disabled(selectedVoicemailIds.isEmpty)

                    Button(role: .destructive) {
                        showClearAllConfirmation = true
                    } label: {
                        Text("Clear All")
                    }
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(themeManager.palette.cardBackground)
            }
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .toolbar {
            if !viewModel.voicemails.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        isEditingVoicemails ? "Done" : "Edit"
                    ) {
                        isEditingVoicemails.toggle()

                        if !isEditingVoicemails {
                            selectedVoicemailIds.removeAll()
                        }
                    }
                }
            }

        }
        .confirmationDialog(
            "Delete selected voicemails?",
            isPresented: $showDeleteSelectedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let token = auth.currentToken, !token.isEmpty else { return }

                let ids = selectedVoicemailIds
                selectedVoicemailIds.removeAll()

                Task {
                    await viewModel.deleteSelected(
                        ids: ids,
                        token: token
                    )

                    if viewModel.voicemails.isEmpty {
                        isEditingVoicemails = false
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "These voicemails will be removed from your voicemail inbox."
            )
        }
        .confirmationDialog(
            "Clear all voicemails?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                guard let token = auth.currentToken, !token.isEmpty else { return }

                selectedVoicemailIds.removeAll()
                isEditingVoicemails = false

                Task {
                    await viewModel.clearAll(
                        token: token
                    )
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will remove all voicemails from your voicemail inbox."
            )
        }
        .task {
            guard let token = auth.currentToken, !token.isEmpty else {
                viewModel.errorMessage =
                appText("auth.youNeedToBeSignedIn", languageCode: appLanguage)
                return
            }
            await viewModel.load(token: token)
        }
        .refreshable {
            guard let token = auth.currentToken, !token.isEmpty else { return }
            await viewModel.refresh(token: token)
        }
        .onChange(of: viewModel.voicemails.map(\.id)) { _, ids in
            selectedVoicemailIds =
                selectedVoicemailIds.intersection(Set(ids))

            if ids.isEmpty {
                isEditingVoicemails = false
            }
        }
        .sheet(
            item: Binding(
                get: { viewModel.selectedVoicemail },
                set: { viewModel.selectedVoicemail = $0 }
            )
        ) { voicemail in
            NavigationStack {
                VoicemailDetailView(
                    voicemail: voicemail,
                    onMarkReadIfNeeded: {
                        guard let token = auth.currentToken, !token.isEmpty else { return }
                        Task {
                            await viewModel.markReadIfNeeded(voicemail, token: token)
                        }
                    },
                    onCallBack: {
                        if let callerUserId = voicemail.callerUserId {
                            callManager.startCall(
                                to: .appUser(
                                    userId: callerUserId,
                                    username: voicemail.resolvedCallerName
                                        ?? voicemail.username
                                ),
                                auth: auth
                            )
                            return
                        }

                        guard let number = voicemail.callbackNumber else {
                            return
                        }

                        callManager.startCall(
                            to: .phoneNumber(
                                number,
                                displayName: voicemail.resolvedCallerName
                            ),
                            auth: auth
                        )
                    }
                )
            }
        }
        .alert(
            appText("voicemail.errorTitle", languageCode: appLanguage),
            isPresented: errorBinding
        ) {
            Button(appText("common.ok", languageCode: appLanguage), role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(
                viewModel.errorMessage
                ?? appText("common.somethingWentWrong", languageCode: appLanguage)
            )
        }
    }

    private var listView: some View {
        List {
            ForEach(viewModel.voicemails) { voicemail in
                HStack(spacing: 10) {
                    if isEditingVoicemails {
                        Button {
                            if selectedVoicemailIds.contains(voicemail.id) {
                                selectedVoicemailIds.remove(voicemail.id)
                            } else {
                                selectedVoicemailIds.insert(voicemail.id)
                            }
                        } label: {
                            Image(
                                systemName:
                                    selectedVoicemailIds.contains(voicemail.id)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .font(.title3)
                            .foregroundStyle(themeManager.palette.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    VoicemailRowView(
                        voicemail: voicemail,
                        onTap: {
                            if isEditingVoicemails {
                                if selectedVoicemailIds.contains(voicemail.id) {
                                    selectedVoicemailIds.remove(voicemail.id)
                                } else {
                                    selectedVoicemailIds.insert(voicemail.id)
                                }
                            } else {
                                viewModel.select(voicemail)
                            }
                        },
                        onToggleRead: {
                            guard !isEditingVoicemails else { return }
                            guard let token = auth.currentToken, !token.isEmpty else { return }

                            Task {
                                await viewModel.markRead(
                                    voicemail,
                                    isRead: !voicemail.isRead,
                                    token: token
                                )
                            }
                        },
                        onDelete: {
                            guard !isEditingVoicemails else { return }
                            guard let token = auth.currentToken, !token.isEmpty else { return }

                            Task {
                                await viewModel.delete(
                                    voicemail,
                                    token: token
                                )
                            }
                        }
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(appText("voicemail.loading", languageCode: appLanguage))
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(themeManager.palette.accent)

            Text(appText("voicemail.couldNotLoad", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(
                appText("common.tryAgain", languageCode: appLanguage)
            ) {
                guard let token = auth.currentToken, !token.isEmpty else { return }
                Task {
                    await viewModel.load(token: token)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundStyle(themeManager.palette.accent)

            Text(appText("voicemail.empty", languageCode: appLanguage))
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text(appText("voicemail.emptySubtitle", languageCode: appLanguage))
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !viewModel.voicemails.isEmpty },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}
