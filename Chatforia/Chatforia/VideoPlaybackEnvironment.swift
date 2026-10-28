import SwiftUI

private struct SuspendInlineVideoPlaybackKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var suspendInlineVideoPlayback: Bool {
        get { self[SuspendInlineVideoPlaybackKey.self] }
        set { self[SuspendInlineVideoPlaybackKey.self] = newValue }
    }
}
