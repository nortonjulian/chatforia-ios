#if DEBUG
import UIKit
import GoogleMobileAds

@MainActor
enum AdInspectorLauncher {
    static func open() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            debugLog("❌ Could not find root view controller for Ad Inspector")
            return
        }

        MobileAds.shared.presentAdInspector(from: root) { error in
            if let error {
                debugLog("❌ Ad Inspector failed to open:", error.localizedDescription)
            } else {
                debugLog("✅ Ad Inspector opened")
            }
        }
    }
}
#endif
