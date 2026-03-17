import Foundation

enum PlaybackRateOption: String, CaseIterable, Identifiable {
    case quarter = "0.25"
    case half = "0.5"
    case full = "1"

    var id: String { rawValue }

    var rate: Double {
        switch self {
        case .quarter:
            return 0.25
        case .half:
            return 0.5
        case .full:
            return 1.0
        }
    }
}
