import SwiftUI
import GoogleMobileAds
import UIKit

struct BannerAdView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BannerAdViewController {
        BannerAdViewController()
    }

    func updateUIViewController(_ uiViewController: BannerAdViewController, context: Context) {}
}

final class BannerAdViewController: UIViewController {
    private var bannerView: BannerView!

    override func viewDidLoad() {
        super.viewDidLoad()

        bannerView = BannerView(adSize: AdSizeBanner)
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2435281174" // iOS test banner ID
        bannerView.rootViewController = self

        view.addSubview(bannerView)
        bannerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        bannerView.load(Request())
    }
}
