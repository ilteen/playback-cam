import Foundation

struct CameraSessionState {
    var isRecording = false
    var errorMessage: String?
    var availableZoomOptions: [CameraZoomOption] = [.wide]
    var selectedZoomOption: CameraZoomOption = .wide
    var requiresPermissionAlert = false
}
