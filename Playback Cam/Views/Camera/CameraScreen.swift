import SwiftUI

struct CameraScreen: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let usesLandscapeControls = isLandscape || isRegularRegularSizeClass

            ZStack {
                captureSurface
                    .ignoresSafeArea()

                CameraEdgeTreatment()
                    .ignoresSafeArea()

                if let errorMessage = viewModel.state.errorMessage {
                    VStack {
                        CameraMessagePill(
                            icon: "exclamationmark.triangle.fill",
                            text: errorMessage
                        )
                        .padding(.top, 14)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                }

                controlsOverlay(isLandscape: usesLandscapeControls)
            }
            .background(.black)
            .animation(.easeInOut(duration: 0.2), value: usesLandscapeControls)
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.state.isRecording)
        .alert("Camera Access Required", isPresented: Binding(
            get: { viewModel.shouldShowPermissionAlert },
            set: { _ in viewModel.dismissPermissionAlert() }
        )) {
            Button("Open Settings") {
                guard let settingsURL = viewModel.settingsURL else { return }
                openURL(settingsURL)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access to record slo-mo videos.")
        }
    }

    @ViewBuilder
    private var captureSurface: some View {
        if viewModel.isPreviewMode {
            CameraPreviewPlaceholder()
        } else {
            CameraPreviewContainer(
                session: viewModel.session,
                onPreviewLayerReady: viewModel.attachPreviewLayer
            )
        }
    }

    @ViewBuilder
    private func controlsOverlay(isLandscape: Bool) -> some View {
        if isLandscape {
            HStack(spacing: 16) {
                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    zoomPicker
                    captureButton
                }
                .padding(.bottom, 25)
            }
        } else {
            VStack {
                Spacer(minLength: 0)

                ZStack {
                    captureButton

                    HStack {
                        Spacer()
                        zoomPicker
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 35)
            }
        }
    }

    private var captureButton: some View {
        CameraShutterButton(
            isRecording: viewModel.state.isRecording && !viewModel.isStopping,
            action: viewModel.captureButtonTapped
        )
        .disabled(viewModel.isStopping || viewModel.shouldShowPermissionAlert)
    }

    @ViewBuilder
    private var zoomPicker: some View {
        if viewModel.showsZoomPicker {
            CameraZoomPicker(
                options: viewModel.state.availableZoomOptions,
                selectedOption: viewModel.state.selectedZoomOption,
                isDisabled: viewModel.state.isRecording || viewModel.isStopping,
                onSelect: viewModel.selectZoomOption
            )
        }
    }

    private var isRegularRegularSizeClass: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

#if DEBUG
struct CameraScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CameraScreen(
                viewModel: .preview(
                    isRecording: false,
                    errorMessage: nil,
                    selectedZoomOption: .wide
                )
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Camera Portrait")

            CameraScreen(
                viewModel: .preview(
                    isRecording: true,
                    errorMessage: nil,
                    selectedZoomOption: .ultraWide
                )
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Camera Landscape")
            .previewInterfaceOrientation(.landscapeRight)
        }
    }
}
#endif
