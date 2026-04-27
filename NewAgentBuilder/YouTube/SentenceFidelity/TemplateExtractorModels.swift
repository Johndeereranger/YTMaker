//
//  TemplateExtractorModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

// MARK: - Creator Template

/// Extracted template representing a creator's structural patterns
struct CreatorTemplate: Codable, Identifiable {
    let id: String
    let channelId: String
    let channelName: String
    let createdAt: Date

    // Source data
    let videosAnalyzed: Int
    let videoIds: [String]

    // Extracted patterns
    let openingPattern: SectionPattern
    let closingPattern: SectionPattern
    let contentPatterns: [ContentPattern]

    // Overall style metrics
    let styleMetrics: StyleMetrics

    // Version tracking
    let extractorVersion: String
}

// MARK: - Section Pattern

/// Pattern for a specific section type (opening/closing)
struct SectionPattern: Codable {
    let sectionType: SectionType

    // Typical structure
    let averageChunkCount: Double
    let averageSentenceCount: Double

    // Dominant characteristics
    let dominantPerspective: ChunkProfile.DominantValue
    let dominantStance: ChunkProfile.DominantValue

    // Common tag densities (averaged across videos)
    let typicalTagDensity: AveragedTagDensity

    // Common boundary triggers
    let commonTriggers: [TriggerFrequency]

    // Example sentences from analyzed videos
    let exampleSentences: [ExampleSentence]

    enum SectionType: String, Codable {
        case opening
        case closing
    }
}

// MARK: - Content Pattern

/// Pattern for middle content sections
struct ContentPattern: Codable, Identifiable {
    var id: String { patternId }
    let patternId: String

    // What characterizes this pattern
    let patternName: String  // e.g., "Evidence Block", "Story Section", "Explanation"
    let frequency: Double    // How often this pattern appears (0-1)

    // Structural characteristics
    let averageSentenceCount: Double
    let typicalPosition: PositionRange  // Where in video this typically appears

    // Content characteristics
    let dominantPerspective: ChunkProfile.DominantValue
    let dominantStance: ChunkProfile.DominantValue
    let typicalTagDensity: AveragedTagDensity

    // Transition patterns
    let typicalEntryTrigger: BoundaryTrigger.BoundaryTriggerType?
    let typicalExitTrigger: BoundaryTrigger.BoundaryTriggerType?

    // Examples
    let exampleChunks: [ChunkExample]
}

// MARK: - Style Metrics

/// Overall style characteristics across the creator's videos
struct StyleMetrics: Codable {
    // Perspective usage
    let firstPersonUsage: Double   // 0-1
    let secondPersonUsage: Double  // 0-1
    let thirdPersonUsage: Double   // 0-1

    // Stance distribution
    let assertingUsage: Double
    let questioningUsage: Double
    let challengingUsage: Double

    // Content characteristics
    let statisticDensity: Double
    let entityDensity: Double
    let quoteDensity: Double

    // Structural
    let averageChunksPerVideo: Double
    let averageSentencesPerChunk: Double

    // Engagement features
    let contrastMarkerFrequency: Double
    let revealLanguageFrequency: Double
    let challengeLanguageFrequency: Double
}

// MARK: - Supporting Types

struct AveragedTagDensity: Codable {
    let hasNumber: Double
    let hasStatistic: Double
    let hasNamedEntity: Double
    let hasQuote: Double
    let hasContrastMarker: Double
    let hasRevealLanguage: Double
    let hasChallengeLanguage: Double
    let hasFirstPerson: Double
    let hasSecondPerson: Double
    let isTransition: Double
    let isSponsorContent: Double
    let isCallToAction: Double

    /// Top tags by density
    var topTags: [(name: String, value: Double)] {
        let allTags: [(name: String, value: Double)] = [
            ("Numbers", hasNumber),
            ("Statistics", hasStatistic),
            ("Entities", hasNamedEntity),
            ("Quotes", hasQuote),
            ("Contrast", hasContrastMarker),
            ("Reveal", hasRevealLanguage),
            ("Challenge", hasChallengeLanguage),
            ("1st Person", hasFirstPerson),
            ("2nd Person", hasSecondPerson)
        ]
        let filtered = allTags.filter { $0.value > 0.05 }
        let sorted = filtered.sorted { $0.value > $1.value }
        return Array(sorted.prefix(5))
    }

    static let empty = AveragedTagDensity(
        hasNumber: 0, hasStatistic: 0, hasNamedEntity: 0, hasQuote: 0,
        hasContrastMarker: 0, hasRevealLanguage: 0, hasChallengeLanguage: 0,
        hasFirstPerson: 0, hasSecondPerson: 0, isTransition: 0,
        isSponsorContent: 0, isCallToAction: 0
    )
}

struct TriggerFrequency: Codable {
    let triggerType: BoundaryTrigger.BoundaryTriggerType
    let frequency: Double  // 0-1, how often this trigger appears
    let count: Int
}

struct ExampleSentence: Codable, Identifiable {
    var id: String { "\(videoId)-\(sentenceIndex)" }
    let videoId: String
    let videoTitle: String
    let sentenceIndex: Int
    let text: String
    let tags: [String]  // Active tags on this sentence
}

struct PositionRange: Codable {
    let start: Double  // 0-1
    let end: Double    // 0-1

    var label: String {
        if start < 0.2 && end < 0.3 {
            return "Early"
        } else if start > 0.7 && end > 0.8 {
            return "Late"
        } else {
            return "Middle (\(Int(start * 100))%-\(Int(end * 100))%)"
        }
    }
}

struct ChunkExample: Codable, Identifiable {
    var id: String { "\(videoId)-\(chunkIndex)" }
    let videoId: String
    let videoTitle: String
    let chunkIndex: Int
    let sentenceCount: Int
    let preview: String  // First few sentences
    let position: Double
}

// MARK: - Extraction Progress

enum TemplateExtractionState {
    case idle
    case analyzing(progress: String)
    case complete(template: CreatorTemplate)
    case failed(error: String)
}
