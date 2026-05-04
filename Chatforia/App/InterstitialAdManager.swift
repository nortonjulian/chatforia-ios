import Foundation
import GoogleMobileAds
import UIKit

@MainActor
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {
    static let shared = InterstitialAdManager()

    private var interstitialAd: InterstitialAd?
    private var showing = false

    private var openCount = 0
    private let showEveryNOpenings = 4

    private let testAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    override private init() {
        super.init()
    }

    func preloadIfNeeded() {
        guard interstitialAd == nil else { return }

        InterstitialAd.load(
            with: testAdUnitID,
            request: Request()
        ) { ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if error != nil {
                    return
                }

                self.interstitialAd = ad
                self.interstitialAd?.fullScreenContentDelegate = self

                #if DEBUG
                print("✅ Interstitial loaded")
                #endif
            }
        }
    }

    func recordChatOpenAndMaybeShow() {
        openCount += 1

        guard openCount % showEveryNOpenings == 0 else { return }
        showIfReady()
    }

    func showIfReady() {
        guard !showing else { return }
        guard let ad = interstitialAd else {
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
        ad.present(from: root)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        showing = false
        interstitialAd = nil
        preloadIfNeeded()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        showing = false
        interstitialAd = nil
        preloadIfNeeded()
    }
}
