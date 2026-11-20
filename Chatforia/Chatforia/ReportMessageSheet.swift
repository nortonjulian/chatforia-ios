import SwiftUI

func localizedReportSender(_ template: String, name: String) -> String {
    for token in ["{name}", "%@", "@@"] where template.contains(token) {
        return template.replacingOccurrences(of: token, with: name)
    }
    // Older catalog entries for Japanese omit the placeholder entirely.
    return "\(name) \(template)"
}

struct ReportMessagePreview {
    let displayText: String
    let evidenceText: String?

    static func resolve(
        message: MessageDTO,
        store: DecryptedMessageTextStore,
        accountId: Int,
        languageCode: String
    ) -> Self {
        guard accountId > 0, store.activeAccountId == accountId else {
            return Self(
                displayText: appText("report.noVisibleText", languageCode: languageCode),
                evidenceText: nil
            )
        }
        return resolve(
            message: message,
            decryptedText: store.text(for: message.id),
            languageCode: languageCode
        )
    }

    static func resolve(
        message: MessageDTO,
        decryptedText: String?,
        languageCode: String
    ) -> Self {
        func visibleText(_ candidate: String?) -> String? {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            let placeholder = trimmed.lowercased()
            guard !["[image]", "[video]", "[audio]", "[file]", "[attachment]", "[gif]", "attachment"].contains(placeholder) else {
                return nil
            }
            return trimmed
        }

        let permittedAttachments = (message.attachments ?? []).filter {
            message.mediaRestricted != true || !$0.isVisualForTeenSafety
        }
        let caption = permittedAttachments.lazy.compactMap { visibleText($0.caption) }.first
        if let text = visibleText(decryptedText)
            ?? visibleText(message.rawContent)
            ?? visibleText(message.translatedForMe)
            ?? caption {
            return Self(displayText: text, evidenceText: text)
        }

        if let attachment = permittedAttachments.first {
            let kind = (attachment.kind ?? "").uppercased()
            let mime = (attachment.mimeType ?? "").lowercased()
            let key: String
            if kind == "AUDIO" || mime.hasPrefix("audio/") {
                key = "messages.mediaAudio"
            } else if kind == "VIDEO" || mime.hasPrefix("video/") {
                key = "messages.mediaVideo"
            } else if kind == "IMAGE" || kind == "GIF" || mime.hasPrefix("image/") {
                key = "messages.mediaPhoto"
            } else {
                key = "messages.mediaFile"
            }
            return Self(displayText: appText(key, languageCode: languageCode), evidenceText: nil)
        }

        if message.mediaRestricted == true {
            return Self(
                displayText: appText("messages.teenMediaRestricted", languageCode: languageCode),
                evidenceText: nil
            )
        }
        if message.audioUrl != nil {
            return Self(displayText: appText("messages.mediaAudio", languageCode: languageCode), evidenceText: nil)
        }
        if message.imageUrl != nil {
            return Self(displayText: appText("messages.mediaPhoto", languageCode: languageCode), evidenceText: nil)
        }
        if message.encryptedPayloadForMe != nil || message.contentCiphertext != nil {
            return Self(displayText: appText("messages.encryptedMessage", languageCode: languageCode), evidenceText: nil)
        }
        return Self(displayText: appText("report.noVisibleText", languageCode: languageCode), evidenceText: nil)
    }
}

struct ReportMessageSheet: View {
    let targetMessage: MessageDTO
    let accountId: Int
    let senderName: String
    let isSubmitting: Bool
    let errorText: String?

    @Binding var reason: ReportReason
    @Binding var contextCount: Int
    @Binding var details: String
    @Binding var blockAfterReport: Bool

    let onCancel: () -> Void
    let onSubmit: (String?) -> Void

    @AppStorage("chatforia_language") private var appLanguage = "en"
    @StateObject private var decryptedStore = DecryptedMessageTextStore.shared

    private var preview: ReportMessagePreview {
        ReportMessagePreview.resolve(
            message: targetMessage,
            store: decryptedStore,
            accountId: accountId,
            languageCode: appLanguage
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(appText("report.reason", languageCode: appLanguage)) {
                    Picker(
                        appText("report.reason", languageCode: appLanguage),
                        selection: $reason
                    ) {
                        ForEach(ReportReason.allCases) { value in
                            Text(value.title(languageCode: appLanguage))
                                .tag(value)
                        }
                    }
                }

                Section(appText("report.includePreviousMessages", languageCode: appLanguage)) {
                    Picker(
                        appText("messages.context", languageCode: appLanguage),
                        selection: $contextCount
                    ) {
                        Text(appText("report.onlyThisMessage", languageCode: appLanguage))
                            .tag(0)

                        Text(appText("report.thisPlusPrevious5", languageCode: appLanguage))
                            .tag(5)

                        Text(appText("report.thisPlusPrevious10", languageCode: appLanguage))
                            .tag(10)

                        Text(appText("report.thisPlusPrevious20", languageCode: appLanguage))
                            .tag(20)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(appText("common.additionalDetails", languageCode: appLanguage)) {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                }

                Section {
                    Toggle(
                        appText("report.blockUserAfterReporting", languageCode: appLanguage),
                        isOn: $blockAfterReport
                    )
                }

                Section(appText("report.preview", languageCode: appLanguage)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            localizedReportSender(
                                appText("report.reportingMessageFrom", languageCode: appLanguage),
                                name: senderName
                            )
                        )
                        .font(.subheadline)

                        Text(
                            preview.displayText
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                    }
                }

                if let errorText, !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(appText("report.title", languageCode: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(
                        appText("button_cancel", languageCode: appLanguage),
                        role: .cancel
                    ) {
                        if !isSubmitting {
                            onCancel()
                        }
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(appText("common.submit", languageCode: appLanguage)) {
                        if decryptedStore.activeAccountId == accountId {
                            onSubmit(preview.evidenceText)
                        }
                    }
                    .disabled(isSubmitting || decryptedStore.activeAccountId != accountId)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                }
            }
        }
    }
}
