import Foundation
import UnityAds

final class UnityAdsManager: NSObject, UnityAdsInitializationDelegate {
    static let shared = UnityAdsManager()

    private(set) var initialized = false
    private var initializing = false

    private override init() {
        super.init()
    }

    func start() {
        guard !initialized, !initializing else { return }

        initializing = true

        UnityAds.initialize(
            UnityAdsConfig.gameID,
            testMode: UnityAdsConfig.testMode,
            initializationDelegate: self
        )
    }

    func initializationComplete() {
        initialized = true
        initializing = false
    }

    func initializationFailed(_ error: UnityAdsInitializationError, withMessage message: String) {
        initialized = false
        initializing = false
    }
}
