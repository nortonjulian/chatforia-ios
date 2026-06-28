import Foundation
import UnityAds
import UIKit

@MainActor
final class UnityInterstitialAdManager: NSObject, UnityAdsLoadDelegate, UnityAdsShowDelegate {
    static let shared = UnityInterstitialAdManager()

    private var loaded = false
    private var isLoading = false
    private var showing = false

    private var openCount = 0
    private let showEveryNOpenings = 4

    private override init() {
        super.init()
    }

    func preloadIfNeeded() {
        guard UnityAdsManager.shared.initialized else {
            UnityAdsManager.shared.start()
            return
        }

        guard !loaded, !isLoading else { return }

        isLoading = true

        UnityAds.load(
            UnityAdsConfig.interstitialPlacementID,
            loadDelegate: self
        )
    }

    func recordChatOpenAndMaybeShow() {
        openCount += 1

        guard openCount % showEveryNOpenings == 0 else { return }

        showIfReady()
    }

    func showIfReady() {
        guard !showing else { return }

        guard loaded else {
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

        UnityAds.show(
            root,
            placementId: UnityAdsConfig.interstitialPlacementID,
            showDelegate: self
        )
    }

    func unityAdsAdLoaded(_ placementId: String) {
        isLoading = false
        loaded = true
        print("✅ Unity interstitial loaded")
    }

    func unityAdsAdFailed(
        toLoad placementId: String,
        withError error: UnityAdsLoadError,
        withMessage message: String
    ) {
        isLoading = false
        loaded = false
        print("❌ Unity interstitial failed to load: \(message)")
    }

    func unityAdsShowComplete(
        _ placementId: String,
        withFinish state: UnityAdsShowCompletionState
    ) {
        showing = false
        loaded = false
        preloadIfNeeded()
    }

    func unityAdsShowFailed(
        _ placementId: String,
        withError error: UnityAdsShowError,
        withMessage message: String
    ) {
        showing = false
        loaded = false
        print("❌ Unity interstitial show failed: \(message)")
        preloadIfNeeded()
    }

    func unityAdsShowStart(_ placementId: String) {}
    func unityAdsShowClick(_ placementId: String) {}
}
