import SwiftUI
import UIKit
import UnityAds

struct UnityBannerAdView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UnityBannerAdViewController {
        UnityBannerAdViewController()
    }

    func updateUIViewController(_ uiViewController: UnityBannerAdViewController, context: Context) {}
}

final class UnityBannerAdViewController: UIViewController, UADSBannerViewDelegate {
    private var bannerView: UADSBannerView?

    override func viewDidLoad() {
        super.viewDidLoad()

        UnityAdsManager.shared.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.loadBanner()
        }
    }

    private func loadBanner() {
        let banner = UADSBannerView(
            placementId: UnityAdsConfig.bannerPlacementID,
            size: CGSize(width: 320, height: 50)
        )

        banner.delegate = self
        bannerView = banner

        view.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.topAnchor.constraint(equalTo: view.topAnchor),
            banner.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            banner.heightAnchor.constraint(equalToConstant: 50),
            banner.widthAnchor.constraint(equalToConstant: 320)
        ])

        banner.load()
    }

    func bannerViewDidLoad(_ bannerView: UADSBannerView!) {
        print("✅ Unity banner loaded")
    }

    func bannerViewDidError(_ bannerView: UADSBannerView!, error: UADSBannerError!) {
        print("❌ Unity banner failed:", error.localizedDescription)
    }
}
