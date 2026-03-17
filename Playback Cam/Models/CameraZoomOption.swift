import Foundation

enum CameraZoomOption: String, CaseIterable, Identifiable {
    case ultraWide = "0.5"
    case wide = "1"

    var id: String { rawValue }

    var label: String {
        "\(rawValue)"
    }
}
