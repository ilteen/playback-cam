import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var playbackViewModel: PlaybackViewModel?

    let cameraViewModel: CameraViewModel

    private let recordingSaver: RecordingSaving

    init(
        cameraService: CameraSessionControlling? = nil,
        recordingSaver: RecordingSaving = PhotoLibraryService()
    ) {
        self.recordingSaver = recordingSaver
        self.cameraViewModel = CameraViewModel(service: cameraService ?? LiveCameraSessionService())
        self.cameraViewModel.onRecordingFinished = { [weak self] recording in
            self?.presentPlayback(for: recording)
        }
    }

    private func presentPlayback(for recording: Recording) {
        playbackViewModel = PlaybackViewModel(
            recording: recording,
            recordingSaver: recordingSaver,
            onDiscard: { [weak self] in
                self?.playbackViewModel = nil
            },
            onKeep: { [weak self] in
                self?.playbackViewModel = nil
            }
        )
    }
}

#if DEBUG
extension AppViewModel {
    static func preview() -> AppViewModel {
        AppViewModel(
            cameraService: PreviewCameraSessionService(
                state: CameraSessionState(
                    isRecording: false,
                    errorMessage: nil,
                    availableZoomOptions: [.ultraWide, .wide],
                    selectedZoomOption: .wide,
                    requiresPermissionAlert: false
                )
            )
        )
    }
}
#endif
