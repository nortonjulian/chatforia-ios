import Foundation

enum AdMobConfig {
    static let appID = "ca-app-pub-8163977681153105~6952662011"

    #if DEBUG
    static let bannerHomeAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let interstitialChatOpenAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    static let bannerHomeAdUnitID = "ca-app-pub-8163977681153105/3009547579"
    static let interstitialChatOpenAdUnitID = "ca-app-pub-8163977681153105/6651233511"
    #endif
}
