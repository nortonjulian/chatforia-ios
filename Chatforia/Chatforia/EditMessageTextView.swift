import SwiftUI
import UIKit

struct EditMessageTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> EditMessageUITextView {
        let textView = EditMessageUITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.text = text
        textView.isScrollEnabled = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setKeyboardFocus(isFocused)
        return textView
    }

    func updateUIView(_ textView: EditMessageUITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused

        if textView.text != text {
            textView.text = text
        }

        textView.setKeyboardFocus(isFocused)
    }

    static func dismantleUIView(_ textView: EditMessageUITextView, coordinator: Coordinator) {
        // A queued request must not reopen the keyboard after this editor is removed.
        textView.delegate = nil
        textView.setKeyboardFocus(false)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        private var didSetInitialCursor = false

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Set the cursor only after focus succeeds, not before window attachment.
            if !didSetInitialCursor {
                let end = textView.endOfDocument
                textView.selectedTextRange = textView.textRange(from: end, to: end)
                didSetInitialCursor = true
            }
            isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused.wrappedValue = false
        }
    }
}

final class EditMessageUITextView: UITextView {
    private var wantsKeyboardFocus = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyKeyboardFocusWhenAttached()
    }

    func setKeyboardFocus(_ focused: Bool) {
        wantsKeyboardFocus = focused
        applyKeyboardFocusWhenAttached()
    }

    private func applyKeyboardFocusWhenAttached() {
        guard window != nil else { return }

        // UIKit focus changes can invoke the delegate. Run outside SwiftUI's
        // updateUIView pass, and read the latest request instead of a stale value.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            if self.wantsKeyboardFocus {
                if !self.isFirstResponder {
                    self.becomeFirstResponder()
                }
            } else if self.isFirstResponder {
                self.resignFirstResponder()
            }
        }
    }
}
