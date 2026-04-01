import AVFoundation
import CoreMedia
import CoreImage
import Foundation
import UIKit

@MainActor
final class LiveCameraSessionService: NSObject, CameraSessionControlling {
    var stateDidChange: ((CameraSessionState) -> Void)?
    var isPreviewStub: Bool { false }
    var currentState: CameraSessionState { state }

    nonisolated(unsafe) let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "playbackcam.camera.session")
    private let delayedPlaybackQueue = DispatchQueue(label: "playbackcam.camera.delayed-playback")

    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private let videoDataOutput = AVCaptureVideoDataOutput()
    private let delayedPlaybackImageContext = CIContext(options: [.cacheIntermediates: false])

    nonisolated(unsafe) private var configured = false
    nonisolated(unsafe) private var activeVideoInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var devicesByZoomOption: [CameraZoomOption: AVCaptureDevice] = [:]
    nonisolated(unsafe) private var defaultFormatsByDeviceID: [String: AVCaptureDevice.Format] = [:]
    nonisolated(unsafe) private var delayedPlaybackFrameCaptureTimes: [TimeInterval] = []
    nonisolated(unsafe) private var delayedPlaybackFrameData: [Data] = []
    nonisolated(unsafe) private var delayedPlaybackFrameStartIndex = 0
    nonisolated(unsafe) private var lastDelayedPlaybackFrameTime: TimeInterval?
    nonisolated(unsafe) private var delayedPlaybackMode = CameraCaptureMode.slowMo
    nonisolated(unsafe) private var delayedPlaybackDelay = 2.0

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    nonisolated(unsafe) private weak var delayedPlaybackImageView: UIImageView?
    private var currentRotationDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var recordingContinuation: CheckedContinuation<Recording?, Never>?
    private var pendingDelayedPlaybackDelaySelectionTask: Task<Void, Never>?

    private var state = CameraSessionState() {
        didSet {
            stateDidChange?(state)
        }
    }

    func attachPreview(to previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        refreshRotationCoordinator(for: currentRotationDevice)
    }

    func attachDelayedPlayback(to imageView: UIImageView) {
        let needsReset = delayedPlaybackImageView !== imageView

        delayedPlaybackImageView = imageView
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.image = nil
        imageView.layer.contentsGravity = .resizeAspectFill
        imageView.layer.masksToBounds = true
        imageView.layer.contents = nil

        if needsReset {
            resetDelayedPlaybackDisplayLayer()
        }
    }

    func detachPreview() {
        pendingDelayedPlaybackDelaySelectionTask?.cancel()
        pendingDelayedPlaybackDelaySelectionTask = nil
        previewRotationObservation = nil
        previewLayer?.session = nil
        previewLayer = nil
        delayedPlaybackImageView?.image = nil
        delayedPlaybackImageView = nil
        refreshRotationCoordinator(for: currentRotationDevice)
    }

    func startSessionIfNeeded() {
        guard !configured else {
            startRunningSession()
            return
        }

        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                state.requiresPermissionAlert = true
                return
            }

            configureSession()
            startRunningSession()
        }
    }

    func stopSession() {
        pendingDelayedPlaybackDelaySelectionTask?.cancel()
        pendingDelayedPlaybackDelaySelectionTask = nil
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }

        delayedPlaybackQueue.async {
            self.resetDelayedPlaybackState()
        }
    }

    func startRecording() {
        guard state.captureMode == .slowMo else { return }
        guard !state.isRecording else { return }
        guard configured else {
            state.errorMessage = "Camera setup not finished."
            return
        }

        state.errorMessage = nil
        state.isRecording = true
        let rotationAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0

        sessionQueue.async {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("capture-\(UUID().uuidString).mov")

            try? FileManager.default.removeItem(at: fileURL)

            if let connection = self.movieOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }

            self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        }
    }

    func stopRecording() async -> Recording? {
        guard state.captureMode == .slowMo else { return nil }
        guard state.isRecording else { return nil }

        state.isRecording = false

        return await withCheckedContinuation { continuation in
            recordingContinuation = continuation
            sessionQueue.async {
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                } else {
                    Task { @MainActor in
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    func selectZoomOption(_ option: CameraZoomOption) {
        guard !state.isRecording else { return }
        guard state.selectedZoomOption != option else { return }
        guard state.availableZoomOptions.contains(option) else { return }

        state.errorMessage = nil

        let captureMode = state.captureMode

        if captureMode == .delayedPlayback {
            state.isDelayedPlaybackReady = false
            delayedPlaybackQueue.async {
                self.resetDelayedPlaybackState()
            }
        }

        sessionQueue.async {
            self.switchToDevice(for: option, captureMode: captureMode)
        }
    }

    func selectCaptureMode(_ mode: CameraCaptureMode) {
        guard !state.isRecording else { return }
        guard state.captureMode != mode else { return }

        pendingDelayedPlaybackDelaySelectionTask?.cancel()
        pendingDelayedPlaybackDelaySelectionTask = nil
        state.captureMode = mode
        state.errorMessage = nil
        state.isDelayedPlaybackReady = false

        let selectedDelay = state.selectedDelayOption.duration

        delayedPlaybackQueue.async {
            self.delayedPlaybackMode = mode
            self.delayedPlaybackDelay = selectedDelay
            self.resetDelayedPlaybackState()
        }

        sessionQueue.async {
            guard let device = self.activeVideoInput?.device else { return }
            self.configureCaptureMode(mode, on: device)
        }
    }

    func selectDelayedPlaybackOption(_ option: DelayedPlaybackDelayOption) {
        guard state.selectedDelayOption != option else { return }

        state.selectedDelayOption = option
        pendingDelayedPlaybackDelaySelectionTask?.cancel()

        pendingDelayedPlaybackDelaySelectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }

            if self.state.captureMode == .delayedPlayback {
                self.state.isDelayedPlaybackReady = false
            }

            self.delayedPlaybackQueue.async {
                self.delayedPlaybackDelay = option.duration
                self.resetDelayedPlaybackState()
            }

            await MainActor.run {
                if self.pendingDelayedPlaybackDelaySelectionTask?.isCancelled == false {
                    self.pendingDelayedPlaybackDelaySelectionTask = nil
                }
            }
        }
    }

    func dismissPermissionAlert() {
        state.requiresPermissionAlert = false
    }

    nonisolated private func startRunningSession() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    nonisolated private func configureSession() {
        sessionQueue.sync {
            guard !self.configured else { return }

            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.inputPriority) {
                self.session.sessionPreset = .inputPriority
            } else {
                self.session.sessionPreset = .high
            }

            defer {
                self.session.commitConfiguration()
            }

            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )

            let ultraWide = discovery.devices.first(where: { $0.deviceType == .builtInUltraWideCamera })
            let wide = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })

            guard let wide else {
                Task { @MainActor in
                    self.state.errorMessage = "Back camera unavailable."
                }
                return
            }

            var devicesByZoomOption: [CameraZoomOption: AVCaptureDevice] = [.wide: wide]
            self.defaultFormatsByDeviceID[wide.uniqueID] = wide.activeFormat

            if let ultraWide {
                devicesByZoomOption[.ultraWide] = ultraWide
                self.defaultFormatsByDeviceID[ultraWide.uniqueID] = ultraWide.activeFormat
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: wide)
                guard self.session.canAddInput(videoInput) else {
                    Task { @MainActor in
                        self.state.errorMessage = "Camera configuration failed."
                    }
                    return
                }

                self.session.addInput(videoInput)
                self.activeVideoInput = videoInput

                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                self.videoDataOutput.videoSettings = [:]
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.delayedPlaybackQueue)

                guard self.session.canAddOutput(self.videoDataOutput) else {
                    Task { @MainActor in
                        self.state.errorMessage = "Camera configuration failed."
                    }
                    return
                }

                self.session.addOutput(self.videoDataOutput)

                guard self.session.canAddOutput(self.movieOutput) else {
                    Task { @MainActor in
                        self.state.errorMessage = "Camera configuration failed."
                    }
                    return
                }

                self.session.addOutput(self.movieOutput)
                self.movieOutput.movieFragmentInterval = .invalid
                self.devicesByZoomOption = devicesByZoomOption
                self.delayedPlaybackMode = .slowMo
                self.delayedPlaybackDelay = DelayedPlaybackDelayOption.two.duration
                self.configured = true

                let zoomOptions = devicesByZoomOption.keys.sorted { lhs, rhs in
                    switch (lhs, rhs) {
                    case (.ultraWide, .wide):
                        return true
                    case (.wide, .ultraWide):
                        return false
                    default:
                        return lhs.rawValue < rhs.rawValue
                    }
                }

                self.configureSlowMotion(on: wide)

                Task { @MainActor in
                    self.state.availableZoomOptions = zoomOptions
                    self.state.selectedZoomOption = .wide
                    self.currentRotationDevice = wide
                    self.refreshRotationCoordinator(for: wide)
                }
            } catch {
                Task { @MainActor in
                    self.state.errorMessage = "Camera configuration failed."
                }
            }
        }
    }

    nonisolated private func configureCaptureMode(_ mode: CameraCaptureMode, on device: AVCaptureDevice) {
        session.beginConfiguration()
        switch mode {
        case .slowMo:
            if session.canSetSessionPreset(.inputPriority) {
                session.sessionPreset = .inputPriority
            } else if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
        case .delayedPlayback:
            if session.canSetSessionPreset(.inputPriority) {
                session.sessionPreset = .inputPriority
            } else if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
        }
        session.commitConfiguration()

        switch mode {
        case .slowMo:
            configureSlowMotion(on: device)
        case .delayedPlayback:
            configureStandardCapture(on: device)
        }
    }

    nonisolated private func configureSlowMotion(on device: AVCaptureDevice) {
        var bestFormat: AVCaptureDevice.Format?
        var bestRate: Double = 0

        for format in device.formats {
            guard let range = format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else {
                continue
            }

            if range.maxFrameRate > bestRate {
                bestRate = range.maxFrameRate
                bestFormat = format
            }
        }

        let targetFPS: Double
        if bestRate >= 240 {
            targetFPS = 240
        } else if bestRate >= 120 {
            targetFPS = 120
        } else if bestRate >= 60 {
            targetFPS = 60
        } else {
            targetFPS = max(30, bestRate)
        }

        do {
            try device.lockForConfiguration()
            if let bestFormat {
                device.activeFormat = bestFormat
            }
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
        } catch {
            return
        }
    }

    nonisolated private func configureStandardCapture(on device: AVCaptureDevice) {
        let preferredFormat = preferredDelayedPlaybackFormat(for: device)

        do {
            try device.lockForConfiguration()
            if let preferredFormat {
                device.activeFormat = preferredFormat
                let frameDuration = CMTime(
                    value: 1,
                    timescale: 60
                )
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            } else if let defaultFormat = defaultFormatsByDeviceID[device.uniqueID] {
                device.activeFormat = defaultFormat
                device.activeVideoMinFrameDuration = .invalid
                device.activeVideoMaxFrameDuration = .invalid
            }
            device.unlockForConfiguration()
        } catch {
            return
        }
    }

    nonisolated private func preferredDelayedPlaybackFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        return device.formats
            .filter { format in
                guard let maximumFrameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() else {
                    return false
                }

                return maximumFrameRate >= 60.0
            }
            .min { lhs, rhs in
                delayedPlaybackFormatScore(for: lhs) < delayedPlaybackFormatScore(for: rhs)
            }
    }

    nonisolated private func delayedPlaybackFormatScore(for format: AVCaptureDevice.Format) -> Double {
        let targetWidth: Int32 = 1920
        let targetHeight: Int32 = 1080
        let targetAspectRatio = Double(targetWidth) / Double(targetHeight)
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let widthDelta = Double(abs(dimensions.width - targetWidth))
        let heightDelta = Double(abs(dimensions.height - targetHeight))
        let aspectRatio = Double(dimensions.width) / Double(max(dimensions.height, 1))
        let aspectPenalty = abs(aspectRatio - targetAspectRatio) * 10_000
        let areaPenalty = widthDelta + heightDelta
        let frameRatePenalty = 60.0 - (
            format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        )

        return aspectPenalty + areaPenalty + max(0.0, frameRatePenalty) * 1_000
    }

    nonisolated private func switchToDevice(for option: CameraZoomOption, captureMode: CameraCaptureMode) {
        guard let device = devicesByZoomOption[option] else { return }
        guard activeVideoInput?.device.uniqueID != device.uniqueID else { return }
        guard let currentInput = activeVideoInput else { return }

        do {
            let newInput = try AVCaptureDeviceInput(device: device)

            session.beginConfiguration()
            session.removeInput(currentInput)

            guard session.canAddInput(newInput) else {
                if session.canAddInput(currentInput) {
                    session.addInput(currentInput)
                }
                session.commitConfiguration()
                return
            }

            session.addInput(newInput)
            activeVideoInput = newInput
            session.commitConfiguration()
            configureCaptureMode(captureMode, on: device)

            Task { @MainActor in
                self.state.selectedZoomOption = option
                self.currentRotationDevice = device
                self.refreshRotationCoordinator(for: device)
            }
        } catch {
            session.beginConfiguration()
            if !session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.uniqueID == currentInput.device.uniqueID }),
               session.canAddInput(currentInput) {
                session.addInput(currentInput)
            }
            session.commitConfiguration()

            Task { @MainActor in
                self.state.errorMessage = "Could not switch lenses."
            }
        }
    }

    private func refreshRotationCoordinator(for device: AVCaptureDevice?) {
        previewRotationObservation = nil
        rotationCoordinator = nil
        currentRotationDevice = device

        guard let device else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            let previewRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyPreviewRotation(angle: previewRotationAngle)
                self.applyVideoDataOutputRotation(angle: previewRotationAngle)
            }
        }
    }

    private func applyPreviewRotation(angle: CGFloat) {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }

        connection.videoRotationAngle = angle
    }

    private func applyVideoDataOutputRotation(angle: CGFloat) {
        guard let connection = videoDataOutput.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }

        connection.videoRotationAngle = angle
    }

    private func resetDelayedPlaybackDisplayLayer() {
        delayedPlaybackImageView?.image = nil
        delayedPlaybackImageView?.layer.contents = nil
    }

    nonisolated private func resetDelayedPlaybackState() {
        delayedPlaybackFrameCaptureTimes.removeAll(keepingCapacity: true)
        delayedPlaybackFrameData.removeAll(keepingCapacity: true)
        delayedPlaybackFrameStartIndex = 0
        lastDelayedPlaybackFrameTime = nil

        Task { @MainActor in
            self.state.isDelayedPlaybackReady = false
            self.resetDelayedPlaybackDisplayLayer()
        }
    }

    nonisolated private func bufferedPlaybackFrameRate() -> Double {
        min(
            60.0,
            max(12.0, 360.0 / max(delayedPlaybackDelay, 1))
        )
    }

    nonisolated private func shouldBufferDelayedPlaybackFrame(at captureTime: TimeInterval) -> Bool {
        let targetFrameRate = bufferedPlaybackFrameRate()

        guard let lastDelayedPlaybackFrameTime else {
            self.lastDelayedPlaybackFrameTime = captureTime
            return true
        }

        guard captureTime - lastDelayedPlaybackFrameTime >= (1 / targetFrameRate) else {
            return false
        }

        self.lastDelayedPlaybackFrameTime = captureTime
        return true
    }

    nonisolated private func dueDelayedPlaybackFrameData(for currentCaptureTime: TimeInterval) -> Data? {
        var dueFrameData: Data?

        while delayedPlaybackFrameStartIndex < delayedPlaybackFrameCaptureTimes.count {
            let firstCaptureTime = delayedPlaybackFrameCaptureTimes[delayedPlaybackFrameStartIndex]
            guard (currentCaptureTime - firstCaptureTime) >= delayedPlaybackDelay else {
                break
            }

            dueFrameData = delayedPlaybackFrameData[delayedPlaybackFrameStartIndex]
            delayedPlaybackFrameStartIndex += 1
        }

        if delayedPlaybackFrameStartIndex > 120,
           delayedPlaybackFrameStartIndex >= (delayedPlaybackFrameCaptureTimes.count / 2) {
            delayedPlaybackFrameCaptureTimes.removeFirst(delayedPlaybackFrameStartIndex)
            delayedPlaybackFrameData.removeFirst(delayedPlaybackFrameStartIndex)
            delayedPlaybackFrameStartIndex = 0
        }

        return dueFrameData
    }

    nonisolated private func encodedDelayedPlaybackFrameData(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let image = CIImage(cvPixelBuffer: imageBuffer)
        let extent = image.extent.integral

        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        guard let renderedFrame = delayedPlaybackImageContext.createCGImage(
            image,
            from: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            return nil
        }

        return UIImage(cgImage: renderedFrame).jpegData(
            compressionQuality: 0.82
        )
    }

    nonisolated private func decodedDelayedPlaybackImage(from frameData: Data) -> UIImage? {
        UIImage(data: frameData)
    }

    nonisolated private func enqueueDelayedPlaybackImage(_ image: UIImage) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let delayedPlaybackImageView = self.delayedPlaybackImageView else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            delayedPlaybackImageView.layer.contents = nil
            delayedPlaybackImageView.image = image
            CATransaction.commit()
        }
    }
}

extension LiveCameraSessionService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        Task { @MainActor in
            let result: Recording?
            if error == nil {
                result = Recording(videoURL: outputFileURL, createdAt: Date())
            } else {
                result = nil
                try? FileManager.default.removeItem(at: outputFileURL)
                self.state.errorMessage = "Recording failed."
            }

            self.state.isRecording = false
            self.recordingContinuation?.resume(returning: result)
            self.recordingContinuation = nil
        }
    }
}

extension LiveCameraSessionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard delayedPlaybackMode == .delayedPlayback else { return }
        let captureTime = ProcessInfo.processInfo.systemUptime

        guard shouldBufferDelayedPlaybackFrame(at: captureTime),
              let encodedFrameData = encodedDelayedPlaybackFrameData(from: sampleBuffer) else {
            return
        }

        delayedPlaybackFrameCaptureTimes.append(captureTime)
        delayedPlaybackFrameData.append(encodedFrameData)

        guard let dueDelayedPlaybackFrameData = dueDelayedPlaybackFrameData(for: captureTime),
              let dueDelayedPlaybackImage = decodedDelayedPlaybackImage(from: dueDelayedPlaybackFrameData) else {
            return
        }

        enqueueDelayedPlaybackImage(dueDelayedPlaybackImage)

        Task { @MainActor in
            if !self.state.isDelayedPlaybackReady {
                self.state.isDelayedPlaybackReady = true
            }
        }
    }
}
