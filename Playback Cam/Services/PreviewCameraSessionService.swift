import AVFoundation

@MainActor
final class PreviewCameraSessionService: CameraSessionControlling {
    let session = AVCaptureSession()
    var stateDidChange: ((CameraSessionState) -> Void)?
    var isPreviewStub: Bool { true }
    var currentState: CameraSessionState { state }

    private var state: CameraSessionState {
        didSet {
            stateDidChange?(state)
        }
    }

    init(state: CameraSessionState) {
        self.state = state
    }

    func attachPreview(to previewLayer: AVCaptureVideoPreviewLayer) {}

    func detachPreview() {}

    func startSessionIfNeeded() {
        stateDidChange?(state)
    }

    func stopSession() {}

    func startRecording() {
        state.isRecording = true
    }

    func stopRecording() async -> Recording? {
        state.isRecording = false
        return nil
    }

    func selectZoomOption(_ option: CameraZoomOption) {
        guard state.availableZoomOptions.contains(option) else { return }
        state.selectedZoomOption = option
    }

    func dismissPermissionAlert() {
        state.requiresPermissionAlert = false
    }
}
