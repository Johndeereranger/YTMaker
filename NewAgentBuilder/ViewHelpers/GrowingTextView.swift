//
//  GrowingTextView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/8/25.
//


import SwiftUI
import UIKit
class PasteEnabledTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}


import SwiftUI
import UIKit

struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var maxLines: Int
    var onHeightChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = PasteEnabledTextView()
        textView.isScrollEnabled = false
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.delegate = context.coordinator
        textView.autocorrectionType = .no
              textView.spellCheckingType = .no
              textView.smartQuotesType = .no
              textView.smartDashesType = .no
              textView.smartInsertDeleteType = .no
//        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
//        textView.addGestureRecognizer(tapGesture)
        textView.isUserInteractionEnabled = true
        textView.addGestureRecognizer(UILongPressGestureRecognizer()) // optional: iOS will handle this by default
        textView.backgroundColor = .clear
        textView.text = placeholder
        textView.textColor = .gray

        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update if the text is actually different AND the text view is not currently being edited
        if uiView.text != text && !uiView.isFirstResponder {
            if text.isEmpty {
                uiView.text = placeholder
                uiView.textColor = .gray
            } else {
                uiView.text = text
                uiView.textColor = .label
            }
        }
        context.coordinator.updateHeight(textView: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextView
        private var lastHeight: CGFloat = 0

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            if textView.textColor == .gray {
                parent.text = ""
            } else {
                parent.text = textView.text
            }

            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !textView.text.isEmpty
            }

            updateHeight(textView: textView)
        }
        
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            if let textView = sender.view as? UITextView {
                textView.becomeFirstResponder()
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            print("📋 Pasteboard: \(UIPasteboard.general.string ?? "nil")")
            if textView.textColor == .gray {
                textView.text = ""
                textView.textColor = .label
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textView.text = parent.placeholder
                textView.textColor = .gray
            }
        }

        func updateHeight(textView: UITextView) {
            let size = CGSize(width: textView.frame.width, height: .infinity)
            let fittingSize = textView.sizeThatFits(size)
            let lineHeight = textView.font?.lineHeight ?? 20
            let maxHeight = lineHeight * CGFloat(parent.maxLines)
            let clampedHeight = min(fittingSize.height, maxHeight)

            if abs(clampedHeight - lastHeight) > 1 {
                lastHeight = clampedHeight
                DispatchQueue.main.async {
                    self.parent.onHeightChange(clampedHeight)
                }
            }
        }
    }
}
