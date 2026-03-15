import SwiftUI
import PhotosUI

struct ProfileRootView: View {
    let user: UserDTO
    @EnvironmentObject var auth: AuthStore

    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarUploadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        ProfileHeaderView(
                            username: user.username,
                            email: user.email,
                            plan: user.plan,
                            avatarUrl: user.avatarUrl
                        )

                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            Label("Change Photo", systemImage: "photo")
                                .font(.subheadline.weight(.medium))
                        }

                        if isUploadingAvatar {
                            ProgressView("Uploading…")
                                .font(.caption)
                        }

                        if let avatarUploadError, !avatarUploadError.isEmpty {
                            Text(avatarUploadError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .onChange(of: selectedAvatarItem) { _, newItem in
                        guard let newItem else { return }
                        Task {
                            await uploadAvatar(from: newItem)
                        }
                    }

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
                            value: displayValue(user.email)
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

    private func uploadAvatar(from item: PhotosPickerItem) async {
        avatarUploadError = nil

        guard let token = auth.currentToken, !token.isEmpty else {
            avatarUploadError = "Missing auth token."
            auth.handleInvalidSession()
            return
        }

        do {
            isUploadingAvatar = true

            guard let data = try await item.loadTransferable(type: Data.self) else {
                avatarUploadError = "Could not read selected image."
                isUploadingAvatar = false
                return
            }

            let responseData = try await APIClient.shared.uploadMultipart(
                path: "users/me/avatar",
                token: token,
                fieldName: "avatar",
                fileData: data,
                fileName: "avatar.jpg",
                mimeType: "image/jpeg"
            )

            let decoded = try JSONDecoder().decode(AvatarUploadResponse.self, from: responseData)

            if case .loggedIn(let existingUser) = auth.state {
                let updated = UserDTO(
                    id: existingUser.id,
                    email: existingUser.email,
                    username: existingUser.username,
                    publicKey: existingUser.publicKey,
                    plan: existingUser.plan,
                    role: existingUser.role,
                    preferredLanguage: existingUser.preferredLanguage,
                    theme: existingUser.theme,
                    avatarUrl: decoded.avatarUrl
                )
                auth.state = .loggedIn(updated)
            }

            isUploadingAvatar = false
        } catch {
            isUploadingAvatar = false
            avatarUploadError = error.localizedDescription
        }
    }
}
