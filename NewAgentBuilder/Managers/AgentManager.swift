//
//  AgentManager.swift
//  AgentBuilde
//
//  Created by Byron Smith on 4/16/25.
//

import FirebaseFirestore
// MARK: - AgentManager
/// Service to handle CRUD operations for Agent in Firestore.
class AgentManager {
    static let instance = AgentManager()
    private let db = Firestore.firestore()
    
    /// Fetches all agents from Firestore.
    func fetchAgents() async throws -> [Agent] {
        let snapshot = try await db.collection("agents").getDocuments()
        return snapshot.documents.compactMap { Agent(document: $0) }
    }
    


    
    /// Creates a new agent in Firestore.
    func createAgent(name: String, description: String?) async throws {
        let agent = Agent(name: name, description: description)
        try await db.collection("agents").document(agent.id.uuidString).setData(from: agent)
    }
    
    /// Updates an existing agent in Firestore.
//    func updateAgent(_ agent: Agent, name: String, description: String?) async throws {
//        var updatedAgent = agent
//        updatedAgent.update(name: name, description: description)
//        try await db.collection("agents").document(agent.id.uuidString).setData(from: updatedAgent)
//    }
    
    /// Deletes an agent from Firestore.
    func deleteAgent(_ agent: Agent) async throws {
        try await db.collection("agents").document(agent.id.uuidString).delete()
    }
    /// Updates the enabledPromptStepIds field for an agent
    func updateEnabledPromptSteps(agentId: UUID, enabledPromptStepIds: [UUID]) async throws {
        try await db.collection("agents")
            .document(agentId.uuidString)
            .updateData([
                "enabledPromptStepIds": enabledPromptStepIds.map { $0.uuidString }
            ])
    }
    func updatePromptStepOrder(agentId: UUID, promptSteps: [PromptStep]) async throws {
        let promptStepsData = promptSteps.map { step in
            [
                "id": step.id.uuidString,
                "title": step.title,
                "prompt": step.prompt,
                "notes": step.notes ?? "",
                "isBatchEligible" : step.isBatchEligible
            ]
        }
        try await db.collection("agents").document(agentId.uuidString)
            .updateData(["promptSteps": promptStepsData])
    }
    
    func updateStep(_ updatedStep: PromptStep, forAgentId agentId: UUID) async throws {
        guard var agent = try await fetchAgent(with: agentId) else { return }

        if let index = agent.promptSteps.firstIndex(where: { $0.id == updatedStep.id }) {
            agent.promptSteps[index] = updatedStep
            try await updatePromptSteps(agentId: agentId, promptSteps: agent.promptSteps)
        }
    }
    
    func updatePromptSteps(agentId: UUID, promptSteps: [PromptStep]) async throws {
        let stepsData = promptSteps.map { step in
            [
                "id": step.id.uuidString,
                "title": step.title,
                "prompt": step.prompt,
                "notes": step.notes ?? "",
                "isBatchEligible" : step.isBatchEligible,
                "useCashe" : step.useCashe,
                "aiModel" : step.aiModel?.rawValue ?? AIModel.gpt4o.rawValue
                
            ]
        }
        try await db.collection("agents").document(agentId.uuidString)
            .updateData(["promptSteps": stepsData])
    }

    /// Updates the chatSessions array for a given agent
    func updateChatSessions(agentId: UUID, chatSessions: [ChatSession]) async throws {
        let sessionData = chatSessions.map { session in
            [
                "id": session.id.uuidString,
                "agentId": session.agentId.uuidString,
                "title": session.title,
                "createdAt": Timestamp(date: session.createdAt)
            ]
        }
        
        try await db.collection("agents")
            .document(agentId.uuidString)
            .updateData([
                "chatSessions": sessionData
            ])
    }
    // MARK: - Fetch single agent by ID
    func fetchAgent(with id: UUID) async throws -> Agent? {
        let doc = try await db.collection("agents").document(id.uuidString).getDocument()
        return Agent(document: doc)
    }
    
    func deleteChatSession(agentId: UUID, sessionId: UUID) async throws {
        let agentRef = Firestore.firestore().collection("agents").document(agentId.uuidString)
        let snapshot = try await agentRef.getDocument()

        guard var data = snapshot.data(),
              var sessions = data["chatSessions"] as? [[String: Any]] else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing sessions data"])
        }

        // 🔥 Remove session from array
        sessions.removeAll { ($0["id"] as? String) == sessionId.uuidString }
        data["chatSessions"] = sessions

        // 💾 Update Firestore
        try await agentRef.setData(data, merge: true)

        // 🧹 Clean up associated PromptRuns
        try await PromptRunManager.instance.deletePromptRuns(for: sessionId)
    }
    
    func fetchPromptRunsForAgent(agentId: UUID) async throws -> [PromptRun] {
        let doc = try await db.collection("agents").document(agentId.uuidString).getDocument()

        guard let data = doc.data(),
              let sessions = data["chatSessions"] as? [[String: Any]] else {
            return []
        }

        let sessionIds: [UUID] = sessions.compactMap { dict in
            guard let idStr = dict["id"] as? String else { return nil }
            return UUID(uuidString: idStr)
        }

        // Fetch all prompt runs at once
        let allRuns = try await PromptRunManager.instance.fetchAllPromptRuns()
        
        // Filter locally — this avoids multiple queries
        return allRuns.filter { run in
            guard let sid = run.chatSessionId else { return false }
            return sessionIds.contains(sid)
        }
    }
  
}
