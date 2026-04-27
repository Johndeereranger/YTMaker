//
//  SkeletonLabViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/24/26.
//
//  ViewModel for the Skeleton Lab tab.
//  Loads corpus data, rebuilds sections per move type,
//  runs 6 skeleton generation paths, formats copy output.
//

import Foundation

@MainActor
class SkeletonLabViewModel: ObservableObject {

    // MARK: - Dependencies

    let coordinator: MarkovScriptWriterCoordinator

    // MARK: - Data State

    enum DataState: Equatable {
        case needsLoad
        case loading
        case ready
        case error(String)
    }

    @Published var dataState: DataState = .needsLoad
    @Published var loadingProgress = ""

    // MARK: - Configuration

    @Published var config = SkeletonLabConfig()
    @Published var selectedMoveType: String?

    var availableMoveTypes: [String] {
        let moveTypes = Set(coordinator.donorSentences.map(\.moveType))
        return moveTypes.sorted()
    }

    // MARK: - Sections & Matrix

    var sectionsForMove: [StructureWorkbenchViewModel.ReconstructedSection] = []
    var atomMatrix: AtomTransitionMatrix?

    // MARK: - Results

    @Published var results: [SkeletonResult] = []
    @Published var isRunning = false
    @Published var progressMessage = ""

    // MARK: - S5/S6 Prose State

    /// Which skeleton result is currently running S5 prose generation (nil = none)
    @Published var s5RunningForId: UUID?

    /// Which skeleton result is currently running S6 adaptive prose generation (nil = none)
    @Published var s6RunningForId: UUID?

    /// Which skeleton result is currently running S7 phrase-library prose generation (nil = none)
    @Published var s7RunningForId: UUID?

    /// Live progress during S5/S6/S7 prose generation (nil = not running)
    @Published var proseProgress: ProseGenerationProgress?

    /// Lightweight struct for per-sentence progress updates during S5/S6 runs.
    struct ProseGenerationProgress {
        let completedSentences: Int
        let totalSentences: Int
        let totalPromptTokens: Int
        let totalCompletionTokens: Int
        let elapsedMs: Int
        let currentPhase: String
        let replanCount: Int
        let lastSignatureMatch: Bool?
    }

    // MARK: - Init

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Data Loading

    func loadCorpusData() async {
        guard dataState != .loading else { return }

        // If coordinator already has data, skip Firebase load
        if coordinator.donorCorpusState == .loaded {
            loadingProgress = "\(coordinator.donorSentences.count) sentences, \(coordinator.donorProfiles.count) profiles (cached)"
            dataState = .ready
            if selectedMoveType == nil, let first = availableMoveTypes.first {
                selectMoveType(first)
            }
            return
        }

        dataState = .loading
        loadingProgress = "Loading corpus..."

        await coordinator.loadDonorCorpus()

        if case .error(let msg) = coordinator.donorCorpusState {
            dataState = .error(msg)
            return
        }

        loadingProgress = "\(coordinator.donorSentences.count) sentences, \(coordinator.donorProfiles.count) profiles"
        dataState = .ready

        // Auto-select first move type
        if selectedMoveType == nil, let first = availableMoveTypes.first {
            selectMoveType(first)
        }
    }

    // MARK: - Move Type Selection

    func selectMoveType(_ moveType: String) {
        selectedMoveType = moveType
        config.moveType = moveType
        results = []

        // Reconstruct sections
        let moveSentences = coordinator.donorSentences.filter { $0.moveType == moveType }
        var groups: [String: [CreatorSentence]] = [:]
        for sentence in moveSentences {
            let key = "\(sentence.videoId)_\(sentence.sectionIndex)"
            groups[key, default: []].append(sentence)
        }

        sectionsForMove = groups.map { key, sentences in
            let sorted = sentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            let parts = key.split(separator: "_", maxSplits: 1)
            let videoId = parts.count > 0 ? String(parts[0]) : key
            let sectionIdx = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            return StructureWorkbenchViewModel.ReconstructedSection(
                id: key,
                videoId: videoId,
                sectionIndex: sectionIdx,
                sentences: sorted
            )
        }.sorted { $0.id < $1.id }

        // Build atom transition matrix
        atomMatrix = SkeletonGeneratorService.buildAtomTransitionMatrix(from: sectionsForMove)

        // Set target sentence count from profile
        if let profile = coordinator.donorProfiles.first(where: { $0.moveType == moveType }) {
            config.targetSentenceCount = Int(profile.medianSentences)
        }
    }

    // MARK: - Run All Paths

    func runAll() async {
        guard let matrix = atomMatrix, !sectionsForMove.isEmpty else { return }
        isRunning = true
        results = []

        let enabledPaths = SkeletonPath.executionOrder.filter { config.enabledPaths.contains($0) }

        for path in enabledPaths {
            progressMessage = "Running \(path.displayName)..."

            // Add a pending placeholder
            let pending = SkeletonResult(
                id: UUID(),
                path: path,
                createdAt: Date(),
                atoms: [],
                sentenceBreaks: [],
                status: .running,
                durationMs: 0,
                llmCallCount: 0,
                promptTokensTotal: 0,
                completionTokensTotal: 0,
                estimatedCost: 0,
                intermediateOutputs: [:],
                llmCalls: []
            )
            results.append(pending)

            let result = await SkeletonGeneratorService.run(
                path: path,
                matrix: matrix,
                config: config,
                sections: sectionsForMove
            )

            // Replace pending with actual result
            if let idx = results.firstIndex(where: { $0.path == path }) {
                results[idx] = result
            }
        }

        progressMessage = ""
        isRunning = false
    }

    // MARK: - Run Single Path

    func runPath(_ path: SkeletonPath) async {
        guard let matrix = atomMatrix, !sectionsForMove.isEmpty else { return }
        isRunning = true
        progressMessage = "Running \(path.displayName)..."

        let result = await SkeletonGeneratorService.run(
            path: path,
            matrix: matrix,
            config: config,
            sections: sectionsForMove
        )

        if let idx = results.firstIndex(where: { $0.path == path }) {
            results[idx] = result
        } else {
            results.append(result)
        }

        progressMessage = ""
        isRunning = false
    }

    // MARK: - Copy Formatters

    func copyResult(_ result: SkeletonResult) -> String {
        var lines: [String] = []
        lines.append("=== \(result.path.shortName): \(result.path.displayName) ===")
        lines.append("Status: \(result.status.rawValue)")

        if !result.atoms.isEmpty {
            lines.append("Atoms (\(result.atomCount)): \(result.atoms.joined(separator: " -> "))")
            lines.append("Sentences (\(result.sentenceCount)):")

            for (sIdx, sentence) in result.sentences.enumerated() {
                lines.append("  S\(sIdx + 1): \(sentence.joined(separator: " -> "))")
            }
        }

        lines.append("Stats: \(result.llmCallCount) LLM calls | \(result.durationMs)ms | \(String(format: "$%.4f", result.estimatedCost))")

        return lines.joined(separator: "\n")
    }

    func copyAllSkeletons() -> String {
        var lines: [String] = []
        lines.append("=== SKELETON LAB RESULTS ===")
        lines.append("Move: \(config.moveType) | Content: \"\(config.contentInput.prefix(80))\"")
        lines.append("Generated: \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("")

        for result in results {
            lines.append("--- \(result.path.shortName): \(result.path.displayName) ---")
            lines.append(copyResult(result))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func copyAllWithDebug() -> String {
        guard let matrix = atomMatrix else { return copyAllSkeletons() }

        var lines: [String] = []
        lines.append("=== SKELETON LAB RESULTS (FULL DEBUG) ===")
        lines.append("Move: \(config.moveType) | Content: \"\(config.contentInput.prefix(80))\"")
        lines.append("Corpus: \(sectionsForMove.count) sections | Matrix: \(matrix.totalTransitionCount) transitions")
        lines.append("Generated: \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("")

        for result in results {
            lines.append("━━━ \(result.path.shortName): \(result.path.displayName) ━━━")
            lines.append(copyResult(result))
            lines.append("")

            // Intermediate outputs
            if !result.intermediateOutputs.isEmpty {
                lines.append("  INTERMEDIATE OUTPUTS:")
                for (key, value) in result.intermediateOutputs.sorted(by: { $0.key < $1.key }) {
                    lines.append("  [\(key)]")
                    for line in value.components(separatedBy: .newlines) {
                        lines.append("    \(line)")
                    }
                }
                lines.append("")
            }

            // Transition quality
            let quality = result.transitionQuality(matrix: matrix)
            if !quality.isEmpty {
                lines.append("  TRANSITION QUALITY:")
                for pair in quality {
                    let marker = pair.isCrossBoundary ? " [BOUNDARY]" : ""
                    let grade = pair.probability >= 0.1 ? "OK" : pair.probability >= 0.03 ? "WEAK" : "BAD"
                    lines.append("    \(pair.from) -> \(pair.to): \(String(format: "%.1f%%", pair.probability * 100)) [\(grade)]\(marker)")
                }
                lines.append("")
            }

            // LLM calls
            if !result.llmCalls.isEmpty {
                lines.append("  LLM CALLS:")
                for call in result.llmCalls {
                    lines.append("  [\(call.callLabel)] \(call.durationMs)ms | \(call.promptTokens)+\(call.completionTokens) tokens")
                    lines.append("    System: \(call.systemPrompt.prefix(200))...")
                    lines.append("    User: \(call.userPrompt.prefix(200))...")
                    lines.append("    Response: \(call.rawResponse.prefix(300))...")
                }
                lines.append("")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - S5 Prose Generation

    /// Run S5 prose generation for a specific skeleton result.
    /// Assembles a StructuredInputBundle from the skeleton's signatures,
    /// runs sentence-by-sentence generation, validates, and persists to Compare tab.
    func runS5(for result: SkeletonResult) async {
        guard result.status == .completed, !result.atoms.isEmpty else { return }
        guard s5RunningForId == nil else { return }

        s5RunningForId = result.id
        progressMessage = "Assembling S5 inputs for \(result.path.shortName)..."
        proseProgress = ProseGenerationProgress(
            completedSentences: 0,
            totalSentences: result.sentenceCount,
            totalPromptTokens: 0,
            totalCompletionTokens: 0,
            elapsedMs: 0,
            currentPhase: "Assembling S5 inputs...",
            replanCount: 0,
            lastSignatureMatch: nil
        )

        let moveType = config.moveType
        let gists = coordinator.session.ramblingGists

        // Build ApprovedStructuralSpec from the skeleton
        let signatureSequence = result.sentences.map { $0.joined(separator: "|") }
        let rhythmOverrides = signatureSequence.enumerated().map { i, _ in
            ApprovedStructuralSpec.RhythmOverride(
                positionIndex: i,
                wordCountMin: 10,
                wordCountMax: 20,
                clauseCountMin: 1,
                clauseCountMax: 3,
                commonOpeners: []
            )
        }

        let spec = ApprovedStructuralSpec(
            moveType: moveType,
            signatureSequence: signatureSequence,
            rhythmOverrides: rhythmOverrides,
            approachUsed: "skeletonLab",
            sourceDescription: "Skeleton Lab \(result.path.shortName)",
            approvedAt: Date()
        )

        // Resolve RhetoricalMoveType from raw string
        guard let rhetoricalMove = RhetoricalMoveType.parse(moveType) else {
            print("[SkeletonLabVM] ERROR: Could not parse moveType \"\(moveType)\" to RhetoricalMoveType")
            s5RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        // Assemble the bundle — loads donors, rhythm, confusable pairs from Firebase
        guard let creatorId = coordinator.selectedChannelIds.first else {
            print("[SkeletonLabVM] ERROR: No channel selected")
            s5RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        let bundle: StructuredInputBundle
        do {
            progressMessage = "Loading donors for \(result.path.shortName)..."
            bundle = try await StructuredInputAssembler.assemble(
                creatorId: creatorId,
                targetMoveType: rhetoricalMove,
                targetPosition: .first,
                approvedSpec: spec
            )
        } catch {
            print("[SkeletonLabVM] ERROR: Bundle assembly failed: \(error.localizedDescription)")
            s5RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        // Run S5 prose generation
        progressMessage = "Generating S5 prose for \(result.path.shortName)..."
        let s5Result = await SkeletonS5Runner.run(
            skeleton: result,
            bundle: bundle,
            gists: gists,
            topicOverride: config.contentInput,
            onProgress: { [weak self] progress in
                self?.proseProgress = progress
            }
        )

        // Store the result on the skeleton
        if let idx = results.firstIndex(where: { $0.id == result.id }) {
            results[idx].s5ProseResult = s5Result
        }

        // Persist to Compare tab storage
        let comparisonRun = SkeletonS5Runner.wrapAsComparisonRun(s5Result, moveType: moveType)
        do {
            try OpenerComparisonStorage.save(comparisonRun, sessionId: coordinator.session.id)
            print("[SkeletonLabVM] S5 run saved to Compare storage (sessionId=\(coordinator.session.id), runId=\(comparisonRun.id))")
        } catch {
            print("[SkeletonLabVM] WARNING: Failed to save S5 run to Compare storage: \(error.localizedDescription)")
        }

        s5RunningForId = nil
        proseProgress = nil
        progressMessage = ""
    }

    // MARK: - S6 Adaptive Prose Generation

    /// Run S6 adaptive prose generation for a specific skeleton result.
    /// Same bundle assembly as S5, but passes the atom transition matrix
    /// and seed so the runner can re-walk the skeleton on drift.
    func runS6(for result: SkeletonResult) async {
        guard result.status == .completed, !result.atoms.isEmpty else { return }
        guard s6RunningForId == nil else { return }
        guard let matrix = atomMatrix else { return }

        s6RunningForId = result.id
        progressMessage = "Assembling S6 inputs for \(result.path.shortName)..."
        proseProgress = ProseGenerationProgress(
            completedSentences: 0,
            totalSentences: result.sentenceCount,
            totalPromptTokens: 0,
            totalCompletionTokens: 0,
            elapsedMs: 0,
            currentPhase: "Assembling S6 inputs...",
            replanCount: 0,
            lastSignatureMatch: nil
        )

        let moveType = config.moveType
        let gists = coordinator.session.ramblingGists

        // Build ApprovedStructuralSpec from the skeleton
        let signatureSequence = result.sentences.map { $0.joined(separator: "|") }
        let rhythmOverrides = signatureSequence.enumerated().map { i, _ in
            ApprovedStructuralSpec.RhythmOverride(
                positionIndex: i,
                wordCountMin: 10,
                wordCountMax: 20,
                clauseCountMin: 1,
                clauseCountMax: 3,
                commonOpeners: []
            )
        }

        let spec = ApprovedStructuralSpec(
            moveType: moveType,
            signatureSequence: signatureSequence,
            rhythmOverrides: rhythmOverrides,
            approachUsed: "skeletonLab",
            sourceDescription: "Skeleton Lab \(result.path.shortName) (S6 Adaptive)",
            approvedAt: Date()
        )

        // Resolve RhetoricalMoveType from raw string
        guard let rhetoricalMove = RhetoricalMoveType.parse(moveType) else {
            print("[SkeletonLabVM] ERROR: Could not parse moveType \"\(moveType)\" to RhetoricalMoveType")
            s6RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        guard let creatorId = coordinator.selectedChannelIds.first else {
            print("[SkeletonLabVM] ERROR: No channel selected")
            s6RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        let bundle: StructuredInputBundle
        do {
            progressMessage = "Loading donors for \(result.path.shortName) (S6)..."
            bundle = try await StructuredInputAssembler.assemble(
                creatorId: creatorId,
                targetMoveType: rhetoricalMove,
                targetPosition: .first,
                approvedSpec: spec
            )
        } catch {
            print("[SkeletonLabVM] ERROR: Bundle assembly failed: \(error.localizedDescription)")
            s6RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        // Run S6 adaptive prose generation
        progressMessage = "Generating S6 adaptive prose for \(result.path.shortName)..."
        let s6Result = await SkeletonS6Runner.run(
            skeleton: result,
            matrix: matrix,
            bundle: bundle,
            gists: gists,
            seed: config.seed,
            onProgress: { [weak self] progress in
                self?.proseProgress = progress
            }
        )

        // Store the result on the skeleton
        if let idx = results.firstIndex(where: { $0.id == result.id }) {
            results[idx].s6ProseResult = s6Result
        }

        // Persist to Compare tab storage
        let comparisonRun = SkeletonS6Runner.wrapAsComparisonRun(s6Result, moveType: moveType)
        do {
            try OpenerComparisonStorage.save(comparisonRun, sessionId: coordinator.session.id)
            print("[SkeletonLabVM] S6 run saved to Compare storage (sessionId=\(coordinator.session.id), runId=\(comparisonRun.id))")
        } catch {
            print("[SkeletonLabVM] WARNING: Failed to save S6 run to Compare storage: \(error.localizedDescription)")
        }

        s6RunningForId = nil
        proseProgress = nil
        progressMessage = ""
    }

    // MARK: - S7 Phrase-Library Prose Generation

    /// Run S7 phrase-library prose generation for a specific skeleton result.
    /// Same bundle assembly as S5 (for rhythm/word counts), but also passes
    /// the corpus sentences so the runner can build phrase libraries per sentence.
    func runS7(for result: SkeletonResult) async {
        guard result.status == .completed, !result.atoms.isEmpty else { return }
        guard s7RunningForId == nil else { return }

        s7RunningForId = result.id
        progressMessage = "Assembling S7 inputs for \(result.path.shortName)..."
        proseProgress = ProseGenerationProgress(
            completedSentences: 0,
            totalSentences: result.sentenceCount,
            totalPromptTokens: 0,
            totalCompletionTokens: 0,
            elapsedMs: 0,
            currentPhase: "Assembling S7 inputs...",
            replanCount: 0,
            lastSignatureMatch: nil
        )

        let moveType = config.moveType
        let gists = coordinator.session.ramblingGists

        // Build ApprovedStructuralSpec from the skeleton
        let signatureSequence = result.sentences.map { $0.joined(separator: "|") }
        let rhythmOverrides = signatureSequence.enumerated().map { i, _ in
            ApprovedStructuralSpec.RhythmOverride(
                positionIndex: i,
                wordCountMin: 10,
                wordCountMax: 20,
                clauseCountMin: 1,
                clauseCountMax: 3,
                commonOpeners: []
            )
        }

        let spec = ApprovedStructuralSpec(
            moveType: moveType,
            signatureSequence: signatureSequence,
            rhythmOverrides: rhythmOverrides,
            approachUsed: "skeletonLab",
            sourceDescription: "Skeleton Lab \(result.path.shortName) (S7 Phrase-Library)",
            approvedAt: Date()
        )

        // Resolve RhetoricalMoveType from raw string
        guard let rhetoricalMove = RhetoricalMoveType.parse(moveType) else {
            print("[SkeletonLabVM] ERROR: Could not parse moveType \"\(moveType)\" to RhetoricalMoveType")
            s7RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        guard let creatorId = coordinator.selectedChannelIds.first else {
            print("[SkeletonLabVM] ERROR: No channel selected")
            s7RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        let bundle: StructuredInputBundle
        do {
            progressMessage = "Loading donors for \(result.path.shortName) (S7)..."
            bundle = try await StructuredInputAssembler.assemble(
                creatorId: creatorId,
                targetMoveType: rhetoricalMove,
                targetPosition: .first,
                approvedSpec: spec
            )
        } catch {
            print("[SkeletonLabVM] ERROR: Bundle assembly failed: \(error.localizedDescription)")
            s7RunningForId = nil
            proseProgress = nil
            progressMessage = ""
            return
        }

        // Run S7 phrase-library prose generation
        progressMessage = "Generating S7 phrase-library prose for \(result.path.shortName)..."
        let s7Result = await SkeletonS7Runner.run(
            skeleton: result,
            bundle: bundle,
            gists: gists,
            corpusSentences: coordinator.donorSentences,
            moveType: moveType,
            topicOverride: config.contentInput,
            onProgress: { [weak self] progress in
                self?.proseProgress = progress
            }
        )

        // Store the result on the skeleton
        if let idx = results.firstIndex(where: { $0.id == result.id }) {
            results[idx].s7ProseResult = s7Result
        }

        // Persist to Compare tab storage
        let comparisonRun = SkeletonS7Runner.wrapAsComparisonRun(s7Result, moveType: moveType)
        do {
            try OpenerComparisonStorage.save(comparisonRun, sessionId: coordinator.session.id)
            print("[SkeletonLabVM] S7 run saved to Compare storage (sessionId=\(coordinator.session.id), runId=\(comparisonRun.id))")
        } catch {
            print("[SkeletonLabVM] WARNING: Failed to save S7 run to Compare storage: \(error.localizedDescription)")
        }

        s7RunningForId = nil
        proseProgress = nil
        progressMessage = ""
    }
}
