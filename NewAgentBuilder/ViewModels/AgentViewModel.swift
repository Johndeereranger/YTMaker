//
//  AgentViewModel.swift
//  AgentBuilde
//
//  Created by Byron Smith on 4/16/25.
//

import Foundation

import Combine

  
// MARK: - AgentViewModel
/// Manages the agent list and CRUD operations, interacting with AgentManager.
class AgentViewModel: ObservableObject {
    static let instance = AgentViewModel()
    @Published var agents: [Agent] = []
    @Published var errorMessage: String?
    private let agentManager: AgentManager = AgentManager.instance
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        //self.agentManager = agentManager
        fetchAgents()
    }
    
    /// Loads agents from AgentManager.
    func fetchAgents() {
        Task {
            do {
                let agents = try await agentManager.fetchAgents()
                DispatchQueue.main.async {
                    self.agents = agents
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load agents: \(error.localizedDescription)"
                }
            }
        }
    }
    func deleteChatSession(_ session: ChatSession, forAgentId agentId: UUID) async {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else { return }
        
        var updated = agents[index]
        updated.chatSessions.removeAll(where: { $0.id == session.id })
        
        await MainActor.run {
            agents[index] = updated
        }

        do {
            try await AgentManager().updateChatSessions(
                agentId: updated.id,
                chatSessions: updated.chatSessions
            )
        } catch {
            print("❌ Failed to sync chat session deletion: \(error.localizedDescription)")
        }
    }
    
//    func updateAgentInstance(_ updatedAgent: Agent) {
//        if let index = agents.firstIndex(where: { $0.id == updatedAgent.id }) {
//            agents[index] = updatedAgent
//            print(#function, "inside Agent View Model")
//        } else {
//            print(#function, "updated agent not found id: \(updatedAgent.id)", "list of agents: \(agents)")
//        }
//    }
    func updateAgentInstance(_ updatedAgent: Agent) {
        if let index = agents.firstIndex(where: { $0.id == updatedAgent.id }) {
            agents[index] = Agent(
                id: updatedAgent.id,
                name: updatedAgent.name,
                description: updatedAgent.description,
                category: updatedAgent.category,
                promptSteps: updatedAgent.promptSteps,
                enabledPromptStepIds: updatedAgent.enabledPromptStepIds,
                chatSessions: updatedAgent.chatSessions
            )
            print(#function, "✅ updated agent at index \(index)")
        } else {
            print(#function, "❌ agent not found id: \(updatedAgent.id), agents: \(agents.map(\.id))")
        }
    }
    
    /// Adds a new agent.
    func addAgent(name: String, description: String?) {
        Task {
            do {
                try await agentManager.createAgent(name: name, description: description)
                await fetchAgents() // Refresh list
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to add agent: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Updates an existing agent.
    func updateAgent(_ agent: Agent, name: String, description: String?) {
        Task {
            do {
//                try await agentManager.updateAgent(agent, name: name, description: description)
//                await fetchAgents() // Refresh list
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to update agent: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Deletes an agent.
    func deleteAgent(_ agent: Agent) {
        Task {
            do {
                try await agentManager.deleteAgent(agent)
                await fetchAgents() // Refresh list
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to delete agent: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func updatePromptStepPrompt(agentId: UUID, stepId: UUID, newPrompt: String) {
        guard let agentIndex = agents.firstIndex(where: { $0.id == agentId }) else {
            print("❌ Agent not found for ID: \(agentId)")
            return
        }

        var updatedAgent = agents[agentIndex]

        guard let stepIndex = updatedAgent.promptSteps.firstIndex(where: { $0.id == stepId }) else {
            print("❌ Prompt step not found for step ID: \(stepId)")
            return
        }

        // 🔄 Local mutation
        updatedAgent.promptSteps[stepIndex].prompt = newPrompt

        // 💾 Save to Firestore
        Task {
            do {
                try await AgentManager.instance.updatePromptSteps(
                    agentId: agentId,
                    promptSteps: updatedAgent.promptSteps
                )

                // ✅ Write back to published state
                await MainActor.run {
                    agents[agentIndex] = updatedAgent
                    print("✅ Prompt step updated in Firestore and local store.")
                }
            } catch {
                print("❌ Firestore update failed: \(error.localizedDescription)")
            }
        }
    }
}
