import SwiftUI
import Combine
import UIKit

struct AppThemePalette {
    let accent: Color
    let titleAccent: Color

    let screenBackground: Color
    let cardBackground: Color
    let border: Color

    let primaryText: Color
    let secondaryText: Color

    let buttonStart: Color
    let buttonEnd: Color
    let buttonForeground: Color

    let bubbleOutgoingStart: Color
    let bubbleOutgoingEnd: Color
    let bubbleOutgoingText: Color

    let bubbleIncoming: Color
    let bubbleIncomingText: Color

    let composerBackground: Color
    let composerFieldBackground: Color
    let composerBorder: Color
    let composerButtonStart: Color
    let composerButtonEnd: Color
    let composerButtonForeground: Color

    let tabSelected: Color
    let tabUnselected: Color

    let highlightedSurface: Color
}

enum ThemeGradientRole: Equatable {
    case button
    case composer
    case outgoingBubble
}

enum ThemeGradientState: Equatable {
    case normal
    case pressed
    case disabled
}

private struct ThemeGradientPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var themeGradientPressed: Bool {
        get { self[ThemeGradientPressedKey.self] }
        set { self[ThemeGradientPressedKey.self] = newValue }
    }
}

/// Keeps the existing plain-button appearance outside Neon.
struct ThemedGradientButtonStyle: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    var plainFallback = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if themeManager.currentCode == "neon" {
            content.buttonStyle(NeonGradientPressStyle())
        } else if plainFallback {
            content.buttonStyle(.plain)
        } else {
            content
        }
    }
}

private struct NeonGradientPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.themeGradientPressed, configuration.isPressed)
    }
}

struct ThemedGradientForeground: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.isEnabled) private var isEnabled
    let role: ThemeGradientRole

    func body(content: Content) -> some View {
        content.foregroundStyle(
            themeManager.gradientForeground(
                for: role,
                state: isEnabled ? .normal : .disabled
            )
        )
    }
}

/// Uses the theme's stops and applies a shape-clipped contrast lift where needed.
struct ThemedGradientFill: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeGradientPressed) private var isPressed
    let role: ThemeGradientRole
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    var state: ThemeGradientState = .normal

    private var resolvedState: ThemeGradientState {
        guard themeManager.currentCode == "neon" else { return .normal }
        if state == .disabled || !isEnabled { return .disabled }
        if state == .pressed || isPressed { return .pressed }
        return .normal
    }

    @ViewBuilder
    var body: some View {
        if resolvedState == .disabled {
            themeManager.gradientDisabledFill
        } else {
            LinearGradient(stops: themeManager.gradientFillStops(for: role), startPoint: startPoint, endPoint: endPoint)
                .overlay {
                    if resolvedState == .pressed {
                        Color.white.opacity(0.06)
                    } else if let lift = themeManager.gradientContrastLift(for: role) {
                        LinearGradient(
                            colors: [.white.opacity(lift.0), .white.opacity(lift.1)],
                            startPoint: startPoint,
                            endPoint: endPoint
                        )
                    }
                }
        }
    }
}

enum ThemeCatalog {
    static func palette(for code: String) -> AppThemePalette {
        switch code.lowercased() {
        case "dawn":
            return .init(
                accent: Color(hex: "#FFB300"),
                titleAccent: Color(hex: "#B56E00"),

                screenBackground: Color(hex: "#FFF7F0"),
                cardBackground: Color(hex: "#FFFFFF"),
                border: Color(hex: "#F1E3D8"),

                primaryText: Color(hex: "#241510"),
                secondaryText: Color(hex: "#745E53"),

                buttonStart: Color(hex: "#FFB300"),
                buttonEnd: Color(hex: "#FF9800"),
                buttonForeground: Color(hex: "#2B1712"),

                bubbleOutgoingStart: Color(hex: "#FFB300"),
                bubbleOutgoingEnd: Color(hex: "#FF9800"),
                bubbleOutgoingText: Color(hex: "#2B1712"),

                bubbleIncoming: Color(hex: "#FFFFFF"),
                bubbleIncomingText: Color(hex: "#241510"),

                composerBackground: Color(hex: "#FFF7F0"),
                composerFieldBackground: Color(hex: "#FFFFFF"),
                composerBorder: Color(hex: "#F1E3D8"),
                composerButtonStart: Color(hex: "#FFB300"),
                composerButtonEnd: Color(hex: "#FF9800"),
                composerButtonForeground: Color(hex: "#2B1712"),

                tabSelected: Color(hex: "#FFB300"),
                tabUnselected: Color(hex: "#A78B7A"),

                highlightedSurface: Color(hex: "#FFF4D0")
            )

        case "midnight", "moon":
            return .init(
                accent: Color(hex: "#3CF9FF"),
                titleAccent: Color(hex: "#EEF2FF"),

                screenBackground: Color(hex: "#050B1A"),
                cardBackground: Color(hex: "#0E1630"),
                border: Color(hex: "#1B2A49"),

                primaryText: Color(hex: "#EEF2FF"),
                secondaryText: Color(hex: "#A3AED0"),

                buttonStart: Color(hex: "#6A3CC1"),
                buttonEnd: Color(hex: "#00C2A8"),
                buttonForeground: .white,

                bubbleOutgoingStart: Color(hex: "#6A3CC1"),
                bubbleOutgoingEnd: Color(hex: "#00C2A8"),
                bubbleOutgoingText: .white,

                bubbleIncoming: Color(hex: "#121933"),
                bubbleIncomingText: Color(hex: "#EEF2FF"),

                composerBackground: Color(hex: "#050B1A"),
                composerFieldBackground: Color(hex: "#121933"),
                composerBorder: Color(hex: "#1E2747"),
                composerButtonStart: Color(hex: "#3CF9FF"),
                composerButtonEnd: Color(hex: "#6A3CC1"),
                composerButtonForeground: .white,

                tabSelected: Color(hex: "#3CF9FF"),
                tabUnselected: Color(hex: "#6E7D9C"),

                highlightedSurface: Color(hex: "#22344C")
            )

        case "amoled":
            return .init(
                accent: Color(hex: "#7C3AED"),
                titleAccent: Color(hex: "#F2F2F2"),

                screenBackground: .black,
                cardBackground: Color(hex: "#0A0A0A"),
                border: Color(hex: "#141414"),

                primaryText: Color(hex: "#F2F2F2"),
                secondaryText: Color(hex: "#A3A3A3"),

                buttonStart: Color(hex: "#7C3AED"),
                buttonEnd: Color(hex: "#5932C7"),
                buttonForeground: .white,

                bubbleOutgoingStart: Color(hex: "#7C3AED"),
                bubbleOutgoingEnd: Color(hex: "#5932C7"),
                bubbleOutgoingText: .white,

                bubbleIncoming: Color(hex: "#111111"),
                bubbleIncomingText: Color(hex: "#F2F2F2"),

                composerBackground: .black,
                composerFieldBackground: Color(hex: "#0F0F0F"),
                composerBorder: Color(hex: "#1A1A1A"),
                composerButtonStart: Color(hex: "#7C3AED"),
                composerButtonEnd: Color(hex: "#5932C7"),
                composerButtonForeground: .white,

                tabSelected: Color(hex: "#7C3AED"),
                tabUnselected: Color(hex: "#6B7280"),

                highlightedSurface: Color(hex: "#171717")
            )

        case "aurora":
            return .init(
                accent: Color(hex: "#29D39A"),
                titleAccent: Color(hex: "#E9FFF8"),

                screenBackground: Color(hex: "#03161B"),
                cardBackground: Color(hex: "#08252B"),
                border: Color(hex: "#123841"),

                primaryText: Color(hex: "#E9FFF8"),
                secondaryText: Color(hex: "#A8D8D1"),

                buttonStart: Color(hex: "#00C2A8"),
                buttonEnd: Color(hex: "#29D39A"),
                buttonForeground: .white,

                bubbleOutgoingStart: Color(hex: "#29D39A"),
                bubbleOutgoingEnd: Color(hex: "#2979FF"),
                bubbleOutgoingText: .white,

                bubbleIncoming: Color(hex: "#143B4A"),
                bubbleIncomingText: Color(hex: "#E9FFF8"),

                composerBackground: Color(hex: "#03161B"),
                composerFieldBackground: Color(hex: "#0B2323"),
                composerBorder: Color(hex: "#123131"),
                composerButtonStart: Color(hex: "#00C2A8"),
                composerButtonEnd: Color(hex: "#29D39A"),
                composerButtonForeground: .white,

                tabSelected: Color(hex: "#29D39A"),
                tabUnselected: Color(hex: "#7AAEA6"),

                highlightedSurface: Color(hex: "#213F52")
            )

        case "neon":
            return .init(
                accent: Color(hex: "#7772F8"),
                titleAccent: Color(hex: "#F4F1FF"),

                screenBackground: Color(hex: "#0D0A22"),
                cardBackground: Color(hex: "#211A3D"),
                border: Color(hex: "#4A3C70"),

                primaryText: Color(hex: "#F4F1FF"),
                secondaryText: Color(hex: "#B9B2D5"),

                buttonStart: Color(hex: "#4667F5"),
                buttonEnd: Color(hex: "#B2C7FF"),
                buttonForeground: .black,

                bubbleOutgoingStart: Color(hex: "#4667F5"),
                bubbleOutgoingEnd: Color(hex: "#B2C7FF"),
                bubbleOutgoingText: .black,

                bubbleIncoming: Color(hex: "#29204B"),
                bubbleIncomingText: Color(hex: "#F4F1FF"),

                composerBackground: Color(hex: "#0D0A22"),
                composerFieldBackground: Color(hex: "#241D42"),
                composerBorder: Color(hex: "#756BA5"),
                composerButtonStart: Color(hex: "#4667F5"),
                composerButtonEnd: Color(hex: "#B2C7FF"),
                composerButtonForeground: .black,

                tabSelected: Color(hex: "#7772F8"),
                tabUnselected: Color(hex: "#AAA3C4"),

                highlightedSurface: Color(hex: "#322957")
            )

        case "sunset":
            return .init(
                accent: Color(hex: "#FF9800"),
                titleAccent: Color(hex: "#C65D52"),

                screenBackground: Color(hex: "#F7E8DE"),
                cardBackground: Color(hex: "#F1DFD2"),
                border: Color(hex: "#D9C4B5"),

                primaryText: Color(hex: "#2C1A10"),
                secondaryText: Color(hex: "#7B6152"),

                buttonStart: Color(hex: "#FF9800"),
                buttonEnd: Color(hex: "#FF6F61"),
                buttonForeground: Color(hex: "#22160E"),

                bubbleOutgoingStart: Color(hex: "#FF9A76"),
                bubbleOutgoingEnd: Color(hex: "#FF9800"),
                bubbleOutgoingText: Color(hex: "#22160E"),

                bubbleIncoming: Color(hex: "#EFE1D7"),
                bubbleIncomingText: Color(hex: "#2C1A10"),

                composerBackground: Color(hex: "#F7E8DE"),
                composerFieldBackground: Color(hex: "#FFF7F3"),
                composerBorder: Color(hex: "#E2CDBF"),
                composerButtonStart: Color(hex: "#FF9800"),
                composerButtonEnd: Color(hex: "#FF6F61"),
                composerButtonForeground: .white,

                tabSelected: Color(hex: "#FF9800"),
                tabUnselected: Color(hex: "#B08B7A"),

                highlightedSurface: Color(hex: "#DDD7D5")
            )

        case "solarized":
            return .init(
                accent: Color(hex: "#B58900"),
                titleAccent: Color(hex: "#0B4251"),

                screenBackground: Color(hex: "#EEE8D5"),
                cardBackground: Color(hex: "#E8E3D0"),
                border: Color(hex: "#D6CFB9"),

                primaryText: Color(hex: "#073642"),
                secondaryText: Color(hex: "#657B83"),

                buttonStart: Color(hex: "#B58900"),
                buttonEnd: Color(hex: "#CB4B16"),
                buttonForeground: Color(hex: "#1B1200"),

                bubbleOutgoingStart: Color(hex: "#B58900"),
                bubbleOutgoingEnd: Color(hex: "#CB4B16"),
                bubbleOutgoingText: Color(hex: "#1B1200"),

                bubbleIncoming: Color(hex: "#F5F0DF"),
                bubbleIncomingText: Color(hex: "#073642"),

                composerBackground: Color(hex: "#EEE8D5"),
                composerFieldBackground: Color(hex: "#FDF6E3"),
                composerBorder: Color(hex: "#D6CFB9"),
                composerButtonStart: Color(hex: "#B58900"),
                composerButtonEnd: Color(hex: "#CB4B16"),
                composerButtonForeground: Color(hex: "#1B1200"),

                tabSelected: Color(hex: "#B58900"),
                tabUnselected: Color(hex: "#8B8B7A"),

                highlightedSurface: Color(hex: "#DDE1D6")
            )

        case "velvet":
            return .init(
                accent: Color(hex: "#FF2D7A"),
                titleAccent: Color(hex: "#FFF3FA"),

                screenBackground: Color(hex: "#17071C"),
                cardBackground: Color(hex: "#241031"),
                border: Color(hex: "#3B1A46"),

                primaryText: Color(hex: "#FFF3FA"),
                secondaryText: Color(hex: "#DAB5CB"),

                buttonStart: Color(hex: "#FF2D7A"),
                buttonEnd: Color(hex: "#FFD84D"),
                buttonForeground: .white,

                bubbleOutgoingStart: Color(hex: "#FF2D7A"),
                bubbleOutgoingEnd: Color(hex: "#FFD84D"),
                bubbleOutgoingText: .white,

                bubbleIncoming: Color(hex: "#2B1736"),
                bubbleIncomingText: Color(hex: "#FFF3FA"),

                composerBackground: Color(hex: "#17071C"),
                composerFieldBackground: Color(hex: "#1F0D26"),
                composerBorder: Color(hex: "#2B1331"),
                composerButtonStart: Color(hex: "#FF2D7A"),
                composerButtonEnd: Color(hex: "#FFD84D"),
                composerButtonForeground: .white,

                tabSelected: Color(hex: "#FF2D7A"),
                tabUnselected: Color(hex: "#A26D95"),

                highlightedSurface: Color(hex: "#29324F")
            )

        default:
            return palette(for: "dawn")
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    private let storageKey = "chatforia.theme"

    @Published private(set) var currentCode: String

    init() {
        self.currentCode = "dawn"
    }

    var palette: AppThemePalette {
        ThemeCatalog.palette(for: currentCode)
    }

    // Keep routine actions legible on the selected theme rather than relying
    // on the device appearance or assuming the accent works on every surface.
    var toolbarIconForeground: Color {
        ThemeContrast.ratio(palette.accent, palette.screenBackground) >= 3
            ? palette.accent : palette.primaryText
    }

    var toolbarTextForeground: Color {
        ThemeContrast.ratio(palette.accent, palette.screenBackground) >= 4.5
            ? palette.accent : palette.primaryText
    }

    var accentControlForeground: Color {
        controlForeground(on: palette.accent, preferred: palette.buttonForeground)
    }

    func gradientStops(for role: ThemeGradientRole) -> (Color, Color) {
        switch role {
        case .button: (palette.buttonStart, palette.buttonEnd)
        case .composer: (palette.composerButtonStart, palette.composerButtonEnd)
        case .outgoingBubble: (palette.bubbleOutgoingStart, palette.bubbleOutgoingEnd)
        }
    }

    func gradientFillStops(for role: ThemeGradientRole) -> [Gradient.Stop] {
        let endpoints = gradientStops(for: role)
        guard currentCode == "neon" else {
            return [.init(color: endpoints.0, location: 0), .init(color: endpoints.1, location: 1)]
        }
        // Keep cobalt dominant, then move briefly through ultraviolet to icy blue.
        return [
            .init(color: endpoints.0, location: 0),
            .init(color: endpoints.0, location: 0.58),
            .init(color: Color(hex: "#7772F8"), location: 0.86),
            .init(color: endpoints.1, location: 1)
        ]
    }

    func gradientForeground(for role: ThemeGradientRole) -> Color {
        switch currentCode {
        case "midnight", "aurora", "velvet": palette.screenBackground
        case "solarized": .black
        case "sunset" where role == .composer: palette.buttonForeground
        default:
            switch role {
            case .button: palette.buttonForeground
            case .composer: palette.composerButtonForeground
            case .outgoingBubble: palette.bubbleOutgoingText
            }
        }
    }

    // Transparent at the safe stop. Neon's small uniform lift compensates for
    // rendered color rounding at its exact cobalt stop.
    func gradientContrastLift(for role: ThemeGradientRole) -> (Double, Double)? {
        switch currentCode {
        case "midnight":
            return role == .composer ? (0, 0.25) : (0.25, 0)
        case "solarized": return (0, 0.05)
        case "neon": return (0.03, 0.03)
        default: return nil
        }
    }

    var outgoingBubbleSecondaryForeground: Color {
        switch currentCode {
        case "midnight", "amoled", "aurora", "neon", "solarized", "velvet":
            gradientForeground(for: .outgoingBubble)
        default:
            palette.bubbleOutgoingText.opacity(0.82)
        }
    }

    var gradientDisabledFill: Color {
        currentCode == "neon" ? Color(hex: "#302A4A") : palette.buttonStart
    }

    var gradientDisabledForeground: Color {
        currentCode == "neon" ? Color(hex: "#AFA7CA") : palette.buttonForeground
    }

    func gradientForeground(for role: ThemeGradientRole, state: ThemeGradientState) -> Color {
        currentCode == "neon" && state == .disabled
            ? gradientDisabledForeground : gradientForeground(for: role)
    }

    func controlForeground(on fill: Color, preferred: Color) -> Color {
        if ThemeContrast.ratio(preferred, fill) >= 3 { return preferred }
        return ThemeContrast.ratio(palette.screenBackground, fill) >= 3
            ? palette.screenBackground : palette.primaryText
    }

    func accessoryForeground(on surface: Color) -> Color {
        ThemeContrast.ratio(palette.accent, surface) >= 3
            ? palette.accent : palette.primaryText
    }

    // Sunset and Solarized secondary text is suitable for icons but too faint
    // for a search placeholder on their card surfaces. Reuse primary text there.
    var searchHintText: Color {
        switch currentCode {
        case "sunset", "solarized": palette.primaryText
        default: palette.secondaryText
        }
    }

    // Secondary labels on the full-screen call and conversation surfaces.
    // Sunset and Solarized secondary colors are too faint on the card surface.
    var screenSecondaryText: Color {
        switch currentCode {
        case "sunset", "solarized": palette.primaryText
        default: palette.secondaryText
        }
    }

    // Navigation titles use system foregrounds, so match their appearance to
    // the app palette even when the device's appearance differs.
    var navigationColorScheme: ColorScheme {
        switch currentCode {
        case "midnight", "amoled", "aurora", "neon", "velvet": .dark
        default: .light
        }
    }

    func apply(code: String) {
        let normalized = Self.normalize(code)
        currentCode = normalized
        UserDefaults.standard.set(normalized, forKey: storageKey)
    }

    private static func normalize(_ code: String) -> String {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = ["dawn", "midnight", "amoled", "aurora", "neon", "sunset", "solarized", "velvet"]
        return allowed.contains(value) ? value : "dawn"
    }
}

private enum ThemeContrast {
    static func ratio(_ first: Color, _ second: Color) -> Double {
        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }

    private static func luminance(_ color: Color) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return 0
        }
        let channels = [red, green, blue].map { value -> Double in
            let channel = Double(value)
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (
                255,
                (int >> 8) * 17,
                (int >> 4 & 0xF) * 17,
                (int & 0xF) * 17
            )
        case 6:
            (a, r, g, b) = (
                255,
                int >> 16,
                int >> 8 & 0xFF,
                int & 0xFF
            )
        case 8:
            (a, r, g, b) = (
                int >> 24,
                int >> 16 & 0xFF,
                int >> 8 & 0xFF,
                int & 0xFF
            )
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
