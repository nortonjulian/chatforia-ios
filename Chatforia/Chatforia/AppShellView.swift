import SwiftUI

struct AppShellView: View {
    let user: UserDTO
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        TabView {
            ChatsRootView()
                .tabItem {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                }

            ContactsRootView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2.fill")
                }

            ProfileRootView(user: user)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
    }
}
