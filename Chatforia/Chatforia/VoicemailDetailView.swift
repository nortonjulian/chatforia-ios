import SwiftUI

struct VoicemailDetailView: View {
    let voicemail: VoicemailDTO
    let onMarkReadIfNeeded: (() -> Void)?
    let onCallBack: (() -> Void)?

    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @State private var didAutoMarkRead = false

    init(
        voicemail: VoicemailDTO,
        onMarkReadIfNeeded: (() -> Void)? = nil,
        onCallBack: (() -> Void)? = nil
    ) {
        self.voicemail = voicemail
        self.onMarkReadIfNeeded = onMarkReadIfNeeded
        self.onCallBack = onCallBack
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                headerCard

                actionButtons

                AudioAttachmentCardView(
                    urlString: voicemail.secureAudioURLString,
                    title: appText("voicemail.title", languageCode: appLanguage),
                    durationSec: Double(voicemail.durationSec ?? 0),
                    isMe: false,
                    maxWidth: .infinity,
                    authToken: TokenStore.shared.read(),
                    onPlaybackStarted: {
                        markReadIfNeeded()
                    }
                )

                transcriptSection
            }
            .padding(16)
        }
        .background(
            themeManager.palette.screenBackground
                .ignoresSafeArea()
        )
        .navigationTitle(
            appText("voicemail.title", languageCode: appLanguage)
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            markReadIfNeeded()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {

            infoRow(
                label: appText("voicemail.from", languageCode: appLanguage) + ":",
                value: displayFrom
            )

            if voicemail.callerUserId == nil {
                infoRow(
                    label: appText("voicemail.to", languageCode: appLanguage) + ":",
                    value: displayTo
                )
            }

            infoRow(
                label: appText("voicemail.received", languageCode: appLanguage),
                value: receivedText
            )

            if let durationSec = voicemail.durationSec {

                infoRow(
                    label: appText("voicemail.duration", languageCode: appLanguage),
                    value: AudioAttachmentCardView.formatTime(
                        Double(durationSec)
                    )
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                themeManager.palette.border,
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var actionButtons: some View {

        if let onCallBack {

            Button(action: onCallBack) {

                Label(
                    appText("calls.callBack", languageCode: appLanguage),
                    systemImage: "phone.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(themeManager.palette.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text(
                appText("voicemail.transcript", languageCode: appLanguage)
            )
            .font(.headline)
            .foregroundStyle(
                themeManager.palette.primaryText
            )

            switch voicemail.transcriptStatus {

            case .complete:

                if let transcript =
                    voicemail.transcript?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                   !transcript.isEmpty {

                    Text(transcript)
                        .font(.body)
                        .foregroundStyle(
                            themeManager.palette.primaryText
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(14)
                        .background(
                            themeManager.palette.cardBackground
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                            .stroke(
                                themeManager.palette.border,
                                lineWidth: 1
                            )
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )

                } else {

                    placeholderCard(
                        appText("voicemail.noTranscript", languageCode: appLanguage)
                    )
                }

            case .pending:

                placeholderCard(
                    appText("voicemail.transcriptPending", languageCode: appLanguage)
                )

            case .failed:

                placeholderCard(
                    appText("voicemail.transcriptUnavailable", languageCode: appLanguage)
                )
            }
        }
    }

    private func markReadIfNeeded() {
        guard !voicemail.isRead,
              !didAutoMarkRead else {
            return
        }

        didAutoMarkRead = true
        onMarkReadIfNeeded?()
    }

    private func infoRow(
        label: String,
        value: String
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 2
        ) {

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    themeManager.palette.secondaryText
                )

            Text(value)
                .font(.subheadline)
                .foregroundStyle(
                    themeManager.palette.primaryText
                )
        }
    }

    private func placeholderCard(
        _ text: String
    ) -> some View {

        Text(text)
            .font(.body)
            .foregroundStyle(
                themeManager.palette.secondaryText
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(14)
            .background(
                themeManager.palette.cardBackground
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    themeManager.palette.border,
                    lineWidth: 1
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
    }

    private var displayFrom: String {

        if let resolvedCallerName = voicemail.resolvedCallerName {
            return resolvedCallerName
        }

        let value = voicemail.fromNumber
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return value.isEmpty
            ? appText("voicemail.unknownCaller", languageCode: appLanguage)
            : value
    }

    private var displayTo: String {

        let value = voicemail.toNumber
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return value.isEmpty
            ? appText("voicemail.yourNumber", languageCode: appLanguage)
            : value
    }

    private var receivedText: String {

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(
            from: voicemail.createdAt
        )
    }
}
