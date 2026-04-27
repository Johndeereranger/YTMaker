//
//  ScriptTraceW4Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation

// MARK: - W4: Three-Tier Adaptation Service

/// Adapts donor sentences to carry new content payloads.
/// Tier 1: full donor adaptation (70-80%). Tier 2: sub-decompose (15-20%). Tier 3: rhythm gen (5-10%).
class ScriptTraceW4Service {
    private let adapter = ClaudeModelAdapter(model: .claude35Sonnet)

    // MARK: - Adaptation Result

    struct AdaptationResult {
        let adaptedText: String
        let tier: AdaptationTier
        let diffSummary: String
    }

    // MARK: - Adapt Beat

    /// Determine tier and adapt the content payload using the donor sentence.
    func adaptBeat(
        payloadText: String,
        donorSentence: CreatorSentence?,
        donorMatchScore: Double,
        targetSignature: String?,
        rhythmTemplates: [RhythmTemplate],
        moveType: String,
        exampleSentences: [CreatorSentence]
    ) async -> AdaptationResult {
        // Determine tier
        if let donor = donorSentence, donorMatchScore > 0.5 {
            // Tier 1: good donor match
            let adapted = await tier1Adapt(payloadText: payloadText, donor: donor)
            return AdaptationResult(
                adaptedText: adapted,
                tier: .tier1,
                diffSummary: "Swapped content into donor structure"
            )
        } else if let donor = donorSentence {
            // Tier 2: donor exists but weak match
            let adapted = await tier2Adapt(payloadText: payloadText, donor: donor)
            return AdaptationResult(
                adaptedText: adapted,
                tier: .tier2,
                diffSummary: "Restructured donor for payload compatibility"
            )
        } else {
            // Tier 3: no donor — rhythm-constrained generation
            let template = rhythmTemplates.first { $0.moveType == moveType }
            let examples = exampleSentences.prefix(3).map { $0.rawText }
            let generated = await tier3Generate(
                payloadText: payloadText,
                template: template,
                examples: Array(examples)
            )
            return AdaptationResult(
                adaptedText: generated,
                tier: .tier3,
                diffSummary: "Generated from rhythm template constraints"
            )
        }
    }

    // MARK: - Tier 1: Full Donor Adaptation (Prompt 7.3)

    private func tier1Adapt(payloadText: String, donor: CreatorSentence) async -> String {
        let systemPrompt = """
        You adapt real creator sentences to carry new content.
        Preserve structure. Swap content. Do NOT write new sentences.
        """

        let userPrompt = """
        DONOR: "\(donor.rawText)"
        CONTENT PAYLOAD: \(payloadText)

        RULES:
        - Preserve length \u{00B1}2 words
        - Preserve syntactic structure
        - Preserve direct address style
        - Preserve concrete/abstract ratio
        - No added commentary
        - No added transitions
        - No statement<->question flip

        Output ONLY the adapted sentence.
        """

        return await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 500]
        )
    }

    // MARK: - Tier 2: Sub-Decomposition Adaptation (Prompt 7.4)

    private func tier2Adapt(payloadText: String, donor: CreatorSentence) async -> String {
        let userPrompt = """
        The payload couldn't perfectly fit the donor sentence structure.

        DONOR: "\(donor.rawText)"
        PAYLOAD: "\(payloadText)"
        DONOR SIGNATURE: \(donor.slotSignature)

        Adapt the donor sentence to carry the payload content.
        You have more structural freedom than Tier 1 — you can adjust clause structure,
        but maintain the creator's voice patterns (openers, rhythm, phrasing style).

        Output ONLY the adapted sentence.
        """

        return await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: "You adapt creator sentences to carry new content while preserving voice.",
            params: ["temperature": 0.4, "max_tokens": 500]
        )
    }

    // MARK: - Tier 3: Rhythm-Constrained Generation (Prompt 7.5)

    private func tier3Generate(
        payloadText: String,
        template: RhythmTemplate?,
        examples: [String]
    ) async -> String {
        let constraintText: String
        if let t = template {
            constraintText = """
            Words: \(t.wordCountMin)-\(t.wordCountMax)
            Clauses: \(t.clauseCountMin)-\(t.clauseCountMax)
            Type: \(t.sentenceType)
            Opener style: \(t.commonOpeners.joined(separator: ", "))
            """
        } else {
            constraintText = "Words: 10-25, Clauses: 1-3, Type: statement"
        }

        let exampleText = examples.enumerated().map { idx, ex in
            "\(idx + 1). \"\(ex)\""
        }.joined(separator: "\n")

        let userPrompt = """
        PAYLOAD: \(payloadText)

        CONSTRAINTS:
        \(constraintText)

        CREATOR EXAMPLES (match this voice):
        \(exampleText)

        Write ONE sentence within constraints that carries the payload content.
        Match the voice/style of the examples.
        Output ONLY the sentence.
        """

        return await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: "You generate sentences in a creator's voice using rhythm constraints.",
            params: ["temperature": 0.5, "max_tokens": 300]
        )
    }
}
