import Foundation

struct AccessibilitySettingsUpdateRequest: Encodable {
    let a11yUiFont: String?
    let a11yVisualAlerts: Bool?
    let a11yVibrate: Bool?
    let a11yFlashOnCall: Bool?
    let a11yLiveCaptions: Bool?
    let a11yVoiceNoteSTT: Bool?
    let a11yCaptionFont: String?
    let a11yCaptionBg: String?
}
