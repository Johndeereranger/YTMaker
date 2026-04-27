//
//  SynthesisModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//

import Foundation

// MARK: - Synthesized Script (Full Run Output)

struct SynthesizedScript: Codable, Identifiable {
    let id: UUID
    let chainAttemptId: UUID
    var sections: [SynthesisSection]
    var smoothedScript: String?
    var moveSequence: [RhetoricalMoveType]
    var synthesizedAt: Date

    // Pass 1 telemetry
    var pass1Telemetry: [SectionTelemetry]

    // Pass 2 debug + telemetry
    var pass2PromptSent: String?
    var pass2SystemPromptSent: String?
    var pass2RawResponse: String?
    var pass2Telemetry: SectionTelemetry?
    var pass1ConcatenatedDraft: String?

    // Versioning
    var promptVersion: String

    init(
        chainAttemptId: UUID,
        sections: [SynthesisSection] = [],
        smoothedScript: String? = nil,
        moveSequence: [RhetoricalMoveType] = [],
        pass1Telemetry: [SectionTelemetry] = [],
        promptVersion: String = SynthesisPromptEngine.PROMPT_VERSION
    ) {
        self.id = UUID()
        self.chainAttemptId = chainAttemptId
        self.sections = sections
        self.smoothedScript = smoothedScript
        self.moveSequence = moveSequence
        self.synthesizedAt = Date()
        self.pass1Telemetry = pass1Telemetry
        self.promptVersion = promptVersion
    }
}

// MARK: - Synthesis Section (Per-Position Output)

struct SynthesisSection: Codable, Identifiable {
    let id: UUID
    let positionIndex: Int
    let moveType: RhetoricalMoveType

    // LLM output
    var writtenText: String
    var summary: String
    var callbacks: [String]
    var endingNote: String
    var analysis: String

    // Source data
    var ramblingGistId: UUID?
    var ramblingSourceText: String?
    var gistLabel: String?

    // Debug: full prompts and response
    var promptSent: String
    var systemPromptSent: String
    var rawResponse: String

    // Debug: corpus context used
    var creatorSectionCount: Int
    var creatorVideoTitles: [String]
    var transitionBridgeUsed: Bool

    // Error tracking
    var parseError: Bool
    var retryCount: Int

    init(
        positionIndex: Int,
        moveType: RhetoricalMoveType,
        writtenText: String = "",
        summary: String = "",
        callbacks: [String] = [],
        endingNote: String = "",
        analysis: String = "",
        ramblingGistId: UUID? = nil,
        ramblingSourceText: String? = nil,
        gistLabel: String? = nil,
        promptSent: String = "",
        systemPromptSent: String = "",
        rawResponse: String = "",
        creatorSectionCount: Int = 0,
        creatorVideoTitles: [String] = [],
        transitionBridgeUsed: Bool = false,
        parseError: Bool = false,
        retryCount: Int = 0
    ) {
        self.id = UUID()
        self.positionIndex = positionIndex
        self.moveType = moveType
        self.writtenText = writtenText
        self.summary = summary
        self.callbacks = callbacks
        self.endingNote = endingNote
        self.analysis = analysis
        self.ramblingGistId = ramblingGistId
        self.ramblingSourceText = ramblingSourceText
        self.gistLabel = gistLabel
        self.promptSent = promptSent
        self.systemPromptSent = systemPromptSent
        self.rawResponse = rawResponse
        self.creatorSectionCount = creatorSectionCount
        self.creatorVideoTitles = creatorVideoTitles
        self.transitionBridgeUsed = transitionBridgeUsed
        self.parseError = parseError
        self.retryCount = retryCount
    }
}

// MARK: - Section Telemetry

struct SectionTelemetry: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let modelUsed: String

    init(from bundle: AIResponseBundle) {
        self.promptTokens = bundle.promptTokens
        self.completionTokens = bundle.completionTokens
        self.totalTokens = bundle.totalTokens
        self.modelUsed = bundle.modelUsed
    }

    init(promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int = 0, modelUsed: String = "") {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.modelUsed = modelUsed
    }
}

// MARK: - Synthesis Run Summary (lightweight, for history picker)

struct SynthesisRunSummary: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let promptVersion: String
    let sectionCount: Int
    let moveSequenceSummary: String
    let hasPass2: Bool

    init(from script: SynthesizedScript) {
        self.id = script.id
        self.timestamp = script.synthesizedAt
        self.promptVersion = script.promptVersion
        self.sectionCount = script.sections.count
        self.moveSequenceSummary = script.moveSequence.prefix(5)
            .map(\.displayName)
            .joined(separator: " → ")
            + (script.moveSequence.count > 5 ? " → ..." : "")
        self.hasPass2 = script.smoothedScript != nil
    }
}

// MARK: - Pass 1 JSON Parse Response

struct Pass1JSONResponse: Codable {
    let writtenText: String
    let summary: String
    let callbacks: [String]?
    let endingNote: String

    enum CodingKeys: String, CodingKey {
        case writtenText
        case summary
        case callbacks
        case endingNote
    }
}
