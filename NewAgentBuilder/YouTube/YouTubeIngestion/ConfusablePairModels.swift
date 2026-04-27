//
//  ConfusablePairModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/16/26.
//

import Foundation

// MARK: - ConfusablePair (Firebase: confusable_pairs collection)

/// Records that two slot labels are interchangeable at a given position within a section type.
/// Built from fidelity test runs where the LLM assigned different labels to the same phrase
/// across repeated annotations.
struct ConfusablePair: Codable, Identifiable, Hashable {
    let id: String                      // "{moveType}_{slotPosition}_{labelA}_{labelB}" (deterministic)
    let moveType: String                // RhetoricalMoveType raw value (e.g. "scene_set")
    let slotPosition: Int               // 0-based index in the slot sequence
    let labelA: String                  // Alphabetically first label
    let labelB: String                  // Alphabetically second label
    let creatorId: String               // channelId — enables future global-vs-creator analysis
    var swapCount: Int                  // Times this swap was observed across runs
    var sampleSize: Int                 // Total observations at this position
    var confidence: Double              // swapCount / sampleSize
    var sourceVideoIds: [String]        // Videos that contributed evidence
    let createdAt: Date
    var updatedAt: Date

    /// Creates a ConfusablePair with labels automatically sorted alphabetically.
    /// This ensures (A,B) and (B,A) always produce the same deterministic ID.
    static func create(
        moveType: String,
        slotPosition: Int,
        label1: String,
        label2: String,
        creatorId: String,
        swapCount: Int,
        sampleSize: Int,
        videoId: String
    ) -> ConfusablePair {
        let sorted = [label1, label2].sorted()
        let labelA = sorted[0]
        let labelB = sorted[1]
        let id = "\(moveType)_\(slotPosition)_\(labelA)_\(labelB)"
        let confidence = sampleSize > 0 ? Double(swapCount) / Double(sampleSize) : 0

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
            sourceVideoIds: [videoId],
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Merge new evidence into this pair (for upsert). Returns updated copy.
    func merging(additionalSwaps: Int, additionalSamples: Int, videoId: String) -> ConfusablePair {
        var updated = self
        updated.swapCount += additionalSwaps
        updated.sampleSize += additionalSamples
        updated.confidence = updated.sampleSize > 0
            ? Double(updated.swapCount) / Double(updated.sampleSize)
            : 0
        if !updated.sourceVideoIds.contains(videoId) {
            updated.sourceVideoIds.append(videoId)
        }
        updated.updatedAt = Date()
        return updated
    }
}

// MARK: - ConfusableLookup (in-memory query expansion index)

/// Lightweight structure for fast confusable pair lookups at query time.
/// Built from loaded ConfusablePair records, keyed by moveType then slotLabel.
struct ConfusableLookup {
    /// moveType -> slotLabel -> set of confusable alternate labels
    let index: [String: [String: Set<String>]]

    /// Returns all confusable alternates for a label within a given moveType.
    /// Returns empty set if no confusables exist.
    func alternates(for label: String, moveType: String) -> Set<String> {
        index[moveType]?[label] ?? []
    }

    /// True if no confusable pairs are loaded.
    var isEmpty: Bool {
        index.isEmpty
    }

    /// Total number of unique confusable relationships across all moveTypes.
    var totalPairCount: Int {
        index.values.reduce(0) { total, labelMap in
            total + labelMap.values.reduce(0) { $0 + $1.count }
        } / 2 // Each pair is stored bidirectionally
    }
}
