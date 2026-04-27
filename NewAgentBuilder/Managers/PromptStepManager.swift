////
////  PromptStepManager.swift
////  AgentBuilder
////
////  Created by Byron Smith on 4/17/25.
////
//
//
//import Foundation
//import FirebaseFirestore
//
//// MARK: - PromptStepManager
///// Handles all Firestore CRUD operations for PromptStep models.
//class PromptStepManager {
//    private let db = Firestore.firestore()
//
//    // Returns the Firestore reference for steps under a specific agent
//    private func stepsRef(forAgentId agentId: UUID) -> CollectionReference {
//        db.collection("agents").document(agentId.uuidString).collection("promptSteps")
//    }
//
//    /// Fetch all prompt steps for a specific agent
//    func fetchSteps(forAgentId agentId: UUID) async throws -> [PromptStep] {
//        let snapshot = try await stepsRef(forAgentId: agentId).getDocuments()
//        return snapshot.documents.compactMap { doc in
//            PromptStep(dictionary: doc.data())
//        }
//    }
//
//    /// Create a new prompt step for an agent
//    func createStep(_ step: PromptStep, forAgentId agentId: UUID) async throws {
//        try await stepsRef(forAgentId: agentId)
//            .document(step.id.uuidString)
//            .setData(["id": step.id.uuidString,
//                      "title": step.title,
//                      "prompt": step.prompt,
//                      "notes": step.notes ?? ""])
//    }
//
//    /// Update an existing prompt step
//    func updateStep(_ step: PromptStep, forAgentId agentId: UUID) async throws {
//        try await stepsRef(forAgentId: agentId)
//            .document(step.id.uuidString)
//            .updateData(["title": step.title,
//                         "prompt": step.prompt,
//                         "notes": step.notes ?? ""])
//    }
//
//    /// Delete a prompt step
//    func deleteStep(_ step: PromptStep, forAgentId agentId: UUID) async throws {
//        try await stepsRef(forAgentId: agentId)
//            .document(step.id.uuidString)
//            .delete()
//    }
//}
