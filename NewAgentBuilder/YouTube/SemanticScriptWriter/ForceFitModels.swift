//
//  ForceFitModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

// MARK: - Step 1: Force-Fit Result (Initial)

/// Result of Step 1: Initial force-fit of rambling to a single template
/// Now uses StructuralTemplate (discovered from real video analysis)
struct ForceFitResult: Identifiable {
    let id = UUID()
    let templateId: String
    let templateName: String
    let template: StructuralTemplate  // Real template from database
    let fitScore: Int  // 0-100
    let chunksFilled: [Int]  // chunk indices that have content
    let chunksMissing: [Int]  // chunk indices missing content
    let questions: [String]  // questions to fill missing chunks
    let rawResponse: String  // Full Claude response for debugging

    var filledPercentage: Int {
        let total = chunksFilled.count + chunksMissing.count
        guard total > 0 else { return 0 }
        return Int((Double(chunksFilled.count) / Double(total)) * 100)
    }
}

// MARK: - Step 2: Question Aggregation Result

/// Result of Step 2: Consolidated questions across all templates
struct QuestionAggregationResult {
    let consolidatedQuestions: [String]
    let questionCountBefore: Int
    let questionCountAfter: Int
    let rawResponse: String
}

// MARK: - Step 4: Re-Fit Result (After Answers)

/// Result of Step 4: Re-fit with enriched content
/// Now uses StructuralTemplate (discovered from real video analysis)
struct ReFitResult: Identifiable {
    let id = UUID()
    let templateId: String
    let templateName: String
    let template: StructuralTemplate  // Real template from database
    let fitScore: Int  // 0-100
    let chunkMapping: [Int: ChunkMapping]  // chunk_index -> mapping
    let weakChunks: [Int]  // chunk indices still weak
    let overallConfidence: Int  // 0-100
    let rawResponse: String
}

/// Content mapped to a single chunk with confidence
struct ChunkMapping: Codable {
    let content: String
    let confidence: Int  // 0-100
}

// MARK: - Step 5: Evaluation & Ranking Result

/// Result of Step 5: Ranked templates with reasoning
struct EvaluationResult {
    let rankedTemplates: [RankedTemplate]
    let recommendation: String  // template_id of rank 1
    let confidence: ConfidenceLevel
    let warnings: [String]
    let rawResponse: String
}

/// A single ranked template with reasoning
struct RankedTemplate: Identifiable {
    let id = UUID()
    let rank: Int
    let templateId: String
    let templateName: String
    let fitScore: Int
    let reasoning: String
}

enum ConfidenceLevel: String, Codable {
    case high
    case medium
    case low
}

// MARK: - View State

enum ForceFitPhase: Equatable {
    case selectingCreators
    case rambling
    case forceFitting          // Step 1
    case aggregatingQuestions  // Step 2
    case reviewingQuestions    // Show consolidated questions
    case ramblingAgain         // Step 3
    case refitting             // Step 4
    case evaluating            // Step 5
    case selectingTemplate     // Step 6
    case done
}

// MARK: - Aggregated Results

/// Combined results from Step 1: all template force-fits
struct Step1Results {
    let results: [ForceFitResult]

    var sortedByFit: [ForceFitResult] {
        results.sorted { $0.fitScore > $1.fitScore }
    }

    /// All questions from all templates (before aggregation)
    var allRawQuestions: [String] {
        results.flatMap { $0.questions }
    }
}

/// Combined results from Step 4: all template re-fits
struct Step4Results {
    let results: [ReFitResult]

    var sortedByFit: [ReFitResult] {
        results.sorted { $0.fitScore > $1.fitScore }
    }
}

// MARK: - Final Selection

/// The user's selected template with mapped content
struct SelectedTemplate: Identifiable {
    let id = UUID()
    let template: StructuralTemplate  // Real template from database
    let reFitResult: ReFitResult
    let combinedRambling: String  // Original + follow-up
    let selectedAt: Date = Date()
}

// MARK: - Helper: Generate Question for Missing Chunk

/// Generates an extraction question for a TemplateChunk based on its properties
func generateExtractionQuestion(for chunk: TemplateChunk) -> String {
    let role = chunk.typicalRole.lowercased()

    // Based on typical role
    if role.contains("hook") || role.contains("opening") {
        return "What's your attention-grabbing opening? What will make viewers want to watch?"
    }
    if role.contains("credential") || role.contains("authority") {
        return "What makes you credible on this topic? What's your experience or qualification?"
    }
    if role.contains("evidence") || role.contains("data") {
        return "What specific evidence or data supports your point?"
    }
    if role.contains("pivot") || role.contains("contrast") || role.contains("shift") {
        return "What's the 'but' or 'however' moment? What challenges the initial view?"
    }
    if role.contains("reveal") || role.contains("insight") {
        return "What's the main insight or revelation you're sharing?"
    }
    if role.contains("application") || role.contains("action") || role.contains("takeaway") {
        return "What should viewers actually do with this information?"
    }
    if role.contains("conclusion") || role.contains("ending") {
        return "How do you want viewers to think/feel at the end?"
    }

    // Based on high tags
    if chunk.highTags.contains("STAT") {
        return "What specific numbers or data do you have for the '\(chunk.typicalRole)' section?"
    }
    if chunk.highTags.contains("1P") {
        return "What personal experience or observation fits the '\(chunk.typicalRole)' section?"
    }
    if chunk.highTags.contains("2P") {
        return "What do you want to say directly to the viewer in the '\(chunk.typicalRole)' section?"
    }
    if chunk.highTags.contains("CONTRAST") {
        return "What contrasting viewpoint or tension fits the '\(chunk.typicalRole)' section?"
    }
    if chunk.highTags.contains("QUOTE") || chunk.highTags.contains("CREDENTIAL") {
        return "What expert source or credential fits the '\(chunk.typicalRole)' section?"
    }

    // Generic fallback
    return "What content fits the '\(chunk.typicalRole)' section? (\(chunk.positionLabel))"
}

/// Generates expected content description for a TemplateChunk
func generateExpectedContent(for chunk: TemplateChunk) -> String {
    var parts: [String] = []

    // Based on high tags
    if chunk.highTags.contains("STAT") {
        parts.append("specific numbers or data")
    }
    if chunk.highTags.contains("1P") {
        parts.append("personal experience or perspective")
    }
    if chunk.highTags.contains("2P") {
        parts.append("direct address to viewer")
    }
    if chunk.highTags.contains("CONTRAST") {
        parts.append("contrasting viewpoint or tension")
    }
    if chunk.highTags.contains("QUOTE") || chunk.highTags.contains("CREDENTIAL") {
        parts.append("expert source or credential")
    }

    // Based on pivot
    if chunk.isPivotPoint {
        if let desc = chunk.pivotDescription {
            parts.append(desc.lowercased())
        } else {
            parts.append("major shift or revelation")
        }
    }

    // Default
    if parts.isEmpty {
        parts.append(chunk.typicalRole)
    }

    return parts.joined(separator: ", ")
}
