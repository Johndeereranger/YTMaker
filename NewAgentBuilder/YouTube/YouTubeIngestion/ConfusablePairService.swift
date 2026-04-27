//
//  ConfusablePairService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/16/26.
//

import Foundation
import FirebaseFirestore

// MARK: - Confusable Pair Service

/// Manages discovery, storage, and query expansion for confusable slot label pairs.
/// Confusable pairs are slot labels that the LLM assigns interchangeably at the same
/// phrase position across repeated annotation runs.
class ConfusablePairService {
    static let shared = ConfusablePairService()

    private let db = Firestore.firestore()
    private let collectionName = "confusable_pairs"

    // MARK: - Extract Pairs from Fidelity Comparisons

    /// Extracts confusable pairs from fidelity test comparisons.
    /// Walks each sentence's phrase alignment looking for non-unanimous positions,
    /// then creates a ConfusablePair for every distinct role pair at that position.
    func extractPairs(
        from comparisons: [SlotFidelitySentenceComparison],
        moveType: String,
        creatorId: String,
        videoId: String
    ) -> [ConfusablePair] {
        // Accumulator: keyed by deterministic ID to merge duplicates within this extraction
        var pairMap: [String: ConfusablePair] = [:]

        for comp in comparisons {
            // Only look at sentences where the signature diverged
            guard !comp.runsAgreedOnSignature else { continue }

            for (position, alignment) in comp.phraseAlignment.enumerated() {
                // Only care about divergent phrases
                guard !alignment.isUnanimous else { continue }

                // Collect distinct roles at this position (excluding "missing")
                let distinctRoles = Set(alignment.rolesPerRun.values.filter { $0 != "missing" })
                guard distinctRoles.count >= 2 else { continue }

                let totalRuns = alignment.rolesPerRun.values.filter { $0 != "missing" }.count

                // For every pair of distinct roles, create/increment a confusable pair
                let sortedRoles = distinctRoles.sorted()
                for i in 0..<sortedRoles.count {
                    for j in (i + 1)..<sortedRoles.count {
                        let pair = ConfusablePair.create(
                            moveType: moveType,
                            slotPosition: position,
                            label1: sortedRoles[i],
                            label2: sortedRoles[j],
                            creatorId: creatorId,
                            swapCount: 1,
                            sampleSize: totalRuns,
                            videoId: videoId
                        )

                        if let existing = pairMap[pair.id] {
                            pairMap[pair.id] = existing.merging(
                                additionalSwaps: 1,
                                additionalSamples: totalRuns,
                                videoId: videoId
                            )
                        } else {
                            pairMap[pair.id] = pair
                        }
                    }
                }
            }
        }

        return Array(pairMap.values).sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Firebase Save (Upsert)

    /// Saves confusable pairs to Firebase. If a pair with the same ID already exists,
    /// merges the counts (upsert). Otherwise creates a new document.
    func savePairs(_ pairs: [ConfusablePair]) async throws {
        guard !pairs.isEmpty else { return }

        for pair in pairs {
            let docRef = db.collection(collectionName).document(pair.id)
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
                    "moveType": pair.moveType,
                    "slotPosition": pair.slotPosition,
                    "labelA": pair.labelA,
                    "labelB": pair.labelB,
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
    }

    // MARK: - Firebase Load

    /// Load all confusable pairs, optionally filtered by moveType and/or creatorId.
    func loadPairs(moveType: String? = nil, creatorId: String? = nil) async throws -> [ConfusablePair] {
        var query: Query = db.collection(collectionName)

        if let moveType = moveType {
            query = query.whereField("moveType", isEqualTo: moveType)
        }
        if let creatorId = creatorId {
            query = query.whereField("creatorId", isEqualTo: creatorId)
        }

        let snapshot = try await query.getDocuments()

        return snapshot.documents.compactMap { doc in
            parsePair(doc.data())
        }.sorted { $0.confidence > $1.confidence }
    }

    private func parsePair(_ data: [String: Any]) -> ConfusablePair? {
        guard let id = data["id"] as? String,
              let moveType = data["moveType"] as? String,
              let slotPosition = data["slotPosition"] as? Int,
              let labelA = data["labelA"] as? String,
              let labelB = data["labelB"] as? String,
              let creatorId = data["creatorId"] as? String else {
            return nil
        }

        let swapCount = data["swapCount"] as? Int ?? 0
        let sampleSize = data["sampleSize"] as? Int ?? 0
        let confidence = data["confidence"] as? Double ?? 0

        return ConfusablePair(
            id: id,
            moveType: moveType,
            slotPosition: slotPosition,
            labelA: labelA,
            labelB: labelB,
            creatorId: creatorId,
            swapCount: swapCount,
            sampleSize: sampleSize,
            confidence: confidence,
            sourceVideoIds: data["sourceVideoIds"] as? [String] ?? [],
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Firebase Delete

    /// Delete a single confusable pair by ID.
    func deletePair(id: String) async throws {
        try await db.collection(collectionName).document(id).delete()
    }

    /// Delete all confusable pairs for a given moveType.
    func deletePairs(moveType: String) async throws {
        let snapshot = try await db.collection(collectionName)
            .whereField("moveType", isEqualTo: moveType)
            .getDocuments()

        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }

    // MARK: - Build Lookup Index

    /// Builds a lightweight in-memory lookup from loaded confusable pairs.
    /// The index is bidirectional: if A↔B are confusable, looking up A returns B and vice versa.
    func buildLookup(from pairs: [ConfusablePair]) -> ConfusableLookup {
        var index: [String: [String: Set<String>]] = [:]

        for pair in pairs {
            // A -> B
            index[pair.moveType, default: [:]][pair.labelA, default: []].insert(pair.labelB)
            // B -> A
            index[pair.moveType, default: [:]][pair.labelB, default: []].insert(pair.labelA)
        }

        return ConfusableLookup(index: index)
    }

    // MARK: - Expand Signature

    /// Expands a slot signature into all variant signatures by substituting confusable labels.
    /// Returns the original signature plus all variants.
    ///
    /// Example: signature "emotional_reaction|geographic_location" with confusable
    /// pair (emotional_reaction ↔ personal_commentary) at position 0 returns:
    /// ["emotional_reaction|geographic_location", "personal_commentary|geographic_location"]
    func expandSignature(
        _ signature: String,
        using lookup: ConfusableLookup,
        moveType: String
    ) -> [String] {
        let slots = signature.components(separatedBy: "|")
        guard !slots.isEmpty else { return [signature] }

        // Build per-position variant arrays
        var slotVariants: [[String]] = []
        for slot in slots {
            var variants = [slot]
            let alternates = lookup.alternates(for: slot, moveType: moveType)
            variants.append(contentsOf: alternates.sorted())
            slotVariants.append(variants)
        }

        // Cartesian product of all slot variant combinations
        var results: [String] = []
        cartesianProduct(slotVariants, current: [], results: &results)

        return results
    }

    /// Recursively builds the cartesian product of slot variant arrays.
    private func cartesianProduct(
        _ arrays: [[String]],
        current: [String],
        results: inout [String]
    ) {
        if current.count == arrays.count {
            results.append(current.joined(separator: "|"))
            return
        }

        let position = current.count
        for variant in arrays[position] {
            cartesianProduct(arrays, current: current + [variant], results: &results)
        }
    }
}
