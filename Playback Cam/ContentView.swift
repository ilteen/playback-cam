import SwiftUI

struct ContentView: View {
    @StateObject private var cameraService = CameraService()
    @State private var latestRecording: RecordingResult?

    var body: some View {
        Group {
            if let recording = latestRecording {
                PlaybackScreen(
                    recording: recording,
                    onDiscard: {
                        latestRecording = nil
                    },
                    onKeep: {
                        latestRecording = nil
                    }
                )
            } else {
                CameraScreen(
                    cameraService: cameraService,
                    onRecordingFinished: { result in
                        latestRecording = result
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct CameraScreen: View {
    @ObservedObject var cameraService: CameraService
    let onRecordingFinished: (RecordingResult) -> Void

    @State private var isStopping = false

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                CameraPreviewView(session: cameraService.session)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if let errorMessage = cameraService.errorMessage {
                    VStack {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.7), in: Capsule())
                        Spacer()
                    }
                    .padding(.top, 16)
                }

                if isLandscape {
                    HStack {
                        Spacer()
                        captureButton
                            .padding(.trailing, 28)
                    }
                } else {
                    VStack {
                        Spacer()
                        captureButton
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .background(.black)
        .onAppear {
            cameraService.startSessionIfNeeded()
        }
        .alert("Camera Access Required", isPresented: Binding(
            get: { cameraService.shouldShowPermissionAlert },
            set: { _ in cameraService.dismissPermissionAlert() }
        )) {
            Button("Open Settings") {
                cameraService.openSystemSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access to record slo-mo videos.")
        }
    }

    private var captureButton: some View {
        Button {
            if cameraService.isRecording {
                stopRecording()
            } else {
                cameraService.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 84, height: 84)
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.18), lineWidth: 1)
                    }

                if cameraService.isRecording {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.red)
                        .frame(width: 31, height: 31)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 70, height: 70)
                }
            }
            .overlay {
                if isStopping {
                    ProgressView()
                        .tint(.white)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 7, x: 0, y: 3)
        }
        .disabled(isStopping || cameraService.shouldShowPermissionAlert)
    }

    private func stopRecording() {
        guard !isStopping else { return }
        isStopping = true

        Task {
            if let result = await cameraService.stopRecording() {
                onRecordingFinished(result)
            }
            isStopping = false
        }
    }
}

#Preview {
    ContentView()
}
