import SwiftUI

struct ReportMessageSheet: View {
    let targetMessage: MessageDTO
    let senderName: String
    let previewText: String
    let isSubmitting: Bool
    let errorText: String?

    @Binding var reason: ReportReason
    @Binding var contextCount: Int
    @Binding var details: String
    @Binding var blockAfterReport: Bool

    let onCancel: () -> Void
    let onSubmit: () -> Void

    @AppStorage("chatforia_language") private var appLanguage = "en"

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
                            String(
                                format: appText(
                                    "report.reportingMessageFrom",
                                    languageCode: appLanguage
                                ),
                                senderName
                            )
                        )
                        .font(.subheadline)

                        Text(
                            previewText.isEmpty
                                ? appText("report.noVisibleText", languageCode: appLanguage)
                                : previewText
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
                        onSubmit()
                    }
                    .disabled(isSubmitting)
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
