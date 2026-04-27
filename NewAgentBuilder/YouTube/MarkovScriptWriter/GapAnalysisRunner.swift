//
//  GapAnalysisRunner.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  Execution orchestrator for the 5 gap analysis paths.
//  All paths run in parallel via TaskGroup. Each path is internally sequential.
//  Uses nonisolated static pattern with per-call ClaudeModelAdapter instances.
//

import Foundation

struct GapAnalysisRunner {

    // MARK: - Inputs

    let model: AIModel
    let sourceResult: ArcPathResult
    let creatorProfile: CreatorNarrativeProfile
    let representativeSpines: [NarrativeSpine]
    let transitionMatrix: SpineTransitionMatrix
    let enabledPaths: Set<GapPath>
    let contentInventory: String?

    // MARK: - Progress Callbacks

    var onCallComplete: (@Sendable (GapPath, String) -> Void)?
    var onPathComplete: (@Sendable (GapPath, ArcPathRunStatus) -> Void)?

    // MARK: - Run All Paths

    func run() async -> [GapPathResult] {
        let paths = Array(enabledPaths).filter(\.isPrimary).sorted { $0.rawValue < $1.rawValue }

        guard let spine = sourceResult.outputSpine else {
            return paths.map { path in
                var result = GapPathResult(path: path)
                result.status = .failed
                result.errorMessage = "Source arc result has no parsed spine"
                return result
            }
        }

        // Capture inputs for sendable closures
        let model = self.model
        let profile = self.creatorProfile
        let repSpines = self.representativeSpines
        let matrix = self.transitionMatrix
        let inventory = self.contentInventory
        let callComplete = self.onCallComplete
        let pathComplete = self.onPathComplete

        var results: [GapPathResult] = []

        await withTaskGroup(of: GapPathResult.self) { group in
            for path in paths {
                group.addTask {
                    switch path {
                    case .g1_singleLLM:
                        return await Self.runG1(
                            model: model, spine: spine,
                            profile: profile, contentInventory: inventory,
                            onCallComplete: callComplete
                        )
                    case .g2_programmaticPlusLLM:
                        return await Self.runG2(
                            model: model, spine: spine,
                            profile: profile, matrix: matrix,
                            contentInventory: inventory,
                            onCallComplete: callComplete
                        )
                    case .g3_representativeComparison:
                        return await Self.runG3(
                            model: model, spine: spine,
                            representativeSpines: repSpines,
                            contentInventory: inventory,
                            onCallComplete: callComplete
                        )
                    case .g4_viewerSimulation:
                        return await Self.runG4(
                            model: model, spine: spine,
                            onCallComplete: callComplete
                        )
                    case .g5_combined:
                        return await Self.runG5(
                            model: model, spine: spine,
                            profile: profile, contentInventory: inventory,
                            onCallComplete: callComplete
                        )
                    case .g6_synthesis:
                        // G6 runs post-hoc via runG6(), not in the parallel TaskGroup.
                        // Should never reach here due to isPrimary filter, but exhaustiveness requires it.
                        var skipped = GapPathResult(path: .g6_synthesis)
                        skipped.status = .skipped
                        return skipped
                    }
                }
            }

            for await result in group {
                results.append(result)
                pathComplete?(result.path, result.status)
            }
        }

        return results.sorted { $0.path.rawValue < $1.path.rawValue }
    }

    // MARK: - LLM Call Helper

    private static func makeLLMCall(
        adapter: ClaudeModelAdapter,
        systemPrompt: String,
        userPrompt: String,
        callIndex: Int,
        callLabel: String,
        path: GapPath? = nil,
        onCallComplete: (@Sendable (GapPath, String) -> Void)? = nil
    ) async -> ArcPathCall {
        let start = CFAbsoluteTimeGetCurrent()

        let bundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 8000]
        )

        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let responseText = bundle?.content ?? ""
        let telemetry = bundle.map { SectionTelemetry(from: $0) }

        if let path { onCallComplete?(path, callLabel) }

        return ArcPathCall(
            callIndex: callIndex,
            callLabel: callLabel,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            rawResponse: responseText,
            outputText: responseText,
            telemetry: telemetry,
            durationMs: elapsed
        )
    }

    // MARK: - G1: Single LLM Gap Detection

    nonisolated static func runG1(
        model: AIModel,
        spine: NarrativeSpine,
        profile: CreatorNarrativeProfile,
        contentInventory: String?,
        onCallComplete: (@Sendable (GapPath, String) -> Void)? = nil
    ) async -> GapPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = GapPathResult(path: .g1_singleLLM)
        result.status = .running

        let prompts = GapAnalysisPromptEngine.g1SingleGapDetection(
            spine: spine, profile: profile, contentInventory: contentInventory
        )

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            callIndex: 0,
            callLabel: "Gap Detection",
            path: .g1_singleLLM,
            onCallComplete: onCallComplete
        )
        result.calls.append(call)

        let rawFindings = GapAnalysisPromptEngine.parseGapFindings(from: call.rawResponse)
        result.findings = GapAnalysisPromptEngine.enforceCapLimit(rawFindings)
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - G2: Programmatic + LLM

    nonisolated static func runG2(
        model: AIModel,
        spine: NarrativeSpine,
        profile: CreatorNarrativeProfile,
        matrix: SpineTransitionMatrix,
        contentInventory: String?,
        onCallComplete: (@Sendable (GapPath, String) -> Void)? = nil
    ) async -> GapPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = GapPathResult(path: .g2_programmaticPlusLLM)
        result.status = .running

        // Programmatic pre-pass
        let flags = runG2ProgrammaticPass(
            spine: spine, profile: profile,
            matrix: matrix, contentInventory: contentInventory
        )
        result.intermediateOutputs["programmaticFlags"] = flags.renderedSummary

        let prompts = GapAnalysisPromptEngine.g2LLMWithFlags(
            spine: spine, contentInventory: contentInventory,
            programmaticFlags: flags
        )

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            callIndex: 0,
            callLabel: "LLM Refinement",
            path: .g2_programmaticPlusLLM,
            onCallComplete: onCallComplete
        )
        result.calls.append(call)

        let rawFindings = GapAnalysisPromptEngine.parseGapFindings(from: call.rawResponse)
        result.findings = GapAnalysisPromptEngine.enforceCapLimit(rawFindings)
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - G2 Programmatic Pre-Pass

    static func runG2ProgrammaticPass(
        spine: NarrativeSpine,
        profile: CreatorNarrativeProfile,
        matrix: SpineTransitionMatrix,
        contentInventory: String?
    ) -> ProgrammaticGapFlags {
        let beats = spine.beats.sorted { $0.beatNumber < $1.beatNumber }
        var structuralFlags: [ProgrammaticFlag] = []
        var payoffFlags: [ProgrammaticFlag] = []
        var signatureFlags: [ProgrammaticFlag] = []
        var densityFlags: [ProgrammaticFlag] = []

        // 1. Structural flags: check function vs positional distribution
        let positionalDist = profile.beatDistribution.positionalDistribution
        for (i, beat) in beats.enumerated() {
            let position = i + 1
            if let positionalData = positionalDist.first(where: { $0.beatPosition == position }) {
                let matchingFunction = positionalData.topFunctions.first(where: { $0.functionLabel == beat.function })
                let percent = matchingFunction?.percent ?? 0
                if percent < 5.0 {
                    structuralFlags.append(ProgrammaticFlag(
                        category: "structural",
                        beatIndex: position,
                        description: "Beat \(position) uses '\(beat.function)' which appears at this position in only \(String(format: "%.1f", percent))% of corpus spines. Common functions here: \(positionalData.topFunctions.prefix(3).map { "\($0.functionLabel) (\(String(format: "%.0f", $0.percent))%)" }.joined(separator: ", "))"
                    ))
                }
            }
        }

        // 2. Payoff flags: find unresolved setups
        let setupFunctions: Set<String> = ["setup-plant", "problem-statement", "stakes-raise"]
        let resolutionFunctions: Set<String> = ["resolution", "discovery", "callback", "reframe"]

        for (i, beat) in beats.enumerated() {
            guard setupFunctions.contains(beat.function) else { continue }
            let hasPayoff = beats[(i + 1)...].contains { laterBeat in
                resolutionFunctions.contains(laterBeat.function) &&
                laterBeat.dependsOn.contains(beat.beatNumber)
            }
            if !hasPayoff {
                // Check if any later resolution-type beat exists at all (weaker check)
                let hasAnyResolution = beats[(i + 1)...].contains { resolutionFunctions.contains($0.function) }
                let severity = hasAnyResolution ? "weakly" : "never"
                payoffFlags.append(ProgrammaticFlag(
                    category: "payoff",
                    beatIndex: i + 1,
                    description: "Beat \(i + 1) ('\(beat.function)': \(beat.contentTag)) is \(severity) resolved — no later beat with a resolution-type function explicitly depends on it."
                ))
            }
        }

        // 3. Signature flags: missing high-frequency creator signatures
        let spineSignatureNames = Set(spine.structuralSignatures.map { $0.name.lowercased() })
        for sig in profile.signatureAggregation.clusteredSignatures.prefix(15) {
            guard sig.frequencyPercent > 30 else { continue }
            let sigNameLower = sig.canonicalName.lowercased()
            let isPresent = spineSignatureNames.contains(where: { $0.contains(sigNameLower) || sigNameLower.contains($0) })
            if !isPresent {
                signatureFlags.append(ProgrammaticFlag(
                    category: "signature",
                    description: "Creator signature '\(sig.canonicalName)' appears in \(String(format: "%.0f", sig.frequencyPercent))% of corpus spines but is absent from this spine."
                ))
            }
        }

        // 4. Density flags: keyword overlap between content atoms and beat contentTags
        // Known limitation: keyword overlap is a crude proxy. A beat's contentTag may describe
        // the same concepts as inventory atoms but use completely different words.
        // Acceptable for comparison testing; revisit with semantic similarity if G2 wins.
        if let inventory = contentInventory {
            let atoms = ArcComparisonViewModel.parseContentAtomList(inventory)
            for (i, beat) in beats.enumerated() {
                let tagWords = Set(
                    beat.contentTag.lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count > 3 }
                )
                guard !tagWords.isEmpty else {
                    densityFlags.append(ProgrammaticFlag(
                        category: "density",
                        beatIndex: i + 1,
                        description: "Beat \(i + 1) has an empty or very short contentTag — may lack sufficient content."
                    ))
                    continue
                }

                let matchingAtoms = atoms.filter { atom in
                    let atomWords = Set(
                        atom.lowercased()
                            .components(separatedBy: CharacterSet.alphanumerics.inverted)
                            .filter { $0.count > 3 }
                    )
                    return !tagWords.isDisjoint(with: atomWords)
                }

                if matchingAtoms.isEmpty {
                    densityFlags.append(ProgrammaticFlag(
                        category: "density",
                        beatIndex: i + 1,
                        description: "Beat \(i + 1) ('\(beat.function)') has 0 matching content atoms — potentially sparse. (Note: keyword overlap may miss semantically related content.)"
                    ))
                } else if matchingAtoms.count > 4 {
                    densityFlags.append(ProgrammaticFlag(
                        category: "density",
                        beatIndex: i + 1,
                        description: "Beat \(i + 1) ('\(beat.function)') maps to \(matchingAtoms.count) content atoms — potentially overloaded, consider splitting."
                    ))
                }
            }
        }

        return ProgrammaticGapFlags(
            structuralFlags: structuralFlags,
            payoffFlags: payoffFlags,
            signatureFlags: signatureFlags,
            densityFlags: densityFlags
        )
    }

    // MARK: - G3: Representative Comparison

    nonisolated static func runG3(
        model: AIModel,
        spine: NarrativeSpine,
        representativeSpines: [NarrativeSpine],
        contentInventory: String?,
        onCallComplete: (@Sendable (GapPath, String) -> Void)? = nil
    ) async -> GapPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = GapPathResult(path: .g3_representativeComparison)
        result.status = .running

        let prompts = GapAnalysisPromptEngine.g3RepresentativeComparison(
            spine: spine,
            representativeSpines: representativeSpines,
            contentInventory: contentInventory
        )

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            callIndex: 0,
            callLabel: "Comparative Analysis",
            path: .g3_representativeComparison,
            onCallComplete: onCallComplete
        )
        result.calls.append(call)

        let rawFindings = GapAnalysisPromptEngine.parseGapFindings(from: call.rawResponse)
        result.findings = GapAnalysisPromptEngine.enforceCapLimit(rawFindings)
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - G4: Viewer Simulation

    nonisolated static func runG4(
        model: AIModel,
        spine: NarrativeSpine,
        onCallComplete: (@Sendable (GapPath, String) -> Void)? = nil
    ) async -> GapPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = GapPathResult(path: .g4_viewerSimulation)
        result.status = .running

        let prompts = GapAnalysisPromptEngine.g4ViewerSimulation(spine: spine)

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            callIndex: 0,
            callLabel: "Viewer Simulation",
            path: .g4_viewerSimulation,
            onCallComplete: onCallComplete
        )
        result.calls.append(call)

        let rawFindings = GapAnalysisPromptEngine.parseGapFindings(from: call.rawResponse)
        result.findings = GapAnalysisPromptEngine.enforceCapLimit(rawFindings)
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - G5: Combined (G1 + G4 → Merge)

    nonisolated static func runG5(
        model: AIModel,
        spine: NarrativeSpine,
        profile: CreatorNarrativeProfile,
        contentInventory: String?,
        onCallComplete: (@Sendable (GapPath, String) -> Void)? = nil
    ) async -> GapPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = GapPathResult(path: .g5_combined)
        result.status = .running

        // Call 1: Viewer Simulation (same as G4)
        let viewerPrompts = GapAnalysisPromptEngine.g4ViewerSimulation(spine: spine)
        let viewerCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: viewerPrompts.system,
            userPrompt: viewerPrompts.user,
            callIndex: 0,
            callLabel: "Viewer Simulation",
            path: .g5_combined,
            onCallComplete: onCallComplete
        )
        result.calls.append(viewerCall)
        let viewerFindings = GapAnalysisPromptEngine.parseGapFindings(from: viewerCall.rawResponse)
        result.intermediateOutputs["viewerFindings"] = viewerCall.rawResponse

        // Call 2: Profile Gap Detection (same as G1)
        let profilePrompts = GapAnalysisPromptEngine.g1SingleGapDetection(
            spine: spine, profile: profile, contentInventory: contentInventory
        )
        let profileCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: profilePrompts.system,
            userPrompt: profilePrompts.user,
            callIndex: 1,
            callLabel: "Profile Gap Detection",
            path: .g5_combined,
            onCallComplete: onCallComplete
        )
        result.calls.append(profileCall)
        let profileFindings = GapAnalysisPromptEngine.parseGapFindings(from: profileCall.rawResponse)
        result.intermediateOutputs["profileFindings"] = profileCall.rawResponse

        // Call 3: Merge & Dedup
        let mergePrompts = GapAnalysisPromptEngine.g5MergeDedup(
            viewerFindings: viewerFindings,
            profileFindings: profileFindings
        )
        let mergeCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: mergePrompts.system,
            userPrompt: mergePrompts.user,
            callIndex: 2,
            callLabel: "Merge & Dedup",
            path: .g5_combined,
            onCallComplete: onCallComplete
        )
        result.calls.append(mergeCall)

        let rawFindings = GapAnalysisPromptEngine.parseGapFindings(from: mergeCall.rawResponse)
        result.findings = GapAnalysisPromptEngine.enforceCapLimit(rawFindings)
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - G6: Synthesis (post-hoc, runs after G1-G5)

    nonisolated static func runG6(
        model: AIModel,
        completedResults: [GapPathResult]
    ) async -> GapPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = GapPathResult(path: .g6_synthesis)
        result.status = .running

        // Build input pairs for the prompt
        let pathInputs: [(path: GapPath, findings: [GapFinding])] = completedResults
            .filter { $0.status == .completed && !$0.findings.isEmpty }
            .map { ($0.path, $0.findings) }

        guard pathInputs.count >= 2 else {
            result.status = .skipped
            result.errorMessage = "Need 2+ completed paths with findings to synthesize"
            result.finalize()
            return result
        }

        // Store source findings summary for debug
        let sourceSummary = pathInputs.map { path, findings in
            "\(path.rawValue): \(findings.count) findings (\(findings.filter { $0.priority == .high }.count) HIGH)"
        }.joined(separator: "\n")
        result.intermediateOutputs["sourceFindings"] = sourceSummary

        let prompts = GapAnalysisPromptEngine.g6Synthesis(pathResults: pathInputs)

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            callIndex: 0,
            callLabel: "Synthesis"
        )
        result.calls.append(call)

        let rawFindings = GapAnalysisPromptEngine.parseGapFindings(from: call.rawResponse)
        result.findings = GapAnalysisPromptEngine.enforceCapLimit(rawFindings)
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - Refinement Pass (cross-reference findings against raw rambling)

    /// Takes the best set of findings and cross-references each against the raw rambling.
    /// Returns the same findings with refinement fields populated.
    /// Non-destructive: if parsing fails, returns original findings unchanged.
    nonisolated static func runRefinement(
        model: AIModel,
        findings: [GapFinding],
        rawRambling: String
    ) async -> (findings: [GapFinding], call: ArcPathCall?) {
        guard !findings.isEmpty, !rawRambling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (findings, nil)
        }

        let adapter = ClaudeModelAdapter(model: model)
        let prompts = GapAnalysisPromptEngine.refinementPass(
            findings: findings,
            rawRambling: rawRambling
        )

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            callIndex: 0,
            callLabel: "Refinement"
        )

        let refined = GapAnalysisPromptEngine.parseRefinementResults(
            from: call.rawResponse,
            into: findings
        )

        return (refined, call)
    }
}
