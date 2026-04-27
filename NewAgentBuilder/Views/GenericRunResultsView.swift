//
//  GenericRunResultsView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/24/25.
//
//
import Foundation
import SwiftUI
struct ResultsView2: View {
    var stepOutputs: [String]
    @State private var expandedStates: [Bool] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if stepOutputs.isEmpty {
                Text("No results yet. Run the agent to see outputs.")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                Text("🔄 Agent Steps Output")
                    .font(.headline)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(stepOutputs.indices, id: \.self) { index in
                            StepOutputItem(
                                index: index,
                                output: stepOutputs[index],
                                isExpanded: expandedBinding(for: index)
                            )
                            .onAppear {
                                ensureExpandedStatesCapacity(for: index)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .onChange(of: stepOutputs) { newValue in
            // Always reset to proper size
            expandedStates = Array(repeating: false, count: newValue.count)
        }
    }
    
    private func expandedBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: {
                index < expandedStates.count ? expandedStates[index] : false
            },
            set: { newValue in
                // No resizing here — resizing only happens in `onAppear`
                if index < expandedStates.count {
                    expandedStates[index] = newValue
                }
            }
        )
    }

    private func ensureExpandedStatesCapacity(for index: Int) {
        if index >= expandedStates.count {
            expandedStates += Array(repeating: false, count: index - expandedStates.count + 1)
        }
    }
}

struct StepOutputItem: View {
    let index: Int
    let output: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isExpanded) {
                OutputContentView(content: output)
            } label: {
                HStack {
                    Text("Step \(index + 1)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    CopyButton(label: "Step \(index + 1) output", valueToCopy: output, font: .caption)
                }
            }

            if !isExpanded {
                OutputPreview(content: output)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct OutputPreview: View {
    let content: String
    
    var body: some View {
        let firstSegment = ContentParser.parseSegments(content).first
        
        switch firstSegment?.type {
        case .code:
            CodePreviewBlock(code: firstSegment?.content ?? "")
        case .text:
            let text = firstSegment?.content ?? ""
            Text(text.prefix(120) + (text.count > 120 ? "…" : ""))
                .font(.body)
                .foregroundColor(.secondary)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        case .none:
            EmptyView()
        }
    }
}

struct OutputContentView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ContentParser.parseSegments(content), id: \.id) { segment in
                switch segment.type {
                case .text:
                    Text(segment.content)
                        .font(.body)
                        .foregroundColor(.primary)

                case .code:
                    VStack(alignment: .leading, spacing: 6) {
                        CopyButton(label: "Code", valueToCopy: segment.content, font: .caption)
                        ScrollView(.horizontal) {
                            Text(segment.content)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Content Parser
struct ContentParser {
    struct ContentSegment: Identifiable {
        let id = UUID()
        let type: SegmentType
        let content: String
        
        enum SegmentType {
            case text, code
        }
    }
    
    static func parseSegments(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var currentBuffer: [String] = []
        var isInCodeBlock = false
        
        for line in content.components(separatedBy: .newlines) {
            if line.starts(with: "```") {
                // Flush current buffer
                if !currentBuffer.isEmpty {
                    let segmentType: ContentSegment.SegmentType = isInCodeBlock ? .code : .text
                    segments.append(ContentSegment(type: segmentType, content: currentBuffer.joined(separator: "\n")))
                    currentBuffer = []
                }
                isInCodeBlock.toggle()
            } else {
                currentBuffer.append(line)
            }
        }
        
        // Handle remaining buffer
        if !currentBuffer.isEmpty {
            let segmentType: ContentSegment.SegmentType = isInCodeBlock ? .code : .text
            segments.append(ContentSegment(type: segmentType, content: currentBuffer.joined(separator: "\n")))
        }
        
        return segments
    }
}
