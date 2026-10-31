#!/usr/bin/env python3
"""Source-wiring regression check for iOS SMS attachment picker and chat previews.

Not a substitute for building in Xcode or verifying actual carrier delivery.
"""
from pathlib import Path
root = Path(__file__).resolve().parents[1] / "Chatforia" / "Chatforia"
sms = (root / "SMSThreadView.swift").read_text()
chats = (root / "ChatsRootView.swift").read_text()

assert 'showAttachmentChoices = true' in sms
assert '.sheet(isPresented: $showAttachmentChoices)' in sms
assert 'AttachmentPickerSheet(' in sms
assert 'showPhotoPicker = true' in sms
assert 'showVideoPicker = true' in sms
assert 'showGIFPicker = true' in sms
assert 'onVideo:' in sms
assert 'onGIF:' in sms
assert '.sheet(isPresented: $showGIFPicker)' in sms
assert 'GIFPickerView { url in' in sms
assert 'pendingGIFURL = url' in sms
assert 'guard let key = await uploadGIF(from: gifURL)' in sms
assert 'URLSession.shared.data(from: url)' in sms
assert 'data.count <= 5_000_000' in sms
assert 'mimeType: "image/gif"' in sms
assert 'data.starts(with: Data("GIF89a".utf8))' in sms
assert 'pendingGIFURL = nil' in sms
assert 'matching: .images' in sms
assert 'matching: .videos' in sms
assert 'selectedPhotoPreview' in sms
assert 'Selected SMS photo preview' in sms
assert 'Remove selected SMS attachment' in sms
assert 'hasPendingAttachment: !selectedPhotos.isEmpty || selectedVideo != nil || pendingGIFURL != nil' in sms
assert 'guard let key = await uploadVideo(video)' in sms
assert 'let mp4 = try await prepareCarrierMP4(data)' in sms
assert 'AVAssetExportSession(' in sms
assert 'presetName: AVAssetExportPresetLowQuality' in sms
assert 'session.outputFileType = .mp4' in sms
assert 'mp4.count <= 500_000' in sms
assert 'data: mp4,' in sms
assert 'try? FileManager.default.removeItem(at: source)' in sms
assert 'try? FileManager.default.removeItem(at: destination)' in sms
assert 'key.hasPrefix("uploads/u")' in sms
assert 'mediaUrls: [key]' in sms
assert sms.index('selectedVideo = nil\n                draft = ""') > sms.index('if let threadID {')
assert 'isLegacyChatforiaMarker' in chats
assert 'last.hasMedia == true || isLegacyChatforiaMarker' in chats
assert 'case "[image]": kinds = ["IMAGE"]' in chats
assert 'case "[video]": kinds = ["VIDEO"]' in chats
assert 'case "[audio]": kinds = ["AUDIO"]' in chats
assert 'mediaPlaceholder ? "" : rawText' in chats
assert 'kinds.contains("IMAGE")' in chats
assert 'else if item.isVideo {' in sms
assert 'SMSAuthenticatedVideoCard(' in sms
assert 'VideoPlayer(player: player)' in sms
assert 'AVAssetImageGenerator(asset: asset)' in sms
assert 'generator.appliesPreferredTrackTransform = true' in sms
assert 'asset.load(.duration)' in sms
assert 'if let thumbnail {' in sms
assert 'Image(systemName: "play.fill")' in sms
assert 'AudioAttachmentCardView.formatTime(durationSeconds)' in sms
assert 'bytes.count <= 500_000' in sms
assert 'previewBytes = nil' in sms
assert 'clearPreview()' in sms
assert 'path: "sms/media/\\(messageId)/\\(mediaIndex)"' in sms
assert 'APIClient.shared.sendRaw(request, token: token)' in sms
assert 'try bytes.write(to: url, options: .atomic)' in sms
assert 'try? FileManager.default.removeItem(at: playbackURL)' in sms
assert 'TokenStore.shared.read() == token' in sms

print("PASS: SMS shared Photo/Video/GIF gallery, private GIF upload wiring, MOV to MP4, previews, private video playback")
print("NOTE: Xcode compilation, Photos video representation, and real MMS delivery require device QA")
