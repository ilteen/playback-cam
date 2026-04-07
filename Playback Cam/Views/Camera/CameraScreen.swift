import SwiftUI
import UIKit

struct CameraScreen: View {
    @ObservedObject var viewModel: CameraViewModel
    let lastSavedRecording: Recording?
    let pendingGallerySaveRecording: Recording?
    let onOpenGallery: () -> Void
    let onGalleryThumbnailFrameChange: (CGRect?) -> Void
    let delaysSessionStart: Bool
    @State private var deviceOrientation = UIDevice.current.orientation
    @State private var hasStartedSession = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { proxy in
            let usesLandscapeControls = isPad

            ZStack {
                captureSurface
                    .ignoresSafeArea()

                CameraEdgeTreatment()
                    .ignoresSafeArea()

                if viewModel.showsDelayedPlaybackLoadingIndicator {
                    CameraDelayedPlaybackLoadingIndicator(
                        selectedDelayOption: viewModel.state.selectedDelayOption
                    )
                    .rotationEffect(delayInterfaceRotationAngle)
                    .animation(.spring(response: 0.28, dampingFraction: 0.84), value: delayInterfaceRotationAngle)
                }

                topOverlay

                controlsOverlay(isLandscape: usesLandscapeControls)
            }
            .background(.black)
            .animation(.easeInOut(duration: 0.2), value: usesLandscapeControls)
            .onPreferenceChange(GalleryThumbnailFramePreferenceKey.self, perform: onGalleryThumbnailFrameChange)
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateDeviceOrientation(with: UIDevice.current.orientation)
            startCameraSessionIfNeeded()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            hasStartedSession = false
            viewModel.onDisappear()
        }
        .onChange(of: delaysSessionStart) { _, _ in
            startCameraSessionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateDeviceOrientation(with: UIDevice.current.orientation)
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
            Text("Allow camera access to record video.")
        }
    }

    @ViewBuilder
    private var captureSurface: some View {
        if viewModel.isPreviewMode {
            CameraPreviewPlaceholder()
        } else {
            CameraPreviewContainer(
                session: viewModel.session,
                showsDelayedPlayback: viewModel.state.captureMode == .delayedPlayback && viewModel.state.isDelayedPlaybackReady,
                onPreviewLayerReady: viewModel.attachPreviewLayer,
                onDelayedPlaybackViewReady: viewModel.attachDelayedPlaybackView
            )
        }
    }

    private var topOverlay: some View {
        let horizontalInset: CGFloat = isPad ? 24 : 24
        let topInset: CGFloat = isPad ? 22 : horizontalInset

        return VStack(spacing: 12) {
            HStack {
                if !isPad {
                    Spacer(minLength: 0)
                    modeToggleButton
                        .rotationEffect(cameraAccessoryRotationAngle)
                        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: cameraAccessoryRotationAngle)
                }
            }

            if let errorMessage = viewModel.state.errorMessage {
                HStack {
                    CameraMessagePill(
                        icon: "exclamationmark.triangle.fill",
                        text: errorMessage
                    )
                    Spacer(minLength: 0)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, topInset)
        .padding(.horizontal, horizontalInset)
        .ignoresSafeArea(edges: isPad ? [] : .top)
    }

    @ViewBuilder
    private func controlsOverlay(isLandscape: Bool) -> some View {
        if isLandscape {
            let shutterSize: CGFloat = 98
            let galleryButtonSize: CGFloat = 48
            let verticalControlSpacing: CGFloat = isPad ? 38 : 14
            let landscapeControlLaneWidth: CGFloat = 98
            let zoomControlHeight: CGFloat = 46
            let modeButtonSize: CGFloat = 48
            let zoomYOffset = -((shutterSize / 2) + (zoomControlHeight / 2) + verticalControlSpacing)
            let modeToggleYOffset: CGFloat = if viewModel.showsZoomPicker {
                zoomYOffset - ((zoomControlHeight / 2) + (modeButtonSize / 2) + verticalControlSpacing)
            } else {
                -((shutterSize / 2) + (modeButtonSize / 2) + verticalControlSpacing)
            }
            let galleryYOffset = (shutterSize / 2) + (galleryButtonSize / 2) + verticalControlSpacing

            HStack {
                Spacer(minLength: 0)

                ZStack {
                    centerControl

                    zoomPicker
                        .offset(y: zoomYOffset)

                    if isPad {
                        modeToggleButton
                            .offset(y: modeToggleYOffset)
                    }

                    galleryButton
                        .offset(y: galleryYOffset)
                }
                .frame(width: landscapeControlLaneWidth)
                .frame(maxHeight: .infinity)
                .padding(.trailing, isPad ? 24 : -20)
            }
        } else {
            VStack {
                Spacer(minLength: 0)

                ZStack {
                    centerControl

                    HStack {
                        galleryButton
                            .rotationEffect(cameraAccessoryRotationAngle)
                            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: cameraAccessoryRotationAngle)
                            .padding(.leading, isPadLandscapeHeld ? -6 : (isPad ? 6 : 20))
                        Spacer()
                        zoomPicker
                            .rotationEffect(cameraAccessoryRotationAngle)
                            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: cameraAccessoryRotationAngle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isPadLandscapeHeld ? 0 : (isPad ? 20 : 35))
                .padding(.bottom, isPadLandscapeHeld ? 62 : (isPad ? 24 : 0))
            }
        }
    }

    @ViewBuilder
    private var centerControl: some View {
        if viewModel.state.captureMode == .slowMo {
            captureButton
        } else {
            delayPicker
        }
    }

    private var captureButton: some View {
        CameraShutterButton(
            isRecording: viewModel.state.isRecording && !viewModel.isStopping,
            action: viewModel.captureButtonTapped
        )
        .disabled(viewModel.isStopping || viewModel.shouldShowPermissionAlert)
    }

    private var delayPicker: some View {
        CameraDelayedPlaybackPicker(
            options: viewModel.state.availableDelayOptions,
            selectedOption: viewModel.state.selectedDelayOption,
            isDisabled: viewModel.isStopping || viewModel.shouldShowPermissionAlert,
            onSelect: viewModel.selectDelayedPlaybackOption
        )
        .rotationEffect(delayInterfaceRotationAngle)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: delayInterfaceRotationAngle)
        .frame(width: isPhoneLandscape ? 110 : nil, height: isPhoneLandscape ? 98 : nil)
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

    private var modeToggleButton: some View {
        CameraModeToggleButton(
            mode: viewModel.state.captureMode,
            isDisabled: viewModel.state.isRecording || viewModel.isStopping || viewModel.shouldShowPermissionAlert,
            action: viewModel.toggleCaptureMode
        )
    }

    @ViewBuilder
    private var galleryButton: some View {
        if let galleryPreviewRecording {
            CameraGalleryButton(
                videoURL: galleryPreviewRecording.videoURL,
                isDisabled: viewModel.state.isRecording || viewModel.isStopping || pendingGallerySaveRecording != nil,
                showsProgress: pendingGallerySaveRecording != nil,
                action: onOpenGallery
            )
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: GalleryThumbnailFramePreferenceKey.self,
                        value: proxy.frame(in: .named("app-root"))
                    )
                }
            }
        }
    }

    private var galleryPreviewRecording: Recording? {
        pendingGallerySaveRecording ?? lastSavedRecording
    }

    private var cameraAccessoryRotationAngle: Angle {
        guard !isPad else { return .zero }

        switch deviceOrientation {
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        default:
            return .zero
        }
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isPadLandscapeHeld: Bool {
        isPad && deviceOrientation.isLandscape
    }

    private var isPhoneLandscape: Bool {
        !isPad && deviceOrientation.isLandscape
    }

    private var delayInterfaceRotationAngle: Angle {
        isPhoneLandscape ? cameraAccessoryRotationAngle : .zero
    }

    private func updateDeviceOrientation(with orientation: UIDeviceOrientation) {
        guard orientation.isLandscape || orientation.isPortrait else { return }
        deviceOrientation = orientation
    }

    private func startCameraSessionIfNeeded() {
        guard !delaysSessionStart else { return }
        guard !hasStartedSession else { return }
        hasStartedSession = true
        viewModel.onAppear()
    }
}

private struct GalleryThumbnailFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
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
                ),
                lastSavedRecording: Recording(
                    videoURL: URL(fileURLWithPath: "/dev/null"),
                    createdAt: .now
                ),
                pendingGallerySaveRecording: nil,
                onOpenGallery: {},
                onGalleryThumbnailFrameChange: { _ in },
                delaysSessionStart: false
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Camera Portrait")

            CameraScreen(
                viewModel: .preview(
                    isRecording: true,
                    errorMessage: nil,
                    selectedZoomOption: .ultraWide
                ),
                lastSavedRecording: Recording(
                    videoURL: URL(fileURLWithPath: "/dev/null"),
                    createdAt: .now
                ),
                pendingGallerySaveRecording: nil,
                onOpenGallery: {},
                onGalleryThumbnailFrameChange: { _ in },
                delaysSessionStart: false
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Camera Landscape")
            .previewInterfaceOrientation(.landscapeRight)

            CameraScreen(
                viewModel: .preview(
                    isRecording: false,
                    errorMessage: nil,
                    selectedZoomOption: .wide,
                    captureMode: .delayedPlayback,
                    selectedDelayOption: .five,
                    isDelayedPlaybackReady: false
                ),
                lastSavedRecording: Recording(
                    videoURL: URL(fileURLWithPath: "/dev/null"),
                    createdAt: .now
                ),
                pendingGallerySaveRecording: nil,
                onOpenGallery: {},
                onGalleryThumbnailFrameChange: { _ in },
                delaysSessionStart: false
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Delayed Playback")
        }
    }
}
#endif
