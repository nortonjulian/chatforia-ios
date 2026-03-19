import SwiftUI

struct UserAvatarView: View {
    enum FallbackStyle {
        case profileDefault
        case initialsPreferred
    }

    let avatarUrl: String?
    let displayName: String
    let size: CGFloat
    let fallbackStyle: FallbackStyle

    var body: some View {
        Group {
            if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()

                    case .failure(_):
                        fallbackView

                    case .empty:
                        placeholderView

                    @unknown default:
                        fallbackView
                    }
                }
                .id(avatarUrl ?? "")
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityLabel("\(displayName) avatar")
    }

    private var resolvedURL: URL? {
        guard let raw = avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let absoluteString: String
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            absoluteString = raw
        } else {
            let base = AppEnvironment.apiBaseURL
            let baseString = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let path = raw.hasPrefix("/") ? raw : "/\(raw)"
            absoluteString = baseString + path
        }

        guard var components = URLComponents(string: absoluteString) else {
            return URL(string: absoluteString)
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "v", value: String(raw.hashValue)))
        components.queryItems = queryItems

        return components.url
    }
    
    @ViewBuilder
    private var fallbackView: some View {
        switch fallbackStyle {
        case .profileDefault:
            if let image = UIImage(named: "default-avatar") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                initialsView
            }

        case .initialsPreferred:
            if initialsText.isEmpty, let image = UIImage(named: "default-avatar") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                initialsView
            }
        }
    }

    private var placeholderView: some View {
        Circle()
            .fill(Color(uiColor: .systemGray5))
            .overlay(
                ProgressView()
                    .scaleEffect(0.8)
            )
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.14))
            .overlay(
                Text(initialsText)
                    .font(initialsFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            )
    }

    private var initialsFont: Font {
        if size >= 72 { return .title3 }
        if size >= 44 { return .headline }
        return .caption
    }

    private var initialsText: String {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        let parts = cleaned
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if !parts.isEmpty {
            return parts.joined()
        }

        return String(cleaned.prefix(1)).uppercased()
    }
}
