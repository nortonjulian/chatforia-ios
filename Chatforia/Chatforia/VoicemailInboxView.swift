import SwiftUI

struct VoicemailInboxView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var callManager: CallManager
    @StateObject private var viewModel = VoicemailInboxViewModel()

    var body: some View {
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
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .task {
            guard let token = auth.currentToken, !token.isEmpty else {
                viewModel.errorMessage = "You need to be signed in."
                return
            }
            await viewModel.load(token: token)
        }
        .refreshable {
            guard let token = auth.currentToken, !token.isEmpty else { return }
            await viewModel.refresh(token: token)
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
                        guard let number = voicemail.callbackNumber else { return }
                        callManager.startCall(
                            to: .phoneNumber(number, displayName: nil),
                            auth: auth
                        )
                    }
                )
            }
        }
        .alert("Voicemail Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
    }

    private var listView: some View {
        List {
            ForEach(viewModel.voicemails) { voicemail in
                VoicemailRowView(
                    voicemail: voicemail,
                    onTap: {
                        viewModel.select(voicemail)
                    },
                    onToggleRead: {
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
                        guard let token = auth.currentToken, !token.isEmpty else { return }
                        Task {
                            await viewModel.delete(
                                voicemail,
                                token: token
                            )
                        }
                    }
                )
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
            Text("Loading voicemail…")
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

            Text("Couldn’t load voicemail")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
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

            Text("No voicemail yet")
                .font(.headline)
                .foregroundStyle(themeManager.palette.primaryText)

            Text("When someone leaves you a voicemail, it will show up here.")
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
