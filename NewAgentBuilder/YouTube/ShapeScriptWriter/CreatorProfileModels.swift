//
//  CreatorProfileModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/27/26.
//

import Foundation

// MARK: - Creator Profile

/// Complete profile for a creator, containing everything needed to generate scripts in their style
struct CreatorProfile: Codable, Identifiable {
    let id: String
    let channelId: String
    let channelName: String
    let createdAt: Date
    let updatedAt: Date

    // Source data
    let videosAnalyzed: Int
    let videoIds: [String]

    // The three core components
    let styleFingerprint: StyleFingerprint
    let shape: ContentShape
    let ingredientList: IngredientList

    // Version tracking
    let profileVersion: String

    init(
        id: String = UUID().uuidString,
        channelId: String,
        channelName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        videosAnalyzed: Int,
        videoIds: [String],
        styleFingerprint: StyleFingerprint,
        shape: ContentShape,
        ingredientList: IngredientList,
        profileVersion: String = "1.0"
    ) {
        self.id = id
        self.channelId = channelId
        self.channelName = channelName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.videosAnalyzed = videosAnalyzed
        self.videoIds = videoIds
        self.styleFingerprint = styleFingerprint
        self.shape = shape
        self.ingredientList = ingredientList
        self.profileVersion = profileVersion
    }
}

// MARK: - Style Fingerprint

/// Quantitative style metrics extracted from analysis
struct StyleFingerprint: Codable {
    // Perspective distribution
    let firstPersonUsage: Double   // 0.0-1.0
    let secondPersonUsage: Double
    let thirdPersonUsage: Double

    // Stance distribution
    let assertingUsage: Double
    let questioningUsage: Double
    let challengingUsage: Double

    // Content density
    let statisticDensity: Double
    let entityDensity: Double
    let quoteDensity: Double

    // Engagement features
    let contrastFrequency: Double
    let revealFrequency: Double
    let challengeLanguageFrequency: Double

    // Structure
    let averageChunksPerVideo: Double
    let averageSentencesPerChunk: Double
    let averagePivotCount: Double

    /// Plain English summary of the style
    var summary: String {
        var parts: [String] = []

        // Perspective
        if firstPersonUsage > 0.4 {
            parts.append("heavily personal (1P: \(pct(firstPersonUsage)))")
        } else if secondPersonUsage > 0.3 {
            parts.append("viewer-focused (2P: \(pct(secondPersonUsage)))")
        } else if thirdPersonUsage > 0.5 {
            parts.append("documentary-style (3P: \(pct(thirdPersonUsage)))")
        }

        // Content richness
        if entityDensity > 0.3 {
            parts.append("entity-rich (\(pct(entityDensity)))")
        }
        if statisticDensity > 0.2 {
            parts.append("data-driven (\(pct(statisticDensity)))")
        }

        // Engagement
        if contrastFrequency > 0.2 {
            parts.append("high contrast/tension")
        }

        return parts.isEmpty ? "balanced style" : parts.joined(separator: ", ")
    }

    private func pct(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }
}

// MARK: - Content Shape

/// The structural "shape" of videos - intro, middle, and close patterns
struct ContentShape: Codable {
    let intro: ShapeSection
    let middle: MiddleShape
    let close: ShapeSection

    /// AI-generated plain English description of overall shape
    let overallDescription: String

    /// What's consistent across all videos
    let consistentElements: [String]

    /// What varies between videos
    let flexibleElements: [String]
}

/// A section of the shape (intro or close)
struct ShapeSection: Codable {
    let name: String                    // e.g., "Personal Hook", "Viewer Address"
    let description: String             // Plain English description
    let typicalPositionRange: String    // e.g., "0-15%"
    let dominantPerspective: String     // "first", "second", "third", "mixed"
    let dominantStance: String          // "asserting", "questioning", "challenging"
    let highTags: [String]              // Common tags in this section
    let examplePhrases: [String]        // Example opening/closing phrases from real videos
}

/// The middle section shape - more complex, describes the "investigation soup"
struct MiddleShape: Codable {
    let name: String                    // e.g., "Investigation Soup", "Evidence Stack"
    let description: String             // Plain English: what does the middle "do"?
    let typicalPositionRange: String    // e.g., "15-85%"

    // Structure
    let typicalBlockCount: Int          // How many distinct blocks/sections
    let pivotCountRange: String         // e.g., "2-4 pivots"

    // Block types that appear
    let commonBlockTypes: [BlockType]

    // Dominant characteristics
    let dominantTags: [String]          // Most common tags throughout middle
    let dominantPerspective: String
    let dominantStance: String
}

/// A type of block that appears in the middle section
struct BlockType: Codable {
    let name: String                    // e.g., "Context Block", "Evidence Block", "Pivot-Complication"
    let description: String             // What this block does
    let frequency: Double               // How often it appears (0.0-1.0)
    let typicalPosition: String         // Where in the middle it usually appears
    let highTags: [String]              // Tags associated with this block type
    let isPivotPoint: Bool              // Is this typically a pivot?
}

// MARK: - Ingredient List

/// What elements MUST appear vs what's optional
struct IngredientList: Codable {
    /// Must appear (80%+ of videos)
    let required: [Ingredient]

    /// Often appears (50-80% of videos)
    let common: [Ingredient]

    /// Sometimes appears (<50% of videos)
    let optional: [Ingredient]

    /// Get all ingredients as flat list
    var all: [Ingredient] {
        required + common + optional
    }

    /// Check if an ingredient type is required
    func isRequired(_ type: String) -> Bool {
        required.contains { $0.type.lowercased() == type.lowercased() }
    }
}

/// A single ingredient element
struct Ingredient: Codable, Identifiable {
    var id: String { type }

    let type: String                    // e.g., "pivot-complication", "personal-intro"
    let description: String             // What it is
    let frequency: Double               // How often it appears
    let typicalCount: String            // e.g., "2-4 per video" or "1 at start"
    let associatedTags: [String]        // Tags that indicate this ingredient
    let exampleFromVideos: String?      // Example pulled from actual video
}

// MARK: - Script Generation Models

/// Extracted content from user's rambling (AI Call #1 output)
struct ExtractedContent: Codable {
    let hookCandidates: [String]        // What makes someone care?
    let corePoints: [String]            // Main claims/arguments
    let evidenceExamples: [String]      // Evidence mentioned
    let ahaRevelation: String?          // The "aha" moment
    let landing: String?                // How should viewer feel at end?
    let rawRambling: String             // Original input
}

/// Gap analysis result (AI Call #2 output)
struct GapAnalysis: Codable {
    let missingIngredients: [String]    // What's missing from the rambling
    let questions: [GapQuestion]        // Questions for user to answer
    let coverageScore: Int              // 0-100, how complete is the rambling?
}

struct GapQuestion: Codable, Identifiable {
    var id: String { question }

    let question: String                // The question to ask
    let reason: String                  // Why we're asking (ties to ingredient)
    let ingredientType: String          // Which ingredient this fills
    let priority: Int                   // 1 = critical, 2 = important, 3 = nice-to-have
}

/// Script outline (AI Call #3 output)
struct ScriptOutline: Codable {
    let sections: [ShapeOutlineSection]
    let estimatedLength: String         // e.g., "8-10 minutes"
    let structureNotes: String          // Notes about the structure
}

struct ShapeOutlineSection: Codable, Identifiable {
    let id: String
    let sectionName: String             // e.g., "INTRO", "CONTEXT BLOCK 1", "PIVOT 1"
    let positionRange: String           // e.g., "0-15%"
    let contentSummary: String          // What this section covers
    let dbQuery: String                 // Query to pull examples from DB
    let targetTags: [String]            // Tags this section should hit
    let isPivot: Bool

    init(
        id: String = UUID().uuidString,
        sectionName: String,
        positionRange: String,
        contentSummary: String,
        dbQuery: String,
        targetTags: [String],
        isPivot: Bool = false
    ) {
        self.id = id
        self.sectionName = sectionName
        self.positionRange = positionRange
        self.contentSummary = contentSummary
        self.dbQuery = dbQuery
        self.targetTags = targetTags
        self.isPivot = isPivot
    }
}

/// Final generated script section (AI Call #4 output)
struct ShapeGeneratedSection: Codable, Identifiable {
    let id: String
    let sectionName: String
    let scriptText: String              // The actual written script
    let wordCount: Int
    let tagsHit: [String]               // Which target tags were hit
    let confidence: Int                 // 0-100, how well does it match style?

    init(
        id: String = UUID().uuidString,
        sectionName: String,
        scriptText: String,
        wordCount: Int,
        tagsHit: [String],
        confidence: Int
    ) {
        self.id = id
        self.sectionName = sectionName
        self.scriptText = scriptText
        self.wordCount = wordCount
        self.tagsHit = tagsHit
        self.confidence = confidence
    }
}

// MARK: - Convenience Extensions

extension CreatorProfile {
    /// Export as readable text for debugging/review
    var exportText: String {
        """
        ══════════════════════════════════════════════════════════════════
        CREATOR PROFILE: \(channelName)
        ══════════════════════════════════════════════════════════════════
        Created: \(createdAt.formatted())
        Videos Analyzed: \(videosAnalyzed)
        Profile Version: \(profileVersion)

        ────────────────────────────────────────────────────────────────────
        STYLE FINGERPRINT
        ────────────────────────────────────────────────────────────────────
        \(styleFingerprint.summary)

        Perspective: 1P \(pct(styleFingerprint.firstPersonUsage)) | 2P \(pct(styleFingerprint.secondPersonUsage)) | 3P \(pct(styleFingerprint.thirdPersonUsage))
        Stance: Assert \(pct(styleFingerprint.assertingUsage)) | Question \(pct(styleFingerprint.questioningUsage)) | Challenge \(pct(styleFingerprint.challengingUsage))
        Content: ENT \(pct(styleFingerprint.entityDensity)) | STAT \(pct(styleFingerprint.statisticDensity)) | QUOTE \(pct(styleFingerprint.quoteDensity))
        Engagement: CONTRAST \(pct(styleFingerprint.contrastFrequency)) | REVEAL \(pct(styleFingerprint.revealFrequency))
        Structure: ~\(String(format: "%.1f", styleFingerprint.averageChunksPerVideo)) chunks/video, ~\(String(format: "%.1f", styleFingerprint.averagePivotCount)) pivots

        ────────────────────────────────────────────────────────────────────
        CONTENT SHAPE
        ────────────────────────────────────────────────────────────────────
        \(shape.overallDescription)

        INTRO (\(shape.intro.typicalPositionRange)):
          "\(shape.intro.name)" - \(shape.intro.description)
          Tags: \(shape.intro.highTags.joined(separator: ", "))

        MIDDLE (\(shape.middle.typicalPositionRange)):
          "\(shape.middle.name)" - \(shape.middle.description)
          Pivots: \(shape.middle.pivotCountRange)
          Block types: \(shape.middle.commonBlockTypes.map { $0.name }.joined(separator: ", "))

        CLOSE (\(shape.close.typicalPositionRange)):
          "\(shape.close.name)" - \(shape.close.description)
          Tags: \(shape.close.highTags.joined(separator: ", "))

        Consistent: \(shape.consistentElements.joined(separator: ", "))
        Flexible: \(shape.flexibleElements.joined(separator: ", "))

        ────────────────────────────────────────────────────────────────────
        INGREDIENT LIST
        ────────────────────────────────────────────────────────────────────
        REQUIRED (must appear):
        \(ingredientList.required.map { "  - \($0.type): \($0.description)" }.joined(separator: "\n"))

        COMMON (often appears):
        \(ingredientList.common.map { "  - \($0.type): \($0.description)" }.joined(separator: "\n"))

        OPTIONAL (sometimes appears):
        \(ingredientList.optional.map { "  - \($0.type): \($0.description)" }.joined(separator: "\n"))
        """
    }

    private func pct(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }
}
