//
//  ProseEditorModels.swift
//  NewAgentBuilder
//
//  Data models for the Prose Editor tab — a human-in-the-loop
//  prose iteration tool. User provides a brief, AI generates,
//  user marks up individual sentences, AI reconstructs.
//

import Foundation

// MARK: - Sentence Status

enum SentenceStatus: String, Codable, CaseIterable {
    case pending    // Fresh AI output, user hasn't reviewed
    case keep       // Locked — include verbatim as anchor
    case edited     // User changed text — treat as locked
    case flagged    // Rewrite — include text + annotation
    case struck     // Remove — annotation describes replacement
}

// MARK: - Sentence Unit

struct SentenceUnit: Codable, Identifiable {
    let id: UUID
    var position: Int
    var text: String
    var status: SentenceStatus
    var annotation: String?
    var originalText: String?

    var isLocked: Bool { status == .keep || status == .edited }

    var wordCount: Int {
        text.split(separator: " ").count
    }

    init(position: Int, text: String, status: SentenceStatus = .pending,
         annotation: String? = nil, originalText: String? = nil) {
        self.id = UUID()
        self.position = position
        self.text = text
        self.status = status
        self.annotation = annotation
        self.originalText = originalText
    }
}

// MARK: - Brief

struct ProseBrief: Codable, Identifiable {
    let id: UUID
    var rawInput: String
    var styleProfileRef: String?
    var createdAt: Date

    init(rawInput: String, styleProfileRef: String? = nil) {
        self.id = UUID()
        self.rawInput = rawInput
        self.styleProfileRef = styleProfileRef
        self.createdAt = Date()
    }
}

// MARK: - Draft

struct ProseDraft: Codable, Identifiable {
    let id: UUID
    let briefId: UUID
    var round: Int
    var sentences: [SentenceUnit]
    var rawAIResponse: String
    var createdAt: Date
    var promptTokens: Int
    var completionTokens: Int

    init(briefId: UUID, round: Int, sentences: [SentenceUnit] = [],
         rawAIResponse: String = "", promptTokens: Int = 0, completionTokens: Int = 0) {
        self.id = UUID()
        self.briefId = briefId
        self.round = round
        self.sentences = sentences
        self.rawAIResponse = rawAIResponse
        self.createdAt = Date()
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

// MARK: - Session

struct ProseEditorSession: Codable, Identifiable {
    let id: UUID
    var brief: ProseBrief?
    var drafts: [ProseDraft]
    var currentRound: Int
    var createdAt: Date
    var updatedAt: Date

    var currentDraft: ProseDraft? { drafts.last }

    init() {
        self.id = UUID()
        self.brief = nil
        self.drafts = []
        self.currentRound = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - Editor Phase

enum ProseEditorPhase {
    case brief
    case editing
    case generating
}
