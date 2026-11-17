import XCTest
@testable import Chatforia

@MainActor
final class ProfileLanguageSaveTests: XCTestCase {
    func testPreferredLanguageSaveCarriesTranslationPreferences() {
        let settings = SettingsViewModel()
        settings.preferredLanguage = "es"
        settings.autoTranslate = true
        settings.showOriginalWithTranslation = false

        let request = settings.makeRequest()

        XCTAssertEqual(request.preferredLanguage, "es")
        XCTAssertEqual(request.uiLanguage, "es")
        XCTAssertTrue(request.autoTranslate)
        XCTAssertFalse(request.showOriginalWithTranslation)
    }

    func testLanguageSaveDoesNotReplaceProfileTabOrNavigationStackIdentity() throws {
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let shell = try String(
            contentsOf: sourceDirectory.appendingPathComponent("AppShellView.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: sourceDirectory.appendingPathComponent("ChatforiaApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(shell.contains(".id(appLanguage)"))
        XCTAssertFalse(app.contains(".id(appLanguage)"))
        XCTAssertTrue(shell.contains("TabView(selection: $selectedTab)"))
    }
}
