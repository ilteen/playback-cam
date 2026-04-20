import PencilKit
import SwiftUI
import UIKit

//TODO: implement undo/redo

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

struct PlaybackDrawingToggleButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil.tip.crop.circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background {
                    Circle()
                        .fill(isActive ? .blue.opacity(0.96) : .black.opacity(0.7))
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(PlaybackPressStyle())
        .accessibilityLabel(String(localized: "Drawing tools"))
    }
}

struct PlaybackFloatingDrawingToggleOverlay: UIViewRepresentable, Animatable {
    let isActive: Bool
    let horizontalInset: CGFloat
    var bottomInset: CGFloat
    let action: () -> Void

    var animatableData: CGFloat {
        get { bottomInset }
        set { bottomInset = newValue }
    }

    func makeUIView(context: Context) -> PlaybackFloatingDrawingToggleAnchorView {
        let view = PlaybackFloatingDrawingToggleAnchorView()
        view.update(
            isActive: isActive,
            horizontalInset: horizontalInset,
            bottomInset: bottomInset,
            action: action
        )
        return view
    }

    func updateUIView(_ uiView: PlaybackFloatingDrawingToggleAnchorView, context: Context) {
        uiView.update(
            isActive: isActive,
            horizontalInset: horizontalInset,
            bottomInset: bottomInset,
            action: action
        )
    }

    static func dismantleUIView(_ uiView: PlaybackFloatingDrawingToggleAnchorView, coordinator: ()) {
        uiView.uninstallFloatingButton()
    }
}

final class PlaybackFloatingDrawingToggleAnchorView: UIView {
    private let floatingButton = UIButton(type: .custom)
    private var leadingConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private weak var installedWindow: UIWindow?
    private var action: (() -> Void)?
    private var isInstalled = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        isHidden = true
        isUserInteractionEnabled = false
        backgroundColor = .clear

        floatingButton.translatesAutoresizingMaskIntoConstraints = false
        floatingButton.accessibilityLabel = String(localized: "Drawing tools")
        floatingButton.layer.cornerRadius = 25
        floatingButton.layer.borderWidth = 1
        floatingButton.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        floatingButton.clipsToBounds = true
        floatingButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        floatingButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
        floatingButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        updateAppearance(isActive: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window == nil {
            uninstallFloatingButton()
        } else {
            installFloatingButtonIfNeeded()
        }
    }

    func update(
        isActive: Bool,
        horizontalInset: CGFloat,
        bottomInset: CGFloat,
        action: @escaping () -> Void
    ) {
        self.action = action
        installFloatingButtonIfNeeded()
        updateAppearance(isActive: isActive)
        leadingConstraint?.constant = horizontalInset
        bottomConstraint?.constant = -bottomInset
        installedWindow?.layoutIfNeeded()
    }

    func uninstallFloatingButton() {
        floatingButton.removeFromSuperview()
        leadingConstraint = nil
        bottomConstraint = nil
        installedWindow = nil
        isInstalled = false
    }

    private func installFloatingButtonIfNeeded() {
        guard let window else { return }

        if installedWindow !== window {
            uninstallFloatingButton()
        }

        guard !isInstalled else { return }

        installedWindow = window
        isInstalled = true
        window.addSubview(floatingButton)

        leadingConstraint = floatingButton.leadingAnchor.constraint(
            equalTo: window.safeAreaLayoutGuide.leadingAnchor
        )
        bottomConstraint = floatingButton.bottomAnchor.constraint(
            equalTo: window.safeAreaLayoutGuide.bottomAnchor
        )

        NSLayoutConstraint.activate([
            leadingConstraint,
            bottomConstraint
        ].compactMap { $0 })
    }

    private func updateAppearance(isActive: Bool) {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let image = UIImage(systemName: "pencil.tip.crop.circle", withConfiguration: imageConfig)
        floatingButton.setImage(image, for: .normal)
        floatingButton.tintColor = .white
        floatingButton.backgroundColor = isActive
            ? UIColor.systemBlue.withAlphaComponent(0.96)
            : UIColor.black.withAlphaComponent(0.7)
    }

    @objc
    private func handleTap() {
        action?()
    }
}

struct PlaybackDrawingCanvas: UIViewRepresentable {
    let drawing: PKDrawing
    let isDrawingEnabled: Bool
    let onDrawingChanged: (PKDrawing) -> Void
    let onToolPickerHeightChanged: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDrawingChanged: onDrawingChanged,
            onToolPickerHeightChanged: onToolPickerHeightChanged
        )
    }

    func makeUIView(context: Context) -> PlaybackDrawingCanvasContainerView {
        let view = PlaybackDrawingCanvasContainerView()
        view.canvasView.delegate = context.coordinator
        view.onToolPickerHeightChanged = context.coordinator.onToolPickerHeightChanged
        configure(view)
        return view
    }

    func updateUIView(_ uiView: PlaybackDrawingCanvasContainerView, context: Context) {
        configure(uiView)
    }

    static func dismantleUIView(_ uiView: PlaybackDrawingCanvasContainerView, coordinator: Coordinator) {
        uiView.setToolPickerVisible(false)
        uiView.canvasView.delegate = nil
    }

    private func configure(_ view: PlaybackDrawingCanvasContainerView) {
        if view.canvasView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            view.canvasView.drawing = drawing
        }

        view.onToolPickerHeightChanged = onToolPickerHeightChanged
        view.canvasView.isUserInteractionEnabled = isDrawingEnabled
        view.setToolPickerVisible(isDrawingEnabled)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let onDrawingChanged: (PKDrawing) -> Void
        let onToolPickerHeightChanged: (CGFloat) -> Void

        init(
            onDrawingChanged: @escaping (PKDrawing) -> Void,
            onToolPickerHeightChanged: @escaping (CGFloat) -> Void
        ) {
            self.onDrawingChanged = onDrawingChanged
            self.onToolPickerHeightChanged = onToolPickerHeightChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}

final class PlaybackDrawingCanvasContainerView: UIView, PKToolPickerObserver {
    let canvasView = PKCanvasView()
    var onToolPickerHeightChanged: ((CGFloat) -> Void)?

    private var toolPicker: PKToolPicker?
    private var wantsToolPickerVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        isOpaque = false
        backgroundColor = .clear

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .systemRed, width: 6)
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.contentInset = .zero
        canvasView.isUserInteractionEnabled = false

        addSubview(canvasView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvasView.frame = bounds
        canvasView.contentSize = bounds.size
        reportToolPickerHeight()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateToolPickerVisibility()
    }

    func setToolPickerVisible(_ isVisible: Bool) {
        wantsToolPickerVisible = isVisible
        updateToolPickerVisibility()
    }

    private func updateToolPickerVisibility() {
        if wantsToolPickerVisible {
            guard window != nil else { return }

            if toolPicker == nil {
                let picker = PKToolPicker()
                picker.addObserver(canvasView)
                picker.addObserver(self)
                toolPicker = picker
            }

            toolPicker?.setVisible(true, forFirstResponder: canvasView)
            if !canvasView.isFirstResponder {
                canvasView.becomeFirstResponder()
            }
            reportToolPickerHeight()
        } else {
            toolPicker?.setVisible(false, forFirstResponder: canvasView)
            toolPicker?.removeObserver(canvasView)
            toolPicker?.removeObserver(self)
            if canvasView.isFirstResponder {
                canvasView.resignFirstResponder()
            }
            toolPicker = nil
            onToolPickerHeightChanged?(0)
        }
    }

    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) {
        reportToolPickerHeight()
    }

    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
        reportToolPickerHeight()
    }

    private func reportToolPickerHeight() {
        guard wantsToolPickerVisible, let toolPicker else {
            onToolPickerHeightChanged?(0)
            return
        }

        let obscuredFrame = toolPicker.frameObscured(in: self)
        onToolPickerHeightChanged?(max(0, obscuredFrame.height))
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
