//
//  SectionQuestionsFirebaseService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/29/26.
//

import Foundation
import FirebaseFirestore

/// Firebase CRUD for the `section_questions` collection.
///
/// Document structure:
/// ```
/// section_questions/{creatorId}_{videoId}_{chunkIndex}
/// ├── creatorId        (queryable)
/// ├── videoId          (queryable)
/// ├── moveLabel        (queryable)
/// ├── position         (queryable)
/// ├── questionsAnswered
/// ├── sectionText
/// ├── briefDescription
/// ├── videoTitle
/// ├── chunkIndex
/// ├── generatedAt
/// ├── promptSent
/// ├── systemPromptSent
/// └── tokensUsed
/// ```
class SectionQuestionsFirebaseService {
    static let shared = SectionQuestionsFirebaseService()

    private let db = Firestore.firestore()
    private let collectionName = "section_questions"

    // MARK: - In-Memory Cache (keyed by creatorId, 5-min TTL)

    private var cachedDocs: [String: [SectionQuestionsDocument]] = [:]
    private var cacheDates: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 300

    private func isCacheValid(for creatorId: String) -> Bool {
        guard let date = cacheDates[creatorId] else { return false }
        return Date().timeIntervalSince(date) < cacheTTL
    }

    func invalidateCache(creatorId: String) {
        cachedDocs.removeValue(forKey: creatorId)
        cacheDates.removeValue(forKey: creatorId)
    }

    private func invalidateAllCaches() {
        cachedDocs.removeAll()
        cacheDates.removeAll()
    }

    // MARK: - Save Single (Upsert via deterministic ID)

    func save(_ doc: SectionQuestionsDocument) async throws {
        let docRef = db.collection(collectionName).document(doc.id)
        try docRef.setData(from: doc)
        print("Saved section question: \(doc.id)")
        invalidateCache(creatorId: doc.creatorId)
    }

    // MARK: - Save Batch

    func saveBatch(_ docs: [SectionQuestionsDocument]) async throws {
        guard !docs.isEmpty else { return }

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

        print("Saved \(docs.count) section questions")

        let creatorIds = Set(docs.map { $0.creatorId })
        for id in creatorIds {
            invalidateCache(creatorId: id)
        }
    }

    // MARK: - Load All for Creator

    func loadAll(creatorId: String, forceRefresh: Bool = false) async throws -> [SectionQuestionsDocument] {
        if !forceRefresh, isCacheValid(for: creatorId),
           let cached = cachedDocs[creatorId] {
            return cached
        }

        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .getDocuments()

        let docs = decodeDocuments(snapshot)

        cachedDocs[creatorId] = docs
        cacheDates[creatorId] = Date()

        return docs
    }

    // MARK: - Load by Position

    func load(creatorId: String, position: String) async throws -> [SectionQuestionsDocument] {
        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .whereField("position", isEqualTo: position)
            .getDocuments()

        return decodeDocuments(snapshot)
    }

    // MARK: - Load by Move Label

    func load(creatorId: String, moveLabel: String) async throws -> [SectionQuestionsDocument] {
        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .whereField("moveLabel", isEqualTo: moveLabel)
            .getDocuments()

        return decodeDocuments(snapshot)
    }

    // MARK: - Load by Move Label AND Position

    func load(creatorId: String, moveLabel: String, position: String) async throws -> [SectionQuestionsDocument] {
        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .whereField("moveLabel", isEqualTo: moveLabel)
            .whereField("position", isEqualTo: position)
            .getDocuments()

        return decodeDocuments(snapshot)
    }

    // MARK: - Load for Specific Video

    func load(creatorId: String, videoId: String) async throws -> [SectionQuestionsDocument] {
        let snapshot = try await db.collection(collectionName)
            .whereField("creatorId", isEqualTo: creatorId)
            .whereField("videoId", isEqualTo: videoId)
            .getDocuments()

        return decodeDocuments(snapshot)
    }

    // MARK: - Delete Single

    func delete(documentId: String) async throws {
        try await db.collection(collectionName).document(documentId).delete()
        print("Deleted section question: \(documentId)")
        invalidateAllCaches()
    }

    // MARK: - Delete All for Creator

    func deleteAll(creatorId: String) async throws {
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

        print("Deleted \(snapshot.documents.count) section questions for creator: \(creatorId)")
        invalidateCache(creatorId: creatorId)
    }

    // MARK: - Decode Helper

    private func decodeDocuments(_ snapshot: QuerySnapshot) -> [SectionQuestionsDocument] {
        var results: [SectionQuestionsDocument] = []
        for doc in snapshot.documents {
            do {
                let decoded = try doc.data(as: SectionQuestionsDocument.self)
                results.append(decoded)
            } catch {
                print("Failed to decode section question \(doc.documentID): \(error)")
            }
        }
        return results
    }
}
