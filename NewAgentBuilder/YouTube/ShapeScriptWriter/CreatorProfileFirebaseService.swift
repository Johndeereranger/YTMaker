//
//  CreatorProfileFirebaseService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/27/26.
//

import Foundation
import FirebaseFirestore

// MARK: - Creator Profile Firebase Service

/// Firebase service for storing and retrieving Creator Profiles
class CreatorProfileFirebaseService {
    static let shared = CreatorProfileFirebaseService()

    private let db = Firestore.firestore()
    private let collectionName = "creatorProfiles"

    private init() {}

    // MARK: - Save

    /// Save a creator profile to Firebase
    func saveProfile(_ profile: CreatorProfile) async throws {
        let data = try Firestore.Encoder().encode(profile)
        try await db.collection(collectionName).document(profile.id).setData(data)
        print("Saved creator profile for: \(profile.channelName)")
    }

    // MARK: - Fetch

    /// Fetch profile for a specific channel
    func getProfile(forChannelId channelId: String) async throws -> CreatorProfile? {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .order(by: "updatedAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else {
            return nil
        }

        return try doc.data(as: CreatorProfile.self)
    }

    /// Fetch profile by ID
    func getProfile(byId profileId: String) async throws -> CreatorProfile? {
        let doc = try await db.collection(collectionName).document(profileId).getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: CreatorProfile.self)
    }

    /// Fetch all profiles
    func getAllProfiles() async throws -> [CreatorProfile] {
        let snapshot = try await db.collection(collectionName)
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        return try snapshot.documents.compactMap { doc in
            try doc.data(as: CreatorProfile.self)
        }
    }

    /// Fetch profiles for multiple channels
    func getProfiles(forChannelIds channelIds: [String]) async throws -> [CreatorProfile] {
        guard !channelIds.isEmpty else { return [] }

        // Firebase 'in' queries limited to 10 items
        var allProfiles: [CreatorProfile] = []

        for chunk in channelIds.chunked(into: 10) {
            let snapshot = try await db.collection(collectionName)
                .whereField("channelId", in: chunk)
                .getDocuments()

            let profiles = try snapshot.documents.compactMap { doc in
                try doc.data(as: CreatorProfile.self)
            }
            allProfiles.append(contentsOf: profiles)
        }

        return allProfiles
    }

    // MARK: - Delete

    /// Delete a profile
    func deleteProfile(_ profile: CreatorProfile) async throws {
        try await db.collection(collectionName).document(profile.id).delete()
        print("Deleted creator profile: \(profile.channelName)")
    }

    /// Delete profile for channel
    func deleteProfile(forChannelId channelId: String) async throws {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        for doc in snapshot.documents {
            try await doc.reference.delete()
        }
    }

    // MARK: - Check Existence

    /// Check if a profile exists for a channel
    func hasProfile(forChannelId channelId: String) async throws -> Bool {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .limit(to: 1)
            .getDocuments()

        return !snapshot.documents.isEmpty
    }
}

// MARK: - Array Extension
