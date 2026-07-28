import SwiftUI

/*
 * Key replacement is intentionally available only through the guarded
 * Start Fresh flow in RestoreEncryptionKeyView. Keeping a second reset
 * screen would create competing security behavior.
 */
@available(
    *,
    unavailable,
    message:
        "Use the guarded Start Fresh flow in RestoreEncryptionKeyView."
)
struct RotateEncryptionKeyView: View {
    var body: some View {
        EmptyView()
    }
}
