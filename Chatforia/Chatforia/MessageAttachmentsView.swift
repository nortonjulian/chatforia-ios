import SwiftUI
import AVKit

struct MessageAttachmentsView: View {
    let attachments: [AttachmentDTO]
    let isMe: Bool
    let maxWidth: CGFloat
    let onVideoTap: ((URL) -> Void)?

    @AppStorage("chatforia_language") private var appLanguage = "en"
    @EnvironmentObject private var auth: AuthStore
    @State private var selectedImageURL: IdentifiableURL?
    // Scoped by account, session, attachment and media variant. A URL from
    // the previous account is never returned when identity changes.
    @State private var grantedMediaURLs: [String: String] = [:]

    @ObservedObject private var audioPlayback = AudioPlaybackViewModel.shared

    private struct MediaGrant: Decodable {
        let url: String
    }

    private var mediaScope: String {
        let identity = String(auth.currentUser?.id ?? 0)
        let session = String(auth.currentToken?.hashValue ?? 0)
        let attachmentsKey = attachments.map {
            String($0.id ?? -1) + ":" + ($0.url ?? "") + ":" + ($0.thumbUrl ?? "")
        }.joined(separator: "|")
        return identity + "/" + session + "/" + attachmentsKey
    }

    private func isLocalPrivateMedia(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URLComponents(string: normalized),
           url.scheme?.lowercased() == "https",
           url.host?.lowercased() == "cdn.chatforia.com",
           url.port == nil,
           url.user == nil,
           url.password == nil,
           url.query == nil,
           url.fragment == nil,
           url.percentEncodedPath.range(of: "%") == nil {
            let pieces = url.path.split(separator: "/")
            return pieces.count >= 4 && pieces[0] == "uploads" &&
                pieces[1].hasPrefix("u") &&
                Int(pieces[1].dropFirst()) != nil &&
                pieces.dropFirst(2).allSatisfy {
                    !$0.isEmpty && $0 != "." && $0 != ".." &&
                    $0.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
                }
        }
        if normalized.lowercased().hasPrefix("http://") ||
           normalized.lowercased().hasPrefix("https://") {
            return false
        }
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count >= 2 && (
            parts.first == "media" || parts.first == "thumbs" ||
            (parts.count >= 3 && parts.first == "uploads" &&
             (parts[1] == "media" || parts[1] == "thumbs"))
        )
    }

    private func grantKey(for id: Int, variant: String) -> String {
        mediaScope + "/" + String(id) + "/" + variant
    }

    private func authorizedAttachment(_ attachment: AttachmentDTO) -> AttachmentDTO {
        let id = attachment.id
        let full = isLocalPrivateMedia(attachment.url)
            ? id.flatMap { grantedMediaURLs[grantKey(for: $0, variant: "file")] }
            : attachment.url
        let preview = isLocalPrivateMedia(attachment.thumbUrl)
            ? id.flatMap { grantedMediaURLs[grantKey(for: $0, variant: "thumb")] }
            : attachment.thumbUrl

        return AttachmentDTO(
            id: attachment.id,
            kind: attachment.kind,
            url: full,
            mimeType: attachment.mimeType,
            width: attachment.width,
            height: attachment.height,
            durationSec: attachment.durationSec,
            caption: attachment.caption,
            thumbUrl: preview
        )
    }

    private func requestMediaGrant(
        for id: Int, variant: String, token: String
    ) async -> String? {
        do {
            let response: MediaGrant = try await APIClient.shared.send(
                APIRequest(
                    path: "private-media/message/\(id)?variant=\(variant)",
                    method: .GET,
                    requiresAuth: true
                ),
                token: token
            )
            // Only allow capability URLs from our own API origin and endpoint.
            guard let resolved = URL(
                string: response.url, relativeTo: AppEnvironment.apiBaseURL
            )?.absoluteURL,
                  resolved.scheme == "https",
                  resolved.host == AppEnvironment.apiBaseURL.host,
                  resolved.path == "/private-media/file",
                  URLComponents(url: resolved, resolvingAgainstBaseURL: false)?
                    .queryItems?.contains(where: { $0.name == "token" }) == true
            else { return nil }
            return resolved.absoluteString
        } catch {
            return nil // Fail closed; never reuse an unprotected local path.
        }
    }

    private func refreshGrantedMedia(for scope: String, token: String) async {
        for attachment in attachments {
            guard !Task.isCancelled, mediaScope == scope, let id = attachment.id else {
                continue
            }
            for (variant, original) in [
                ("file", attachment.url),
                ("thumb", attachment.thumbUrl)
            ] where isLocalPrivateMedia(original) {
                let url = await requestMediaGrant(for: id, variant: variant, token: token)
                guard !Task.isCancelled, mediaScope == scope else { return }
                grantedMediaURLs[grantKey(for: id, variant: variant)] = url
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                attachmentCard(authorizedAttachment(attachment))
            }
        }
        .frame(maxWidth: maxWidth, alignment: isMe ? .trailing : .leading)
        .sheet(item: $selectedImageURL) { item in
            AttachmentImageViewer(imageURL: item.url)
        }
        .task(id: mediaScope) {
            let scope = mediaScope
            grantedMediaURLs.removeAll()
            guard auth.currentUser != nil,
                  let token = auth.currentToken, !token.isEmpty else {
                return
            }
            while !Task.isCancelled, mediaScope == scope {
                await refreshGrantedMedia(for: scope, token: token)
                do {
                    try await Task.sleep(nanoseconds: 40_000_000_000)
                } catch {
                    return
                }
            }
        }
        .onChange(of: auth.currentUser?.id) { _, _ in
            // Playback is shared globally; do not retain a prior user's audio.
            audioPlayback.stop()
            selectedImageURL = nil
        }
    }

    @ViewBuilder
    private func attachmentCard(_ attachment: AttachmentDTO) -> some View {
        let kind = (attachment.kind ?? "").uppercased()
        let mimeType = (attachment.mimeType ?? "").lowercased()

        if mimeType == "image/gif" || kind == "GIF" {
            gifCard(attachment)
        } else {
            switch kind {
            case "IMAGE":
                imageCard(attachment)
            case "AUDIO":
                audioCard(attachment)
            case "VIDEO":
                videoCard(attachment)
            case "FILE":
                tappableFileCard(
                    title: attachment.caption?.nilIfBlank ?? fileNameFromURL(attachment.url) ?? appText(
                        "common.file",
                        languageCode: appLanguage
                    ),
                    subtitle: attachment.mimeType?.nilIfBlank ?? appText(
                        "messages.attachment",
                        languageCode: appLanguage
                    ),
                    systemImage: "doc.fill",
                    urlString: attachment.url
                )
            default:
                tappableFileCard(
                    title: attachment.caption?.nilIfBlank ?? appText(
                        "messages.attachment",
                        languageCode: appLanguage
                    ),
                    subtitle: attachment.mimeType?.nilIfBlank ?? appText(
                        "messages.attachment",
                        languageCode: appLanguage
                    ),
                    systemImage: "paperclip",
                    urlString: attachment.url
                )
            }
        }
    }
    
    @ViewBuilder
    private func videoCard(_ attachment: AttachmentDTO) -> some View {
        let mime = (attachment.mimeType ?? "").lowercased()
        let supportedInline = [
            "video/mp4",
            "video/quicktime",
            "video/3gpp",
            "video/3gpp2"
        ].contains(mime)

        VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
            if supportedInline, let url = resolvedURL(from: attachment.url) {
                ZStack {
                    InlineVideoPlayerView(url: url)
                        .frame(width: min(maxWidth, 240), height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        onVideoTap?(url)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.clear)

                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                        .frame(width: min(maxWidth, 240), height: 180)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                tappableFileCard(
                    title: attachment.caption?.nilIfBlank ?? appText(
                        "messages.mediaVideo",
                        languageCode: appLanguage
                    ),
                    subtitle: attachment.mimeType?.nilIfBlank ?? appText(
                        "messages.videoAttachment",
                        languageCode: appLanguage
                    ),
                    systemImage: "video.fill",
                    urlString: attachment.url
                )
            }

        }
    }

    @ViewBuilder
    private func imageCard(_ attachment: AttachmentDTO) -> some View {
        let thumbURLString = attachment.thumbUrl?.nilIfBlank
        let fullURLString = attachment.url?.nilIfBlank
        let previewURLString = thumbURLString ?? fullURLString
        let fullURL = fullURLString.flatMap { URL(string: absoluteMediaURLString($0)) }

        VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
            if let previewURLString,
               let url = URL(string: absoluteMediaURLString(previewURLString)) {
                Button {
                    if let fullURL {
                        selectedImageURL = IdentifiableURL(url: fullURL)
                    } else {
                        selectedImageURL = IdentifiableURL(url: url)
                    }
                } label: {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                                ProgressView()
                            }
                            .frame(width: min(maxWidth, 240), height: 180)

                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: min(maxWidth, 240), maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        case .failure:
                            fallbackMediaCard(
                                title: attachment.caption?.nilIfBlank ?? appText(
                                    "messages.mediaPhoto",
                                    languageCode: appLanguage
                                ),
                                subtitle: attachment.mimeType?.nilIfBlank ?? appText(
                                    "messages.imageAttachment",
                                    languageCode: appLanguage
                                ),
                                systemImage: "photo.fill"
                            )
                            .frame(width: min(maxWidth, 240))

                        @unknown default:
                            fallbackMediaCard(
                                title: attachment.caption?.nilIfBlank ?? appText(
                                    "messages.mediaPhoto",
                                    languageCode: appLanguage
                                ),
                                subtitle: attachment.mimeType?.nilIfBlank ?? appText(
                                    "messages.imageAttachment",
                                    languageCode: appLanguage
                                ),
                                systemImage: "photo.fill"
                            )
                            .frame(width: min(maxWidth, 240))
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                fallbackMediaCard(
                    title: attachment.caption?.nilIfBlank ?? appText(
                        "messages.mediaPhoto",
                        languageCode: appLanguage
                    ),
                    subtitle: attachment.mimeType?.nilIfBlank ?? appText(
                        "messages.imageAttachment",
                        languageCode: appLanguage
                    ),
                    systemImage: "photo.fill"
                )
                .frame(width: min(maxWidth, 240))
            }

            }
        }
    
    
    @ViewBuilder
    private func gifCard(_ attachment: AttachmentDTO) -> some View {
        let thumbURLString = attachment.thumbUrl?.nilIfBlank
        let fullURLString = attachment.url?.nilIfBlank
        let previewURLString = thumbURLString ?? fullURLString
        let fullURL = fullURLString.flatMap { URL(string: absoluteMediaURLString($0)) }

        VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
            if let previewURLString,
               let url = URL(string: absoluteMediaURLString(previewURLString)) {

                Button {
                    if let fullURL {
                        selectedImageURL = IdentifiableURL(url: fullURL)
                    } else {
                        selectedImageURL = IdentifiableURL(url: url)
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        GIFWebView(url: url)
                            .frame(width: min(maxWidth, 240), height: 180)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Text(appText("media.gif", languageCode: appLanguage))
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.72))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(8)
                    }
                }
                .buttonStyle(.plain)

            } else {
                fallbackMediaCard(
                    title: attachment.caption?.nilIfBlank ?? appText(
                        "media.gif",
                        languageCode: appLanguage
                    ),
                    subtitle: attachment.mimeType?.nilIfBlank ?? appText(
                        "messages.gifAttachment",
                        languageCode: appLanguage
                    ),
                    systemImage: "photo"
                )
                .frame(width: min(maxWidth, 240))
            }
        }
    }

    @ViewBuilder
    private func audioCard(_ attachment: AttachmentDTO) -> some View {
        let title = attachment.caption?.nilIfBlank ?? appText(
            "composer.voiceNote",
            languageCode: appLanguage,
            fallback: "Voice note"
        )

        if let url = resolvedURL(from: attachment.url) {
            let urlString = url.absoluteString
            let isCurrent = audioPlayback.isCurrent(
                urlString: urlString
            )

            let displayedDuration = isCurrent
                ? audioPlayback.displayDuration(
                    fallback: attachment.durationSec
                )
                : attachment.durationSec ?? 0

            let displayedCurrentTime = isCurrent
                ? audioPlayback.currentTime
                : 0

            HStack(spacing: 12) {
                Button {
                    audioPlayback.togglePlayback(
                        urlString: urlString
                    )
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 44, height: 44)

                        if isCurrent && audioPlayback.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(
                                systemName:
                                    isCurrent && audioPlayback.isPlaying
                                    ? "pause.fill"
                                    : "play.fill"
                            )
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(
                                x: isCurrent && audioPlayback.isPlaying
                                    ? 0
                                    : 1
                            )
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isCurrent, displayedDuration > 0 {
                        Slider(
                            value: Binding(
                                get: {
                                    min(
                                        audioPlayback.currentTime,
                                        displayedDuration
                                    )
                                },
                                set: { newValue in
                                    audioPlayback.seek(to: newValue)
                                }
                            ),
                            in: 0...displayedDuration
                        )
                        .controlSize(.small)
                    } else {
                        ProgressView(
                            value: displayedCurrentTime,
                            total: max(displayedDuration, 1)
                        )
                        .progressViewStyle(.linear)
                    }

                    HStack {
                        Text(
                            formattedDuration(
                                displayedCurrentTime
                            )
                        )

                        Spacer(minLength: 8)

                        Text(
                            formattedDuration(
                                displayedDuration
                            )
                        )
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            .padding(12)
            .frame(maxWidth: min(maxWidth, 280))
            .background(
                Color(uiColor: .secondarySystemBackground)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        } else {
            fileLikeCard(
                title: title,
                subtitle: attachment.mimeType?.nilIfBlank ?? appText(
                    "messages.audioAttachment",
                    languageCode: appLanguage
                ),
                systemImage: "waveform"
            )
        }
    }

    @ViewBuilder
    private func tappableFileCard(title: String, subtitle: String, systemImage: String, urlString: String?) -> some View {
        if let url = resolvedURL(from: urlString) {
            Link(destination: url) {
                fileLikeCard(title: title, subtitle: subtitle, systemImage: systemImage)
            }
            .buttonStyle(.plain)
        } else {
            fileLikeCard(title: title, subtitle: subtitle, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private func fileLikeCard(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func fallbackMediaCard(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func fileNameFromURL(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw) else { return nil }
        let last = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return last.isEmpty ? nil : last
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func absoluteMediaURLString(_ value: String) -> String {
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return value
        }

        let base = AppEnvironment.apiBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = value.hasPrefix("/") ? value : "/" + value
        return base + path
    }

    private func resolvedURL(from value: String?) -> URL? {
        guard let value = value?.nilIfBlank else { return nil }
        return URL(string: absoluteMediaURLString(value))
    }
}

private struct AttachmentImageViewer: View {
    let imageURL: URL
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chatforia_language") private var appLanguage = "en"

    private var isGIF: Bool {
        imageURL.pathExtension.lowercased() == "gif"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isGIF {
                    GIFWebView(url: imageURL)
                        .ignoresSafeArea()
                } else {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)

                        case .success(let image):
                            ZoomableImageView(image: image)

                        case .failure:
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 28))
                                Text(
                                    appText(
                                        "media.couldNotLoadImage",
                                        languageCode: appLanguage
                                    )
                                )
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)

                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        appText(
                            "common.done",
                            languageCode: appLanguage
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ZoomableImageView: View {
    let image: Image

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(1, min(lastScale * value, 4))
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if scale > 1 {
                        scale = 1
                        lastScale = 1
                    } else {
                        scale = 2
                        lastScale = 2
                    }
                }
            }
            .padding()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
