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
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }

                Section("Include previous messages") {
                    Picker("Context", selection: $contextCount) {
                        Text("Only this message").tag(0)
                        Text("This + previous 5").tag(5)
                        Text("This + previous 10").tag(10)
                        Text("This + previous 20").tag(20)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Additional details") {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                }

                Section {
                    Toggle("Block this user after reporting", isOn: $blockAfterReport)
                }

                Section("Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reporting message from **\(senderName)**")
                            .font(.subheadline)

                        Text(previewText.isEmpty ? "[No visible text]" : previewText)
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
            .navigationTitle("Report Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        if !isSubmitting {
                            onCancel()
                        }
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
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
