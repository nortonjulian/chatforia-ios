import SwiftUI

struct ProfileHeaderView: View {
    let username: String
    let email: String
    let plan: String?

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 84, height: 84)
                .overlay(
                    Text(initials)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                )

            VStack(spacing: 4) {
                Text(username)
                    .font(.title3.weight(.semibold))

                Text(email)
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

    private var initials: String {
        let parts = username
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if !parts.isEmpty {
            return parts.joined()
        }

        return String(username.prefix(1)).uppercased()
    }
}
