import SwiftUI

struct VoicemailDetailView: View {
    let voicemail: VoicemailDTO
    let onMarkReadIfNeeded: (() -> Void)?
    let onCallBack: (() -> Void)?

    @EnvironmentObject private var themeManager: ThemeManager
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
                    urlString: voicemail.audioUrl,
                    title: String(localized: "voicemail.title"),
                    durationSec: Double(voicemail.durationSec ?? 0),
                    isMe: false,
                    maxWidth: .infinity,
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
            String(localized: "voicemail.title")
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            markReadIfNeeded()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {

            infoRow(
                label: String(localized: "voicemail.from"),
                value: displayFrom
            )

            infoRow(
                label: String(localized: "voicemail.to"),
                value: displayTo
            )

            infoRow(
                label: String(localized: "voicemail.received"),
                value: receivedText
            )

            if let durationSec = voicemail.durationSec {

                infoRow(
                    label: String(localized: "voicemail.duration"),
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
                    "calls.callBack",
                    systemImage: "phone.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(themeManager.palette.accent)
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text(
                String(localized: "voicemail.transcript")
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
                        String(
                            localized:
                                "voicemail.noTranscript"
                        )
                    )
                }

            case .pending:

                placeholderCard(
                    String(
                        localized:
                            "voicemail.transcriptPending"
                    )
                )

            case .failed:

                placeholderCard(
                    String(
                        localized:
                            "voicemail.transcriptUnavailable"
                    )
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

        let value = voicemail.fromNumber
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return value.isEmpty
            ? String(
                localized:
                    "voicemail.unknownCaller"
            )
            : value
    }

    private var displayTo: String {

        let value = voicemail.toNumber
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return value.isEmpty
            ? String(
                localized:
                    "voicemail.yourNumber"
            )
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
