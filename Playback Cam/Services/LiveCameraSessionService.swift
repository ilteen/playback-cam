import AVFoundation
import Foundation

@MainActor
final class LiveCameraSessionService: NSObject, CameraSessionControlling {
    var stateDidChange: ((CameraSessionState) -> Void)?
    var isPreviewStub: Bool { false }
    var currentState: CameraSessionState { state }

    nonisolated(unsafe) let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "playbackcam.camera.session")
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()

    nonisolated(unsafe) private var configured = false
    nonisolated(unsafe) private var activeVideoInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var devicesByZoomOption: [CameraZoomOption: AVCaptureDevice] = [:]

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentRotationDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var recordingContinuation: CheckedContinuation<Recording?, Never>?

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

    func detachPreview() {
        previewRotationObservation = nil
        previewLayer?.session = nil
        previewLayer = nil
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
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func startRecording() {
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

        sessionQueue.async {
            self.switchToDevice(for: option)
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
            self.session.sessionPreset = .high

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
            if let ultraWide {
                devicesByZoomOption[.ultraWide] = ultraWide
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

                guard self.session.canAddOutput(self.movieOutput) else {
                    Task { @MainActor in
                        self.state.errorMessage = "Camera configuration failed."
                    }
                    return
                }

                self.session.addOutput(self.movieOutput)
                self.movieOutput.movieFragmentInterval = .invalid
                self.devicesByZoomOption = devicesByZoomOption
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

    nonisolated private func switchToDevice(for option: CameraZoomOption) {
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
            configureSlowMotion(on: device)

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
            Task { @MainActor in
                self?.applyPreviewRotation(angle: coordinator.videoRotationAngleForHorizonLevelPreview)
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
