import Foundation

struct PlaybackState {
    var isPlaying = false
    var isScrubbing = false
    var duration: Double = 0.01
    var currentTime: Double = 0
    var frameDuration: Double = 1.0 / 30.0

    var scrubFraction: Double {
        min(max(currentTime / max(duration, 0.01), 0), 1)
    }
}
