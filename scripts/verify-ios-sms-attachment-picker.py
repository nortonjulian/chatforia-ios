#!/usr/bin/env python3
"""Source-wiring regression check for iOS SMS attachment picker and chat previews.

Not a substitute for building in Xcode or verifying actual carrier delivery.
"""
from pathlib import Path
root = Path(__file__).resolve().parents[1] / "Chatforia" / "Chatforia"
sms = (root / "SMSThreadView.swift").read_text()
chats = (root / "ChatsRootView.swift").read_text()

assert 'showAttachmentChoices = true' in sms
assert 'Button("Photo") { showPhotoPicker = true }' in sms
assert 'Button("Video") { showVideoPicker = true }' in sms
assert 'matching: .images' in sms
assert 'matching: .videos' in sms
assert 'selectedPhotoPreview' in sms
assert 'Selected SMS photo preview' in sms
assert 'Remove selected SMS attachment' in sms
assert 'hasPendingAttachment: !selectedPhotos.isEmpty || selectedVideo != nil' in sms
assert 'guard let key = await uploadVideo(video)' in sms
assert 'data.count <= 500_000' in sms
assert 'key.hasPrefix("uploads/u")' in sms
assert 'mediaUrls: [key]' in sms
assert sms.index('selectedVideo = nil\n                draft = ""') > sms.index('if let threadID {')
assert 'mediaMarkers.contains(rawText.lowercased()) && last.hasMedia == true' in chats
assert 'mediaPlaceholder ? "" : rawText' in chats
assert 'kinds.contains("IMAGE")' in chats

print("PASS: iOS SMS Photo/Video picker, pending media preview, authenticated send, and chat-list marker wiring")
print("NOTE: Xcode compilation, Photos video representation, and real MMS delivery require device QA")
