import AVFoundation
import Combine
import Foundation

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

    func dismissPermissionAlert() {
        service.dismissPermissionAlert()
    }

    func selectZoomOption(_ option: CameraZoomOption) {
        service.selectZoomOption(option)
    }

    func captureButtonTapped() {
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
        selectedZoomOption: CameraZoomOption = .wide
    ) -> CameraViewModel {
        let service = PreviewCameraSessionService(
            state: CameraSessionState(
                isRecording: isRecording,
                errorMessage: errorMessage,
                availableZoomOptions: [.ultraWide, .wide],
                selectedZoomOption: selectedZoomOption,
                requiresPermissionAlert: false
            )
        )
        return CameraViewModel(service: service)
    }
}
#endif
