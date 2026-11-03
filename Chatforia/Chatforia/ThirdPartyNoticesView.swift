import SwiftUI

/// Reads the notices shipped with this app; no connection is required.
struct ThirdPartyNoticesView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var notices: String?
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let notices {
                        Text(verbatim: notices)
                            .font(.footnote)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if loadFailed {
                        Text("Bundled notices could not be loaded.")
                        Link("View website notices", destination: URL(string: "https://chatforia.com/legal/open-source")!)
                    } else {
                        ProgressView()
                    }
                }
                .padding()
                .foregroundStyle(themeManager.palette.primaryText)
            }
            .background(themeManager.palette.screenBackground.ignoresSafeArea())
            .toolbarBackground(themeManager.palette.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("Open Source Licenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Open Source Licenses")
                        .font(.headline)
                        .foregroundStyle(themeManager.palette.titleAccent)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard notices == nil else { return }
                guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    loadFailed = true
                    return
                }
                notices = text
            }
        }
        .tint(themeManager.palette.accent)
    }
}
