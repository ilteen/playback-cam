//
//  Playback_CamApp.swift
//  Playback Cam
//
//  Created by Philipp on 22.02.26.
//

import SwiftUI
import AVFAudio

@main
struct Playback_CamApp: App {
    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
