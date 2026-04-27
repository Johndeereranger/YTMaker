//
//  PromptRunManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/5/25.
//


import FirebaseFirestore

// MARK: - PromptRunManager
/// Service to handle CRUD operations for PromptRun in Firestore.
class PromptRunManager {
    private let db = Firestore.firestore()
    static let instance = PromptRunManager()
    
    // MARK: - Create or Overwrite
    func savePromptRun(_ run: PromptRun) async throws {
        let data = toFirestoreData(run)
        try await db.collection("promptRuns")
            .document(run.id.uuidString)
            .setData(data)
    }

    // MARK: - Partial Field Update
    func updatePromptRunFields(runId: UUID, fields: [String: Any]) async throws {
        try await db.collection("promptRuns")
            .document(runId.uuidString)
            .updateData(fields)
    }

    // MARK: - Fetch All Runs for a Session
    func fetchPromptRuns(for chatSessionId: UUID) async throws -> [PromptRun] {
        let snapshot = try await db.collection("promptRuns")
            .whereField("chatSessionId", isEqualTo: chatSessionId.uuidString)
            .order(by: "createdAt")
            .getDocuments()

        return snapshot.documents.compactMap { PromptRun(document: $0) }
    }

    // MARK: - Delete Single Run
    func deletePromptRun(runId: UUID) async throws {
        try await db.collection("promptRuns")
            .document(runId.uuidString)
            .delete()
    }

    // MARK: - Delete All Runs for a Session
    func deleteRunsForSession(sessionId: UUID) async throws {
        let runs = try await fetchPromptRuns(for: sessionId)
        for run in runs {
            try await deletePromptRun(runId: run.id)
        }
    }

    // MARK: - Firestore Mapping
    private func toFirestoreData(_ run: PromptRun) -> [String: Any] {
        return [
            "id": run.id.uuidString,
            "chatSessionId": run.chatSessionId?.uuidString ?? "",
            "promptStepId": run.promptStepId.uuidString,
            "basePrompt": run.basePrompt,
            "userInput": run.userInput,
            "finalPrompt": run.finalPrompt,
            "response": run.response,
            "createdAt": Timestamp(date: run.createdAt),
            "feedbackNote": run.feedbackNote ?? "",
            "feedbackRating": run.feedbackRating ?? 0,
            "inputID": run.inputID ?? "",
            "purpose": run.purpose.rawValue,
            // Insert new fields here after "purpose"
            "modelUsed": run.modelUsed ?? "",
            "promptTokenCount": run.promptTokenCount ?? 0,
            "completionTokenCount": run.completionTokenCount ?? 0,
            "totalTokenCount": run.totalTokenCount ?? 0,
            "finishReason": run.finishReason ?? "",
            "cachedTokens": run.cachedTokens ?? 0,
            "imageURL": run.imageURL ?? ""
        ]
    }
    
    func deleteOrphanedPromptRuns(existingSessionIds: [UUID]) async throws {
        let allRuns = try await fetchAllPromptRuns() // Implement this to fetch all PromptRuns
        let orphaned = allRuns.filter {
            guard let sessionId = $0.chatSessionId else { return true }
            return !existingSessionIds.contains(sessionId)
        }

        for run in orphaned {
            try await deletePromptRun(runId: run.id)
        }

        print("🧹 Deleted \(orphaned.count) orphaned PromptRuns")
    }
    func deletePromptRuns(for sessionId: UUID) async throws {
        let runs = try await fetchPromptRuns(for: sessionId)
        for run in runs {
            try await deletePromptRun(runId: run.id)
        }
        print("🗑️ Deleted \(runs.count) PromptRuns for session \(sessionId)")
    }
    // MARK: - Fetch All PromptRuns
    func fetchAllPromptRuns() async throws -> [PromptRun] {
        let snapshot = try await db.collection("promptRuns")
            .order(by: "createdAt")
            .getDocuments()

        return snapshot.documents.compactMap { PromptRun(document: $0) }
    }
}
