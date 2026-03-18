import Foundation

struct Recording: Equatable, Identifiable {
    let id: UUID
    let videoURL: URL
    let createdAt: Date
    let basePlaybackRate: Double

    init(
        id: UUID = UUID(),
        videoURL: URL,
        createdAt: Date,
        basePlaybackRate: Double = 1.0
    ) {
        self.id = id
        self.videoURL = videoURL
        self.createdAt = createdAt
        self.basePlaybackRate = basePlaybackRate
    }
}
