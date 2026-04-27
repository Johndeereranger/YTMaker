//
//  SkeletonS6Runner.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/24/26.
//
//  Adaptive S6 prose generation runner for the Skeleton Lab tab.
//  Takes a SkeletonResult (atom sequence with sentence breaks) and generates
//  prose sentence-by-sentence. After each sentence, detects drift between
//  the planned atom signature and the actual prose output. If drift exceeds
//  a threshold, re-walks the REMAINING skeleton from the actual landing state
//  using the same transition matrix — adapting the plan to match reality.
//
//  The skeleton is the hypothesis. The prose is the experiment.
//  When the experiment contradicts the hypothesis, update the hypothesis.
//
//  Reuses:
//    - StructuredComparisonPromptEngine.buildS5SentencePrompt() for prompts
//    - SkeletonComplianceService.cleanResponse() for output cleaning
//    - ScriptFidelityService.parseSentence() + .extractSlotSignature() for drift detection
//    - SkeletonGeneratorService.applySentenceBreaks() for re-walked sentence breaks
//    - AtomTransitionMatrix.sampleNextWithContext() for re-walking
//

import Foundation

// MARK: - S6 Adaptive Prose Runner

enum SkeletonS6Runner {

    /// Drift detection threshold — minimum atom overlap fraction to consider a match.
    /// Below this, a replan is triggered.
    static let driftThreshold: Double = 0.50

    // MARK: - Result Types

    struct S6ProseResult: Identifiable, Codable {
        let id: UUID
        let skeletonId: UUID
        let skeletonPath: SkeletonPath
        let createdAt: Date

        let finalText: String
        let sentences: [S6SentenceResult]
        let replanEvents: [ReplanEvent]

        let totalPromptTokens: Int
        let totalCompletionTokens: Int
        let totalCost: Double
        let durationMs: Int

        // Original skeleton stats (for comparison)
        let originalAtomCount: Int
        let originalSentenceCount: Int
        // Final realized stats
        let finalAtomCount: Int
        let finalSentenceCount: Int

        var signatureHitRate: Double {
            guard !sentences.isEmpty else { return 0 }
            let hits = sentences.filter(\.signatureMatch).count
            return Double(hits) / Double(sentences.count)
        }

        var replanCount: Int { replanEvents.count }
    }

    struct S6SentenceResult: Identifiable, Codable {
        let id: UUID
        let index: Int
        let targetSignature: String      // what the (possibly re-walked) skeleton planned
        let actualSignature: String      // what the heuristic tagger detected
        let signatureMatch: Bool
        let generatedText: String
        let donorReference: String
        let systemPrompt: String
        let userPrompt: String
        let rawResponse: String
        let promptTokens: Int
        let completionTokens: Int
        let wasReplanned: Bool           // was this sentence's target from a re-walked skeleton?
        let replanEventIndex: Int?       // which ReplanEvent produced this target (nil if original)
    }

    struct ReplanEvent: Identifiable, Codable {
        let id: UUID
        let afterSentenceIndex: Int      // which sentence triggered the replan
        let triggerReason: String        // "drift: overlap 0.31 < threshold 0.50"

        // What the original plan said
        let originalRemainingAtoms: [String]
        let originalRemainingSentenceCount: Int

        // What we landed on
        let actualLastAtom: String       // last atom of the actual prose
        let actualPrevAtom: String?      // second-to-last (for trigram context)

        // What the re-walk produced
        let rewalkedAtoms: [String]
        let rewalkedSentenceBreaks: Set<Int>
        let rewalkedSentenceCount: Int

        let walkTrace: String            // step-by-step re-walk log
    }

    // MARK: - Run

    /// Generate prose from a skeleton result using the S6 adaptive method.
    /// After each sentence, checks for drift. If drift exceeds threshold,
    /// re-walks the remaining skeleton from the actual landing state.
    ///
    /// - Parameters:
    ///   - skeleton: The atom skeleton to realize as prose
    ///   - matrix: Atom transition matrix for re-walking
    ///   - bundle: Pre-assembled structured inputs (donors, rhythm templates, etc.)
    ///   - gists: User's content chunks for topic context
    ///   - seed: RNG seed for reproducible re-walks
    /// - Returns: Full prose result with per-sentence debug and replan events
    static func run(
        skeleton: SkeletonResult,
        matrix: AtomTransitionMatrix,
        bundle: StructuredInputBundle,
        gists: [RamblingGist],
        seed: UInt64 = 42,
        onProgress: (@MainActor (SkeletonLabViewModel.ProseGenerationProgress) -> Void)? = nil
    ) async -> S6ProseResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var rng = SeededRNG(seed: seed)

        // Track remaining sentences as [[String]] — each inner array is one sentence's atom list
        var remainingSentences: [[String]] = skeleton.sentences
        let originalAtomCount = skeleton.atomCount
        let originalSentenceCount = skeleton.sentenceCount

        print("[SkeletonS6Runner] ═══ STARTING S6 ADAPTIVE PROSE GENERATION ═══")
        print("[SkeletonS6Runner] WHAT: skeleton=\(skeleton.path.shortName) atoms=\(originalAtomCount) sentences=\(originalSentenceCount)")
        print("[SkeletonS6Runner] WHAT: drift threshold=\(String(format: "%.2f", driftThreshold))")
        print("[SkeletonS6Runner] WHAT: bundle has \(bundle.donorsByPosition.count) donor positions, \(bundle.rhythmTemplates.count) rhythm templates")
        print("[SkeletonS6Runner] WHAT: \(gists.count) gists for topic context")

        // Fire initial progress
        await onProgress?(SkeletonLabViewModel.ProseGenerationProgress(
            completedSentences: 0,
            totalSentences: originalSentenceCount,
            totalPromptTokens: 0,
            totalCompletionTokens: 0,
            elapsedMs: 0,
            currentPhase: "Starting S6 adaptive generation...",
            replanCount: 0,
            lastSignatureMatch: nil
        ))

        var sentenceResults: [S6SentenceResult] = []
        var previousSentences: [String] = []
        var replanEvents: [ReplanEvent] = []
        var totalPrompt = 0
        var totalCompletion = 0
        var globalSentenceIndex = 0

        // Current bundle — updated after each replan with new targetSignatureSequence
        var currentBundle = bundle

        // Track which replan event (if any) produced the current remaining sentences
        var activeReplanIndex: Int? = nil

        while !remainingSentences.isEmpty {
            let targetSentenceAtoms = remainingSentences[0]
            let targetSig = targetSentenceAtoms.joined(separator: "|")

            // Build prompt using the same engine as S5
            let (system, user) = StructuredComparisonPromptEngine.buildS5SentencePrompt(
                sentenceIndex: globalSentenceIndex,
                bundle: currentBundle,
                matchOpenings: [],
                filteredGists: gists,
                previousSentences: previousSentences
            )

            // Extract donor reference for debug
            var donorRef = ""
            if globalSentenceIndex < currentBundle.donorsByPosition.count,
               let first = currentBundle.donorsByPosition[globalSentenceIndex].matchingSentences.first {
                donorRef = first.rawText
            }

            let wasReplanned = activeReplanIndex != nil

            print("[SkeletonS6Runner] --- Sentence \(globalSentenceIndex + 1) (remaining: \(remainingSentences.count)) ---")
            print("[SkeletonS6Runner] WHAT: targetSig=\"\(targetSig)\"\(wasReplanned ? " [REPLANNED from event #\(activeReplanIndex! + 1)]" : "")")
            print("[SkeletonS6Runner] WHAT: donor=\"\(donorRef.prefix(80))\"")
            print("[SkeletonS6Runner] WHY: token requirements = \(SkeletonComplianceService.combinedTokenRequirements(for: targetSig).prefix(120))")

            // Call Claude
            let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
            let llmBundle = await adapter.generate_response_bundle(
                prompt: user,
                promptBackgroundInfo: system,
                params: ["temperature": 0.4, "max_tokens": 300]
            )

            let rawResponse = llmBundle?.content ?? ""
            let cleaned = SkeletonComplianceService.cleanResponse(rawResponse)

            // Detect what the prose actually produced (FREE — heuristic tagger)
            let parsed = ScriptFidelityService.parseSentence(text: cleaned, index: globalSentenceIndex)
            let actualSig = ScriptFidelityService.extractSlotSignature(from: parsed)
            let strictMatch = actualSig == targetSig

            // Compute drift — atom set overlap fraction (Jaccard-like)
            let targetAtomSet = Set(targetSig.split(separator: "|").map(String.init))
            let actualAtomSet = Set(actualSig.split(separator: "|").map(String.init))
            let unionCount = targetAtomSet.union(actualAtomSet).count
            let overlapCount = targetAtomSet.intersection(actualAtomSet).count
            let overlap = unionCount > 0 ? Double(overlapCount) / Double(unionCount) : 1.0
            let isDrift = overlap < driftThreshold

            let promptTok = llmBundle?.promptTokens ?? 0
            let completionTok = llmBundle?.completionTokens ?? 0
            totalPrompt += promptTok
            totalCompletion += completionTok

            print("[SkeletonS6Runner] WHAT: generated=\"\(cleaned.prefix(100))\"")
            print("[SkeletonS6Runner] WHAT: actualSig=\"\(actualSig)\" strictMatch=\(strictMatch ? "MATCH" : "MISS")")
            print("[SkeletonS6Runner] WHAT: drift overlap=\(String(format: "%.2f", overlap)) threshold=\(String(format: "%.2f", driftThreshold)) isDrift=\(isDrift)")
            print("[SkeletonS6Runner] WHY: target atoms=\(targetAtomSet.sorted()) vs actual atoms=\(actualAtomSet.sorted()) intersection=\(overlapCount) union=\(unionCount)")

            // Record this sentence
            let sentenceResult = S6SentenceResult(
                id: UUID(),
                index: globalSentenceIndex,
                targetSignature: targetSig,
                actualSignature: actualSig,
                signatureMatch: strictMatch,
                generatedText: cleaned,
                donorReference: donorRef,
                systemPrompt: system,
                userPrompt: user,
                rawResponse: rawResponse,
                promptTokens: promptTok,
                completionTokens: completionTok,
                wasReplanned: wasReplanned,
                replanEventIndex: activeReplanIndex
            )
            sentenceResults.append(sentenceResult)
            previousSentences.append(cleaned)

            // Consume the sentence we just generated
            remainingSentences.removeFirst()
            globalSentenceIndex += 1

            // If drift detected AND there are remaining sentences, re-walk
            if isDrift && !remainingSentences.isEmpty {
                let remainingAtomBudget = remainingSentences.flatMap({ $0 }).count
                guard remainingAtomBudget > 0 else {
                    print("[SkeletonS6Runner] WHAT: drift detected but no remaining atom budget — skipping replan")
                    break
                }

                let remainingSentenceTarget = remainingSentences.count

                // Extract actual landing atoms from the prose for trigram context
                let actualAtomList = actualSig.split(separator: "|").map(String.init)
                let lastActualAtom = actualAtomList.last ?? targetSentenceAtoms.last ?? ""
                let prevActualAtom = actualAtomList.count >= 2
                    ? actualAtomList[actualAtomList.count - 2] : nil

                print("[SkeletonS6Runner] ╔═══ REPLAN TRIGGERED (after sentence \(globalSentenceIndex)) ═══╗")
                print("[SkeletonS6Runner] WHAT: original remaining atoms=\(remainingSentences.flatMap({ $0 }))")
                print("[SkeletonS6Runner] WHAT: actual landing state=\(lastActualAtom) prev=\(prevActualAtom ?? "none")")
                print("[SkeletonS6Runner] WHY: overlap \(String(format: "%.2f", overlap)) < threshold \(String(format: "%.2f", driftThreshold)) → re-walk from actual landing")

                // Re-walk remaining atoms from actual landing state
                var rewalkedAtoms: [String] = [lastActualAtom]
                var walkTrace: [String] = ["Step 0: start=\(lastActualAtom) (actual landing from prose)"]

                for step in 1..<remainingAtomBudget {
                    guard let current = rewalkedAtoms.last else { break }
                    let prev = rewalkedAtoms.count >= 2
                        ? rewalkedAtoms[rewalkedAtoms.count - 2]
                        : prevActualAtom

                    guard let sample = matrix.sampleNextWithContext(
                        from: current,
                        context: prev,
                        using: &rng
                    ) else {
                        walkTrace.append("Step \(step): DEAD END from \(current)")
                        break
                    }

                    let source = sample.usedTrigram ? "TRIGRAM" : "BIGRAM"
                    let prob = matrix.probability(from: current, to: sample.atom)
                    rewalkedAtoms.append(sample.atom)
                    walkTrace.append("Step \(step): \(current)->\(sample.atom) [\(source)] p=\(String(format: "%.1f%%", prob * 100)) ctx=\(prev ?? "none")")
                }

                // Apply sentence breaks to re-walked atoms
                let rewalkedBreaks = SkeletonGeneratorService.applySentenceBreaks(
                    atoms: rewalkedAtoms,
                    breakProbs: matrix.breakProbabilities,
                    positionRamp: matrix.positionBreakRamp,
                    targetCount: remainingSentenceTarget,
                    rng: &rng
                )

                // Split re-walked atoms into sentences
                let newRemaining = splitAtoms(rewalkedAtoms, breaks: rewalkedBreaks)
                let rewalkedSentenceCount = newRemaining.count

                print("[SkeletonS6Runner] WHAT: re-walked \(rewalkedAtoms.count) atoms → \(rewalkedSentenceCount) sentences (target was \(remainingSentenceTarget))")
                print("[SkeletonS6Runner] WHAT: re-walked atoms=\(rewalkedAtoms)")
                print("[SkeletonS6Runner] WHAT: re-walked breaks=\(rewalkedBreaks.sorted())")
                for (sIdx, sent) in newRemaining.enumerated() {
                    print("[SkeletonS6Runner] WHAT: re-walked S\(globalSentenceIndex + sIdx + 1): \(sent.joined(separator: "|"))")
                }
                print("[SkeletonS6Runner] ╚═══ REPLAN COMPLETE ═══╝")

                // Record the replan event
                let event = ReplanEvent(
                    id: UUID(),
                    afterSentenceIndex: globalSentenceIndex - 1,
                    triggerReason: "drift: overlap \(String(format: "%.2f", overlap)) < threshold \(String(format: "%.2f", driftThreshold))",
                    originalRemainingAtoms: remainingSentences.flatMap({ $0 }),
                    originalRemainingSentenceCount: remainingSentenceTarget,
                    actualLastAtom: lastActualAtom,
                    actualPrevAtom: prevActualAtom,
                    rewalkedAtoms: rewalkedAtoms,
                    rewalkedSentenceBreaks: rewalkedBreaks,
                    rewalkedSentenceCount: rewalkedSentenceCount,
                    walkTrace: walkTrace.joined(separator: "\n")
                )
                replanEvents.append(event)
                activeReplanIndex = replanEvents.count - 1

                // Replace remaining sentences with re-walked sentences
                remainingSentences = newRemaining

                // Update the bundle's targetSignatureSequence for the prompt engine
                // Sentences already generated keep their original signatures;
                // remaining sentences get the re-walked signatures
                let generatedSigs = sentenceResults.map(\.targetSignature)
                let newRemainingSigs = newRemaining.map { $0.joined(separator: "|") }
                let updatedSignatureSequence = generatedSigs + newRemainingSigs

                currentBundle = StructuredInputBundle(
                    creatorId: bundle.creatorId,
                    fingerprints: bundle.fingerprints,
                    donorsByPosition: bundle.donorsByPosition,
                    sectionProfile: bundle.sectionProfile,
                    rhythmTemplates: bundle.rhythmTemplates,
                    confusableLookup: bundle.confusableLookup,
                    targetMoveType: bundle.targetMoveType,
                    targetPosition: bundle.targetPosition,
                    targetSignatureSequence: updatedSignatureSequence,
                    targetSentenceCount: updatedSignatureSequence.count
                )
            }

            // Report progress after each sentence (and after any replan)
            let elapsedSoFar = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let currentTotal = sentenceResults.count + remainingSentences.count
            let nextPhase: String
            if remainingSentences.isEmpty {
                nextPhase = "Finishing..."
            } else if isDrift && replanEvents.count > 0 {
                nextPhase = "Replanned \u{2192} sentence \(globalSentenceIndex + 1)/\(currentTotal)..."
            } else {
                nextPhase = "Generating sentence \(globalSentenceIndex + 1)/\(currentTotal)..."
            }
            await onProgress?(SkeletonLabViewModel.ProseGenerationProgress(
                completedSentences: sentenceResults.count,
                totalSentences: currentTotal,
                totalPromptTokens: totalPrompt,
                totalCompletionTokens: totalCompletion,
                elapsedMs: elapsedSoFar,
                currentPhase: nextPhase,
                replanCount: replanEvents.count,
                lastSignatureMatch: strictMatch
            ))
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let durationMs = Int(elapsed * 1000)

        // Cost estimate: Claude 4 Sonnet pricing
        let cost = Double(totalPrompt) * 3.0 / 1_000_000 + Double(totalCompletion) * 15.0 / 1_000_000

        let finalText = previousSentences.joined(separator: " ")
        let hits = sentenceResults.filter(\.signatureMatch).count
        let finalAtomCount = sentenceResults.reduce(0) {
            $0 + $1.targetSignature.split(separator: "|").count
        }

        print("[SkeletonS6Runner] ═══ S6 COMPLETE ═══")
        print("[SkeletonS6Runner] WHAT: \(sentenceResults.count) sentences generated in \(durationMs)ms")
        print("[SkeletonS6Runner] WHAT: signature hit rate = \(hits)/\(sentenceResults.count) (\(String(format: "%.0f", Double(hits) / max(Double(sentenceResults.count), 1) * 100))%)")
        print("[SkeletonS6Runner] WHAT: replans = \(replanEvents.count)")
        print("[SkeletonS6Runner] WHAT: tokens = \(totalPrompt) prompt + \(totalCompletion) completion = \(totalPrompt + totalCompletion) total")
        print("[SkeletonS6Runner] WHAT: estimated cost = \(String(format: "$%.4f", cost))")
        print("[SkeletonS6Runner] WHY: original skeleton had \(originalAtomCount) atoms / \(originalSentenceCount) sentences → final realized \(finalAtomCount) atoms / \(sentenceResults.count) sentences")

        return S6ProseResult(
            id: UUID(),
            skeletonId: skeleton.id,
            skeletonPath: skeleton.path,
            createdAt: Date(),
            finalText: finalText,
            sentences: sentenceResults,
            replanEvents: replanEvents,
            totalPromptTokens: totalPrompt,
            totalCompletionTokens: totalCompletion,
            totalCost: cost,
            durationMs: durationMs,
            originalAtomCount: originalAtomCount,
            originalSentenceCount: originalSentenceCount,
            finalAtomCount: finalAtomCount,
            finalSentenceCount: sentenceResults.count
        )
    }

    // MARK: - Helpers

    /// Split a flat atom array into per-sentence groups using break indices.
    private static func splitAtoms(_ atoms: [String], breaks: Set<Int>) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for (i, atom) in atoms.enumerated() {
            if breaks.contains(i) && !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(atom)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Compare Tab Storage Bridge

    /// Convert an S6ProseResult into an OpenerComparisonRun for Compare tab persistence.
    static func wrapAsComparisonRun(_ result: S6ProseResult, moveType: String) -> OpenerComparisonRun {
        let calls: [OpenerMethodCall] = result.sentences.map { sentence in
            let replanTag = sentence.wasReplanned ? " [REPLANNED]" : ""
            return OpenerMethodCall(
                callIndex: sentence.index,
                callLabel: "S6 Sentence \(sentence.index + 1) (sig: \(sentence.targetSignature))\(replanTag)",
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

        // Build intermediates with replan event data
        var intermediates: [String: String] = [:]
        intermediates["skeleton_path"] = result.skeletonPath.displayName
        intermediates["skeleton_id"] = result.skeletonId.uuidString
        intermediates["replan_count"] = "\(result.replanCount)"
        intermediates["original_skeleton"] = "\(result.originalAtomCount) atoms / \(result.originalSentenceCount) sentences"
        intermediates["final_realized"] = "\(result.finalAtomCount) atoms / \(result.finalSentenceCount) sentences"

        // Signature validation
        var sigDebug: [String] = []
        for s in result.sentences {
            let match = s.signatureMatch ? "MATCH" : "MISS"
            let replan = s.wasReplanned ? " [REPLANNED]" : ""
            sigDebug.append("S\(s.index + 1) [\(match)]\(replan) target=\(s.targetSignature) actual=\(s.actualSignature)")
        }
        intermediates["signature_validation"] = sigDebug.joined(separator: "\n")
        intermediates["signature_hit_rate"] = String(format: "%.0f%%", result.signatureHitRate * 100)

        // Replan events
        if !result.replanEvents.isEmpty {
            var replanDebug: [String] = []
            for (idx, event) in result.replanEvents.enumerated() {
                replanDebug.append("REPLAN #\(idx + 1) (after sentence \(event.afterSentenceIndex + 1)):")
                replanDebug.append("  Trigger: \(event.triggerReason)")
                replanDebug.append("  Landing: \(event.actualLastAtom) (prev: \(event.actualPrevAtom ?? "none"))")
                replanDebug.append("  Original remaining: \(event.originalRemainingAtoms.joined(separator: " -> ")) (\(event.originalRemainingSentenceCount) sentences)")
                replanDebug.append("  Re-walked: \(event.rewalkedAtoms.joined(separator: " -> ")) (\(event.rewalkedSentenceCount) sentences)")
            }
            intermediates["replan_events"] = replanDebug.joined(separator: "\n")
        }

        var methodResult = OpenerMethodResult(
            method: .s6_adaptiveSkeleton,
            strategyId: "skeletonLab_\(result.skeletonPath.shortName)_s6",
            runVariantIndex: 0,
            outputText: result.finalText,
            intermediateOutputs: intermediates,
            calls: calls,
            status: .completed
        )
        methodResult.finalize(cost: result.totalCost)

        var strategyRun = OpenerStrategyComparisonRun(
            strategyId: "skeletonLab_\(result.skeletonPath.shortName)_s6",
            strategyName: "Skeleton Lab \(result.skeletonPath.displayName) (S6 Adaptive)"
        )
        strategyRun.methodResults = [methodResult]

        var run = OpenerComparisonRun(
            modelUsed: "claude-4-sonnet",
            enabledMethods: [.s6_adaptiveSkeleton]
        )
        run.strategyRuns = [strategyRun]
        run.finalize()

        return run
    }

    // MARK: - Copy Formatters

    /// Format S6 prose result for clipboard with WHAT/WHAT/WHY debug.
    static func formatForCopy(_ result: S6ProseResult) -> String {
        var lines: [String] = []
        lines.append("=== S6 ADAPTIVE PROSE OUTPUT (from \(result.skeletonPath.shortName): \(result.skeletonPath.displayName)) ===")
        lines.append("Generated: \(result.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Sentences: \(result.sentences.count) | Sig Hit Rate: \(String(format: "%.0f%%", result.signatureHitRate * 100)) | Replans: \(result.replanCount)")
        lines.append("Original: \(result.originalAtomCount) atoms / \(result.originalSentenceCount) sent | Final: \(result.finalAtomCount) atoms / \(result.finalSentenceCount) sent")
        lines.append("Tokens: \(result.totalPromptTokens + result.totalCompletionTokens) | Cost: \(String(format: "$%.4f", result.totalCost)) | Duration: \(result.durationMs)ms")
        lines.append("")
        lines.append("--- Final Text ---")
        lines.append(result.finalText)
        lines.append("")
        lines.append("--- Per-Sentence Breakdown ---")

        for s in result.sentences {
            let match = s.signatureMatch ? "MATCH" : "MISS"
            let replanTag = s.wasReplanned ? " [REPLANNED]" : ""
            lines.append("")
            lines.append("S\(s.index + 1) [\(match)]\(replanTag)")
            lines.append("  WHAT target: \(s.targetSignature)")
            lines.append("  WHAT actual: \(s.actualSignature)")

            // Compute and show drift
            let targetSet = Set(s.targetSignature.split(separator: "|").map(String.init))
            let actualSet = Set(s.actualSignature.split(separator: "|").map(String.init))
            let unionCount = targetSet.union(actualSet).count
            let overlapCount = targetSet.intersection(actualSet).count
            let overlap = unionCount > 0 ? Double(overlapCount) / Double(unionCount) : 1.0
            lines.append("  WHAT drift: overlap \(String(format: "%.2f", overlap))\(overlap < driftThreshold ? " < threshold \(String(format: "%.2f", driftThreshold)) -> REPLAN triggered" : " >= threshold (no replan)")")

            lines.append("  Text: \(s.generatedText)")
            if !s.donorReference.isEmpty {
                lines.append("  Donor: \(s.donorReference)")
            }
            lines.append("  WHY: requirements = \(SkeletonComplianceService.combinedTokenRequirements(for: s.targetSignature).prefix(200))")
            lines.append("  Tokens: \(s.promptTokens) + \(s.completionTokens)")
        }

        // Replan events
        if !result.replanEvents.isEmpty {
            lines.append("")
            lines.append("--- Replan Events ---")
            for (idx, event) in result.replanEvents.enumerated() {
                lines.append("")
                lines.append("REPLAN EVENT #\(idx + 1) (after sentence \(event.afterSentenceIndex + 1)):")
                lines.append("  WHAT: \(event.triggerReason)")
                lines.append("  WHAT: original remaining atoms [\(event.originalRemainingAtoms.joined(separator: ", "))] (\(event.originalRemainingSentenceCount) sentences)")
                lines.append("  WHAT: actual landing state = \(event.actualLastAtom) (prev = \(event.actualPrevAtom ?? "none"))")
                lines.append("  WHAT: re-walked atoms [\(event.rewalkedAtoms.joined(separator: ", "))] (\(event.rewalkedSentenceCount) sentences)")
                lines.append("  WHY: re-walk trace:")
                for traceLine in event.walkTrace.components(separatedBy: .newlines) {
                    lines.append("    \(traceLine)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Format with full prompts for deep debug.
    static func formatForCopyWithPrompts(_ result: S6ProseResult) -> String {
        var lines: [String] = []
        lines.append(formatForCopy(result))
        lines.append("")
        lines.append("--- Full Prompts ---")

        for s in result.sentences {
            lines.append("")
            lines.append("=== Sentence \(s.index + 1)\(s.wasReplanned ? " [REPLANNED]" : "") ===")
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
