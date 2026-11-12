import SwiftUI
import UIKit

/// Keeps UIKit's per-conversation keyboard memory while leaving keyboard choice to the user.
final class ConversationTextView: UITextView {
    var keyboardContextIdentifier: String?

    override var textInputContextIdentifier: String? { keyboardContextIdentifier }
}

struct ContextualMessageTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let contextIdentifier: String?
    let placeholder: String
    let textColor: UIColor
    let isEnabled: Bool

    func makeUIView(context: Context) -> ConversationTextView {
        let view = ConversationTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.isScrollEnabled = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: ConversationTextView, context: Context) {
        context.coordinator.parent = self
        view.keyboardContextIdentifier = contextIdentifier
        view.accessibilityLabel = placeholder
        view.textColor = textColor
        view.isEditable = isEnabled
        if view.text != text { view.text = text }
        if isFocused && !view.isFirstResponder {
            DispatchQueue.main.async { [weak view] in
                guard let view, !view.isFirstResponder else { return }
                view.becomeFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ConversationTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let lineHeight = uiView.font?.lineHeight ?? 20
        return CGSize(width: width, height: min(max(measured.height, lineHeight), lineHeight * 5))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ContextualMessageTextView

        init(_ parent: ContextualMessageTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isFocused = false }
    }
}
