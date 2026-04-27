//
//  AgentDetailViewModel.swift
//  AgentBuilder
//
//  Created by Byron Smith on 4/17/25.
//


import Foundation
import SwiftUI

extension EnvironmentValues {
    @Entry var agentDetailViewModel: AgentDetailViewModel = .empty
    
}
import Foundation

// MARK: - AgentDetailViewModel
class AgentDetailViewModel: ObservableObject {
    @Published var agent: Agent
    @Published var errorMessage: String?

    private let agentManager: AgentManager
    private let agentId: UUID

    init(agent: Agent, agentManager: AgentManager = AgentManager()) {
        self.agent = agent
        self.agentManager = agentManager
        self.agentId = agent.id
    }
    
    static let empty = AgentDetailViewModel(agent: .empty)

    // MARK: - Prompt Step Operations
    
    @MainActor
    func saveStep(_ step: PromptStep) async throws {
        let isNew = !agent.promptSteps.contains(where: { $0.id == step.id })

        var updatedSteps = agent.promptSteps

        if let index = updatedSteps.firstIndex(where: { $0.id == step.id }) {
            updatedSteps[index] = step
        } else {
            updatedSteps.append(step)
        }

        // ✅ Persist updated steps list
        try await AgentManager().updatePromptSteps(agentId: agent.id, promptSteps: updatedSteps)

        // ✅ If new, also append to enabledPromptStepIds and persist that field
        if isNew {
            agent.enabledPromptStepIds.append(step.id)
            try await AgentManager().updateEnabledPromptSteps(
                agentId: agent.id,
                enabledPromptStepIds: agent.enabledPromptStepIds
            )
        }
    }

    func addPromptStep(_ step: PromptStep) {
        agent.promptSteps.append(step)
        savePromptSteps()
    }

    func updatePromptStep(_ step: PromptStep) {
        if let index = agent.promptSteps.firstIndex(where: { $0.id == step.id }) {
            agent.promptSteps[index] = step
            savePromptSteps()
        }
    }

    func deletePromptStep(_ step: PromptStep) {
        agent.promptSteps.removeAll { $0.id == step.id }
        savePromptSteps()
    }

    func reorderPromptSteps(from source: IndexSet, to destination: Int) {
        agent.promptSteps.move(fromOffsets: source, toOffset: destination)
        savePromptSteps()
    }

    func isStepEnabled(_ step: PromptStep) -> Bool {
        agent.enabledPromptStepIds.contains(step.id)
    }

    func enablePromptStep(_ step: PromptStep) {
        guard !agent.enabledPromptStepIds.contains(step.id) else { return }
        agent.enabledPromptStepIds.append(step.id)
        saveEnabledPromptSteps()
    }

    func disablePromptStep(_ step: PromptStep) {
        agent.enabledPromptStepIds.removeAll { $0 == step.id }
        saveEnabledPromptSteps()
    }

    // MARK: - Save Functions

    private func savePromptSteps() {
        Task {
            do {
                try await agentManager.updatePromptSteps(agentId: agentId, promptSteps: agent.promptSteps)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to save prompt steps: \(error.localizedDescription)"
                }
            }
        }
    }

    private func saveEnabledPromptSteps() {
        Task {
            do {
                try await agentManager.updateEnabledPromptSteps(agentId: agentId, enabledPromptStepIds: agent.enabledPromptStepIds)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to save enabled steps: \(error.localizedDescription)"
                }
            }
        }
    }
    
    @MainActor
    func updateStepField(_ updatedStep: PromptStep) async {
        if let index = agent.promptSteps.firstIndex(where: { $0.id == updatedStep.id }) {
            agent.promptSteps[index] = updatedStep
        } else {
            agent.promptSteps.append(updatedStep)
        }

        do {
            try await agentManager.updatePromptSteps(agentId: agentId, promptSteps: agent.promptSteps)
        } catch {
            self.errorMessage = "Failed to update step: \(error.localizedDescription)"
        }
    }
}
