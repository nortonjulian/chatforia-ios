import SwiftUI
import UIKit

struct EditMessageTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
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
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }

        if isFocused {
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }

            if !context.coordinator.didSetInitialCursor {
                let end = textView.endOfDocument
                textView.selectedTextRange = textView.textRange(from: end, to: end)
                context.coordinator.didSetInitialCursor = true
            }
        } else {
            if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        var didSetInitialCursor = false

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused = false
        }
    }
}
