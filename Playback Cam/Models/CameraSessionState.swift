import Foundation

enum CameraCaptureMode: String, CaseIterable {
    case slowMo
    case delayedPlayback

    var toggleMode: CameraCaptureMode {
        switch self {
        case .slowMo:
            return .delayedPlayback
        case .delayedPlayback:
            return .slowMo
        }
    }

    var symbolName: String {
        switch self {
        case .slowMo:
            return "slowmo"
        case .delayedPlayback:
            return "circle.dotted.and.circle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .slowMo:
            return String(localized: "Slow motion recording mode")
        case .delayedPlayback:
            return String(localized: "Delayed video playback mode")
        }
    }

    var toggleSymbolName: String {
        toggleMode.symbolName
    }

    var toggleAccessibilityLabel: String {
        switch toggleMode {
        case .slowMo:
            return String(localized: "Switch to slow motion recording mode")
        case .delayedPlayback:
            return String(localized: "Switch to delayed video playback mode")
        }
    }
}

enum DelayedPlaybackDelayOption: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case five = 5
    case ten = 10
    case twenty = 20

    var id: Int { rawValue }

    var duration: TimeInterval {
        Double(rawValue)
    }

    var label: String {
        "\(rawValue)"
    }

    var accessibilityLabel: String {
        if rawValue == 1 {
            return String(localized: "1-second delay")
        }

        return String(
            format: String(localized: "%d-second delay"),
            locale: .current,
            rawValue
        )
    }
}

struct CameraSessionState {
    var isRecording = false
    var errorMessage: String?
    var availableZoomOptions: [CameraZoomOption] = [.wide]
    var selectedZoomOption: CameraZoomOption = .wide
    var requiresPermissionAlert = false
    var captureMode: CameraCaptureMode = .slowMo
    var availableDelayOptions: [DelayedPlaybackDelayOption] = DelayedPlaybackDelayOption.allCases
    var selectedDelayOption: DelayedPlaybackDelayOption = .two
    var isDelayedPlaybackReady = false
}
