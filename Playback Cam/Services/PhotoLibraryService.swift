@preconcurrency import AVFoundation
import Foundation
import Photos

enum PhotoLibrarySaveResult {
    case saved(Recording)
    case denied
    case failed
}

protocol RecordingSaving {
    func save(recording: Recording, playbackRate: PlaybackRateOption) async -> PhotoLibrarySaveResult
}

struct PhotoLibraryService: RecordingSaving {
    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession

        init(session: AVAssetExportSession) {
            self.session = session
        }
    }

    func save(recording: Recording, playbackRate: PlaybackRateOption) async -> PhotoLibrarySaveResult {
        let authorizationStatus = await requestAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return .denied
        }

        guard let exportURL = await exportRetimedVideo(for: recording, playbackRate: playbackRate) else {
            return .failed
        }

        let success = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: exportURL)
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }

        guard success else {
            try? FileManager.default.removeItem(at: exportURL)
            return .failed
        }

        return .saved(
            Recording(
                videoURL: exportURL,
                createdAt: recording.createdAt,
                basePlaybackRate: playbackRate.rate
            )
        )
    }

    private func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func exportRetimedVideo(for recording: Recording, playbackRate: PlaybackRateOption) async -> URL? {
        let asset = AVURLAsset(url: recording.videoURL)

        guard
            let duration = try? await asset.load(.duration),
            let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
        else {
            return nil
        }

        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        do {
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack,
                at: .zero
            )
        } catch {
            return nil
        }

        if let preferredTransform = try? await videoTrack.load(.preferredTransform) {
            compositionVideoTrack.preferredTransform = preferredTransform
        }

        let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / playbackRate.rate)
        compositionVideoTrack.scaleTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            toDuration: scaledDuration
        )

        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            do {
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack,
                    at: .zero
                )
                compositionAudioTrack.scaleTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    toDuration: scaledDuration
                )
            } catch {
                return nil
            }
        }

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-gallery-\(recording.id.uuidString).mov")

        try? FileManager.default.removeItem(at: exportURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            return nil
        }

        exportSession.outputURL = exportURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false

        do {
            if #available(iOS 18, *) {
                try await exportSession.export(to: exportURL, as: .mov)
            } else {
                let exportSessionBox = ExportSessionBox(session: exportSession)
                let status = await withCheckedContinuation { continuation in
                    exportSessionBox.session.exportAsynchronously {
                        continuation.resume(returning: exportSessionBox.session.status)
                    }
                }

                guard status == .completed else {
                    throw exportSession.error ?? NSError(domain: "PlaybackCam.Export", code: -1)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: exportURL)
            return nil
        }

        return exportURL
    }
}
