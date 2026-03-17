import Foundation

struct Recording: Equatable, Identifiable {
    let id: UUID
    let videoURL: URL
    let createdAt: Date

    init(id: UUID = UUID(), videoURL: URL, createdAt: Date) {
        self.id = id
        self.videoURL = videoURL
        self.createdAt = createdAt
    }
}
