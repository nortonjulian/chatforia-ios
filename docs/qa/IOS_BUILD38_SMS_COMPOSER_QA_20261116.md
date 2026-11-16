# Build 38 iOS SMS unread and composer QA — local review

Branch: `release/build38-integration-20261115`. No provider traffic, TestFlight upload, or production change occurred.

## Local verification

- The SMS thread GET is read-only. The foreground scroll viewport reports intersecting row IDs; only positive, inbound IDs from the loaded, owned thread are sent in batches of at most 100 to `POST /sms/threads/:id/read` with `messageIds`. Background, obscured, wrong-account, wrong-thread, and off-screen rows do not create acknowledgment work.
- A failed POST leaves unread state unchanged and retries the same visible IDs on the next layout, refresh, or foreground event. An in-flight POST cannot be claimed twice. Newly visible arrivals need their own POST. After success, the chat list fetches its authoritative count and the app badge fetches authoritative badge state; neither assumes the count is zero.
- The redundant composer globe and its stored language-selection preference wiring are removed. The stable per-conversation UIKit context remains for user-selected system keyboard memory. App language, instant translation settings, drafts, AI actions, attachments, recording, and accessibility code paths were not changed.
- Focused iPhone 17 / iOS 27 Simulator XCTest run: **44/44 passed** across SMS thread, typing context, chat list, and notification suites. After additional SMS isolation assertions, SMS + chat list **24/24 passed**; the final SMS suite **17/17 passed** after viewport and socket checks. The final iOS Simulator **Release build passed** with code signing disabled. These are automated results, not physical-device observations.
- The older standalone `verify-sms-unread.py` models the retired GET-marks-read contract and is historical evidence. `verify-ios-live-updates.py` currently has an unrelated stale `MessageDTO` fixture missing `expiresAt`; `verify-sms-refresh-labels.py` asserts a missing `sms.voiceNote` catalog key. These harnesses were not counted as passing current checks. The focused XCTest suites and Release compile above passed.

## Physical-device QA still required

1. With a test account and synthetic or controlled inbound SMS/MMS, open a thread with multiple unread items. Confirm only on-screen inbound rows clear, scrolling reveals and clears older rows, and the Chats count and home-screen badge match the server after each acknowledgment.
2. While a read POST is pending or connectivity fails, deliver another message. Confirm the new unread item remains until visible; retry after reconnection and confirm no duplicate or wrong-thread clearing. Repeat after app background/foreground, push navigation, and account switching.
3. Verify manual iOS keyboard switching in two conversations retains drafts and does not alter app language or instant-translation preferences. Confirm composer AI tools, attachments, voice recording, labels, and VoiceOver focus still work without the globe menu.
4. Once the separate backend alias change is reviewed and deployed, confirm an SMS and MMS push title uses the receiving account's saved alias, and an unsaved number falls back to the phone number. APNs delivery and device badge behavior remain live checks.
