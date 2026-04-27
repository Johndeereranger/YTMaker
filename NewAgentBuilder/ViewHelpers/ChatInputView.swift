//
//  ChatInputView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/30/25.
//

import SwiftUI

struct MeasuredTextField2: View {
    @Binding var text: String
    var onHeightChange: (CGFloat) -> Void

    var body: some View {
        TextField("Message...", text: $text, axis: .vertical)
            .lineLimit(1...6)
            .foregroundColor(.black)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            onHeightChange(geo.size.height)
                        }
                        .onChange(of: text) { _ in
                            onHeightChange(geo.size.height)
                        }
                }
            )
    }
}
struct MeasuredTextField: View {
        @Binding var text: String
        var placeholder: String = "Message..."
        var lineLimit: ClosedRange<Int> = 1...6
        var onHeightChange: (CGFloat) -> Void

        @State private var internalHeight: CGFloat = .zero

        var body: some View {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $text)
                    .frame(minHeight: internalHeight, maxHeight: internalHeight)
                    .background(GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.size.height) { newHeight in
                                if internalHeight != newHeight {
                                    internalHeight = newHeight
                                    onHeightChange(newHeight)
                                }
                            }
                    })
                    .padding(.horizontal, 2)
            }
            .onChange(of: text) { _ in
                recalculateHeight()
            }
            .onAppear {
                recalculateHeight()
            }
        }

        private func recalculateHeight() {
            let lineHeight: CGFloat = 20 // Approximate line height (can tweak)
            let minLines = CGFloat(lineLimit.lowerBound)
            let maxLines = CGFloat(lineLimit.upperBound)
            let textLineCount = CGFloat(text.components(separatedBy: .newlines).count)
            let clamped = min(max(textLineCount, minLines), maxLines)
            let newHeight = clamped * lineHeight + 12 // base padding
            if internalHeight != newHeight {
                internalHeight = newHeight
                onHeightChange(newHeight)
            }
        }
    }

struct InputBar2: View {
    @State private var internalText: String = ""
    @State private var textFieldHeight: CGFloat = 0
    @State private var isExpanded: Bool = false
    @State private var droppedHTML: String = ""
    
    var onSend: (String) -> Void
    var onTopRightTap: (() -> Void)? = nil
    
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .bottom, spacing: 8) {
                GrowingTextView(
                    text: $internalText,
                    placeholder: "Type your message...",
                    maxLines: 6,
                    onHeightChange: { newHeight in
                        textFieldHeight = newHeight
                    }
                )
                .frame(height: textFieldHeight)
                .padding(12)
                .background(Color.white)
                .cornerRadius(18)
//                
//                HTMLDropView(htmlText: $droppedHTML)
//                    .frame(width: 80, height: 80)

                

                Button(action: {
                    let trimmedText = internalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedHTML = droppedHTML.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmedText.isEmpty {
                        onSend(trimmedText)
                        internalText = ""
                    } else if !trimmedHTML.isEmpty {
                        onSend(trimmedHTML)
                        droppedHTML = ""
                    }
                }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(8)
                .disabled(
                    internalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    droppedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .padding()
            .background(.ultraThinMaterial)
            
            if textFieldHeight > 75 {
                Button(action: { onTopRightTap?()
                    isExpanded = true}) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        //.foregroundColor(Color(UIColor.darkGray))
                            .foregroundColor(.platformDarkGray)
                            .font(.system(size: 20, weight: .bold))
                            .padding(10)
                    }
                    .transition(.opacity)
                    .padding(.trailing, 20)
                    .padding(.top, 8)
                    .buttonStyle(PlainButtonStyle())
            }
            
        }
        .sheet(isPresented: $isExpanded, onDismiss: {
            isExpanded = false
        }) {
            ExpandedInputEditor(
                text: $internalText, isPresented: $isExpanded,
                onSend: {
                    onSend(internalText)
                    internalText = ""
                    //isExpanded = false
                },
                onClose: {
                   // isExpanded = false
                }
            )
        }
    }
}
import SwiftUI
import UniformTypeIdentifiers

import SwiftUI
import UniformTypeIdentifiers

struct HTMLDropView: View {
    @Binding var htmlText: String
    @State private var isDropped = false

    var body: some View {
        ZStack {
            if isDropped {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.green)
                    Text("HTML File Loaded")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    Text("📄 Drag & drop an HTML file here")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .onDrop(of: [UTType.html.identifier], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.html.identifier) { url, _ in
                guard let url = url,
                      let content = try? String(contentsOf: url) else { return }
                DispatchQueue.main.async {
                    htmlText = content
                    isDropped = true
                }
            }
            return true
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers
struct DocumentData: Identifiable {
    let id = UUID()
    let rawHTML: String
    let filename: String
}

class DocumentUploadViewModel: ObservableObject {
    @Published var stagedDocuments: [DocumentData] = []
}
struct DocumentDropView: View {
    @StateObject var viewModel = DocumentUploadViewModel()
    @State private var selectedDocument: String?

    var body: some View {
        VStack(spacing: 20) {
            if let selected = selectedDocument {
                VStack(alignment: .leading) {
                    Text("📄 Preview of dropped HTML:")
                        .font(.headline)
                    ScrollView {
                        Text(selected)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxHeight: 300)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
            }

            // 🧾 Drop Zone
            Text("Drag & drop HTML files here")
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .onDrop(of: [UTType.html.identifier], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
        }
        .padding()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.html.identifier) { url, _ in
                    guard let url = url else { return }

                    do {
                        let content = try String(contentsOf: url)
                        DispatchQueue.main.async {
                            selectedDocument = content
                            viewModel.stagedDocuments.append(DocumentData(rawHTML: content, filename: url.lastPathComponent))
                        }
                    } catch {
                        print("❌ Error reading HTML file: \(error.localizedDescription)")
                    }
                }
                handled = true
            }
        }
        return handled
    }
}


import SwiftUI

struct InputBarPasteOnly: View {
    @State private var pastedText: String = ""
    @State private var showExpanded: Bool = false
    
    var onSend: (String) -> Void
    var onTopRightTap: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 8) {
                HStack {
                    Text(pastedText.isEmpty ? "Tap to paste..." : "Pasted ✓")
                        .foregroundColor(pastedText.isEmpty ? .gray : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture {
                            handlePaste()
                        }

                    Spacer()
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(18)

                Button(action: {
                    let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSend(trimmed)
                    pastedText = ""
                }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(pastedText.isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(PlainButtonStyle())
                .padding(8)
            }
            .padding()
            .background(.ultraThinMaterial)

            if !pastedText.isEmpty {
                Button(action: {
                    onTopRightTap?()
                    showExpanded = true
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundColor(.platformDarkGray)
                        .font(.system(size: 20, weight: .bold))
                        .padding(10)
                }
                .padding(.trailing, 20)
                .padding(.top, 8)
                .buttonStyle(PlainButtonStyle())
            }
        }
        .sheet(isPresented: $showExpanded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("📋 Pasted Content Preview:")
                        .font(.headline)
                    Text(pastedText)
                        .font(.body)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding()
            }
        }
    }

    private func handlePaste() {
        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            pastedText = text
        }
    }
}
