//
//  FileDropView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/27/25.
//

import SwiftUI
import UniformTypeIdentifiers


struct DroppedTextFile: Identifiable {
    let id = UUID()
    let url: URL
    let preview: String
}

struct FileDropView: View {
    @State private var droppedFiles: [DroppedTextFile] = []
    @State private var selectedPreview: String?

    var body: some View {
        VStack(spacing: 20) {
            if let preview = selectedPreview {
                VStack(alignment: .leading) {
                    Text("📄 Preview:")
                        .font(.headline)
                    ScrollView {
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxHeight: 300)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
            }

            Text("Drag & drop TXT files here")
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            Button("📋 Copy All Inputs") {
                let combined = droppedFiles.enumerated().map { index, file in
                    "Input\(index + 1): \(file.preview)"
                }.joined(separator: "\n\n")

                UIPasteboard.general.string = combined
            }
            .buttonStyle(.borderedProminent)
            
            Button("📋 Send All to Firebase") {
                for file in droppedFiles {
                    ContentItemManager.shared.createContentItem(
                        contentType: .note,
                        text: file.preview,
                        author: nil,
                        source: nil,
                        summary: nil
                    ) { success in
                        if success {
                            print("✅ Uploaded: \(file.preview.prefix(30))...")
                        } else {
                            print("❌ Failed to upload: \(file.preview.prefix(30))...")
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)


            List(droppedFiles) { file in
                VStack(alignment: .leading) {
                    Text(file.url.lastPathComponent)
                        .font(.headline)
                    Text(file.preview)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .onTapGesture {
                    selectedPreview = file.preview
                }
            }
        }
        .padding()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.plainText.identifier) { url, _ in
                    guard let url = url else { return }

                    do {
                        let contents = try String(contentsOf: url)
                        let preview = contents
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .prefix(500)
                        let dropped = DroppedTextFile(url: url, preview: String(preview))
                        DispatchQueue.main.async {
                            droppedFiles.append(dropped)
                        }
                    } catch {
                        print("❌ Error reading TXT file: \(error.localizedDescription)")
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
