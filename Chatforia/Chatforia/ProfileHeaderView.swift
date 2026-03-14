import SwiftUI

struct ProfileHeaderView: View {
    let username: String
    let email: String?
    let plan: String?
    let avatarUrl: String?

    var body: some View {
        VStack(spacing: 12) {
            UserAvatarView(
                avatarUrl: avatarUrl,
                displayName: username,
                size: 84,
                fallbackStyle: .profileDefault
            )

            VStack(spacing: 4) {
                Text(username)
                    .font(.title3.weight(.semibold))

                Text(displayEmail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let plan, !plan.isEmpty {
                    Text(plan.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.top, 4)
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
