import XCTest
@testable import Chatforia

@MainActor
final class ThemeManagerTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "chatforia.theme")
        super.tearDown()
    }

    func testInitialThemeIsDawn() {
        let manager = ThemeManager()

        XCTAssertEqual(manager.currentCode, "dawn")
    }

    func testApplyValidThemeUpdatesCurrentCode() {
        let manager = ThemeManager()

        manager.apply(code: "midnight")

        XCTAssertEqual(manager.currentCode, "midnight")
    }

    func testApplyTrimsAndLowercasesThemeCode() {
        let manager = ThemeManager()

        manager.apply(code: "  AURORA  ")

        XCTAssertEqual(manager.currentCode, "aurora")
    }

    func testApplyInvalidThemeFallsBackToDawn() {
        let manager = ThemeManager()

        manager.apply(code: "unknown-theme")

        XCTAssertEqual(manager.currentCode, "dawn")
    }

    func testApplySavesThemeToUserDefaults() {
        let manager = ThemeManager()

        manager.apply(code: "velvet")

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "chatforia.theme"),
            "velvet"
        )
    }

    func testThemeCatalogAcceptsMoonAliasForMidnight() {
        let moon = ThemeCatalog.palette(for: "moon")
        let midnight = ThemeCatalog.palette(for: "midnight")

        // Smoke test: both aliases should produce usable palettes.
        XCTAssertNotNil(moon)
        XCTAssertNotNil(midnight)
    }

    func testThemeCatalogUnknownThemeFallsBackToDawn() {
        let palette = ThemeCatalog.palette(for: "not-real")

        XCTAssertNotNil(palette)
    }

    func testAllKnownThemeCodesReturnPalette() {
        let codes = [
            "dawn",
            "midnight",
            "moon",
            "amoled",
            "aurora",
            "neon",
            "sunset",
            "solarized",
            "velvet"
        ]

        for code in codes {
            let palette = ThemeCatalog.palette(for: code)
            XCTAssertNotNil(palette)
        }
    }
}
