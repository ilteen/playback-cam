import AVFoundation
import AVKit
import SwiftUI

struct PlaybackPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        configure(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        configure(uiViewController)
    }

    private func configure(_ controller: AVPlayerViewController) {
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.allowsPictureInPicturePlayback = false
        controller.updatesNowPlayingInfoCenter = false
        if #available(iOS 16.0, *) {
            controller.allowsVideoFrameAnalysis = false
        }
        controller.view.backgroundColor = .black
        controller.contentOverlayView?.backgroundColor = .clear
    }
}
