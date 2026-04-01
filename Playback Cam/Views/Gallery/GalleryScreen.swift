import SwiftUI

struct GalleryScreen: View {
    private enum ActiveAlert: Identifiable {
        case deleteFailed(String)

        var id: String {
            switch self {
            case let .deleteFailed(message):
                return "error-\(message)"
            }
        }
    }

    let reviewViewModel: PlaybackViewModel?
    let onDeleteRecording: (Recording) async -> PhotoLibraryDeleteResult
    let onClose: () -> Void

    @State private var selectedIndex: Int
    @State private var savedViewModels: [PlaybackViewModel]
    @State private var activeAlert: ActiveAlert?
    @State private var deletingRecordingID: UUID?

    init(
        recordings: [Recording],
        initialIndex: Int,
        playbackSettings: PlaybackSettingsStore,
        reviewViewModel: PlaybackViewModel? = nil,
        onDeleteRecording: @escaping (Recording) async -> PhotoLibraryDeleteResult,
        onClose: @escaping () -> Void
    ) {
        self.reviewViewModel = reviewViewModel
        self.onDeleteRecording = onDeleteRecording
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

                    if let currentSavedRecording {
                        deleteOverlay(
                            isLandscape: isLandscape,
                            recording: currentSavedRecording
                        )
                    }
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case let .deleteFailed(message):
                return Alert(
                    title: Text("Delete failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var currentViewModel: PlaybackViewModel? {
        guard allViewModels.indices.contains(selectedIndex) else { return nil }
        return allViewModels[selectedIndex]
    }

    private var currentSavedRecording: Recording? {
        guard savedViewModels.indices.contains(selectedIndex) else { return nil }
        return savedViewModels[selectedIndex].recording
    }

    private var allViewModels: [PlaybackViewModel] {
        if let reviewViewModel {
            return savedViewModels + [reviewViewModel]
        }

        return savedViewModels
    }

    private func deleteOverlay(isLandscape: Bool, recording: Recording) -> some View {
        let edgeInset: CGFloat
        if isPad {
            edgeInset = 46
        } else if isLandscape {
            edgeInset = 0
        } else {
            edgeInset = 24
        }

        let topInset: CGFloat = if isPad {
            22
        } else if isLandscape {
            10
        } else {
            edgeInset
        }

        return VStack {
            HStack {
                Spacer(minLength: 0)

                Button {
                    guard deletingRecordingID == nil else { return }
                    delete(recording)
                } label: {
                    Image(systemName: "trash")
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
                .disabled(deletingRecordingID != nil)
                .opacity(deletingRecordingID == nil ? 1 : 0.42)
                .overlay {
                    if deletingRecordingID == recording.id {
                        ProgressView()
                            .tint(.white)
                    }
                }
        }
        .padding(.top, topInset)
        .padding(.horizontal, edgeInset)

        Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: (!isPad && !isLandscape) ? .top : [])
    }

    private func delete(_ recording: Recording) {
        guard deletingRecordingID == nil else { return }
        deletingRecordingID = recording.id

        Task {
            let result = await onDeleteRecording(recording)

            await MainActor.run {
                deletingRecordingID = nil

                switch result {
                case .deleted:
                    removeDeletedRecording(withID: recording.id)

                case .denied:
                    activeAlert = .deleteFailed(String(localized: "Photo Library access was denied."))

                case .failed:
                    activeAlert = .deleteFailed(String(localized: "The video could not be removed from Photos."))
                }
            }
        }
    }

    private func removeDeletedRecording(withID recordingID: UUID) {
        guard let removedIndex = savedViewModels.firstIndex(where: { $0.recording.id == recordingID }) else { return }

        savedViewModels.remove(at: removedIndex)

        if allViewModels.isEmpty {
            onClose()
            return
        }

        selectedIndex = min(selectedIndex, allViewModels.count - 1)
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
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
