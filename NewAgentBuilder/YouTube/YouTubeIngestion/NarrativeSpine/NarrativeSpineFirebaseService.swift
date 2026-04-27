//
//  NarrativeSpineFirebaseService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import Foundation
import FirebaseFirestore

class NarrativeSpineFirebaseService {
    static let shared = NarrativeSpineFirebaseService()
    private let db = Firestore.firestore()
    private let collectionName = "narrative_spines"

    private init() {}

    // MARK: - Save

    func saveSpine(_ spine: NarrativeSpine) async throws {
        let docRef = db.collection(collectionName).document(spine.videoId)
        try docRef.setData(from: spine)
        print("✅ Saved narrative spine for video \(spine.videoId) (\(spine.beats.count) beats)")
    }

    // MARK: - Load Single

    func loadSpine(videoId: String) async throws -> NarrativeSpine? {
        let docRef = db.collection(collectionName).document(videoId)
        let snapshot = try await docRef.getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: NarrativeSpine.self)
    }

    // MARK: - Load for Channel (bulk)

    func loadSpines(channelId: String) async throws -> [NarrativeSpine] {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: NarrativeSpine.self)
        }
    }

    // MARK: - Delete

    func deleteSpine(videoId: String) async throws {
        try await db.collection(collectionName).document(videoId).delete()
        print("🗑️ Deleted narrative spine for video \(videoId)")
    }

    func deleteSpines(channelId: String) async throws -> Int {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
        print("🗑️ Deleted \(snapshot.documents.count) narrative spines for channel \(channelId)")
        return snapshot.documents.count
    }

    // MARK: - Mark Spine Complete on Video Doc

    func markSpineComplete(videoId: String, beatCount: Int) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)

        try await docRef.setData([
            "narrativeSpineStatus": [
                "complete": true,
                "beatCount": beatCount,
                "lastUpdated": Timestamp(date: Date())
            ]
        ], merge: true)
    }

    // MARK: - Clear Spine Status on Video Doc

    func clearSpineStatus(videoId: String) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)

        try await docRef.setData([
            "narrativeSpineStatus": [
                "complete": false,
                "beatCount": 0,
                "lastUpdated": Timestamp(date: Date())
            ]
        ], merge: true)
    }
}
