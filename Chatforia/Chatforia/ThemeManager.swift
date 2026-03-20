import SwiftUI
import Combine

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
                accent: Color(hex: "#3CF9FF"),
                titleAccent: Color(hex: "#EAF2FF"),

                screenBackground: Color(hex: "#060A16"),
                cardBackground: Color(hex: "#0E1426"),
                border: Color(hex: "#1A2540"),

                primaryText: Color(hex: "#EAF2FF"),
                secondaryText: Color(hex: "#9FB3D1"),

                buttonStart: Color(hex: "#3CF9FF"),
                buttonEnd: Color(hex: "#7C3AED"),
                buttonForeground: .white,

                bubbleOutgoingStart: Color(hex: "#3CF9FF"),
                bubbleOutgoingEnd: Color(hex: "#6A3CC1"),
                bubbleOutgoingText: .white,

                bubbleIncoming: Color(hex: "#18243A"),
                bubbleIncomingText: Color(hex: "#EAF2FF"),

                composerBackground: Color(hex: "#060A16"),
                composerFieldBackground: Color(hex: "#0F141D"),
                composerBorder: Color(hex: "#171821"),
                composerButtonStart: Color(hex: "#3CF9FF"),
                composerButtonEnd: Color(hex: "#7C3AED"),
                composerButtonForeground: .white,

                tabSelected: Color(hex: "#3CF9FF"),
                tabUnselected: Color(hex: "#7487A8"),

                highlightedSurface: Color(hex: "#22344C")
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
    @Published var currentCode: String = "dawn"

    var palette: AppThemePalette {
        ThemeCatalog.palette(for: currentCode)
    }

    func apply(code: String) {
        currentCode = code.lowercased()
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
