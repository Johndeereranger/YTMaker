//
//  PasteableTextView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/10/26.
//




import SwiftUI
import UIKit

struct PasteableTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onImagePasted: (UIImage) -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = PasteHandlingTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = UIColor.systemBackground
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        
        // Set up paste handling
        textView.onImagePasted = onImagePasted
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update if the actual text content has changed
        let isShowingPlaceholder = uiView.textColor == UIColor.placeholderText
        let currentActualText = isShowingPlaceholder ? "" : uiView.text
        
        if currentActualText != text {
            if text.isEmpty {
                uiView.text = placeholder
                uiView.textColor = UIColor.placeholderText
            } else {
                uiView.text = text
                uiView.textColor = UIColor.label
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: PasteableTextView
        
        init(_ parent: PasteableTextView) {
            self.parent = parent
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.textColor == UIColor.placeholderText {
                textView.text = ""
                textView.textColor = UIColor.label
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = UIColor.placeholderText
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            // Only update the binding if we're not showing placeholder text
            if textView.textColor != UIColor.placeholderText {
                parent.text = textView.text
            } else if textView.text.isEmpty {
                // If text becomes empty and we're not showing placeholder yet
                parent.text = ""
                textView.text = parent.placeholder
                textView.textColor = UIColor.placeholderText
            }
        }
    }
}

class PasteHandlingTextView: UITextView {
    var onImagePasted: ((UIImage) -> Void)?
    
    override func paste(_ sender: Any?) {
        // Check if clipboard has an image
        if UIPasteboard.general.hasImages, let image = UIPasteboard.general.image {
            onImagePasted?(image)
        } else {
            // Fall back to default paste behavior for text
            super.paste(sender)
        }
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return UIPasteboard.general.hasStrings || UIPasteboard.general.hasImages
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
