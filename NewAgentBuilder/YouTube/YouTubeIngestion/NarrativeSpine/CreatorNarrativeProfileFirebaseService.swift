//
//  CreatorNarrativeProfileFirebaseService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import Foundation
import FirebaseFirestore

class CreatorNarrativeProfileFirebaseService {
    static let shared = CreatorNarrativeProfileFirebaseService()
    private let db = Firestore.firestore()
    private let collectionName = "creator_narrative_profiles"

    private init() {}

    // MARK: - Save (Upsert — doc ID = channelId)

    func saveProfile(_ profile: CreatorNarrativeProfile) async throws {
        let docRef = db.collection(collectionName).document(profile.channelId)
        try docRef.setData(from: profile)
        print("✅ Saved creator narrative profile for \(profile.channelName) (\(profile.spineCount) spines)")
    }

    // MARK: - Load

    func loadProfile(channelId: String) async throws -> CreatorNarrativeProfile? {
        let docRef = db.collection(collectionName).document(channelId)
        let snapshot = try await docRef.getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: CreatorNarrativeProfile.self)
    }

    // MARK: - Delete

    func deleteProfile(channelId: String) async throws {
        try await db.collection(collectionName).document(channelId).delete()
        print("🗑️ Deleted creator narrative profile for channel \(channelId)")
    }
}
