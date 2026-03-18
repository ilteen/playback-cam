import SwiftUI

struct PlaybackEdgeTreatment: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.48), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [.clear, .black.opacity(0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
        }
    }
}

struct PlaybackPreviewPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.1),
                    Color(red: 0.12, green: 0.13, blue: 0.15),
                    Color(red: 0.03, green: 0.03, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.white.opacity(0.05))
                .frame(maxWidth: 420, maxHeight: 260)
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .padding(32)

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 68, weight: .regular))
                .foregroundStyle(.white.opacity(0.16))
        }
    }
}

struct PlaybackCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(.black.opacity(0.24))
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(PlaybackPressStyle())
    }
}

struct PlaybackPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PlaybackTransportButton: View {
    let systemName: String
    let action: () -> Void
    let doubleAction: () -> Void
    let holdAction: () -> Void
    let holdEndAction: () -> Void

    @GestureState private var isPressed = false
    @State private var holdTask: Task<Void, Never>?
    @State private var singleTapTask: Task<Void, Never>?
    @State private var isHolding = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background {
                Circle()
                    .fill(.white.opacity(0.24))
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .scaleEffect(isPressed || isHolding ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.12), value: isPressed || isHolding)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onChanged { _ in
                        guard holdTask == nil, !isHolding else { return }

                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 180_000_000)
                            guard !Task.isCancelled else { return }

                            singleTapTask?.cancel()
                            singleTapTask = nil
                            isHolding = true
                            holdAction()
                        }
                    }
                    .onEnded { _ in
                        holdTask?.cancel()
                        holdTask = nil

                        if isHolding {
                            isHolding = false
                            holdEndAction()
                            return
                        }

                        handleTap()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .onDisappear {
                holdTask?.cancel()
                holdTask = nil
                singleTapTask?.cancel()
                singleTapTask = nil

                if isHolding {
                    isHolding = false
                    holdEndAction()
                }
            }
    }

    private func handleTap() {
        if let singleTapTask {
            singleTapTask.cancel()
            self.singleTapTask = nil
            doubleAction()
            return
        }

        singleTapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            self.singleTapTask = nil
            action()
        }
    }
}

struct KnoblessScrubBar: View {
    let progress: Double
    let onScrubStart: () -> Void
    let onScrub: (Double) -> Void
    let onScrubEnded: () -> Void

    @State private var dragStartProgress: Double?

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let width = max(proxy.size.width, 1)
            let fillWidth = max(6, width * clampedProgress)
            let isScrubbing = dragStartProgress != nil
            let barHeight: CGFloat = isScrubbing ? 15 : 8

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: barHeight)

                Capsule()
                    .fill(.white)
                    .frame(width: fillWidth, height: barHeight)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.14), value: isScrubbing)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if dragStartProgress == nil {
                            dragStartProgress = clampedProgress
                            onScrubStart()
                        }

                        let baseProgress = dragStartProgress ?? clampedProgress
                        let nextProgress = min(max(baseProgress + (value.translation.width / width), 0), 1)
                        onScrub(nextProgress)
                    }
                    .onEnded { _ in
                        dragStartProgress = nil
                        onScrubEnded()
                    }
            )
        }
    }
}

#if DEBUG
struct PlaybackComponentsShowcase_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            PlaybackPreviewPlaceholder()
            PlaybackEdgeTreatment()

            VStack {
                HStack {
                    PlaybackCircleButton(systemName: "xmark", action: {})
                    Spacer()
                    PlaybackCircleButton(systemName: "square.and.arrow.down", action: {})
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        KnoblessScrubBar(
                            progress: 0.42,
                            onScrubStart: {},
                            onScrub: { _ in },
                            onScrubEnded: {}
                        )
                        .frame(height: 20)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Playback Components Showcase")
    }
}
#endif
