import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class CameraViewModel: ObservableObject {
    @Published private(set) var state: CameraSessionState
    @Published private(set) var isStopping = false

    let session: AVCaptureSession
    let isPreviewMode: Bool

    var onRecordingFinished: (Recording) -> Void = { _ in }

    var settingsURL: URL? {
        URL(string: "app-settings:")
    }

    private let service: CameraSessionControlling

    init(service: CameraSessionControlling) {
        self.service = service
        self.session = service.session
        self.isPreviewMode = service.isPreviewStub
        self.state = service.currentState
        self.service.stateDidChange = { [weak self] newState in
            self?.state = newState
        }
    }

    var shouldShowPermissionAlert: Bool {
        state.requiresPermissionAlert
    }

    var showsZoomPicker: Bool {
        state.availableZoomOptions.contains(.wide) && state.availableZoomOptions.contains(.ultraWide)
    }

    var showsDelayedPlaybackLoadingIndicator: Bool {
        state.captureMode == .delayedPlayback && !state.isDelayedPlaybackReady
    }

    func onAppear() {
        service.startSessionIfNeeded()
    }

    func onDisappear() {
        service.detachPreview()
        service.stopSession()
    }

    func attachPreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard !isPreviewMode else { return }
        service.attachPreview(to: previewLayer)
    }

    func attachDelayedPlaybackView(_ imageView: UIImageView) {
        guard !isPreviewMode else { return }
        service.attachDelayedPlayback(to: imageView)
    }

    func dismissPermissionAlert() {
        service.dismissPermissionAlert()
    }

    func selectZoomOption(_ option: CameraZoomOption) {
        service.selectZoomOption(option)
    }

    func toggleCaptureMode() {
        let nextMode: CameraCaptureMode = state.captureMode == .slowMo ? .delayedPlayback : .slowMo
        service.selectCaptureMode(nextMode)
    }

    func selectDelayedPlaybackOption(_ option: DelayedPlaybackDelayOption) {
        service.selectDelayedPlaybackOption(option)
    }

    func captureButtonTapped() {
        guard state.captureMode == .slowMo else { return }

        if state.isRecording {
            stopRecording()
        } else {
            service.startRecording()
        }
    }

    private func stopRecording() {
        guard !isStopping else { return }
        isStopping = true

        Task {
            if let recording = await service.stopRecording() {
                onRecordingFinished(recording)
            }
            isStopping = false
        }
    }
}

#if DEBUG
extension CameraViewModel {
    static func preview(
        isRecording: Bool = false,
        errorMessage: String? = nil,
        selectedZoomOption: CameraZoomOption = .wide,
        captureMode: CameraCaptureMode = .slowMo,
        selectedDelayOption: DelayedPlaybackDelayOption = .two,
        isDelayedPlaybackReady: Bool = false
    ) -> CameraViewModel {
        let service = PreviewCameraSessionService(
            state: CameraSessionState(
                isRecording: isRecording,
                errorMessage: errorMessage,
                availableZoomOptions: [.ultraWide, .wide],
                selectedZoomOption: selectedZoomOption,
                requiresPermissionAlert: false,
                captureMode: captureMode,
                availableDelayOptions: DelayedPlaybackDelayOption.allCases,
                selectedDelayOption: selectedDelayOption,
                isDelayedPlaybackReady: isDelayedPlaybackReady
            )
        )
        return CameraViewModel(service: service)
    }
}
#endif
