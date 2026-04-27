//
//  CreatorNarrativeProfileModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import Foundation

// MARK: - Creator Narrative Profile (Firebase Document)

struct CreatorNarrativeProfile: Codable, Identifiable {
    var id: String { channelId }

    let channelId: String
    let channelName: String
    let spineCount: Int
    let includedVideoIds: [String]
    let generatedAt: Date

    // Layer 1: Structural Signature Aggregation
    let signatureAggregation: SignatureAggregationLayer

    // Layer 2: Phase Pattern Analysis
    let phasePatterns: PhasePatternLayer

    // Layer 3: Throughline Pattern Analysis
    let throughlinePatterns: ThroughlinePatternLayer

    // Layer 4: Beat Function Distribution
    let beatDistribution: BeatDistributionLayer

    // Representative Spines
    let representativeSpines: [RepresentativeSpine]

    // Full rendered text for clipboard copy
    var renderedText: String
}

// MARK: - Layer 1: Structural Signature Aggregation

struct SignatureAggregationLayer: Codable {
    let totalSignaturesInput: Int
    let clusteredSignatures: [ClusteredSignature]
}

struct ClusteredSignature: Codable, Identifiable {
    var id: String { canonicalName }

    let canonicalName: String
    let description: String
    let frequency: Int
    let frequencyPercent: Double
    let variants: [String]
}

// MARK: - Layer 2: Phase Pattern Analysis

struct PhasePatternLayer: Codable {
    let typicalPhaseCount: PhaseCountRange
    let typicalArchitecture: [TypicalPhase]
    let architectureNarrative: String
}

struct PhaseCountRange: Codable {
    let min: Int
    let max: Int
    let mode: Int
    let median: Double
}

struct TypicalPhase: Codable, Identifiable {
    var id: Int { phasePosition }

    let phasePosition: Int
    let commonNames: [String]
    let definingTechniques: [String]
    let typicalBeatSpan: String
    let frequency: Int
}

// MARK: - Layer 3: Throughline Pattern Analysis

struct ThroughlinePatternLayer: Codable {
    let recurringMovementPattern: String
    let commonOpeningMoves: [String]
    let commonClosingMoves: [String]
    let throughlineNarrative: String
}

// MARK: - Layer 4: Beat Function Distribution

struct BeatDistributionLayer: Codable {
    let totalBeatsAnalyzed: Int
    let globalDistribution: [FunctionFrequency]
    let positionalDistribution: [PositionalBeat]
}

struct FunctionFrequency: Codable, Identifiable {
    var id: String { functionLabel }

    let functionLabel: String
    let count: Int
    let percent: Double
}

struct PositionalBeat: Codable, Identifiable {
    var id: Int { beatPosition }

    let beatPosition: Int
    let topFunctions: [FunctionAtPosition]
    let spinesCoveringThisPosition: Int
}

struct FunctionAtPosition: Codable {
    let functionLabel: String
    let count: Int
    let percent: Double
}

// MARK: - Representative Spines

struct RepresentativeSpine: Codable, Identifiable {
    var id: String { videoId }

    let videoId: String
    let videoTitle: String
    let matchScore: Double
    let matchReason: String
}

// MARK: - Build Status

enum ProfileBuildPhase: String, CaseIterable {
    case idle
    case loadingSpines
    case buildingLayers
    case selectingRepresentatives
    case saving
    case complete
    case failed

    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .loadingSpines: return "Loading spines..."
        case .buildingLayers: return "Building layers 1-4..."
        case .selectingRepresentatives: return "Selecting representative spines..."
        case .saving: return "Saving profile..."
        case .complete: return "Profile complete"
        case .failed: return "Failed"
        }
    }
}
