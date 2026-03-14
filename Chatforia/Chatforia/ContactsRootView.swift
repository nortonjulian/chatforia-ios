import SwiftUI

struct ContactsRootView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "No contacts yet",
                    subtitle: "Saved contacts will appear here once you add them.",
                    buttonTitle: "Start a chat",
                    buttonAction: {
                        // wire later
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Contacts")
            .searchable(text: $searchText, prompt: "Search contacts")
        }
    }
}
