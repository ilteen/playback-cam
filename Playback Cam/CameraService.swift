import AVFoundation
import Combine
import SwiftUI
import UIKit

struct RecordingResult {
    let videoURL: URL
    let createdAt: Date
}

@MainActor
final class CameraService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var captureFPS: Double?
    @Published private(set) var shouldShowPermissionAlert = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "playbackcam.session.queue")
    private let movieOutput = AVCaptureMovieFileOutput()

    private var configured = false
    private var recordingContinuation: CheckedContinuation<RecordingResult?, Never>?

    func startSessionIfNeeded() {
        guard !configured else {
            startRunningSession()
            return
        }

        Task {
            let granted = await requestPermissions()
            guard granted else {
                shouldShowPermissionAlert = true
                return
            }

            configureSession()
            startRunningSession()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        guard configured else {
            errorMessage = "Camera setup not finished."
            return
        }

        errorMessage = nil
        isRecording = true

        sessionQueue.async {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("capture-\(UUID().uuidString).mov")

            try? FileManager.default.removeItem(at: fileURL)
            if let connection = self.movieOutput.connection(with: .video),
               connection.isVideoOrientationSupported {
                connection.videoOrientation = self.currentVideoOrientation()
            }
            self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        }
    }

    func stopRecording() async -> RecordingResult? {
        guard isRecording else { return nil }

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

    func openSystemSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    func dismissPermissionAlert() {
        shouldShowPermissionAlert = false
    }

    private func requestPermissions() async -> Bool {
        let camera = await AVCaptureDevice.requestAccess(for: .video)
        guard camera else { return false }
        return true
    }

    private func startRunningSession() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func configureSession() {
        sessionQueue.sync {
            guard !self.configured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            defer {
                self.session.commitConfiguration()
            }

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                Task { @MainActor in
                    self.errorMessage = "Back camera unavailable."
                }
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: camera)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                }

                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                    self.movieOutput.movieFragmentInterval = .invalid
                }

                let fps = self.configureSlowMotion(on: camera)
                Task { @MainActor in
                    self.captureFPS = fps
                }

                self.configured = true
            } catch {
                Task { @MainActor in
                    self.errorMessage = "Camera configuration failed."
                }
            }
        }
    }

    private func configureSlowMotion(on device: AVCaptureDevice) -> Double {
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
            return 30
        }

        return targetFPS
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .portrait
        }

        switch scene.interfaceOrientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        Task { @MainActor in
            self.isRecording = false

            let result: RecordingResult?
            if error == nil {
                result = RecordingResult(videoURL: outputFileURL, createdAt: Date())
            } else {
                result = nil
                try? FileManager.default.removeItem(at: outputFileURL)
                self.errorMessage = "Recording failed."
            }

            self.recordingContinuation?.resume(returning: result)
            self.recordingContinuation = nil
        }
    }
}
