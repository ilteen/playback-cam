@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.11),
                    Color(red: 0.15, green: 0.16, blue: 0.18),
                    Color(red: 0.05, green: 0.05, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 14)
                .offset(x: -90, y: -180)

            Circle()
                .fill(Color(red: 0.96, green: 0.74, blue: 0.42).opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 20)
                .offset(x: 110, y: 180)

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
                .padding(24)
        }
    }
}

struct CameraEdgeTreatment: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.36), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [.clear, .black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
        }
    }
}

struct CameraMessagePill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.52, blue: 0.31))

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.black.opacity(0.42))
        }
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }
}

struct CameraGalleryButton: View {
    let videoURL: URL
    let isDisabled: Bool
    let showsProgress: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CameraGalleryThumbnail(
                videoURL: videoURL,
                sideLength: 48,
                showsProgress: showsProgress
            )
        }
        .buttonStyle(CameraPressStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
    }
}

struct CameraGalleryThumbnail: View {
    let videoURL: URL
    let sideLength: CGFloat
    let showsProgress: Bool

    @State private var thumbnailImage: UIImage?

    private let cornerRadius: CGFloat = 2

    var body: some View {
        ZStack {
            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [.white.opacity(0.16), .white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: sideLength, height: sideLength)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .overlay {
            if showsProgress {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.black.opacity(0.4))

                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.3))
        }
        .task(id: videoURL) {
            thumbnailImage = VideoThumbnailService.cachedImage(for: videoURL)

            if thumbnailImage == nil {
                thumbnailImage = await loadThumbnail()
            }
        }
    }

    private func loadThumbnail() async -> UIImage? {
        await VideoThumbnailService.prepareThumbnail(for: videoURL)
    }
}

struct CameraModeToggleButton: View {
    let mode: CameraCaptureMode
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: mode.toggleSymbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(.black.opacity(0.7))
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(CameraPressStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .accessibilityLabel(mode.toggleAccessibilityLabel)
    }
}

struct CameraShutterButton: View {
    let isRecording: Bool
    let action: () -> Void
    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                CameraSloMoShutterRing()
                    .frame(width: 78, height: 78)
                
                RoundedRectangle(cornerRadius: isRecording ? 6 : 31, style: .continuous)
                    .fill(.red)
                    .frame(width: isRecording ? 30 : 56, height: isRecording ? 30 : 56)
                    .scaleEffect(isPressed ? 0.94 : 1)
                    .animation(.easeInOut(duration: 0.12), value: isPressed)
            }
            .frame(width: 98, height: 98)
            .shadow(color: .black.opacity(0.24), radius: 10, y: 6)
            .animation(.easeInOut(duration: 0.1), value: isRecording)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
    }
}

struct CameraDelayedPlaybackPicker: View {
    let options: [DelayedPlaybackDelayOption]
    let selectedOption: DelayedPlaybackDelayOption
    let isDisabled: Bool
    let onSelect: (DelayedPlaybackDelayOption) -> Void

    var body: some View {
        Picker("Delay", selection: Binding(
            get: { selectedOption },
            set: onSelect
        )) {
            ForEach(options) { option in
                Text("\(option.label)s")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .tag(option)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 98, height: 110)
        .clipped()
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.black.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .opacity(isDisabled ? 0.72 : 1)
        .disabled(isDisabled)
    }
}

struct CameraDelayedPlaybackLoadingIndicator: View {
    let selectedDelayOption: DelayedPlaybackDelayOption

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
                .tint(.white)

            Text(loadingText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var loadingText: String {
        String(
            format: String(localized: "Buffering %d s delay"),
            locale: .current,
            selectedDelayOption.rawValue
        )
    }
}

private struct CameraSloMoShutterRing: View {
    private let stripeCount = 112

    var body: some View {
        ZStack {
            ForEach(0..<stripeCount, id: \.self) { index in
                Rectangle()
                    .fill(.white)
                    .frame(width: 1, height: 4)
                    .offset(y: -32)
                    .rotationEffect(.degrees(Double(index) * (360.0 / Double(stripeCount))))
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

struct CameraShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct CameraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CameraZoomPicker: View {
    let options: [CameraZoomOption]
    let selectedOption: CameraZoomOption
    let isDisabled: Bool
    let onSelect: (CameraZoomOption) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(selectedOption == option ? option.label + "x" : option.label)
                        .font(.system(size: selectedOption == option ? 13 : 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedOption == option ? .yellow : .white)
                        .frame(
                            width: selectedOption == option ? 36 : 30,
                            height: selectedOption == option ? 36 : 30
                        )
                        .background(
                            selectedOption == option ? Color.black.opacity(0.5) : Color.black.opacity(0.2),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.black.opacity(0.24))
        }
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .opacity(isDisabled ? 0.75 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: selectedOption)
    }
}

#if DEBUG
struct CameraComponentsShowcase_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CameraPreviewPlaceholder()
            CameraEdgeTreatment()

            VStack(spacing: 28) {
                CameraMessagePill(
                    icon: "exclamationmark.triangle.fill",
                    text: "Back camera unavailable."
                )
                .padding(.top, 24)

                Spacer(minLength: 0)

                CameraZoomPicker(
                    options: [.ultraWide, .wide],
                    selectedOption: .wide,
                    isDisabled: false,
                    onSelect: { _ in }
                )

                HStack(spacing: 24) {
                    CameraShutterButton(isRecording: false, action: {})
                    CameraShutterButton(isRecording: true, action: {})
                }
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Camera Components Showcase")
    }
}

struct CameraPreviewPlaceholder_Previews: PreviewProvider {
    static var previews: some View {
        CameraPreviewPlaceholder()
            .preferredColorScheme(.dark)
            .previewDisplayName("Camera Preview Placeholder")
    }
}

struct CameraEdgeTreatment_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.2)
            CameraEdgeTreatment()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Camera Edge Treatment")
    }
}

struct CameraMessagePill_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            CameraMessagePill(
                icon: "exclamationmark.triangle.fill",
                text: "Back camera unavailable."
            )
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Camera Message Pill")
    }
}

struct CameraShutterButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ZStack {
                Color.black
                CameraShutterButton(isRecording: false, action: {})
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Shutter Idle")

            ZStack {
                Color.black
                CameraShutterButton(isRecording: true, action: {})
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Shutter Recording")
        }
    }
}

struct CameraZoomPicker_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ZStack {
                Color.black
                CameraZoomPicker(
                    options: [.ultraWide, .wide],
                    selectedOption: .wide,
                    isDisabled: false,
                    onSelect: { _ in }
                )
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Zoom Picker Active")

            ZStack {
                Color.black
                CameraZoomPicker(
                    options: [.ultraWide, .wide],
                    selectedOption: .ultraWide,
                    isDisabled: true,
                    onSelect: { _ in }
                )
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Zoom Picker Disabled")
        }
    }
}
#endif
