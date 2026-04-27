//
//  SpineAlignmentFirebaseService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/2/26.
//

import Foundation
import FirebaseFirestore

class SpineAlignmentFirebaseService {
    static let shared = SpineAlignmentFirebaseService()
    private let db = Firestore.firestore()
    private let alignmentCollection = "spine_rhetorical_alignments"
    private let mappingTableCollection = "spine_rhetorical_mapping_tables"
    private let confusablePairCollection = "spine_alignment_confusable_pairs"

    private init() {}

    // MARK: - Save Alignment (multi-run: doc ID = "{videoId}_run{N}")

    func saveAlignment(_ alignment: SpineRhetoricalAlignment) async throws {
        let docId = "\(alignment.videoId)_run\(alignment.runNumber)"
        let docRef = db.collection(alignmentCollection).document(docId)
        try docRef.setData(from: alignment)
        print("✅ Saved spine-rhetorical alignment run \(alignment.runNumber) for video \(alignment.videoId) (\(alignment.beatAlignments.count) beats, \(alignment.unmappedMoves.count) unmapped)")
    }

    // MARK: - Load Single Run

    func loadAlignment(videoId: String, runNumber: Int) async throws -> SpineRhetoricalAlignment? {
        let docId = "\(videoId)_run\(runNumber)"
        let docRef = db.collection(alignmentCollection).document(docId)
        let snapshot = try await docRef.getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: SpineRhetoricalAlignment.self)
    }

    // MARK: - Load All Runs for a Video

    func loadAllRuns(videoId: String) async throws -> [SpineRhetoricalAlignment] {
        let snapshot = try await db.collection(alignmentCollection)
            .whereField("videoId", isEqualTo: videoId)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: SpineRhetoricalAlignment.self)
        }.sorted { $0.runNumber < $1.runNumber }
    }

    // MARK: - Load Alignments for Channel (bulk — returns all runs for all videos)

    func loadAlignments(channelId: String) async throws -> [SpineRhetoricalAlignment] {
        let snapshot = try await db.collection(alignmentCollection)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: SpineRhetoricalAlignment.self)
        }
    }

    // MARK: - Delete All Runs for a Video

    func deleteAlignments(videoId: String) async throws {
        let runs = try await loadAllRuns(videoId: videoId)
        for run in runs {
            let docId = "\(videoId)_run\(run.runNumber)"
            try await db.collection(alignmentCollection).document(docId).delete()
        }
        print("🗑️ Deleted \(runs.count) spine-rhetorical alignment runs for video \(videoId)")
    }

    // MARK: - Mark Run Complete on Video Doc (increments completedRunCount)

    func markRunComplete(
        videoId: String,
        runNumber: Int,
        beatCount: Int,
        orphanBeatCount: Int,
        unmappedMoveCount: Int
    ) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)

        try await docRef.setData([
            "spineAlignmentStatus": [
                "complete": true,
                "completedRunCount": runNumber,
                "beatCount": beatCount,
                "orphanBeatCount": orphanBeatCount,
                "unmappedMoveCount": unmappedMoveCount,
                "lastUpdated": Timestamp(date: Date())
            ]
        ], merge: true)
    }

    // MARK: - Clear Alignment Status

    func clearAlignmentStatus(videoId: String) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)

        try await docRef.setData([
            "spineAlignmentStatus": [
                "complete": false,
                "completedRunCount": 0,
                "beatCount": 0,
                "orphanBeatCount": 0,
                "unmappedMoveCount": 0,
                "lastUpdated": Timestamp(date: Date())
            ]
        ], merge: true)
    }

    // MARK: - Save Mapping Table

    func saveMappingTable(_ table: SpineRhetoricalMappingTable) async throws {
        let docRef = db.collection(mappingTableCollection).document(table.channelId)
        try docRef.setData(from: table)
        print("✅ Saved mapping table for channel \(table.channelId) (\(table.functionMappings.count) functions, \(table.videoCount) videos)")
    }

    // MARK: - Load Mapping Table

    func loadMappingTable(channelId: String) async throws -> SpineRhetoricalMappingTable? {
        let docRef = db.collection(mappingTableCollection).document(channelId)
        let snapshot = try await docRef.getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: SpineRhetoricalMappingTable.self)
    }

    // MARK: - Confusable Pairs: Save (Additive Upsert)

    func saveConfusablePairs(_ pairs: [SpineAlignmentConfusablePair]) async throws {
        guard !pairs.isEmpty else { return }

        for pair in pairs {
            let docRef = db.collection(confusablePairCollection).document(pair.id)
            let existing = try await docRef.getDocument()

            if existing.exists, let data = existing.data() {
                // Merge counts with existing record
                let existingSwapCount = data["swapCount"] as? Int ?? 0
                let existingSampleSize = data["sampleSize"] as? Int ?? 0
                let existingVideoIds = data["sourceVideoIds"] as? [String] ?? []

                let mergedSwapCount = existingSwapCount + pair.swapCount
                let mergedSampleSize = existingSampleSize + pair.sampleSize
                let mergedConfidence = mergedSampleSize > 0
                    ? Double(mergedSwapCount) / Double(mergedSampleSize)
                    : 0.0
                let mergedVideoIds = Array(Set(existingVideoIds + pair.sourceVideoIds))

                try await docRef.updateData([
                    "swapCount": mergedSwapCount,
                    "sampleSize": mergedSampleSize,
                    "confidence": mergedConfidence,
                    "sourceVideoIds": mergedVideoIds,
                    "updatedAt": Timestamp(date: Date())
                ])
            } else {
                // New record
                let dict: [String: Any] = [
                    "id": pair.id,
                    "function": pair.function,
                    "moveA": pair.moveA,
                    "moveB": pair.moveB,
                    "creatorId": pair.creatorId,
                    "swapCount": pair.swapCount,
                    "sampleSize": pair.sampleSize,
                    "confidence": pair.confidence,
                    "sourceVideoIds": pair.sourceVideoIds,
                    "createdAt": Timestamp(date: pair.createdAt),
                    "updatedAt": Timestamp(date: pair.updatedAt)
                ]
                try await docRef.setData(dict)
            }
        }
        print("✅ Saved \(pairs.count) spine alignment confusable pairs")
    }

    // MARK: - Confusable Pairs: Load

    func loadConfusablePairs(creatorId: String) async throws -> [SpineAlignmentConfusablePair] {
        let snapshot = try await db.collection(confusablePairCollection)
            .whereField("creatorId", isEqualTo: creatorId)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let id = data["id"] as? String,
                  let function = data["function"] as? String,
                  let moveA = data["moveA"] as? String,
                  let moveB = data["moveB"] as? String,
                  let creatorId = data["creatorId"] as? String,
                  let swapCount = data["swapCount"] as? Int,
                  let sampleSize = data["sampleSize"] as? Int,
                  let confidence = data["confidence"] as? Double else { return nil }

            let sourceVideoIds = data["sourceVideoIds"] as? [String] ?? []
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

            return SpineAlignmentConfusablePair(
                id: id, function: function,
                moveA: moveA, moveB: moveB,
                creatorId: creatorId,
                swapCount: swapCount, sampleSize: sampleSize,
                confidence: confidence,
                sourceVideoIds: sourceVideoIds,
                createdAt: createdAt, updatedAt: updatedAt
            )
        }.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Confusable Pairs: Delete All for Creator

    func deleteConfusablePairs(creatorId: String) async throws {
        let snapshot = try await db.collection(confusablePairCollection)
            .whereField("creatorId", isEqualTo: creatorId)
            .getDocuments()

        for doc in snapshot.documents {
            try await doc.reference.delete()
        }
        print("🗑️ Deleted \(snapshot.documents.count) confusable pairs for creator \(creatorId)")
    }
}
