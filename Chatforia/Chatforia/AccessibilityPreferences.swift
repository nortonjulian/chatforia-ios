import Foundation
import SwiftUI

enum A11yFontSize: String, Codable, CaseIterable, Identifiable {
    case sm, md, lg, xl

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .sm: return "accessibility_font_sm"
        case .md: return "accessibility_font_md"
        case .lg: return "accessibility_font_lg"
        case .xl: return "accessibility_font_xl"
        }
    }

    var swiftUIFont: Font {
        switch self {
        case .sm: return .subheadline
        case .md: return .body
        case .lg: return .title3
        case .xl: return .title2
        }
    }
}

enum A11yCaptionBackground: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case transparent

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .light: return "accessibility_caption_bg_light"
        case .dark: return "accessibility_caption_bg_dark"
        case .transparent: return "accessibility_caption_bg_transparent"
        }
    }
}
