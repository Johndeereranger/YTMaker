//
//  MermaidDropZoneView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/28/25.
//
//import SwiftUI
//import UniformTypeIdentifiers
//
//struct MermaidDropZoneView: View {
//    @Binding var mermaidCode: String
//    @State private var isTargeted = false
//
//    var body: some View {
//        HStack(spacing: 12) {
//            Text("📥 Drop Mermaid .txt or .md file here or Paste Below")
//                .font(.headline)
//                .padding()
//                .frame(maxWidth: .infinity)
//                .background(isTargeted ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
//                .cornerRadius(8)
//                .onDrop(of: [UTType.plainText, .utf8PlainText, .fileURL], isTargeted: $isTargeted) { providers in
//                    handleDrop(providers)
//                }
//
//            TextEditor(text: $mermaidCode)
//                .font(.system(.body, design: .monospaced))
//                .frame(minHeight: 200)
//                .padding(4)
//                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
//        }
//        .padding()
//    }
//
//    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
//        for provider in providers {
//            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
//                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
//                    if let data = item as? Data,
//                       let url = URL(dataRepresentation: data, relativeTo: nil),
//                       let content = try? String(contentsOf: url) {
//                        DispatchQueue.main.async {
//                            self.mermaidCode = content
//                        }
//                    }
//                }
//                return true
//            }
//
//            if provider.canLoadObject(ofClass: String.self) {
//                _ = provider.loadObject(ofClass: String.self) { object, _ in
//                    if let str = object {
//                        DispatchQueue.main.async {
//                            self.mermaidCode = str
//                        }
//                    }
//                }
//                return true
//            }
//        }
//        return false
//    }
//}
