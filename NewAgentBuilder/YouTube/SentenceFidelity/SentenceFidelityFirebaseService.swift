//
//  SentenceFidelityFirebaseService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation
import FirebaseFirestore

/// Firebase service for sentence fidelity tests
/// Completely isolated from main YouTube data - uses its own collection
class SentenceFidelityFirebaseService {

    static let shared = SentenceFidelityFirebaseService()

    private let db = Firestore.firestore()
    private let collectionName = "sentenceFidelityTests"

    private init() {}

    // MARK: - Save Test Run

    /// Save a new fidelity test run
    func saveTestRun(_ test: SentenceFidelityTest) async throws {
        let docRef = db.collection(collectionName).document(test.id)
        let data = try Firestore.Encoder().encode(test)
        try await docRef.setData(data)
        print("Saved sentence fidelity test: \(test.id)")
    }

    // MARK: - Load Tests

    /// Get all test runs for a video
    func getTestRuns(forVideoId videoId: String) async throws -> [SentenceFidelityTest] {
        let snapshot = try await db.collection(collectionName)
            .whereField("videoId", isEqualTo: videoId)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: SentenceFidelityTest.self)
        }
    }

    /// Get a specific test run by ID
    func getTestRun(id: String) async throws -> SentenceFidelityTest? {
        let doc = try await db.collection(collectionName).document(id).getDocument()
        return try? doc.data(as: SentenceFidelityTest.self)
    }

    /// Get the next run number for a video
    func getNextRunNumber(forVideoId videoId: String) async throws -> Int {
        let existingRuns = try await getTestRuns(forVideoId: videoId)
        let maxRun = existingRuns.map { $0.runNumber }.max() ?? 0
        return maxRun + 1
    }

    // MARK: - Fetch All (for audit tools)

    /// Fetch all test runs, keeping only the latest run per video
    func getAllTestRuns() async throws -> [SentenceFidelityTest] {
        let snapshot = try await db.collection(collectionName)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let allTests = snapshot.documents.compactMap { doc in
            try? doc.data(as: SentenceFidelityTest.self)
        }

        // Keep only the latest run per video (already sorted newest-first)
        var seen = Set<String>()
        var latestPerVideo: [SentenceFidelityTest] = []
        for test in allTests {
            if !seen.contains(test.videoId) {
                seen.insert(test.videoId)
                latestPerVideo.append(test)
            }
        }

        return latestPerVideo
    }

    // MARK: - Delete

    /// Delete a test run
    func deleteTestRun(id: String) async throws {
        try await db.collection(collectionName).document(id).delete()
        print("Deleted sentence fidelity test: \(id)")
    }

    /// Delete all test runs for a video
    func deleteAllTestRuns(forVideoId videoId: String) async throws {
        let runs = try await getTestRuns(forVideoId: videoId)
        for run in runs {
            try await deleteTestRun(id: run.id)
        }
    }

    /// Delete ALL sentence fidelity tests across all videos
    func deleteAllTestRuns() async throws -> Int {
        let snapshot = try await db.collection(collectionName).getDocuments()
        let docs = snapshot.documents
        guard !docs.isEmpty else {
            print("No sentence fidelity tests to delete")
            return 0
        }

        for chunk in stride(from: 0, to: docs.count, by: 500) {
            let batch = db.batch()
            let end = min(chunk + 500, docs.count)
            for i in chunk..<end {
                batch.deleteDocument(docs[i].reference)
            }
            try await batch.commit()
        }

        print("Deleted \(docs.count) sentence fidelity tests")
        return docs.count
    }

    // MARK: - Batch Queries

    /// Get video IDs that have sentence analysis data
    func getVideoIdsWithAnalysis(forChannelId channelId: String) async throws -> Set<String> {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        let videoIds = snapshot.documents.compactMap { doc -> String? in
            doc.data()["videoId"] as? String
        }
        return Set(videoIds)
    }

    /// Get all test runs for multiple videos at once (for batch display)
    func getTestRunsForVideos(_ videoIds: [String]) async throws -> [String: [SentenceFidelityTest]] {
        guard !videoIds.isEmpty else { return [:] }

        // Firestore 'in' queries are limited to 30 items, so batch them
        var result: [String: [SentenceFidelityTest]] = [:]
        for chunk in videoIds.chunked(into: 30) {
            let snapshot = try await db.collection(collectionName)
                .whereField("videoId", in: chunk)
                .getDocuments()

            for doc in snapshot.documents {
                if let test = try? doc.data(as: SentenceFidelityTest.self) {
                    result[test.videoId, default: []].append(test)
                }
            }
        }

        // Sort each video's runs by date (newest first)
        for (videoId, runs) in result {
            result[videoId] = runs.sorted { $0.createdAt > $1.createdAt }
        }

        return result
    }

    // MARK: - Update Comparison

    /// Update a test run with comparison data
    func updateComparison(
        testId: String,
        comparedToRunId: String,
        stabilityScore: Double,
        fieldStability: [String: Double]
    ) async throws {
        let docRef = db.collection(collectionName).document(testId)
        try await docRef.updateData([
            "comparedToRunId": comparedToRunId,
            "stabilityScore": stabilityScore,
            "fieldStability": fieldStability
        ])
    }
}
