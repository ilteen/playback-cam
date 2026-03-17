import SwiftUI

struct AppView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let playbackViewModel = viewModel.playbackViewModel {
                PlaybackScreen(viewModel: playbackViewModel)
            } else {
                CameraScreen(viewModel: viewModel.cameraViewModel)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView(viewModel: .preview())
    }
}
#endif
