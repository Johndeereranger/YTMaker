//
//  SkeletonS5Runner.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/24/26.
//
//  Lightweight S5-only prose generation runner for the Skeleton Lab tab.
//  Takes a SkeletonResult (atom sequence with sentence breaks) and generates
//  actual prose sentence-by-sentence using the same prompt engine as the
//  Compare tab's S5 method, but runs only 1 variant instead of 3.
//
//  Reuses:
//    - StructuredComparisonPromptEngine.buildS5SentencePrompt() for prompts
//    - SkeletonComplianceService.cleanResponse() for output cleaning
//    - ScriptFidelityService.parseSentence() + .extractSlotSignature() for validation
//    - StructuredInputAssembler.assemble() for donor/rhythm loading
//    - OpenerComparisonStorage.save() for Compare tab persistence
//

import Foundation

// MARK: - S5 Prose Runner

enum SkeletonS5Runner {

    // MARK: - Result Types

    struct S5ProseResult: Identifiable, Codable {
        let id: UUID
        let skeletonId: UUID
        let skeletonPath: SkeletonPath
        let createdAt: Date

        let finalText: String
        let sentences: [S5SentenceResult]

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

    struct S5SentenceResult: Identifiable, Codable {
        let id: UUID
        let index: Int
        let targetSignature: String
        let actualSignature: String
        let signatureMatch: Bool
        let generatedText: String
        let donorReference: String
        let systemPrompt: String
        let userPrompt: String
        let rawResponse: String
        let promptTokens: Int
        let completionTokens: Int
    }

    // MARK: - Run

    /// Generate prose from a skeleton result using the S5 sentence-by-sentence method.
    ///
    /// - Parameters:
    ///   - skeleton: The atom skeleton to realize as prose
    ///   - bundle: Pre-assembled structured inputs (donors, rhythm templates, etc.)
    ///   - gists: User's content chunks for topic context
    /// - Returns: Full prose result with per-sentence debug
    static func run(
        skeleton: SkeletonResult,
        bundle: StructuredInputBundle,
        gists: [RamblingGist],
        topicOverride: String? = nil,
        onProgress: (@MainActor (SkeletonLabViewModel.ProseGenerationProgress) -> Void)? = nil
    ) async -> S5ProseResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Convert skeleton sentences → signature sequence
        // Each sentence's atoms joined with "|" gives the target slot signature
        let signatureSequence = skeleton.sentences.map { $0.joined(separator: "|") }

        print("[SkeletonS5Runner] ═══ STARTING S5 PROSE GENERATION ═══")
        print("[SkeletonS5Runner] WHAT: skeleton=\(skeleton.path.shortName) atoms=\(skeleton.atomCount) sentences=\(skeleton.sentenceCount)")
        print("[SkeletonS5Runner] WHAT: signatureSequence=\(signatureSequence)")
        print("[SkeletonS5Runner] WHAT: bundle has \(bundle.donorsByPosition.count) donor positions, \(bundle.rhythmTemplates.count) rhythm templates")
        print("[SkeletonS5Runner] WHAT: \(gists.count) gists for topic context")

        // Fire initial progress
        await onProgress?(SkeletonLabViewModel.ProseGenerationProgress(
            completedSentences: 0,
            totalSentences: signatureSequence.count,
            totalPromptTokens: 0,
            totalCompletionTokens: 0,
            elapsedMs: 0,
            currentPhase: "Starting S5 generation...",
            replanCount: 0,
            lastSignatureMatch: nil
        ))

        var sentenceResults: [S5SentenceResult] = []
        var previousSentences: [String] = []
        var totalPrompt = 0
        var totalCompletion = 0

        for i in 0..<signatureSequence.count {
            let targetSig = signatureSequence[i]

            // Build prompt using the same engine as Compare tab S5
            let (system, user) = StructuredComparisonPromptEngine.buildS5SentencePrompt(
                sentenceIndex: i,
                bundle: bundle,
                matchOpenings: [],
                filteredGists: gists,
                previousSentences: previousSentences,
                topicOverride: topicOverride
            )

            // Extract donor reference for debug logging
            var donorRef = ""
            if i < bundle.donorsByPosition.count,
               let first = bundle.donorsByPosition[i].matchingSentences.first {
                donorRef = first.rawText
            }

            print("[SkeletonS5Runner] --- Sentence \(i + 1)/\(signatureSequence.count) ---")
            print("[SkeletonS5Runner] WHAT: targetSig=\"\(targetSig)\"")
            print("[SkeletonS5Runner] WHAT: donor=\"\(donorRef.prefix(80))\"")
            print("[SkeletonS5Runner] WHY: token requirements = \(SkeletonComplianceService.combinedTokenRequirements(for: targetSig).prefix(120))")

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

            print("[SkeletonS5Runner] WHAT: generated=\"\(cleaned.prefix(100))\"")
            print("[SkeletonS5Runner] WHAT: actualSig=\"\(actualSig)\" match=\(match ? "MATCH" : "MISS")")
            print("[SkeletonS5Runner] WHY: target atoms=[\(targetSig)] vs detected atoms=[\(actualSig)]")

            let sentenceResult = S5SentenceResult(
                id: UUID(),
                index: i,
                targetSignature: targetSig,
                actualSignature: actualSig,
                signatureMatch: match,
                generatedText: cleaned,
                donorReference: donorRef,
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

        print("[SkeletonS5Runner] ═══ S5 COMPLETE ═══")
        print("[SkeletonS5Runner] WHAT: \(sentenceResults.count) sentences generated in \(durationMs)ms")
        print("[SkeletonS5Runner] WHAT: signature hit rate = \(hits)/\(sentenceResults.count) (\(String(format: "%.0f", Double(hits) / max(Double(sentenceResults.count), 1) * 100))%)")
        print("[SkeletonS5Runner] WHAT: tokens = \(totalPrompt) prompt + \(totalCompletion) completion = \(totalPrompt + totalCompletion) total")
        print("[SkeletonS5Runner] WHAT: estimated cost = \(String(format: "$%.4f", cost))")

        return S5ProseResult(
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

    /// Convert an S5ProseResult into an OpenerComparisonRun for Compare tab persistence.
    /// The run appears in Compare's file-based history automatically.
    static func wrapAsComparisonRun(_ result: S5ProseResult, moveType: String) -> OpenerComparisonRun {
        // Build OpenerMethodCalls from sentence results
        let calls: [OpenerMethodCall] = result.sentences.map { sentence in
            OpenerMethodCall(
                callIndex: sentence.index,
                callLabel: "S5 Sentence \(sentence.index + 1) (sig: \(sentence.targetSignature))",
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

        // Build intermediates with per-sentence WHAT/WHAT/WHY debug
        var intermediates: [String: String] = [:]
        intermediates["skeleton_path"] = result.skeletonPath.displayName
        intermediates["skeleton_id"] = result.skeletonId.uuidString

        var sigDebug: [String] = []
        for s in result.sentences {
            let match = s.signatureMatch ? "MATCH" : "MISS"
            sigDebug.append("S\(s.index + 1) [\(match)] target=\(s.targetSignature) actual=\(s.actualSignature)")
        }
        intermediates["signature_validation"] = sigDebug.joined(separator: "\n")
        intermediates["signature_hit_rate"] = String(format: "%.0f%%", result.signatureHitRate * 100)

        // Build the method result
        var methodResult = OpenerMethodResult(
            method: .s5_skeletonDriven,
            strategyId: "skeletonLab_\(result.skeletonPath.shortName)",
            runVariantIndex: 0,
            outputText: result.finalText,
            intermediateOutputs: intermediates,
            calls: calls,
            status: .completed
        )
        methodResult.finalize(cost: result.totalCost)

        // Wrap in strategy run
        var strategyRun = OpenerStrategyComparisonRun(
            strategyId: "skeletonLab_\(result.skeletonPath.shortName)",
            strategyName: "Skeleton Lab \(result.skeletonPath.displayName)"
        )
        strategyRun.methodResults = [methodResult]

        // Build the comparison run
        var run = OpenerComparisonRun(
            modelUsed: "claude-4-sonnet",
            enabledMethods: [.s5_skeletonDriven]
        )
        run.strategyRuns = [strategyRun]
        run.finalize()

        return run
    }

    // MARK: - Copy Formatter

    /// Format S5 prose result for clipboard with WHAT/WHAT/WHY debug.
    static func formatForCopy(_ result: S5ProseResult) -> String {
        var lines: [String] = []
        lines.append("=== S5 PROSE OUTPUT (from \(result.skeletonPath.shortName): \(result.skeletonPath.displayName)) ===")
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
            if !s.donorReference.isEmpty {
                lines.append("  Donor: \(s.donorReference)")
            }
            lines.append("  WHY: requirements = \(SkeletonComplianceService.combinedTokenRequirements(for: s.targetSignature).prefix(200))")
            lines.append("  Tokens: \(s.promptTokens) + \(s.completionTokens)")
        }

        return lines.joined(separator: "\n")
    }

    /// Format with full prompts for deep debug.
    static func formatForCopyWithPrompts(_ result: S5ProseResult) -> String {
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
