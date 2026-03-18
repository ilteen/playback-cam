import SwiftUI

struct GalleryScreen: View {
    let reviewViewModel: PlaybackViewModel?
    let onClose: () -> Void

    @State private var selectedIndex: Int
    @State private var savedViewModels: [PlaybackViewModel]

    init(
        recordings: [Recording],
        initialIndex: Int,
        playbackSettings: PlaybackSettingsStore,
        reviewViewModel: PlaybackViewModel? = nil,
        onClose: @escaping () -> Void
    ) {
        self.reviewViewModel = reviewViewModel
        self.onClose = onClose

        let boundedIndex = min(max(initialIndex, 0), max(recordings.count - 1, 0))
        _selectedIndex = State(initialValue: reviewViewModel == nil ? boundedIndex : recordings.count)
        _savedViewModels = State(
            initialValue: recordings.map { recording in
                PlaybackViewModel(
                    galleryRecording: recording,
                    playbackSettings: playbackSettings,
                    onClose: onClose
                )
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if !allViewModels.isEmpty {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(allViewModels.enumerated()), id: \.element.recording.id) { index, viewModel in
                            GalleryVideoPage(viewModel: viewModel)
                                .id("\(viewModel.recording.id.uuidString)-\(isLandscape)")
                                .tag(index)
                        }
                    }
                    .id(isLandscape)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()

                    if let currentViewModel {
                        PlaybackScreen(
                            viewModel: currentViewModel,
                            showsBackground: false,
                            showsPlaybackSurface: false,
                            showsEdgeTreatment: true,
                            managesPlayerLifecycle: false
                        )
                        .id("\(currentViewModel.recording.id.uuidString)-\(isLandscape)")
                    }
                }
            }
        }
    }

    private var currentViewModel: PlaybackViewModel? {
        guard allViewModels.indices.contains(selectedIndex) else { return nil }
        return allViewModels[selectedIndex]
    }

    private var allViewModels: [PlaybackViewModel] {
        if let reviewViewModel {
            return savedViewModels + [reviewViewModel]
        }

        return savedViewModels
    }
}

private struct GalleryVideoPage: View {
    @ObservedObject var viewModel: PlaybackViewModel

    var body: some View {
        PlaybackPlayerView(player: viewModel.player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .background(.black)
            .allowsHitTesting(false)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
}
