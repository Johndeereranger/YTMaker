//
//  SkeletonS7Runner.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/24/26.
//
//  S7 phrase-library prose generation runner for the Skeleton Lab tab.
//  Takes a SkeletonResult (atom sequence with sentence breaks) and generates
//  prose sentence-by-sentence, packing a PHRASE LIBRARY into each prompt
//  instead of a single donor voice reference.
//
//  For each sentence, builds sliding n-gram windows (capped at 4-grams)
//  over the atom skeleton and finds all corpus phrases matching each window.
//  This gives the LLM overlapping examples of how real creators combine
//  those exact atom patterns in natural prose.
//
//  Reuses:
//    - SkeletonComplianceService.combinedTokenRequirements() for structural rules
//    - SkeletonComplianceService.cleanResponse() for output cleaning
//    - ScriptFidelityService.parseSentence() + .extractSlotSignature() for validation
//    - StructuredInputAssembler.assemble() for rhythm/word-count loading
//    - OpenerComparisonStorage.save() for Compare tab persistence
//

import Foundation

// MARK: - S7 Phrase-Library Prose Runner

enum SkeletonS7Runner {

    // MARK: - Phrase Library Types

    struct PhraseLibraryEntry {
        let pattern: [String]
        let patternLabel: String
        let ngramSize: Int
        let matches: [PhraseMatch]
    }

    struct PhraseMatch {
        let phraseText: String
        let sentenceText: String
        let videoId: String
    }

    // MARK: - Result Types

    struct S7ProseResult: Identifiable, Codable {
        let id: UUID
        let skeletonId: UUID
        let skeletonPath: SkeletonPath
        let createdAt: Date

        let finalText: String
        let sentences: [S7SentenceResult]

        let totalPromptTokens: Int
        let totalCompletionTokens: Int
        let totalCost: Double
        let durationMs: Int

        var signatureHitRate: Double {
            guard !sentences.isEmpty else { return 0 }
            let hits = sentences.filter(\.signatureMatch).count
            return Double(hits) / Double(sentences.count)
        }
    }

    struct S7SentenceResult: Identifiable, Codable {
        let id: UUID
        let index: Int
        let targetSignature: String
        let actualSignature: String
        let signatureMatch: Bool
        let generatedText: String
        let phraseLibrarySummary: String
        let systemPrompt: String
        let userPrompt: String
        let rawResponse: String
        let promptTokens: Int
        let completionTokens: Int
    }

    // MARK: - Phrase Library Builder

    /// Build a phrase library for a single sentence's atom skeleton.
    /// Generates all contiguous sub-sequences from length min(atomCount, 4) down to 1,
    /// then searches the corpus for matching phrases.
    ///
    /// - Parameters:
    ///   - sentenceAtoms: The atom types for this sentence (e.g. ["actor_reference", "narrative_action", "visual_detail"])
    ///   - corpusSentences: All corpus sentences (with phrases populated)
    ///   - moveType: Filter corpus to this move type
    ///   - maxPerNgram: Cap matches per n-gram pattern (default 8)
    /// - Returns: Phrase library entries sorted by n-gram size descending
    static func buildPhraseLibrary(
        sentenceAtoms: [String],
        corpusSentences: [CreatorSentence],
        moveType: String,
        maxPerNgram: Int = 8
    ) -> [PhraseLibraryEntry] {
        guard !sentenceAtoms.isEmpty else { return [] }

        let moveSentences = corpusSentences.filter { $0.moveType == moveType }
        let maxNgram = min(sentenceAtoms.count, 4)
        var entries: [PhraseLibraryEntry] = []

        // Generate all contiguous sub-sequences from maxNgram down to 1
        for ngramSize in stride(from: maxNgram, through: 1, by: -1) {
            guard sentenceAtoms.count >= ngramSize else { continue }
            let windowCount = sentenceAtoms.count - ngramSize + 1

            for windowStart in 0..<windowCount {
                let pattern = Array(sentenceAtoms[windowStart..<(windowStart + ngramSize)])
                let patternLabel = pattern.joined(separator: " \u{2192} ")

                // Search corpus for this pattern
                var matches: [PhraseMatch] = []

                for sentence in moveSentences {
                    guard matches.count < maxPerNgram else { break }

                    // Try phrase-level matching first (more precise)
                    if let phrases = sentence.phrases, !phrases.isEmpty {
                        let roles = phrases.map(\.role)
                        guard roles.count >= ngramSize else { continue }

                        for start in 0...(roles.count - ngramSize) {
                            let slice = Array(roles[start..<(start + ngramSize)])
                            if slice == pattern {
                                let matchedPhrases = phrases[start..<(start + ngramSize)]
                                let phraseText = matchedPhrases.map(\.text).joined(separator: " ")
                                matches.append(PhraseMatch(
                                    phraseText: phraseText,
                                    sentenceText: sentence.rawText,
                                    videoId: sentence.videoId
                                ))
                                break // One match per sentence
                            }
                        }
                    } else {
                        // Fallback: match on slotSequence, return full sentence text
                        let slots = sentence.slotSequence
                        guard slots.count >= ngramSize else { continue }

                        for start in 0...(slots.count - ngramSize) {
                            let slice = Array(slots[start..<(start + ngramSize)])
                            if slice == pattern {
                                matches.append(PhraseMatch(
                                    phraseText: sentence.rawText,
                                    sentenceText: sentence.rawText,
                                    videoId: sentence.videoId
                                ))
                                break
                            }
                        }
                    }
                }

                if !matches.isEmpty {
                    entries.append(PhraseLibraryEntry(
                        pattern: pattern,
                        patternLabel: patternLabel,
                        ngramSize: ngramSize,
                        matches: matches
                    ))
                }
            }
        }

        return entries
    }

    /// Format a phrase library into a human-readable string for the LLM prompt.
    static func formatPhraseLibraryForPrompt(_ entries: [PhraseLibraryEntry]) -> String {
        guard !entries.isEmpty else { return "No matching phrases found in corpus." }

        var lines: [String] = []
        lines.append("Phrase Library — real examples of these atom combinations:")
        lines.append("")

        for entry in entries {
            let sizeLabel = "\(entry.ngramSize)-gram"
            lines.append("[\(sizeLabel)] \(entry.patternLabel) (\(entry.matches.count) matches):")
            for match in entry.matches {
                lines.append("  - \"\(match.phraseText)\"")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Format a phrase library into a debug summary string (for phraseLibrarySummary field).
    static func formatPhraseLibrarySummary(_ entries: [PhraseLibraryEntry]) -> String {
        var lines: [String] = []
        for entry in entries {
            lines.append("[\(entry.ngramSize)-gram] \(entry.patternLabel): \(entry.matches.count) matches")
            for match in entry.matches {
                lines.append("  \"\(match.phraseText.prefix(80))\"")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - S7 Prompt Builder

    /// Build the system and user prompts for S7 phrase-library generation.
    static func buildS7SentencePrompt(
        sentenceIndex: Int,
        totalSentences: Int,
        targetSignature: String,
        phraseLibrary: [PhraseLibraryEntry],
        bundle: StructuredInputBundle,
        gists: [RamblingGist],
        previousSentences: [String],
        topicOverride: String?
    ) -> (system: String, user: String) {

        // Topic resolution
        let topic: String
        if let override = topicOverride, !override.isEmpty {
            topic = override
        } else if let first = gists.first {
            topic = first.sourceText
        } else {
            topic = "this topic"
        }

        // System prompt
        let system = """
        You are writing a YouTube video opening about \(topic).
        Study the phrase examples below — they show how real creators combine these structural elements.
        Write prose that captures the same natural patterns and tone.
        Output ONLY the single sentence, nothing else. No quotes, no labels, no explanation.
        """

        // User prompt
        var userParts: [String] = []

        // 1. Position context
        userParts.append("You are writing sentence \(sentenceIndex + 1) of \(totalSentences) in this opener.")

        // 2. Topic
        userParts.append("Topic: \(topic)")

        // 3. Phrase library
        userParts.append(formatPhraseLibraryForPrompt(phraseLibrary))

        // 4. Structural requirements
        let requirements = SkeletonComplianceService.combinedTokenRequirements(for: targetSignature)
        userParts.append("Structural requirements:\n\(requirements)")

        // 5. Word count from rhythm templates
        if sentenceIndex < bundle.rhythmTemplates.count {
            let rhythm = bundle.rhythmTemplates[sentenceIndex]
            userParts.append("Word count: aim for \(rhythm.wordCountMin)-\(rhythm.wordCountMax) words.")

            // 6. Sentence type
            if rhythm.sentenceType == "question" {
                userParts.append("Sentence type: question — end with ?")
            } else if rhythm.sentenceType == "fragment" {
                userParts.append("Sentence type: short fragment, 2-4 words.")
            } else {
                userParts.append("Sentence type: declarative statement ending with period.")
            }
        } else {
            userParts.append("Word count: aim for 10-20 words.")
            userParts.append("Sentence type: declarative statement ending with period.")
        }

        // 7. Previous context
        if !previousSentences.isEmpty {
            userParts.append("Sentences so far in this opener:")
            for (i, s) in previousSentences.enumerated() {
                userParts.append("\(i + 1). \(s)")
            }
            userParts.append("Write the next sentence that continues naturally from these.")
        }

        let user = userParts.joined(separator: "\n\n")
        return (system, user)
    }

    // MARK: - Run

    /// Generate prose from a skeleton result using the S7 phrase-library method.
    /// For each sentence, builds a phrase library from sliding n-gram windows
    /// over the atom skeleton, packs it into the prompt, and generates prose.
    ///
    /// - Parameters:
    ///   - skeleton: The atom skeleton to realize as prose
    ///   - bundle: Pre-assembled structured inputs (rhythm templates, word counts)
    ///   - gists: User's content chunks for topic context
    ///   - corpusSentences: Full corpus sentences with phrase annotations
    ///   - moveType: Rhetorical move type to filter corpus
    ///   - topicOverride: Optional explicit topic
    ///   - onProgress: Progress callback for status bar updates
    /// - Returns: Full prose result with per-sentence debug
    static func run(
        skeleton: SkeletonResult,
        bundle: StructuredInputBundle,
        gists: [RamblingGist],
        corpusSentences: [CreatorSentence],
        moveType: String,
        topicOverride: String? = nil,
        onProgress: (@MainActor (SkeletonLabViewModel.ProseGenerationProgress) -> Void)? = nil
    ) async -> S7ProseResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Convert skeleton sentences → signature sequence + atom lists
        let sentenceAtomLists = skeleton.sentences
        let signatureSequence = sentenceAtomLists.map { $0.joined(separator: "|") }

        print("[SkeletonS7Runner] \u{2550}\u{2550}\u{2550} STARTING S7 PHRASE-LIBRARY PROSE GENERATION \u{2550}\u{2550}\u{2550}")
        print("[SkeletonS7Runner] WHAT: skeleton=\(skeleton.path.shortName) atoms=\(skeleton.atomCount) sentences=\(skeleton.sentenceCount)")
        print("[SkeletonS7Runner] WHAT: signatureSequence=\(signatureSequence)")
        print("[SkeletonS7Runner] WHAT: corpus has \(corpusSentences.count) sentences for phrase library")
        print("[SkeletonS7Runner] WHAT: \(gists.count) gists for topic context")

        // Fire initial progress
        await onProgress?(SkeletonLabViewModel.ProseGenerationProgress(
            completedSentences: 0,
            totalSentences: signatureSequence.count,
            totalPromptTokens: 0,
            totalCompletionTokens: 0,
            elapsedMs: 0,
            currentPhase: "Starting S7 phrase-library generation...",
            replanCount: 0,
            lastSignatureMatch: nil
        ))

        var sentenceResults: [S7SentenceResult] = []
        var previousSentences: [String] = []
        var totalPrompt = 0
        var totalCompletion = 0

        for i in 0..<signatureSequence.count {
            let targetSig = signatureSequence[i]
            let sentenceAtoms = sentenceAtomLists[i]

            // Build phrase library for this sentence's atoms
            let phraseLibrary = buildPhraseLibrary(
                sentenceAtoms: sentenceAtoms,
                corpusSentences: corpusSentences,
                moveType: moveType
            )

            let librarySummary = formatPhraseLibrarySummary(phraseLibrary)
            let totalMatches = phraseLibrary.reduce(0) { $0 + $1.matches.count }

            // Build S7 prompt
            let (system, user) = buildS7SentencePrompt(
                sentenceIndex: i,
                totalSentences: signatureSequence.count,
                targetSignature: targetSig,
                phraseLibrary: phraseLibrary,
                bundle: bundle,
                gists: gists,
                previousSentences: previousSentences,
                topicOverride: topicOverride
            )

            print("[SkeletonS7Runner] --- Sentence \(i + 1)/\(signatureSequence.count) ---")
            print("[SkeletonS7Runner] WHAT: targetSig=\"\(targetSig)\"")
            print("[SkeletonS7Runner] WHAT: phrase library has \(phraseLibrary.count) n-gram entries, \(totalMatches) total matches")
            for entry in phraseLibrary {
                print("[SkeletonS7Runner] WHAT: [\(entry.ngramSize)-gram] \(entry.patternLabel): \(entry.matches.count) matches")
            }
            print("[SkeletonS7Runner] WHY: token requirements = \(SkeletonComplianceService.combinedTokenRequirements(for: targetSig).prefix(120))")

            // Call Claude
            let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
            let llmBundle = await adapter.generate_response_bundle(
                prompt: user,
                promptBackgroundInfo: system,
                params: ["temperature": 0.4, "max_tokens": 300]
            )

            let rawResponse = llmBundle?.content ?? ""
            let cleaned = SkeletonComplianceService.cleanResponse(rawResponse)

            // Validate with fidelity detectors
            let parsed = ScriptFidelityService.parseSentence(text: cleaned, index: i)
            let actualSig = ScriptFidelityService.extractSlotSignature(from: parsed)
            let match = actualSig == targetSig

            let promptTok = llmBundle?.promptTokens ?? 0
            let completionTok = llmBundle?.completionTokens ?? 0
            totalPrompt += promptTok
            totalCompletion += completionTok

            print("[SkeletonS7Runner] WHAT: generated=\"\(cleaned.prefix(100))\"")
            print("[SkeletonS7Runner] WHAT: actualSig=\"\(actualSig)\" match=\(match ? "MATCH" : "MISS")")
            print("[SkeletonS7Runner] WHY: target atoms=[\(targetSig)] vs detected atoms=[\(actualSig)]")

            let sentenceResult = S7SentenceResult(
                id: UUID(),
                index: i,
                targetSignature: targetSig,
                actualSignature: actualSig,
                signatureMatch: match,
                generatedText: cleaned,
                phraseLibrarySummary: librarySummary,
                systemPrompt: system,
                userPrompt: user,
                rawResponse: rawResponse,
                promptTokens: promptTok,
                completionTokens: completionTok
            )
            sentenceResults.append(sentenceResult)
            previousSentences.append(cleaned)

            // Report progress after each sentence
            let elapsedSoFar = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let nextPhase = (i + 1 < signatureSequence.count)
                ? "Generating sentence \(i + 2)/\(signatureSequence.count)..."
                : "Finishing..."
            await onProgress?(SkeletonLabViewModel.ProseGenerationProgress(
                completedSentences: i + 1,
                totalSentences: signatureSequence.count,
                totalPromptTokens: totalPrompt,
                totalCompletionTokens: totalCompletion,
                elapsedMs: elapsedSoFar,
                currentPhase: nextPhase,
                replanCount: 0,
                lastSignatureMatch: match
            ))
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let durationMs = Int(elapsed * 1000)

        // Cost estimate: Claude 4 Sonnet pricing
        let cost = Double(totalPrompt) * 3.0 / 1_000_000 + Double(totalCompletion) * 15.0 / 1_000_000

        let finalText = previousSentences.joined(separator: " ")
        let hits = sentenceResults.filter(\.signatureMatch).count

        print("[SkeletonS7Runner] \u{2550}\u{2550}\u{2550} S7 COMPLETE \u{2550}\u{2550}\u{2550}")
        print("[SkeletonS7Runner] WHAT: \(sentenceResults.count) sentences generated in \(durationMs)ms")
        print("[SkeletonS7Runner] WHAT: signature hit rate = \(hits)/\(sentenceResults.count) (\(String(format: "%.0f", Double(hits) / max(Double(sentenceResults.count), 1) * 100))%)")
        print("[SkeletonS7Runner] WHAT: tokens = \(totalPrompt) prompt + \(totalCompletion) completion = \(totalPrompt + totalCompletion) total")
        print("[SkeletonS7Runner] WHAT: estimated cost = \(String(format: "$%.4f", cost))")

        return S7ProseResult(
            id: UUID(),
            skeletonId: skeleton.id,
            skeletonPath: skeleton.path,
            createdAt: Date(),
            finalText: finalText,
            sentences: sentenceResults,
            totalPromptTokens: totalPrompt,
            totalCompletionTokens: totalCompletion,
            totalCost: cost,
            durationMs: durationMs
        )
    }

    // MARK: - Compare Tab Storage Bridge

    /// Convert an S7ProseResult into an OpenerComparisonRun for Compare tab persistence.
    static func wrapAsComparisonRun(_ result: S7ProseResult, moveType: String) -> OpenerComparisonRun {
        let calls: [OpenerMethodCall] = result.sentences.map { sentence in
            OpenerMethodCall(
                callIndex: sentence.index,
                callLabel: "S7 Sentence \(sentence.index + 1) (sig: \(sentence.targetSignature))",
                systemPrompt: sentence.systemPrompt,
                userPrompt: sentence.userPrompt,
                rawResponse: sentence.rawResponse,
                outputText: sentence.generatedText,
                telemetry: SectionTelemetry(
                    promptTokens: sentence.promptTokens,
                    completionTokens: sentence.completionTokens,
                    totalTokens: sentence.promptTokens + sentence.completionTokens,
                    modelUsed: "claude-4-sonnet"
                ),
                durationMs: result.durationMs / max(result.sentences.count, 1)
            )
        }

        var intermediates: [String: String] = [:]
        intermediates["skeleton_path"] = result.skeletonPath.displayName
        intermediates["skeleton_id"] = result.skeletonId.uuidString
        intermediates["method"] = "S7 Phrase-Library"

        var sigDebug: [String] = []
        for s in result.sentences {
            let match = s.signatureMatch ? "MATCH" : "MISS"
            sigDebug.append("S\(s.index + 1) [\(match)] target=\(s.targetSignature) actual=\(s.actualSignature)")
        }
        intermediates["signature_validation"] = sigDebug.joined(separator: "\n")
        intermediates["signature_hit_rate"] = String(format: "%.0f%%", result.signatureHitRate * 100)

        // Include phrase library summaries
        var libDebug: [String] = []
        for s in result.sentences {
            libDebug.append("S\(s.index + 1) phrase library:")
            libDebug.append(s.phraseLibrarySummary)
            libDebug.append("")
        }
        intermediates["phrase_libraries"] = libDebug.joined(separator: "\n")

        var methodResult = OpenerMethodResult(
            method: .s7_phraseLibrary,
            strategyId: "skeletonLab_S7_\(result.skeletonPath.shortName)",
            runVariantIndex: 0,
            outputText: result.finalText,
            intermediateOutputs: intermediates,
            calls: calls,
            status: .completed
        )
        methodResult.finalize(cost: result.totalCost)

        var strategyRun = OpenerStrategyComparisonRun(
            strategyId: "skeletonLab_S7_\(result.skeletonPath.shortName)",
            strategyName: "Skeleton Lab S7 \(result.skeletonPath.displayName)"
        )
        strategyRun.methodResults = [methodResult]

        var run = OpenerComparisonRun(
            modelUsed: "claude-4-sonnet",
            enabledMethods: [.s7_phraseLibrary]
        )
        run.strategyRuns = [strategyRun]
        run.finalize()

        return run
    }

    // MARK: - Copy Formatters

    /// Format S7 prose result for clipboard with WHAT/WHAT/WHY debug.
    static func formatForCopy(_ result: S7ProseResult) -> String {
        var lines: [String] = []
        lines.append("=== S7 PHRASE-LIBRARY PROSE OUTPUT (from \(result.skeletonPath.shortName): \(result.skeletonPath.displayName)) ===")
        lines.append("Generated: \(result.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Sentences: \(result.sentences.count) | Sig Hit Rate: \(String(format: "%.0f%%", result.signatureHitRate * 100))")
        lines.append("Tokens: \(result.totalPromptTokens + result.totalCompletionTokens) | Cost: \(String(format: "$%.4f", result.totalCost)) | Duration: \(result.durationMs)ms")
        lines.append("")
        lines.append("--- Final Text ---")
        lines.append(result.finalText)
        lines.append("")
        lines.append("--- Per-Sentence Breakdown ---")

        for s in result.sentences {
            let match = s.signatureMatch ? "MATCH" : "MISS"
            lines.append("")
            lines.append("S\(s.index + 1) [\(match)]")
            lines.append("  WHAT target: \(s.targetSignature)")
            lines.append("  WHAT actual: \(s.actualSignature)")
            lines.append("  Text: \(s.generatedText)")
            lines.append("  WHY: requirements = \(SkeletonComplianceService.combinedTokenRequirements(for: s.targetSignature).prefix(200))")
            lines.append("  Tokens: \(s.promptTokens) + \(s.completionTokens)")
            lines.append("  Phrase Library:")
            for line in s.phraseLibrarySummary.components(separatedBy: .newlines) {
                lines.append("    \(line)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Format with full prompts for deep debug.
    static func formatForCopyWithPrompts(_ result: S7ProseResult) -> String {
        var lines: [String] = []
        lines.append(formatForCopy(result))
        lines.append("")
        lines.append("--- Full Prompts ---")

        for s in result.sentences {
            lines.append("")
            lines.append("=== Sentence \(s.index + 1) ===")
            lines.append("SYSTEM:")
            lines.append(s.systemPrompt)
            lines.append("")
            lines.append("USER:")
            lines.append(s.userPrompt)
            lines.append("")
            lines.append("RAW RESPONSE:")
            lines.append(s.rawResponse)
        }

        return lines.joined(separator: "\n")
    }
}
