import Foundation
import GoogleMobileAds
import UIKit

@MainActor
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {
    static let shared = InterstitialAdManager()

    private var interstitialAd: InterstitialAd?
    private var isLoading = false
    private var showing = false

    private var openCount = 0
    private let showEveryNOpenings = 4

    private var lastShownAt: Date?
    private let minimumSecondsBetweenShows: TimeInterval = 15 * 60

    private override init() {
        super.init()
    }

    func preloadIfNeeded() {
        guard interstitialAd == nil, !isLoading else { return }

        isLoading = true

        InterstitialAd.load(
            with: AdMobConfig.interstitialChatOpenAdUnitID,
            request: Request()
        ) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }

                self.isLoading = false

                if let error {
                    debugLog("❌ AdMob interstitial failed to load:", error.localizedDescription)
                    return
                }

                self.interstitialAd = ad
                self.interstitialAd?.fullScreenContentDelegate = self

                debugLog("✅ AdMob interstitial loaded")
            }
        }
    }

    func recordChatOpenAndMaybeShow() {
        guard !showing else { return }

        openCount += 1
        preloadIfNeeded()

        guard openCount % showEveryNOpenings == 0 else { return }

        showIfReady()
    }

    func showIfReady() {
        guard !showing else { return }

        if let lastShownAt,
           Date().timeIntervalSince(lastShownAt) < minimumSecondsBetweenShows {
            preloadIfNeeded()
            return
        }

        guard let interstitialAd else {
            preloadIfNeeded()
            return
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }

        showing = true
        interstitialAd.present(from: root)
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        lastShownAt = Date()
        debugLog("📺 AdMob interstitial will present")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        showing = false
        interstitialAd = nil
        preloadIfNeeded()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        showing = false
        interstitialAd = nil
        debugLog("❌ AdMob interstitial failed to present:", error.localizedDescription)
        preloadIfNeeded()
    }
}