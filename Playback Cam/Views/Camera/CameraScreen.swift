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
            let shutterSize: CGFloat = 98
            let galleryButtonSize: CGFloat = 48
            let verticalControlSpacing: CGFloat = 14
            let landscapeControlLaneWidth: CGFloat = 98
            let zoomControlHeight: CGFloat = 46
            let zoomYOffset = -((shutterSize / 2) + (zoomControlHeight / 2) + verticalControlSpacing)
            let galleryYOffset = (shutterSize / 2) + (galleryButtonSize / 2) + verticalControlSpacing

            HStack {
                Spacer(minLength: 0)

                ZStack {
                    captureButton

                    zoomPicker
                        .offset(y: zoomYOffset)

                    galleryButton
                        .offset(y: galleryYOffset)
                }
                .frame(width: landscapeControlLaneWidth)
                .frame(maxHeight: .infinity)
                .padding(.trailing, -20)
            }
        } else {
            VStack {
                Spacer(minLength: 0)

                ZStack {
                    captureButton

                    HStack {
                        galleryButton
                            .rotationEffect(cameraAccessoryRotationAngle)
                            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: cameraAccessoryRotationAngle)
                            .padding(.leading, 20)
                        Spacer()
                        zoomPicker
                            .rotationEffect(cameraAccessoryRotationAngle)
                            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: cameraAccessoryRotationAngle)
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

    private var isRegularRegularSizeClass: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    private var galleryPreviewRecording: Recording? {
        pendingGallerySaveRecording ?? lastSavedRecording
    }

    private var cameraAccessoryRotationAngle: Angle {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .zero }

        switch deviceOrientation {
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        default:
            return .zero
        }
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
        }
    }
}
#endif
