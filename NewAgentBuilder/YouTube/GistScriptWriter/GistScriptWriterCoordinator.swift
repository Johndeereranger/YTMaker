//
//  GistScriptWriterCoordinator.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/29/26.
//

import Foundation
import SwiftUI

/// Main coordinator for the Gist Script Writer workflow
/// Manages session state, persists data, and coordinates services
@MainActor
class GistScriptWriterCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var currentSession: GistScriptSession
    @Published var phase: GistScriptPhase = .inputRambling

    // Processing state
    @Published var isProcessing = false
    @Published var processingMessage = ""
    @Published var errorMessage: String?

    // Extracted gists
    @Published var ramblingGists: [RamblingGist] = []

    // Johnny's gists (loaded from corpus)
    @Published var johnnyGists: [JohnnyGist] = []
    @Published var johnnyGistsLoaded = false

    // Match results
    @Published var matchResults: [UUID: [GistMatch]] = [:]  // RamblingGistID -> matches
    @Published var selectedMatchType: GistMatchType = .gistBToGistB

    // Manual search
    @Published var searchQuery = ""
    @Published var searchFilters = GistSearchFilters()
    @Published var searchResults: [JohnnyGist] = []
    @Published var hasPerformedSearch = false

    // Matching fidelity testing (original)
    @Published var fidelityTests: [GistFidelityTest] = []
    @Published var currentFidelityRun: Int = 0

    // Extraction fidelity testing (prompt stability)
    @Published var extractionFidelityRuns: [ExtractionFidelityRun] = []
    @Published var extractionFidelityResult: ExtractionFidelityResult?
    @Published var extractionFidelityRunCount: Int = 3
    @Published var extractionFidelityTemperature: Double = 0.2
    @Published var extractionFidelityCurrentRun: Int = 0
    @Published var extractionFidelityStatus: String = ""

    // Prompt version tracking
    @Published var promptVersions: [PromptVersion] = []
    @Published var selectedVersionAId: UUID?
    @Published var selectedVersionBId: UUID?
    @Published var newVersionLabel: String = ""
    @Published var newVersionNotes: String = ""

    // Expansion state
    @Published var expandedGistIds: Set<UUID> = []
    @Published var expandedMatchIds: Set<UUID> = []
    @Published var expandedVersionIds: Set<UUID> = []

    // Search context (which gist we're searching on behalf of)
    @Published var searchContextGist: RamblingGist?

    // MARK: - Services

    private let ramblingToGistService = RamblingToGistService()
    private let gistMatchingService = GistMatchingService()

    // MARK: - Persistence Keys

    private let sessionKey = "GistScriptWriter.CurrentSession"
    private let johnnyGistsKey = "GistScriptWriter.JohnnyGists"
    private let promptVersionsKey = "GistScriptWriter.PromptVersions"

    // MARK: - Init

    init() {
        self.currentSession = GistScriptSession()
        loadPersistedSession()
        loadPromptVersions()
    }

    // MARK: - Session Management

    func loadPersistedSession() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let session = try? JSONDecoder().decode(GistScriptSession.self, from: data) {
            self.currentSession = session
            self.ramblingGists = session.ramblingGists

            // Restore phase based on session state
            if !session.ramblingGists.isEmpty {
                self.phase = .reviewingGists
            } else if !session.rawRamblingText.isEmpty {
                self.phase = .inputRambling
            }
        }
    }

    func persistSession() {
        currentSession.ramblingGists = ramblingGists
        currentSession.touch()

        if let data = try? JSONEncoder().encode(currentSession) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    func clearSession() {
        currentSession = GistScriptSession()
        ramblingGists = []
        matchResults = [:]
        fidelityTests = []
        phase = .inputRambling
        persistSession()
    }

    func newSession(keepRambling: Bool = false) {
        let oldRambling = keepRambling ? currentSession.rawRamblingText : ""
        currentSession = GistScriptSession(rawRamblingText: oldRambling)
        ramblingGists = []
        matchResults = [:]
        phase = .inputRambling
        persistSession()
    }

    // MARK: - Rambling Input

    func updateRamblingText(_ text: String) {
        currentSession.rawRamblingText = text
        persistSession()
    }

    // MARK: - Extract Gists from Rambling

    func extractGistsFromRambling() async {
        guard !currentSession.rawRamblingText.isEmpty else {
            errorMessage = "No rambling text to process"
            print("❌ [GistScriptWriter] No rambling text to process")
            return
        }

        isProcessing = true
        processingMessage = "Extracting gists from your rambling..."
        errorMessage = nil
        phase = .extractingGists

        let wordCount = currentSession.rawRamblingText.split(separator: " ").count
        print("🔄 [GistScriptWriter] Starting gist extraction from \(wordCount) words...")

        do {
            let startTime = Date()
            let gists = try await ramblingToGistService.extractGists(
                from: currentSession.rawRamblingText
            )
            let elapsed = Date().timeIntervalSince(startTime)
            print("✅ [GistScriptWriter] Extracted \(gists.count) gists in \(String(format: "%.1f", elapsed))s")

            ramblingGists = gists
            currentSession.ramblingGists = gists
            persistSession()

            phase = .reviewingGists
            processingMessage = "Extracted \(gists.count) gists"
        } catch {
            print("❌ [GistScriptWriter] Extraction failed: \(error)")
            errorMessage = "Failed to extract gists: \(error.localizedDescription)"
            phase = .inputRambling
        }

        isProcessing = false
    }

    // MARK: - Load Johnny's Gists

    func loadJohnnyGists(forChannelIds channelIds: [String]? = nil) async {
        isProcessing = true
        processingMessage = "Loading Johnny's gists from corpus..."
        print("🔄 [GistScriptWriter] Loading Johnny gists from corpus (channels: \(channelIds?.joined(separator: ", ") ?? "all"))...")

        do {
            let startTime = Date()
            johnnyGists = try await gistMatchingService.loadJohnnyGists(
                channelIds: channelIds
            )
            let elapsed = Date().timeIntervalSince(startTime)
            johnnyGistsLoaded = true
            processingMessage = "Loaded \(johnnyGists.count) Johnny gists"
            print("✅ [GistScriptWriter] Loaded \(johnnyGists.count) Johnny gists in \(String(format: "%.1f", elapsed))s")
        } catch {
            print("❌ [GistScriptWriter] Failed to load Johnny gists: \(error)")
            errorMessage = "Failed to load Johnny gists: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    // MARK: - Matching

    func matchAllGists(matchType: GistMatchType, topK: Int = 5) async {
        guard johnnyGistsLoaded else {
            errorMessage = "Load Johnny's gists first"
            return
        }

        isProcessing = true
        processingMessage = "Matching gists..."
        phase = .matchingGists

        var results: [UUID: [GistMatch]] = [:]

        for (index, ramblingGist) in ramblingGists.enumerated() {
            processingMessage = "Matching gist \(index + 1) of \(ramblingGists.count)..."

            let matches = await gistMatchingService.findMatches(
                for: ramblingGist,
                in: johnnyGists,
                matchType: matchType,
                topK: topK
            )

            results[ramblingGist.id] = matches
        }

        matchResults = results
        phase = .reviewingMatches
        isProcessing = false
    }

    func matchSingleGist(_ gist: RamblingGist, matchType: GistMatchType, topK: Int = 10) async -> [GistMatch] {
        guard johnnyGistsLoaded else { return [] }

        return await gistMatchingService.findMatches(
            for: gist,
            in: johnnyGists,
            matchType: matchType,
            topK: topK
        )
    }

    // MARK: - Manual Search

    func searchJohnnyGists() {
        guard johnnyGistsLoaded else {
            print("🔍 [GistSearch] Search skipped — Johnny gists not loaded")
            return
        }

        print("🔍 [GistSearch] Searching \(johnnyGists.count) gists for query: '\(searchQuery)' | filters active: \(searchFilters.isActive)")

        searchResults = gistMatchingService.searchGists(
            query: searchQuery,
            filters: searchFilters,
            in: johnnyGists
        )
        hasPerformedSearch = true

        print("🔍 [GistSearch] Found \(searchResults.count) results")
    }

    func searchForSimilar(to gist: RamblingGist, topK: Int = 20) async -> [GistMatch] {
        guard johnnyGistsLoaded else { return [] }

        // Search with all three match types and combine
        var allMatches: [GistMatch] = []

        for matchType in GistMatchType.allCases {
            let matches = await gistMatchingService.findMatches(
                for: gist,
                in: johnnyGists,
                matchType: matchType,
                topK: topK
            )
            allMatches.append(contentsOf: matches)
        }

        // Dedupe by johnny gist ID, keeping highest score
        var seen: [UUID: GistMatch] = [:]
        for match in allMatches {
            if let existing = seen[match.johnnyGist.id] {
                if match.similarityScore > existing.similarityScore {
                    seen[match.johnnyGist.id] = match
                }
            } else {
                seen[match.johnnyGist.id] = match
            }
        }

        return seen.values.sorted { $0.similarityScore > $1.similarityScore }
    }

    // MARK: - Manual Match Management

    func addManualMatch(johnnyGist: JohnnyGist, forRamblingGist ramblingGist: RamblingGist) {
        let match = GistMatch(
            ramblingGist: ramblingGist,
            johnnyGist: johnnyGist,
            similarityScore: 1.0,
            matchType: .combined
        )

        if matchResults[ramblingGist.id] != nil {
            matchResults[ramblingGist.id]?.insert(match, at: 0)
        } else {
            matchResults[ramblingGist.id] = [match]
        }
    }

    // MARK: - Fidelity Testing

    func runFidelityTest(matchType: GistMatchType, topK: Int = 5, runs: Int = 1) async {
        isProcessing = true

        for run in 1...runs {
            currentFidelityRun = run
            processingMessage = "Fidelity test run \(run) of \(runs)..."

            // Run matching
            await matchAllGists(matchType: matchType, topK: topK)

            // Calculate stats
            var strong = 0, moderate = 0, weak = 0, none = 0

            for (_, matches) in matchResults {
                if let best = matches.first {
                    if best.similarityScore >= 0.8 {
                        strong += 1
                    } else if best.similarityScore >= 0.6 {
                        moderate += 1
                    } else {
                        weak += 1
                    }
                } else {
                    none += 1
                }
            }

            let test = GistFidelityTest(
                sessionId: currentSession.id,
                matchType: matchType,
                topK: topK,
                totalGists: ramblingGists.count,
                strongMatches: strong,
                moderateMatches: moderate,
                weakMatches: weak,
                noMatches: none
            )

            fidelityTests.append(test)
        }

        isProcessing = false
        currentFidelityRun = 0
    }

    func compareFidelityTests() -> FidelityComparison? {
        guard fidelityTests.count >= 2 else { return nil }

        let tests = fidelityTests.suffix(2)
        guard let test1 = tests.first, let test2 = tests.last else { return nil }

        return FidelityComparison(test1: test1, test2: test2)
    }

    // MARK: - Extraction Fidelity Testing (Prompt Stability)

    /// Run extraction fidelity test - extract gists N times and compare stability
    func runExtractionFidelityTest() async {
        guard !currentSession.rawRamblingText.isEmpty else {
            errorMessage = "No rambling text to test"
            return
        }

        isProcessing = true
        extractionFidelityRuns = []
        extractionFidelityResult = nil
        extractionFidelityCurrentRun = 0
        extractionFidelityStatus = "Starting extraction fidelity test..."
        errorMessage = nil

        let inputText = currentSession.rawRamblingText
        let temperature = extractionFidelityTemperature
        let runCount = extractionFidelityRunCount

        print("\n========================================")
        print("EXTRACTION FIDELITY TEST")
        print("========================================")
        print("Temperature: \(temperature)")
        print("Runs: \(runCount)")
        print("Input words: \(inputText.split(separator: " ").count)")

        var runs: [ExtractionFidelityRun] = []

        extractionFidelityStatus = "Running \(runCount) extractions in parallel..."
        processingMessage = extractionFidelityStatus

        await withTaskGroup(of: ExtractionFidelityRun?.self) { group in
            for i in 1...runCount {
                group.addTask {
                    let service = RamblingToGistService()
                    print("\n--- Run \(i) of \(runCount) (parallel) ---")

                    do {
                        let result = try await service.extractGistsWithMetadata(
                            from: inputText,
                            temperature: temperature
                        )

                        let run = ExtractionFidelityRun(
                            runNumber: i,
                            temperature: temperature,
                            gists: result.gists,
                            rawResponse: result.rawResponse,
                            durationSeconds: result.durationSeconds
                        )

                        print("✅ Run \(i): \(result.gists.count) chunks in \(String(format: "%.1f", result.durationSeconds))s")
                        return run

                    } catch {
                        print("❌ Run \(i) failed: \(error)")
                        return nil
                    }
                }
            }

            // Collect results as they arrive
            for await run in group {
                guard let run = run else { continue }
                runs.append(run)
                runs.sort { $0.runNumber < $1.runNumber }
                extractionFidelityRuns = runs
                extractionFidelityCurrentRun = runs.count
                extractionFidelityStatus = "Completed \(runs.count) of \(runCount)..."
                processingMessage = extractionFidelityStatus
            }
        }

        extractionFidelityRuns = runs

        // Analyze results
        if runs.count >= 2 {
            extractionFidelityStatus = "Analyzing results..."
            extractionFidelityResult = analyzeExtractionFidelity(runs: runs, inputText: inputText, temperature: temperature)
            print("\n✅ Stability Score: \(Int((extractionFidelityResult?.stabilityScore ?? 0) * 100))%")
        } else {
            extractionFidelityStatus = "Need at least 2 successful runs to analyze"
        }

        isProcessing = false
        extractionFidelityCurrentRun = 0
        processingMessage = ""
    }

    /// Clear extraction fidelity results
    func clearExtractionFidelityResults() {
        extractionFidelityRuns = []
        extractionFidelityResult = nil
        extractionFidelityCurrentRun = 0
        extractionFidelityStatus = ""
    }

    /// Analyze extraction runs for stability
    private func analyzeExtractionFidelity(runs: [ExtractionFidelityRun], inputText: String, temperature: Double) -> ExtractionFidelityResult {
        let inputWordCount = inputText.split(separator: " ").count

        // 1. Analyze chunk count variance
        var chunkCountDist: [Int: Int] = [:]
        for run in runs {
            chunkCountDist[run.chunkCount, default: 0] += 1
        }
        let minChunks = chunkCountDist.keys.min() ?? 0
        let maxChunks = chunkCountDist.keys.max() ?? 0
        let dominantCount = chunkCountDist.max(by: { $0.value < $1.value })?.key ?? 0

        let chunkCountVariance = ChunkCountVariance(
            distribution: chunkCountDist,
            minChunks: minChunks,
            maxChunks: maxChunks,
            dominantCount: dominantCount
        )

        // 2. Analyze chunk boundary divergences
        // Use word offset as proxy for boundary (count words in source_text up to each chunk)
        var boundaryDivergences: [ChunkBoundaryDivergence] = []

        let maxChunkIndex = runs.map { $0.gists.count }.max() ?? 0
        for chunkIndex in 0..<maxChunkIndex {
            var wordBoundaries: [Int: Int] = [:]

            for run in runs {
                guard chunkIndex < run.gists.count else { continue }
                // Calculate cumulative word count up to this chunk
                let wordsBeforeThisChunk = run.gists.prefix(chunkIndex).reduce(0) {
                    $0 + $1.sourceText.split(separator: " ").count
                }
                wordBoundaries[wordsBeforeThisChunk, default: 0] += 1
            }

            let minBoundary = wordBoundaries.keys.min() ?? 0
            let maxBoundary = wordBoundaries.keys.max() ?? 0

            boundaryDivergences.append(ChunkBoundaryDivergence(
                chunkIndex: chunkIndex,
                wordBoundaries: wordBoundaries,
                variance: maxBoundary - minBoundary
            ))
        }

        // 3. Analyze move label variance
        var moveVariances: [MoveVariance] = []

        for chunkIndex in 0..<maxChunkIndex {
            var moveDist: [String: Int] = [:]

            for run in runs {
                guard chunkIndex < run.gists.count else { continue }
                let moveLabel = run.gists[chunkIndex].moveLabel ?? "NONE"
                moveDist[moveLabel, default: 0] += 1
            }

            let dominant = moveDist.max(by: { $0.value < $1.value })
            let totalForChunk = moveDist.values.reduce(0, +)
            let dominantPct = dominant.map { Double($0.value) / Double(totalForChunk) * 100 } ?? 0

            moveVariances.append(MoveVariance(
                chunkIndex: chunkIndex,
                moveDistribution: moveDist,
                dominantMove: dominant?.key,
                dominantPercentage: dominantPct
            ))
        }

        // 4. Analyze frame variance
        var frameVariances: [FrameVariance] = []

        for chunkIndex in 0..<maxChunkIndex {
            // Gist A frame
            var frameADist: [String: Int] = [:]
            for run in runs {
                guard chunkIndex < run.gists.count else { continue }
                frameADist[run.gists[chunkIndex].gistA.frame.rawValue, default: 0] += 1
            }
            let dominantA = frameADist.max(by: { $0.value < $1.value })
            let totalA = frameADist.values.reduce(0, +)

            frameVariances.append(FrameVariance(
                chunkIndex: chunkIndex,
                gistType: "A",
                frameDistribution: frameADist,
                dominantFrame: dominantA?.key,
                dominantPercentage: dominantA.map { Double($0.value) / Double(totalA) * 100 } ?? 0
            ))

            // Gist B frame
            var frameBDist: [String: Int] = [:]
            for run in runs {
                guard chunkIndex < run.gists.count else { continue }
                frameBDist[run.gists[chunkIndex].gistB.frame.rawValue, default: 0] += 1
            }
            let dominantB = frameBDist.max(by: { $0.value < $1.value })
            let totalB = frameBDist.values.reduce(0, +)

            frameVariances.append(FrameVariance(
                chunkIndex: chunkIndex,
                gistType: "B",
                frameDistribution: frameBDist,
                dominantFrame: dominantB?.key,
                dominantPercentage: dominantB.map { Double($0.value) / Double(totalB) * 100 } ?? 0
            ))
        }

        return ExtractionFidelityResult(
            inputWordCount: inputWordCount,
            temperature: temperature,
            totalRuns: runs.count,
            successfulRuns: runs.count,
            chunkCountVariance: chunkCountVariance,
            chunkBoundaryDivergences: boundaryDivergences.filter { $0.variance > 0 },
            moveVariances: moveVariances.filter { !$0.isStable },
            frameVariances: frameVariances.filter { !$0.isStable }
        )
    }

    /// Export extraction fidelity results as text
    func exportExtractionFidelityAsText() -> String {
        guard let result = extractionFidelityResult else {
            return "No extraction fidelity results"
        }

        var output = """
        ════════════════════════════════════════════════════════════════════════════════
        EXTRACTION FIDELITY TEST RESULTS
        ════════════════════════════════════════════════════════════════════════════════
        Date: \(result.createdAt.formatted())
        Temperature: \(result.temperature)
        Runs: \(result.successfulRuns)/\(result.totalRuns) successful
        Input: \(result.inputWordCount) words

        STABILITY SCORE: \(Int(result.stabilityScore * 100))%

        ────────────────────────────────────────────────────────────────────────────────
        CHUNK COUNT VARIANCE
        ────────────────────────────────────────────────────────────────────────────────
        \(result.chunkCountVariance.summaryText)

        """

        if !result.chunkBoundaryDivergences.isEmpty {
            output += """

            ────────────────────────────────────────────────────────────────────────────────
            CHUNK BOUNDARY DIVERGENCES (\(result.chunkBoundaryDivergences.count) unstable)
            ────────────────────────────────────────────────────────────────────────────────

            """
            for div in result.chunkBoundaryDivergences {
                output += "Chunk \(div.chunkIndex + 1): \(div.summaryText) (variance: \(div.variance) words)\n"
            }
        }

        if !result.moveVariances.isEmpty {
            output += """

            ────────────────────────────────────────────────────────────────────────────────
            MOVE LABEL DIVERGENCES (\(result.moveVariances.count) unstable)
            ────────────────────────────────────────────────────────────────────────────────

            """
            for mv in result.moveVariances {
                output += "Chunk \(mv.chunkIndex + 1): \(mv.summaryText)\n"
            }
        }

        output += """

        ────────────────────────────────────────────────────────────────────────────────
        RUN DETAILS
        ────────────────────────────────────────────────────────────────────────────────

        """
        for run in extractionFidelityRuns {
            output += """
            Run \(run.runNumber): \(run.chunkCount) chunks in \(String(format: "%.1f", run.durationSeconds))s

            """
            for gist in run.gists {
                output += "  [\(gist.chunkIndex + 1)] \(gist.moveLabel ?? "N/A") | \(gist.gistB.frame.rawValue) | \(gist.briefDescription.prefix(60))...\n"
            }
            output += "\n"
        }

        return output
    }

    // MARK: - Prompt Version Tracking

    func loadPromptVersions() {
        if let data = UserDefaults.standard.data(forKey: promptVersionsKey),
           let versions = try? JSONDecoder().decode([PromptVersion].self, from: data) {
            self.promptVersions = versions
        }
        // Pre-fill the next version label
        newVersionLabel = nextVersionLabel()
    }

    func persistPromptVersions() {
        if let data = try? JSONEncoder().encode(promptVersions) {
            UserDefaults.standard.set(data, forKey: promptVersionsKey)
        }
    }

    func nextVersionLabel() -> String {
        "v\(promptVersions.count + 1)"
    }

    func saveCurrentAsVersion() {
        let label = newVersionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }

        let notes = newVersionNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let systemPrompt = ramblingToGistService.buildSystemPrompt()
        let userPrompt = ramblingToGistService.buildExtractionPrompt(ramblingText: "<INPUT_TEXT>")

        // Attach fidelity data if available
        let fidelityResult = extractionFidelityResult
        let fidelityRuns = extractionFidelityRuns.isEmpty ? nil : extractionFidelityRuns

        // Chunk count from the most recent extraction
        let chunkCount = ramblingGists.isEmpty ? nil : ramblingGists.count

        let version = PromptVersion(
            versionLabel: label,
            changeNotes: notes.isEmpty ? "No notes" : notes,
            systemPromptText: systemPrompt,
            userPromptTemplate: userPrompt,
            fidelityResult: fidelityResult,
            fidelityRuns: fidelityRuns,
            chunkCountFromLastRun: chunkCount,
            stabilityScore: fidelityResult?.stabilityScore
        )

        promptVersions.append(version)
        persistPromptVersions()

        // Reset form for next version
        newVersionLabel = nextVersionLabel()
        newVersionNotes = ""
    }

    func deletePromptVersion(id: UUID) {
        promptVersions.removeAll { $0.id == id }
        persistPromptVersions()

        // Clear comparison selection if deleted
        if selectedVersionAId == id { selectedVersionAId = nil }
        if selectedVersionBId == id { selectedVersionBId = nil }
    }

    func compareSelectedVersions() -> PromptVersionComparison? {
        guard let aId = selectedVersionAId,
              let bId = selectedVersionBId,
              let a = promptVersions.first(where: { $0.id == aId }),
              let b = promptVersions.first(where: { $0.id == bId }) else {
            return nil
        }
        return PromptVersionComparison(versionA: a, versionB: b)
    }

    func toggleVersionExpansion(_ id: UUID) {
        if expandedVersionIds.contains(id) {
            expandedVersionIds.remove(id)
        } else {
            expandedVersionIds.insert(id)
        }
    }

    func exportVersionSummaryAsText(_ version: PromptVersion) -> String {
        var output = """
        ════════════════════════════════════════════════════════════════════════════════
        PROMPT VERSION: \(version.versionLabel)
        ════════════════════════════════════════════════════════════════════════════════
        Date: \(version.createdAt.formatted())
        Notes: \(version.changeNotes)
        Prompt Length: \(version.promptCharCount) chars
        Stability Score: \(version.stabilityScore.map { "\(Int($0 * 100))%" } ?? "N/A")
        Chunk Count: \(version.chunkCountFromLastRun.map { "\($0)" } ?? "N/A")
        """

        if let result = version.fidelityResult {
            output += """


            ────────────────────────────────────────────────────────────────────────────────
            FIDELITY RESULTS
            ────────────────────────────────────────────────────────────────────────────────
            Stability Score: \(Int(result.stabilityScore * 100))%
            Runs: \(result.successfulRuns)/\(result.totalRuns)
            Temperature: \(result.temperature)
            Chunk Count: \(result.chunkCountVariance.summaryText)
            """

            if !result.chunkBoundaryDivergences.isEmpty {
                output += "\n\nBoundary Divergences (\(result.chunkBoundaryDivergences.count) unstable):"
                for div in result.chunkBoundaryDivergences {
                    output += "\n  Chunk \(div.chunkIndex + 1): \(div.summaryText) (variance: \(div.variance) words)"
                }
            }

            if !result.moveVariances.isEmpty {
                output += "\n\nMove Variances (\(result.moveVariances.count) unstable):"
                for mv in result.moveVariances {
                    output += "\n  Chunk \(mv.chunkIndex + 1): \(mv.summaryText)"
                }
            }

            if !result.frameVariances.isEmpty {
                output += "\n\nFrame Variances (\(result.frameVariances.count) unstable):"
                for fv in result.frameVariances {
                    output += "\n  Chunk \(fv.chunkIndex + 1) Gist \(fv.gistType): \(fv.frameDistribution.sorted(by: { $0.value > $1.value }).map { "\($0.key): \($0.value)x" }.joined(separator: ", "))"
                }
            }
        }

        if let runs = version.fidelityRuns, !runs.isEmpty {
            for run in runs.sorted(by: { $0.runNumber < $1.runNumber }) {
                output += """


                ────────────────────────────────────────────────────────────────────────────────
                RUN \(run.runNumber) — \(run.chunkCount) chunks — \(String(format: "%.1f", run.durationSeconds))s
                ────────────────────────────────────────────────────────────────────────────────
                """

                for gist in run.gists.sorted(by: { $0.chunkIndex < $1.chunkIndex }) {
                    let move = gist.moveLabel ?? "N/A"
                    let frame = gist.gistB.frame.rawValue
                    output += "\n  [\(gist.chunkIndex + 1)] \(move) | \(frame) | \(gist.briefDescription)"
                }
            }
        }

        return output
    }

    func exportVersionAsText(_ version: PromptVersion) -> String {
        var output = """
        ════════════════════════════════════════════════════════════════════════════════
        PROMPT VERSION: \(version.versionLabel)
        ════════════════════════════════════════════════════════════════════════════════
        Date: \(version.createdAt.formatted())
        Notes: \(version.changeNotes)
        Prompt Length: \(version.promptCharCount) chars
        Stability Score: \(version.stabilityScore.map { "\(Int($0 * 100))%" } ?? "N/A")
        Chunk Count: \(version.chunkCountFromLastRun.map { "\($0)" } ?? "N/A")

        ────────────────────────────────────────────────────────────────────────────────
        SYSTEM PROMPT
        ────────────────────────────────────────────────────────────────────────────────

        \(version.systemPromptText)

        ────────────────────────────────────────────────────────────────────────────────
        USER PROMPT TEMPLATE
        ────────────────────────────────────────────────────────────────────────────────

        \(version.userPromptTemplate)
        """

        if let result = version.fidelityResult {
            output += """


            ────────────────────────────────────────────────────────────────────────────────
            FIDELITY RESULTS
            ────────────────────────────────────────────────────────────────────────────────
            Stability Score: \(Int(result.stabilityScore * 100))%
            Runs: \(result.successfulRuns)/\(result.totalRuns)
            Temperature: \(result.temperature)
            Chunk Count: \(result.chunkCountVariance.summaryText)
            """

            if !result.chunkBoundaryDivergences.isEmpty {
                output += "\n\nBoundary Divergences (\(result.chunkBoundaryDivergences.count) unstable):"
                for div in result.chunkBoundaryDivergences {
                    output += "\n  Chunk \(div.chunkIndex + 1): \(div.summaryText) (variance: \(div.variance) words)"
                }
            }

            if !result.moveVariances.isEmpty {
                output += "\n\nMove Variances (\(result.moveVariances.count) unstable):"
                for mv in result.moveVariances {
                    output += "\n  Chunk \(mv.chunkIndex + 1): \(mv.summaryText)"
                }
            }

            if !result.frameVariances.isEmpty {
                output += "\n\nFrame Variances (\(result.frameVariances.count) unstable):"
                for fv in result.frameVariances {
                    output += "\n  Chunk \(fv.chunkIndex + 1) Gist \(fv.gistType): \(fv.frameDistribution.sorted(by: { $0.value > $1.value }).map { "\($0.key): \($0.value)x" }.joined(separator: ", "))"
                }
            }
        }

        // Per-run raw details
        if let runs = version.fidelityRuns, !runs.isEmpty {
            for run in runs.sorted(by: { $0.runNumber < $1.runNumber }) {
                output += """


                ────────────────────────────────────────────────────────────────────────────────
                RUN \(run.runNumber) — \(run.chunkCount) chunks — \(String(format: "%.1f", run.durationSeconds))s — temp \(run.temperature)
                ────────────────────────────────────────────────────────────────────────────────
                """

                for gist in run.gists.sorted(by: { $0.chunkIndex < $1.chunkIndex }) {
                    output += """


                    ╔═══ CHUNK \(gist.chunkIndex + 1)\(gist.moveLabel.map { " — \($0)" } ?? "")\(gist.confidence.map { " — confidence: \(String(format: "%.2f", $0))" } ?? "")
                    ║ GIST_A:
                    ║   Frame: \(gist.gistA.frame.rawValue)
                    ║   Subject: \(gist.gistA.subject.joined(separator: ", "))
                    ║   Premise: \(gist.gistA.premise)
                    ║ GIST_B:
                    ║   Frame: \(gist.gistB.frame.rawValue)
                    ║   Subject: \(gist.gistB.subject.joined(separator: ", "))
                    ║   Premise: \(gist.gistB.premise)
                    ║ Brief: \(gist.briefDescription)
                    """

                    if let telemetry = gist.telemetry {
                        output += """

                        ║ Telemetry: stance=\(telemetry.dominantStance) 1p=\(telemetry.firstPersonCount) 2p=\(telemetry.secondPersonCount) 3p=\(telemetry.thirdPersonCount) numbers=\(telemetry.numberCount) temporal=\(telemetry.temporalCount) contrast=\(telemetry.contrastCount) questions=\(telemetry.questionCount) quotes=\(telemetry.quoteCount) spatial=\(telemetry.spatialCount) technical=\(telemetry.technicalCount)
                        """
                    }

                    output += """

                    ║ Source Text:
                    ║ \(gist.sourceText.replacingOccurrences(of: "\n", with: "\n║ "))
                    ╚═══
                    """
                }

                output += """


                ──── RAW API RESPONSE ────
                \(run.rawResponse)
                ──── END RAW RESPONSE ────
                """
            }
        }

        return output
    }

    func exportVersionComparisonAsText() -> String {
        guard let comparison = compareSelectedVersions() else {
            return "No comparison available"
        }

        let a = comparison.versionA
        let b = comparison.versionB

        var output = """
        ════════════════════════════════════════════════════════════════════════════════
        PROMPT VERSION COMPARISON
        ════════════════════════════════════════════════════════════════════════════════
        Version A: \(a.versionLabel) (\(a.createdAt.formatted()))
        Version B: \(b.versionLabel) (\(b.createdAt.formatted()))

        ────────────────────────────────────────────────────────────────────────────────
        DELTAS
        ────────────────────────────────────────────────────────────────────────────────
        Stability: \(comparison.stabilityDelta.map { delta in
            let sign = delta > 0 ? "+" : ""
            return "\(sign)\(Int(delta * 100))%"
        } ?? "N/A")
        Chunk Count: \(comparison.chunkCountDelta.map { delta in
            let sign = delta > 0 ? "+" : ""
            return "\(sign)\(delta)"
        } ?? "N/A")
        Prompt Length: \(comparison.promptLengthDelta > 0 ? "+" : "")\(comparison.promptLengthDelta) chars
        System Prompt: \(a.systemPromptText.count) → \(b.systemPromptText.count) chars
        User Template: \(a.userPromptTemplate.count) → \(b.userPromptTemplate.count) chars

        Summary: \(comparison.summary)
        """

        return output
    }

    func exportAllVersionsAsText() -> String {
        guard !promptVersions.isEmpty else { return "No prompt versions saved" }

        var output = """
        ════════════════════════════════════════════════════════════════════════════════
        ALL PROMPT VERSIONS (\(promptVersions.count) total)
        ════════════════════════════════════════════════════════════════════════════════

        """

        for version in promptVersions.sorted(by: { $0.createdAt < $1.createdAt }) {
            let stability = version.stabilityScore.map { "\(Int($0 * 100))%" } ?? "—"
            let chunks = version.chunkCountFromLastRun.map { "\($0)" } ?? "—"
            output += """
            \(version.versionLabel) | \(version.createdAt.formatted()) | Stability: \(stability) | Chunks: \(chunks)
               Notes: \(version.changeNotes)

            """
        }

        return output
    }

    func exportRunGistAsText(_ gist: RamblingGist) -> String {
        """
        Chunk \(gist.chunkIndex + 1)\(gist.moveLabel.map { " — \($0)" } ?? "")
        Frame A: \(gist.gistA.frame.rawValue) | Frame B: \(gist.gistB.frame.rawValue)
        Gist A Subject: \(gist.gistA.subject.joined(separator: ", "))
        Gist A Premise: \(gist.gistA.premise)
        Gist B Subject: \(gist.gistB.subject.joined(separator: ", "))
        Gist B Premise: \(gist.gistB.premise)
        Brief: \(gist.briefDescription)
        Source: \(gist.sourceText)
        """
    }

    // MARK: - Expansion Toggle

    func toggleGistExpansion(_ id: UUID) {
        if expandedGistIds.contains(id) {
            expandedGistIds.remove(id)
        } else {
            expandedGistIds.insert(id)
        }
    }

    func toggleMatchExpansion(_ id: UUID) {
        if expandedMatchIds.contains(id) {
            expandedMatchIds.remove(id)
        } else {
            expandedMatchIds.insert(id)
        }
    }

    func expandAll() {
        expandedGistIds = Set(ramblingGists.map { $0.id })
        expandedMatchIds = Set(matchResults.values.flatMap { $0 }.map { $0.id })
    }

    func collapseAll() {
        expandedGistIds.removeAll()
        expandedMatchIds.removeAll()
    }

    // MARK: - Export

    func exportAllAsText() -> String {
        var output = currentSession.exportGistsAsText()

        if !matchResults.isEmpty {
            let johnnyDict = Dictionary(uniqueKeysWithValues: johnnyGists.map { ($0.id, $0) })
            output += "\n\n"
            output += currentSession.exportMatchesAsText(johnnyGists: johnnyDict)
        }

        if !fidelityTests.isEmpty {
            output += "\n\n"
            output += exportFidelityTestsAsText()
        }

        return output
    }

    func exportFidelityTestsAsText() -> String {
        var output = """
        ════════════════════════════════════════════════════════════════════════════════
        FIDELITY TEST RESULTS
        ════════════════════════════════════════════════════════════════════════════════

        """

        for (index, test) in fidelityTests.enumerated() {
            output += """

            ────────────────────────────────────────────────────────────────────────────────
            RUN \(index + 1) — \(test.createdAt.formatted())
            ────────────────────────────────────────────────────────────────────────────────
            Match Type: \(test.matchType.rawValue)
            Top K: \(test.topK)
            Total Gists: \(test.totalGists)

            Results:
            - Strong (≥80%): \(test.strongMatches) (\(Int(Double(test.strongMatches) / Double(test.totalGists) * 100))%)
            - Moderate (60-80%): \(test.moderateMatches) (\(Int(Double(test.moderateMatches) / Double(test.totalGists) * 100))%)
            - Weak (<60%): \(test.weakMatches) (\(Int(Double(test.weakMatches) / Double(test.totalGists) * 100))%)
            - No Match: \(test.noMatches)

            Success Rate: \(Int(test.successRate * 100))%

            """
        }

        return output
    }
}

// MARK: - Search Filters

struct GistSearchFilters: Equatable {
    var channelIds: Set<String> = []
    var moveCategories: Set<String> = []
    var moveLabels: Set<String> = []
    var frames: Set<GistFrame> = []
    var minSimilarity: Double = 0.0
    var positionRange: ClosedRange<Double> = 0.0...1.0

    var isActive: Bool {
        !channelIds.isEmpty ||
        !moveCategories.isEmpty ||
        !moveLabels.isEmpty ||
        !frames.isEmpty ||
        minSimilarity > 0 ||
        positionRange != 0.0...1.0
    }

    mutating func reset() {
        channelIds.removeAll()
        moveCategories.removeAll()
        moveLabels.removeAll()
        frames.removeAll()
        minSimilarity = 0.0
        positionRange = 0.0...1.0
    }
}

// MARK: - Sort Options

enum GistSortOption: String, CaseIterable {
    case similarityDesc = "Similarity (High → Low)"
    case similarityAsc = "Similarity (Low → High)"
    case positionAsc = "Position (Start → End)"
    case positionDesc = "Position (End → Start)"
    case channelName = "Channel Name"
    case moveCategory = "Move Category"
}

// MARK: - Fidelity Comparison

struct FidelityComparison {
    let test1: GistFidelityTest
    let test2: GistFidelityTest

    var successRateDelta: Double {
        test2.successRate - test1.successRate
    }

    var strongMatchDelta: Int {
        test2.strongMatches - test1.strongMatches
    }

    var isImproved: Bool {
        successRateDelta > 0
    }

    var summary: String {
        let direction = isImproved ? "improved" : "declined"
        let percent = Int(abs(successRateDelta) * 100)
        return "Success rate \(direction) by \(percent)%"
    }
}
