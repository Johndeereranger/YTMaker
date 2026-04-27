//
//  DonorLibraryModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation

// MARK: - 16 Slot Types (Sentence Content Classification)

enum SlotType: String, Codable, CaseIterable {
    case geographicLocation = "geographic_location"
    case visualDetail = "visual_detail"
    case quantitativeClaim = "quantitative_claim"
    case temporalMarker = "temporal_marker"
    case actorReference = "actor_reference"
    case contradiction = "contradiction"
    case sensoryDetail = "sensory_detail"
    case rhetoricalQuestion = "rhetorical_question"
    case evaluativeClaim = "evaluative_claim"
    case pivotPhrase = "pivot_phrase"
    case directAddress = "direct_address"
    case narrativeAction = "narrative_action"
    case abstractFraming = "abstract_framing"
    case comparison = "comparison"
    case emptyConnector = "empty_connector"
    case factualRelay = "factual_relay"
    case reactionBeat = "reaction_beat"
    case visualAnchor = "visual_anchor"
    case other = "other"

    var displayName: String {
        switch self {
        case .geographicLocation: return "Geographic Location"
        case .visualDetail: return "Visual Detail"
        case .quantitativeClaim: return "Quantitative Claim"
        case .temporalMarker: return "Temporal Marker"
        case .actorReference: return "Actor Reference"
        case .contradiction: return "Contradiction"
        case .sensoryDetail: return "Sensory Detail"
        case .rhetoricalQuestion: return "Rhetorical Question"
        case .evaluativeClaim: return "Evaluative Claim"
        case .pivotPhrase: return "Pivot Phrase"
        case .directAddress: return "Direct Address"
        case .narrativeAction: return "Narrative Action"
        case .abstractFraming: return "Abstract Framing"
        case .comparison: return "Comparison"
        case .emptyConnector: return "Empty Connector"
        case .factualRelay: return "Factual Relay"
        case .reactionBeat: return "Reaction Beat"
        case .visualAnchor: return "Visual Anchor"
        case .other: return "Other"
        }
    }
}

// MARK: - 8 Payload Types (Content Payload Classification)

enum PayloadType: String, Codable, CaseIterable {
    case quantitativeFinding = "quantitative_finding"
    case geographicSpecificity = "geographic_specificity"
    case contradictionPayload = "contradiction"
    case actionDescription = "action_description"
    case statusClaim = "status_claim"
    case temporalContext = "temporal_context"
    case causalClaim = "causal_claim"
    case identityStatement = "identity_statement"

    var displayName: String {
        switch self {
        case .quantitativeFinding: return "Quantitative Finding"
        case .geographicSpecificity: return "Geographic Specificity"
        case .contradictionPayload: return "Contradiction"
        case .actionDescription: return "Action Description"
        case .statusClaim: return "Status Claim"
        case .temporalContext: return "Temporal Context"
        case .causalClaim: return "Causal Claim"
        case .identityStatement: return "Identity Statement"
        }
    }
}

// MARK: - SentencePhrase (phrase-level annotation from A2 v2)

struct SentencePhrase: Codable, Hashable {
    let text: String
    let role: String
}

// MARK: - SentenceFunction (rhetorical function classification)

enum SentenceFunction: String, Codable, CaseIterable {
    case sceneSet = "scene_set"
    case establishAssumption = "establish_assumption"
    case introduceContradiction = "introduce_contradiction"
    case deliverEvidence = "deliver_evidence"
    case poseQuestion = "pose_question"
    case directAddress = "direct_address"
    case transitionBridge = "transition_bridge"
    case evaluativeJudgment = "evaluative_judgment"
    case narrativeAction = "narrative_action"
    case contextAnchor = "context_anchor"
    case revealPayoff = "reveal_payoff"
    case other = "other"

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - CreatorSentence (Firebase: creator_sentences collection)

struct CreatorSentence: Codable, Identifiable, Hashable {
    let id: String                          // {videoId}_{sectionIdx}_{sentenceIdx}
    let videoId: String
    let channelId: String
    let sectionIndex: Int
    let sentenceIndex: Int
    let moveType: String                    // RhetoricalMoveType raw value
    let sectionCategory: String             // RhetoricalCategory raw value
    let rawText: String

    // Slot annotation (A2) — derived from phrases in v2
    let slotSequence: [String]              // Ordered slot type raw values
    let slotSignature: String               // Canonical: "geographic_location|visual_detail"
    let clauseCount: Int
    let wordCount: Int
    let isQuestion: Bool
    let isFragment: Bool
    let hasDirectAddress: Bool
    let openingPattern: String              // First 2-3 words

    // Phrase-level annotation (A2 v2)
    var phrases: [SentencePhrase]?          // [{text, role}] — raw LLM output
    var sentenceFunction: String?           // Rhetorical function label
    var deterministicHints: [String]?       // e.g. ["hasTemporalMarker", "hasFirstPerson"]
    var hintMismatches: [String]?           // Hints the LLM contradicted

    // Embedding (A3) — optional, populated after A3
    var embedding: [Float]?

    // Neighbor signatures for bigram context
    var prevSlotSignature: String?
    var nextSlotSignature: String?

    let createdAt: Date

    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CreatorSentence, rhs: CreatorSentence) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - SlotBigram (Firebase: slot_bigrams collection)

struct SlotBigram: Codable, Identifiable, Hashable {
    let id: String                          // Auto-generated
    let videoId: String
    let channelId: String
    let fromSignature: String               // Slot signature of sentence N
    let toSignature: String                 // Slot signature of sentence N+1
    let fromMove: String                    // Move type raw value
    let toMove: String                      // Move type raw value
    let count: Int
    let probability: Double                 // count / total transitions from this sig
    let crossSection: Bool                  // True if fromMove != toMove
    let createdAt: Date
}

// MARK: - SectionProfile (Firebase: section_profiles collection)

struct SectionProfile: Codable, Identifiable, Hashable {
    let id: String
    let videoId: String
    let channelId: String
    let moveType: String                    // RhetoricalMoveType raw value
    let minSentences: Int
    let maxSentences: Int
    let medianSentences: Double
    let commonOpeningSignatures: [String]   // Top opening slot signatures
    let commonClosingSignatures: [String]   // Top closing slot signatures
    let totalSections: Int                  // How many sections of this move type
    let createdAt: Date
}

// MARK: - RhythmTemplate (Firebase: rhythm_templates collection)

struct RhythmTemplate: Codable, Identifiable, Hashable {
    let id: String
    let videoId: String
    let channelId: String
    let moveType: String                    // RhetoricalMoveType raw value
    let positionInSection: String           // "opening" | "mid" | "closing"
    let wordCountMin: Int
    let wordCountMax: Int
    let clauseCountMin: Int
    let clauseCountMax: Int
    let sentenceType: String                // "statement" | "question" | "fragment"
    let commonOpeners: [String]             // Frequent opening patterns
    let typicalSlotSignature: String        // Most common signature at this position
    let createdAt: Date
}

// MARK: - DonorLibraryStatus (stored on YouTubeVideo doc)

struct DonorLibraryStatus: Codable, Hashable {
    var a2Complete: Bool = false
    var a3Complete: Bool = false
    var a4Complete: Bool = false
    var a5Complete: Bool = false
    var sentenceCount: Int = 0
    var lastUpdated: Date?
}
