//
//  FadeOutCopyButton.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/29/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A copy button that fades out for 1-2 seconds after being pressed
/// to provide visual feedback that content was copied
struct FadeOutCopyButton: View {
    let text: String
    let label: String
    let systemImage: String
    let fadeDuration: Double

    @State private var isCopied = false
    @State private var opacity: Double = 1.0

    init(
        text: String,
        label: String = "Copy",
        systemImage: String = "doc.on.doc",
        fadeDuration: Double = 1.5
    ) {
        self.text = text
        self.label = label
        self.systemImage = systemImage
        self.fadeDuration = fadeDuration
    }

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : systemImage)
                Text(isCopied ? "Copied!" : label)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(isCopied ? .green : .blue)
        .opacity(opacity)
        .disabled(isCopied)
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }

    private func copyToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        withAnimation {
            isCopied = true
            opacity = 0.5
        }

        // Reset after fade duration
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
            withAnimation {
                isCopied = false
                opacity = 1.0
            }
        }
    }
}

/// A more compact copy button for inline use
struct CompactCopyButton: View {
    let text: String
    let fadeDuration: Double

    @State private var isCopied = false

    init(text: String, fadeDuration: Double = 2.0) {
        self.text = text
        self.fadeDuration = fadeDuration
    }

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundColor(isCopied ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }

    private func copyToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        isCopied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
            isCopied = false
        }
    }
}

/// Copy button for menu items (no fade, just checkmark feedback)
struct MenuCopyButton: View {
    let text: String
    let label: String
    let systemImage: String

    @State private var isCopied = false

    init(text: String, label: String, systemImage: String = "doc.on.doc") {
        self.text = text
        self.label = label
        self.systemImage = systemImage
    }

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            Label(isCopied ? "Copied!" : label, systemImage: isCopied ? "checkmark" : systemImage)
        }
    }

    private func copyToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        isCopied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isCopied = false
        }
    }
}

// MARK: - Copy All Button (for multiple items)

struct CopyAllButton: View {
    let items: [String]
    let separator: String
    let label: String

    @State private var isCopied = false
    @State private var opacity: Double = 1.0

    init(items: [String], separator: String = "\n\n", label: String = "Copy All") {
        self.items = items
        self.separator = separator
        self.label = label
    }

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc.fill")
                Text(isCopied ? "Copied!" : label)
            }
            .font(.caption)
        }
        .buttonStyle(.borderedProminent)
        .tint(isCopied ? .green : .blue)
        .opacity(opacity)
        .disabled(isCopied)
    }

    private func copyToClipboard() {
        let combined = items.joined(separator: separator)

        #if canImport(UIKit)
        UIPasteboard.general.string = combined
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        #endif

        withAnimation {
            isCopied = true
            opacity = 0.5
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
                opacity = 1.0
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        FadeOutCopyButton(text: "Sample text to copy")

        CompactCopyButton(text: "Compact copy")

        CopyAllButton(items: ["Item 1", "Item 2", "Item 3"])
    }
    .padding()
}
