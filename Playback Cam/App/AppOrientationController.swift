import SwiftUI
import UIKit

@MainActor
final class AppOrientationController {
    static let shared = AppOrientationController()

    private(set) var supportedOrientations: UIInterfaceOrientationMask = {
        return .portrait
    }()

    private init() {}

    func applyCameraPolicy() {
        apply(mask: .portrait)
    }

    func applyPlaybackPolicy() {
        apply(mask: .allButUpsideDown)
    }

    private func apply(mask: UIInterfaceOrientationMask) {
        supportedOrientations = mask

        UIView.performWithoutAnimation {
            for windowScene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            where windowScene.activationState == .foregroundActive {
                for window in windowScene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }

                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            }
        }
    }
}

final class PlaybackCamAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationController.shared.supportedOrientations
    }
}
