#!/usr/bin/env python3
"""Static regression check for the production iOS SMS photo/MMS path.

Run separately from Xcode compile and device testing; this confirms source wiring
only, not successful HTTP upload, provider acceptance or carrier delivery.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = (root / "Chatforia/Chatforia/SMSThreadView.swift").read_text()
upload = (root / "Chatforia/Chatforia/UploadService.swift").read_text()
vm = (root / "Chatforia/Chatforia/SMSThreadViewModel.swift").read_text()

begin = view.index("    private func uploadImages(_ items: [PhotosPickerItem])")
end = view.index("\n}\n\n// MARK: - Messages list", begin)
photo = view[begin:end]

begin = view.index("        if !selectedPhotos.isEmpty {")
end = view.index("        let trimmed = draft.trimmingCharacters", begin)
send = view[begin:end]

assert "matching: .images" in view
assert "maxSelectionCount: 5" in view
assert "resized.jpegData(compressionQuality:" in photo
assert "aggregateBytes <= maxMessageBytes" in photo
assert "targetJPEGBytes = 1_000_000" in photo
assert "var preparedPhotos: [Data] = []" in photo
assert photo.index("preparedPhotos.append(jpeg)") < photo.index("for jpeg in preparedPhotos")
assert "UploadService.shared.uploadImage(data: jpeg, token: token)" in photo
assert "let key = uploaded.key" in photo
assert "keys.append(key)" in photo
assert "uploaded.url" not in photo
assert "selectedPhotos.removeAll()" in send
assert send.index("selectedPhotos.removeAll()") > send.index("if let threadId {")
assert "await vm.sendMediaMessage(" in send
assert "mediaUrls: urls" in send
assert 'APIRequest(path: "sms/send"' in vm
assert 'path: "uploads/complete"' in upload
assert "key: file.key ?? intent.key" in upload

print("PASS: iOS SMS photo JPEG conversion, 1 MB target, 5 MB aggregate cap, private key, retry, send route wiring")
print("NOTE: Photo-only scope; video selection and live carrier delivery are not tested.")
