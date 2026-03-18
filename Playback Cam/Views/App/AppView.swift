import SwiftUI
import UIKit

struct AppView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var galleryThumbnailFrame: CGRect?
    @State private var showsPlaybackTransitionCover = false
    private let orientationController = AppOrientationController.shared

    var body: some View {
        ZStack {
            ZStack {
                if let playbackViewModel = viewModel.playbackViewModel {
                    GalleryScreen(
                        recordings: viewModel.sessionSavedRecordings,
                        initialIndex: viewModel.sessionSavedRecordings.count,
                        playbackSettings: viewModel.playbackSettings,
                        reviewViewModel: playbackViewModel,
                        onClose: viewModel.discardActivePlayback
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                } else if let galleryStartIndex = viewModel.galleryStartIndex {
                    GalleryScreen(
                        recordings: viewModel.sessionSavedRecordings,
                        initialIndex: galleryStartIndex,
                        playbackSettings: viewModel.playbackSettings,
                        onClose: viewModel.closeGallery
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                } else {
                    CameraScreen(
                        viewModel: viewModel.cameraViewModel,
                        lastSavedRecording: viewModel.lastSessionSavedRecording,
                        pendingGallerySaveRecording: viewModel.pendingGallerySaveRecording,
                        onOpenGallery: viewModel.openGallery,
                        onGalleryThumbnailFrameChange: { galleryThumbnailFrame = $0 },
                        delaysSessionStart: false
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: routeIdentity)

            if showsPlaybackTransitionCover {
                Color.black
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "app-root")
        .preferredColorScheme(.dark)
        .statusBar(hidden: !usesPlaybackOrientation)
        .onAppear(perform: updateOrientationPolicy)
        .onChange(of: pendingPlaybackID) { _, newValue in
            guard newValue != nil else { return }

            if shouldHideLandscapeReviewRotation {
                showsPlaybackTransitionCover = true
                orientationController.applyPlaybackPolicy()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    viewModel.presentPendingPlayback()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    showsPlaybackTransitionCover = false
                }
            } else {
                viewModel.presentPendingPlayback()
                updateOrientationPolicy()
            }
        }
        .onChange(of: reviewPlaybackID) { _, _ in
            updateOrientationPolicy()
        }
        .onChange(of: viewModel.galleryStartIndex) { _, _ in
            updateOrientationPolicy()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            updateOrientationPolicy()
        }
    }

    private var usesPlaybackOrientation: Bool {
        viewModel.playbackViewModel != nil || viewModel.galleryStartIndex != nil
    }

    private var reviewPlaybackID: UUID? {
        viewModel.playbackViewModel?.recording.id
    }

    private var pendingPlaybackID: UUID? {
        viewModel.pendingPlaybackRecording?.id
    }

    private var routeIdentity: String {
        if let playbackID = viewModel.playbackViewModel?.recording.id {
            return "playback-\(playbackID.uuidString)"
        }

        if let galleryStartIndex = viewModel.galleryStartIndex {
            return "gallery-\(galleryStartIndex)-\(viewModel.sessionSavedRecordings.count)"
        }

        return "camera"
    }

    private var shouldHideLandscapeReviewRotation: Bool {
        UIDevice.current.userInterfaceIdiom == .phone &&
        UIDevice.current.orientation.isLandscape
    }

    private func updateOrientationPolicy() {
        if usesPlaybackOrientation {
            orientationController.applyPlaybackPolicy()
        } else {
            orientationController.applyCameraPolicy()
        }
    }
}

private struct GalleryTransitionThumbnail: View {
    let thumbnailImage: UIImage?
    let sideLength: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: sideLength, height: sideLength)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.black)
                    .frame(width: sideLength, height: sideLength)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(cornerRadius > 0 ? 0.18 : 0), lineWidth: 1)
        }
    }
}

#if DEBUG
struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView(viewModel: .preview())
    }
}
#endif
