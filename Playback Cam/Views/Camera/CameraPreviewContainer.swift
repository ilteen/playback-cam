import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewContainer: UIViewRepresentable {
    let session: AVCaptureSession
    let showsDelayedPlayback: Bool
    let onPreviewLayerReady: (AVCaptureVideoPreviewLayer) -> Void
    let onDelayedPlaybackViewReady: (UIImageView) -> Void

    func makeUIView(context: Context) -> CameraCaptureSurfaceView {
        let view = CameraCaptureSurfaceView()
        configure(view)
        return view
    }

    func updateUIView(_ uiView: CameraCaptureSurfaceView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: CameraCaptureSurfaceView) {
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.delayedPlaybackView.contentMode = .scaleAspectFill
        view.showsDelayedPlayback = showsDelayedPlayback
        onPreviewLayerReady(view.previewLayer)
        onDelayedPlaybackViewReady(view.delayedPlaybackView)
    }
}

final class CameraCaptureSurfaceView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    let delayedPlaybackView = UIImageView()

    var showsDelayedPlayback = false {
        didSet {
            previewLayer.isHidden = showsDelayedPlayback
            delayedPlaybackView.isHidden = !showsDelayedPlayback
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.addSublayer(previewLayer)
        addSubview(delayedPlaybackView)
        delayedPlaybackView.backgroundColor = .black
        delayedPlaybackView.contentMode = .scaleAspectFill
        delayedPlaybackView.clipsToBounds = true
        delayedPlaybackView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        delayedPlaybackView.frame = bounds
    }
}
