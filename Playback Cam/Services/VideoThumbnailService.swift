@preconcurrency import AVFoundation
import CoreGraphics
import UIKit

enum VideoThumbnailService {
    private static let cache = NSCache<NSURL, UIImage>()

    static func cachedImage(for videoURL: URL) -> UIImage? {
        cache.object(forKey: videoURL as NSURL)
    }

    static func prepareThumbnail(
        for videoURL: URL,
        maximumSize: CGSize = CGSize(width: 192, height: 192)
    ) async -> UIImage? {
        if let cached = cachedImage(for: videoURL) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: videoURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = maximumSize

                let generatedImage = try? generator.copyCGImage(
                    at: CMTime(seconds: 0, preferredTimescale: 600),
                    actualTime: nil
                )

                let image = generatedImage.map(UIImage.init(cgImage:))
                if let image {
                    cache.setObject(image, forKey: videoURL as NSURL)
                }

                continuation.resume(returning: image)
            }
        }
    }
}
