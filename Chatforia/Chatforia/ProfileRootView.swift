import SwiftUI

struct ProfileRootView: View {
    let user: UserDTO
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ProfileHeaderView(
                        username: user.username,
                        email: user.email,
                        plan: user.plan
                    )

                    SectionCardView(title: "Account") {
                        SettingsRowView(
                            systemImage: "person.crop.circle",
                            title: "Username",
                            value: user.username
                        )

                        Divider()

                        SettingsRowView(
                            systemImage: "envelope",
                            title: "Email",
                            value: user.email
                        )

                        if let role = user.role, !role.isEmpty {
                            Divider()
                            SettingsRowView(
                                systemImage: "briefcase",
                                title: "Role",
                                value: role
                            )
                        }

                        if let plan = user.plan, !plan.isEmpty {
                            Divider()
                            SettingsRowView(
                                systemImage: "star",
                                title: "Plan",
                                value: plan
                            )
                        }
                    }

                    SectionCardView(title: "Preferences") {
                        SettingsRowView(
                            systemImage: "globe",
                            title: "Language",
                            value: displayValue(user.preferredLanguage)
                        )

                        Divider()

                        SettingsRowView(
                            systemImage: "paintbrush",
                            title: "Theme",
                            value: displayValue(user.theme)
                        )
                    }

                    SectionCardView(title: "Messaging") {
                        SettingsRowView(
                            systemImage: "checkmark.message",
                            title: "Read Receipts",
                            value: "Coming soon"
                        )

                        Divider()

                        SettingsRowView(
                            systemImage: "timer",
                            title: "Disappearing Messages",
                            value: "Coming soon"
                        )

                        Divider()

                        SettingsRowView(
                            systemImage: "translate",
                            title: "Translation",
                            value: displayValue(user.preferredLanguage)
                        )
                    }

                    Button(role: .destructive) {
                        auth.logout()
                    } label: {
                        Text("Log out")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Profile")
        }
    }

    private func displayValue(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "—"
        }
        return value
    }
}
