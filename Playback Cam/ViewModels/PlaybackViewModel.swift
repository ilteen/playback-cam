import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published private(set) var state: PlaybackState
    @Published var selectedRate: PlaybackRateOption
    @Published private(set) var saveMessage: String?
    @Published private(set) var isSaving = false

    let player: AVPlayer
    let isPreviewMode: Bool
    let recording: Recording

    private let recordingSaver: RecordingSaving
    private let onDiscard: () -> Void
    private let onKeep: () -> Void

    private var wasPlayingBeforeScrub = false
    private var observerToken: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var metadataTask: Task<Void, Never>?

    init(
        recording: Recording,
        recordingSaver: RecordingSaving = PhotoLibraryService(),
        onDiscard: @escaping () -> Void,
        onKeep: @escaping () -> Void
    ) {
        self.recording = recording
        self.recordingSaver = recordingSaver
        self.onDiscard = onDiscard
        self.onKeep = onKeep
        self.player = AVPlayer()
        self.state = PlaybackState()
        self.selectedRate = .quarter
        self.isPreviewMode = false
    }

    #if DEBUG
    private init(
        recording: Recording,
        previewState: PlaybackState,
        selectedRate: PlaybackRateOption
    ) {
        self.recording = recording
        self.recordingSaver = PhotoLibraryService()
        self.onDiscard = {}
        self.onKeep = {}
        self.player = AVPlayer()
        self.state = previewState
        self.selectedRate = selectedRate
        self.isPreviewMode = true
    }
    #endif

    func onAppear() {
        guard !isPreviewMode else { return }
        configurePlayer()
    }

    func onDisappear() {
        guard !isPreviewMode else { return }
        tearDownPlayer()
    }

    func selectPlaybackRate(_ option: PlaybackRateOption) {
        selectedRate = option
        guard state.isPlaying, !isPreviewMode else { return }
        player.rate = Float(option.rate)
    }

    func togglePlayback() {
        if isPreviewMode {
            if state.isPlaying {
                state.isPlaying = false
            } else {
                if state.currentTime >= state.duration - state.frameDuration {
                    state.currentTime = 0
                }
                state.isPlaying = true
            }
            return
        }

        if state.isPlaying {
            state.isPlaying = false
            player.pause()
            return
        }

        if state.currentTime >= state.duration - state.frameDuration {
            state.currentTime = 0
            seek(to: 0)
        }

        state.isPlaying = true
        player.playImmediately(atRate: Float(selectedRate.rate))
    }

    func beginScrubbing() {
        guard !state.isScrubbing else { return }

        state.isScrubbing = true
        wasPlayingBeforeScrub = state.isPlaying

        guard state.isPlaying, !isPreviewMode else { return }
        player.pause()
        state.isPlaying = false
    }

    func scrub(to fraction: Double) {
        let targetTime = min(max(state.duration * fraction, 0), state.duration)
        state.currentTime = targetTime

        guard !isPreviewMode else { return }
        seek(to: targetTime)
    }

    func endScrubbing() {
        state.isScrubbing = false
        guard wasPlayingBeforeScrub else { return }

        wasPlayingBeforeScrub = false
        state.isPlaying = true

        guard !isPreviewMode else { return }
        player.playImmediately(atRate: Float(selectedRate.rate))
    }

    func stepFrame(by amount: Int) {
        let nextTime = min(
            max(0, state.currentTime + Double(amount) * state.frameDuration),
            state.duration
        )

        state.currentTime = nextTime
        state.isPlaying = false

        guard !isPreviewMode else { return }
        player.pause()
        seek(to: nextTime)
    }

    func discardRecording() {
        if !isPreviewMode {
            player.pause()
            try? FileManager.default.removeItem(at: recording.videoURL)
        }
        onDiscard()
    }

    func saveToPhotoLibrary() {
        guard !isSaving else { return }

        guard !isPreviewMode else {
            saveMessage = "Preview only."
            return
        }

        isSaving = true
        saveMessage = nil

        Task {
            let result = await recordingSaver.save(recording: recording)

            switch result {
            case .saved:
                try? FileManager.default.removeItem(at: recording.videoURL)
                isSaving = false
                saveMessage = "Saved"

                try? await Task.sleep(nanoseconds: 350_000_000)
                onKeep()

            case .denied:
                isSaving = false
                saveMessage = "Photo Library access denied."

            case .failed:
                isSaving = false
                saveMessage = "Save failed."
            }
        }
    }

    func timeString(for seconds: Double) -> String {
        let totalCentiseconds = Int((seconds * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let wholeSeconds = (totalCentiseconds % 6000) / 100
        let centiseconds = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, wholeSeconds, centiseconds)
    }

    private func configurePlayer() {
        let asset = AVURLAsset(url: recording.videoURL)
        let item = AVPlayerItem(asset: asset)

        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause

        metadataTask?.cancel()
        state.frameDuration = 1.0 / 30.0
        state.duration = 0.01
        state.currentTime = 0

        metadataTask = Task {
            let loadedDuration = try? await asset.load(.duration)
            let loadedTracks = try? await asset.loadTracks(withMediaType: .video)

            guard !Task.isCancelled else { return }

            if let loadedDuration {
                state.duration = max(CMTimeGetSeconds(loadedDuration), 0.01)
            }

            if let track = loadedTracks?.first,
               let nominalFrameRate = try? await track.load(.nominalFrameRate),
               nominalFrameRate > 0 {
                state.frameDuration = 1.0 / Double(nominalFrameRate)
            }
        }

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        observerToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.state.isScrubbing else { return }
                self.state.currentTime = min(max(0, CMTimeGetSeconds(time)), self.state.duration)
            }
        }

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state.isPlaying = false
                self.state.currentTime = self.state.duration
            }
        }
    }

    private func tearDownPlayer() {
        metadataTask?.cancel()
        metadataTask = nil

        player.pause()
        state.isPlaying = false
        state.isScrubbing = false

        if let observerToken {
            player.removeTimeObserver(observerToken)
            self.observerToken = nil
        }

        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
    }

    private func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
}

#if DEBUG
extension PlaybackViewModel {
    static func preview(
        isPlaying: Bool,
        currentTime: Double,
        duration: Double,
        selectedRate: PlaybackRateOption
    ) -> PlaybackViewModel {
        let recording = Recording(
            videoURL: URL(fileURLWithPath: "/dev/null"),
            createdAt: .now
        )

        return PlaybackViewModel(
            recording: recording,
            previewState: PlaybackState(
                isPlaying: isPlaying,
                isScrubbing: false,
                duration: duration,
                currentTime: currentTime,
                frameDuration: 1.0 / 120.0
            ),
            selectedRate: selectedRate
        )
    }
}
#endif
