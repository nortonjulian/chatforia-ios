import SwiftUI

enum ContactDetailAction {
    case message
    case call
}

struct ContactDetailView: View {
    let contact: ContactDTO
    let onAction: (ContactDetailAction) -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    private var displayName: String {
        if let alias = contact.alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
            return alias
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
        return "Unknown Contact"
    }

    private var subtitle: String {
        if let username = contact.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            return "@\(username)"
        }
        if let externalPhone = contact.externalPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !externalPhone.isEmpty {
            return externalPhone
        }
        return "Saved contact"
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
                                title: "Message",
                                systemImage: "message.fill"
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onAction(.call)
                        } label: {
                            actionRow(
                                title: "Call",
                                systemImage: "phone.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 14) {
                        detailLine(title: "Name", value: displayName)

                        if let externalName = contact.externalName, !externalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            detailLine(title: "External Name", value: externalName)
                        }

                        if let phone = contact.externalPhone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            detailLine(title: "Phone", value: phone)
                        }

                        if let username = contact.user?.username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            detailLine(title: "Username", value: "@\(username)")
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
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
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
