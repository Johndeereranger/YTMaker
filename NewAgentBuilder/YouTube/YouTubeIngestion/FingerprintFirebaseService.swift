//
//  FingerprintFirebaseService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/14/26.
//

import Foundation
import FirebaseFirestore

/// Firebase CRUD for the top-level `fingerprints` collection.
///
/// Document structure:
/// ```
/// fingerprints/{creatorId}_{moveLabel}_{position}_{promptType}
/// ├── creatorId        (queryable)
/// ├── moveLabel        (queryable)
/// ├── position         (queryable)
/// ├── promptType       (queryable)
/// ├── fingerprintText
/// ├── sourceVideoCount
/// ├── sourceSequenceIds
/// ├── generatedAt
/// ├── promptSent
/// └── tokensUsed
/// ```
class FingerprintFirebaseService {
    static let shared = FingerprintFirebaseService()

    private let db = Firestore.firestore()
    private let collectionName = "fingerprints"

    // MARK: - In-Memory Cache (keyed by creatorId, 5-min TTL)

    private var cachedFingerprints: [String: [FingerprintDocument]] = [:]
    private var cacheDates: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 300

    private func isCacheValid(for creatorId: String) -> Bool {
        guard let date = cacheDates[creatorId] else { return false }
        return Date().timeIntervalSince(date) < cacheTTL
    }

    func invalidateCache(creatorId: String) {
        cachedFingerprints.removeValue(forKey: creatorId)
        cacheDates.removeValue(forKey: creatorId)
    }

    private func invalidateAllCaches() {
        cachedFingerprints.removeAll()
        cacheDates.removeAll()
    }

    // MARK: - Save Single (Upsert via deterministic ID)

    func saveFingerprint(_ doc: FingerprintDocument) async throws {
        let docRef = db.collection(collectionName).document(doc.id)
        try docRef.setData(from: doc)
        print("Saved fingerprint: \(doc.id)")
        invalidateCache(creatorId: doc.creatorId)
    }

    // MARK: - Save Batch

    func saveFingerprints(_ docs: [FingerprintDocument]) async throws {
        guard !docs.isEmpty else { return }

        // Firestore batch limit is 500
        let chunks = stride(from: 0, to: docs.count, by: 500).map {
            Array(docs[$0..<min($0 + 500, docs.count)])
        }

        for chunk in chunks {
            let batch = db.batch()
            for doc in chunk {
                let docRef = db.collection(collectionName).document(doc.id)
                try batch.setData(from: doc, forDocument: docRef)
            }
            try await batch.commit()
        }

        print("Saved \(docs.count) fingerprints")

        // Invalidate caches for all affected creators
        let creatorIds = Set(docs.map { $0.creatorId })
        for id in creatorIds {
            invalidateCache(creatorId: id)
        }
    }

    // MARK: - Load All for Creator

    func loadFingerprints(creatorId: String, forceRefresh: Bool = false) async throws -> [FingerprintDocument] {
        if !forceRefresh, isCacheValid(for: creatorId),
           let cached = cachedFingerprints[creatorId] {
            return cached
        }

        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .getDocuments()

        var fingerprints: [FingerprintDocument] = []
        for doc in snapshot.documents {
            do {
                let fp = try doc.data(as: FingerprintDocument.self)
                fingerprints.append(fp)
            } catch {
                print("Failed to decode fingerprint \(doc.documentID): \(error)")
            }
        }

        cachedFingerprints[creatorId] = fingerprints
        cacheDates[creatorId] = Date()

        return fingerprints
    }

    // MARK: - Load All Types for One Slot

    func loadFingerprints(creatorId: String, moveLabel: String, position: String) async throws -> [FingerprintDocument] {
        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .whereField("moveLabel", isEqualTo: moveLabel)
            .whereField("position", isEqualTo: position)
            .getDocuments()

        var fingerprints: [FingerprintDocument] = []
        for doc in snapshot.documents {
            do {
                let fp = try doc.data(as: FingerprintDocument.self)
                fingerprints.append(fp)
            } catch {
                print("Failed to decode fingerprint \(doc.documentID): \(error)")
            }
        }
        return fingerprints
    }

    // MARK: - Load One Type Across All Slots

    func loadFingerprints(creatorId: String, promptType: FingerprintPromptType) async throws -> [FingerprintDocument] {
        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .whereField("promptType", isEqualTo: promptType.rawValue)
            .getDocuments()

        var fingerprints: [FingerprintDocument] = []
        for doc in snapshot.documents {
            do {
                let fp = try doc.data(as: FingerprintDocument.self)
                fingerprints.append(fp)
            } catch {
                print("Failed to decode fingerprint \(doc.documentID): \(error)")
            }
        }
        return fingerprints
    }

    // MARK: - Load Single Specific Fingerprint

    func loadFingerprint(creatorId: String, moveLabel: String, position: String, promptType: String) async throws -> FingerprintDocument? {
        let docId = "\(creatorId)_\(moveLabel)_\(position)_\(promptType)"
        let docRef = db.collection(collectionName).document(docId)
        let document = try await docRef.getDocument()

        guard document.exists else { return nil }
        return try document.data(as: FingerprintDocument.self)
    }

    // MARK: - Delete Single

    func deleteFingerprint(documentId: String) async throws {
        try await db.collection(collectionName).document(documentId).delete()
        print("Deleted fingerprint: \(documentId)")
        invalidateAllCaches()
    }

    // MARK: - Delete All for Creator

    func deleteAllFingerprints(creatorId: String) async throws {
        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .getDocuments()

        guard !snapshot.documents.isEmpty else { return }

        let chunks = stride(from: 0, to: snapshot.documents.count, by: 500).map {
            Array(snapshot.documents[$0..<min($0 + 500, snapshot.documents.count)])
        }

        for chunk in chunks {
            let batch = db.batch()
            for doc in chunk {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        print("Deleted \(snapshot.documents.count) fingerprints for creator: \(creatorId)")
        invalidateCache(creatorId: creatorId)
    }
}
