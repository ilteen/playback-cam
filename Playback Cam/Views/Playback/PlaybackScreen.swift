import SwiftUI

struct PlaybackScreen: View {
    @ObservedObject var viewModel: PlaybackViewModel
    private let showsBackground: Bool
    private let showsPlaybackSurface: Bool
    private let showsEdgeTreatment: Bool
    private let managesPlayerLifecycle: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(
        viewModel: PlaybackViewModel,
        showsBackground: Bool = true,
        showsPlaybackSurface: Bool = true,
        showsEdgeTreatment: Bool = true,
        managesPlayerLifecycle: Bool = true
    ) {
        self.viewModel = viewModel
        self.showsBackground = showsBackground
        self.showsPlaybackSurface = showsPlaybackSurface
        self.showsEdgeTreatment = showsEdgeTreatment
        self.managesPlayerLifecycle = managesPlayerLifecycle
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let usesLandscapeControls = isLandscape || isRegularRegularSizeClass
            let usesDeferredSystemGestures = usesLandscapeControls

            ZStack {
                if showsBackground {
                    Color.black.ignoresSafeArea()
                }

                if showsPlaybackSurface {
                    playbackSurface
                        .ignoresSafeArea()
                }

                if showsEdgeTreatment {
                    PlaybackEdgeTreatment()
                        .ignoresSafeArea()
                }

                topOverlay(isLandscape: usesLandscapeControls)

                controlsOverlay(isLandscape: usesLandscapeControls)

                scrubOverlay(isLandscape: usesLandscapeControls)

                if let saveMessage = viewModel.saveMessage {
                    saveToast(message: saveMessage, isLandscape: usesLandscapeControls)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: usesLandscapeControls)
            .persistentSystemOverlays(usesDeferredSystemGestures ? .hidden : .visible)
            .defersSystemGestures(on: usesDeferredSystemGestures ? .bottom : [])
        }
        .onAppear {
            guard managesPlayerLifecycle else { return }
            viewModel.onAppear()
        }
        .onDisappear {
            guard managesPlayerLifecycle else { return }
            viewModel.onDisappear()
        }
    }

    @ViewBuilder
    private var playbackSurface: some View {
        if viewModel.isPreviewMode {
            PlaybackPreviewPlaceholder()
        } else {
            PlaybackPlayerView(player: viewModel.player)
                .allowsHitTesting(false)
        }
    }

    private func topOverlay(isLandscape: Bool) -> some View {
        VStack {
            HStack {
                Button(action: viewModel.discardRecording) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background {
                            Circle()
                                .fill(.black.opacity(0.7))
                        }
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        }
                }
                .buttonStyle(PlaybackPressStyle())

                Spacer(minLength: 0)

                if viewModel.showsSaveButton {
                    Button(action:  viewModel.saveToPhotoLibrary) {
                        Image(systemName: "square.and.arrow.down")
                            .padding(.bottom, 5)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background {
                                Circle()
                                    .fill(.black.opacity(0.7))
                            }
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.14), lineWidth: 1)
                            }
                }
                .buttonStyle(PlaybackPressStyle())
                .opacity(viewModel.isSaving ? 0.42 : 1)
                .overlay {
                    if viewModel.isSaving {
                        ProgressView()
                                .tint(.white)
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, isLandscape ? 0 : 10)

            Spacer(minLength: 0)
        }
    }

    private func scrubOverlay(isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 12) {
                KnoblessScrubBar(
                    progress: viewModel.state.scrubFraction,
                    onScrubStart: viewModel.beginScrubbing,
                    onScrub: viewModel.scrub,
                    onScrubEnded: viewModel.endScrubbing
                )
                .frame(height: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .padding(.horizontal, isLandscape ? 108 : 12)
            .padding(.bottom, isLandscape ? 12 : 100)
        }
    }

    @ViewBuilder
    private func controlsOverlay(isLandscape: Bool) -> some View {
        if isLandscape {
            let overlayHorizontalInset: CGFloat = 0
            let topActionButtonSize: CGFloat = 50
            let landscapeControlLaneWidth: CGFloat = 82
            let landscapeControlLaneTrailingInset = overlayHorizontalInset - ((landscapeControlLaneWidth - topActionButtonSize) / 2)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    VStack {
                        Spacer(minLength: 0)

                        speedPicker(isLandscape: true)
                            .background {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .fill(.black.opacity(0.7))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(.white.opacity(0.14), lineWidth: 1)
                            }
                            .padding(.bottom, -26)
                    }

                    VStack(spacing: 14) {
                        transportButton(
                            systemName: "backward.end.fill",
                            action: { viewModel.stepFrame(by: -1) },
                            doubleAction: { viewModel.stepFrame(by: -10) },
                            holdAction: { viewModel.beginTransportPlayback(direction: -1) },
                            holdEndAction: viewModel.endTransportPlayback
                        )

                        playPauseButton(size: 40)

                        transportButton(
                            systemName: "forward.end.fill",
                            action: { viewModel.stepFrame(by: 1) },
                            doubleAction: { viewModel.stepFrame(by: 10) },
                            holdAction: { viewModel.beginTransportPlayback(direction: 1) },
                            holdEndAction: viewModel.endTransportPlayback
                        )
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.black.opacity(0.7))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }
                }
                .frame(width: landscapeControlLaneWidth)
                .frame(maxHeight: .infinity)
                .padding(.trailing, landscapeControlLaneTrailingInset)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    HStack(spacing: 12) {
                        transportButton(
                            systemName: "backward.end.fill",
                            action: { viewModel.stepFrame(by: -1) },
                            doubleAction: { viewModel.stepFrame(by: -10) },
                            holdAction: { viewModel.beginTransportPlayback(direction: -1) },
                            holdEndAction: viewModel.endTransportPlayback
                        )

                        playPauseButton(size: 40)

                        transportButton(
                            systemName: "forward.end.fill",
                            action: { viewModel.stepFrame(by: 1) },
                            doubleAction: { viewModel.stepFrame(by: 10) },
                            holdAction: { viewModel.beginTransportPlayback(direction: 1) },
                            holdEndAction: viewModel.endTransportPlayback
                        )
                        
                    }
                    .padding(7)
                    .background {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.black.opacity(0.7))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                    HStack {
                        Spacer()
                        speedPicker(isLandscape: false)
                            .background {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .fill(.black.opacity(0.7))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(.white.opacity(0.14), lineWidth: 1)
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
        }
    }

    private func speedPicker(isLandscape: Bool) -> some View {
        Picker("Playback Speed", selection: Binding(
            get: { viewModel.selectedRate },
            set: { viewModel.selectPlaybackRate($0) }
        )) {
            ForEach(PlaybackRateOption.allCases) { option in
                Text(option.rawValue)
                    .tag(option)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: isLandscape ? 82 : 76, height: isLandscape ? 120 : 96)
        .clipped()
    }

    private func playPauseButton(size: CGFloat) -> some View {
        Button {
            viewModel.togglePlayback()
        } label: {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.96))

                Image(systemName: viewModel.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
        }
        .buttonStyle(PlaybackPressStyle())
    }

    private func transportButton(
        systemName: String,
        action: @escaping () -> Void,
        doubleAction: @escaping () -> Void,
        holdAction: @escaping () -> Void,
        holdEndAction: @escaping () -> Void
    ) -> some View {
        PlaybackTransportButton(
            systemName: systemName,
            action: action,
            doubleAction: doubleAction,
            holdAction: holdAction,
            holdEndAction: holdEndAction
        )
    }

    private func saveToast(message: String, isLandscape: Bool) -> some View {
        VStack {
            Spacer(minLength: 0)

            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    Capsule()
                        .fill(.black.opacity(0.38))
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .padding(.bottom, isLandscape ? 28 : 150)
        }
    }

    private var isRegularRegularSizeClass: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

#if DEBUG
struct PlaybackScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PlaybackScreen(
                viewModel: .preview(
                    isPlaying: false,
                    currentTime: 3.42,
                    duration: 12.84,
                    selectedRate: .quarter
                )
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Playback Portrait")

            PlaybackScreen(
                viewModel: .preview(
                    isPlaying: true,
                    currentTime: 7.18,
                    duration: 12.84,
                    selectedRate: .half
                )
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Playback Landscape")
            .previewInterfaceOrientation(.landscapeRight)
        }
    }
}
#endif
