# Synthetic iOS forwarding UI QA — 2026-11-10

This branch starts from the completed disappearing-message QA commit `f55baba`. The `DISAPPEARING_QA` entry point blocks URLSession requests and omits the normal app delegate, analytics, push, ads, send queue, and socket startup. The forwarding fixture selects an in-memory fetch/save service only with `--forwarding-qa`; the normal `ForwardingSettingsView` initializer still uses `ForwardingService.shared`. Test destinations are synthetic.

## Actual simulator UI observations

- [Account A](qa-artifacts/chatforia-forwarding-ios-account-a-20261110.png): the real `ForwardingSettingsView` showed enabled text forwarding to `+15551110000` and an overnight 22→6 schedule. Save was disabled with no changes pending.
- [Account B](qa-artifacts/chatforia-forwarding-ios-account-b-20261110.png): a separate synthetic account showed enabled call forwarding to `+15552220000` and no account A text destination.
- [Invalid fixture](qa-artifacts/chatforia-forwarding-ios-invalid-20261110.png): the screen displayed the invalid phone and incomplete quiet-hours errors, and Save was disabled.
- [In-process account switch](qa-artifacts/chatforia-forwarding-ios-autoswitch-20261110.png): after the fixture changed the authenticated user from A to B without restarting the app, B's call destination appeared and A's text destination was absent.

These are rendered screen observations, not provider or database results. The fixture did not exercise taps for save/reopen or a deployed settings endpoint; those remain device checks.

## Automated results

- Targeted `ForwardingSettingsViewModelTests` passed **13/13**, zero failed or skipped, in `/private/tmp/chatforia-ios-forwarding-ui-final-tests-20261110.xcresult`.
- The no-network QA app built and launched on the disposable iPhone 17 / iOS 27 simulator. A separate normal Debug app build also passed, with the QA entry point excluded.
- The first forwarding fixture launch crashed because `SectionCardView` needs a `ThemeManager` environment object. The fixture was corrected and the subsequent screen captures above passed; no production settings code was changed for that fixture failure.

The completed disappearing-message UI receipt and artifacts remain unchanged. Firefox, deployed attachment-access denial, physical-device checks, and migration-162 release preparation remain outstanding in their separate tracks. No production or Stage 5/6 recovery work was performed.
