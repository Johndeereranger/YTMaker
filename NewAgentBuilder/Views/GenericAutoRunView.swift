//
//  GenericAutoRunView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/23/25.
//


import SwiftUI
import SwiftUI

// MARK: - Main View
struct GenericAutoRunView: View {
//    @StateObject private var viewModel = GenericAutoRunViewModel(agentId: UUID(uuidString: "91B60D7A-9463-42D9-A684-0D97FA73EA84")!)

    @StateObject private var viewModel = GenericAutoRunViewModel()
    @ObservedObject private var agentViewModel = AgentViewModel.instance
    @State private var selectedAgentId: UUID?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                if !viewModel.isRunning, viewModel.chatSession == nil {
                    AgentSelectionPicker(
                        agents: agentViewModel.agents,
                        selectedAgentId: $selectedAgentId,
                        onSelect: viewModel.setAgent
                    )
                }
                if viewModel.chatSession != nil {
                    ChatSessionHeaderView(
                        title: Binding(
                            get: { viewModel.chatSession?.title ?? "" },
                            set: {viewModel.chatSession?.title = $0}

                        ),
                        onSave: {

                            viewModel.updateSessionTitle($0) }
                    )
                }

                ResultsView2(stepOutputs: viewModel.stepOutputs)

                AgentRunStatusView(isRunning: viewModel.isRunning)
                
                if let agent = viewModel.agent {
                         AgentSpecificExtrasView(agent: agent, viewModel: viewModel)
                     }
                
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

              
            }
            .padding()
        }
        .task {
            await viewModel.loadAgent()
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.chatSession == nil {
                InputBar2 { inputText in
                    viewModel.droppedInput = inputText
                    print("✅ droppedInput set to \(inputText.prefix(40))...")
                    Task { await viewModel.runAllSteps() }
                } onTopRightTap: {
                    print("ℹ️ Top-right tap (InputBar2)")
                }
            }
        }
        .onAppear {
            if selectedAgentId == nil,
               let first = agentViewModel.agents.first {
                selectedAgentId = first.id
                viewModel.setAgent(first)
            }
        }
    }
}

struct AgentSelectionPicker: View {
    let agents: [Agent]
    @Binding var selectedAgentId: UUID?
    let onSelect: (Agent) -> Void

    var body: some View {
        Picker("Select Agent", selection: Binding(
            get: { selectedAgentId ?? agents.first?.id },
            set: { newId in
                selectedAgentId = newId
                if let agent = agents.first(where: { $0.id == newId }) {
                    onSelect(agent)
                }
            }
        )) {
            ForEach(agents) { agent in
                Text(agent.name).tag(agent.id as UUID?)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Agent Specific Extras
struct AgentSpecificExtrasView: View {
    let agent: Agent
    @ObservedObject var viewModel: GenericAutoRunViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isSpecialAgent {
                Button(action: viewModel.copyAllSwiftCode) {
                    Label("Copy Swift Code", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                if !viewModel.campCode.isEmpty {
                    Button(action: viewModel.copyCampCode) {
                        Label("Copy Camp Code", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.bordered)
                }

                WeekPickerView(selectedWeek: $viewModel.selectedWeek)
            }
        }
        .padding(.top)
    }

    private var isSpecialAgent: Bool {
        agent.id.uuidString == "91B60D7A-9463-42D9-A684-0D97FA73EA84"
    }


}
struct WeekPickerView: View {
    @Binding var selectedWeek: Int

    var body: some View {
        HStack {
            Text("Week:")
                .font(.subheadline)

            Picker("Week", selection: $selectedWeek) {
                ForEach(1...44, id: \.self) { week in
                    Text("Week \(week)").tag(week)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300)

            Spacer()
        }
        .padding(.bottom, 4)
    }
}
//
//struct ResultsView2: View {
//    var stepOutputs: [String]
//    @State private var expandedStates: [Bool] = []
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            if stepOutputs.isEmpty {
//                Text("No results yet. Run the agent to see outputs.")
//                    .foregroundColor(.secondary)
//                    .italic()
//                    .padding()
//            } else {
//                Text("🔄 Agent Steps Output")
//                    .font(.headline)
//
//                ScrollView {
//                    LazyVStack(alignment: .leading, spacing: 16) {
//                        ForEach(Array(stepOutputs.enumerated()), id: \.offset) { index, output in
//                            DisclosureItem(
//                                index: index,
//                                output: output,
//                                isExpanded: Binding(
//                                    get: { index < expandedStates.count ? expandedStates[index] : false },
//                                    set: { newValue in
//                                        if index >= expandedStates.count {
//                                            expandedStates += Array(repeating: false, count: index - expandedStates.count + 1)
//                                        }
//                                        expandedStates[index] = newValue
//                                    }
//                                )
//                            )
//                        }
//                    }
//                    .padding(.vertical)
//                }
//            }
//        }
//        .onChange(of: stepOutputs) { newValue in
//            expandedStates = Array(repeating: false, count: newValue.count)
//        }
//    }
//}
//
//struct DisclosureItem: View {
//    let index: Int
//    let output: String
//    @Binding var isExpanded: Bool
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            DisclosureGroup(isExpanded: $isExpanded) {
//                SegmentedOutputView(raw: output)
//            } label: {
//                HStack {
//                    Text("Step \(index + 1)")
//                        .font(.subheadline)
//                        .fontWeight(.semibold)
//                    Spacer()
//                    CopyButton(label: "Copy", valueToCopy: output, font: .caption)
//                }
//            }
//
////            if !isExpanded {
////                ParsedAttributedCodeViewShort(raw: output)
////                    .padding(.top, 4)
////            }
//            if !isExpanded {
//                let segments = parseSegmentChunks(output)
//                if let first = segments.first {
//                    switch first.0 {
//                    case "code":
//                        CodePreviewBlock(code: first.1)
//                    case "text":
//                        Text(first.1.prefix(120) + (first.1.count > 120 ? "…" : ""))
//                            .font(.body)
//                            .foregroundColor(.secondary)
//                            .padding(8)
//                            .background(Color.gray.opacity(0.1))
//                            .cornerRadius(8)
//                    default:
//                        EmptyView()
//                    }
//                }
//            }
//        }
//        .padding()
//        .background(Color.gray.opacity(0.05))
//        .cornerRadius(8)
//    }
//    
//    func parseSegmentChunks(_ raw: String) -> [(String, String)] {
//        var results: [(String, String)] = []
//        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
//        var buffer: [String] = []
//        var inCode = false
//
//        for line in lines {
//            if line.starts(with: "```") {
//                if inCode {
//                    results.append(("code", buffer.joined(separator: "\n")))
//                    buffer = []
//                } else {
//                    if !buffer.isEmpty {
//                        results.append(("text", buffer.joined(separator: "\n")))
//                        buffer = []
//                    }
//                }
//                inCode.toggle()
//            } else {
//                buffer.append(String(line))
//            }
//        }
//
//        if !buffer.isEmpty {
//            results.append((inCode ? "code" : "text", buffer.joined(separator: "\n")))
//        }
//
//        return results
//    }
//}
//
//struct SegmentedOutputView: View {
//    let raw: String
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            ForEach(parseChunks(from: raw), id: \.self) { chunk in
//                switch chunk.type {
//                case .text:
//                    Text(chunk.content)
//                        .font(.body)
//                        .foregroundColor(.primary)
//
//                case .code:
//                    VStack(alignment: .leading, spacing: 6) {
//                        ScrollView(.horizontal) {
//                            Text(chunk.content)
//                                .font(.system(.body, design: .monospaced))
//                                .foregroundColor(.primary)
//                                .padding(8)
//                                .background(Color(.systemGray6))
//                                .cornerRadius(6)
//                        }
//
//                        CopyButton(label: "Copy Code", valueToCopy: chunk.content, font: .caption)
//                    }
//                }
//            }
//        }
//    }
//
//    // MARK: - Parsing Logic
//    private func parseChunks(from raw: String) -> [SegmentChunk] {
//        var result: [SegmentChunk] = []
//        var inCode = false
//        var buffer: [String] = []
//
//        for line in raw.components(separatedBy: .newlines) {
//            if line.starts(with: "```") {
//                if inCode {
//                    // Close code block
//                    result.append(.code(buffer.joined(separator: "\n")))
//                    buffer = []
//                } else {
//                    // Close text block if any
//                    if !buffer.isEmpty {
//                        result.append(.text(buffer.joined(separator: "\n")))
//                        buffer = []
//                    }
//                }
//                inCode.toggle()
//            } else {
//                buffer.append(line)
//            }
//        }
//
//        // Append trailing buffer
//        if !buffer.isEmpty {
//            result.append(inCode ? .code(buffer.joined(separator: "\n")) : .text(buffer.joined(separator: "\n")))
//        }
//
//        return result
//    }
//
//    struct SegmentChunk: Hashable {
//        enum ChunkType { case text, code }
//        let type: ChunkType
//        let content: String
//
//        static func text(_ content: String) -> SegmentChunk {
//            SegmentChunk(type: .text, content: content)
//        }
//        static func code(_ content: String) -> SegmentChunk {
//            SegmentChunk(type: .code, content: content)
//        }
//    }
//}
