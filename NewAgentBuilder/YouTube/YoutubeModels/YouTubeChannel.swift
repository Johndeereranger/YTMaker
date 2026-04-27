//
//  YouTubeChannel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//

import Foundation
import FirebaseFirestore
import SwiftUI
import Foundation

// MARK: - Channel Model
struct YouTubeChannel: Codable, Identifiable, Hashable, Equatable {
    let channelId: String
    let name: String
    let handle: String
    let thumbnailUrl: String
    let videoCount: Int
    let lastSynced: Date
    var isStudyCreator: Bool = false
    var hasSentenceAnalysis: Bool = false

    var metadata: ChannelMetadata?
    var isPinned: Bool
    var notHunting: Bool
    
    // ═══════════════════════════════════════════════════════════
    // A3: Creator Aggregation Fields (flattened, all optional)
    // ═══════════════════════════════════════════════════════════
    
    var styleIds: [String]?
    var scriptsAnalyzed: Int?
    var lastFullClusterAt: Date?
    var pendingRecluster: Bool?
    
    // Constraints - flattened
    var constraintSentenceLengthMin: Double?
    var constraintSentenceLengthMax: Double?
    var constraintSentenceLengthTarget: Double?
    var constraintTeaseDistanceMin: Double?
    var constraintTeaseDistanceMax: Double?
    var constraintTeaseDistanceTarget: Double?
    var constraintQuestionsPerSectionMin: Double?
    var constraintQuestionsPerSectionMax: Double?
    var constraintQuestionsPerSectionTarget: Double?
    
    // Anchor families - parallel arrays
    var anchorOpenerPhrases: [String]?
    var anchorOpenerFrequencies: [Double]?
    var anchorTurnPhrases: [String]?
    var anchorTurnFrequencies: [Double]?
    var anchorProofPhrases: [String]?
    var anchorProofFrequencies: [Double]?
    
    // Cooldown
    var cooldownMinDistance: Int?
    var cooldownMaxFrequency: Double?
    
    // ═══════════════════════════════════════════════════════════
    // Identifiable / Computed
    // ═══════════════════════════════════════════════════════════
    
    var id: String { channelId }
    
    var hasCreatorAggregation: Bool {
        styleIds != nil && !(styleIds?.isEmpty ?? true)
    }
    
    // ═══════════════════════════════════════════════════════════
    // Init
    // ═══════════════════════════════════════════════════════════
    
    init(
        channelId: String,
        name: String,
        handle: String,
        thumbnailUrl: String,
        videoCount: Int,
        lastSynced: Date,
        isStudyCreator: Bool = false,
        hasSentenceAnalysis: Bool = false,
        metadata: ChannelMetadata? = nil,
        isPinned: Bool = false,
        notHunting: Bool = false,
        // A3 fields
        styleIds: [String]? = nil,
        scriptsAnalyzed: Int? = nil,
        lastFullClusterAt: Date? = nil,
        pendingRecluster: Bool? = nil,
        constraintSentenceLengthMin: Double? = nil,
        constraintSentenceLengthMax: Double? = nil,
        constraintSentenceLengthTarget: Double? = nil,
        constraintTeaseDistanceMin: Double? = nil,
        constraintTeaseDistanceMax: Double? = nil,
        constraintTeaseDistanceTarget: Double? = nil,
        constraintQuestionsPerSectionMin: Double? = nil,
        constraintQuestionsPerSectionMax: Double? = nil,
        constraintQuestionsPerSectionTarget: Double? = nil,
        anchorOpenerPhrases: [String]? = nil,
        anchorOpenerFrequencies: [Double]? = nil,
        anchorTurnPhrases: [String]? = nil,
        anchorTurnFrequencies: [Double]? = nil,
        anchorProofPhrases: [String]? = nil,
        anchorProofFrequencies: [Double]? = nil,
        cooldownMinDistance: Int? = nil,
        cooldownMaxFrequency: Double? = nil
    ) {
        self.channelId = channelId
        self.name = name
        self.handle = handle
        self.thumbnailUrl = thumbnailUrl
        self.videoCount = videoCount
        self.lastSynced = lastSynced
        self.isStudyCreator = isStudyCreator
        self.hasSentenceAnalysis = hasSentenceAnalysis
        self.metadata = metadata
        self.isPinned = isPinned
        self.notHunting = notHunting
        // A3
        self.styleIds = styleIds
        self.scriptsAnalyzed = scriptsAnalyzed
        self.lastFullClusterAt = lastFullClusterAt
        self.pendingRecluster = pendingRecluster
        self.constraintSentenceLengthMin = constraintSentenceLengthMin
        self.constraintSentenceLengthMax = constraintSentenceLengthMax
        self.constraintSentenceLengthTarget = constraintSentenceLengthTarget
        self.constraintTeaseDistanceMin = constraintTeaseDistanceMin
        self.constraintTeaseDistanceMax = constraintTeaseDistanceMax
        self.constraintTeaseDistanceTarget = constraintTeaseDistanceTarget
        self.constraintQuestionsPerSectionMin = constraintQuestionsPerSectionMin
        self.constraintQuestionsPerSectionMax = constraintQuestionsPerSectionMax
        self.constraintQuestionsPerSectionTarget = constraintQuestionsPerSectionTarget
        self.anchorOpenerPhrases = anchorOpenerPhrases
        self.anchorOpenerFrequencies = anchorOpenerFrequencies
        self.anchorTurnPhrases = anchorTurnPhrases
        self.anchorTurnFrequencies = anchorTurnFrequencies
        self.anchorProofPhrases = anchorProofPhrases
        self.anchorProofFrequencies = anchorProofFrequencies
        self.cooldownMinDistance = cooldownMinDistance
        self.cooldownMaxFrequency = cooldownMaxFrequency
    }
    
    // ═══════════════════════════════════════════════════════════
    // Decoder
    // ═══════════════════════════════════════════════════════════
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Core fields
        channelId = try container.decode(String.self, forKey: .channelId)
        name = try container.decode(String.self, forKey: .name)
        handle = try container.decode(String.self, forKey: .handle)
        thumbnailUrl = try container.decode(String.self, forKey: .thumbnailUrl)
        videoCount = try container.decode(Int.self, forKey: .videoCount)
        lastSynced = try container.decode(Date.self, forKey: .lastSynced)
        isStudyCreator = try container.decodeIfPresent(Bool.self, forKey: .isStudyCreator) ?? false
        hasSentenceAnalysis = try container.decodeIfPresent(Bool.self, forKey: .hasSentenceAnalysis) ?? false
        metadata = try container.decodeIfPresent(ChannelMetadata.self, forKey: .metadata)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        notHunting = try container.decodeIfPresent(Bool.self, forKey: .notHunting) ?? false
        
        // A3 fields
        styleIds = try container.decodeIfPresent([String].self, forKey: .styleIds)
        scriptsAnalyzed = try container.decodeIfPresent(Int.self, forKey: .scriptsAnalyzed)
        lastFullClusterAt = try container.decodeIfPresent(Date.self, forKey: .lastFullClusterAt)
        pendingRecluster = try container.decodeIfPresent(Bool.self, forKey: .pendingRecluster)
        
        // Constraints
        constraintSentenceLengthMin = try container.decodeIfPresent(Double.self, forKey: .constraintSentenceLengthMin)
        constraintSentenceLengthMax = try container.decodeIfPresent(Double.self, forKey: .constraintSentenceLengthMax)
        constraintSentenceLengthTarget = try container.decodeIfPresent(Double.self, forKey: .constraintSentenceLengthTarget)
        constraintTeaseDistanceMin = try container.decodeIfPresent(Double.self, forKey: .constraintTeaseDistanceMin)
        constraintTeaseDistanceMax = try container.decodeIfPresent(Double.self, forKey: .constraintTeaseDistanceMax)
        constraintTeaseDistanceTarget = try container.decodeIfPresent(Double.self, forKey: .constraintTeaseDistanceTarget)
        constraintQuestionsPerSectionMin = try container.decodeIfPresent(Double.self, forKey: .constraintQuestionsPerSectionMin)
        constraintQuestionsPerSectionMax = try container.decodeIfPresent(Double.self, forKey: .constraintQuestionsPerSectionMax)
        constraintQuestionsPerSectionTarget = try container.decodeIfPresent(Double.self, forKey: .constraintQuestionsPerSectionTarget)
        
        // Anchor families
        anchorOpenerPhrases = try container.decodeIfPresent([String].self, forKey: .anchorOpenerPhrases)
        anchorOpenerFrequencies = try container.decodeIfPresent([Double].self, forKey: .anchorOpenerFrequencies)
        anchorTurnPhrases = try container.decodeIfPresent([String].self, forKey: .anchorTurnPhrases)
        anchorTurnFrequencies = try container.decodeIfPresent([Double].self, forKey: .anchorTurnFrequencies)
        anchorProofPhrases = try container.decodeIfPresent([String].self, forKey: .anchorProofPhrases)
        anchorProofFrequencies = try container.decodeIfPresent([Double].self, forKey: .anchorProofFrequencies)
        
        // Cooldown
        cooldownMinDistance = try container.decodeIfPresent(Int.self, forKey: .cooldownMinDistance)
        cooldownMaxFrequency = try container.decodeIfPresent(Double.self, forKey: .cooldownMaxFrequency)
    }
    
    // ═══════════════════════════════════════════════════════════
    // CodingKeys
    // ═══════════════════════════════════════════════════════════
    
    enum CodingKeys: String, CodingKey {
        case channelId, name, handle, thumbnailUrl, videoCount, lastSynced
        case isStudyCreator, hasSentenceAnalysis, metadata, isPinned, notHunting
        // A3
        case styleIds, scriptsAnalyzed, lastFullClusterAt, pendingRecluster
        // Constraints
        case constraintSentenceLengthMin, constraintSentenceLengthMax, constraintSentenceLengthTarget
        case constraintTeaseDistanceMin, constraintTeaseDistanceMax, constraintTeaseDistanceTarget
        case constraintQuestionsPerSectionMin, constraintQuestionsPerSectionMax, constraintQuestionsPerSectionTarget
        // Anchors
        case anchorOpenerPhrases, anchorOpenerFrequencies
        case anchorTurnPhrases, anchorTurnFrequencies
        case anchorProofPhrases, anchorProofFrequencies
        // Cooldown
        case cooldownMinDistance, cooldownMaxFrequency
    }
    
    // ═══════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════
    
    var formattedSubscriberCount: String? {
        guard let count = metadata?.subscriberCount else { return nil }
        
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000.0
            return String(format: "%.1fM", millions)
        } else if count >= 1_000 {
            let thousands = Double(count) / 1_000.0
            if thousands.truncatingRemainder(dividingBy: 1.0) == 0 {
                return String(format: "%.0fK", thousands)
            } else {
                return String(format: "%.1fK", thousands)
            }
        } else {
            return String(count)
        }
    }
    
    static func == (lhs: YouTubeChannel, rhs: YouTubeChannel) -> Bool {
        lhs.channelId == rhs.channelId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(channelId)
    }
}
//struct YouTubeChannelOld: Codable, Identifiable, Hashable, Equatable {
//    let channelId: String
//    let name: String
//    let handle: String
//    let thumbnailUrl: String
//    let videoCount: Int
//    let lastSynced: Date
//    var isStudyCreator: Bool = false
//    
//    var metadata: ChannelMetadata?
//    var isPinned: Bool
//    var notHunting: Bool
//    
//    // ═══════════════════════════════════════════════════════════
//    // A3: Creator Aggregation Fields (flattened, all optional)
//    // ═══════════════════════════════════════════════════════════
//    var modeIds: [String]?
//    var globalConstraints: GlobalConstraints?
//    var anchorFamilies: AnchorFamilies?
//    var cooldownRules: CooldownRules?
//    var scriptsAnalyzed: Int?
//    var lastFullClusterAt: Date?
//    var pendingRecluster: Bool?
//    
//    // Identifiable conformance
//    var id: String { channelId }
//    
//    // Check if A3 has been run
//    var hasCreatorAggregation: Bool {
//        modeIds != nil && !(modeIds?.isEmpty ?? true)
//    }
//    
//    // Custom init for when creating from YouTube API
//    init(channelId: String, name: String, handle: String, thumbnailUrl: String,
//         videoCount: Int, lastSynced: Date, metadata: ChannelMetadata? = nil,
//         isPinned: Bool = false, notHunting: Bool = false,
//         modeIds: [String]? = nil, globalConstraints: GlobalConstraints? = nil,
//         anchorFamilies: AnchorFamilies? = nil, cooldownRules: CooldownRules? = nil,
//         scriptsAnalyzed: Int? = nil, lastFullClusterAt: Date? = nil,
//         pendingRecluster: Bool? = nil) {
//        self.channelId = channelId
//        self.name = name
//        self.handle = handle
//        self.thumbnailUrl = thumbnailUrl
//        self.videoCount = videoCount
//        self.lastSynced = lastSynced
//        self.metadata = metadata
//        self.isPinned = isPinned
//        self.notHunting = notHunting
//        self.modeIds = modeIds
//        self.globalConstraints = globalConstraints
//        self.anchorFamilies = anchorFamilies
//        self.cooldownRules = cooldownRules
//        self.scriptsAnalyzed = scriptsAnalyzed
//        self.lastFullClusterAt = lastFullClusterAt
//        self.pendingRecluster = pendingRecluster
//    }
//    
//    // Custom decoder to handle missing fields from Firebase
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        channelId = try container.decode(String.self, forKey: .channelId)
//        name = try container.decode(String.self, forKey: .name)
//        handle = try container.decode(String.self, forKey: .handle)
//        thumbnailUrl = try container.decode(String.self, forKey: .thumbnailUrl)
//        videoCount = try container.decode(Int.self, forKey: .videoCount)
//        lastSynced = try container.decode(Date.self, forKey: .lastSynced)
//        metadata = try container.decodeIfPresent(ChannelMetadata.self, forKey: .metadata)
//        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
//        notHunting = try container.decodeIfPresent(Bool.self, forKey: .notHunting) ?? false
//        isStudyCreator = try container.decodeIfPresent(Bool.self, forKey: .isStudyCreator) ?? false
//        
//        // A3 fields
//        modeIds = try container.decodeIfPresent([String].self, forKey: .modeIds)
//        globalConstraints = try container.decodeIfPresent(GlobalConstraints.self, forKey: .globalConstraints)
//        anchorFamilies = try container.decodeIfPresent(AnchorFamilies.self, forKey: .anchorFamilies)
//        cooldownRules = try container.decodeIfPresent(CooldownRules.self, forKey: .cooldownRules)
//        scriptsAnalyzed = try container.decodeIfPresent(Int.self, forKey: .scriptsAnalyzed)
//        lastFullClusterAt = try container.decodeIfPresent(Date.self, forKey: .lastFullClusterAt)
//        pendingRecluster = try container.decodeIfPresent(Bool.self, forKey: .pendingRecluster)
//    }
//    
//    enum CodingKeys: String, CodingKey {
//        case channelId, name, handle, thumbnailUrl, videoCount, lastSynced
//        case metadata, isPinned, notHunting, isStudyCreator
//        case modeIds, globalConstraints, anchorFamilies, cooldownRules
//        case scriptsAnalyzed, lastFullClusterAt, pendingRecluster
//    }
//    
//    var formattedSubscriberCount: String? {
//        guard let count = metadata?.subscriberCount else { return nil }
//        
//        if count >= 1_000_000 {
//            let millions = Double(count) / 1_000_000.0
//            return String(format: "%.1fM", millions)
//        } else if count >= 1_000 {
//            let thousands = Double(count) / 1_000.0
//            if thousands.truncatingRemainder(dividingBy: 1.0) == 0 {
//                return String(format: "%.0fK", thousands)
//            } else {
//                return String(format: "%.1fK", thousands)
//            }
//        } else {
//            return String(count)
//        }
//    }
//    
//    // Equatable conformance
//    static func == (lhs: YouTubeChannelOld, rhs: YouTubeChannelOld) -> Bool {
//        lhs.channelId == rhs.channelId
//    }
//    
//    // Hashable conformance
//    func hash(into hasher: inout Hasher) {
//        hasher.combine(channelId)
//    }
//}

// MARK: - Channel Metadata
struct ChannelMetadata: Codable, Hashable, Equatable {
    let subscriberCount: Int?
    let description: String?
}

// MARK: - Global Constraints
struct GlobalConstraints: Codable, Hashable, Equatable {
    var sentenceLength: ConstraintRange
    var contractionRate: ConstraintRange
    var formality: ConstraintRange
}

struct ConstraintRange: Codable, Hashable, Equatable {
    var min: Double
    var max: Double
    var typical: Double
}

// MARK: - Anchor Families
struct AnchorFamilies: Codable, Hashable, Equatable {
    var openers: [AnchorFamily]
    var turns: [AnchorFamily]
    var proofFrames: [AnchorFamily]
}

struct AnchorFamily: Codable, Hashable, Equatable, Identifiable {
    var id: String { familyId }
    
    let familyId: String
    var canonicalPhrase: String
    var variants: [String]
    var function: String
    var frequency: Double
    var contexts: [String]
    var avgUsesPerScript: Double
}

// MARK: - Cooldown Rules
struct CooldownRules: Codable, Hashable, Equatable {
    var anchorMinDistance: Int
    var anchorMaxFrequency: Double
    var beatTypeMaxConsecutive: Int
}



