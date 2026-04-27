//
//  SectionQuestionsModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/29/26.
//

import Foundation

// MARK: - Section Question Input (Pre-Generation)

/// Represents a single section from a video that can be sent to AI
/// for "what questions does this section answer?" analysis.
struct SectionQuestionInput: Identifiable {
    let videoId: String
    let videoTitle: String
    let chunkIndex: Int
    let moveType: RhetoricalMoveType
    let position: FingerprintPosition
    let sectionText: String
    let briefDescription: String

    var id: String { "\(videoId)_\(chunkIndex)" }
}

// MARK: - Section Questions Document (Firestore)

/// Stores the AI-generated "questions answered" analysis for a single section.
/// Document ID is deterministic: `{creatorId}_{videoId}_{chunkIndex}`
struct SectionQuestionsDocument: Codable, Identifiable {
    let creatorId: String
    let videoId: String
    let videoTitle: String
    let chunkIndex: Int
    let moveLabel: String               // RhetoricalMoveType.rawValue
    let position: String                // FingerprintPosition.rawValue
    let sectionText: String             // Raw transcript text sent to AI
    let briefDescription: String        // From RhetoricalMove.briefDescription
    let questionsAnswered: String       // AI-generated response
    let generatedAt: Date
    let promptSent: String
    let systemPromptSent: String
    let tokensUsed: Int

    var id: String { "\(creatorId)_\(videoId)_\(chunkIndex)" }

    var moveLabelType: RhetoricalMoveType? {
        RhetoricalMoveType(rawValue: moveLabel)
    }

    var positionType: FingerprintPosition? {
        FingerprintPosition(rawValue: position)
    }
}

// MARK: - Generation Result

struct SectionQuestionResult: Identifiable {
    let id = UUID()
    let input: SectionQuestionInput
    let status: GenerationStatus
    let questionsAnswered: String?
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

        var displayText: String {
            switch self {
            case .pending: return "Pending"
            case .inProgress: return "Running..."
            case .success: return "Done"
            case .failed(let msg): return "Failed: \(msg)"
            }
        }

        var isTerminal: Bool {
            switch self {
            case .success, .failed: return true
            default: return false
            }
        }
    }
}
