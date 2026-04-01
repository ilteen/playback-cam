import Foundation

struct Recording: Equatable, Identifiable {
    let id: UUID
    let videoURL: URL
    let createdAt: Date
    let basePlaybackRate: Double
    let photoLibraryAssetIdentifier: String?

    init(
        id: UUID = UUID(),
        videoURL: URL,
        createdAt: Date,
        basePlaybackRate: Double = 1.0,
        photoLibraryAssetIdentifier: String? = nil
    ) {
        self.id = id
        self.videoURL = videoURL
        self.createdAt = createdAt
        self.basePlaybackRate = basePlaybackRate
        self.photoLibraryAssetIdentifier = photoLibraryAssetIdentifier
    }
}
