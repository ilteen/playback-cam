import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var pendingPlaybackRecording: Recording?
    @Published private(set) var playbackViewModel: PlaybackViewModel?
    @Published private(set) var sessionSavedRecordings: [Recording] = []
    @Published private(set) var galleryStartIndex: Int?
    @Published private(set) var pendingSaveTransitionRecording: Recording?
    @Published private(set) var pendingGallerySaveRecording: Recording?

    let cameraViewModel: CameraViewModel
    let playbackSettings = PlaybackSettingsStore()

    private let recordingSaver: RecordingSaving

    init(
        cameraService: CameraSessionControlling? = nil,
        recordingSaver: RecordingSaving = PhotoLibraryService()
    ) {
        self.recordingSaver = recordingSaver
        self.cameraViewModel = CameraViewModel(service: cameraService ?? LiveCameraSessionService())
        cleanupSessionGalleryFiles()
        self.cameraViewModel.onRecordingFinished = { [weak self] recording in
            self?.pendingPlaybackRecording = recording
        }
    }

    var lastSessionSavedRecording: Recording? {
        sessionSavedRecordings.last
    }

    var showsGalleryButton: Bool {
        !sessionSavedRecordings.isEmpty
    }

    func openGallery() {
        guard !sessionSavedRecordings.isEmpty else { return }
        galleryStartIndex = sessionSavedRecordings.count - 1
    }

    func closeGallery() {
        galleryStartIndex = nil
    }

    func clearPendingSaveTransition() {
        pendingSaveTransitionRecording = nil
    }

    func discardActivePlayback() {
        playbackViewModel?.discardRecording()
    }

    func presentPendingPlayback() {
        guard let recording = pendingPlaybackRecording else { return }
        pendingPlaybackRecording = nil
        presentPlayback(for: recording)
    }

    private func presentPlayback(for recording: Recording) {
        playbackViewModel = PlaybackViewModel(
            recording: recording,
            playbackSettings: playbackSettings,
            recordingSaver: recordingSaver,
            onDiscard: { [weak self] in
                self?.playbackViewModel = nil
            },
            onSaveStarted: { [weak self] savingRecording in
                self?.pendingGallerySaveRecording = savingRecording
            },
            onSaveFinished: { [weak self] in
                self?.pendingGallerySaveRecording = nil
            },
            onKeep: { [weak self] in
                self?.playbackViewModel = nil
            },
            onSavedToSession: { [weak self] savedRecording in
                guard let self else { return }
                self.sessionSavedRecordings.append(savedRecording)
                Task {
                    _ = await VideoThumbnailService.prepareThumbnail(for: savedRecording.videoURL)
                }
            }
        )
    }

    private func cleanupSessionGalleryFiles() {
        let temporaryDirectory = FileManager.default.temporaryDirectory

        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in fileURLs where fileURL.lastPathComponent.hasPrefix("session-gallery-") {
            try? FileManager.default.removeItem(at: fileURL)
        }
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
