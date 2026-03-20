import SwiftUI

struct ContactsRootView: View {
    @State private var searchText = ""
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        NavigationStack {
            Group {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "No contacts yet",
                    subtitle: "Saved contacts will appear here once you add them.",
                    buttonTitle: "Start a chat",
                    buttonAction: {
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(themeManager.palette.screenBackground)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search contacts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ThemedNavigationTitle(title: "Contacts")
                        .environmentObject(themeManager)
                }
            }
        }
    }
}
