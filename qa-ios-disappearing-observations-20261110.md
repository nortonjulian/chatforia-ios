# Synthetic iOS disappearing-message UI QA — 2026-11-10

Branch `qa/ios-disappearing-ui-20261110` starts at the completed iOS fix `1fd9286`. The disposable iPhone 17 / iOS 27 simulator ID was `519D3177-808A-4414-BD2E-0F1AB45D3491`. The `DISAPPEARING_QA` compile flag selects a separate entry point with no normal app delegate, analytics, push, ads, send queue, or socket startup. It registers a URLSession-denying protocol and points any accidental APIClient request at localhost port 1. The real `ChatThreadView`, `MessagesListView`, `ChatListRowView`, `ChatThreadViewModel`, and `MessageStore` render a synthetic 22-message room; the fixture contains no credentials or provider URL.

## Actual simulator UI observations

- [Before expiry](qa-artifacts/ios-cache-path-before.png), the open thread displayed `Expiring visible text`, the `attachment.txt` file row, and `Expiring attachment`. The production preview row displayed `Expiring attachment`.
- [After expiry and synthetic reconnect/reopen/scroll](qa-artifacts/ios-cache-path-after.png), the preview displayed the latest live `Synthetic history 20`; the old scrolled history began at row 2, with expired row 1 absent. The QA model showed three loads: initial, synthetic reconnect, and thread reopen. The synthetic source was submitted unchanged to the production `MessageStore` filtering path on each load.
- A separate [open-thread deadline capture](qa-artifacts/ios-open-thread-expired.png) shows the expiring text and attachment row gone while the chat remains open. It was captured before the final QA source-path refinement; the production expiry loop did not change.
- Launching Settings and returning to the same QA app process kept expired content absent in the [background/foreground screenshot](qa-artifacts/ios-cache-path-background-reopen.png). The process ID stayed `88595` across that cycle.
- Terminating and starting a new QA app process with the original saved deadline kept the preview and thread free of expired content in the [relaunch screenshot](qa-artifacts/ios-cache-path-relaunch.png).

The preview row is the production `ChatListRowView`, fed an authoritative-style synthetic preview selected by the harness; this does not exercise a deployed `/conversations` response. Reconnect is a synthetic `.socketDidReconnect` notification through the real view-model observer and cache path, not a provider socket connection. The old attachment URL is a `qa://` fixture and was not fetched; deployed attachment-access verification remains outstanding.

## Automated results, separate from UI observations

- Final Xcode result bundle `/private/tmp/chatforia-ios-disappearing-ui-final-tests.xcresult`: `ChatThreadViewModelTests`, `MessageStoreTests`, and `ChatsViewModelTests` passed **32/32**, zero failures or skips, on the disposable simulator.
- The QA-flag simulator app and the normal Debug simulator app both built successfully. The normal build omits the synthetic entry point and retains the existing production URL handling.
- `git diff --check` passed. No product failure was demonstrated; the code changes in this branch are gated QA seams and observations.
