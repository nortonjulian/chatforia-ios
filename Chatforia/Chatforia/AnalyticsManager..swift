import Foundation
import PostHog

@MainActor
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private init() {}

    func configure() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
              let host = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String else {
            print("❌ Missing PostHog config")
            return
        }

        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = true
        config.debug = true

        PostHogSDK.shared.setup(config)

        print("📊 PostHog initialized")
    }

    func identify(_ userId: Int, properties: [String: Any] = [:]) {
        PostHogSDK.shared.identify(String(userId), userProperties: properties)
    }

    func capture(_ event: String, properties: [String: Any] = [:]) {
        var merged = properties
        merged["platform"] = "ios"

        PostHogSDK.shared.capture(event, properties: merged)
    }

    func reset() {
        PostHogSDK.shared.reset()
    }
}
