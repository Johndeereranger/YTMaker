//
//  SemanticScriptModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

// MARK: - Content Tags (Detected from Rambling)

struct DetectedTag: Identifiable, Hashable {
    let id = UUID()
    let type: TagType
    let text: String
    let range: Range<String.Index>?

    // Manual Hashable conformance since Range<String.Index> isn't Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
        hasher.combine(text)
    }

    static func == (lhs: DetectedTag, rhs: DetectedTag) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.text == rhs.text
    }

    enum TagType: String, CaseIterable, Hashable {
        case statistic = "STAT"
        case contrast = "CONTRAST"
        case credential = "CREDENTIAL"
        case namedEntity = "ENTITY"
        case question = "QUESTION"
        case claim = "CLAIM"
        case example = "EXAMPLE"
        case emotion = "EMOTION"

        var icon: String {
            switch self {
            case .statistic: return "number"
            case .contrast: return "arrow.left.arrow.right"
            case .credential: return "person.badge.shield.checkmark"
            case .namedEntity: return "building.2"
            case .question: return "questionmark"
            case .claim: return "exclamationmark.bubble"
            case .example: return "lightbulb"
            case .emotion: return "heart"
            }
        }

        var color: String {
            switch self {
            case .statistic: return "blue"
            case .contrast: return "orange"
            case .credential: return "green"
            case .namedEntity: return "purple"
            case .question: return "cyan"
            case .claim: return "red"
            case .example: return "yellow"
            case .emotion: return "pink"
            }
        }
    }
}

// MARK: - Content Gap (What's Missing)

struct ContentGap: Identifiable {
    let id = UUID()
    let type: GapType
    let description: String

    enum GapType: String {
        case noApplication = "No 'so what' / application"
        case noData = "No specific data or numbers"
        case noContrast = "No tension or contrast"
        case noCredential = "No source or credential"
        case vague = "Content too vague to match"
    }
}

// MARK: - Rambling Analysis Result

struct RamblingAnalysis {
    let detectedTags: [DetectedTag]
    let gaps: [ContentGap]
    let contentSummary: String
    let suggestedMatches: [TemplateMatch]
}

// MARK: - Template Match (Corpus Match Result)

struct TemplateMatch: Identifiable {
    let id = UUID()
    let channelId: String
    let channelName: String
    let templateName: String
    let template: StructuralTemplate
    let matchScore: Double  // 0-1, how well the rambling fits this template
    let matchReason: String // Why this template was suggested

    var displayName: String {
        "\(channelName) - \(templateName)"
    }
}

// MARK: - Filled Slot (Content Mapped to Template Chunk)

struct FilledSlot: Identifiable {
    let id = UUID()
    let chunkIndex: Int
    let templateChunk: TemplateChunk
    let mappedContent: String
    let gaps: [String]  // What the template expects but rambling didn't provide
    let overflow: [String]  // Extra content that doesn't fit here

    var hasGaps: Bool { !gaps.isEmpty }
    var hasOverflow: Bool { !overflow.isEmpty }

    var templateGuidance: String {
        "\(templateChunk.typicalRole) - \(templateChunk.highTags.joined(separator: ", "))"
    }
}

// MARK: - Filled Template

struct FilledTemplate: Identifiable {
    let id = UUID()
    let match: TemplateMatch
    let slots: [FilledSlot]
    let parkingLot: [String]  // Content that didn't fit any slot

    var hasUnmappedContent: Bool { !parkingLot.isEmpty }
}

// MARK: - Generated Section

struct GeneratedSection: Identifiable {
    let id = UUID()
    let slotIndex: Int
    let sentences: [GeneratedSentence]
    let generatedAt: Date
}

struct GeneratedSentence: Identifiable {
    let id = UUID()
    let text: String
    let sourceReference: SourceReference?
}

struct SourceReference: Identifiable {
    let id = UUID()
    let videoId: String
    let videoTitle: String
    let channelName: String
    let timestamp: String?
    let matchedSentence: String
    let surroundingContext: [String]  // Sentences before/after
}

// MARK: - View State

enum SemanticScriptPhase: Equatable {
    case rambling
    case analyzing
    case pickingTemplate
    case reviewingSlots
    case generatingSection(slotIndex: Int)
    case reviewingGenerated
}

// MARK: - Script Result (Final Output)

struct SemanticScriptResult: Identifiable {
    let id = UUID()
    let createdAt: Date
    let originalRambling: String
    let selectedTemplate: TemplateMatch
    let filledSlots: [FilledSlot]
    let generatedSections: [Int: GeneratedSection]  // slotIndex -> generated content

    /// Export as formatted text
    func exportAsText() -> String {
        var output = """
        ════════════════════════════════════════════════════════════════
        SEMANTIC SCRIPT - \(selectedTemplate.displayName)
        ════════════════════════════════════════════════════════════════
        Generated: \(createdAt.formatted())

        TEMPLATE: \(selectedTemplate.templateName)
        CREATOR STYLE: \(selectedTemplate.channelName)

        ────────────────────────────────────────────────────────────────
        SCRIPT OUTLINE
        ────────────────────────────────────────────────────────────────

        """

        for slot in filledSlots {
            let position = slot.templateChunk.positionLabel
            let role = slot.templateChunk.typicalRole
            output += "\n[\(position)] \(role)\n"

            if let generated = generatedSections[slot.chunkIndex] {
                output += "--- GENERATED ---\n"
                for sentence in generated.sentences {
                    output += "\(sentence.text)\n"
                }
            } else {
                output += "--- YOUR NOTES ---\n"
                output += "\(slot.mappedContent)\n"
            }

            if slot.hasGaps {
                output += "⚠️ Gaps: \(slot.gaps.joined(separator: ", "))\n"
            }
        }

        return output
    }
}
