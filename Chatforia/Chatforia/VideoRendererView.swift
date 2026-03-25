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

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.contentMode = contentMode
        view.shouldMirror = mirror
        view.backgroundColor = .black

        attachRendererIfNeeded(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        uiView.shouldMirror = mirror
        uiView.contentMode = contentMode

        detachRendererIfNeeded(from: uiView, coordinator: context.coordinator)
        attachRendererIfNeeded(to: uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: VideoView, coordinator: Coordinator) {
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
