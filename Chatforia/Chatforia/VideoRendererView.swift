import SwiftUI
import TwilioVideo

struct VideoRendererView: UIViewRepresentable {
    let mirror: Bool
    let contentMode: VideoView.ContentMode
    let remoteTrack: RemoteVideoTrack?
    let localTrack: LocalVideoTrack?

    init(
        mirror: Bool = false,
        contentMode: VideoView.ContentMode = .scaleAspectFill,
        remoteTrack: RemoteVideoTrack? = nil,
        localTrack: LocalVideoTrack? = nil
    ) {
        self.mirror = mirror
        self.contentMode = contentMode
        self.remoteTrack = remoteTrack
        self.localTrack = localTrack
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SceneVideoContainer {
        let container = SceneVideoContainer()
        let view = container.videoView
        view.contentMode = contentMode
        view.shouldMirror = mirror
        view.backgroundColor = .black

        attachRendererIfNeeded(to: view, coordinator: context.coordinator)
        return container
    }

    func updateUIView(_ container: SceneVideoContainer, context: Context) {
        let uiView = container.videoView
        uiView.shouldMirror = mirror
        uiView.contentMode = contentMode

        detachRendererIfNeeded(from: uiView, coordinator: context.coordinator)
        attachRendererIfNeeded(to: uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ container: SceneVideoContainer, coordinator: Coordinator) {
        let uiView = container.videoView
        if let remoteTrack = coordinator.remoteTrack {
            remoteTrack.removeRenderer(uiView)
            coordinator.remoteTrack = nil
        }

        if let localTrack = coordinator.localTrack {
            localTrack.removeRenderer(uiView)
            coordinator.localTrack = nil
        }
    }

    final class Coordinator {
        var remoteTrack: RemoteVideoTrack?
        var localTrack: LocalVideoTrack?
    }

    private func attachRendererIfNeeded(to view: VideoView, coordinator: Coordinator) {
        if let remoteTrack {
            guard coordinator.remoteTrack !== remoteTrack else { return }

            remoteTrack.addRenderer(view)
            coordinator.remoteTrack = remoteTrack
            coordinator.localTrack = nil
            return
        }

        if let localTrack {
            guard coordinator.localTrack !== localTrack else { return }

            localTrack.addRenderer(view)
            coordinator.localTrack = localTrack
            coordinator.remoteTrack = nil
        }
    }

    private func detachRendererIfNeeded(from view: VideoView, coordinator: Coordinator) {
        if let currentRemote = coordinator.remoteTrack, currentRemote !== remoteTrack {
            currentRemote.removeRenderer(view)
            coordinator.remoteTrack = nil
        }

        if let currentLocal = coordinator.localTrack, currentLocal !== localTrack {
            currentLocal.removeRenderer(view)
            coordinator.localTrack = nil
        }

        if remoteTrack == nil, let currentRemote = coordinator.remoteTrack {
            currentRemote.removeRenderer(view)
            coordinator.remoteTrack = nil
        }

        if localTrack == nil, let currentLocal = coordinator.localTrack {
            currentLocal.removeRenderer(view)
            coordinator.localTrack = nil
        }
    }
}

// Twilio VideoView does not support subclassing. Wrap it to forward the
// scene's orientation after SwiftUI/UIKit attaches or lays out the video.
final class SceneVideoContainer: UIView {
    let videoView = VideoView()
    private weak var lastScene: UIWindowScene?
    private var lastOrientation: UIInterfaceOrientation = .unknown

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(videoView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshCameraOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoView.frame = bounds
        refreshCameraOrientation()
    }

    private func refreshCameraOrientation() {
        guard let scene = window?.windowScene,
              scene.interfaceOrientation != .unknown
        else { return }
        guard scene !== lastScene || scene.interfaceOrientation != lastOrientation
        else { return }
        lastScene = scene
        lastOrientation = scene.interfaceOrientation
        UserInterfaceTracker.sceneInterfaceOrientationDidChange(scene)
    }
}
