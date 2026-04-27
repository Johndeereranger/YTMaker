//
//  ArcComparisonRunner.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  Execution orchestrator for the 10 narrative arc paths.
//  P1–P5: Original approach (Pass 1 & 2).
//  V6–V10: Enriched-rambling approach (Pass 2 only).
//  All paths run in parallel via TaskGroup. Each path is internally sequential.
//  Uses nonisolated static pattern with per-call ClaudeModelAdapter instances.
//

import Foundation

struct ArcComparisonRunner {

    // MARK: - Inputs

    let model: AIModel
    let rawRambling: String
    let baseRambling: String       // coordinator.session.rawRamblingText (no supplemental appended)
    let channelId: String
    let creatorProfile: CreatorNarrativeProfile
    let representativeSpines: [NarrativeSpine]
    let allThroughlines: [(videoId: String, throughline: String)]
    let enabledPaths: Set<ArcPath>
    let gapFindings: [GapFinding]
    let allGapFindings: [GapFinding]  // ALL findings from ALL gap paths (for Q→A matching)

    /// Supplemental Q&A text (for V-path preprocessing). Empty string if not available.
    let supplementalText: String
    /// First-pass spine that gap detection ran against (for V6–V10 positional reference).
    let firstPassSpine: NarrativeSpine?

    /// Callback for spine lookup by videoId (for dynamic selection paths).
    let fetchSpinesByIds: ([String]) async -> [NarrativeSpine]

    /// Fires after each individual LLM call completes (ticks the progress bar).
    var onCallComplete: (@Sendable (ArcPath, String) -> Void)?

    /// Fires when an entire path finishes all its calls (updates status badge).
    var onPathComplete: (@Sendable (ArcPath, ArcPathRunStatus) -> Void)?

    // MARK: - Run All Paths

    func run() async -> (results: [ArcPathResult], preprocessingCalls: [ArcPathCall]) {
        let paths = Array(enabledPaths).sorted { $0.rawValue < $1.rawValue }
        let pPaths = paths.filter { !$0.isPass2Only }
        let vPaths = paths.filter { $0.isPass2Only }

        // Capture inputs for sendable closures
        let model = self.model
        let rawRambling = self.rawRambling
        let channelId = self.channelId
        let profile = self.creatorProfile
        let repSpines = self.representativeSpines
        let throughlines = self.allThroughlines
        let gaps = self.gapFindings
        let fetchSpines = self.fetchSpinesByIds
        let callComplete = self.onCallComplete
        let pathComplete = self.onPathComplete
        let base = self.baseRambling

        // Stage 1: Shared split extraction (when ANY V-path is enabled and supplemental text exists)
        var preprocessingCalls: [ArcPathCall] = []
        var enrichedInventory: String = ""
        var positionalMetadata: String = ""

        if !vPaths.isEmpty && !supplementalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 1a. Base inventory — extract from base rambling alone
            let baseInvPrompts = ArcComparisonPromptEngine.contentInventoryPrompt(rawRambling: base)
            let baseInvCall = await Self.makeLLMCall(
                adapter: ClaudeModelAdapter(model: model),
                systemPrompt: baseInvPrompts.system,
                userPrompt: baseInvPrompts.user,
                callIndex: 0,
                callLabel: "Base Inventory",
                path: .v6_enrichedSinglePass,
                onCallComplete: callComplete
            )
            preprocessingCalls.append(baseInvCall)
            let baseInventory = baseInvCall.rawResponse
            print("[Preprocessing] Base inventory extracted: \(baseInventory.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count) lines")

            // 1b. Strip Q/A framing from supplemental text (filters meta-statements)
            let cleanedSupplemental = Self.stripQAFraming(supplementalText)
            print("[Preprocessing] Cleaned supplemental: \(cleanedSupplemental.count) chars from \(supplementalText.count) chars")

            // 1c. Supplemental inventory — extract as NEW distinct atoms
            if !cleanedSupplemental.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let suppInvPrompts = ArcComparisonPromptEngine.supplementalInventoryPrompt(cleanedSupplemental: cleanedSupplemental)
                let suppInvCall = await Self.makeLLMCall(
                    adapter: ClaudeModelAdapter(model: model),
                    systemPrompt: suppInvPrompts.system,
                    userPrompt: suppInvPrompts.user,
                    callIndex: 1,
                    callLabel: "Supplemental Inventory",
                    path: .v6_enrichedSinglePass,
                    onCallComplete: callComplete
                )
                preprocessingCalls.append(suppInvCall)
                let supplementalInventory = suppInvCall.rawResponse

                // 1d. Merge inventories (Swift-side, renumber, tag [SUP])
                let (merged, supplementalRange) = Self.mergeInventories(base: baseInventory, supplemental: supplementalInventory)
                enrichedInventory = merged
                print("[Preprocessing] Merged inventory: \(merged.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count) atoms (supplemental range: \(supplementalRange))")

                // 1e. Positional metadata for V6-V10 (Swift-side, references [SUP] atom numbers)
                if vPaths.contains(where: { $0.isEnrichedPath }) {
                    positionalMetadata = ArcComparisonPromptEngine.renderPositionalGapMetadata(
                        gapFindings: gaps,
                        supplementalRange: supplementalRange
                    )
                }
            } else {
                // No valid supplemental content after filtering — use base inventory only
                enrichedInventory = baseInventory
                print("[Preprocessing] No supplemental content after Q/A filtering — using base inventory only")
            }
        }

        // Capture for sendable closures
        let inventory = enrichedInventory
        let posMetadata = positionalMetadata

        // Stage 2: Run all paths in parallel
        var results: [ArcPathResult] = []

        await withTaskGroup(of: ArcPathResult.self) { group in
            // P-paths: original approach
            for path in pPaths {
                group.addTask {
                    switch path {
                    case .p1_singlePass:
                        return await Self.runP1(
                            model: model, rawRambling: rawRambling, channelId: channelId,
                            profile: profile, repSpines: repSpines, gapFindings: gaps,
                            onCallComplete: callComplete
                        )
                    case .p2_contentFirst:
                        return await Self.runP2(
                            model: model, rawRambling: rawRambling, channelId: channelId,
                            profile: profile, repSpines: repSpines, gapFindings: gaps,
                            onCallComplete: callComplete
                        )
                    case .p3_fourStepPipeline:
                        return await Self.runP3(
                            model: model, rawRambling: rawRambling, channelId: channelId,
                            profile: profile, repSpines: repSpines, gapFindings: gaps,
                            onCallComplete: callComplete
                        )
                    case .p4_dynamicSelection:
                        return await Self.runP4(
                            model: model, rawRambling: rawRambling, channelId: channelId,
                            profile: profile, throughlines: throughlines, gapFindings: gaps, fetchSpines: fetchSpines,
                            onCallComplete: callComplete
                        )
                    case .p5_dynamicContentFirst:
                        return await Self.runP5(
                            model: model, rawRambling: rawRambling, channelId: channelId,
                            profile: profile, throughlines: throughlines, gapFindings: gaps, fetchSpines: fetchSpines,
                            onCallComplete: callComplete
                        )
                    default:
                        fatalError("Unexpected P-path: \(path)")
                    }
                }
            }

            // V-paths: all use shared enriched inventory
            for path in vPaths {
                group.addTask {
                    switch path {
                    case .v6_enrichedSinglePass:
                        return await Self.runV6(
                            model: model, enrichedInventory: inventory, positionalMetadata: posMetadata,
                            channelId: channelId, profile: profile, repSpines: repSpines, gapFindings: gaps,
                            onCallComplete: callComplete
                        )
                    case .v7_enrichedContentFirst:
                        return await Self.runV7(
                            model: model, enrichedInventory: inventory, positionalMetadata: posMetadata,
                            channelId: channelId, profile: profile, repSpines: repSpines, gapFindings: gaps,
                            onCallComplete: callComplete
                        )
                    case .v8_enrichedFourStep:
                        return await Self.runV8(
                            model: model, enrichedInventory: inventory, positionalMetadata: posMetadata,
                            channelId: channelId, profile: profile, repSpines: repSpines, gapFindings: gaps,
                            onCallComplete: callComplete
                        )
                    case .v9_enrichedDynamic:
                        return await Self.runV9(
                            model: model, enrichedInventory: inventory, positionalMetadata: posMetadata,
                            channelId: channelId, profile: profile, throughlines: throughlines, gapFindings: gaps,
                            fetchSpines: fetchSpines, onCallComplete: callComplete
                        )
                    case .v10_enrichedDynamicContent:
                        return await Self.runV10(
                            model: model, enrichedInventory: inventory, positionalMetadata: posMetadata,
                            channelId: channelId, profile: profile, throughlines: throughlines, gapFindings: gaps,
                            fetchSpines: fetchSpines, onCallComplete: callComplete
                        )
                    case .v11_freshFourStep:
                        return await Self.runV11(
                            model: model, enrichedInventory: inventory,
                            channelId: channelId, profile: profile, repSpines: repSpines, gapFindings: gaps,
                            onCallComplete: callComplete
                        )
                    case .v12_freshDynamicContent:
                        return await Self.runV12(
                            model: model, enrichedInventory: inventory,
                            channelId: channelId, profile: profile, throughlines: throughlines, gapFindings: gaps,
                            fetchSpines: fetchSpines, onCallComplete: callComplete
                        )
                    default:
                        fatalError("Unexpected V-path: \(path)")
                    }
                }
            }

            for await result in group {
                results.append(result)
                pathComplete?(result.path, result.status)
            }
        }

        return (results.sorted { $0.path.rawValue < $1.path.rawValue }, preprocessingCalls)
    }

    // MARK: - Helpers

    /// Create a dummy YouTubeVideo for spine parsing.
    private static func dummyVideo(rawRambling: String, channelId: String, pathLabel: String) -> YouTubeVideo {
        YouTubeVideo(
            videoId: "arc-\(pathLabel)-\(UUID().uuidString.prefix(8))",
            channelId: channelId,
            title: "Arc Comparison — \(pathLabel)",
            description: "",
            publishedAt: Date(),
            duration: "PT0S",
            thumbnailUrl: "",
            stats: VideoStats(viewCount: 0, likeCount: 0, commentCount: 0),
            createdAt: Date(),
            transcript: rawRambling
        )
    }

    /// Make a single LLM call and return the call record.
    private static func makeLLMCall(
        adapter: ClaudeModelAdapter,
        systemPrompt: String,
        userPrompt: String,
        callIndex: Int,
        callLabel: String,
        path: ArcPath,
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathCall {
        let start = CFAbsoluteTimeGetCurrent()

        let bundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 16000]
        )

        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let responseText = bundle?.content ?? ""
        let telemetry = bundle.map { SectionTelemetry(from: $0) }

        let call = ArcPathCall(
            callIndex: callIndex,
            callLabel: callLabel,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            rawResponse: responseText,
            outputText: responseText,
            telemetry: telemetry,
            durationMs: elapsed
        )

        onCallComplete?(path, callLabel)
        return call
    }

    /// Parse the final call response as a NarrativeSpine.
    private static func parseSpine(from text: String, video: YouTubeVideo) -> NarrativeSpine? {
        do {
            return try NarrativeSpinePromptEngine.parseResponse(text, video: video)
        } catch {
            print("[ArcRunner] Spine parse failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Path 1: Single Pass

    nonisolated static func runP1(
        model: AIModel,
        rawRambling: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        repSpines: [NarrativeSpine],
        gapFindings: [GapFinding] = [],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .p1_singlePass)
        result.status = .running

        let prompts = ArcComparisonPromptEngine.p1SinglePass(
            rawRambling: rawRambling,
            profile: profile,
            representativeSpines: repSpines,
            gapFindings: gapFindings
        )

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            callIndex: 0,
            callLabel: "Spine Generation",
            path: .p1_singlePass,
            onCallComplete: onCallComplete
        )
        result.calls.append(call)
        result.rawSpineText = call.rawResponse

        let video = dummyVideo(rawRambling: rawRambling, channelId: channelId, pathLabel: "P1")
        result.outputSpine = parseSpine(from: call.rawResponse, video: video)
        result.status = result.outputSpine != nil ? .completed : .failed
        if result.outputSpine == nil {
            result.errorMessage = "Failed to parse spine from LLM response"
        }
        result.finalize()
        return result
    }

    // MARK: - Path 2: Content-First

    nonisolated static func runP2(
        model: AIModel,
        rawRambling: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        repSpines: [NarrativeSpine],
        gapFindings: [GapFinding] = [],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .p2_contentFirst)
        result.status = .running

        // Call 1: Content Inventory
        let inventoryPrompts = ArcComparisonPromptEngine.contentInventoryPrompt(rawRambling: rawRambling, gapFindings: gapFindings)
        let inventoryCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: inventoryPrompts.system,
            userPrompt: inventoryPrompts.user,
            callIndex: 0,
            callLabel: "Content Inventory",
            path: .p2_contentFirst,
            onCallComplete: onCallComplete
        )
        result.calls.append(inventoryCall)
        result.intermediateOutputs["contentInventory"] = inventoryCall.rawResponse

        guard !inventoryCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Content inventory call returned empty response"
            result.finalize()
            return result
        }

        // Call 2: Spine Construction
        let spinePrompts = ArcComparisonPromptEngine.p2SpineConstruction(
            contentInventory: inventoryCall.rawResponse,
            profile: profile,
            representativeSpines: repSpines,
            gapFindings: gapFindings
        )
        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: spinePrompts.user,
            callIndex: 1,
            callLabel: "Spine Construction",
            path: .p2_contentFirst,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: rawRambling, channelId: channelId, pathLabel: "P2")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)
        result.status = result.outputSpine != nil ? .completed : .failed
        if result.outputSpine == nil {
            result.errorMessage = "Failed to parse spine from LLM response"
        }
        result.finalize()
        return result
    }

    // MARK: - Path 3: Four-Step Pipeline

    nonisolated static func runP3(
        model: AIModel,
        rawRambling: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        repSpines: [NarrativeSpine],
        gapFindings: [GapFinding] = [],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .p3_fourStepPipeline)
        result.status = .running

        // Call 1: Content Inventory
        let inventoryPrompts = ArcComparisonPromptEngine.contentInventoryPrompt(rawRambling: rawRambling, gapFindings: gapFindings)
        let inventoryCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: inventoryPrompts.system,
            userPrompt: inventoryPrompts.user,
            callIndex: 0,
            callLabel: "Content Inventory",
            path: .p3_fourStepPipeline,
            onCallComplete: onCallComplete
        )
        result.calls.append(inventoryCall)
        result.intermediateOutputs["contentInventory"] = inventoryCall.rawResponse

        guard !inventoryCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Content inventory call returned empty response"
            result.finalize()
            return result
        }

        // Call 2: Causal Thread
        let threadPrompts = ArcComparisonPromptEngine.p3CausalThread(contentInventory: inventoryCall.rawResponse)
        let threadCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: threadPrompts.system,
            userPrompt: threadPrompts.user,
            callIndex: 1,
            callLabel: "Causal Thread",
            path: .p3_fourStepPipeline,
            onCallComplete: onCallComplete
        )
        result.calls.append(threadCall)
        result.intermediateOutputs["causalThread"] = threadCall.rawResponse

        guard !threadCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Causal thread call returned empty response"
            result.finalize()
            return result
        }

        // Call 3: Structural Plan
        let planPrompts = ArcComparisonPromptEngine.p3StructuralPlan(
            causalThread: threadCall.rawResponse,
            contentInventory: inventoryCall.rawResponse,
            profile: profile,
            gapFindings: gapFindings
        )
        let planCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: planPrompts.system,
            userPrompt: planPrompts.user,
            callIndex: 2,
            callLabel: "Structural Plan",
            path: .p3_fourStepPipeline,
            onCallComplete: onCallComplete
        )
        result.calls.append(planCall)
        result.intermediateOutputs["structuralPlan"] = planCall.rawResponse

        guard !planCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Structural plan call returned empty response"
            result.finalize()
            return result
        }

        // Call 4: Full Spine
        let spinePrompts = ArcComparisonPromptEngine.p3FullSpine(
            structuralPlan: planCall.rawResponse,
            contentInventory: inventoryCall.rawResponse,
            representativeSpines: repSpines,
            gapFindings: gapFindings
        )
        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: spinePrompts.user,
            callIndex: 3,
            callLabel: "Full Spine",
            path: .p3_fourStepPipeline,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: rawRambling, channelId: channelId, pathLabel: "P3")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)
        result.status = result.outputSpine != nil ? .completed : .failed
        if result.outputSpine == nil {
            result.errorMessage = "Failed to parse spine from LLM response"
        }
        result.finalize()
        return result
    }

    // MARK: - Path 4: Dynamic Example Selection

    nonisolated static func runP4(
        model: AIModel,
        rawRambling: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        throughlines: [(videoId: String, throughline: String)],
        gapFindings: [GapFinding] = [],
        fetchSpines: ([String]) async -> [NarrativeSpine],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .p4_dynamicSelection)
        result.status = .running

        // Call 1: Example Selection
        let selectPrompts = ArcComparisonPromptEngine.p4ExampleSelection(
            rawRambling: rawRambling,
            allThroughlines: throughlines,
            signatures: profile.signatureAggregation.clusteredSignatures,
            gapFindings: gapFindings
        )
        let selectCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: selectPrompts.system,
            userPrompt: selectPrompts.user,
            callIndex: 0,
            callLabel: "Example Selection",
            path: .p4_dynamicSelection,
            onCallComplete: onCallComplete
        )
        result.calls.append(selectCall)

        let selectedIds = ArcComparisonPromptEngine.parseExampleSelection(selectCall.rawResponse)
        result.intermediateOutputs["selectedExampleIds"] = selectedIds.joined(separator: ", ")
        result.intermediateOutputs["selectionResponse"] = selectCall.rawResponse

        guard !selectedIds.isEmpty else {
            result.status = .failed
            result.errorMessage = "Example selection returned no videoIds"
            result.finalize()
            return result
        }

        // Fetch full spines for selected examples
        let selectedSpines = await fetchSpines(selectedIds)
        result.intermediateOutputs["selectedSpineCount"] = "\(selectedSpines.count) of \(selectedIds.count) requested"

        guard !selectedSpines.isEmpty else {
            result.status = .failed
            result.errorMessage = "Could not fetch any of the selected spines from Firebase"
            result.finalize()
            return result
        }

        // Call 2: Spine Construction with selected examples
        let spinePrompts = ArcComparisonPromptEngine.p4SpineConstruction(
            rawRambling: rawRambling,
            profile: profile,
            selectedSpines: selectedSpines,
            gapFindings: gapFindings
        )
        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: spinePrompts.user,
            callIndex: 1,
            callLabel: "Spine Construction",
            path: .p4_dynamicSelection,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: rawRambling, channelId: channelId, pathLabel: "P4")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)
        result.status = result.outputSpine != nil ? .completed : .failed
        if result.outputSpine == nil {
            result.errorMessage = "Failed to parse spine from LLM response"
        }
        result.finalize()
        return result
    }

    // MARK: - Path 5: Dynamic + Content-First

    nonisolated static func runP5(
        model: AIModel,
        rawRambling: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        throughlines: [(videoId: String, throughline: String)],
        gapFindings: [GapFinding] = [],
        fetchSpines: ([String]) async -> [NarrativeSpine],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .p5_dynamicContentFirst)
        result.status = .running

        // Call 1: Content Inventory
        let inventoryPrompts = ArcComparisonPromptEngine.contentInventoryPrompt(rawRambling: rawRambling, gapFindings: gapFindings)
        let inventoryCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: inventoryPrompts.system,
            userPrompt: inventoryPrompts.user,
            callIndex: 0,
            callLabel: "Content Inventory",
            path: .p5_dynamicContentFirst,
            onCallComplete: onCallComplete
        )
        result.calls.append(inventoryCall)
        result.intermediateOutputs["contentInventory"] = inventoryCall.rawResponse

        guard !inventoryCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Content inventory call returned empty response"
            result.finalize()
            return result
        }

        // Call 2: Example Selection (from inventory, not raw rambling)
        let selectPrompts = ArcComparisonPromptEngine.p5ExampleSelection(
            contentInventory: inventoryCall.rawResponse,
            allThroughlines: throughlines,
            signatures: profile.signatureAggregation.clusteredSignatures,
            gapFindings: gapFindings
        )
        let selectCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: selectPrompts.system,
            userPrompt: selectPrompts.user,
            callIndex: 1,
            callLabel: "Example Selection",
            path: .p5_dynamicContentFirst,
            onCallComplete: onCallComplete
        )
        result.calls.append(selectCall)

        let selectedIds = ArcComparisonPromptEngine.parseExampleSelection(selectCall.rawResponse)
        result.intermediateOutputs["selectedExampleIds"] = selectedIds.joined(separator: ", ")
        result.intermediateOutputs["selectionResponse"] = selectCall.rawResponse

        guard !selectedIds.isEmpty else {
            result.status = .failed
            result.errorMessage = "Example selection returned no videoIds"
            result.finalize()
            return result
        }

        // Fetch full spines for selected examples
        let selectedSpines = await fetchSpines(selectedIds)
        result.intermediateOutputs["selectedSpineCount"] = "\(selectedSpines.count) of \(selectedIds.count) requested"

        guard !selectedSpines.isEmpty else {
            result.status = .failed
            result.errorMessage = "Could not fetch any of the selected spines from Firebase"
            result.finalize()
            return result
        }

        // Call 3: Spine Construction
        let spinePrompts = ArcComparisonPromptEngine.p5SpineConstruction(
            contentInventory: inventoryCall.rawResponse,
            profile: profile,
            selectedSpines: selectedSpines,
            gapFindings: gapFindings
        )
        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: spinePrompts.user,
            callIndex: 2,
            callLabel: "Spine Construction",
            path: .p5_dynamicContentFirst,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: rawRambling, channelId: channelId, pathLabel: "P5")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)
        result.status = result.outputSpine != nil ? .completed : .failed
        if result.outputSpine == nil {
            result.errorMessage = "Failed to parse spine from LLM response"
        }
        result.finalize()
        return result
    }

    // MARK: - Shared Preprocessing Helpers

    /// Strip Q/A framing from supplemental text and filter meta-statements.
    /// Uses parseQABlocks() to parse, then filters out meta-statements and strips markers.
    nonisolated static func stripQAFraming(_ supplementalText: String) -> String {
        let qaBlocks = parseQABlocks(supplementalText)
        guard !qaBlocks.isEmpty else { return supplementalText }

        // Meta-statement patterns — these are about the script, not creator speech
        let metaPatterns = [
            "the script says",
            "the script doesn't",
            "the script doesn't",  // curly apostrophe variant
            "the script describes",
            "partially answered"
        ]

        var cleanedParagraphs: [String] = []
        var droppedCount = 0

        for qa in qaBlocks {
            let answerLower = qa.answer.lowercased()
            let isMeta = metaPatterns.contains { answerLower.contains($0) }
            if isMeta {
                droppedCount += 1
                print("[stripQAFraming] Dropped meta-statement: \"\(qa.answer.prefix(60))...\"")
                continue
            }
            // Strip any leading "A:" or "A: " prefix
            var cleaned = qa.answer
            if cleaned.hasPrefix("A: ") { cleaned = String(cleaned.dropFirst(3)) }
            else if cleaned.hasPrefix("A:") { cleaned = String(cleaned.dropFirst(2)) }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                cleanedParagraphs.append(cleaned)
            }
        }

        print("[stripQAFraming] Kept \(cleanedParagraphs.count)/\(qaBlocks.count) blocks (\(droppedCount) meta-statements dropped)")
        return cleanedParagraphs.joined(separator: "\n\n")
    }

    /// Merge two numbered content inventories. Base atoms keep 1–N, supplemental atoms become (N+1)–(N+M)
    /// with [SUP] prefix tags. Returns the merged string and the supplemental atom number range.
    nonisolated static func mergeInventories(
        base: String,
        supplemental: String
    ) -> (merged: String, supplementalRange: ClosedRange<Int>) {
        // Parse base atoms (strip existing numbering)
        let baseAtoms = parseNumberedList(base)
        let suppAtoms = parseNumberedList(supplemental)

        let baseCount = baseAtoms.count
        let suppCount = suppAtoms.count

        var lines: [String] = []

        // Base atoms: 1–N
        for (i, atom) in baseAtoms.enumerated() {
            lines.append("\(i + 1). \(atom)")
        }

        // Supplemental atoms: (N+1)–(N+M) with [SUP] tag
        for (i, atom) in suppAtoms.enumerated() {
            lines.append("\(baseCount + i + 1). [SUP] \(atom)")
        }

        let supplementalStart = baseCount + 1
        let supplementalEnd = baseCount + max(suppCount, 1)
        let range = supplementalStart...supplementalEnd

        print("[mergeInventories] Base: \(baseCount) atoms, Supplemental: \(suppCount) atoms, Total: \(baseCount + suppCount), Range: \(range)")

        return (lines.joined(separator: "\n"), range)
    }

    /// Parse a numbered list into individual text items (strip number prefix).
    private nonisolated static func parseNumberedList(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line -> String? in
                if let range = line.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                    let atom = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return atom.isEmpty ? nil : atom
                }
                return line  // non-numbered line, keep as-is
            }
    }

    /// Parse supplemental text into ordered Q&A blocks by splitting on [Q: ...] markers.
    private nonisolated static func parseQABlocks(_ text: String) -> [(question: String, answer: String)] {
        var blocks: [(question: String, answer: String)] = []
        let lines = text.components(separatedBy: "\n")
        var currentQuestion: String?
        var answerLines: [String] = []

        for line in lines {
            if line.hasPrefix("[Q: ") && line.hasSuffix("]") {
                // Save previous Q&A block
                if let q = currentQuestion {
                    let answer = answerLines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !answer.isEmpty {
                        blocks.append((question: q, answer: answer))
                    }
                }
                // Start new block
                currentQuestion = String(line.dropFirst(4).dropLast(1))
                answerLines = []
            } else {
                answerLines.append(line)
            }
        }
        // Save final block
        if let q = currentQuestion {
            let answer = answerLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty {
                blocks.append((question: q, answer: answer))
            }
        }

        return blocks
    }

    /// Parse a beat position number from a gap finding's location string (e.g. "Between beats 3 and 4" → 3).
    private nonisolated static func parseBeatPosition(from location: String) -> Int {
        // Match patterns like "Between beats 3 and 4", "After beat 5", "Before beat 2"
        let patterns = [
            #"[Bb]etween beats? (\d+)"#,
            #"[Aa]fter beat (\d+)"#,
            #"[Bb]efore beat (\d+)"#,
            #"[Bb]eat (\d+)"#
        ]
        for pattern in patterns {
            if let match = location.range(of: pattern, options: .regularExpression) {
                let digits = location[match].filter(\.isNumber)
                if let num = Int(String(digits.prefix(3))) {
                    return num
                }
            }
        }
        return 999  // unknown position sorts to end
    }

    // MARK: - Shared Gap Validation (Stage 3 for V6–V10)

    /// Run post-hoc gap coverage validation for a completed spine.
    nonisolated static func runGapValidation(
        model: AIModel,
        spine: NarrativeSpine,
        gapFindings: [GapFinding],
        callIndex: Int,
        path: ArcPath,
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> (result: GapCoverageResult, call: ArcPathCall) {
        let adapter = ClaudeModelAdapter(model: model)

        let highFindings = gapFindings.filter { $0.priority == .high }
        guard !highFindings.isEmpty else {
            let emptyResult = GapCoverageResult(
                coveredGapIds: [],
                uncoveredGapIds: [],
                coverageSummary: "No HIGH-priority gaps to validate."
            )
            let dummyCall = ArcPathCall(
                callIndex: callIndex,
                callLabel: "Gap Validation",
                systemPrompt: "",
                userPrompt: "[Skipped — no HIGH-priority gaps]",
                rawResponse: "",
                outputText: "",
                telemetry: nil,
                durationMs: 0
            )
            return (emptyResult, dummyCall)
        }

        let prompts = ArcComparisonPromptEngine.gapCoverageValidationPrompt(
            spine: spine,
            highPriorityFindings: highFindings
        )

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            callIndex: callIndex,
            callLabel: "Gap Validation",
            path: path,
            onCallComplete: onCallComplete
        )

        let allGapIds = highFindings.map(\.id)
        let coverageResult = ArcComparisonPromptEngine.parseGapCoverageValidation(
            call.rawResponse,
            allGapIds: allGapIds
        )

        return (coverageResult, call)
    }

    // MARK: - Path V6: Inventory-Based Single Pass (+ positional metadata)

    nonisolated static func runV6(
        model: AIModel,
        enrichedInventory: String,
        positionalMetadata: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        repSpines: [NarrativeSpine],
        gapFindings: [GapFinding],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .v6_enrichedSinglePass)
        result.status = .running
        result.intermediateOutputs["contentInventory"] = enrichedInventory

        // Spine construction from enriched inventory (switched from p1SinglePass to p2SpineConstruction)
        let prompts = ArcComparisonPromptEngine.p2SpineConstruction(
            contentInventory: enrichedInventory,
            profile: profile,
            representativeSpines: repSpines
        )
        // Append positional metadata so the planner knows where [SUP] atoms belong
        let enrichedUser = positionalMetadata.isEmpty ? prompts.user : prompts.user + "\n\n" + positionalMetadata

        let call = await makeLLMCall(
            adapter: adapter,
            systemPrompt: prompts.system,
            userPrompt: enrichedUser,
            callIndex: 0,
            callLabel: "Spine Construction",
            path: .v6_enrichedSinglePass,
            onCallComplete: onCallComplete
        )
        result.calls.append(call)
        result.rawSpineText = call.rawResponse

        let video = dummyVideo(rawRambling: enrichedInventory, channelId: channelId, pathLabel: "V6")
        result.outputSpine = parseSpine(from: call.rawResponse, video: video)

        guard result.outputSpine != nil else {
            result.status = .failed
            result.errorMessage = "Failed to parse spine from LLM response"
            result.finalize()
            return result
        }

        // Gap validation
        let (coverageResult, validationCall) = await runGapValidation(
            model: model, spine: result.outputSpine!, gapFindings: gapFindings, callIndex: 1,
            path: .v6_enrichedSinglePass, onCallComplete: onCallComplete
        )
        result.calls.append(validationCall)
        result.gapValidationResult = coverageResult
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - Path V7: Inventory-Based Content-First (+ positional metadata)

    nonisolated static func runV7(
        model: AIModel,
        enrichedInventory: String,
        positionalMetadata: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        repSpines: [NarrativeSpine],
        gapFindings: [GapFinding],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .v7_enrichedContentFirst)
        result.status = .running
        result.intermediateOutputs["contentInventory"] = enrichedInventory

        // Call 1: Spine Construction from shared enriched inventory + positional metadata
        let spinePrompts = ArcComparisonPromptEngine.p2SpineConstruction(
            contentInventory: enrichedInventory,
            profile: profile,
            representativeSpines: repSpines
        )
        let enrichedUser = positionalMetadata.isEmpty ? spinePrompts.user : spinePrompts.user + "\n\n" + positionalMetadata

        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: enrichedUser,
            callIndex: 0,
            callLabel: "Spine Construction",
            path: .v7_enrichedContentFirst,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: enrichedInventory, channelId: channelId, pathLabel: "V7")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)

        guard result.outputSpine != nil else {
            result.status = .failed
            result.errorMessage = "Failed to parse spine from LLM response"
            result.finalize()
            return result
        }

        // Call 2: Gap Validation
        let (coverageResult, validationCall) = await runGapValidation(
            model: model, spine: result.outputSpine!, gapFindings: gapFindings, callIndex: 1,
            path: .v7_enrichedContentFirst, onCallComplete: onCallComplete
        )
        result.calls.append(validationCall)
        result.gapValidationResult = coverageResult
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - Path V8: Inventory-Based Four-Step (+ positional metadata on plan)

    nonisolated static func runV8(
        model: AIModel,
        enrichedInventory: String,
        positionalMetadata: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        repSpines: [NarrativeSpine],
        gapFindings: [GapFinding],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .v8_enrichedFourStep)
        result.status = .running
        result.intermediateOutputs["contentInventory"] = enrichedInventory

        // Call 1: Causal Thread (from shared enriched inventory)
        let threadPrompts = ArcComparisonPromptEngine.p3CausalThread(contentInventory: enrichedInventory)
        let threadCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: threadPrompts.system,
            userPrompt: threadPrompts.user,
            callIndex: 0,
            callLabel: "Causal Thread",
            path: .v8_enrichedFourStep,
            onCallComplete: onCallComplete
        )
        result.calls.append(threadCall)
        result.intermediateOutputs["causalThread"] = threadCall.rawResponse

        guard !threadCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Causal thread call returned empty response"
            result.finalize()
            return result
        }

        // Call 2: Structural Plan (+ positional metadata so planner places [SUP] atoms correctly)
        let planPrompts = ArcComparisonPromptEngine.p3StructuralPlan(
            causalThread: threadCall.rawResponse,
            contentInventory: enrichedInventory,
            profile: profile
        )
        let planUser = positionalMetadata.isEmpty ? planPrompts.user : planPrompts.user + "\n\n" + positionalMetadata
        let planCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: planPrompts.system,
            userPrompt: planUser,
            callIndex: 1,
            callLabel: "Structural Plan",
            path: .v8_enrichedFourStep,
            onCallComplete: onCallComplete
        )
        result.calls.append(planCall)
        result.intermediateOutputs["structuralPlan"] = planCall.rawResponse

        guard !planCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Structural plan call returned empty response"
            result.finalize()
            return result
        }

        // Call 3: Full Spine
        let spinePrompts = ArcComparisonPromptEngine.p3FullSpine(
            structuralPlan: planCall.rawResponse,
            contentInventory: enrichedInventory,
            representativeSpines: repSpines
        )
        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: spinePrompts.user,
            callIndex: 2,
            callLabel: "Full Spine",
            path: .v8_enrichedFourStep,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: enrichedInventory, channelId: channelId, pathLabel: "V8")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)

        guard result.outputSpine != nil else {
            result.status = .failed
            result.errorMessage = "Failed to parse spine from LLM response"
            result.finalize()
            return result
        }

        // Call 4: Gap Validation
        let (coverageResult, validationCall) = await runGapValidation(
            model: model, spine: result.outputSpine!, gapFindings: gapFindings, callIndex: 3,
            path: .v8_enrichedFourStep, onCallComplete: onCallComplete
        )
        result.calls.append(validationCall)
        result.gapValidationResult = coverageResult
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - Path V9: Inventory-Based Dynamic Selection (+ positional metadata)

    nonisolated static func runV9(
        model: AIModel,
        enrichedInventory: String,
        positionalMetadata: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        throughlines: [(videoId: String, throughline: String)],
        gapFindings: [GapFinding],
        fetchSpines: ([String]) async -> [NarrativeSpine],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .v9_enrichedDynamic)
        result.status = .running
        result.intermediateOutputs["contentInventory"] = enrichedInventory

        // Call 1: Example Selection (from inventory, using P5-style inventory-based prompt)
        let selectPrompts = ArcComparisonPromptEngine.p5ExampleSelection(
            contentInventory: enrichedInventory,
            allThroughlines: throughlines,
            signatures: profile.signatureAggregation.clusteredSignatures
        )
        let selectCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: selectPrompts.system,
            userPrompt: selectPrompts.user,
            callIndex: 0,
            callLabel: "Example Selection",
            path: .v9_enrichedDynamic,
            onCallComplete: onCallComplete
        )
        result.calls.append(selectCall)

        let selectedIds = ArcComparisonPromptEngine.parseExampleSelection(selectCall.rawResponse)
        result.intermediateOutputs["selectedExampleIds"] = selectedIds.joined(separator: ", ")
        result.intermediateOutputs["selectionResponse"] = selectCall.rawResponse

        guard !selectedIds.isEmpty else {
            result.status = .failed
            result.errorMessage = "Example selection returned no videoIds"
            result.finalize()
            return result
        }

        let selectedSpines = await fetchSpines(selectedIds)
        result.intermediateOutputs["selectedSpineCount"] = "\(selectedSpines.count) of \(selectedIds.count) requested"

        guard !selectedSpines.isEmpty else {
            result.status = .failed
            result.errorMessage = "Could not fetch any of the selected spines from Firebase"
            result.finalize()
            return result
        }

        // Call 2: Spine Construction (P5-style inventory prompt + positional metadata)
        let spinePrompts = ArcComparisonPromptEngine.p5SpineConstruction(
            contentInventory: enrichedInventory,
            profile: profile,
            selectedSpines: selectedSpines
        )
        let enrichedUser = positionalMetadata.isEmpty ? spinePrompts.user : spinePrompts.user + "\n\n" + positionalMetadata

        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: enrichedUser,
            callIndex: 1,
            callLabel: "Spine Construction",
            path: .v9_enrichedDynamic,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: enrichedInventory, channelId: channelId, pathLabel: "V9")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)

        guard result.outputSpine != nil else {
            result.status = .failed
            result.errorMessage = "Failed to parse spine from LLM response"
            result.finalize()
            return result
        }

        // Call 3: Gap Validation
        let (coverageResult, validationCall) = await runGapValidation(
            model: model, spine: result.outputSpine!, gapFindings: gapFindings, callIndex: 2,
            path: .v9_enrichedDynamic, onCallComplete: onCallComplete
        )
        result.calls.append(validationCall)
        result.gapValidationResult = coverageResult
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - Path V10: Inventory-Based Dynamic + Content-First (+ positional metadata)

    nonisolated static func runV10(
        model: AIModel,
        enrichedInventory: String,
        positionalMetadata: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        throughlines: [(videoId: String, throughline: String)],
        gapFindings: [GapFinding],
        fetchSpines: ([String]) async -> [NarrativeSpine],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .v10_enrichedDynamicContent)
        result.status = .running
        result.intermediateOutputs["contentInventory"] = enrichedInventory

        // Call 1: Example Selection (from shared enriched inventory)
        let selectPrompts = ArcComparisonPromptEngine.p5ExampleSelection(
            contentInventory: enrichedInventory,
            allThroughlines: throughlines,
            signatures: profile.signatureAggregation.clusteredSignatures
        )
        let selectCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: selectPrompts.system,
            userPrompt: selectPrompts.user,
            callIndex: 0,
            callLabel: "Example Selection",
            path: .v10_enrichedDynamicContent,
            onCallComplete: onCallComplete
        )
        result.calls.append(selectCall)

        let selectedIds = ArcComparisonPromptEngine.parseExampleSelection(selectCall.rawResponse)
        result.intermediateOutputs["selectedExampleIds"] = selectedIds.joined(separator: ", ")
        result.intermediateOutputs["selectionResponse"] = selectCall.rawResponse

        guard !selectedIds.isEmpty else {
            result.status = .failed
            result.errorMessage = "Example selection returned no videoIds"
            result.finalize()
            return result
        }

        let selectedSpines = await fetchSpines(selectedIds)
        result.intermediateOutputs["selectedSpineCount"] = "\(selectedSpines.count) of \(selectedIds.count) requested"

        guard !selectedSpines.isEmpty else {
            result.status = .failed
            result.errorMessage = "Could not fetch any of the selected spines from Firebase"
            result.finalize()
            return result
        }

        // Call 2: Spine Construction (+ positional metadata)
        let spinePrompts = ArcComparisonPromptEngine.p5SpineConstruction(
            contentInventory: enrichedInventory,
            profile: profile,
            selectedSpines: selectedSpines
        )
        let enrichedUser = positionalMetadata.isEmpty ? spinePrompts.user : spinePrompts.user + "\n\n" + positionalMetadata

        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: enrichedUser,
            callIndex: 1,
            callLabel: "Spine Construction",
            path: .v10_enrichedDynamicContent,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: enrichedInventory, channelId: channelId, pathLabel: "V10")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)

        guard result.outputSpine != nil else {
            result.status = .failed
            result.errorMessage = "Failed to parse spine from LLM response"
            result.finalize()
            return result
        }

        // Call 3: Gap Validation
        let (coverageResult, validationCall) = await runGapValidation(
            model: model, spine: result.outputSpine!, gapFindings: gapFindings, callIndex: 2,
            path: .v10_enrichedDynamicContent, onCallComplete: onCallComplete
        )
        result.calls.append(validationCall)
        result.gapValidationResult = coverageResult
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - Path V11: Fresh Four-Step (no positional metadata)

    nonisolated static func runV11(
        model: AIModel,
        enrichedInventory: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        repSpines: [NarrativeSpine],
        gapFindings: [GapFinding],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .v11_freshFourStep)
        result.status = .running
        result.intermediateOutputs["contentInventory"] = enrichedInventory

        // Call 1: Causal Thread (from shared enriched inventory)
        let threadPrompts = ArcComparisonPromptEngine.p3CausalThread(contentInventory: enrichedInventory)
        let threadCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: threadPrompts.system,
            userPrompt: threadPrompts.user,
            callIndex: 0,
            callLabel: "Causal Thread",
            path: .v11_freshFourStep,
            onCallComplete: onCallComplete
        )
        result.calls.append(threadCall)
        result.intermediateOutputs["causalThread"] = threadCall.rawResponse

        guard !threadCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Causal thread call returned empty response"
            result.finalize()
            return result
        }

        // Call 2: Structural Plan (no positional metadata — planner figures out placement)
        let planPrompts = ArcComparisonPromptEngine.p3StructuralPlan(
            causalThread: threadCall.rawResponse,
            contentInventory: enrichedInventory,
            profile: profile
        )
        let planCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: planPrompts.system,
            userPrompt: planPrompts.user,
            callIndex: 1,
            callLabel: "Structural Plan",
            path: .v11_freshFourStep,
            onCallComplete: onCallComplete
        )
        result.calls.append(planCall)
        result.intermediateOutputs["structuralPlan"] = planCall.rawResponse

        guard !planCall.rawResponse.isEmpty else {
            result.status = .failed
            result.errorMessage = "Structural plan call returned empty response"
            result.finalize()
            return result
        }

        // Call 3: Full Spine
        let spinePrompts = ArcComparisonPromptEngine.p3FullSpine(
            structuralPlan: planCall.rawResponse,
            contentInventory: enrichedInventory,
            representativeSpines: repSpines
        )
        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: spinePrompts.user,
            callIndex: 2,
            callLabel: "Full Spine",
            path: .v11_freshFourStep,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: enrichedInventory, channelId: channelId, pathLabel: "V11")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)

        guard result.outputSpine != nil else {
            result.status = .failed
            result.errorMessage = "Failed to parse spine from LLM response"
            result.finalize()
            return result
        }

        // Call 4: Gap Validation
        let (coverageResult, validationCall) = await runGapValidation(
            model: model, spine: result.outputSpine!, gapFindings: gapFindings, callIndex: 3,
            path: .v11_freshFourStep, onCallComplete: onCallComplete
        )
        result.calls.append(validationCall)
        result.gapValidationResult = coverageResult
        result.status = .completed
        result.finalize()
        return result
    }

    // MARK: - Path V12: Fresh Dynamic + Content-First (no positional metadata)

    nonisolated static func runV12(
        model: AIModel,
        enrichedInventory: String,
        channelId: String,
        profile: CreatorNarrativeProfile,
        throughlines: [(videoId: String, throughline: String)],
        gapFindings: [GapFinding],
        fetchSpines: ([String]) async -> [NarrativeSpine],
        onCallComplete: (@Sendable (ArcPath, String) -> Void)? = nil
    ) async -> ArcPathResult {
        let adapter = ClaudeModelAdapter(model: model)
        var result = ArcPathResult(path: .v12_freshDynamicContent)
        result.status = .running
        result.intermediateOutputs["contentInventory"] = enrichedInventory

        // Call 1: Example Selection (from shared enriched inventory)
        let selectPrompts = ArcComparisonPromptEngine.p5ExampleSelection(
            contentInventory: enrichedInventory,
            allThroughlines: throughlines,
            signatures: profile.signatureAggregation.clusteredSignatures
        )
        let selectCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: selectPrompts.system,
            userPrompt: selectPrompts.user,
            callIndex: 0,
            callLabel: "Example Selection",
            path: .v12_freshDynamicContent,
            onCallComplete: onCallComplete
        )
        result.calls.append(selectCall)

        let selectedIds = ArcComparisonPromptEngine.parseExampleSelection(selectCall.rawResponse)
        result.intermediateOutputs["selectedExampleIds"] = selectedIds.joined(separator: ", ")
        result.intermediateOutputs["selectionResponse"] = selectCall.rawResponse

        guard !selectedIds.isEmpty else {
            result.status = .failed
            result.errorMessage = "Example selection returned no videoIds"
            result.finalize()
            return result
        }

        let selectedSpines = await fetchSpines(selectedIds)
        result.intermediateOutputs["selectedSpineCount"] = "\(selectedSpines.count) of \(selectedIds.count) requested"

        guard !selectedSpines.isEmpty else {
            result.status = .failed
            result.errorMessage = "Could not fetch any of the selected spines from Firebase"
            result.finalize()
            return result
        }

        // Call 2: Spine Construction (no positional metadata)
        let spinePrompts = ArcComparisonPromptEngine.p5SpineConstruction(
            contentInventory: enrichedInventory,
            profile: profile,
            selectedSpines: selectedSpines
        )
        let spineCall = await makeLLMCall(
            adapter: adapter,
            systemPrompt: spinePrompts.system,
            userPrompt: spinePrompts.user,
            callIndex: 1,
            callLabel: "Spine Construction",
            path: .v12_freshDynamicContent,
            onCallComplete: onCallComplete
        )
        result.calls.append(spineCall)
        result.rawSpineText = spineCall.rawResponse

        let video = dummyVideo(rawRambling: enrichedInventory, channelId: channelId, pathLabel: "V12")
        result.outputSpine = parseSpine(from: spineCall.rawResponse, video: video)

        guard result.outputSpine != nil else {
            result.status = .failed
            result.errorMessage = "Failed to parse spine from LLM response"
            result.finalize()
            return result
        }

        // Call 3: Gap Validation
        let (coverageResult, validationCall) = await runGapValidation(
            model: model, spine: result.outputSpine!, gapFindings: gapFindings, callIndex: 2,
            path: .v12_freshDynamicContent, onCallComplete: onCallComplete
        )
        result.calls.append(validationCall)
        result.gapValidationResult = coverageResult
        result.status = .completed
        result.finalize()
        return result
    }
}
