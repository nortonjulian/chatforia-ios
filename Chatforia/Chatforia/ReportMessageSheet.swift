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

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "report.reason")) {
                    Picker(
                        String(localized: "report.reason"),
                        selection: $reason
                    ) {
                        ForEach(ReportReason.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }

                Section(String(localized: "report.includePreviousMessages")) {
                    Picker(
                        String(localized: "messages.context"),
                        selection: $contextCount
                    ) {
                        Text(String(localized: "report.onlyThisMessage"))
                            .tag(0)

                        Text(String(localized: "report.thisPlusPrevious5"))
                            .tag(5)

                        Text(String(localized: "report.thisPlusPrevious10"))
                            .tag(10)

                        Text(String(localized: "report.thisPlusPrevious20"))
                            .tag(20)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(String(localized: "common.additionalDetails")) {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                }

                Section {
                    Toggle(
                        String(localized: "report.blockUserAfterReporting"),
                        isOn: $blockAfterReport
                    )
                }

                Section(String(localized: "report.preview")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            String(
                                format: String(localized: "report.reportingMessageFrom"),
                                senderName
                            )
                        )
                        .font(.subheadline)

                        Text(
                            previewText.isEmpty
                                ? String(localized: "report.noVisibleText")
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
            .navigationTitle(String(localized: "report.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(
                        String(localized: "button_cancel"),
                        role: .cancel
                    ) {
                        if !isSubmitting {
                            onCancel()
                        }
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.submit")) {
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