//
//  CreatorProfileService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/27/26.
//

import Foundation

// MARK: - Creator Profile Service

/// Service for generating and managing Creator Profiles
/// Takes template extraction output and collapses it into Shape + Ingredients
@MainActor
class CreatorProfileService: ObservableObject {
    static let shared = CreatorProfileService()

    @Published var state: ProfileGenerationState = .idle
    @Published var currentProfile: CreatorProfile?
    @Published var progress: String = ""

    private let profileVersion = "1.0"

    private init() {}

    // MARK: - Generate Profile

    /// Generate a complete creator profile from clustering results
    func generateProfile(
        channel: YouTubeChannel,
        clusteringResult: ClusteringResult,
        creatorTemplate: CreatorTemplate,
        onProgress: ((String) -> Void)? = nil
    ) async -> CreatorProfile? {

        state = .generating(step: "Starting profile generation...")
        onProgress?("Starting profile generation...")

        // Step 1: Extract Style Fingerprint (from existing data)
        progress = "Extracting style fingerprint..."
        onProgress?(progress)
        let styleFingerprint = extractStyleFingerprint(from: creatorTemplate, clustering: clusteringResult)

        // Step 2: Collapse templates into Shape
        progress = "Collapsing templates into shape..."
        onProgress?(progress)
        let shape = await collapseToShape(
            templates: clusteringResult.templates,
            creatorTemplate: creatorTemplate,
            channelName: channel.name
        )

        // Step 3: Extract Ingredient List
        progress = "Extracting ingredient list..."
        onProgress?(progress)
        let ingredients = extractIngredients(
            from: clusteringResult.templates,
            creatorTemplate: creatorTemplate
        )

        // Step 4: Build Profile
        progress = "Building profile..."
        onProgress?(progress)

        let profile = CreatorProfile(
            channelId: channel.channelId,
            channelName: channel.name,
            videosAnalyzed: clusteringResult.videoStructures.count,
            videoIds: clusteringResult.videoStructures.map { $0.videoId },
            styleFingerprint: styleFingerprint,
            shape: shape,
            ingredientList: ingredients,
            profileVersion: profileVersion
        )

        currentProfile = profile
        state = .complete(profile: profile)
        onProgress?("Profile generation complete!")

        return profile
    }

    // MARK: - Style Fingerprint Extraction

    private func extractStyleFingerprint(
        from template: CreatorTemplate,
        clustering: ClusteringResult
    ) -> StyleFingerprint {

        // Calculate average pivot count from video structures
        let pivotCounts = clustering.videoStructures.map { $0.pivotPositions.count }
        let avgPivots = pivotCounts.isEmpty ? 0 : Double(pivotCounts.reduce(0, +)) / Double(pivotCounts.count)

        return StyleFingerprint(
            firstPersonUsage: template.styleMetrics.firstPersonUsage,
            secondPersonUsage: template.styleMetrics.secondPersonUsage,
            thirdPersonUsage: template.styleMetrics.thirdPersonUsage,
            assertingUsage: template.styleMetrics.assertingUsage,
            questioningUsage: template.styleMetrics.questioningUsage,
            challengingUsage: template.styleMetrics.challengingUsage,
            statisticDensity: template.styleMetrics.statisticDensity,
            entityDensity: template.styleMetrics.entityDensity,
            quoteDensity: template.styleMetrics.quoteDensity,
            contrastFrequency: template.styleMetrics.contrastMarkerFrequency,
            revealFrequency: template.styleMetrics.revealLanguageFrequency,
            challengeLanguageFrequency: template.styleMetrics.challengeLanguageFrequency,
            averageChunksPerVideo: template.styleMetrics.averageChunksPerVideo,
            averageSentencesPerChunk: template.styleMetrics.averageSentencesPerChunk,
            averagePivotCount: avgPivots
        )
    }

    // MARK: - Shape Collapse

    private func collapseToShape(
        templates: [StructuralTemplate],
        creatorTemplate: CreatorTemplate,
        channelName: String
    ) async -> ContentShape {

        // Extract intro pattern
        let intro = extractIntroSection(from: creatorTemplate)

        // Extract close pattern
        let close = extractCloseSection(from: creatorTemplate)

        // Collapse middle from all templates
        let middle = collapseMiddle(from: templates)

        // Find what's consistent vs flexible
        let (consistent, flexible) = findConsistentAndFlexible(templates: templates)

        // Generate overall description using AI
        let overallDescription = await generateShapeDescription(
            channelName: channelName,
            templates: templates,
            intro: intro,
            middle: middle,
            close: close
        )

        return ContentShape(
            intro: intro,
            middle: middle,
            close: close,
            overallDescription: overallDescription,
            consistentElements: consistent,
            flexibleElements: flexible
        )
    }

    private func extractIntroSection(from template: CreatorTemplate) -> ShapeSection {
        let opening = template.openingPattern

        // Determine name based on characteristics
        let name: String
        if opening.dominantPerspective == .first {
            name = "Personal Hook"
        } else if opening.dominantStance == .questioning {
            name = "Question Hook"
        } else {
            name = "Context Hook"
        }

        // Extract high tags
        let highTags = opening.typicalTagDensity.topTags.prefix(5).map { $0.name }

        // Get example phrases from examples
        let examples = opening.exampleSentences.prefix(3).map { $0.text }

        return ShapeSection(
            name: name,
            description: "Opens with \(opening.dominantPerspective.rawValue) perspective, \(opening.dominantStance.rawValue) stance",
            typicalPositionRange: "0-15%",
            dominantPerspective: opening.dominantPerspective.rawValue,
            dominantStance: opening.dominantStance.rawValue,
            highTags: Array(highTags),
            examplePhrases: Array(examples)
        )
    }

    private func extractCloseSection(from template: CreatorTemplate) -> ShapeSection {
        let closing = template.closingPattern

        // Determine name
        let name: String
        if closing.dominantPerspective == .second {
            name = "Viewer Address"
        } else if closing.dominantPerspective == .first {
            name = "Personal Reflection"
        } else {
            name = "Summary Close"
        }

        let highTags = closing.typicalTagDensity.topTags.prefix(5).map { $0.name }
        let examples = closing.exampleSentences.prefix(3).map { $0.text }

        return ShapeSection(
            name: name,
            description: "Closes with \(closing.dominantPerspective.rawValue) perspective, \(closing.dominantStance.rawValue) stance",
            typicalPositionRange: "85-100%",
            dominantPerspective: closing.dominantPerspective.rawValue,
            dominantStance: closing.dominantStance.rawValue,
            highTags: Array(highTags),
            examplePhrases: Array(examples)
        )
    }

    private func collapseMiddle(from templates: [StructuralTemplate]) -> MiddleShape {
        guard !templates.isEmpty else {
            return MiddleShape(
                name: "Standard Middle",
                description: "No templates available",
                typicalPositionRange: "15-85%",
                typicalBlockCount: 5,
                pivotCountRange: "1-3",
                commonBlockTypes: [],
                dominantTags: [],
                dominantPerspective: "mixed",
                dominantStance: "asserting"
            )
        }

        // Aggregate across all templates
        var allChunks: [TemplateChunk] = []
        var pivotCounts: [Int] = []

        for template in templates {
            // Get middle chunks (not first or last)
            let middleChunks = template.typicalSequence.filter {
                $0.positionStart >= 0.15 && $0.positionEnd <= 0.85
            }
            allChunks.append(contentsOf: middleChunks)
            pivotCounts.append(template.keyPivots.count)
        }

        // Calculate pivot range
        let minPivots = pivotCounts.min() ?? 0
        let maxPivots = pivotCounts.max() ?? 3
        let pivotRange = "\(minPivots)-\(maxPivots)"

        // Find common block types
        let blockTypes = extractBlockTypes(from: allChunks, totalTemplates: templates.count)

        // Find dominant tags across all middle sections
        var tagCounts: [String: Int] = [:]
        for chunk in allChunks {
            for tag in chunk.highTags {
                tagCounts[tag, default: 0] += 1
            }
        }
        let dominantTags = tagCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }

        // Dominant perspective/stance
        let perspectives = allChunks.map { $0.dominantPerspective.rawValue }
        let stances = allChunks.map { $0.dominantStance.rawValue }
        let dominantPerspective = mostFrequent(perspectives) ?? "mixed"
        let dominantStance = mostFrequent(stances) ?? "asserting"

        // Generate name based on characteristics
        let name = generateMiddleName(
            pivotRange: pivotRange,
            dominantTags: dominantTags,
            blockTypes: blockTypes
        )

        // Generate description
        let description = generateMiddleDescription(
            blockTypes: blockTypes,
            pivotRange: pivotRange,
            dominantTags: dominantTags
        )

        return MiddleShape(
            name: name,
            description: description,
            typicalPositionRange: "15-85%",
            typicalBlockCount: allChunks.count / max(1, templates.count),
            pivotCountRange: pivotRange,
            commonBlockTypes: blockTypes,
            dominantTags: Array(dominantTags),
            dominantPerspective: dominantPerspective,
            dominantStance: dominantStance
        )
    }

    private func extractBlockTypes(from chunks: [TemplateChunk], totalTemplates: Int) -> [BlockType] {
        // Group chunks by role
        var roleGroups: [String: [TemplateChunk]] = [:]
        for chunk in chunks {
            roleGroups[chunk.typicalRole, default: []].append(chunk)
        }

        // Convert to BlockTypes
        return roleGroups.map { role, roleChunks in
            let frequency = Double(roleChunks.count) / Double(max(1, totalTemplates))
            let isPivot = roleChunks.first?.isPivotPoint ?? false

            // Aggregate tags
            var tags: [String: Int] = [:]
            for chunk in roleChunks {
                for tag in chunk.highTags {
                    tags[tag, default: 0] += 1
                }
            }
            let topTags = tags.sorted { $0.value > $1.value }.prefix(3).map { $0.key }

            // Average position
            let avgPos = roleChunks.map { ($0.positionStart + $0.positionEnd) / 2 }.reduce(0, +) / Double(max(1, roleChunks.count))
            let posLabel = avgPos < 0.33 ? "early" : (avgPos < 0.66 ? "mid" : "late")

            return BlockType(
                name: role,
                description: "\(role) block",
                frequency: frequency,
                typicalPosition: posLabel,
                highTags: Array(topTags),
                isPivotPoint: isPivot
            )
        }.sorted { $0.frequency > $1.frequency }
    }

    private func generateMiddleName(pivotRange: String, dominantTags: [String], blockTypes: [BlockType]) -> String {
        // Determine name based on characteristics
        if dominantTags.contains("ENT") && pivotRange.contains("2") || pivotRange.contains("3") || pivotRange.contains("4") {
            return "Investigation Soup"
        } else if dominantTags.contains("STAT") {
            return "Evidence Stack"
        } else if blockTypes.contains(where: { $0.name.lowercased().contains("story") }) {
            return "Narrative Build"
        } else if dominantTags.contains("CONTRAST") {
            return "Tension Builder"
        } else {
            return "Content Core"
        }
    }

    private func generateMiddleDescription(blockTypes: [BlockType], pivotRange: String, dominantTags: [String]) -> String {
        let blockNames = blockTypes.prefix(3).map { $0.name }.joined(separator: ", ")
        let tagStr = dominantTags.prefix(3).joined(separator: ", ")

        return "Builds through \(blockNames) with \(pivotRange) pivots. Heavy on \(tagStr)."
    }

    private func findConsistentAndFlexible(templates: [StructuralTemplate]) -> ([String], [String]) {
        guard templates.count >= 2 else {
            return (["Single template - cannot determine patterns"], [])
        }

        var consistent: [String] = []
        var flexible: [String] = []

        // Check pivot counts
        let pivotCounts = Set(templates.map { $0.keyPivots.count })
        if pivotCounts.count == 1 {
            consistent.append("Exactly \(pivotCounts.first!) pivot points")
        } else {
            flexible.append("Pivot count varies (\(pivotCounts.min()!)-\(pivotCounts.max()!))")
        }

        // Check chunk counts
        let chunkCounts = templates.map { $0.typicalSequence.count }
        let avgChunks = chunkCounts.reduce(0, +) / chunkCounts.count
        let variance = chunkCounts.map { abs($0 - avgChunks) }.reduce(0, +) / chunkCounts.count
        if variance <= 1 {
            consistent.append("~\(avgChunks) chunks per video")
        } else {
            flexible.append("Chunk count varies (\(chunkCounts.min()!)-\(chunkCounts.max()!))")
        }

        // Check for consistent characteristics
        let allCharacteristics = templates.flatMap { $0.dominantCharacteristics }
        var charCounts: [String: Int] = [:]
        for char in allCharacteristics {
            charCounts[char, default: 0] += 1
        }

        for (char, count) in charCounts {
            let frequency = Double(count) / Double(templates.count)
            if frequency >= 0.8 {
                consistent.append(char)
            } else if frequency >= 0.4 {
                flexible.append("\(char) (appears in \(Int(frequency * 100))%)")
            }
        }

        return (consistent, flexible)
    }

    private func generateShapeDescription(
        channelName: String,
        templates: [StructuralTemplate],
        intro: ShapeSection,
        middle: MiddleShape,
        close: ShapeSection
    ) async -> String {
        // For now, generate a rule-based description
        // Later this could be an AI call

        let pivotInfo = middle.pivotCountRange
        let middleName = middle.name

        return """
        \(channelName) videos follow a "\(middleName)" structure: \
        opens with \(intro.name.lowercased()), \
        builds through \(pivotInfo) pivot-complications in the middle, \
        and lands with \(close.name.lowercased()).
        """
    }

    // MARK: - Ingredient Extraction

    private func extractIngredients(
        from templates: [StructuralTemplate],
        creatorTemplate: CreatorTemplate
    ) -> IngredientList {

        var ingredientCandidates: [String: (count: Int, tags: [String], description: String)] = [:]
        let totalVideos = templates.reduce(0) { $0 + $1.videoCount }

        // Extract from templates
        for template in templates {
            // Personal intro check
            if template.typicalSequence.first?.dominantPerspective == .first {
                ingredientCandidates["personal-intro", default: (0, [], "Personal introduction")] = (
                    ingredientCandidates["personal-intro"]?.count ?? 0 + template.videoCount,
                    ["1P"],
                    "Opens with first-person perspective"
                )
            }

            // Pivot complications
            let pivotCount = template.keyPivots.count
            if pivotCount > 0 {
                ingredientCandidates["pivot-complication", default: (0, [], "")] = (
                    ingredientCandidates["pivot-complication"]?.count ?? 0 + template.videoCount,
                    ["CONTRAST", "REVEAL"],
                    "\(pivotCount) pivot-complication(s) that reframe the narrative"
                )
            }

            // Check for entity richness
            let entityChunks = template.typicalSequence.filter { $0.highTags.contains("ENT") }
            if entityChunks.count >= 2 {
                ingredientCandidates["entity-rich", default: (0, [], "")] = (
                    ingredientCandidates["entity-rich"]?.count ?? 0 + template.videoCount,
                    ["ENT"],
                    "Heavy use of named entities throughout"
                )
            }

            // Evidence blocks
            let evidenceChunks = template.typicalSequence.filter {
                $0.typicalRole.lowercased().contains("evidence") ||
                $0.highTags.contains("STAT") ||
                $0.highTags.contains("QUOTE")
            }
            if !evidenceChunks.isEmpty {
                ingredientCandidates["evidence-block", default: (0, [], "")] = (
                    ingredientCandidates["evidence-block"]?.count ?? 0 + template.videoCount,
                    ["STAT", "QUOTE"],
                    "Evidence blocks with statistics or quotes"
                )
            }

            // Viewer address closing
            if template.typicalSequence.last?.dominantPerspective == .second {
                ingredientCandidates["viewer-address", default: (0, [], "")] = (
                    ingredientCandidates["viewer-address"]?.count ?? 0 + template.videoCount,
                    ["2P"],
                    "Direct viewer address in closing"
                )
            }

            // Contrast language
            let contrastChunks = template.typicalSequence.filter { $0.highTags.contains("CONTRAST") }
            if contrastChunks.count >= 2 {
                ingredientCandidates["contrast-language", default: (0, [], "")] = (
                    ingredientCandidates["contrast-language"]?.count ?? 0 + template.videoCount,
                    ["CONTRAST"],
                    "High contrast/tension language throughout"
                )
            }
        }

        // Also check style metrics for density thresholds
        if creatorTemplate.styleMetrics.entityDensity > 0.3 {
            ingredientCandidates["entity-rich"] = (
                totalVideos,
                ["ENT"],
                "Entity density > 30%"
            )
        }

        if creatorTemplate.styleMetrics.statisticDensity > 0.2 {
            ingredientCandidates["statistic-rich"] = (
                Int(Double(totalVideos) * creatorTemplate.styleMetrics.statisticDensity * 2),
                ["STAT"],
                "Heavy use of statistics"
            )
        }

        if creatorTemplate.styleMetrics.contrastMarkerFrequency > 0.2 {
            ingredientCandidates["contrast-language"] = (
                totalVideos,
                ["CONTRAST"],
                "High contrast marker frequency > 20%"
            )
        }

        // Categorize by frequency
        var required: [Ingredient] = []
        var common: [Ingredient] = []
        var optional: [Ingredient] = []

        for (type, data) in ingredientCandidates {
            let frequency = Double(data.count) / Double(max(1, totalVideos))

            let ingredient = Ingredient(
                type: type,
                description: data.description,
                frequency: frequency,
                typicalCount: "varies",
                associatedTags: data.tags,
                exampleFromVideos: nil
            )

            if frequency >= 0.8 {
                required.append(ingredient)
            } else if frequency >= 0.5 {
                common.append(ingredient)
            } else if frequency >= 0.2 {
                optional.append(ingredient)
            }
        }

        // Sort by frequency
        required.sort { $0.frequency > $1.frequency }
        common.sort { $0.frequency > $1.frequency }
        optional.sort { $0.frequency > $1.frequency }

        return IngredientList(
            required: required,
            common: common,
            optional: optional
        )
    }

    // MARK: - Helpers

    private func mostFrequent(_ items: [String]) -> String? {
        var counts: [String: Int] = [:]
        for item in items {
            counts[item, default: 0] += 1
        }
        return counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }.first?.key
    }
}

// MARK: - State

enum ProfileGenerationState {
    case idle
    case generating(step: String)
    case complete(profile: CreatorProfile)
    case failed(error: String)

    var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }
}
