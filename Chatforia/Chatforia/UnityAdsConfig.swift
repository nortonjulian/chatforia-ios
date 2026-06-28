import Foundation

enum UnityAdsConfig {
    static let gameID = "800077391"
    static let bannerPlacementID = "Banner_iOS"
    static let interstitialPlacementID = "Interstitial_iOS"

    #if DEBUG
    static let testMode = true
    #else
    static let testMode = false
    #endif
}
