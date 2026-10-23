import SwiftUI

private struct ContactBlockAccountRequest: Encodable {
    let targetUserId: Int
}

private struct ContactBlockedAccountRow: Decodable {
    let userId: Int
}

private struct ContactBlockedAccountsResponse: Decodable {
    let items: [ContactBlockedAccountRow]
}

private struct ContactBlockMutationResponse: Decodable {
    let success: Bool
}


enum ContactDetailAction {
    case message
    case call
    case video
}

struct ContactDetailView: View {
    let contact: ContactDTO
    let onAction: (ContactDetailAction) -> Void
    let onEdit: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @State private var accountBlockKnown = false
    @State private var isAccountBlocked = false
    @State private var isUpdatingAccountBlock = false
    @State private var confirmAccountBlockChange = false
    @State private var accountBlockError: String?


    private var displayName: String {
        if let alias = contact.alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
            return alias
        }
        if let name = contact.user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let username = contact.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return username
        }
        if let externalName = contact.externalName?.trimmingCharacters(in: .whitespacesAndNewlines), !externalName.isEmpty {
            return externalName
        }
        if let externalPhone = contact.externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !externalPhone.isEmpty {
            return externalPhone
        }
        return appText(
            "ios.unknown_contact",
            languageCode: appLanguage
        )
    }

    private var subtitle: String {
        if let username = contact.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return "@\(username)"
        }
        if let externalPhone = contact.externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !externalPhone.isEmpty {
            return externalPhone
        }
        return appText(
            "contacts.savedContact",
            languageCode: appLanguage
        )
    }

    var body: some View {
        ZStack {
        themeManager.palette.screenBackground
            .ignoresSafeArea()

        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Circle()
                        .fill(themeManager.palette.border)
                        .frame(width: 88, height: 88)
                        .overlay(
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(themeManager.palette.primaryText)
                        )

                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(themeManager.palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                VStack(spacing: 12) {
                    Button {
                        onAction(.message)
                    } label: {
                        actionRow(
                            title: appText("common.message", languageCode: appLanguage),
                            systemImage: "message.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAction(.call)
                    } label: {
                        actionRow(
                            title: appText("common.call", languageCode: appLanguage),
                            systemImage: "phone.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    if contact.user?.id != nil {
                        Button {
                            onAction(.video)
                        } label: {
                            actionRow(
                                title: appText("common.video", languageCode: appLanguage),
                                systemImage: "video.fill"
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            confirmAccountBlockChange = true
                        } label: {
                            actionRow(
                                title: isAccountBlocked
                                    ? "Unblock Chatforia account"
                                    : "Block Chatforia account",
                                systemImage: isAccountBlocked
                                    ? "hand.raised.slash"
                                    : "hand.raised.fill"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!accountBlockKnown || isUpdatingAccountBlock)
                    }
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    detailLine(
                        title: appText("common.name", languageCode: appLanguage),
                        value: displayName
                    )

                    if let externalName = contact.externalName,
                       !externalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailLine(
                            title: appText("contacts.externalName", languageCode: appLanguage),
                            value: externalName
                        )
                    }

                    if let phone = contact.externalPhone,
                       !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailLine(
                            title: appText("common.phone", languageCode: appLanguage),
                            value: phone
                        )
                    }

                    if let username = contact.user?.username,
                       !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailLine(
                            title: appText("common.username", languageCode: appLanguage),
                            value: "@\(username)"
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(themeManager.palette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding()
        }
    }
    .navigationTitle(
        appText("contacts.contact", languageCode: appLanguage)
    )
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Button(
                appText("common.edit", languageCode: appLanguage)
            ) {
                onEdit()
            }
            .foregroundStyle(themeManager.palette.accent)
        }
    }
    .task(id: contact.user?.id) {
        await loadAccountBlockState()
    }
    .confirmationDialog(
        isAccountBlocked ? "Unblock this Chatforia account?" : "Block this Chatforia account?",
        isPresented: $confirmAccountBlockChange,
        titleVisibility: .visible
    ) {
        Button(isAccountBlocked ? "Unblock account" : "Block account") {
            Task { await updateAccountBlock() }
        }
        Button("Cancel", role: .cancel) {}
    } message: {
        Text(isAccountBlocked
             ? "This account will be able to contact you again unless they blocked you."
             : "This account will no longer be able to directly message or call you. Your message history will remain.")
    }
    .alert("Account blocking", isPresented: Binding(
        get: { accountBlockError != nil },
        set: { if !$0 { accountBlockError = nil } }
    )) {
        Button("OK", role: .cancel) { accountBlockError = nil }
    } message: {
        Text(accountBlockError ?? "")
    }
}

    private func loadAccountBlockState() async {
        accountBlockKnown = false
        guard let userId = contact.user?.id else { return }
        guard let token = TokenStore.shared.read() else {
            accountBlockError = "Sign in to manage blocked accounts."
            return
        }
        do {
            let response: ContactBlockedAccountsResponse = try await APIClient.shared.send(
                APIRequest(path: "blocks", method: .GET, requiresAuth: true),
                token: token
            )
            isAccountBlocked = response.items.contains { $0.userId == userId }
            accountBlockKnown = true
        } catch {
            accountBlockError = "Could not load this account's blocking status."
        }
    }

    private func updateAccountBlock() async {
        guard !isUpdatingAccountBlock,
              let userId = contact.user?.id,
              let token = TokenStore.shared.read() else { return }
        isUpdatingAccountBlock = true
        defer { isUpdatingAccountBlock = false }
        do {
            let currentlyBlocked = isAccountBlocked
            let body: Data?
            if currentlyBlocked {
                body = nil
            } else {
                body = try JSONEncoder().encode(ContactBlockAccountRequest(targetUserId: userId))
            }
            let response: ContactBlockMutationResponse = try await APIClient.shared.send(
                APIRequest(
                    path: currentlyBlocked ? "blocks/\(userId)" : "blocks",
                    method: currentlyBlocked ? .DELETE : .POST,
                    body: body,
                    requiresAuth: true
                ),
                token: token
            )
            guard response.success else {
                accountBlockError = "Account blocking could not be updated."
                return
            }
            isAccountBlocked = !currentlyBlocked
            accountBlockKnown = true
        } catch {
            accountBlockError = "Could not update account blocking. Try again."
        }
    }

    private func actionRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(themeManager.palette.accent)
                .frame(width: 24)

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(themeManager.palette.primaryText)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(themeManager.palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeManager.palette.secondaryText)

            Text(value)
                .font(.body)
                .foregroundStyle(themeManager.palette.primaryText)
        }
    }
}
