//
//  FingerprintModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/14/26.
//

import Foundation
import SwiftUI

// MARK: - Prompt Type Registry

/// Each case represents an independent fingerprint prompt.
/// Adding a new prompt type: add a case here, then add its system prompt in FingerprintPromptEngine.
/// Everything else (Firebase, UI, generation, batch) picks it up automatically via CaseIterable.
enum FingerprintPromptType: String, Codable, CaseIterable {
    case comprehensive         = "comprehensive"
    case layer3Discovery       = "layer3_discovery"
    case narrativeLens         = "narrative_lens"
    case registerAnalysis      = "register_analysis"
    case sentenceConstruction  = "sentence_construction"
    case mechanicalFingerprint = "mechanical_fingerprint"

    var displayName: String {
        switch self {
        case .comprehensive:         return "Comprehensive"
        case .layer3Discovery:       return "Layer 3 Discovery"
        case .narrativeLens:         return "Narrative Lens"
        case .registerAnalysis:      return "Register Analysis"
        case .sentenceConstruction:  return "Sentence Construction"
        case .mechanicalFingerprint: return "Mechanical Fingerprint"
        }
    }

    var shortLabel: String {
        switch self {
        case .comprehensive:         return "CMP"
        case .layer3Discovery:       return "L3D"
        case .narrativeLens:         return "NRL"
        case .registerAnalysis:      return "REG"
        case .sentenceConstruction:  return "SEN"
        case .mechanicalFingerprint: return "MEC"
        }
    }

    var iconName: String {
        switch self {
        case .comprehensive:         return "doc.text.magnifyingglass"
        case .layer3Discovery:       return "square.3.layers.3d"
        case .narrativeLens:         return "list.bullet.rectangle.portrait"
        case .registerAnalysis:      return "person.text.rectangle"
        case .sentenceConstruction:  return "text.line.first.and.arrowtriangle.forward"
        case .mechanicalFingerprint: return "number"
        }
    }

    var tintColor: Color {
        switch self {
        case .comprehensive:         return .blue
        case .layer3Discovery:       return .purple
        case .narrativeLens:         return .green
        case .registerAnalysis:      return .orange
        case .sentenceConstruction:  return .pink
        case .mechanicalFingerprint: return .red
        }
    }
}

// MARK: - Position Bucket

enum FingerprintPosition: String, Codable, CaseIterable {
    case first = "first"
    case second = "second"
    case closing = "closing"
    case middle = "middle"

    var displayName: String {
        switch self {
        case .first: return "Position #1"
        case .second: return "Position #2"
        case .closing: return "Closing"
        case .middle: return "Middle"
        }
    }

    var shortLabel: String {
        switch self {
        case .first: return "#1"
        case .second: return "#2"
        case .closing: return "End"
        case .middle: return "Mid"
        }
    }
}

// MARK: - Slot Key (Move Label + Position)

struct FingerprintSlotKey: Hashable, Codable {
    let moveLabel: RhetoricalMoveType
    let position: FingerprintPosition

    /// Deterministic document ID for Firebase upserts (includes prompt type)
    func documentId(creatorId: String, promptType: FingerprintPromptType) -> String {
        "\(creatorId)_\(moveLabel.rawValue)_\(position.rawValue)_\(promptType.rawValue)"
    }

    /// Determine position bucket from a move's index in the sequence
    static func positionBucket(chunkIndex: Int, sequenceLength: Int) -> FingerprintPosition {
        if chunkIndex == 0 { return .first }
        if chunkIndex == 1 { return .second }
        if chunkIndex >= sequenceLength - 2 { return .closing }
        return .middle
    }

    /// Build a slot key from a move's position in a sequence
    static func from(chunkIndex: Int, moveType: RhetoricalMoveType, sequenceLength: Int) -> FingerprintSlotKey {
        FingerprintSlotKey(
            moveLabel: moveType,
            position: positionBucket(chunkIndex: chunkIndex, sequenceLength: sequenceLength)
        )
    }
}

// MARK: - Fingerprint Document (Firestore)

struct FingerprintDocument: Codable, Identifiable {
    let creatorId: String
    let moveLabel: String               // RhetoricalMoveType.rawValue
    let position: String                // FingerprintPosition.rawValue
    let promptType: String              // FingerprintPromptType.rawValue
    let fingerprintText: String         // LLM-generated fingerprint
    let sourceVideoCount: Int
    let sourceSequenceIds: [String]     // Video IDs whose rhetorical sequences fed this fingerprint
    let generatedAt: Date
    let promptSent: String
    let tokensUsed: Int

    var id: String { "\(creatorId)_\(moveLabel)_\(position)_\(promptType)" }

    var moveLabelType: RhetoricalMoveType? {
        RhetoricalMoveType(rawValue: moveLabel)
    }

    var positionType: FingerprintPosition? {
        FingerprintPosition(rawValue: position)
    }

    var promptTypeEnum: FingerprintPromptType? {
        FingerprintPromptType(rawValue: promptType)
    }

    var slotKey: FingerprintSlotKey? {
        guard let ml = moveLabelType, let pos = positionType else { return nil }
        return FingerprintSlotKey(moveLabel: ml, position: pos)
    }

    // Backward compat: old docs without promptType decode as "legacy"
    enum CodingKeys: String, CodingKey {
        case creatorId, moveLabel, position, promptType
        case fingerprintText, sourceVideoCount, sourceSequenceIds
        case generatedAt, promptSent, tokensUsed
    }

    init(creatorId: String, moveLabel: String, position: String, promptType: String,
         fingerprintText: String, sourceVideoCount: Int, sourceSequenceIds: [String],
         generatedAt: Date, promptSent: String, tokensUsed: Int) {
        self.creatorId = creatorId
        self.moveLabel = moveLabel
        self.position = position
        self.promptType = promptType
        self.fingerprintText = fingerprintText
        self.sourceVideoCount = sourceVideoCount
        self.sourceSequenceIds = sourceSequenceIds
        self.generatedAt = generatedAt
        self.promptSent = promptSent
        self.tokensUsed = tokensUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatorId = try container.decode(String.self, forKey: .creatorId)
        moveLabel = try container.decode(String.self, forKey: .moveLabel)
        position = try container.decode(String.self, forKey: .position)
        promptType = try container.decodeIfPresent(String.self, forKey: .promptType) ?? "legacy"
        fingerprintText = try container.decode(String.self, forKey: .fingerprintText)
        sourceVideoCount = try container.decode(Int.self, forKey: .sourceVideoCount)
        sourceSequenceIds = try container.decode([String].self, forKey: .sourceSequenceIds)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        promptSent = try container.decode(String.self, forKey: .promptSent)
        tokensUsed = try container.decode(Int.self, forKey: .tokensUsed)
    }
}

// MARK: - Slot Availability (Pre-Generation Analysis)

struct FingerprintSlotAvailability: Identifiable {
    let slotKey: FingerprintSlotKey
    var exampleCount: Int
    var sourceVideoIds: [String]
    var sampleTexts: [String]               // Raw transcript text from sentence ranges
    var sourceVideoTitles: [String]         // Video title per sample (parallel array with sampleTexts)
    var existingFingerprints: [FingerprintPromptType: FingerprintDocument]

    var id: String { "\(slotKey.moveLabel.rawValue)_\(slotKey.position.rawValue)" }

    func hasSufficientData(minimum: Int) -> Bool {
        exampleCount >= minimum
    }

    /// How many prompt types have been generated for this slot
    var generatedCount: Int {
        existingFingerprints.count
    }

    /// Whether all prompt types are generated
    var isFullyGenerated: Bool {
        generatedCount == FingerprintPromptType.allCases.count
    }

    /// Which prompt types are missing
    var missingPromptTypes: [FingerprintPromptType] {
        FingerprintPromptType.allCases.filter { existingFingerprints[$0] == nil }
    }

    /// Whether any existing fingerprint is stale (new videos not included)
    var isStale: Bool {
        let currentSet = Set(sourceVideoIds)
        return existingFingerprints.values.contains { fp in
            let existingSet = Set(fp.sourceSequenceIds)
            return !currentSet.isSubset(of: existingSet)
        }
    }

    /// Which prompt types have stale fingerprints
    var stalePromptTypes: [FingerprintPromptType] {
        let currentSet = Set(sourceVideoIds)
        return existingFingerprints.compactMap { type, fp in
            let existingSet = Set(fp.sourceSequenceIds)
            return currentSet.isSubset(of: existingSet) ? nil : type
        }
    }
}

// MARK: - Generation Result

struct FingerprintGenerationResult: Identifiable {
    let id = UUID()
    let slotKey: FingerprintSlotKey
    let promptType: FingerprintPromptType
    let status: GenerationStatus
    let fingerprintText: String?
    let promptSent: String?
    let systemPromptSent: String?
    let rawResponse: String?
    let tokensUsed: Int?
    let error: String?

    enum GenerationStatus: Equatable {
        case pending
        case inProgress
        case success
        case failed(String)
        case skipped(String)

        var displayText: String {
            switch self {
            case .pending: return "Pending"
            case .inProgress: return "Running..."
            case .success: return "Done"
            case .failed(let msg): return "Failed: \(msg)"
            case .skipped(let msg): return "Skipped: \(msg)"
            }
        }

        var isTerminal: Bool {
            switch self {
            case .success, .failed, .skipped: return true
            default: return false
            }
        }
    }
}

// MARK: - Summary Stats

struct SlotSummary {
    let totalSlots: Int
    let slotsWithData: Int
    let slotsWithSufficientData: Int
    let slotsGenerated: Int             // slots with at least 1 fingerprint
    let slotsFullyGenerated: Int        // slots with ALL prompt types
    let slotsStale: Int
    let totalFingerprints: Int          // total individual fingerprint docs
}
