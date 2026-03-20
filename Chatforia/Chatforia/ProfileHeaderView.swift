import SwiftUI

struct ProfileHeaderView: View {
    let username: String
    let email: String?
    let plan: String?
    let avatarUrl: String?

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(themeManager.palette.accent.opacity(0.12))
                    .frame(width: 96, height: 96)

                UserAvatarView(
                    avatarUrl: avatarUrl,
                    displayName: username,
                    size: 84,
                    fallbackStyle: .profileDefault
                )
            }

            VStack(spacing: 4) {
                Text(username)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.palette.titleAccent)

                Text(displayEmail)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.palette.secondaryText)

                if let plan, !plan.isEmpty {
                    Text(plan.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.palette.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(themeManager.palette.accent.opacity(0.14))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var displayEmail: String {
        guard let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "—"
        }
        return email
    }
}
