//
//  SkeletonComplianceService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/21/26.
//
//  Skeleton Compliance Test — Phase B proof of concept.
//  Takes a real corpus section as a structural skeleton, generates new content
//  for a different topic using the lookup-table-driven prompt per position,
//  then validates each generated sentence with the 8 deterministic hint detectors
//  and scores the full section via ScriptFidelityService.
//

import Foundation

// MARK: - Data Models

struct PositionSpec {
    let index: Int
    let slotSignature: String
    let wordCount: Int
    let sentenceType: String       // "statement" | "question" | "fragment"
    let originalText: String       // skeleton sentence (display/debug only)
}

struct ComplianceTestResult {
    let positions: [PositionResult]
    let sectionFidelity: SectionFidelityResult?
    let generatedSectionText: String
    let moveType: String?

    struct PositionResult {
        let index: Int
        let targetSignature: String
        let actualSignature: String
        let signatureMatch: Bool
        let targetWordCount: Int
        let actualWordCount: Int
        let generatedText: String
        let donorText: String
        let prompt: String
    }

    var signatureHitRate: Double {
        guard !positions.isEmpty else { return 0 }
        let hits = positions.filter(\.signatureMatch).count
        return Double(hits) / Double(positions.count)
    }

    var avgWordCountDelta: Double {
        guard !positions.isEmpty else { return 0 }
        let total = positions.map { abs($0.actualWordCount - $0.targetWordCount) }.reduce(0, +)
        return Double(total) / Double(positions.count)
    }
}

// MARK: - Skeleton Compliance Service

enum SkeletonComplianceService {

    // MARK: - Lookup Table

    /// Maps a single slot type to plain-English token requirements for the Claude prompt.
    static func tokenRequirements(for slotType: String) -> String {
        switch slotType {
        case "temporal_marker":
            return "Must contain a specific year (e.g. \"In 2018\") OR one of these words: ago, recently, decade, last year, earlier, later."
        case "quantitative_claim":
            return "Must contain a specific number — either digits (like \"47\" or \"3.5\") or number words (like \"million\", \"forty\", \"hundreds\")."
        case "contradiction":
            return "Must contain one of these contrast words: but, however, yet, actually, though, instead, although, nevertheless."
        case "direct_address":
            return "Must address the viewer directly using \"you\" or \"your\"."
        case "narrative_action":
            return "Must use first person (I, me, my, we, our). Must NOT use \"you\" or \"your\"."
        case "reaction_beat":
            return "Must be a standalone interjection, 1-3 words total. Start with one of: Oh, Wow, Yeah, Right, Man, Well. End with punctuation. Nothing else in the sentence."
        case "visual_anchor":
            return "Must be a standalone deictic phrase, 1-4 words total. Start with one of: This, That, These, Those, Here, There. End with punctuation. Nothing else in the sentence."
        case "rhetorical_question":
            return "Must be a question ending with \"?\". Must NOT contain: numbers, year references, contrast words (but/however/yet/actually/though), first person (I/me/my/we), or second person (you/your)."
        case "empty_connector":
            return "Must be a short transitional phrase, 2-4 words. Start with a lowercase letter. No numbers, no personal pronouns, no contrast words."
        case "factual_relay":
            return "Must be a declarative statement ending with a period. At least 5 words, start with an uppercase letter. Must NOT contain: numbers, year references, contrast words (but/however/yet), first person (I/me/my/we), or second person (you/your)."
        default:
            // Unknown slot type — give generic guidance
            return "Write a declarative statement ending with a period."
        }
    }

    /// Builds combined token requirements for a compound signature (e.g. "temporal_marker|direct_address").
    static func combinedTokenRequirements(for signature: String) -> String {
        let slots = signature.split(separator: "|").map(String.init)

        if slots.count == 1 {
            return tokenRequirements(for: slots[0])
        }

        // Union requirements, handling conflicts between positive and negative constraints.
        // For compound signatures, positive requirements win over negative exclusions.
        // E.g. temporal_marker|direct_address: must have a year AND must use "you/your".
        var requirements: [String] = []
        for slot in slots {
            requirements.append("[\(slot)] \(tokenRequirements(for: slot))")
        }
        return "This sentence must satisfy ALL of the following:\n" + requirements.joined(separator: "\n")
    }

    // MARK: - Prompt Builder

    static func buildPrompt(
        position: Int,
        totalPositions: Int,
        slotSignature: String,
        wordCountRange: ClosedRange<Int>,
        sentenceType: String,
        contentTopic: String,
        donorSentence: String,
        previousSentences: [String]
    ) -> (system: String, user: String) {

        let system = """
        You are writing a YouTube script about \(contentTopic). \
        Match the tone and register of the example voice reference — conversational, direct, spoken-word. \
        Output ONLY the single sentence, nothing else. No quotes, no labels, no explanation.
        """

        var userParts: [String] = []

        // Position context
        userParts.append("You are writing sentence \(position + 1) of \(totalPositions) in this script section.")

        // Topic
        userParts.append("Topic: \(contentTopic)")

        // Voice reference
        userParts.append("Voice reference (match this tone, NOT this content): \"\(donorSentence)\"")

        // Token requirements from lookup table
        let reqs = combinedTokenRequirements(for: slotSignature)
        userParts.append("Structural requirements:\n\(reqs)")

        // Word count
        userParts.append("Word count: aim for \(wordCountRange.lowerBound)-\(wordCountRange.upperBound) words.")

        // Sentence type
        switch sentenceType {
        case "question":
            userParts.append("Sentence type: end with a question mark.")
        case "fragment":
            userParts.append("Sentence type: keep it to a short phrase, 2-4 words.")
        default:
            userParts.append("Sentence type: declarative statement, end with a period.")
        }

        // Prior context
        if !previousSentences.isEmpty {
            let context = previousSentences.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            userParts.append("Sentences so far in this section:\n\(context)\n\nWrite the next sentence that continues naturally from these.")
        }

        let user = userParts.joined(separator: "\n\n")
        return (system: system, user: user)
    }

    // MARK: - Run Full Test

    static func runComplianceTest(
        skeleton: [PositionSpec],
        donors: [String],
        contentTopic: String,
        moveType: String?,
        cache: FidelityCorpusCache,
        onProgress: @escaping (Int, Int, String) -> Void
    ) async -> ComplianceTestResult {

        var positionResults: [ComplianceTestResult.PositionResult] = []
        var previousSentences: [String] = []

        for (i, spec) in skeleton.enumerated() {
            let donor = i < donors.count ? donors[i] : ""

            // Word count range: ±3 from skeleton
            let lo = max(1, spec.wordCount - 3)
            let hi = spec.wordCount + 3
            let wordCountRange = lo...hi

            let (system, user) = buildPrompt(
                position: spec.index,
                totalPositions: skeleton.count,
                slotSignature: spec.slotSignature,
                wordCountRange: wordCountRange,
                sentenceType: spec.sentenceType,
                contentTopic: contentTopic,
                donorSentence: donor,
                previousSentences: previousSentences
            )

            await MainActor.run {
                onProgress(i + 1, skeleton.count, "Generating position \(i + 1)/\(skeleton.count)...")
            }

            // Call Claude
            let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
            let bundle = await adapter.generate_response_bundle(
                prompt: user,
                promptBackgroundInfo: system,
                params: ["temperature": 0.4, "max_tokens": 300]
            )

            let rawResponse = bundle?.content ?? ""
            let cleaned = cleanResponse(rawResponse)

            // Parse with the same detectors the scorer uses
            let parsed = ScriptFidelityService.parseSentence(text: cleaned, index: i)
            let actualSignature = ScriptFidelityService.extractSlotSignature(from: parsed)

            let result = ComplianceTestResult.PositionResult(
                index: i,
                targetSignature: spec.slotSignature,
                actualSignature: actualSignature,
                signatureMatch: actualSignature == spec.slotSignature,
                targetWordCount: spec.wordCount,
                actualWordCount: parsed.wordCount,
                generatedText: cleaned,
                donorText: donor,
                prompt: "SYSTEM:\n\(system)\n\nUSER:\n\(user)"
            )
            positionResults.append(result)
            previousSentences.append(cleaned)
        }

        // Score the full section
        let sectionText = previousSentences.joined(separator: " ")
        let weightProfile = FidelityStorage.loadActiveWeightProfile()
            ?? FidelityWeightProfile.equalWeights()

        let sectionFidelity = ScriptFidelityService.evaluateSingleSection(
            sectionText: sectionText,
            moveType: moveType,
            cache: cache,
            weightProfile: weightProfile
        )

        return ComplianceTestResult(
            positions: positionResults,
            sectionFidelity: sectionFidelity,
            generatedSectionText: sectionText,
            moveType: moveType
        )
    }

    // MARK: - Helpers

    /// Strip markdown quotes, backticks, labels, and leading/trailing whitespace from Claude's response.
    static func cleanResponse(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove surrounding quotes
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }

        // Remove backtick wrappers
        if text.hasPrefix("`") && text.hasSuffix("`") {
            text = String(text.dropFirst().dropLast())
        }

        // Remove common labels Claude prepends
        let labelPatterns = [
            #"^(?:Sentence|Output|Here(?:'s| is))[:\s]*"#,
            #"^\d+\.\s*"#
        ]
        for pattern in labelPatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                text = String(text[range.upperBound...])
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Debug Report

    static func formatDebugReport(_ result: ComplianceTestResult) -> String {
        var lines: [String] = []
        lines.append("=== SKELETON COMPLIANCE TEST REPORT ===")
        lines.append("Move Type: \(result.moveType ?? "Unknown")")
        lines.append("Positions: \(result.positions.count)")
        lines.append("Signature Hit Rate: \(String(format: "%.0f", result.signatureHitRate * 100))% (\(result.positions.filter(\.signatureMatch).count)/\(result.positions.count))")
        lines.append("Avg Word Count Delta: \(String(format: "%.1f", result.avgWordCountDelta))")

        if let fidelity = result.sectionFidelity {
            lines.append("Composite Fidelity: \(String(format: "%.1f", fidelity.compositeScore))")
            lines.append("")
            lines.append("--- Dimension Scores ---")
            for (dim, score) in fidelity.dimensionScores.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                lines.append("  \(dim.rawValue): \(String(format: "%.1f", score.score))")
                for sub in score.subMetrics {
                    // WHAT: raw value, WHAT: corpus baseline, WHY: how score was derived
                    lines.append("    \(sub.name): raw=\(String(format: "%.3f", sub.rawValue)) corpus=\(String(format: "%.3f", sub.corpusMean)) score=\(String(format: "%.1f", sub.score))")
                }
            }
        }

        lines.append("")
        lines.append("--- Per-Position Results ---")
        for pos in result.positions {
            let match = pos.signatureMatch ? "MATCH" : "MISS"
            lines.append("")
            lines.append("Position \(pos.index): [\(match)]")
            lines.append("  Target sig: \(pos.targetSignature)")
            lines.append("  Actual sig: \(pos.actualSignature)")
            lines.append("  Target WC: \(pos.targetWordCount)  Actual WC: \(pos.actualWordCount)")
            lines.append("  Generated: \(pos.generatedText)")
            lines.append("  Donor:     \(pos.donorText)")
            // WHY: what requirements were in the prompt
            let reqs = combinedTokenRequirements(for: pos.targetSignature)
            lines.append("  Requirements: \(reqs)")
        }

        lines.append("")
        lines.append("--- Generated Section ---")
        lines.append(result.generatedSectionText)

        lines.append("")
        lines.append("--- Full Prompts ---")
        for pos in result.positions {
            lines.append("")
            lines.append("=== Position \(pos.index) ===")
            lines.append(pos.prompt)
        }

        return lines.joined(separator: "\n")
    }
}
