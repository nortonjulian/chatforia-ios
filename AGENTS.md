# AGENTS

## Purpose
This repository is an iOS SwiftUI app named Chatforia. The codebase is centered in `Chatforia/Chatforia/` and builds from the Xcode project at `Chatforia/Chatforia.xcodeproj`.

## Recommended workflow
- Open `Chatforia/Chatforia.xcodeproj` in Xcode.
- Use the `Chatforia` target and the app scheme if available.
- The project uses SwiftUI, async/await, and Swift Package Manager–resolved frameworks inside the Xcode project.
- Do not assume there is a separate README or docs file; inspect source files and the Xcode project directly.

## Key areas
- `Chatforia/Chatforia/ChatforiaApp.swift` — app entry point.
- `Chatforia/Chatforia/` — main app code, views, models, services, and controllers.
- `Chatforia/Chatforia/Localizable.xcstrings` — large localized string catalog; do not edit keys without confirming usage.
- `Chatforia/Chatforia/Info.plist` — app configuration and privacy descriptions.
- `Chatforia/Chatforia/Chatforia.entitlements` — entitlements for features like call handling.

## Important conventions
- UI strings are often wrapped using `String(localized:)` with localized keys.
- Views use SwiftUI state, environment objects, and navigation destinations extensively.
- Networking and API logic are usually contained in `APIClient.swift`, services, and view models.
- The app contains multiple communication features: messaging, SMS support, voice calling, video calling, ads, and device pairing.

## Build guidance
- Primary build path is Xcode. If using CLI, build the Xcode project directly:
  - `xcodebuild -project Chatforia/Chatforia.xcodeproj -scheme Chatforia -destination 'platform=iOS Simulator,name=iPhone 15' build`
- The project currently uses Xcode-managed dependencies and an Xcode project-based target configuration.

## When editing code
- Prefer small targeted code changes and keep SwiftUI state and async flows consistent.
- Avoid new errors in localization keys or Xcode build settings.
- If the task touches privacy-sensitive functionality, verify permission strings in `Info.plist`.

## Notes for AI agents
- There is no existing agent-specific documentation in the repo.
- Avoid bulk refactors of the localized strings file unless the change is clearly needed.
- If you cannot determine the correct build scheme, use the `Chatforia` target in `Chatforia/Chatforia.xcodeproj`.
