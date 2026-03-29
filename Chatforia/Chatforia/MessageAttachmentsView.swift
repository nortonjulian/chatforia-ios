import SwiftUI

struct MessageAttachmentsView: View {
    let attachments: [AttachmentDTO]
    let isMe: Bool
    let maxWidth: CGFloat

    @State private var selectedImageURL: IdentifiableURL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                attachmentCard(attachment)
            }
        }
        .frame(maxWidth: maxWidth, alignment: isMe ? .trailing : .leading)
        .sheet(item: $selectedImageURL) { item in
            AttachmentImageViewer(imageURL: item.url)
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
                tappableFileCard(
                    title: attachment.caption?.nilIfBlank ?? "Video",
                    subtitle: attachment.mimeType?.nilIfBlank ?? "Video attachment",
                    systemImage: "video.fill",
                    urlString: attachment.url
                )
            case "FILE":
                tappableFileCard(
                    title: attachment.caption?.nilIfBlank ?? fileNameFromURL(attachment.url) ?? "File",
                    subtitle: attachment.mimeType?.nilIfBlank ?? "File attachment",
                    systemImage: "doc.fill",
                    urlString: attachment.url
                )
            default:
                tappableFileCard(
                    title: attachment.caption?.nilIfBlank ?? "Attachment",
                    subtitle: attachment.mimeType?.nilIfBlank ?? "Attachment",
                    systemImage: "paperclip",
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

        VStack(alignment: .leading, spacing: 6) {
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
                                .scaledToFill()
                                .frame(width: min(maxWidth, 240), height: 180)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        case .failure:
                            fallbackMediaCard(
                                title: attachment.caption?.nilIfBlank ?? "Image",
                                subtitle: attachment.mimeType?.nilIfBlank ?? "Image attachment",
                                systemImage: "photo.fill"
                            )
                            .frame(width: min(maxWidth, 240))

                        @unknown default:
                            fallbackMediaCard(
                                title: attachment.caption?.nilIfBlank ?? "Image",
                                subtitle: attachment.mimeType?.nilIfBlank ?? "Image attachment",
                                systemImage: "photo.fill"
                            )
                            .frame(width: min(maxWidth, 240))
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                fallbackMediaCard(
                    title: attachment.caption?.nilIfBlank ?? "Image",
                    subtitle: attachment.mimeType?.nilIfBlank ?? "Image attachment",
                    systemImage: "photo.fill"
                )
                .frame(width: min(maxWidth, 240))
            }

            if let caption = attachment.caption?.nilIfBlank {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }
    
    @ViewBuilder
    private func gifCard(_ attachment: AttachmentDTO) -> some View {
        let thumbURLString = attachment.thumbUrl?.nilIfBlank
        let fullURLString = attachment.url?.nilIfBlank
        let previewURLString = thumbURLString ?? fullURLString
        let fullURL = fullURLString.flatMap { URL(string: absoluteMediaURLString($0)) }

        VStack(alignment: .leading, spacing: 6) {
            if let previewURLString,
               let url = URL(string: absoluteMediaURLString(previewURLString)) {

                Button {
                    if let fullURL {
                        selectedImageURL = IdentifiableURL(url: fullURL)
                    } else {
                        selectedImageURL = IdentifiableURL(url: url)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            GIFWebView(url: url)
                                .frame(width: min(maxWidth, 240), height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Text("GIF")
                                .font(.caption2.bold())
                                .padding(6)
                                .background(.black.opacity(0.7))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                                .padding(6)
                        }
                    }
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

            } else {
                fallbackMediaCard(
                    title: attachment.caption?.nilIfBlank ?? "GIF",
                    subtitle: attachment.mimeType?.nilIfBlank ?? "GIF attachment",
                    systemImage: "photo"
                )
                .frame(width: min(maxWidth, 240))
            }
        }
    }

    @ViewBuilder
    private func audioCard(_ attachment: AttachmentDTO) -> some View {
        let title = attachment.caption?.nilIfBlank ?? "Audio"
        let subtitle: String = {
            if let dur = attachment.durationSec {
                return formattedDuration(dur)
            }
            return attachment.mimeType?.nilIfBlank ?? "Audio attachment"
        }()

        tappableFileCard(
            title: title,
            subtitle: subtitle,
            systemImage: "waveform",
            urlString: attachment.url
        )
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
                                Text("Could not load image")
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
                    Button("Done") {
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
