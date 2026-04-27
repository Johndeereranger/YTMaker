//
//  BoundaryDetectionModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

// MARK: - Boundary Trigger

/// What caused a chunk boundary to be detected
struct BoundaryTrigger: Codable, Hashable {
    let type: BoundaryTriggerType
    let sentenceIndex: Int
    let confidence: BoundaryConfidence

    enum BoundaryTriggerType: String, Codable, CaseIterable, Hashable {
        case transition = "transition"
        case sponsor = "sponsor"
        case cta = "cta"
        case contrastQuestion = "contrast_question"
        case reveal = "reveal"
        case perspectiveShift = "perspective_shift"

        var displayName: String {
            switch self {
            case .transition: return "Transition"
            case .sponsor: return "Sponsor Section"
            case .cta: return "Call to Action"
            case .contrastQuestion: return "Contrast + Question"
            case .reveal: return "Reveal Language"
            case .perspectiveShift: return "Perspective Shift"
            }
        }

        var description: String {
            switch self {
            case .transition: return "Explicit transition language (\"So let's look at\", \"Moving on\")"
            case .sponsor: return "Start of sponsorship content"
            case .cta: return "Start of call-to-action section"
            case .contrastQuestion: return "Contrast marker combined with questioning stance"
            case .reveal: return "Reveal language with first-person or transition"
            case .perspectiveShift: return "Shift from third-person to first-person questioning"
            }
        }
    }

    enum BoundaryConfidence: String, Codable, Hashable {
        case high = "high"
        case medium = "medium"
    }
}

// MARK: - Chunk Profile

/// Aggregate metadata about a chunk
struct ChunkProfile: Codable, Hashable {
    let dominantPerspective: DominantValue
    let dominantStance: DominantValue
    let tagDensity: TagDensity
    let boundaryTrigger: BoundaryTrigger?

    enum DominantValue: String, Codable, Hashable {
        case first = "first"
        case second = "second"
        case third = "third"
        case asserting = "asserting"
        case questioning = "questioning"
        case challenging = "challenging"
        case neutral = "neutral"
        case mixed = "mixed"
    }
}

// MARK: - Tag Density

/// Density of each tag type within a chunk (0.0 to 1.0)
struct TagDensity: Codable, Hashable {
    let hasNumber: Double
    let hasStatistic: Double
    let hasNamedEntity: Double
    let hasQuote: Double
    let hasContrastMarker: Double
    let hasRevealLanguage: Double
    let hasChallengeLanguage: Double
    let hasFirstPerson: Double
    let hasSecondPerson: Double
    let isTransition: Double
    let isSponsorContent: Double
    let isCallToAction: Double

    /// Get formatted percentages for display
    var displayValues: [(name: String, value: Double)] {
        [
            ("Numbers", hasNumber),
            ("Statistics", hasStatistic),
            ("Named Entities", hasNamedEntity),
            ("Quotes", hasQuote),
            ("Contrast", hasContrastMarker),
            ("Reveal", hasRevealLanguage),
            ("Challenge", hasChallengeLanguage),
            ("First Person", hasFirstPerson),
            ("Second Person", hasSecondPerson),
            ("Transitions", isTransition),
            ("Sponsor", isSponsorContent),
            ("CTA", isCallToAction)
        ].filter { $0.value > 0 }
    }

    /// Highest density tags
    var topTags: [(name: String, value: Double)] {
        let sorted = displayValues.sorted { $0.value > $1.value }
        return Array(sorted.prefix(3))
    }
}

// MARK: - Chunk

/// A detected chunk (section) of a video transcript
struct Chunk: Codable, Identifiable, Hashable {
    var id: Int { chunkIndex }

    let chunkIndex: Int
    let startSentence: Int
    let endSentence: Int
    let sentences: [SentenceTelemetry]
    let profile: ChunkProfile
    let positionInVideo: Double  // 0.0 to 1.0
    let sentenceCount: Int

    /// Text preview of the chunk (first few sentences)
    var preview: String {
        sentences.prefix(3).map { $0.text }.joined(separator: " ")
    }

    /// Full text of the chunk
    var fullText: String {
        sentences.map { $0.text }.joined(separator: " ")
    }

    /// Formatted position label
    var positionLabel: String {
        let percentage = Int(positionInVideo * 100)
        if percentage < 10 {
            return "Opening"
        } else if percentage < 30 {
            return "Early (\(percentage)%)"
        } else if percentage < 70 {
            return "Middle (\(percentage)%)"
        } else if percentage < 90 {
            return "Late (\(percentage)%)"
        } else {
            return "Closing"
        }
    }
}

// MARK: - Boundary Detection Result

/// Complete result of boundary detection on a video
struct BoundaryDetectionResult: Codable, Identifiable {
    let id: String
    let videoId: String
    let videoTitle: String
    let channelId: String
    let createdAt: Date

    let totalSentences: Int
    let chunks: [Chunk]

    // Detection metadata
    let detectionVersion: String
    let sourceFidelityTestId: String?  // Which sentence tagging run was used

    // Summary stats
    var chunkCount: Int { chunks.count }
    var averageChunkSize: Double {
        guard !chunks.isEmpty else { return 0 }
        return Double(totalSentences) / Double(chunks.count)
    }

    /// Distribution of boundary trigger types
    var triggerDistribution: [BoundaryTrigger.BoundaryTriggerType: Int] {
        var dist: [BoundaryTrigger.BoundaryTriggerType: Int] = [:]
        for chunk in chunks {
            if let trigger = chunk.profile.boundaryTrigger {
                dist[trigger.type, default: 0] += 1
            }
        }
        return dist
    }

    /// Chunks by position in video
    var chunksByPosition: (opening: [Chunk], middle: [Chunk], closing: [Chunk]) {
        let opening = chunks.filter { $0.positionInVideo < 0.15 }
        let closing = chunks.filter { $0.positionInVideo > 0.85 }
        let middle = chunks.filter { $0.positionInVideo >= 0.15 && $0.positionInVideo <= 0.85 }
        return (opening, middle, closing)
    }
}

// MARK: - Detection Parameters

/// Tunable parameters for boundary detection
struct BoundaryDetectionParams {
    /// Minimum position before reveal triggers fire (avoids hook reveals)
    var revealPositionThreshold: Double = 0.1

    /// Minimum sentences between boundaries
    var minChunkSize: Int = 3

    /// Whether to suppress CTA boundaries near end of video
    var suppressEndCTAs: Bool = true
    var endCTAThreshold: Double = 0.9

    /// Whether to create boundary when exiting sponsor section
    var boundaryOnSponsorExit: Bool = true

    static let `default` = BoundaryDetectionParams()
}

// MARK: - Audit Trail Models (Deep Dive Debug)

/// Result of evaluating a single boundary rule against a sentence pair
struct RuleEvaluation {
    let ruleNumber: Int
    let ruleName: String
    let ruleConfidence: BoundaryTrigger.BoundaryConfidence
    let fired: Bool
    let conditions: [ConditionResult]

    /// A single boolean sub-condition within a compound rule
    struct ConditionResult {
        let fieldName: String
        let actualValue: String
        let requiredValue: String
        let passed: Bool
    }
}

/// Complete audit trail for what happened when the algorithm visited a sentence
struct SentenceAuditRecord {
    let sentenceIndex: Int
    let current: SentenceTelemetry
    let previous: SentenceTelemetry?
    let distanceFromLastBoundary: Int
    let minChunkSizeRequired: Int
    let wasSuppressedByMinChunkSize: Bool
    let suppressedTriggerType: BoundaryTrigger.BoundaryTriggerType?
    let relativePosition: Double
    let rulesEvaluated: [RuleEvaluation]
    let firedTrigger: BoundaryTrigger?
    let wasBoundary: Bool
}

/// Complete audit trail for one boundary detection run
struct BoundaryAuditTrail {
    let videoTitle: String
    let totalSentences: Int
    let params: BoundaryDetectionParams
    let records: [SentenceAuditRecord]

    var boundaries: [SentenceAuditRecord] {
        records.filter { $0.wasBoundary }
    }

    var suppressions: [SentenceAuditRecord] {
        records.filter { $0.wasSuppressedByMinChunkSize }
    }

    var nearMisses: [SentenceAuditRecord] {
        records.filter { record in
            !record.wasBoundary && !record.wasSuppressedByMinChunkSize &&
            record.rulesEvaluated.contains { rule in
                !rule.fired && rule.conditions.contains(where: { $0.passed })
            }
        }
    }
}
