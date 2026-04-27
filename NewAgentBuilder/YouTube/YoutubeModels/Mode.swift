//
//  Mode.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/21/26.
//


import Foundation

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Mode Model
// Collection: modes/{modeId}
// ═══════════════════════════════════════════════════════════════════════════

struct Mode: Codable, Hashable, Equatable, Identifiable {
    var id: String { modeId }
    
    // Identity
    let modeId: String
    let channelId: String
    var modeName: String
    var modeDescription: String
    
    // Clustering
    var vectorModel: ModeVectorModel
    
    // Distributions (for natural variation)
    var distributions: ModeDistributions
    
    // Beat Choreography
    var beatChoreography: BeatChoreography
    
    // Signatures
    var signatures: ModeSignatures
    
    // Discriminators
    var discriminators: ModeDiscriminators
    
    // Constraints
    var constraints: ModeConstraints
    
    // Usage Guidance
    var usage: ModeUsage
    
    // Metadata
    var scriptCount: Int
    var exemplarCount: Int
    var lastUpdated: Date
    var createdAt: Date
}

// MARK: - Vector Model
struct ModeVectorModel: Codable, Hashable, Equatable {
    var centroid: ModeCentroid
    var acceptance: ModeAcceptance
    var featureWeights: FeatureWeights
}

struct ModeCentroid: Codable, Hashable, Equatable {
    // Structural
    var sectionCount: Double
    var turnPosition: Double
    
    // Beat percentages
    var beatPctTease: Double
    var beatPctQuestion: Double
    var beatPctPromise: Double
    var beatPctData: Double
    var beatPctStory: Double
    var beatPctContext: Double
    var beatPctPayoff: Double
    
    // Constraint averages
    var avgSentenceLength: Double
    var avgBeatLength: Double
    var avgTeaseDistance: Double
    var avgQuestionsPerSection: Double
    
    // Voice averages
    var avgFormality: Double
    var avgContractionRate: Double
    var criticalStancePct: Double
    var slowBuildTempoPct: Double
}

struct ModeAcceptance: Codable, Hashable, Equatable {
    var distanceMetric: String
    var maxDistance: Double
    var outlierMode: String
}

struct FeatureWeights: Codable, Hashable, Equatable {
    var beatTypePct: Double
    var stancePct: Double
    var tempoPct: Double
    var turnPositionNorm: Double
    var sentenceLengthDist: Double
    var teaseDistanceDist: Double
}

// MARK: - Distributions
struct ModeDistributions: Codable, Hashable, Equatable {
    var sentenceLengthWords: Histogram
    var beatLengthSentences: Histogram
    var formality: Histogram
    var teaseDistanceBeats: Histogram
    var stance: [String: Double]
    var tempo: [String: Double]
}

struct Histogram: Codable, Hashable, Equatable {
    var bins: [Double]
    var binEdges: [Double]
}

// MARK: - Beat Choreography
struct BeatChoreography: Codable, Hashable, Equatable {
    var overall: [String: Double]
    var bySection: [String: [String: Double]]
    var commonSequences: CommonSequences
}

struct CommonSequences: Codable, Hashable, Equatable {
    var bigrams: [BeatSequence]
    var trigrams: [BeatSequence]
}

struct BeatSequence: Codable, Hashable, Equatable {
    var seq: [String]
    var frequency: Double
    var location: String?
}

// MARK: - Signatures
struct ModeSignatures: Codable, Hashable, Equatable {
    var required: [String]
    var typical: [String]
    var avoid: [String]
    var sectionSequence: [String]
    var sectionSequenceVariants: [SectionSequenceVariant]
}

struct SectionSequenceVariant: Codable, Hashable, Equatable {
    var sequence: [String]
    var frequency: Double
}

// MARK: - Discriminators
struct ModeDiscriminators: Codable, Hashable, Equatable {
    var requiredRules: [DiscriminatorRule]
    var vsOtherModes: [PairwiseDiscriminator]
    var unassignedPolicy: UnassignedPolicy
}

struct DiscriminatorRule: Codable, Hashable, Equatable, Identifiable {
    var id: String { ruleId }
    
    let ruleId: String
    var description: String
    var features: [String]
    var ruleOperator: String
    var threshold: Double?
    var weight: Double
}

struct PairwiseDiscriminator: Codable, Hashable, Equatable {
    var modeId: String
    var modeName: String
    var distinctions: [String]
    var numericSeparators: [NumericSeparator]
    var comparisons: [ModeComparison]
}

struct NumericSeparator: Codable, Hashable, Equatable {
    var feature: String
    var thisModeRange: RangeMinMax
    var otherModeRange: RangeMinMax
    var confidence: Double?
}

struct RangeMinMax: Codable, Hashable, Equatable {
    var min: Double
    var max: Double
}

struct ModeComparison: Codable, Hashable, Equatable {
    var thisScript: String
    var thatScript: String
    var keyDifference: String
}

struct UnassignedPolicy: Codable, Hashable, Equatable {
    var maxDistanceFromAnyMode: Double
    var minRulesSatisfied: Int
    var action: String
}

// MARK: - Constraints
struct ModeConstraints: Codable, Hashable, Equatable {
    var sentenceLength: ConstraintWithRange
    var beatLength: ConstraintWithRange
    var teaseDistance: ConstraintSimple
    var turnPosition: ConstraintSimple
    var questionsPerSection: ConstraintSimple
    var beatPercentages: [String: RangeMinMax]?
}

struct ConstraintWithRange: Codable, Hashable, Equatable {
    var min: Double
    var max: Double
    var target: Double
    var range: [Double]
}

struct ConstraintSimple: Codable, Hashable, Equatable {
    var min: Double
    var max: Double
    var typical: Double
}

// MARK: - Usage
struct ModeUsage: Codable, Hashable, Equatable {
    var topics: [String]
    var intents: [String]
    var notFor: [String]
    var exampleTopics: [String]
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Mode Exemplar Model
// Collection: modeExemplars/{exemplarId}
// ═══════════════════════════════════════════════════════════════════════════

struct ModeExemplar: Codable, Hashable, Equatable, Identifiable {
    var id: String { exemplarId }
    
    // Identity
    let exemplarId: String
    let modeId: String
    let channelId: String
    let videoId: String
    
    // Content
    var title: String
    var rationale: String  // 3 sentences: WHY this script is in this mode
    var summary: String    // 2 sentences: WHAT this script does
    
    // Clustering
    var distanceFromCentroid: Double
    var rank: Int
    var distinguishingFeatures: [String]
    
    // Snippets (for AI learning)
    var snippets: ExemplarSnippets
    
    // Fingerprint (embedded snapshot)
    var fingerprint: ScriptFingerprint
    
    // Metadata
    var duration: Int
    var addedToMode: Date
}

struct ExemplarSnippets: Codable, Hashable, Equatable {
    var hookSnippet: String
    var turnSnippet: String
    var payoffSnippet: String
}

struct ScriptFingerprint: Codable, Hashable, Equatable {
    var sectionSequence: [String]
    var turnPosition: Double
    var totalBeats: Int
    var beatDistribution: [String: Int]
    var sentenceStats: StatsSummary
    var teaseDistanceStats: StatsSummary?
    var stanceDistribution: [String: Double]
    var tempoDistribution: [String: Double]
    var avgFormality: Double
    var contractionRate: Double
}

struct StatsSummary: Codable, Hashable, Equatable {
    var mean: Double
    var stdDev: Double?
    var min: Double?
    var max: Double?
}