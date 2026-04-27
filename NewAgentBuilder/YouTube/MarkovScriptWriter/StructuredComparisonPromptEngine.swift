//
//  StructuredComparisonPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/16/26.
//
//  Prompt builders for S1-S4 structured comparison methods.
//  Each builder takes a fingerprintType parameter — pulling ONLY that one
//  fingerprint's text as the voice constraint. This is what distinguishes
//  each of the 6 variants within an approach.
//

import Foundation

struct StructuredComparisonPromptEngine {

    // MARK: - Shared Prompt Sections

    /// Format the structural spec: target signature sequence, sentence count, rhythm constraints.
    static func buildStructuralSpec(bundle: StructuredInputBundle) -> String {
        var parts: [String] = []
        parts.append("## STRUCTURAL SPECIFICATION")
        parts.append("Target move type: \(bundle.targetMoveType)")
        parts.append("Target position: \(bundle.targetPosition.displayName)")
        parts.append("Target sentence count: \(bundle.targetSentenceCount)")
        parts.append("")

        parts.append("### Sentence-by-Sentence Slot Signatures")
        parts.append("Each sentence should follow the slot pattern below. Slots describe the FUNCTION of each phrase in the sentence.")
        parts.append("")

        for (i, sig) in bundle.targetSignatureSequence.enumerated() {
            let position: String
            if i == 0 { position = "(opening)" }
            else if i == bundle.targetSentenceCount - 1 { position = "(closing)" }
            else { position = "(mid)" }

            // Find rhythm template for this position
            let posLabel = i == 0 ? "opening" : (i == bundle.targetSentenceCount - 1 ? "closing" : "mid")
            let rhythm = bundle.rhythmTemplates.first { $0.positionInSection == posLabel }

            var line = "Sentence \(i + 1) \(position): \(sig)"
            if let r = rhythm {
                line += " | \(r.wordCountMin)-\(r.wordCountMax) words, \(r.clauseCountMin)-\(r.clauseCountMax) clauses"
                if r.sentenceType == "question" { line += " [question]" }
                if r.sentenceType == "fragment" { line += " [fragment]" }
            }
            parts.append(line)
        }

        if let profile = bundle.sectionProfile {
            parts.append("")
            parts.append("### Section Profile")
            parts.append("Typical range: \(profile.minSentences)-\(profile.maxSentences) sentences (median \(String(format: "%.0f", profile.medianSentences)))")
            parts.append("Based on \(profile.totalSections) examples from this creator")
        }

        return parts.joined(separator: "\n")
    }

    /// Format the voice constraint from ONE specific fingerprint type.
    static func buildVoiceConstraints(bundle: StructuredInputBundle, fingerprintType: FingerprintPromptType) -> String {
        guard let doc = bundle.fingerprints[fingerprintType] else {
            return "## VOICE CONSTRAINTS\n[No \(fingerprintType.displayName) fingerprint available for this slot]"
        }

        var parts: [String] = []
        parts.append("## VOICE CONSTRAINTS (\(fingerprintType.displayName) Fingerprint)")
        parts.append("")
        parts.append("The following is a \(fingerprintType.displayName.lowercased()) analysis of how this creator writes \(bundle.targetMoveType) sections at \(bundle.targetPosition.displayName) position.")
        parts.append("Your writing MUST match these voice patterns:")
        parts.append("")
        parts.append(doc.fingerprintText)

        return parts.joined(separator: "\n")
    }

    /// Format donor examples for a specific position, limited to `limit` examples.
    static func buildDonorExamples(bundle: StructuredInputBundle, positionIndex: Int, limit: Int = 3) -> String {
        guard positionIndex < bundle.donorsByPosition.count else { return "" }
        let donorMatch = bundle.donorsByPosition[positionIndex]
        let examples = Array(donorMatch.matchingSentences.prefix(limit))
        guard !examples.isEmpty else { return "" }

        var parts: [String] = []
        parts.append("### Donor Examples for Position \(positionIndex + 1) (signature: \(donorMatch.targetSignature))")

        for (i, sentence) in examples.enumerated() {
            parts.append("Example \(i + 1): \"\(sentence.rawText)\"")
            parts.append("  Signature: \(sentence.slotSignature) | \(sentence.wordCount) words | \(sentence.clauseCount) clauses")
        }

        return parts.joined(separator: "\n")
    }

    /// Format ALL donor examples across all positions (for full-section prompts).
    static func buildAllDonorExamples(bundle: StructuredInputBundle, limit: Int = 3) -> String {
        var parts: [String] = []
        parts.append("## DONOR EXAMPLES")
        parts.append("These are real sentences from this creator that match each target position's slot signature:")
        parts.append("")

        for match in bundle.donorsByPosition {
            let section = buildDonorExamples(bundle: bundle, positionIndex: match.positionIndex, limit: limit)
            if !section.isEmpty {
                parts.append(section)
                parts.append("")
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Shared narrative mode constraints (reuse from M-methods).
    static var sharedConstraints: String {
        [
            OpenerComparisonPromptEngine.NARRATIVE_MODE,
            OpenerComparisonPromptEngine.VERB_CONSTRAINT,
            OpenerComparisonPromptEngine.ACTOR_REQUIREMENT,
            OpenerComparisonPromptEngine.EVIDENCE_MINIMUM,
            OpenerComparisonPromptEngine.TEXTURE_RULES
        ].joined(separator: "\n\n")
    }

    // MARK: - S1: Single-Pass Structured

    static func buildS1Prompt(
        bundle: StructuredInputBundle,
        fingerprintType: FingerprintPromptType,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist]
    ) -> (system: String, user: String) {

        let system = """
        You are a script writer who produces YouTube video openings that match a specific creator's voice.
        You have been given a structural specification, voice constraints from a fingerprint analysis, and donor examples.
        Write EXACTLY \(bundle.targetSentenceCount) sentences. Each sentence must follow its target slot signature pattern.

        \(sharedConstraints)

        \(buildStructuralSpec(bundle: bundle))

        \(buildVoiceConstraints(bundle: bundle, fingerprintType: fingerprintType))
        """

        var userParts: [String] = []

        // Template openings for context
        userParts.append("## TEMPLATE OPENINGS (for reference — match this voice)")
        for opening in matchOpenings {
            userParts.append("### Template: \(opening.title)")
            for section in opening.sectionTexts {
                userParts.append("[\(section.label)] \(section.text)")
            }
            userParts.append("")
        }

        // Donor examples
        userParts.append(buildAllDonorExamples(bundle: bundle))

        // Content to write about
        userParts.append("## CONTENT MATERIAL")
        for (i, gist) in filteredGists.enumerated() {
            userParts.append("### Position \(i + 1) Content:")
            userParts.append(gist.sourceText)
            userParts.append("")
        }

        userParts.append("## WRITE THE OPENING")
        userParts.append("Write exactly \(bundle.targetSentenceCount) sentences. Each sentence must follow its target slot signature.")
        userParts.append("Output ONLY the script text — no labels, no commentary.")

        let user = userParts.joined(separator: "\n")
        return (system, user)
    }

    // MARK: - S2: Sentence-by-Sentence

    static func buildS2SentencePrompt(
        sentenceIndex: Int,
        bundle: StructuredInputBundle,
        fingerprintType: FingerprintPromptType,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist],
        previousSentences: [String]
    ) -> (system: String, user: String) {
        let targetSig = sentenceIndex < bundle.targetSignatureSequence.count
            ? bundle.targetSignatureSequence[sentenceIndex]
            : "narrative_action"

        let posLabel = sentenceIndex == 0 ? "opening"
            : (sentenceIndex == bundle.targetSentenceCount - 1 ? "closing" : "mid")
        let rhythm = bundle.rhythmTemplates.first { $0.positionInSection == posLabel }

        let system = """
        You write ONE sentence at a time for a YouTube video opening, matching a specific creator's voice.
        This is sentence \(sentenceIndex + 1) of \(bundle.targetSentenceCount).

        \(sharedConstraints)

        \(buildVoiceConstraints(bundle: bundle, fingerprintType: fingerprintType))
        """

        var userParts: [String] = []

        // Target for this sentence
        userParts.append("## TARGET FOR THIS SENTENCE")
        userParts.append("Position: \(sentenceIndex + 1) of \(bundle.targetSentenceCount) (\(posLabel))")
        userParts.append("Slot signature: \(targetSig)")
        if let r = rhythm {
            userParts.append("Word count: \(r.wordCountMin)-\(r.wordCountMax)")
            userParts.append("Clause count: \(r.clauseCountMin)-\(r.clauseCountMax)")
            userParts.append("Type: \(r.sentenceType)")
            if !r.commonOpeners.isEmpty {
                userParts.append("Common openers: \(r.commonOpeners.joined(separator: ", "))")
            }
        }
        userParts.append("")

        // Donor examples for this position
        userParts.append(buildDonorExamples(bundle: bundle, positionIndex: sentenceIndex, limit: 5))
        userParts.append("")

        // Previously generated sentences
        if !previousSentences.isEmpty {
            userParts.append("## SENTENCES SO FAR")
            for (i, s) in previousSentences.enumerated() {
                userParts.append("\(i + 1). \(s)")
            }
            userParts.append("")
        }

        // Content to write about
        userParts.append("## CONTENT MATERIAL")
        for gist in filteredGists {
            userParts.append(gist.sourceText)
        }
        userParts.append("")

        userParts.append("Write ONLY sentence \(sentenceIndex + 1). One sentence. Match the slot signature. Output ONLY the sentence text.")

        let user = userParts.joined(separator: "\n")
        return (system, user)
    }

    // MARK: - S5: Skeleton-Driven (Lookup Table)

    /// S5 per-sentence prompt: uses SkeletonComplianceService lookup table to translate
    /// slot signatures into concrete token requirements instead of semantic descriptions.
    static func buildS5SentencePrompt(
        sentenceIndex: Int,
        bundle: StructuredInputBundle,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist],
        previousSentences: [String],
        topicOverride: String? = nil
    ) -> (system: String, user: String) {
        let targetSig = sentenceIndex < bundle.targetSignatureSequence.count
            ? bundle.targetSignatureSequence[sentenceIndex]
            : "narrative_action"

        let posLabel = sentenceIndex == 0 ? "opening"
            : (sentenceIndex == bundle.targetSentenceCount - 1 ? "closing" : "mid")
        let rhythm = bundle.rhythmTemplates.first { $0.positionInSection == posLabel }

        // Topic: prefer explicit override from Skeleton Lab, fall back to gist sourceText
        let topic: String
        if let override = topicOverride, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            topic = override
        } else {
            topic = filteredGists.first?.sourceText ?? "this topic"
        }

        // One donor sentence as voice reference
        var donorSentence = ""
        if sentenceIndex < bundle.donorsByPosition.count,
           let first = bundle.donorsByPosition[sentenceIndex].matchingSentences.first {
            donorSentence = first.rawText
        }

        // Lean system prompt — mirrors SkeletonComplianceService.buildPrompt()
        let system = """
        You are writing a YouTube video opening about \(topic). \
        Match the tone and register of the example voice reference — conversational, direct, spoken-word. \
        Output ONLY the single sentence, nothing else. No quotes, no labels, no explanation.
        """

        var userParts: [String] = []

        // 1. Position
        userParts.append("You are writing sentence \(sentenceIndex + 1) of \(bundle.targetSentenceCount) in this opener.")

        // 2. Topic
        userParts.append("Topic: \(topic)")

        // 3. Voice reference — one donor sentence
        if !donorSentence.isEmpty {
            userParts.append("Voice reference (match this tone, NOT this content): \"\(donorSentence)\"")
        }

        // 4. Token requirements from lookup table
        let reqs = SkeletonComplianceService.combinedTokenRequirements(for: targetSig)
        userParts.append("Structural requirements:\n\(reqs)")

        // 5. Word count — always provide a range
        if let r = rhythm {
            userParts.append("Word count: aim for \(r.wordCountMin)-\(r.wordCountMax) words.")
        } else {
            userParts.append("Word count: aim for 10-20 words.")
        }

        // 6. Sentence type
        let sentenceType = rhythm?.sentenceType ?? "statement"
        switch sentenceType {
        case "question":
            userParts.append("Sentence type: end with a question mark.")
        case "fragment":
            userParts.append("Sentence type: keep it to a short phrase, 2-4 words.")
        default:
            userParts.append("Sentence type: declarative statement, end with a period.")
        }

        // 7. Previous sentences
        if !previousSentences.isEmpty {
            let context = previousSentences.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            userParts.append("Sentences so far in this opener:\n\(context)\n\nWrite the next sentence that continues naturally from these.")
        }

        let user = userParts.joined(separator: "\n\n")
        return (system, user)
    }

    // MARK: - S3: Draft-Then-Fix

    /// S3 Call 1: Generate a full draft using structural spec + fingerprint.
    static func buildS3DraftPrompt(
        bundle: StructuredInputBundle,
        fingerprintType: FingerprintPromptType,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist]
    ) -> (system: String, user: String) {
        // Reuse S1 prompt for the draft call — same inputs, same task
        return buildS1Prompt(
            bundle: bundle,
            fingerprintType: fingerprintType,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
    }

    /// S3 Call 2: Evaluate draft against structural spec, report divergences.
    static func buildS3EvaluatePrompt(
        draftText: String,
        bundle: StructuredInputBundle,
        fingerprintType: FingerprintPromptType
    ) -> (system: String, user: String) {

        let system = """
        You are a structural evaluator for script text. Your job is to compare a draft against a target specification and report SPECIFIC divergences.

        For each sentence in the draft:
        1. Identify what slot signature it actually follows (label each phrase with its slot type)
        2. Compare against the target signature for that position
        3. Check word count against rhythm template
        4. Check voice patterns against the fingerprint constraints

        Report divergences as a numbered list of specific, actionable fixes.
        """

        var userParts: [String] = []

        userParts.append("## TARGET SPECIFICATION")
        userParts.append(buildStructuralSpec(bundle: bundle))
        userParts.append("")

        userParts.append(buildVoiceConstraints(bundle: bundle, fingerprintType: fingerprintType))
        userParts.append("")

        userParts.append("## DRAFT TO EVALUATE")
        userParts.append(draftText)
        userParts.append("")

        // Slot type reference
        userParts.append("## SLOT TYPE REFERENCE")
        userParts.append("Available slot types: \(SlotType.allCases.map(\.rawValue).joined(separator: ", "))")
        userParts.append("")

        userParts.append("## OUTPUT FORMAT")
        userParts.append("For each sentence, output:")
        userParts.append("SENTENCE N: \"[first few words...]\"")
        userParts.append("  Target signature: [expected]")
        userParts.append("  Actual signature: [what you detected]")
        userParts.append("  Word count: [actual] (target: [min]-[max])")
        userParts.append("  Divergences: [specific issues]")
        userParts.append("")
        userParts.append("Then at the end, provide:")
        userParts.append("## FIX PRIORITY LIST")
        userParts.append("Numbered list of the most impactful fixes, from highest priority to lowest.")

        let user = userParts.joined(separator: "\n")
        return (system, user)
    }

    /// S3 Call 3: Fix the draft using evaluation feedback.
    static func buildS3FixPrompt(
        draftText: String,
        evaluationFeedback: String,
        bundle: StructuredInputBundle,
        fingerprintType: FingerprintPromptType,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are a script rewriter. You have a draft, a structural evaluation with specific divergences, and voice constraints.
        Apply the fixes from the evaluation to bring the draft into alignment with the target specification.
        Preserve the content and narrative flow — only change what the evaluation flags as divergent.

        \(sharedConstraints)

        \(buildVoiceConstraints(bundle: bundle, fingerprintType: fingerprintType))
        """

        var userParts: [String] = []

        userParts.append("## ORIGINAL DRAFT")
        userParts.append(draftText)
        userParts.append("")

        userParts.append("## STRUCTURAL EVALUATION & FIX LIST")
        userParts.append(evaluationFeedback)
        userParts.append("")

        userParts.append("## TARGET SPECIFICATION")
        userParts.append(buildStructuralSpec(bundle: bundle))
        userParts.append("")

        // Template openings for voice reference
        userParts.append("## TEMPLATE OPENINGS (voice reference)")
        for opening in matchOpenings {
            userParts.append("### \(opening.title)")
            for section in opening.sectionTexts {
                userParts.append("[\(section.label)] \(section.text)")
            }
        }
        userParts.append("")

        userParts.append("## REWRITE")
        userParts.append("Apply the fixes. Output ONLY the rewritten script text — no commentary, no labels.")

        let user = userParts.joined(separator: "\n")
        return (system, user)
    }

    // MARK: - S4: Spec-First Generation

    /// S4 Call 1: Produce a sentence-by-sentence plan.
    static func buildS4PlanPrompt(
        bundle: StructuredInputBundle,
        fingerprintType: FingerprintPromptType,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist]
    ) -> (system: String, user: String) {

        let system = """
        You are a script planner. Your job is NOT to write the script — it's to create a detailed sentence-by-sentence plan.
        For each sentence, specify:
        1. What slot signature it should follow
        2. What content from the material it should include
        3. What voice pattern from the fingerprint it should use
        4. Specific word count and structural targets

        \(buildStructuralSpec(bundle: bundle))

        \(buildVoiceConstraints(bundle: bundle, fingerprintType: fingerprintType))
        """

        var userParts: [String] = []

        // Content material
        userParts.append("## CONTENT MATERIAL")
        for (i, gist) in filteredGists.enumerated() {
            userParts.append("### Material \(i + 1):")
            userParts.append(gist.sourceText)
            userParts.append("")
        }

        // Template openings for context
        userParts.append("## TEMPLATE OPENINGS (voice reference)")
        for opening in matchOpenings {
            userParts.append("### \(opening.title)")
            for section in opening.sectionTexts {
                userParts.append("[\(section.label)] \(section.text)")
            }
        }
        userParts.append("")

        // Donor examples
        userParts.append(buildAllDonorExamples(bundle: bundle))
        userParts.append("")

        userParts.append("## CREATE THE PLAN")
        userParts.append("For each of the \(bundle.targetSentenceCount) sentences, output:")
        userParts.append("SENTENCE N:")
        userParts.append("  Slot signature: [target signature]")
        userParts.append("  Content: [what from the material to include]")
        userParts.append("  Voice pattern: [specific fingerprint pattern to apply]")
        userParts.append("  Word count target: [min-max]")
        userParts.append("  Opening word/phrase: [suggested opener]")

        let user = userParts.joined(separator: "\n")
        return (system, user)
    }

    /// S4 Call 2: Execute the plan.
    static func buildS4ExecutePrompt(
        plan: String,
        bundle: StructuredInputBundle,
        fingerprintType: FingerprintPromptType,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist]
    ) -> (system: String, user: String) {

        let system = """
        You are a script writer executing a detailed sentence-by-sentence plan.
        Follow the plan EXACTLY — it specifies the slot signature, content, voice pattern, and word count for each sentence.
        Your job is to write natural prose that satisfies every constraint in the plan.

        \(sharedConstraints)

        \(buildVoiceConstraints(bundle: bundle, fingerprintType: fingerprintType))
        """

        var userParts: [String] = []

        userParts.append("## THE PLAN")
        userParts.append(plan)
        userParts.append("")

        // Content material for reference
        userParts.append("## CONTENT MATERIAL")
        for (i, gist) in filteredGists.enumerated() {
            userParts.append("### Material \(i + 1):")
            userParts.append(gist.sourceText)
            userParts.append("")
        }

        // Template openings for voice
        userParts.append("## TEMPLATE OPENINGS (voice reference)")
        for opening in matchOpenings {
            userParts.append("### \(opening.title)")
            for section in opening.sectionTexts {
                userParts.append("[\(section.label)] \(section.text)")
            }
        }
        userParts.append("")

        userParts.append("## EXECUTE THE PLAN")
        userParts.append("Write exactly \(bundle.targetSentenceCount) sentences following the plan above.")
        userParts.append("Output ONLY the script text — no labels, no commentary.")

        let user = userParts.joined(separator: "\n")
        return (system, user)
    }
}
