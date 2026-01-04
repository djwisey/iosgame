import Foundation

final class AdManager {
    static let shared = AdManager()

    private init() {}

    func preloadInterstitial() {
        print("[AdManager] preloadInterstitial")
    }

    func showInterstitialIfReady(reason: String) {
        print("[AdManager] showInterstitialIfReady reason=\(reason)")
    }
}
