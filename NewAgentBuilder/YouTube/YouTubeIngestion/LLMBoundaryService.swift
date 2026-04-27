//
//  LLMBoundaryService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/4/26.
//

import Foundation
import FirebaseFirestore
import Combine

/// Firebase CRUD service for LLM boundary/section results.
/// Follows the same pattern as BatchDigressionAnalysisService.
@MainActor
class LLMBoundaryService: ObservableObject {

    // MARK: - Published State

    @Published var videoResults: [LLMBoundaryVideoResult] = []
    @Published var errorMessage: String?

    // MARK: - Firebase

    private let db = Firestore.firestore()
    private let collectionName = "llmBoundaryResults"

    // MARK: - Load Results

    func loadResults(forChannelId channelId: String) async {
        do {
            let snapshot = try await db.collection(collectionName)
                .whereField("channelId", isEqualTo: channelId)
                .getDocuments()

            videoResults = snapshot.documents.compactMap { doc in
                try? doc.data(as: LLMBoundaryVideoResult.self)
            }
            print("Loaded \(videoResults.count) LLM boundary results for channel: \(channelId)")
        } catch {
            errorMessage = "Failed to load boundary results: \(error.localizedDescription)"
            print("Failed to load LLM boundary results: \(error)")
        }
    }

    // MARK: - Save

    func saveResult(_ result: LLMBoundaryVideoResult) async throws {
        let docRef = db.collection(collectionName).document(result.id)
        let data = try Firestore.Encoder().encode(result)
        try await docRef.setData(data)
        print("Saved LLM boundary result: \(result.id) (\(result.chunks.count) chunks, \(result.boundaries.count) boundaries)")
    }

    // MARK: - Convenience

    func hasBoundaries(forVideoId videoId: String) -> Bool {
        videoResults.contains { $0.videoId == videoId }
    }

    func result(forVideoId videoId: String) -> LLMBoundaryVideoResult? {
        videoResults.first { $0.videoId == videoId }
    }

    // MARK: - Delete

    func deleteResult(forVideoId videoId: String, channelId: String) async throws {
        let docId = LLMBoundaryVideoResult.docId(channelId: channelId, videoId: videoId)
        try await db.collection(collectionName).document(docId).delete()
        videoResults.removeAll { $0.videoId == videoId }
        print("Deleted LLM boundary result for video: \(videoId)")
    }

    func deleteResults(forChannelId channelId: String) async throws {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
        videoResults = []
        print("Deleted \(snapshot.documents.count) LLM boundary results for channel: \(channelId)")
    }
}
