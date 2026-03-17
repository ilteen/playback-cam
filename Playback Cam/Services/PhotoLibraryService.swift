import Photos

enum PhotoLibrarySaveResult {
    case saved
    case denied
    case failed
}

protocol RecordingSaving {
    func save(recording: Recording) async -> PhotoLibrarySaveResult
}

struct PhotoLibraryService: RecordingSaving {
    func save(recording: Recording) async -> PhotoLibrarySaveResult {
        let authorizationStatus = await requestAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return .denied
        }

        let success = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: recording.videoURL)
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }

        return success ? .saved : .failed
    }

    private func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
