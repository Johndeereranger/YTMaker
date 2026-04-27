//
//  PromptRunInspectorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/13/25.
//


import SwiftUI

struct PromptRunInspectorView: View {
    let agent: Agent
    let stepId: UUID

    @State private var runs: [PromptRun] = []
    @State private var selectedPurpose: PromptRunPurpose? = nil
    @State private var selectedInputID: String? = nil
    @State private var groupedByInput: [String: [PromptRun]] = [:]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Prompt Runs for Step")
                .font(.title2)
                .padding(.bottom, 4)

            List(filteredGroupedRuns.keys.sorted(), id: \.self) { inputID in
                Section(header: Text("Input Group: \(inputID)")) {
                    ForEach(filteredGroupedRuns[inputID] ?? []) { run in
                        PromptRunEngineeringCell(run: run) {
                            deleteSpecificRun(run)
                        }
                    }
                    .onDelete { indexSet in
                        deleteRun(at: indexSet, in: inputID)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            Task {
                let allRuns = try? await AgentManager.instance.fetchPromptRunsForAgent(agentId: agent.id)
                runs = allRuns?.filter { $0.promptStepId == stepId } ?? []
                groupedByInput = Dictionary(grouping: runs, by: { $0.inputID ?? "<none>" })
            }
        }
        .navigationTitle("Prompt Inspector")
    }
    
    private func deleteRun(at offsets: IndexSet, in inputID: String) {
        guard var runsInGroup = groupedByInput[inputID] else { return }

        let deletedRuns = offsets.map { runsInGroup[$0] }

        for run in deletedRuns {
            Task {
                try? await PromptRunManager.instance.deletePromptRun(runId: run.id)
            }
        }

        runsInGroup.remove(atOffsets: offsets)
        groupedByInput[inputID] = runsInGroup

        // Remove deleted runs from the flat list
        runs.removeAll { run in deletedRuns.contains(where: { $0.id == run.id }) }
    }

    private func deleteSpecificRun(_ run: PromptRun) {
        Task {
            try? await PromptRunManager.instance.deletePromptRun(runId: run.id)
            groupedByInput[run.inputID ?? "<none>"]?.removeAll { $0.id == run.id }
            runs.removeAll { $0.id == run.id }
        }
    }

    private var filteredGroupedRuns: [String: [PromptRun]] {
        groupedByInput.mapValues { group in
            group.filter { run in
                (selectedPurpose == nil || run.purpose == selectedPurpose)
            }
        }.filter { !$0.value.isEmpty }
    }
}


import SwiftUI

struct PromptRunEngineeringCell: View {
    let run: PromptRun
    let onDelete: () -> Void

    @State private var isExpanded: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showCopyConfirm: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("📝 Input: \(run.userInput)")
                Text("🗣️ Response: \(run.response)")
                Text("🧠 Base Prompt: \(run.basePrompt)")
                Text("🧪 Final Prompt: \(run.finalPrompt)")
                Divider()
                Text("📌 Purpose: \(run.purpose.rawValue)")
                Text("🔗 inputID: \(run.inputID ?? "<none>")")
                Text("📦 Token Summary:")
                VStack(alignment: .leading, spacing: 2) {
                    Text("   • Prompt: \(run.promptTokenCount ?? 0)")
                    Text("   • Completion: \(run.completionTokenCount ?? 0)")
                    Text("   • Total: \(run.totalTokenCount ?? 0)")
                    Text("   • Cached: \(run.cachedTokens ?? 0)")
                }
                Divider()
                if let reason = run.finishReason {
                    Text("🏁 Finish Reason: \(reason)")
                }
                if let model = run.modelUsed {
                    Text("🤖 Model: \(model)")
                }
            }
            .font(.caption)
            .padding(.top, 4)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🧠 Prompt: \(run.basePrompt.prefix(60))")
                        .font(.subheadline.bold())
                    Text("📝 Input: \(run.userInput.prefix(60))")
                        .font(.subheadline)
                    Text("🗣️ Response: \(run.response.prefix(60))")
                        .font(.subheadline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("   • Prompt: \(run.promptTokenCount ?? 0)")
                    Text("   • Completion: \(run.completionTokenCount ?? 0)")
                    Text("   • Total: \(run.totalTokenCount ?? 0)")
                    Text("   • Cached: \(run.cachedTokens ?? 0)")
                    Text(" $\(PromptCostEstimator.instance.estimateCost(from: run))")
                }
                Button {
                    showCopyConfirm = false
                    let summary = """
                    🧠 Prompt: \(run.basePrompt)
                    📝 Input: \(run.userInput)
                    🧪 Final Prompt: \(run.finalPrompt)
                    🗣️ Response: \(run.response)
                    📌 Purpose: \(run.purpose.rawValue)
                    🔗 InputID: \(run.inputID ?? "<none>")
                    🤖 Model: \(run.modelUsed ?? "Unknown")
                    🏁 Finish Reason: \(run.finishReason ?? "Unknown")
                    📦 Tokens:
                      - Prompt: \(run.promptTokenCount ?? 0)
                      - Completion: \(run.completionTokenCount ?? 0)
                      - Total: \(run.totalTokenCount ?? 0)
                      - Cached: \(run.cachedTokens ?? 0)
                    """
                    UIPasteboard.general.string = summary
                    showCopyConfirm = true
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
        .alert("Delete this run?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Copied full run to clipboard!", isPresented: $showCopyConfirm) {
            Button("OK", role: .cancel) {}
        }
    }
}
