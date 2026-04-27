//
//  SynthesisService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  Two-pass synthesis orchestration:
//  Pass 1: Sequential section-by-section synthesis
//  Pass 2: Transition smoothing across seams
//

import Foundation

struct SynthesisService {

    // MARK: - Main Entry Point

    static func synthesize(
        chain: ChainAttempt,
        gists: [RamblingGist],
        retriever: CorpusRetriever,
        onSectionComplete: @escaping @Sendable (Int, SynthesisSection) -> Void
    ) async throws -> SynthesizedScript {

        let moveSequence = chain.positions.map(\.moveType)
        var script = SynthesizedScript(
            chainAttemptId: chain.id,
            moveSequence: moveSequence
        )

        // --- Pass 1: Section-by-section synthesis ---
        let pass1Result = await runPass1(
            chain: chain,
            gists: gists,
            retriever: retriever,
            onSectionComplete: onSectionComplete
        )
        script.sections = pass1Result.sections
        script.pass1Telemetry = pass1Result.telemetry

        // Build concatenated draft for comparison
        script.pass1ConcatenatedDraft = pass1Result.sections
            .map(\.writtenText)
            .joined(separator: "\n\n")

        // --- Pass 2: Transition smoothing ---
        let pass2Result = await runPass2(
            sections: pass1Result.sections,
            moveSequence: moveSequence,
            retriever: retriever
        )
        script.smoothedScript = pass2Result.smoothedScript
        script.pass2PromptSent = pass2Result.promptSent
        script.pass2SystemPromptSent = pass2Result.systemPromptSent
        script.pass2RawResponse = pass2Result.rawResponse
        script.pass2Telemetry = pass2Result.telemetry

        return script
    }

    // MARK: - Pass 1: Sequential Section Synthesis

    private struct Pass1Result {
        let sections: [SynthesisSection]
        let telemetry: [SectionTelemetry]
    }

    private static func runPass1(
        chain: ChainAttempt,
        gists: [RamblingGist],
        retriever: CorpusRetriever,
        onSectionComplete: @escaping @Sendable (Int, SynthesisSection) -> Void
    ) async -> Pass1Result {

        let moveSequence = chain.positions.map(\.moveType)
        let totalPositions = chain.positions.count

        var sections: [SynthesisSection] = []
        var telemetry: [SectionTelemetry] = []

        // Accumulated state across sections
        var scriptSoFar = ""
        var priorSummaries: [String] = []
        var allCallbacks: [String] = []

        for position in chain.positions {
            let idx = position.positionIndex

            // Resolve the user's rambling gist for this position
            let ramblingGist = position.mappedGistId.flatMap { gistId in
                gists.first { $0.id == gistId }
            }

            let rawRambling = ramblingGist?.sourceText ?? "(No rambling content mapped to this position)"
            let gistADesc = ramblingGist.map { "\($0.gistA.subject.joined(separator: ", ")) — \($0.gistA.premise) [\($0.gistA.frame.displayName)]" } ?? "(no gist)"
            let gistBDesc = ramblingGist.map { "\($0.gistB.subject.joined(separator: ", ")) — \($0.gistB.premise) [\($0.gistB.frame.displayName)]" } ?? "(no gist)"
            let frameLabel = ramblingGist?.gistA.frame.displayName ?? "unknown"

            // Retrieve creator sections for this move type
            let positionZone = CorpusRetriever.PositionZone.fromChainPosition(
                index: idx,
                totalPositions: totalPositions
            )
            let creatorGists = retriever.creatorSections(
                for: position.moveType,
                positionZone: positionZone
            )

            // Build creator section bundles with preceding context
            let creatorBundles = creatorGists.map { cg in
                SynthesisPromptEngine.CreatorSectionBundle(
                    fullChunkText: cg.fullChunkText,
                    videoTitle: cg.videoTitle,
                    precedingChunkText: retriever.precedingChunk(for: cg)?.fullChunkText
                )
            }

            // Transition bridge (sections 2+)
            let transitionBridge: SynthesisPromptEngine.TransitionBridgeBundle?
            if idx > 0 {
                let prevMove = chain.positions[idx - 1].moveType
                let result = retriever.transitionExamples(from: prevMove, to: position.moveType)
                transitionBridge = SynthesisPromptEngine.TransitionBridgeBundle(
                    previousMoveType: prevMove,
                    currentMoveType: position.moveType,
                    examples: result.pairs.map { (
                        tailText: $0.tail.fullChunkText,
                        headText: $0.head.fullChunkText,
                        videoTitle: $0.tail.videoTitle
                    )},
                    isFallback: result.isFallback,
                    fallbackType: result.fallbackType
                )
            } else {
                transitionBridge = nil
            }

            // Build prompt
            let input = SynthesisPromptEngine.Pass1Input(
                moveType: position.moveType,
                arcMoveSequence: moveSequence,
                currentPositionIndex: idx,
                scriptSoFar: scriptSoFar,
                priorSummaries: priorSummaries,
                priorCallbacks: allCallbacks,
                rawRambling: rawRambling,
                gistADescription: gistADesc,
                gistBDescription: gistBDesc,
                frameLabel: frameLabel,
                creatorSections: creatorBundles,
                transitionBridge: transitionBridge
            )

            let (systemPrompt, userPrompt) = SynthesisPromptEngine.buildPass1Prompt(input: input)

            // Call LLM
            let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
            let bundle = await adapter.generate_response_bundle(
                prompt: userPrompt,
                promptBackgroundInfo: systemPrompt,
                params: ["temperature": 0.3, "max_tokens": 2000]
            )

            let rawResponse = bundle?.content ?? ""
            let sectionTelemetry = bundle.map { SectionTelemetry(from: $0) }
                ?? SectionTelemetry()

            // Parse JSON response
            let parseResult = parsePass1Response(rawResponse: rawResponse, retryCount: 0)

            var section: SynthesisSection
            if let parsed = parseResult.parsed {
                section = SynthesisSection(
                    positionIndex: idx,
                    moveType: position.moveType,
                    writtenText: parsed.writtenText,
                    summary: parsed.summary,
                    callbacks: parsed.callbacks ?? [],
                    endingNote: parsed.endingNote,
                    analysis: parseResult.analysis,
                    ramblingGistId: position.mappedGistId,
                    ramblingSourceText: ramblingGist?.sourceText,
                    gistLabel: frameLabel,
                    promptSent: userPrompt,
                    systemPromptSent: systemPrompt,
                    rawResponse: rawResponse,
                    creatorSectionCount: creatorBundles.count,
                    creatorVideoTitles: creatorGists.map(\.videoTitle),
                    transitionBridgeUsed: transitionBridge != nil,
                    parseError: false,
                    retryCount: parseResult.retryCount
                )
            } else if parseResult.retryCount == 0 {
                // Retry once with JSON reminder
                print("[SynthesisService] JSON parse failed for section \(idx), retrying...")
                let retryResponse = await adapter.generate_response(
                    prompt: userPrompt + "\n\nIMPORTANT: Respond ONLY with valid JSON. No markdown, no backticks, no explanation.",
                    promptBackgroundInfo: systemPrompt,
                    params: ["temperature": 0.2, "max_tokens": 2000]
                )

                let retryParse = parsePass1Response(rawResponse: retryResponse, retryCount: 1)
                if let parsed = retryParse.parsed {
                    section = SynthesisSection(
                        positionIndex: idx,
                        moveType: position.moveType,
                        writtenText: parsed.writtenText,
                        summary: parsed.summary,
                        callbacks: parsed.callbacks ?? [],
                        endingNote: parsed.endingNote,
                        analysis: retryParse.analysis.isEmpty ? parseResult.analysis : retryParse.analysis,
                        ramblingGistId: position.mappedGistId,
                        ramblingSourceText: ramblingGist?.sourceText,
                        gistLabel: frameLabel,
                        promptSent: userPrompt,
                        systemPromptSent: systemPrompt,
                        rawResponse: retryResponse,
                        creatorSectionCount: creatorBundles.count,
                        creatorVideoTitles: creatorGists.map(\.videoTitle),
                        transitionBridgeUsed: transitionBridge != nil,
                        parseError: false,
                        retryCount: 1
                    )
                } else {
                    // Both attempts failed — use raw response as writtenText
                    print("[SynthesisService] Both parse attempts failed for section \(idx). Using raw response.")
                    section = SynthesisSection(
                        positionIndex: idx,
                        moveType: position.moveType,
                        writtenText: rawResponse,
                        summary: "",
                        callbacks: [],
                        endingNote: "",
                        analysis: parseResult.analysis,
                        ramblingGistId: position.mappedGistId,
                        ramblingSourceText: ramblingGist?.sourceText,
                        gistLabel: frameLabel,
                        promptSent: userPrompt,
                        systemPromptSent: systemPrompt,
                        rawResponse: rawResponse,
                        creatorSectionCount: creatorBundles.count,
                        creatorVideoTitles: creatorGists.map(\.videoTitle),
                        transitionBridgeUsed: transitionBridge != nil,
                        parseError: true,
                        retryCount: 2
                    )
                }
            } else {
                // Should not reach here, but handle gracefully
                section = SynthesisSection(
                    positionIndex: idx,
                    moveType: position.moveType,
                    writtenText: rawResponse,
                    parseError: true,
                    retryCount: parseResult.retryCount
                )
            }

            // Accumulate state for next section
            if !section.writtenText.isEmpty {
                scriptSoFar += (scriptSoFar.isEmpty ? "" : "\n\n") + section.writtenText
            }
            if !section.summary.isEmpty {
                priorSummaries.append(section.summary)
            }
            allCallbacks.append(contentsOf: section.callbacks)

            sections.append(section)
            telemetry.append(sectionTelemetry)

            // Notify UI
            onSectionComplete(idx, section)
        }

        return Pass1Result(sections: sections, telemetry: telemetry)
    }

    // MARK: - Pass 1 JSON Parsing

    private struct ParseResult {
        let parsed: Pass1JSONResponse?
        let analysis: String
        let retryCount: Int
    }

    private static func parsePass1Response(rawResponse: String, retryCount: Int) -> ParseResult {
        var text = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Extract <analysis>...</analysis> content
        var analysis = ""
        if let openRange = text.range(of: "<analysis>"),
           let closeRange = text.range(of: "</analysis>") {
            analysis = String(text[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove the analysis block so only JSON remains
            text = String(text[closeRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Strip markdown code fences if present
        if text.hasPrefix("```json") {
            text = String(text.dropFirst(7))
        } else if text.hasPrefix("```") {
            text = String(text.dropFirst(3))
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Find outermost JSON object braces
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            text = String(text[firstBrace...lastBrace])
        }

        guard let data = text.data(using: .utf8) else {
            return ParseResult(parsed: nil, analysis: analysis, retryCount: retryCount)
        }

        do {
            let decoded = try JSONDecoder().decode(Pass1JSONResponse.self, from: data)
            return ParseResult(parsed: decoded, analysis: analysis, retryCount: retryCount)
        } catch {
            print("[SynthesisService] JSON parse error: \(error.localizedDescription)")
            return ParseResult(parsed: nil, analysis: analysis, retryCount: retryCount)
        }
    }

    // MARK: - Pass 2: Transition Smoothing

    private struct Pass2Result {
        let smoothedScript: String?
        let promptSent: String
        let systemPromptSent: String
        let rawResponse: String
        let telemetry: SectionTelemetry?
    }

    private static func runPass2(
        sections: [SynthesisSection],
        moveSequence: [RhetoricalMoveType],
        retriever: CorpusRetriever
    ) async -> Pass2Result {

        guard sections.count >= 2 else {
            // No seams to smooth with 0 or 1 sections
            let concatenated = sections.map(\.writtenText).joined(separator: "\n\n")
            return Pass2Result(
                smoothedScript: concatenated,
                promptSent: "",
                systemPromptSent: "",
                rawResponse: concatenated,
                telemetry: nil
            )
        }

        // Build transition examples for each seam
        var seamTransitions: [SynthesisPromptEngine.SeamTransition] = []
        for i in 0..<(sections.count - 1) {
            let moveA = sections[i].moveType
            let moveB = sections[i + 1].moveType
            let result = retriever.transitionExamples(from: moveA, to: moveB)

            seamTransitions.append(SynthesisPromptEngine.SeamTransition(
                seamIndex: i,
                moveA: moveA,
                moveB: moveB,
                endingNoteA: sections[i].endingNote,
                examples: result.pairs.map { (
                    tailText: $0.tail.fullChunkText,
                    headText: $0.head.fullChunkText,
                    videoTitle: $0.tail.videoTitle
                )},
                isFallback: result.isFallback,
                fallbackType: result.fallbackType
            ))
        }

        // Build prompt
        let input = SynthesisPromptEngine.Pass2Input(
            sections: sections,
            moveSequence: moveSequence,
            transitionExamples: seamTransitions
        )
        let (systemPrompt, userPrompt) = SynthesisPromptEngine.buildPass2Prompt(input: input)

        // Compute dynamic max_tokens
        let draftWordCount = sections.reduce(0) { $0 + $1.writtenText.split(separator: " ").count }
        let maxTokens = min(8000, max(4000, Int(Double(draftWordCount) * 1.3 * 1.5)))

        // Call LLM
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let bundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": maxTokens]
        )

        let rawResponse = bundle?.content ?? ""
        let telemetry = bundle.map { SectionTelemetry(from: $0) }

        return Pass2Result(
            smoothedScript: rawResponse.trimmingCharacters(in: .whitespacesAndNewlines),
            promptSent: userPrompt,
            systemPromptSent: systemPrompt,
            rawResponse: rawResponse,
            telemetry: telemetry
        )
    }
}
