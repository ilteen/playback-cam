import AVFAudio
import SwiftUI

@main
struct PlaybackCamApp: App {
    @StateObject private var appViewModel = AppViewModel()

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            AppView(viewModel: appViewModel)
        }
    }
}
