//
//  ScriptTraceModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation
import SwiftUI

// MARK: - Adaptation Tier

enum AdaptationTier: String, Codable, CaseIterable {
    case tier1 = "T1"       // Full donor adaptation (70-80%)
    case tier2 = "T2"       // Sub-decomposition needed (15-20%)
    case tier3 = "T3"       // Rhythm-constrained generation (5-10%)
    case none = "None"

    var displayName: String {
        switch self {
        case .tier1: return "Tier 1 — Donor Adapt"
        case .tier2: return "Tier 2 — Sub-Decompose"
        case .tier3: return "Tier 3 — Rhythm Gen"
        case .none: return "None"
        }
    }

    var color: Color {
        switch self {
        case .tier1: return .green
        case .tier2: return .yellow
        case .tier3: return .red
        case .none: return .gray
        }
    }
}

// MARK: - Content Payload (W1.5 — ephemeral, not persisted)

struct ContentPayload: Identifiable {
    let id = UUID()
    let gistFrameId: UUID               // Parent gist
    let payloadIndex: Int               // Order within gist
    let contentText: String             // The atomic fact/claim/observation
    let payloadType: PayloadType
    let targetSlotTypes: [SlotType]     // Which slot types this maps to
    let complexity: PayloadComplexity

    enum PayloadComplexity: String, Codable {
        case single
        case compound
    }
}

// MARK: - Script Beat (full trace per beat — ephemeral)

struct ScriptBeat: Identifiable {
    let id = UUID()
    let beatIndex: Int
    let sectionMove: String             // RhetoricalMoveType raw value
    let sectionCategory: String         // RhetoricalCategory raw value

    // W1.5 — Payload decomposition
    var payloads: [ContentPayload]

    // W2 — Slot bigram walk
    var targetSlotSignature: String?

    // W3 — Donor retrieval
    var donorSentence: CreatorSentence?
    var donorMatchReason: String?
    var donorSimilarityScore: Double?

    // W4 — Adaptation
    var adaptedText: String?
    var adaptationTier: AdaptationTier = .none

    // W5 — Seam check
    var seamEdit: String?
    var finalText: String?

    // Status
    var isProcessing: Bool = false
    var error: String?
}
