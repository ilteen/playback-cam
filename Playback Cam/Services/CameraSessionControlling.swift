import AVFoundation
import UIKit

@MainActor
protocol CameraSessionControlling: AnyObject {
    var session: AVCaptureSession { get }
    var currentState: CameraSessionState { get }
    var stateDidChange: ((CameraSessionState) -> Void)? { get set }
    var isPreviewStub: Bool { get }

    func attachPreview(to previewLayer: AVCaptureVideoPreviewLayer)
    func attachDelayedPlayback(to imageView: UIImageView)
    func detachPreview()
    func startSessionIfNeeded()
    func stopSession()
    func startRecording()
    func stopRecording() async -> Recording?
    func selectZoomOption(_ option: CameraZoomOption)
    func selectCaptureMode(_ mode: CameraCaptureMode)
    func selectDelayedPlaybackOption(_ option: DelayedPlaybackDelayOption)
    func dismissPermissionAlert()
}
