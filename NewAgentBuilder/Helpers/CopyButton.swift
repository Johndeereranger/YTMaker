//
//  CopyButton.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/15/25.
//


import SwiftUI
import MobileCoreServices
struct CopyButton2: View {
    let label: String
    let valueToCopy: String
    var font: Font = .body

    @State private var isCopied = false

    var body: some View {
        Button(action: {
            UIPasteboard.general.string = valueToCopy
            withAnimation {
                isCopied = true
            }

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    isCopied = false
                }
            }
        }) {
            Label(
                title: { Text(isCopied ? "Copied" : "Copy \(label)").font(font) },
                icon: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .transition(.opacity)
                }
            )
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}


import SwiftUI
import UniformTypeIdentifiers

struct CopyButtonWasWorking: View {
    let label: String
    let valueToCopy: String
    var font: Font = .body
    
    @State private var isCopied = false
    
    var body: some View {
        Button(action: {
            // Debug: Log the input
            print("Attempting to copy: '\(valueToCopy)'")
            print("Input length: \(valueToCopy.count)")
            
            let pasteboard = UIPasteboard.general
            
            // Try setting as plain text UTI
            if let data = valueToCopy.data(using: .utf8) {
                pasteboard.setData(data, forPasteboardType: UTType.plainText.identifier)
                print("Set data for UTI: \(UTType.plainText.identifier)")
            } else {
                print("Failed to convert valueToCopy to UTF-8 data")
            }
            
            // Fallback: Also set as string for broader compatibility
            pasteboard.string = valueToCopy
            print("Set pasteboard.string: '\(valueToCopy)'")
            
            // Debug: Log pasteboard contents
            print("Pasteboard types: \(pasteboard.types)")
            print("Pasteboard string: \(pasteboard.string ?? "nil")")
            
            // Only show "Copied" if there's content
            if !valueToCopy.isEmpty {
                withAnimation {
                    isCopied = true
                }
                
                // Reset after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        isCopied = false
                    }
                }
            }
        }) {
            Label(
                title: { Text(isCopied ? "Copied" : "Copy \(label)").font(font) },
                icon: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .transition(.opacity)
                }
            )
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}
//
//struct CopyButton: View {
//    let label: String
//    let valueToCopy: String
//    var font: Font = .body
//    var showIcon: Bool = true           // ✅ NEW: Show/hide icon
//    var includesCopyPrefix: Bool = true // ✅ NEW: Add "Copy" prefix
//    
//    @State private var isCopied = false
//    
//    var body: some View {
//        Button(action: {
//            // Debug: Log the input
//            print("Attempting to copy: '\(valueToCopy)'")
//            print("Input length: \(valueToCopy.count)")
//            
//            let pasteboard = UIPasteboard.general
//            
//            // Try setting as plain text UTI
//            if let data = valueToCopy.data(using: .utf8) {
//                pasteboard.setData(data, forPasteboardType: UTType.plainText.identifier)
//                print("Set data for UTI: \(UTType.plainText.identifier)")
//            } else {
//                print("Failed to convert valueToCopy to UTF-8 data")
//            }
//            
//            // Fallback: Also set as string for broader compatibility
//            pasteboard.string = valueToCopy
//            print("Set pasteboard.string: '\(valueToCopy)'")
//            
//            // Debug: Log pasteboard contents
//            print("Pasteboard types: \(pasteboard.types)")
//            print("Pasteboard string: \(pasteboard.string ?? "nil")")
//            
//            // Only show "Copied" if there's content
//            if !valueToCopy.isEmpty {
//                withAnimation {
//                    isCopied = true
//                }
//                
//                // Reset after delay
//                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
//                    withAnimation {
//                        isCopied = false
//                    }
//                }
//            }
//        }) {
//            // ✅ Dynamic label based on settings
//            let displayLabel = includesCopyPrefix ? "Copy \(label)" : label
//            let copiedLabel = isCopied ? "Copied" : displayLabel
//            
//            if showIcon {
//                Label(
//                    title: { Text(copiedLabel).font(font) },
//                    icon: {
//                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
//                            .transition(.opacity)
//                    }
//                )
//            } else {
//                Text(copiedLabel)
//                    .font(font)
//            }
//        }
//        .buttonStyle(BorderlessButtonStyle())
//    }
//}
////
////#Preview {
////    CopyButton(label: "Test", valueToCopy: "Hello, World!")
////}
//
//struct CopyButtonAction: View {
//    let label: String
//    let action: () -> Void
//    var font: Font = .body
//    var isDisabled: Bool = false
//    
//    @State private var isCopied = false
//    
//    var body: some View {
//        Button(action: {
//            action()
//            
//            if true {  // Assume action succeeds; adjust if needed
//                withAnimation {
//                    isCopied = true
//                }
//                
//                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
//                    withAnimation {
//                        isCopied = false
//                    }
//                }
//            }
//        }) {
//            Label(
//                title: { Text(isCopied ? "Copied" : "Copy \(label)").font(font) },
//                icon: {
//                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
//                        .transition(.opacity)
//                }
//            )
//        }
//        .buttonStyle(.bordered)
//        .disabled(isDisabled)
//    }
//}


struct CopyButton: View {
    let label: String
    let valueToCopy: String
    var font: Font = .body
    var showIcon: Bool = true
    var includesCopyPrefix: Bool = true
    
    @State private var isCopied = false
    
    var body: some View {
        Button(action: {
            copyToClipboard()
            
            if !valueToCopy.isEmpty {
                withAnimation {
                    isCopied = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        isCopied = false
                    }
                }
            }
        }) {
            let displayLabel = includesCopyPrefix ? "Copy \(label)" : label
            let copiedLabel = isCopied ? "Copied" : displayLabel
            
            if showIcon {
                Label(
                    title: { Text(copiedLabel).font(font) },
                    icon: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .transition(.opacity)
                    }
                )
            } else {
                Text(copiedLabel)
                    .font(font)
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    
    private func copyToClipboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(valueToCopy, forType: .string)
        #else
        UIPasteboard.general.string = valueToCopy
        #endif
        
        print("✅ Copied to clipboard: \(valueToCopy.prefix(50))...")
    }
}

struct CopyButtonAction: View {
    let label: String
    let action: () -> Void
    var font: Font = .body
    var isDisabled: Bool = false
    
    @State private var isCopied = false
    
    var body: some View {
        Button(action: {
            action()
            
            withAnimation {
                isCopied = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    isCopied = false
                }
            }
        }) {
            Label(
                title: { Text(isCopied ? "Copied" : "Copy \(label)").font(font) },
                icon: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .transition(.opacity)
                }
            )
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }
}
