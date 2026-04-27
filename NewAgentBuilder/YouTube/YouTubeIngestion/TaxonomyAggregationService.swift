//
//  TaxonomyAggregationService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import Foundation

/// Result wrapper that includes both the aggregation result and the prompt used
struct AggregationResultWithPrompt {
    let result: TaxonomyAggregationResult
    let promptUsed: String
    let rawResponse: String
}

/// Result wrapper for style library aggregation (new template-focused approach)
struct StyleLibraryResultWithPrompt {
    let result: StyleLibraryAggregationResult
    let promptUsed: String
    let rawResponse: String
}

/// Service for aggregating Phase 0 results into content type clusters
class TaxonomyAggregationService {

    static let shared = TaxonomyAggregationService()

    // Note: For parallel fidelity testing, use aggregateWithFreshAdapter() instead
    private let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

    /// Creates a fresh adapter for parallel execution (avoids serialization from shared adapter)
    private func createFreshAdapter() -> ClaudeModelAdapter {
        return ClaudeModelAdapter(model: .claude4Sonnet)
    }

    // MARK: - Main Aggregation Function

    /// Aggregate Phase 0 results from multiple videos into content type clusters
    /// Uses execution traces when available, falls back to legacy categorical data
    /// - Parameters:
    ///   - videos: Videos with Phase 0 results to analyze
    ///   - temperature: LLM temperature (default 0.3 for consistent clustering)
    /// - Returns: AggregationResultWithPrompt containing clusters, shared patterns, and the prompt used
    func aggregatePhase0Results(videos: [YouTubeVideo], temperature: Double = 0.3) async throws -> AggregationResultWithPrompt {

        // Filter to only videos with Phase 0 results (either format)
        let analyzedVideos = videos.filter { $0.phase0Result != nil }

        guard analyzedVideos.count >= 3 else {
            throw AggregationError.insufficientVideos("Need at least 3 videos with Phase 0 results")
        }

        // Build the input data for the LLM - use execution traces when available, fall back to legacy
        let videoSummaries = analyzedVideos.map { video -> String in
            let p = video.phase0Result!

            // If we have execution trace (new format), use it
            if let trace = p.executionTrace {
                let pivotSummary = trace.pivots.map { pivot in
                    "  - Pivot \(pivot.pivotNumber) at \(pivot.timestampPercent)%: \"\(pivot.triggerMoment)\" → challenges: \(pivot.assumptionChallenged)"
                }.joined(separator: "\n")

                return """
                ═══════════════════════════════════════════════════════════════
                VIDEO: "\(video.title)"
                ID: \(video.videoId)
                [HAS EXECUTION TRACE]
                ═══════════════════════════════════════════════════════════════

                OPENING (~\(trace.opening.durationSeconds) seconds):
                - Hook Type: \(trace.opening.hookType)
                - What Happens: \(trace.opening.whatHappens)

                PIVOTS:
                \(pivotSummary)

                EVIDENCE FLOW: \(trace.evidenceFlow.joined(separator: " → "))

                ESCALATION: \(trace.escalation)

                RESOLUTION: \(trace.resolution)

                NARRATOR ROLE: \(trace.narratorRole)
                """
            } else {
                // Fall back to legacy categorical data
                return """
                ═══════════════════════════════════════════════════════════════
                VIDEO: "\(video.title)"
                ID: \(video.videoId)
                [LEGACY FORMAT - no execution trace]
                ═══════════════════════════════════════════════════════════════

                PIVOT COUNT: \(p.pivotCount)
                RETENTION STRATEGY: \(p.retentionStrategy)
                ARGUMENT TYPE: \(p.argumentType)
                SECTION DENSITY: \(p.sectionDensity)
                NARRATIVE DEVICE: \(p.narrativeDevice)
                EVIDENCE TYPES: \(p.evidenceTypes.joined(separator: ", "))
                CORE QUESTION: \(p.coreQuestion)
                """
            }
        }.joined(separator: "\n\n")

        // Check how many videos have execution traces vs legacy format
        let videosWithTraces = analyzedVideos.filter { $0.phase0Result?.executionTrace != nil }.count
        let videosWithLegacy = analyzedVideos.count - videosWithTraces

        let formatNote = videosWithLegacy > 0
            ? "\n\nNOTE: \(videosWithTraces) videos have detailed execution traces, \(videosWithLegacy) have legacy categorical data. Use what's available for each video."
            : ""

        let prompt = """
        I have \(analyzedVideos.count) videos with structural analysis data.\(formatNote)

        HERE ARE ALL VIDEOS:

        \(videoSummaries)

        ═══════════════════════════════════════════════════════════════
        CLUSTERING TEST: STRUCTURAL SURVIVABILITY
        ═══════════════════════════════════════════════════════════════

        THE FUNDAMENTAL QUESTION:
        "If an AI used Video A's execution trace as a template to write Video B, where would the structure BREAK?"

        If nowhere → same cluster.
        If specific break point → different clusters.

        ### Break Categories (use only these):
        - opening-mismatch: Opening architecture doesn't transfer
        - narrator-mismatch: Creator's relationship to material is incompatible
        - evidence-flow-mismatch: Proof accumulation sequence doesn't fit
        - pivot-mechanics-mismatch: Turns are triggered by incompatible mechanisms
        - escalation-mismatch: How stakes/complexity builds is structurally different
        - resolution-mismatch: Closing architecture doesn't transfer
        - none: No structural break — compatible

        ### CRITICAL: No Transitivity
        You may NOT assume transitivity. If A fits B and B fits C, you must still verify A fits C directly.

        ### Clustering Rules:
        - Test each pair explicitly using the "where would it break?" question
        - Cluster by whether the same execution trace could generate both videos
        - Aim for 3-7 total clusters
        - Allow single-video clusters if genuinely distinct

        DO NOT cluster by: Topic, tone, what viewer learns, how outputs "feel"
        DO cluster by: Structural survivability — would template reuse break or work?

        ═══════════════════════════════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════════════════════════════

        For each cluster, provide:
        - **name**: Name reflecting the EXECUTION APPROACH
        - **coreQuestion**: The structural pattern this cluster represents
        - **description**: 2-3 sentences on what makes this cluster template-compatible
        - **evidenceTypes**: Common evidence flow patterns
        - **narrativeArc**: How these videos structurally progress
        - **videoIds**: Array of video IDs in this cluster
        - **typicalPivotMin / typicalPivotMax**: Range of pivot counts
        - **dominantRetentionStrategy**: "template-compatible" (we no longer use old categories)
        - **dominantArgumentType**: "template-compatible"
        - **dominantSectionDensity**: "template-compatible"
        - **viewerTransformation**: Before/after state
        - **emotionalArc**: How the structure builds
        - **creatorRole**: Narrator role pattern
        - **signatureMoves**: Opening/pivot/ending patterns

        Also provide:
        - **creatorOrientation**: Overall creator patterns
        - **sharedPatterns**: Patterns shared across ALL clusters
        - **creatorSignature**: What makes this creator's execution unique

        {
          "creatorOrientation": {
            "primaryEvidenceSources": "",
            "emotionalTrajectory": "",
            "creatorPositioning": "",
            "resolutionPattern": ""
          },
          "clusters": [
            {
              "name": "",
              "coreQuestion": "",
              "description": "",
              "evidenceTypes": [],
              "narrativeArc": "",
              "videoIds": [],
              "typicalPivotMin": 0,
              "typicalPivotMax": 0,
              "dominantRetentionStrategy": "template-compatible",
              "dominantArgumentType": "template-compatible",
              "dominantSectionDensity": "template-compatible",
              "viewerTransformation": {
                "before": "",
                "after": ""
              },
              "emotionalArc": "",
              "creatorRole": "",
              "signatureMoves": {
                "openingPattern": "",
                "pivotMechanism": "",
                "endingPattern": ""
              }
            }
          ],
          "sharedPatterns": [],
          "creatorSignature": ""
        }

        Return ONLY valid JSON, no other text.
        """

        let systemPrompt = """
        You are clustering videos by STRUCTURAL SURVIVABILITY for AI script generation.

        The core test: "If an AI used Video A's execution trace as a template to write Video B, where would the structure BREAK?"

        If nowhere → same cluster.
        If specific break point → different clusters.

        Be rigorous. Test each pairing explicitly. Do not assume transitivity.
        Topics don't matter. Execution transfer matters.

        Return only valid JSON.
        """

        let fullPromptForCopy = """
        SYSTEM PROMPT:
        \(systemPrompt)

        USER PROMPT:
        \(prompt)
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 6000]
        )

        let parsedResult = try parseAggregationResponse(response: response)

        return AggregationResultWithPrompt(
            result: parsedResult,
            promptUsed: fullPromptForCopy,
            rawResponse: response
        )
    }

    /// Parallel-safe version that creates a fresh adapter (use this for fidelity testing)
    func aggregatePhase0ResultsParallel(videos: [YouTubeVideo], temperature: Double = 0.3) async throws -> AggregationResultWithPrompt {
        // Create a fresh adapter for this call to enable true parallel execution
        let freshAdapter = createFreshAdapter()

        // Filter to only videos with Phase 0 results (either format)
        let analyzedVideos = videos.filter { $0.phase0Result != nil }

        guard analyzedVideos.count >= 3 else {
            throw AggregationError.insufficientVideos("Need at least 3 videos with Phase 0 results")
        }

        // Build the input data for the LLM - use execution traces when available, fall back to legacy
        let videoSummaries = analyzedVideos.map { video -> String in
            let p = video.phase0Result!

            // If we have execution trace (new format), use it
            if let trace = p.executionTrace {
                let pivotSummary = trace.pivots.map { pivot in
                    "  - Pivot \(pivot.pivotNumber) at \(pivot.timestampPercent)%: \"\(pivot.triggerMoment)\" → challenges: \(pivot.assumptionChallenged)"
                }.joined(separator: "\n")

                return """
                ═══════════════════════════════════════════════════════════════
                VIDEO: "\(video.title)"
                ID: \(video.videoId)
                [HAS EXECUTION TRACE]
                ═══════════════════════════════════════════════════════════════

                OPENING (~\(trace.opening.durationSeconds) seconds):
                - Hook Type: \(trace.opening.hookType)
                - What Happens: \(trace.opening.whatHappens)

                PIVOTS:
                \(pivotSummary)

                EVIDENCE FLOW: \(trace.evidenceFlow.joined(separator: " → "))

                ESCALATION: \(trace.escalation)

                RESOLUTION: \(trace.resolution)

                NARRATOR ROLE: \(trace.narratorRole)
                """
            } else {
                // Fall back to legacy categorical data
                return """
                ═══════════════════════════════════════════════════════════════
                VIDEO: "\(video.title)"
                ID: \(video.videoId)
                [LEGACY FORMAT - no execution trace]
                ═══════════════════════════════════════════════════════════════

                PIVOT COUNT: \(p.pivotCount)
                RETENTION STRATEGY: \(p.retentionStrategy)
                ARGUMENT TYPE: \(p.argumentType)
                SECTION DENSITY: \(p.sectionDensity)
                NARRATIVE DEVICE: \(p.narrativeDevice)
                EVIDENCE TYPES: \(p.evidenceTypes.joined(separator: ", "))
                CORE QUESTION: \(p.coreQuestion)
                """
            }
        }.joined(separator: "\n\n")

        // Check how many videos have execution traces vs legacy format
        let videosWithTraces = analyzedVideos.filter { $0.phase0Result?.executionTrace != nil }.count
        let videosWithLegacy = analyzedVideos.count - videosWithTraces

        let formatNote = videosWithLegacy > 0
            ? "\n\nNOTE: \(videosWithTraces) videos have detailed execution traces, \(videosWithLegacy) have legacy categorical data. Use what's available for each video."
            : ""

        let prompt = """
        I have \(analyzedVideos.count) videos with structural analysis data.\(formatNote)

        HERE ARE ALL VIDEOS:

        \(videoSummaries)

        ═══════════════════════════════════════════════════════════════
        CLUSTERING TEST: STRUCTURAL SURVIVABILITY
        ═══════════════════════════════════════════════════════════════

        THE FUNDAMENTAL QUESTION:
        "If an AI used Video A's execution trace as a template to write Video B, where would the structure BREAK?"

        If nowhere → same cluster.
        If specific break point → different clusters.

        ### Break Categories (use only these):
        - opening-mismatch: Opening architecture doesn't transfer
        - narrator-mismatch: Creator's relationship to material is incompatible
        - evidence-flow-mismatch: Proof accumulation sequence doesn't fit
        - pivot-mechanics-mismatch: Turns are triggered by incompatible mechanisms
        - escalation-mismatch: How stakes/complexity builds is structurally different
        - resolution-mismatch: Closing architecture doesn't transfer
        - none: No structural break — compatible

        ### CRITICAL: No Transitivity
        You may NOT assume transitivity. If A fits B and B fits C, you must still verify A fits C directly.

        ### Clustering Rules:
        - Test each pair explicitly using the "where would it break?" question
        - Cluster by whether the same execution trace could generate both videos
        - Aim for 3-7 total clusters
        - Allow single-video clusters if genuinely distinct

        DO NOT cluster by: Topic, tone, what viewer learns, how outputs "feel"
        DO cluster by: Structural survivability — would template reuse break or work?

        ═══════════════════════════════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════════════════════════════

        For each cluster, provide:
        - **name**: Name reflecting the EXECUTION APPROACH
        - **coreQuestion**: The structural pattern this cluster represents
        - **description**: 2-3 sentences on what makes this cluster template-compatible
        - **evidenceTypes**: Common evidence flow patterns
        - **narrativeArc**: How these videos structurally progress
        - **videoIds**: Array of video IDs in this cluster
        - **typicalPivotMin / typicalPivotMax**: Range of pivot counts
        - **dominantRetentionStrategy**: "template-compatible"
        - **dominantArgumentType**: "template-compatible"
        - **dominantSectionDensity**: "template-compatible"
        - **viewerTransformation**: Before/after state
        - **emotionalArc**: How the structure builds
        - **creatorRole**: Narrator role pattern
        - **signatureMoves**: Opening/pivot/ending patterns

        Also provide:
        - **creatorOrientation**: Overall creator patterns
        - **sharedPatterns**: Patterns shared across ALL clusters
        - **creatorSignature**: What makes this creator's execution unique

        {
          "creatorOrientation": {
            "primaryEvidenceSources": "",
            "emotionalTrajectory": "",
            "creatorPositioning": "",
            "resolutionPattern": ""
          },
          "clusters": [
            {
              "name": "",
              "coreQuestion": "",
              "description": "",
              "evidenceTypes": [],
              "narrativeArc": "",
              "videoIds": [],
              "typicalPivotMin": 0,
              "typicalPivotMax": 0,
              "dominantRetentionStrategy": "template-compatible",
              "dominantArgumentType": "template-compatible",
              "dominantSectionDensity": "template-compatible",
              "viewerTransformation": {
                "before": "",
                "after": ""
              },
              "emotionalArc": "",
              "creatorRole": "",
              "signatureMoves": {
                "openingPattern": "",
                "pivotMechanism": "",
                "endingPattern": ""
              }
            }
          ],
          "sharedPatterns": [],
          "creatorSignature": ""
        }

        Return ONLY valid JSON, no other text.
        """

        let systemPrompt = """
        You are clustering videos by STRUCTURAL SURVIVABILITY for AI script generation.

        The core test: "If an AI used Video A's execution trace as a template to write Video B, where would the structure BREAK?"

        If nowhere → same cluster.
        If specific break point → different clusters.

        Be rigorous. Test each pairing explicitly. Do not assume transitivity.
        Topics don't matter. Execution transfer matters.

        Return only valid JSON.
        """

        let fullPromptForCopy = """
        SYSTEM PROMPT:
        \(systemPrompt)

        USER PROMPT:
        \(prompt)
        """

        let response = await freshAdapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 6000]
        )

        let parsedResult = try parseAggregationResponse(response: response)

        return AggregationResultWithPrompt(
            result: parsedResult,
            promptUsed: fullPromptForCopy,
            rawResponse: response
        )
    }

    // MARK: - Style Library Aggregation (New Template-Focused Approach)

    /// Aggregate videos into style libraries based on STRUCTURAL SURVIVABILITY
    /// Uses execution traces to determine template compatibility
    /// - Parameters:
    ///   - videos: Videos with execution traces to cluster
    ///   - temperature: LLM temperature (default 0.2 for consistent clustering)
    /// - Returns: StyleLibraryResultWithPrompt containing style libraries and boundary decisions
    func aggregateToStyleLibraries(videos: [YouTubeVideo], temperature: Double = 0.2) async throws -> StyleLibraryResultWithPrompt {
        let freshAdapter = createFreshAdapter()

        // Filter to videos with execution traces
        let tracedVideos = videos.filter { $0.phase0Result?.executionTrace != nil }

        guard tracedVideos.count >= 3 else {
            throw AggregationError.insufficientVideos("Need at least 3 videos with execution traces")
        }

        // Build execution trace summaries
        let videoSummaries = tracedVideos.map { video -> String in
            let trace = video.phase0Result!.executionTrace!
            let pivotSummary = trace.pivots.map { p in
                "  - Pivot \(p.pivotNumber) at \(p.timestampPercent)%: \"\(p.triggerMoment)\" → challenges: \(p.assumptionChallenged)"
            }.joined(separator: "\n")

            return """
            ═══════════════════════════════════════════════════════════════
            VIDEO: "\(video.title)"
            ID: \(video.videoId)
            ═══════════════════════════════════════════════════════════════

            OPENING (~\(trace.opening.durationSeconds) seconds):
            - Hook Type: \(trace.opening.hookType)
            - What Happens: \(trace.opening.whatHappens)

            PIVOTS:
            \(pivotSummary)

            EVIDENCE FLOW: \(trace.evidenceFlow.joined(separator: " → "))

            ESCALATION: \(trace.escalation)

            RESOLUTION: \(trace.resolution)

            NARRATOR ROLE: \(trace.narratorRole)
            """
        }.joined(separator: "\n\n")

        let prompt = Self.buildStyleLibraryPrompt(videoCount: tracedVideos.count, videoSummaries: videoSummaries)

        let response = await freshAdapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: Self.styleLibrarySystemPrompt,
            params: ["temperature": temperature, "max_tokens": 8000]
        )

        let fullPromptForCopy = """
        === SYSTEM PROMPT ===
        \(Self.styleLibrarySystemPrompt)

        === USER PROMPT ===
        \(prompt)
        """

        let parsedResult = try parseStyleLibraryResponse(response: response)

        return StyleLibraryResultWithPrompt(
            result: parsedResult,
            promptUsed: fullPromptForCopy,
            rawResponse: response
        )
    }

    /// Build the style library clustering prompt (exposed for copying)
    static func buildStyleLibraryPrompt(videoCount: Int, videoSummaries: String) -> String {
        return """
        I have \(videoCount) videos with execution traces. Each trace describes what LITERALLY HAPPENS structurally.

        HERE ARE ALL VIDEOS:

        \(videoSummaries)

        ═══════════════════════════════════════════════════════════════
        CLUSTERING TEST: STRUCTURAL SURVIVABILITY
        ═══════════════════════════════════════════════════════════════

        You are building a STYLE LIBRARY for AI script generation.
        Group videos by EXECUTION TEMPLATE — the replicable structural recipe that lets an AI write new scripts in that style.

        THE CORE TEST:
        "If an AI used Video A's execution trace as a template to write Video B, where would the structure BREAK?"

        If nowhere → same cluster.
        If specific break point → different clusters.

        ### CRITICAL: No Transitivity Assumption

        You may NOT assume transitivity. If A fits B and B fits C, you must still verify A fits C directly.
        Do not infer compatibility through chains.

        ### Break Categories (use only these):

        - opening-mismatch: Opening architecture doesn't transfer
        - narrator-mismatch: Creator's relationship to material is incompatible
        - evidence-flow-mismatch: Proof accumulation sequence doesn't fit
        - pivot-mechanics-mismatch: Turns are triggered by incompatible mechanisms
        - escalation-mismatch: How stakes/complexity builds is structurally different
        - resolution-mismatch: Closing architecture doesn't transfer
        - none: No structural break — compatible

        ### Clustering Rules:

        - Cluster by whether the same execution trace could generate both videos
        - Allow 5-12 videos per cluster if execution genuinely transfers
        - Allow 1-2 videos if genuinely distinct template
        - Aim for 3-7 total style libraries

        DO NOT cluster by: Topic, tone, what viewer learns, how outputs "feel"
        DO cluster by: Structural survivability — would template reuse break or work?

        ═══════════════════════════════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════════════════════════════

        {
          "styleLibraries": [
            {
              "name": "Short name describing the EXECUTION APPROACH",
              "stylePresetTag": "kebab-case-tag",
              "whatThisTrains": "What new video can an AI write after studying this library?",

              "executionRecipe": {
                "opening": "What happens in first 60-90 seconds?",
                "pivotPattern": "How many pivots, what triggers them?",
                "evidenceFlow": "How does proof accumulate?",
                "escalation": "How do stakes build?",
                "resolution": "How does it close?"
              },

              "trainingSet": {
                "videoIds": ["id1", "id2"],
                "whyTheseBelongTogether": "If you used any video's execution trace to write another here, where would it break? (Answer: nowhere — explain why)",
                "notesForAI": "What's key to replicating this style?"
              },

              "usageGuidance": {
                "bestUseCaseForGeneration": "What video idea fits this style?",
                "referencePriority": "high | medium | niche"
              }
            }
          ],
          "boundaryDecisions": [
            {
              "videoId": "id",
              "assignedTo": "style-tag",
              "consideredFor": ["other-tag-1", "other-tag-2"],
              "decisionReason": "Why this cluster",
              "wouldBreakAt": "Break category if used for rejected cluster"
            }
          ]
        }

        Include boundaryDecisions for videos that were difficult to assign (considered for multiple clusters).

        Return ONLY valid JSON, no other text.
        """
    }

    /// System prompt for style library clustering (exposed for copying)
    static let styleLibrarySystemPrompt = """
        You are building a style library for AI script generation.
        Group videos by EXECUTION TEMPLATE — the replicable structural recipe.

        The core test is STRUCTURAL SURVIVABILITY, not similarity.
        Think like a model trainer. Topics don't matter. Execution transfer matters.

        For every grouping decision, ask:
        "If an AI used Video A's execution trace as a template to write Video B, where would the structure BREAK?"

        If nowhere → same cluster.
        If specific break point → different clusters.

        Be rigorous. Test each pairing explicitly. Do not assume transitivity.

        Return only valid JSON.
        """

    // MARK: - Response Parsing

    private func parseAggregationResponse(response: String) throws -> TaxonomyAggregationResult {

        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw AggregationError.invalidResponse("Could not find JSON in response")
        }

        let decoded = try JSONDecoder().decode(AggregationResponseData.self, from: data)

        // Convert to domain models
        let creatorOrientation = decoded.creatorOrientation.map { co in
            CreatorOrientation(
                primaryEvidenceSources: co.primaryEvidenceSources,
                emotionalTrajectory: co.emotionalTrajectory,
                creatorPositioning: co.creatorPositioning,
                resolutionPattern: co.resolutionPattern
            )
        }

        let clusters = decoded.clusters.map { c in
            let viewerTransformation = c.viewerTransformation.map { vt in
                ViewerTransformation(before: vt.before, after: vt.after)
            }

            let signatureMoves = c.signatureMoves.map { sm in
                SignatureMoves(
                    openingPattern: sm.openingPattern,
                    pivotMechanism: sm.pivotMechanism,
                    endingPattern: sm.endingPattern
                )
            }

            return ContentTypeCluster(
                name: c.name,
                coreQuestion: c.coreQuestion,
                description: c.description,
                evidenceTypes: c.evidenceTypes,
                narrativeArc: c.narrativeArc,
                videoIds: c.videoIds,
                typicalPivotMin: c.typicalPivotMin,
                typicalPivotMax: c.typicalPivotMax,
                dominantRetentionStrategy: c.dominantRetentionStrategy,
                dominantArgumentType: c.dominantArgumentType,
                dominantSectionDensity: c.dominantSectionDensity,
                viewerTransformation: viewerTransformation,
                emotionalArc: c.emotionalArc,
                creatorRole: c.creatorRole,
                signatureMoves: signatureMoves
            )
        }

        return TaxonomyAggregationResult(
            creatorOrientation: creatorOrientation,
            clusters: clusters,
            sharedPatterns: decoded.sharedPatterns,
            creatorSignature: decoded.creatorSignature
        )
    }

    private func parseStyleLibraryResponse(response: String) throws -> StyleLibraryAggregationResult {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw AggregationError.invalidResponse("Could not find JSON in style library response")
        }

        let decoded = try JSONDecoder().decode(StyleLibraryResponseData.self, from: data)

        // Convert to domain models
        let libraries = decoded.styleLibraries.map { lib in
            StyleLibrary(
                name: lib.name,
                stylePresetTag: lib.stylePresetTag,
                whatThisTrains: lib.whatThisTrains,
                executionRecipe: ExecutionRecipe(
                    opening: lib.executionRecipe.opening,
                    pivotPattern: lib.executionRecipe.pivotPattern,
                    evidenceFlow: lib.executionRecipe.evidenceFlow,
                    escalation: lib.executionRecipe.escalation,
                    resolution: lib.executionRecipe.resolution
                ),
                trainingSet: TrainingSet(
                    videoIds: lib.trainingSet.videoIds,
                    whyTheseBelongTogether: lib.trainingSet.whyTheseBelongTogether,
                    notesForAI: lib.trainingSet.notesForAI
                ),
                usageGuidance: UsageGuidance(
                    bestUseCaseForGeneration: lib.usageGuidance.bestUseCaseForGeneration,
                    referencePriority: lib.usageGuidance.referencePriority
                )
            )
        }

        let boundaryDecisions = decoded.boundaryDecisions?.map { bd in
            BoundaryDecision(
                videoId: bd.videoId,
                assignedTo: bd.assignedTo,
                consideredFor: bd.consideredFor,
                decisionReason: bd.decisionReason,
                wouldBreakAt: bd.wouldBreakAt
            )
        } ?? []

        return StyleLibraryAggregationResult(
            styleLibraries: libraries,
            boundaryDecisions: boundaryDecisions
        )
    }

    // MARK: - JSON Extraction

    private func extractJSON(from response: String) -> String? {
        // Try to find JSON in ```json block
        if let jsonBlockRange = response.range(of: "```json"),
           let endBlockRange = response.range(of: "```", range: jsonBlockRange.upperBound..<response.endIndex) {
            let jsonContent = String(response[jsonBlockRange.upperBound..<endBlockRange.lowerBound])
            return jsonContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON in generic ``` block
        if let startRange = response.range(of: "```"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            let content = String(response[startRange.upperBound..<endRange.lowerBound])
            if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Try to find JSON by locating first { and last }
        if let firstBrace = response.firstIndex(of: "{"),
           let lastBrace = response.lastIndex(of: "}") {
            let jsonContent = String(response[firstBrace...lastBrace])
            return jsonContent
        }

        // If already clean JSON
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }

        return nil
    }

    // MARK: - Helper Types for JSON Decoding

    private struct AggregationResponseData: Codable {
        let creatorOrientation: CreatorOrientationData?
        let clusters: [ClusterData]
        let sharedPatterns: [String]
        let creatorSignature: String
    }

    private struct CreatorOrientationData: Codable {
        let primaryEvidenceSources: String
        let emotionalTrajectory: String
        let creatorPositioning: String
        let resolutionPattern: String
    }

    private struct ClusterData: Codable {
        let name: String
        let coreQuestion: String
        let description: String
        let evidenceTypes: [String]
        let narrativeArc: String
        let videoIds: [String]
        let typicalPivotMin: Int
        let typicalPivotMax: Int
        let dominantRetentionStrategy: String
        let dominantArgumentType: String
        let dominantSectionDensity: String
        // New intent features
        let viewerTransformation: ViewerTransformationData?
        let emotionalArc: String?
        let creatorRole: String?
        let signatureMoves: SignatureMovesData?
    }

    private struct ViewerTransformationData: Codable {
        let before: String
        let after: String
    }

    private struct SignatureMovesData: Codable {
        let openingPattern: String
        let pivotMechanism: String
        let endingPattern: String
    }

    // MARK: - Style Library Response Data Types

    private struct StyleLibraryResponseData: Codable {
        let styleLibraries: [StyleLibraryData]
        let boundaryDecisions: [BoundaryDecisionData]?
    }

    private struct StyleLibraryData: Codable {
        let name: String
        let stylePresetTag: String
        let whatThisTrains: String
        let executionRecipe: ExecutionRecipeData
        let trainingSet: TrainingSetData
        let usageGuidance: UsageGuidanceData
    }

    private struct ExecutionRecipeData: Codable {
        let opening: String
        let pivotPattern: String
        let evidenceFlow: String
        let escalation: String
        let resolution: String
    }

    private struct TrainingSetData: Codable {
        let videoIds: [String]
        let whyTheseBelongTogether: String
        let notesForAI: String
    }

    private struct UsageGuidanceData: Codable {
        let bestUseCaseForGeneration: String
        let referencePriority: String
    }

    private struct BoundaryDecisionData: Codable {
        let videoId: String
        let assignedTo: String
        let consideredFor: [String]
        let decisionReason: String
        let wouldBreakAt: String
    }

    enum AggregationError: Error, LocalizedError {
        case insufficientVideos(String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .insufficientVideos(let message): return message
            case .invalidResponse(let message): return "Invalid aggregation response: \(message)"
            }
        }
    }
}
