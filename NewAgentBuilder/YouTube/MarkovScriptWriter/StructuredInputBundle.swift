//
//  StructuredInputBundle.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/16/26.
//
//  Data model packaging all structured inputs from the Donor Library
//  for consumption by S1-S4 structured comparison methods.
//  Each S-method variant uses ONE fingerprint type as its voice constraint;
//  the bundle carries all 6 so the runner can loop over them.
//

import Foundation

// MARK: - Structured Input Bundle

struct StructuredInputBundle {

    /// Creator (channel) these inputs belong to
    let creatorId: String

    /// All available fingerprints for the target slot, keyed by prompt type.
    /// Up to 6 entries — one per FingerprintPromptType.
    let fingerprints: [FingerprintPromptType: FingerprintDocument]

    /// Donor sentences grouped by target position index.
    /// Each entry contains the target signature + matching sentences (expanded via confusable pairs).
    let donorsByPosition: [DonorSentenceMatch]

    /// Section profile for the target move type (sentence count stats, common openings/closings).
    let sectionProfile: SectionProfile?

    /// Rhythm templates for the target move type (per-position word/clause constraints).
    let rhythmTemplates: [RhythmTemplate]

    /// Confusable pair lookup for signature expansion.
    let confusableLookup: ConfusableLookup

    /// Target move type raw value (e.g. "scene_set")
    let targetMoveType: String

    /// Target position bucket
    let targetPosition: FingerprintPosition

    /// Ordered slot signatures for the target section (one per sentence).
    let targetSignatureSequence: [String]

    /// How many sentences the target section should have (derived from section profile median).
    let targetSentenceCount: Int

    // MARK: - Computed

    /// Which fingerprint types are available (have been generated).
    var availableFingerprintTypes: [FingerprintPromptType] {
        FingerprintPromptType.allCases.filter { fingerprints[$0] != nil }
    }

    /// Total donor sentences across all positions.
    var totalDonorCount: Int {
        donorsByPosition.reduce(0) { $0 + $1.matchingSentences.count }
    }

    /// Summary string for UI display.
    var summaryText: String {
        "\(fingerprints.count) fingerprints, \(totalDonorCount) donors, \(targetSentenceCount) target sentences"
    }
}

// MARK: - Donor Sentence Match (per target position)

struct DonorSentenceMatch: Identifiable {
    let id: Int

    /// 0-based position in the target signature sequence.
    let positionIndex: Int

    /// The primary target signature at this position.
    let targetSignature: String

    /// All expanded signatures (original + confusable variants).
    let expandedSignatures: [String]

    /// Creator sentences matching any of the expanded signatures.
    let matchingSentences: [CreatorSentence]

    init(positionIndex: Int, targetSignature: String, expandedSignatures: [String], matchingSentences: [CreatorSentence]) {
        self.id = positionIndex
        self.positionIndex = positionIndex
        self.targetSignature = targetSignature
        self.expandedSignatures = expandedSignatures
        self.matchingSentences = matchingSentences
    }
}

// MARK: - Approved Structural Spec (from Structure Workbench)

/// User-approved structural specification produced by the Structure Workbench tab.
/// When present, StructuredInputAssembler uses this instead of auto-derivation.
struct ApprovedStructuralSpec: Codable {
    let moveType: String
    let signatureSequence: [String]
    let rhythmOverrides: [RhythmOverride]
    let approachUsed: String        // "realSection" | "bigramWalk" | "statistical"
    let sourceDescription: String   // e.g. "Video abc123, Section 2" or "Bigram walk seed 42"
    let approvedAt: Date

    var sentenceCount: Int { signatureSequence.count }

    struct RhythmOverride: Codable {
        let positionIndex: Int
        var wordCountMin: Int
        var wordCountMax: Int
        var clauseCountMin: Int
        var clauseCountMax: Int
        var commonOpeners: [String]
    }
}
