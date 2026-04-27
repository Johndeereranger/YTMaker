//
//  StructuralSequenceModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

// MARK: - Position Snapshot

/// A snapshot of what's happening at a normalized position in a video
struct PositionSnapshot: Codable, Hashable {
    let position: Double // 0.0 to 1.0 (binned, e.g., 0.1, 0.2, 0.3...)
    let chunkIndex: Int

    // Dominant characteristics at this position
    let dominantPerspective: ChunkProfile.DominantValue
    let dominantStance: ChunkProfile.DominantValue

    // Top active tags at this position (e.g., ["STAT", "1P", "CONTRAST"])
    let topTags: [String]

    // Spike indicators - is this tag significantly higher than average?
    let hasContrastSpike: Bool
    let hasRevealSpike: Bool
    let hasChallengeSpike: Bool
    let hasStatSpike: Bool
    let hasQuoteSpike: Bool

    // Is this a pivot point (significant shift from previous)?
    let isPivot: Bool
    let pivotReason: String?

    /// Short label for display
    var label: String {
        var parts: [String] = []

        // Add perspective
        switch dominantPerspective {
        case .first: parts.append("1P")
        case .second: parts.append("2P")
        case .third: parts.append("3P")
        default: break
        }

        // Add stance
        switch dominantStance {
        case .asserting: parts.append("ASS")
        case .questioning: parts.append("Q")
        case .challenging: parts.append("CH")
        default: break
        }

        // Add spikes
        if hasContrastSpike { parts.append("⚡CONT") }
        if hasRevealSpike { parts.append("⚡REV") }
        if hasStatSpike { parts.append("⚡STAT") }
        if hasQuoteSpike { parts.append("⚡QUOTE") }

        return parts.joined(separator: " ")
    }
}

// MARK: - Video Structure

/// The structural shape/sequence of a single video
struct VideoStructure: Codable, Identifiable, Hashable {
    var id: String { videoId }

    let videoId: String
    let videoTitle: String
    let channelId: String

    // Raw chunk data
    let chunkCount: Int
    let totalSentences: Int

    // The sequence of position snapshots (normalized to bins)
    let sequence: [PositionSnapshot]

    // Pivot points - where major structural shifts occur
    let pivotPositions: [Double]

    // Fingerprint for quick similarity comparison
    // This is a simplified encoding of the structure
    let fingerprint: StructuralFingerprint

    /// Text summary of the structure
    var structureSummary: String {
        var lines: [String] = []
        lines.append("\(videoTitle)")
        lines.append("Chunks: \(chunkCount), Pivots: \(pivotPositions.count)")

        for snapshot in sequence {
            let posLabel = String(format: "%.0f%%", snapshot.position * 100)
            let pivotMark = snapshot.isPivot ? " ← PIVOT" : ""
            lines.append("  [\(posLabel)] \(snapshot.label)\(pivotMark)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Structural Fingerprint

/// A simplified encoding of video structure for similarity comparison
struct StructuralFingerprint: Codable, Hashable {
    // 10-bin encoding (0-10%, 10-20%, etc.)
    // Each bin stores the dominant characteristics
    let bins: [BinProfile]

    // Key metrics
    let pivotCount: Int
    let firstPivotPosition: Double?
    let lastPivotPosition: Double?
    let dominantPattern: String // e.g., "1P-heavy", "stat-rich", "question-driven"

    struct BinProfile: Codable, Hashable {
        let binIndex: Int // 0-9
        let perspective: ChunkProfile.DominantValue
        let stance: ChunkProfile.DominantValue
        let hasSpike: Bool
        let spikeType: String? // "CONTRAST", "REVEAL", etc.
    }

    /// Calculate similarity to another fingerprint (0.0 to 1.0)
    func similarity(to other: StructuralFingerprint) -> Double {
        var matchScore = 0.0
        let binCount = Double(min(bins.count, other.bins.count))
        guard binCount > 0 else { return 0 }

        for i in 0..<Int(binCount) {
            let myBin = bins[i]
            let otherBin = other.bins[i]

            // Perspective match (0.3 weight)
            if myBin.perspective == otherBin.perspective {
                matchScore += 0.3
            }

            // Stance match (0.3 weight)
            if myBin.stance == otherBin.stance {
                matchScore += 0.3
            }

            // Spike match (0.4 weight)
            if myBin.hasSpike == otherBin.hasSpike {
                matchScore += 0.2
                if myBin.spikeType == otherBin.spikeType {
                    matchScore += 0.2
                }
            }
        }

        let baseSimilarity = matchScore / binCount

        // Bonus for similar pivot patterns
        var pivotBonus = 0.0
        if pivotCount == other.pivotCount {
            pivotBonus += 0.05
        }
        if let myFirst = firstPivotPosition, let otherFirst = other.firstPivotPosition {
            if abs(myFirst - otherFirst) < 0.15 {
                pivotBonus += 0.05
            }
        }

        return min(1.0, baseSimilarity + pivotBonus)
    }
}

// MARK: - Structural Template

/// A cluster of videos with similar structure - the actual "template"
struct StructuralTemplate: Codable, Identifiable {
    let id: String
    let templateName: String // "Journey", "Deep Dive", "Evidence Stack", etc.
    let channelId: String

    // Videos in this cluster
    let videoCount: Int
    let videoIds: [String]
    let exampleVideoTitles: [String] // 3-5 example titles

    // The representative/typical sequence for this template
    let typicalSequence: [TemplateChunk]

    // Key characteristics
    let keyPivots: [PivotPoint]
    let averageChunkCount: Double
    let dominantCharacteristics: [String] // e.g., ["1P-heavy", "late-contrast"]

    // Confidence/quality
    let clusterTightness: Double // How similar are videos in this cluster (0-1)
}

// MARK: - Template Chunk

/// A chunk in the typical sequence of a structural template
struct TemplateChunk: Codable, Identifiable, Hashable {
    var id: Int { chunkIndex }

    let chunkIndex: Int
    let positionStart: Double // 0.0 to 1.0
    let positionEnd: Double   // 0.0 to 1.0

    // What typically happens here
    let typicalRole: String // "Opening hook", "Evidence block", "Pivot", etc.
    let dominantPerspective: ChunkProfile.DominantValue
    let dominantStance: ChunkProfile.DominantValue

    // What tags are typically high here
    let highTags: [String] // e.g., ["1P", "STAT", "CONTRAST"]

    // Is this a pivot point?
    let isPivotPoint: Bool
    let pivotDescription: String?

    /// Formatted position range
    var positionLabel: String {
        String(format: "[%.0f%%-%.0f%%]", positionStart * 100, positionEnd * 100)
    }

    /// One-line summary
    var summary: String {
        var parts = [positionLabel, typicalRole]
        if !highTags.isEmpty {
            parts.append("high \(highTags.joined(separator: "+"))")
        }
        if isPivotPoint, let desc = pivotDescription {
            parts.append("← \(desc)")
        }
        return parts.joined(separator: " - ")
    }
}

// MARK: - Pivot Point

/// A significant structural shift point
struct PivotPoint: Codable, Hashable {
    let position: Double // 0.0 to 1.0
    let chunkIndex: Int
    let pivotType: PivotType
    let description: String

    enum PivotType: String, Codable {
        case contrastSpike = "contrast_spike"
        case revealSpike = "reveal_spike"
        case perspectiveShift = "perspective_shift"
        case stanceShift = "stance_shift"
        case topicTransition = "topic_transition"
    }

    var label: String {
        String(format: "%.0f%% - %@", position * 100, description)
    }
}

// MARK: - Clustering Result

/// Result of clustering videos by structural similarity
struct ClusteringResult: Codable {
    let channelId: String
    let channelName: String
    let createdAt: Date

    // All video structures that were analyzed
    let videoStructures: [VideoStructure]

    // The resulting structural templates
    let templates: [StructuralTemplate]

    // Unclustered videos (too unique to fit a template)
    let outlierVideoIds: [String]

    // Quality metrics
    let averageClusterTightness: Double
    let coveragePercent: Double // % of videos that fit a template

    /// Summary text
    var summary: String {
        var lines: [String] = []
        lines.append("=== STRUCTURAL TEMPLATES FOR \(channelName.uppercased()) ===")
        lines.append("Analyzed \(videoStructures.count) videos")
        lines.append("Found \(templates.count) distinct structural patterns")
        lines.append("Coverage: \(Int(coveragePercent * 100))% of videos fit a template")
        lines.append("")

        for template in templates.sorted(by: { $0.videoCount > $1.videoCount }) {
            lines.append("---")
            lines.append("TEMPLATE: \"\(template.templateName)\" (used in \(template.videoCount) videos)")
            lines.append("Typical chunk sequence:")

            for chunk in template.typicalSequence {
                let pivotMark = chunk.isPivotPoint ? " ← PIVOT" : ""
                lines.append("  \(chunk.chunkIndex + 1). \(chunk.positionLabel) \(chunk.typicalRole) - \(chunk.highTags.joined(separator: ", "))\(pivotMark)")
            }

            if !template.keyPivots.isEmpty {
                lines.append("Key pivots: \(template.keyPivots.map { $0.label }.joined(separator: ", "))")
            }

            lines.append("Similar videos (\(template.exampleVideoTitles.count)): \(template.exampleVideoTitles.joined(separator: ", "))")
        }

        if !outlierVideoIds.isEmpty {
            lines.append("")
            lines.append("Outliers (\(outlierVideoIds.count) videos with unique structure)")
        }

        return lines.joined(separator: "\n")
    }
}
