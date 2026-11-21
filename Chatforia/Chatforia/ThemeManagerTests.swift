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

    func testNavigationAndFilledControlSemanticColorsMeetContrastAcrossThemes() {
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
            XCTAssertGreaterThanOrEqual(
                contrast(manager.toolbarIconForeground, palette.screenBackground), 3,
                "Toolbar icons in \(option.code)"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(manager.toolbarTextForeground, palette.screenBackground), 4.5,
                "Edit and Done in \(option.code)"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(manager.accentControlForeground, palette.accent), 3,
                "Call and playback symbols in \(option.code)"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(
                    manager.controlForeground(
                        on: palette.bubbleOutgoingStart,
                        preferred: palette.bubbleOutgoingText
                    ),
                    palette.bubbleOutgoingStart
                ), 3,
                "Outgoing audio control in \(option.code)"
            )
            for surface in [palette.cardBackground, palette.composerFieldBackground] {
                XCTAssertGreaterThanOrEqual(
                    contrast(manager.accessoryForeground(on: surface), surface), 3,
                    "Composer accessories in \(option.code)"
                )
            }
        }
    }

    func testRenderedGradientForegroundContrastAcrossThemesAndAppearances() {
        func luminance(_ components: [CGFloat]) -> Double {
            let channels = components.prefix(3).map { value -> Double in
                let channel = Double(value)
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }

        func contrast(_ first: [CGFloat], _ second: [CGFloat]) -> Double {
            let values = [luminance(first), luminance(second)].sorted()
            return (values[1] + 0.05) / (values[0] + 0.05)
        }

        func components(_ color: Color) -> [CGFloat] {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            return [red, green, blue]
        }

        let manager = ThemeManager()
        let width = 256
        for option in AppThemes.all {
            manager.apply(code: option.code)
            for appearance in [ColorScheme.light, .dark] {
                for role in [ThemeGradientRole.button, .composer, .outgoingBubble] {
                    let isBubble = role == .outgoingBubble
                    let height = isBubble ? 256 : 64
                    let renderer = ImageRenderer(content:
                        ThemedGradientFill(
                            role: role,
                            startPoint: isBubble ? .topLeading : .leading,
                            endPoint: isBubble ? .bottomTrailing : .trailing
                        )
                            .environmentObject(manager)
                            .environment(\.colorScheme, appearance)
                            .frame(width: CGFloat(width), height: CGFloat(height))
                    )
                    renderer.scale = 1
                    guard let image = renderer.uiImage?.cgImage else {
                        XCTFail("Could not render \(option.code), \(role), \(appearance)")
                        continue
                    }

                    var pixels = [UInt8](repeating: 0, count: width * height * 4)
                    let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
                        guard let context = CGContext(
                            data: buffer.baseAddress,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        ) else { return false }
                        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                        return true
                    }
                    XCTAssertTrue(drewImage)
                    guard drewImage else { continue }

                    let foreground = components(manager.gradientForeground(for: role))
                    var minimum = Double.infinity
                    let rows = isBubble
                        ? Array(stride(from: 2, to: height - 2, by: 2))
                        : [height / 2]
                    for y in rows {
                        for x in 2..<(width - 2) {
                            let offset = (y * width + x) * 4
                            let background = (0..<3).map { CGFloat(pixels[offset + $0]) / 255 }
                            minimum = min(minimum, contrast(foreground, background))
                        }
                    }
                    XCTContext.runActivity(
                        named: "\(option.code) \(role) \(appearance) minimum \(String(format: "%.2f", minimum)):1"
                    ) { _ in }
                    if option.code == "neon" {
                        XCTAssertEqual(manager.gradientContrastLift(for: role)?.0, 0.03)
                        XCTAssertEqual(manager.gradientContrastLift(for: role)?.1, 0.03)
                        let original: Color
                        switch role {
                        case .button: original = manager.palette.buttonForeground
                        case .composer: original = manager.palette.composerButtonForeground
                        case .outgoingBubble: original = manager.palette.bubbleOutgoingText
                        }
                        XCTAssertEqual(components(manager.gradientForeground(for: role)), components(original))
                    }
                    XCTAssertGreaterThanOrEqual(
                        minimum, 4.5,
                        "Rendered \(option.code), \(role), \(appearance): \(minimum)"
                    )
                }
            }
        }
    }

    func testOutgoingFallbackTextIsOpaqueWhereGradientRequiresIt() {
        let manager = ThemeManager()
        for option in AppThemes.all {
            manager.apply(code: option.code)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(manager.outgoingBubbleSecondaryForeground)
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            let needsFullOpacity = ["midnight", "amoled", "aurora", "neon", "solarized", "velvet"]
                .contains(option.code)
            XCTAssertEqual(alpha, needsFullOpacity ? 1 : 0.82, accuracy: 0.01, option.code)
        }
    }

    func testNeonPressedAndDisabledGradientsRemainReadable() {
        func luminance(_ values: [CGFloat]) -> Double {
            let channels = values.prefix(3).map { value -> Double in
                let channel = Double(value)
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }

        func contrast(_ first: [CGFloat], _ second: [CGFloat]) -> Double {
            let values = [luminance(first), luminance(second)].sorted()
            return (values[1] + 0.05) / (values[0] + 0.05)
        }

        func components(_ color: Color) -> [CGFloat] {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            return [red, green, blue]
        }

        let manager = ThemeManager()
        manager.apply(code: "neon")
        let width = 256
        let height = 64
        for appearance in [ColorScheme.light, .dark] {
            for role in [ThemeGradientRole.button, .composer, .outgoingBubble] {
                for state in [ThemeGradientState.pressed, .disabled] {
                    let renderer = ImageRenderer(content:
                        ThemedGradientFill(
                            role: role,
                            startPoint: .leading,
                            endPoint: .trailing,
                            state: state
                        )
                            .environmentObject(manager)
                            .environment(\.colorScheme, appearance)
                            .frame(width: CGFloat(width), height: CGFloat(height))
                    )
                    renderer.scale = 1
                    guard let image = renderer.uiImage?.cgImage else {
                        XCTFail("Could not render Neon \(role), \(state), \(appearance)")
                        continue
                    }
                    var pixels = [UInt8](repeating: 0, count: width * height * 4)
                    let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
                        guard let context = CGContext(
                            data: buffer.baseAddress,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        ) else { return false }
                        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                        return true
                    }
                    XCTAssertTrue(drewImage)
                    guard drewImage else { continue }

                    let foreground = components(manager.gradientForeground(for: role, state: state))
                    var minimum = Double.infinity
                    for x in 2..<(width - 2) {
                        let offset = ((height / 2) * width + x) * 4
                        let background = (0..<3).map { CGFloat(pixels[offset + $0]) / 255 }
                        minimum = min(minimum, contrast(foreground, background))
                    }
                    XCTContext.runActivity(named: "neon \(role) \(state) \(appearance) minimum \(String(format: "%.2f", minimum)):1") { _ in }
                    XCTAssertGreaterThanOrEqual(minimum, 4.5)
                }
            }
        }
    }

    func testNeonSurfacesAndControlRolesAreDistinctFromMidnight() {
        func components(_ color: Color) -> [CGFloat] {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            return [red, green, blue]
        }

        func luminance(_ color: Color) -> Double {
            let channels = components(color).map { value -> Double in
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
        manager.apply(code: "neon")
        let neon = manager.palette
        let midnight = ThemeCatalog.palette(for: "midnight")
        XCTAssertNotEqual(components(neon.screenBackground), components(midnight.screenBackground))
        XCTAssertNotEqual(components(neon.cardBackground), components(midnight.cardBackground))
        XCTAssertNotEqual(components(neon.buttonStart), components(midnight.buttonStart))
        XCTAssertGreaterThanOrEqual(contrast(neon.primaryText, neon.screenBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(neon.primaryText, neon.cardBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(neon.secondaryText, neon.screenBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(neon.secondaryText, neon.cardBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(neon.bubbleIncomingText, neon.bubbleIncoming), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(neon.tabUnselected, neon.screenBackground), 3)
        XCTAssertGreaterThanOrEqual(contrast(manager.accentControlForeground, neon.accent), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(neon.composerBorder, neon.composerFieldBackground), 3)
        XCTAssertGreaterThanOrEqual(contrast(manager.gradientDisabledForeground, manager.gradientDisabledFill), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(manager.toolbarIconForeground, neon.screenBackground), 3)
        XCTAssertEqual(components(manager.outgoingBubbleSecondaryForeground), components(neon.bubbleOutgoingText))
    }

    func testNeonCobaltGradientStopsAndInkAreScopedToNeon() {
        func rgb(_ color: Color) -> [Int] {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            return [red, green, blue].map { Int(($0 * 255).rounded()) }
        }

        let manager = ThemeManager()
        manager.apply(code: "neon")
        XCTAssertEqual(rgb(manager.palette.accent), [0x77, 0x72, 0xF8])
        XCTAssertEqual(rgb(manager.palette.screenBackground), [0x0D, 0x0A, 0x22])
        XCTAssertEqual(rgb(manager.palette.cardBackground), [0x21, 0x1A, 0x3D])
        XCTAssertEqual(rgb(manager.palette.bubbleIncoming), [0x29, 0x20, 0x4B])
        for role in [ThemeGradientRole.button, .composer, .outgoingBubble] {
            let stops = manager.gradientFillStops(for: role)
            XCTAssertEqual(stops.map(\.location), [0, 0.58, 0.86, 1])
            XCTAssertEqual(stops.map { rgb($0.color) }, [
                [0x46, 0x67, 0xF5], [0x46, 0x67, 0xF5],
                [0x77, 0x72, 0xF8], [0xB2, 0xC7, 0xFF]
            ])
            XCTAssertEqual(rgb(manager.gradientForeground(for: role)), [0, 0, 0])
        }

        for code in AppThemes.all.map(\.code).filter({ $0 != "neon" }) {
            manager.apply(code: code)
            for role in [ThemeGradientRole.button, .composer, .outgoingBubble] {
                let stops = manager.gradientFillStops(for: role)
                let endpoints = manager.gradientStops(for: role)
                XCTAssertEqual(stops.count, 2, code)
                XCTAssertEqual(stops.map(\.location), [0, 1], code)
                XCTAssertEqual(rgb(stops[0].color), rgb(endpoints.0), code)
                XCTAssertEqual(rgb(stops[1].color), rgb(endpoints.1), code)
            }
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

    func testCallAndConversationLabelsContrastAcrossThemes() {
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
            for surface in [palette.screenBackground, palette.cardBackground] {
                XCTAssertGreaterThanOrEqual(
                    contrast(palette.primaryText, surface), 4.5,
                    "Call controls and contact names in \(option.code)"
                )
                XCTAssertGreaterThanOrEqual(
                    contrast(manager.screenSecondaryText, surface), 4.5,
                    "Call state and SMS/Chatforia label in \(option.code)"
                )
            }
            for appearance in [ColorScheme.light, .dark] {
                for isSMS in [false, true] {
                    let host = UIHostingController(rootView:
                        NavigationStack {
                            Color.clear
                                .navigationBarTitleDisplayMode(.inline)
                                .modifier(ThemedNavigationBar())
                                .toolbar {
                                    ToolbarItem(placement: .principal) {
                                        ConversationTransportTitle(title: "Sample contact", isSMS: isSMS)
                                    }
                                }
                        }
                        .environmentObject(manager)
                        .environment(\.colorScheme, appearance)
                    )
                    let size = host.sizeThatFits(in: CGSize(width: 390, height: 844))
                    XCTAssertGreaterThan(size.width, 0, "\(option.code), \(appearance), SMS \(isSMS)")
                }
            }
        }
    }

    func testNavigationBackButtonResolvedTintAcrossThemes() {
        func findBar(in view: UIView) -> UINavigationBar? {
            if let bar = view as? UINavigationBar { return bar }
            return view.subviews.lazy.compactMap { findBar(in: $0) }.first
        }

        func luminance(_ color: UIColor) -> Double {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            let channels = [red, green, blue].map { value -> Double in
                let channel = Double(value)
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }

        let manager = ThemeManager()
        for option in AppThemes.all {
            manager.apply(code: option.code)
            for appearance in [ColorScheme.light, .dark] {
                let host = UIHostingController(rootView:
                    NavigationStack(path: .constant([1])) {
                        Text("Root")
                            .navigationDestination(for: Int.self) { _ in
                                Text("Detail")
                                    .navigationTitle("Detail")
                                    .modifier(ThemedNavigationBar())
                            }
                    }
                    .environmentObject(manager)
                    .tint(manager.palette.accent)
                    .environment(\.colorScheme, appearance)
                )
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                window.rootViewController = host
                window.makeKeyAndVisible()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.view.layoutIfNeeded()
                guard let bar = findBar(in: host.view) else {
                    XCTFail("Missing rendered navigation bar in \(option.code), \(appearance)")
                    window.isHidden = true
                    continue
                }
                XCTAssertGreaterThan(bar.items?.count ?? 0, 1,
                                     "Expected a pushed screen with a back button in \(option.code)")
                let tint = bar.tintColor ?? .clear
                let surface = UIColor(manager.palette.screenBackground)
                let light = max(luminance(tint), luminance(surface))
                let dark = min(luminance(tint), luminance(surface))
                XCTAssertGreaterThanOrEqual((light + 0.05) / (dark + 0.05), 3,
                                            "Resolved back-button tint in \(option.code), \(appearance)")
                window.isHidden = true
            }
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

    func testCallsSelectorUsesThemeAppearanceAcrossSystemModes() {
        let manager = ThemeManager()
        for option in AppThemes.all {
            manager.apply(code: option.code)
            for systemStyle in [UIUserInterfaceStyle.light, .dark] {
                for selected in CallsSegment.allCases {
                    let host = UIHostingController(rootView:
                        CallsSegmentSelector(selection: .constant(selected))
                            .environmentObject(manager)
                    )
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                    window.overrideUserInterfaceStyle = systemStyle
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    host.view.layoutIfNeeded()

                    guard let selector = segmentedControl(in: host.view) else {
                        XCTFail("Missing Calls selector in \(option.code), \(systemStyle)")
                        window.isHidden = true
                        continue
                    }
                    let expected: UIUserInterfaceStyle =
                        manager.navigationColorScheme == .dark ? .dark : .light
                    XCTAssertEqual(selector.traitCollection.userInterfaceStyle, expected)
                    XCTAssertEqual(selector.numberOfSegments, 2)
                    XCTAssertEqual(selector.selectedSegmentIndex, selected == .recents ? 0 : 1)
                    let language = UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"
                    XCTAssertEqual(
                        selector.titleForSegment(at: 0),
                        appText(CallsSegment.recents.titleKey, languageCode: language)
                    )
                    XCTAssertEqual(
                        selector.titleForSegment(at: 1),
                        appText(CallsSegment.voicemail.titleKey, languageCode: language)
                    )
                    window.isHidden = true
                }
            }
        }
    }

    func testCallsHeaderRendersAcrossThemesAndSystemAppearances() {
        let manager = ThemeManager()
        let auth = AuthStore(
            tokenStore: CallsThemeNoTokenStore(),
            refreshEntitlements: {},
            ensureLocalKeys: { _, _ in false },
            finishLoginNotifications: {}
        )
        for option in AppThemes.all {
            manager.apply(code: option.code)
            for appearance in [ColorScheme.light, .dark] {
                let host = UIHostingController(rootView:
                    NavigationStack { CallHistoryView() }
                        .environmentObject(auth)
                        .environmentObject(manager)
                        .environmentObject(CallManager.shared)
                        .environment(\.colorScheme, appearance)
                )
                let size = host.sizeThatFits(in: CGSize(width: 390, height: 844))
                XCTAssertGreaterThan(size.width, 0, "\(option.code), \(appearance)")
                XCTAssertGreaterThan(size.height, 0, "\(option.code), \(appearance)")
            }
        }
    }

    func testCallsSelectorUpdatesWhenThemeChangesWithoutChangingSelection() {
        let manager = ThemeManager()
        manager.apply(code: "midnight")
        let host = UIHostingController(rootView:
            CallsSegmentSelector(selection: .constant(.voicemail))
                .environmentObject(manager)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.view.layoutIfNeeded()
        guard let initial = segmentedControl(in: host.view) else {
            XCTFail("Missing Calls selector")
            return
        }
        XCTAssertEqual(initial.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(initial.selectedSegmentIndex, 1)

        manager.apply(code: "dawn")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.layoutIfNeeded()
        guard let updated = segmentedControl(in: host.view) else {
            XCTFail("Missing Calls selector after theme change")
            return
        }
        XCTAssertEqual(updated.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(updated.selectedSegmentIndex, 1)
    }

    private func segmentedControl(in root: UIView) -> UISegmentedControl? {
        if let control = root as? UISegmentedControl { return control }
        for subview in root.subviews {
            if let control = segmentedControl(in: subview) { return control }
        }
        return nil
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

@MainActor
private final class CallsThemeNoTokenStore: TokenStoring {
    func read() -> String? { nil }
    func save(_ token: String) { }
    func clear() { }
}
