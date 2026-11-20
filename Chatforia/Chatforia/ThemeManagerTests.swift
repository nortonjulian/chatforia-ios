import XCTest
import SwiftUI
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

    func testSearchTextHintAndNavigationTitleContrastAcrossThemes() {
        func luminance(_ color: Color) -> Double {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            let channels = [red, green, blue].map { value -> Double in
                let channel = Double(value)
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }

        func contrast(_ first: Color, _ second: Color) -> Double {
            let values = [luminance(first), luminance(second)].sorted()
            return (values[1] + 0.05) / (values[0] + 0.05)
        }

        let manager = ThemeManager()
        for option in AppThemes.all {
            manager.apply(code: option.code)
            let palette = manager.palette
            let systemTitle: Color = manager.navigationColorScheme == .dark ? .white : .black
            XCTAssertGreaterThanOrEqual(
                contrast(palette.primaryText, palette.cardBackground), 4.5,
                "Typed search text in \(option.code)"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(manager.searchHintText, palette.cardBackground), 4.5,
                "Search prompt and icons in \(option.code)"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(systemTitle, palette.screenBackground), 4.5,
                "Navigation title in \(option.code)"
            )
        }
    }

    func testPinnedSearchRendersWithBothSystemAppearancesAndThemeChanges() {
        let manager = ThemeManager()
        for option in AppThemes.all {
            manager.apply(code: option.code)
            for appearance in [ColorScheme.light, .dark] {
                let field = ThemedPinnedSearchField(
                    text: .constant("Synthetic search"),
                    placeholder: "Search Chats",
                    clearAccessibilityLabel: "Clear chat search"
                )
                let host = UIHostingController(rootView:
                    NavigationStack {
                        field
                            .navigationTitle("Chats")
                            .toolbarBackground(manager.palette.screenBackground, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                            .toolbarColorScheme(manager.navigationColorScheme, for: .navigationBar)
                    }
                    .environmentObject(manager)
                    .environment(\.colorScheme, appearance)
                )
                let size = host.sizeThatFits(in: CGSize(width: 390, height: 844))
                XCTAssertGreaterThan(size.width, 0, "\(option.code), \(appearance)")
                XCTAssertGreaterThan(size.height, 0, "\(option.code), \(appearance)")
            }
        }
    }

    func testSharedAvatarInitialsMeetNormalTextContrastInEveryTheme() {
        func rgb(_ color: Color) -> [Double] {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            return [Double(red), Double(green), Double(blue)]
        }

        func luminance(_ channels: [Double]) -> Double {
            let linear = channels.map { channel in
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }

        for option in AppThemes.all {
            let palette = ThemeCatalog.palette(for: option.code)
            let accent = rgb(palette.accent)
            let card = rgb(palette.cardBackground)
            let background = zip(accent, card).map { pair in
                0.14 * pair.0 + 0.86 * pair.1
            }
            let foreground = rgb(palette.primaryText)
            let light = max(luminance(background), luminance(foreground))
            let dark = min(luminance(background), luminance(foreground))
            XCTAssertGreaterThanOrEqual((light + 0.05) / (dark + 0.05), 4.5,
                                        "Avatar initials need readable contrast in \(option.code)")
        }
    }
}
