import Combine

@MainActor
final class PlaybackSettingsStore: ObservableObject {
    @Published var selectedRate: PlaybackRateOption = .quarter
}

