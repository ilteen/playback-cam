import AVFoundation
import Photos
import SwiftUI
import UIKit

private enum PlaybackRateOption: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case quarter = "0.25x"
    case half = "0.5x"
    case full = "1.0x"

    var id: String { rawValue }
}

struct PlaybackScreen: View {
    let recording: RecordingResult
    let onDiscard: () -> Void
    let onKeep: () -> Void

    @State private var isPlaying = false
    @State private var duration: Double = 0.01
    @State private var currentTime: Double = 0
    @State private var selectedRate: PlaybackRateOption = .auto
    @State private var frameDuration: Double = 1.0 / 30.0
    @State private var sourceFPS: Double = 120
    @State private var observerToken: Any?
    @State private var saveMessage: String?
    @State private var isSaving = false

    @State private var player = AVPlayer()

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                PlayerSurface(player: player)
                    .ignoresSafeArea()

                topOverlay

                scrubOverlay(isLandscape: isLandscape)

                controlsOverlay(isLandscape: isLandscape)

                if let saveMessage {
                    VStack {
                        Spacer()
                        Text(saveMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(.bottom, isLandscape ? 18 : 84)
                    }
                }
            }
            .onAppear { configurePlayer() }
            .onDisappear { tearDownPlayer() }
        }
    }

    private var iosDefaultRate: Double {
        min(1.0, max(0.05, 30.0 / max(sourceFPS, 30)))
    }

    private var activeRate: Double {
        switch selectedRate {
        case .auto: return iosDefaultRate
        case .quarter: return 0.25
        case .half: return 0.5
        case .full: return 1.0
        }
    }

    private var frameStepAmount: Int {
        max(1, Int((10.0 * activeRate).rounded()))
    }

    private var scrubFraction: Double {
        min(max(currentTime / max(duration, 0.01), 0), 1)
    }

    private var topOverlay: some View {
        VStack {
            HStack {
                Button {
                    discardAndReturn()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    saveToPhotoLibrary()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.35), in: Circle())
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()
        }
    }

    private func scrubOverlay(isLandscape: Bool) -> some View {
        VStack {
            Spacer()

            HStack(spacing: 10) {
                KnoblessScrubBar(
                    progress: scrubFraction,
                    onScrub: { ratio in
                        let newValue = duration * ratio
                        currentTime = min(max(0, newValue), duration)
                        seek(to: currentTime)
                    }
                )
                .frame(height: 20)

                Text(timeString(for: currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.28), in: Capsule())
            .padding(.horizontal, isLandscape ? 90 : 12)
            .padding(.bottom, isLandscape ? 14 : 74)
        }
    }

    @ViewBuilder
    private func controlsOverlay(isLandscape: Bool) -> some View {
        if isLandscape {
            HStack {
                Spacer()
                VStack(spacing: 14) {
                    skipButton(isBackward: true)
                    playPauseButton(size: 52)
                    skipButton(isBackward: false)
                    speedButtonsHorizontal
                }
                .padding(.trailing, 12)
                .padding(.vertical, 58)
            }
        } else {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    skipButton(isBackward: true)
                    playPauseButton(size: 54)
                    skipButton(isBackward: false)
                    speedButtonsHorizontal
                }
                .padding(.bottom, 22)
            }
        }
    }

    private func playPauseButton(size: CGFloat) -> some View {
        Button {
            togglePlayback()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }

    private func skipButton(isBackward: Bool) -> some View {
        Button {
            stepFrame(by: isBackward ? -frameStepAmount : frameStepAmount)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isBackward ? "backward.end.fill" : "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(frameStepAmount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(width: 52, height: 40)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.16), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private var speedButtonsHorizontal: some View {
        HStack(spacing: 6) {
            speedButton(.auto, label: "Auto")
            speedButton(.quarter, label: "0.25")
            speedButton(.half, label: "0.5")
            speedButton(.full, label: "1x")
        }
        .onChange(of: selectedRate) {
            if isPlaying {
                player.rate = Float(activeRate)
            }
        }
    }

    private func speedButton(_ option: PlaybackRateOption, label: String) -> some View {
        Button {
            selectedRate = option
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedRate == option ? .black : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            .background(
                (selectedRate == option ? Color.white.opacity(0.95) : Color.black.opacity(0.35)),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(.white.opacity(selectedRate == option ? 0.0 : 0.16), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func configurePlayer() {
        let asset = AVURLAsset(url: recording.videoURL)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)

        if let track = asset.tracks(withMediaType: .video).first,
           track.nominalFrameRate > 0 {
            sourceFPS = Double(track.nominalFrameRate)
            frameDuration = 1.0 / sourceFPS
        }

        duration = max(CMTimeGetSeconds(asset.duration), 0.01)

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        observerToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = min(max(0, CMTimeGetSeconds(time)), duration)
        }
    }

    private func tearDownPlayer() {
        isPlaying = false
        player.pause()
        if let observerToken {
            player.removeTimeObserver(observerToken)
            self.observerToken = nil
        }
    }

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            player.playImmediately(atRate: Float(activeRate))
        } else {
            player.pause()
        }
    }

    private func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func stepFrame(by amount: Int) {
        player.pause()
        isPlaying = false

        let nextTime = min(
            max(0, currentTime + Double(amount) * frameDuration),
            duration
        )

        currentTime = nextTime
        seek(to: nextTime)
    }

    private func discardAndReturn() {
        player.pause()
        try? FileManager.default.removeItem(at: recording.videoURL)
        onDiscard()
    }

    private func saveToPhotoLibrary() {
        guard !isSaving else { return }
        isSaving = true
        saveMessage = nil

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    isSaving = false
                    saveMessage = "Photo Library access denied."
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: recording.videoURL)
            }, completionHandler: { success, _ in
                DispatchQueue.main.async {
                    isSaving = false
                    if success {
                        try? FileManager.default.removeItem(at: recording.videoURL)
                        saveMessage = "Saved"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onKeep()
                        }
                    } else {
                        saveMessage = "Save failed."
                    }
                }
            })
        }
    }

    private func timeString(for seconds: Double) -> String {
        let totalCentiseconds = Int((seconds * 100).rounded())
        let mins = totalCentiseconds / 6000
        let secs = (totalCentiseconds % 6000) / 100
        let cs = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", mins, secs, cs)
    }
}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer")
        }
        return layer
    }
}

private struct KnoblessScrubBar: View {
    let progress: Double
    let onScrub: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            let width = proxy.size.width
            let fillWidth = max(3, width * clamped)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.32))
                    .frame(height: 5)

                Capsule()
                    .fill(.white)
                    .frame(width: fillWidth, height: 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = min(max(value.location.x / max(width, 1), 0), 1)
                        onScrub(ratio)
                    }
            )
        }
    }
}
