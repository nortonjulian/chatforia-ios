# iOS forwarding zone and persistent mock QA — 2026-11-10

All data and recipients were synthetic. The QA app registered a network-denying URL protocol, and the injected forwarding fetch/save closures used a local `UserDefaults` store keyed by synthetic account. Production builds exclude the QA-only launch path. Existing disappearing-message and earlier forwarding results remain unchanged.

## Automated checks

- `ForwardingSettingsViewModelTests` in the disposable iPhone 17 simulator: **15 passed, 0 failed**. The added tests cover device-zone default for a legacy `NULL` setting, saved-zone retention on a second device zone, and invalid-zone rejection. The final rerun after the fixed-offset fallback passed; result bundle: `/private/tmp/chatforia-ios-forwarding-zone-final-20261110.xcresult`.
- Normal Debug simulator build without `DISAPPEARING_QA`: **passed**. The build emitted existing Swift concurrency and dependency warnings; it had exit code 0.

## Observed simulator UI

1. Launched account A with an empty QA store. A QA-only launch argument set a 21→06 schedule and `America/Denver`, then called the real `ForwardingSettingsView.save()` path. The mock persisted the DTO, and the root removed and re-created the actual settings screen. The [reopened screen](qa-artifacts/chatforia-forwarding-ios-zone-reopened-20261110.png) displayed 21, 6, `America/Denver`, and the saved-zone explanation.
2. Terminated the app and launched synthetic account B. The [B screen](qa-artifacts/chatforia-forwarding-ios-zone-account-b-20261110.png) showed B's separate call destination, no A text destination or quiet-hour values, and the unsaved device-zone explanation.
3. Terminated the app and relaunched A without the auto-save argument. The [A relaunch screen](qa-artifacts/chatforia-forwarding-ios-zone-account-a-relaunch-20261110.png) still displayed 21, 6, and `America/Denver` from the persistent mock.

The save was triggered by a QA-only automation seam in the real view, not by a finger tap. This proves the screen's save/reload path and account-keyed local persistence in a running simulator; it does not prove deployed API persistence or provider behavior. The dedicated simulator was shut down after the run.
