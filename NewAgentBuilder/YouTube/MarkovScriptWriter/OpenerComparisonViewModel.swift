//
//  OpenerComparisonViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//
//  ViewModel for the Opener Comparison tab.
//  Loads Step 1-2 results from UserDefaults, manages run configuration,
//  orchestrates the comparison runner, and handles persistence.
//

import Foundation

@MainActor
class OpenerComparisonViewModel: ObservableObject {

    // MARK: - Dependencies

    let coordinator: MarkovScriptWriterCoordinator

    // MARK: - Configuration

    @Published var selectedModel: AIModel = .claude4Sonnet
    @Published var enabledMethods: Set<OpenerMethod> = [.s5_skeletonDriven]
    @Published var selectedStrategyId: String = "A"
    @Published var selectedMoveType: RhetoricalMoveType = .sceneSet

    // MARK: - Step 1-2 Data (loaded from UserDefaults)

    @Published var matchResult: OpenerMatchResult?
    @Published var gistFilterResult: OpenerGistFilterResult?

    // MARK: - Run State

    @Published var isRunning = false
    @Published var progressMessage = ""
    @Published var methodStatuses: [OpenerMethod: MethodRunStatus] = [:]
    @Published var completedCount = 0
    @Published var totalExpectedCalls = 0

    // MARK: - Structured Input State (for S-methods)

    @Published var structuredBundle: StructuredInputBundle?
    @Published var isLoadingStructuredInputs = false
    @Published var structuredInputError: String?
    @Published var enabledFingerprintTypes: Set<FingerprintPromptType> = Set(FingerprintPromptType.allCases)

    // MARK: - Results

    @Published var currentRun: OpenerComparisonRun?
    @Published var runHistory: [OpenerComparisonRunSummary] = []

    // MARK: - Fidelity Evaluator State

    @Published var fidelityEvaluations: [(label: String, score: FidelityScore, sections: [SectionFidelityResult], slotDebug: [SlotDebugData]?)] = []
    @Published var isEvaluating = false
    @Published var showWeightConfig = false
    @Published var isReEvaluatingHistory = false
    @Published var reEvalProgressMessage = ""

    // MARK: - Persistence Keys (shared with OpenerMatcherView)

    private static let matchResultKey = "OpenerMatcher.LastResult"
    private static let gistFilterKey = "OpenerMatcher.LastGistFilterResult"

    // MARK: - Init

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Load Dependencies

    func loadDependencies() {
        // Load Step 1 result
        if let data = UserDefaults.standard.data(forKey: Self.matchResultKey),
           let saved = try? JSONDecoder().decode(OpenerMatchResult.self, from: data) {
            matchResult = saved
        }

        // Load Step 2 result
        if let data = UserDefaults.standard.data(forKey: Self.gistFilterKey),
           let saved = try? JSONDecoder().decode(OpenerGistFilterResult.self, from: data) {
            gistFilterResult = saved
        }

        // Load run history from storage
        let sessionId = coordinator.session.id
        let runIds = OpenerComparisonStorage.listRunIds(sessionId: sessionId)
        runHistory = runIds.compactMap { runId -> OpenerComparisonRunSummary? in
            guard let run = OpenerComparisonStorage.load(runId: runId, sessionId: sessionId) else { return nil }
            return OpenerComparisonRunSummary(from: run)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Structured Input Loading

    /// Load structured inputs from Firebase for S-methods.
    func loadStructuredInputs() async {
        guard !isLoadingStructuredInputs else { return }
        isLoadingStructuredInputs = true
        structuredInputError = nil
        defer { isLoadingStructuredInputs = false }

        // Determine creatorId from selected channels
        guard let creatorId = coordinator.selectedChannelIds.first else {
            structuredInputError = "No channel selected"
            return
        }

        // Move type from picker, position is always first (openers)
        let targetMove = selectedMoveType
        let targetPosition: FingerprintPosition = .first

        do {
            print("[CompareVM] WHAT: Loading structured inputs — creatorId=\(creatorId) moveType=\(targetMove.rawValue) position=\(targetPosition.rawValue)")
            print("[CompareVM] WHAT: approvedSpec=\(coordinator.approvedStructuralSpec != nil ? "present" : "nil")")
            structuredBundle = try await StructuredInputAssembler.assemble(
                creatorId: creatorId,
                targetMoveType: targetMove,
                targetPosition: targetPosition,
                approvedSpec: coordinator.approvedStructuralSpec
            )
            // Sync enabled fingerprints to what's actually available
            let available = structuredBundle?.availableFingerprintTypes ?? []
            enabledFingerprintTypes = Set(available)
            print("[CompareVM] RESULT: Bundle loaded — \(structuredBundle?.summaryText ?? "nil")")
            print("[CompareVM] RESULT: Available fingerprint types: \(available.map(\.rawValue).sorted().joined(separator: ", "))")
            print("[CompareVM] RESULT: enabledFingerprintTypes count=\(enabledFingerprintTypes.count)")
            if available.isEmpty {
                print("[CompareVM] WHY: Zero fingerprints → S-methods will have no variants to run → they will stay pending")
            }
        } catch {
            print("[CompareVM] ERROR: \(error.localizedDescription)")
            structuredInputError = error.localizedDescription
        }
    }

    /// Whether any enabled method requires structured inputs.
    var hasStructuredMethods: Bool {
        enabledMethods.contains(where: \.isStructured)
    }

    // MARK: - Validation

    var canRun: Bool {
        matchResult != nil && gistFilterResult != nil && !enabledMethods.isEmpty && !isRunning
    }

    var prerequisiteMessage: String? {
        if matchResult == nil { return "Run Step 1 (Opener Match) in the Opener tab first." }
        if gistFilterResult == nil { return "Run Step 2 (Gist Filter) in the Opener tab first." }
        return nil
    }

    var selectedStrategies: [OpenerStrategy] {
        guard let match = matchResult else { return [] }
        return match.strategies.filter { $0.strategyId == selectedStrategyId }
    }

    // MARK: - Run

    func startRun() async {
        guard canRun,
              let match = matchResult,
              let filter = gistFilterResult else { return }

        isRunning = true
        progressMessage = "Starting comparison run..."
        completedCount = 0
        methodStatuses = [:]

        // Auto-load structured inputs if S-methods are enabled and bundle is missing
        if hasStructuredMethods && structuredBundle == nil {
            progressMessage = "Loading structured inputs from Firebase..."
            await loadStructuredInputs()
            guard structuredBundle != nil else {
                progressMessage = "Failed to load structured inputs: \(structuredInputError ?? "unknown error")"
                isRunning = false
                return
            }
        }

        // Initialize statuses
        for method in enabledMethods {
            methodStatuses[method] = .pending
        }

        // Calculate total expected calls (S-methods: per-variant × enabled fingerprint count)
        let fingerprintCount = enabledFingerprintTypes.count
        totalExpectedCalls = enabledMethods.map { method in
            method.isStructured ? method.ownCallCount * fingerprintCount : method.ownCallCount
        }.reduce(0, +)

        var comparisonRun = OpenerComparisonRun(
            modelUsed: selectedModel.rawValue,
            enabledMethods: enabledMethods
        )

        // Run for selected strategy
        let strategies = match.strategies.filter { $0.strategyId == selectedStrategyId }

        for strategy in strategies {
            // Build corpus openings for this strategy's matched videos
            let matchOpenings = buildOpeningsForStrategy(strategy: strategy)
            let filteredGists = resolveFilteredGists(strategy: strategy, filter: filter)

            let runner = OpenerComparisonRunner(
                model: selectedModel,
                strategy: strategy,
                matchOpenings: matchOpenings,
                filteredGists: filteredGists,
                enabledMethods: enabledMethods,
                structuredBundle: structuredBundle,
                enabledFingerprintTypes: enabledFingerprintTypes
            )

            runner.onProgress = { [weak self] message, method, status in
                self?.progressMessage = message
                if let method {
                    self?.methodStatuses[method] = status
                }
                if status == .completed || status == .failed {
                    self?.completedCount += 1
                }
            }

            let strategyRun = await runner.run()
            comparisonRun.strategyRuns.append(strategyRun)
        }

        comparisonRun.finalize()
        currentRun = comparisonRun

        // Persist
        do {
            try OpenerComparisonStorage.save(comparisonRun, sessionId: coordinator.session.id)
            let summary = OpenerComparisonRunSummary(from: comparisonRun)
            runHistory.insert(summary, at: 0)
        } catch {
            print("[OpenerComparison] Failed to save run: \(error.localizedDescription)")
        }

        isRunning = false
        progressMessage = "Run complete. \(comparisonRun.totalCalls) calls, \(String(format: "$%.4f", comparisonRun.totalCost)) estimated cost."
    }

    // MARK: - Load Saved Run

    func loadSavedRun(_ summary: OpenerComparisonRunSummary) {
        guard let run = OpenerComparisonStorage.load(runId: summary.id, sessionId: coordinator.session.id) else {
            progressMessage = "Failed to load run."
            return
        }
        currentRun = run

        // Sync strategy picker to the loaded run's strategy so copy buttons work
        if let firstStrategyId = run.strategyRuns.first?.strategyId {
            selectedStrategyId = firstStrategyId
        }

        // Update method statuses from loaded run
        methodStatuses = [:]
        for stratRun in run.strategyRuns {
            for result in stratRun.methodResults {
                methodStatuses[result.method] = result.status
            }
        }
    }

    // MARK: - Delete Run

    func deleteRun(_ summary: OpenerComparisonRunSummary) {
        OpenerComparisonStorage.delete(runId: summary.id, sessionId: coordinator.session.id)
        runHistory.removeAll { $0.id == summary.id }
        if currentRun?.id == summary.id {
            currentRun = nil
            methodStatuses = [:]
        }
    }

    // MARK: - Copy

    func copyAllOutput() -> String {
        currentRun?.copyAllOutput(strategyId: selectedStrategyId) ?? ""
    }

    func copyAllWithMethodology() -> String {
        currentRun?.copyAllWithMethodology(strategyId: selectedStrategyId) ?? ""
    }

    func copyAllWithMethodologyShort() -> String {
        currentRun?.copyAllWithMethodologyShort(strategyId: selectedStrategyId) ?? ""
    }

    func copyPromptsOnly() -> String {
        currentRun?.copyPromptsOnly(strategyId: selectedStrategyId) ?? ""
    }

    // MARK: - Helpers

    /// Build CorpusOpening arrays for the 2 videos matched to this strategy.
    private func buildOpeningsForStrategy(strategy: OpenerStrategy) -> [OpenerMatcherPromptEngine.CorpusOpening] {
        let videos = coordinator.corpusVideos
        let sequences = coordinator.sequences
        let titles = coordinator.videoTitles

        return strategy.matches.compactMap { match -> OpenerMatcherPromptEngine.CorpusOpening? in
            guard let video = videos[match.videoId],
                  let seq = sequences[match.videoId],
                  let transcript = video.transcript else { return nil }

            let sortedMoves = seq.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            guard !sortedMoves.isEmpty else { return nil }

            let slice = Array(sortedMoves.prefix(2))
            let sentences = SentenceParser.parse(transcript)

            var sectionTexts: [(label: String, text: String)] = []
            let hasAnySentenceBoundaries = slice.contains { $0.startSentence != nil && $0.endSentence != nil }

            if hasAnySentenceBoundaries {
                for move in slice {
                    let label = move.moveType.displayName
                    var textLines: [String] = []
                    if let start = move.startSentence, let end = move.endSentence,
                       !sentences.isEmpty, start < sentences.count {
                        let safeEnd = min(end, sentences.count - 1)
                        for i in start...safeEnd {
                            textLines.append(sentences[i])
                        }
                    } else {
                        textLines.append(move.briefDescription)
                    }
                    sectionTexts.append((label: label, text: textLines.joined(separator: " ")))
                }
            } else {
                let targetWordCount = 150
                var wordsSoFar = 0
                var collectedSentences: [String] = []
                for sentence in sentences {
                    collectedSentences.append(sentence)
                    wordsSoFar += sentence.split(separator: " ").count
                    if wordsSoFar >= targetWordCount { break }
                }
                let moveLabels = slice.map { $0.moveType.displayName }.joined(separator: " -> ")
                sectionTexts.append((label: moveLabels, text: collectedSentences.joined(separator: " ")))
            }

            let title = titles[match.videoId] ?? match.videoTitle
            return OpenerMatcherPromptEngine.CorpusOpening(
                videoId: match.videoId,
                title: title,
                sectionTexts: sectionTexts
            )
        }
    }

    /// Resolve the 2 filtered gists for a strategy from gist filter results.
    private func resolveFilteredGists(strategy: OpenerStrategy, filter: OpenerGistFilterResult) -> [RamblingGist] {
        guard let stratFilter = filter.strategyFilters.first(where: { $0.strategyId == strategy.strategyId }) else {
            return []
        }

        let allGists = coordinator.session.ramblingGists
        return stratFilter.positions.compactMap { position -> RamblingGist? in
            guard let selectedId = position.selectedGistId else { return nil }
            return allGists.first { $0.id == selectedId }
        }
    }

    // MARK: - Fidelity Evaluation

    /// Get S2 slot annotations for a section of text, using disk cache first, then live LLM call.
    /// Returns nil if both cache and LLM fail.
    private func getS2Annotations(for text: String) async -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hash = FidelityStorage.s2TextHash(trimmed)

        // Cache hit — return immediately
        if let cached = FidelityStorage.loadS2Cache(textHash: hash) {
            print("[S2 Cache] HIT for hash \(hash) (\(cached.s2Signatures.count) sigs)")
            return cached.s2Signatures
        }

        // Cache miss — call LLM
        let sentences = SentenceParser.parse(trimmed)
        guard !sentences.isEmpty else { return nil }

        let hints = sentences.map { DeterministicHints.compute(for: $0) }

        do {
            let annotations = try await DonorLibraryA2Service.shared.callSlotAnnotation(
                sentences: sentences,
                hints: hints,
                moveType: selectedMoveType.rawValue,
                category: ""
            )
            let s2Sigs = annotations.map { $0.slotSequence.joined(separator: "|") }

            // Save to cache
            let cachedAnnotations = annotations.enumerated().map { (i, ann) in
                CachedSlotAnnotation(
                    sentenceText: i < sentences.count ? sentences[i] : "",
                    slotSequence: ann.slotSequence,
                    sentenceFunction: ann.sentenceFunction
                )
            }
            let entry = S2CacheEntry(
                textHash: hash,
                sectionText: trimmed,
                s2Signatures: s2Sigs,
                annotations: cachedAnnotations,
                timestamp: Date(),
                modelUsed: "claude4Sonnet"
            )
            FidelityStorage.saveS2Cache(entry)

            print("[S2 Cache] MISS for hash \(hash) — annotated \(s2Sigs.count) sigs via LLM")
            return s2Sigs
        } catch {
            print("[S2 Annotation] LLM call failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Evaluate all completed methods in the current run using persisted cache.
    /// Makes live LLM calls for S2 slot annotations (with disk caching).
    /// Writes scores back into the run's method results and re-saves to disk.
    func evaluateFidelity() async {
        guard var run = currentRun,
              let cache = coordinator.fidelityCache else { return }

        isEvaluating = true
        fidelityEvaluations = []

        // Resolve topic text from gists for prompt spec debug
        let topicText: String? = {
            guard let filter = gistFilterResult,
                  let match = matchResult,
                  let strategy = match.strategies.first(where: { $0.strategyId == selectedStrategyId }) else { return nil }
            let gists = resolveFilteredGists(strategy: strategy, filter: filter)
            return gists.first?.sourceText
        }()

        let weightProfile = coordinator.fidelityWeightProfile
        var scoresByLabel: [String: FidelityScore] = [:]

        let completedResults = run.strategyRuns.flatMap(\.methodResults).filter { $0.status == .completed }

        for result in completedResults {
            // Get S2 annotations (cache-first, then LLM)
            let s2Sigs = await getS2Annotations(for: result.outputText)

            let (score, sections) = ScriptFidelityService.evaluate(
                outputText: result.outputText,
                cache: cache,
                weightProfile: weightProfile,
                s2Signatures: s2Sigs,
                moveType: selectedMoveType.rawValue
            )

            // Build slot debug data for each section
            let parsedSections = ScriptFidelityService.parseScript(result.outputText, moveType: selectedMoveType.rawValue)
            let debugData = parsedSections.map { parsed in
                ScriptFidelityService.buildSlotDebugData(
                    section: parsed,
                    corpusStats: cache.corpusStats,
                    s2Signatures: s2Sigs,
                    bundle: structuredBundle,
                    topicText: topicText
                )
            }

            fidelityEvaluations.append((
                label: result.displayLabel,
                score: score,
                sections: sections,
                slotDebug: debugData
            ))
            scoresByLabel[result.displayLabel] = score
        }

        // Sort by composite score descending
        fidelityEvaluations.sort { $0.score.compositeScore > $1.score.compositeScore }

        // Persist scores back into the run's method results
        for si in run.strategyRuns.indices {
            for mi in run.strategyRuns[si].methodResults.indices {
                let label = run.strategyRuns[si].methodResults[mi].displayLabel
                if let score = scoresByLabel[label] {
                    run.strategyRuns[si].methodResults[mi].fidelityScore = score
                }
            }
        }
        currentRun = run

        do {
            try OpenerComparisonStorage.save(run, sessionId: coordinator.session.id)
            if let idx = runHistory.firstIndex(where: { $0.id == run.id }) {
                runHistory[idx] = OpenerComparisonRunSummary(from: run)
            }
        } catch {
            print("[OpenerComparison] Failed to re-save run after fidelity eval: \(error.localizedDescription)")
        }

        isEvaluating = false
    }

    /// Re-evaluate fidelity for all saved runs in history using current scorer + baseline.
    /// Uses S2 cache only (no live LLM calls) to avoid expensive batch annotation.
    func reEvaluateAllHistory() {
        guard let cache = coordinator.fidelityCache else { return }

        isReEvaluatingHistory = true
        let weightProfile = coordinator.fidelityWeightProfile
        let sessionId = coordinator.session.id
        let runIds = OpenerComparisonStorage.listRunIds(sessionId: sessionId)
        let total = runIds.count

        var updatedSummaries: [OpenerComparisonRunSummary] = []

        for (index, runId) in runIds.enumerated() {
            reEvalProgressMessage = "Evaluating run \(index + 1)/\(total)..."

            guard var run = OpenerComparisonStorage.load(runId: runId, sessionId: sessionId) else {
                continue
            }

            var didChange = false
            for si in run.strategyRuns.indices {
                for mi in run.strategyRuns[si].methodResults.indices {
                    guard run.strategyRuns[si].methodResults[mi].status == .completed,
                          !run.strategyRuns[si].methodResults[mi].outputText.isEmpty else {
                        continue
                    }
                    let outputText = run.strategyRuns[si].methodResults[mi].outputText
                    // Use S2 cache only (no LLM calls) for history re-evaluation
                    let hash = FidelityStorage.s2TextHash(outputText)
                    let cachedS2 = FidelityStorage.loadS2Cache(textHash: hash)?.s2Signatures

                    let (score, _) = ScriptFidelityService.evaluate(
                        outputText: outputText,
                        cache: cache,
                        weightProfile: weightProfile,
                        s2Signatures: cachedS2,
                        moveType: selectedMoveType.rawValue
                    )
                    run.strategyRuns[si].methodResults[mi].fidelityScore = score
                    didChange = true
                }
            }

            if didChange {
                do {
                    try OpenerComparisonStorage.save(run, sessionId: sessionId)
                } catch {
                    print("[OpenerComparison] Failed to re-save run \(runId): \(error.localizedDescription)")
                }
            }

            updatedSummaries.append(OpenerComparisonRunSummary(from: run))

            if currentRun?.id == run.id {
                currentRun = run
            }
        }

        runHistory = updatedSummaries.sorted { $0.createdAt > $1.createdAt }
        reEvalProgressMessage = "Re-evaluated \(total) runs."
        isReEvaluatingHistory = false
    }

    /// Build a copyable text report of all fidelity evaluation results.
    func copyFidelityReport() -> String {
        guard let cache = coordinator.fidelityCache else { return "No baseline computed." }
        return ScriptFidelityService.buildEvaluationReport(
            evaluations: fidelityEvaluations,
            cache: cache,
            weightProfile: coordinator.fidelityWeightProfile
        )
    }

    /// Build a text table of per-dimension fidelity scores across all history runs.
    func copyHistoryFidelityReport() -> String {
        let dims = FidelityDimension.allCases
        let dimHeaders = ["Mech", "Voc", "Shp", "Slot", "Rhy", "Cov", "Stn", "Don"]

        var lines: [String] = []
        lines.append("Fidelity History Report")
        lines.append(String(repeating: "═", count: 100))

        let header = "Date".padding(toLength: 20, withPad: " ", startingAt: 0)
            + "Best".padding(toLength: 10, withPad: " ", startingAt: 0)
            + "Comp".padding(toLength: 6, withPad: " ", startingAt: 0)
            + dimHeaders.map { $0.padding(toLength: 6, withPad: " ", startingAt: 0) }.joined()
            + "Fails"
        lines.append(header)
        lines.append(String(repeating: "─", count: 100))

        let sorted = runHistory.sorted { $0.createdAt < $1.createdAt }
        for summary in sorted {
            guard let composite = summary.bestFidelityComposite,
                  let method = summary.bestFidelityMethod,
                  let dimScores = summary.bestFidelityDimensions else {
                continue
            }

            let dateStr = summary.createdAt.formatted(date: .abbreviated, time: .shortened)
            var row = dateStr.padding(toLength: 20, withPad: " ", startingAt: 0)
            row += method.padding(toLength: 10, withPad: " ", startingAt: 0)
            row += String(format: "%.0f", composite).padding(toLength: 6, withPad: " ", startingAt: 0)

            for dim in dims {
                let score = dimScores[dim.rawValue] ?? 0
                row += String(format: "%.0f", score).padding(toLength: 6, withPad: " ", startingAt: 0)
            }

            let fails = summary.bestFidelityHardFails ?? 0
            row += "\(fails)"
            lines.append(row)
        }

        if lines.count <= 4 {
            lines.append("(No runs with fidelity data)")
        }

        return lines.joined(separator: "\n")
    }

    /// Persist the current weight profile selection.
    func persistWeightProfile() {
        let profile = coordinator.fidelityWeightProfile
        FidelityStorage.saveWeightProfile(profile)
        FidelityStorage.setActiveProfileId(profile.id)
    }
}
