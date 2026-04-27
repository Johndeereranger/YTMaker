//
//  MarkovScriptWriterCoordinator.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/17/26.
//
//  Main coordinator for the Markov Script Writer.
//  Autoloads data from GistScriptWriter session, manages Markov matrix building,
//  and will coordinate chain building + matching in later phases.
//

import Foundation
import SwiftUI

// MARK: - Gap Pre-Build Snapshot (for before/after comparison)

struct GapPreBuildSnapshot {
    let gistCountBefore: Int
    let deadEndCountBefore: Int
    let bestChainLengthBefore: Int?
    let bestCoverageBefore: Double?
    let moveCountsBefore: [RhetoricalMoveType: Int]
}

@MainActor
class MarkovScriptWriterCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var session: MarkovScriptSession
    @Published var phase: MarkovScriptPhase = .input

    // Lightweight change trigger — views observe this instead of heavyweight data structs
    @Published var dataVersion: Int = 0

    // Autoload
    @Published var hasAutoloadedData = false
    @Published var autoloadSource = ""

    // Markov data
    var markovMatrix: MarkovMatrix?
    var sequences: [String: RhetoricalSequence] = [:]
    var videoTitles: [String: String] = [:]
    var corpusVideos: [String: YouTubeVideo] = [:]
    @Published var useParentLevel = false
    @Published var selectedChannelIds: Set<String> = [] {
        didSet {
            if let channelId = selectedChannelIds.first {
                fidelityCache = FidelityStorage.loadCorpusCache(creatorId: channelId)
            } else {
                fidelityCache = nil
            }
        }
    }
    @Published var availableChannels: [YouTubeChannel] = []
    var corpusWordCounts: CorpusWordCountService.CorpusWordCountResult?

    // Markov Explorer state
    @Published var selectedMove: RhetoricalMoveType?
    @Published var explorerPath: [RhetoricalMoveType] = []  // Interactive sequence builder

    // Processing
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var errorMessage: String?

    // Expansion & Chain state
    var expansionIndex: FrameExpansionIndex?
    var currentChainRun: ChainBuildRun?

    // Trace explorer state
    @Published var traceSource: TraceSource?
    @Published var tracePositions: [TracePosition] = []
    @Published var traceActiveIndex: Int = 0
    @Published var traceWhatIfOverride: [Int: RhetoricalMoveType] = [:]

    // UI state
    @Published var expandedGistIds: Set<UUID> = []

    // Gap response state
    @Published var activeGapResponses: [GapResponse] = []
    @Published var gapPreBuildSnapshot: GapPreBuildSnapshot?

    // Gist lookup cache (O(1) instead of O(N) linear search)
    private var gistCache: [UUID: RamblingGist] = [:]

    // Synthesis state
    var johnnyGists: [JohnnyGist] = []
    var activeSynthesis: SynthesizedScript?
    @Published var synthesisProgress: (current: Int, total: Int)?

    // Script Trace B state (ephemeral — Side B pipeline)
    @Published var scriptTraceBeats: [ScriptBeat] = []
    @Published var isRunningScriptTrace = false
    @Published var scriptTraceProgress = ""

    // Donor corpus data (shared across Atoms, Skel Lab, Structure tabs)
    enum DonorCorpusState: Equatable {
        case notLoaded
        case loading
        case loaded
        case error(String)
    }

    @Published var donorCorpusState: DonorCorpusState = .notLoaded
    @Published var donorCorpusProgress = ""
    var donorSentences: [CreatorSentence] = []
    var donorBigrams: [SlotBigram] = []
    var donorProfiles: [SectionProfile] = []
    var donorTemplates: [RhythmTemplate] = []
    var donorConfusableLookup: ConfusableLookup?

    // Structure Workbench
    @Published var approvedStructuralSpec: ApprovedStructuralSpec?

    // Fidelity Evaluator (persisted across sessions)
    @Published var fidelityCache: FidelityCorpusCache?
    @Published var fidelityWeightProfile: FidelityWeightProfile = .equalWeights()

    // MARK: - Persistence Keys

    private let sessionKey = "MarkovScriptWriter.CurrentSession"
    private let gistSessionKey = "GistScriptWriter.CurrentSession"

    // MARK: - Init

    init() {
        self.session = MarkovScriptSession()
        MarkovSessionStorage.migrateFromUserDefaultsIfNeeded(key: sessionKey)
        loadPersistedSession()
        autoloadFromGistSession()
        rebuildGistCache()

        // Chain run loading moved to loadLatestChainRunIfNeeded() — called from .task
        // to avoid blocking the main thread (was 468ms synchronous JSON decode).

        // Load persisted fidelity data
        if let channelId = selectedChannelIds.first {
            fidelityCache = FidelityStorage.loadCorpusCache(creatorId: channelId)
        }
        fidelityWeightProfile = FidelityStorage.loadActiveWeightProfile() ?? .equalWeights()
    }

    /// Loads the most recent chain run from disk on a background thread.
    /// Called from the view's .task so it doesn't block init().
    func loadLatestChainRunIfNeeded() async {
        guard currentChainRun == nil, let latest = session.chainRuns.last else { return }
        let sessionId = session.id
        let runId = latest.id
        let run = await Task.detached {
            MarkovSessionStorage.loadChainRun(runId: runId, sessionId: sessionId)
        }.value
        currentChainRun = run
        dataVersion += 1
    }

    // MARK: - Autoload from Gist Script Writer

    /// Reads the GistScriptWriter's persisted session and copies rambling data
    /// if our own session is empty. One-way copy — changes here don't write back.
    func autoloadFromGistSession() {
        // Only autoload if we don't already have data
        guard session.ramblingGists.isEmpty else { return }

        guard let data = UserDefaults.standard.data(forKey: gistSessionKey),
              let gistSession = try? JSONDecoder().decode(GistScriptSession.self, from: data) else {
            return
        }

        // Only copy if the gist session actually has data
        guard !gistSession.ramblingGists.isEmpty else { return }

        session.rawRamblingText = gistSession.rawRamblingText
        session.ramblingGists = gistSession.ramblingGists
        session.importedFromGistSession = true
        hasAutoloadedData = true
        rebuildGistCache()

        let dateStr = gistSession.updatedAt.formatted(date: .abbreviated, time: .shortened)
        autoloadSource = gistSession.sessionName ?? "Gist Writer session (\(dateStr))"

        persistSession()
    }

    /// Manually re-import from GistScriptWriter (overwrite current data)
    func refreshFromGistWriter() {
        guard let data = UserDefaults.standard.data(forKey: gistSessionKey),
              let gistSession = try? JSONDecoder().decode(GistScriptSession.self, from: data) else {
            errorMessage = "No Gist Script Writer session found"
            return
        }

        guard !gistSession.ramblingGists.isEmpty else {
            errorMessage = "Gist Script Writer session has no extracted gists"
            return
        }

        session.rawRamblingText = gistSession.rawRamblingText
        session.ramblingGists = gistSession.ramblingGists
        session.importedFromGistSession = true
        hasAutoloadedData = true
        rebuildGistCache()

        let dateStr = gistSession.updatedAt.formatted(date: .abbreviated, time: .shortened)
        autoloadSource = gistSession.sessionName ?? "Gist Writer session (\(dateStr))"

        persistSession()
    }

    // MARK: - Session Persistence (file-based)

    func loadPersistedSession() {
        guard let saved = MarkovSessionStorage.load() else { return }
        self.session = saved

        if !saved.ramblingGists.isEmpty {
            hasAutoloadedData = true
            if saved.importedFromGistSession {
                autoloadSource = "Previously imported from Gist Writer"
            }
        }
    }

    func persistSession() {
        session.touch()
        MarkovSessionStorage.save(session)
    }

    func clearSession() {
        session = MarkovScriptSession()
        hasAutoloadedData = false
        autoloadSource = ""
        markovMatrix = nil
        sequences = [:]
        videoTitles = [:]
        corpusVideos = [:]
        corpusWordCounts = nil
        expansionIndex = nil
        currentChainRun = nil
        explorerPath = []
        selectedMove = nil
        traceSource = nil
        tracePositions = []
        traceWhatIfOverride = [:]
        activeGapResponses = []
        gapPreBuildSnapshot = nil
        scriptTraceBeats = []
        isRunningScriptTrace = false
        scriptTraceProgress = ""
        approvedStructuralSpec = nil
        fidelityCache = nil
        fidelityWeightProfile = .equalWeights()
        clearDonorCorpus()
        phase = .input
        dataVersion += 1
        MarkovSessionStorage.deleteAllChainRuns(sessionId: session.id)
        MarkovSessionStorage.delete()
    }

    // MARK: - Script Trace B Pipeline

    /// Runs the full Side B pipeline: W1.5 → W2 → W3 → W4 → W5 for each gist.
    func runScriptTracePipeline() async {
        let gists = session.ramblingGists
        guard !gists.isEmpty else { return }

        isRunningScriptTrace = true
        scriptTraceBeats = []
        scriptTraceProgress = "Loading donor library..."

        // Use shared donor corpus (load if not yet loaded)
        if donorCorpusState != .loaded {
            await loadDonorCorpus()
        }

        let allSentences = donorSentences
        let allBigrams = donorBigrams
        let allProfiles = donorProfiles
        let allTemplates = donorTemplates

        if allSentences.isEmpty {
            scriptTraceProgress = "No donor sentences found. Run the Donor Library Pipeline first."
            isRunningScriptTrace = false
            return
        }

        let w15Service = ScriptTraceW15Service()
        let w2Service = ScriptTraceW2Service()
        let w3Service = ScriptTraceW3Service()
        let w4Service = ScriptTraceW4Service()
        let w5Service = ScriptTraceW5Service()

        var usedDonorIds: Set<String> = []
        var beats: [ScriptBeat] = []

        // Use chain positions if available, otherwise use gists directly
        let bestChain = currentChainRun?.bestChain
        let positions = bestChain?.positions ?? []

        for (idx, gist) in gists.enumerated() {
            scriptTraceProgress = "Beat \(idx + 1)/\(gists.count): Decomposing..."

            // Determine move type from chain position or gist's move label
            let moveType: String
            let category: String
            if idx < positions.count {
                moveType = positions[idx].moveType.rawValue
                category = positions[idx].category.rawValue
            } else {
                moveType = gist.moveLabel ?? "evidence-stack"
                category = RhetoricalMoveType(rawValue: moveType)?.category.rawValue ?? "Evidence"
            }

            // W1.5: Payload Decomposition
            let payloads = await w15Service.decomposeGist(
                gistText: gist.sourceText,
                gistFrame: gist.gistA.frame,
                targetMove: moveType
            )

            // W2: Slot Bigram Walk
            scriptTraceProgress = "Beat \(idx + 1)/\(gists.count): Slot walk..."
            let previousSig = beats.last?.targetSlotSignature
            let targetSig = w2Service.walkBigram(
                moveType: moveType,
                previousSignature: previousSig,
                bigrams: allBigrams,
                profiles: allProfiles
            )

            // W3: Donor Retrieval
            scriptTraceProgress = "Beat \(idx + 1)/\(gists.count): Finding donor..."
            let primaryPayloadText = payloads.first?.contentText ?? gist.sourceText
            let donorMatch = w3Service.retrieveDonor(
                moveType: moveType,
                targetSignature: targetSig,
                payloadText: primaryPayloadText,
                payloadEmbedding: nil,
                corpus: allSentences,
                excludeIds: usedDonorIds
            )

            if let donor = donorMatch {
                usedDonorIds.insert(donor.sentence.id)
            }

            // W4: Tier Adaptation
            scriptTraceProgress = "Beat \(idx + 1)/\(gists.count): Adapting..."
            let exampleSentences = allSentences.filter { $0.moveType == moveType }.prefix(3)
            let adaptation = await w4Service.adaptBeat(
                payloadText: primaryPayloadText,
                donorSentence: donorMatch?.sentence,
                donorMatchScore: donorMatch?.similarityScore ?? 0.0,
                targetSignature: targetSig,
                rhythmTemplates: allTemplates,
                moveType: moveType,
                exampleSentences: Array(exampleSentences)
            )

            let beat = ScriptBeat(
                beatIndex: idx,
                sectionMove: moveType,
                sectionCategory: category,
                payloads: payloads,
                targetSlotSignature: targetSig,
                donorSentence: donorMatch?.sentence,
                donorMatchReason: donorMatch?.matchReason,
                donorSimilarityScore: donorMatch?.similarityScore,
                adaptedText: adaptation.adaptedText,
                adaptationTier: adaptation.tier,
                finalText: adaptation.adaptedText
            )

            beats.append(beat)
            scriptTraceBeats = beats
        }

        // W5: Seam Check (run on all beats)
        scriptTraceProgress = "Running seam checks..."
        let texts = beats.compactMap { $0.adaptedText }
        if texts.count == beats.count {
            let seamResults = await w5Service.checkAllSeams(texts: texts)
            for i in 0..<beats.count {
                beats[i].seamEdit = seamResults[i].editDescription
                beats[i].finalText = seamResults[i].finalText
            }
            scriptTraceBeats = beats
        }

        isRunningScriptTrace = false
        scriptTraceProgress = "Done: \(beats.count) beats (\(beats.filter { $0.adaptationTier == .tier1 }.count) T1, \(beats.filter { $0.adaptationTier == .tier2 }.count) T2, \(beats.filter { $0.adaptationTier == .tier3 }.count) T3)"
    }

    // MARK: - Corpus Loading

    func loadAvailableChannels() async {
        do {
            availableChannels = try await MarkovCorpusLoader.availableChannels()
            if selectedChannelIds.isEmpty,
               let jh = availableChannels.first(where: { $0.name == "Johnny Harris" }) {
                selectedChannelIds = [jh.channelId]
            }
        } catch {
            errorMessage = "Failed to load channels: \(error.localizedDescription)"
        }
    }

    func loadCorpusAndBuildMatrix() async {
        isLoading = true
        loadingMessage = "Loading rhetorical sequences..."
        errorMessage = nil

        do {
            let channelIds = selectedChannelIds.isEmpty ? nil : Array(selectedChannelIds)
            let result = try await MarkovCorpusLoader.loadSequences(channelIds: channelIds)
            sequences = result.sequences
            videoTitles = result.videoTitles
            corpusVideos = result.corpusVideos

            // CPU-bound work — run off the main actor so tab switching stays responsive
            loadingMessage = "Building transition matrix..."
            let useParent = useParentLevel
            let seqs = result.sequences
            let videos = result.corpusVideos
            let matrix = await Task.detached {
                MarkovTransitionService.buildMatrix(from: seqs, useParentLevel: useParent)
            }.value
            markovMatrix = matrix

            loadingMessage = "Computing corpus word counts..."
            let wordCounts = await Task.detached {
                CorpusWordCountService.computeStats(sequences: seqs, corpusVideos: videos)
            }.value
            corpusWordCounts = wordCounts

            dataVersion += 1
            isLoading = false
            loadingMessage = ""
        } catch {
            isLoading = false
            loadingMessage = ""
            errorMessage = "Failed to build matrix: \(error.localizedDescription)"
        }
    }

    // MARK: - Donor Corpus Loading (shared across Atoms, Skel Lab, Structure tabs)

    /// Loads all donor corpus data from Firebase once. Subsequent calls are no-ops if already loaded.
    func loadDonorCorpus() async {
        guard donorCorpusState != .loading, donorCorpusState != .loaded else { return }
        donorCorpusState = .loading
        donorCorpusProgress = "Loading donor corpus..."

        let channelIds = Array(selectedChannelIds)
        guard !channelIds.isEmpty else {
            donorCorpusState = .error("No channels selected")
            return
        }

        var sentences: [CreatorSentence] = []
        var bigrams: [SlotBigram] = []
        var profiles: [SectionProfile] = []
        var templates: [RhythmTemplate] = []
        var pairs: [ConfusablePair] = []

        for (i, channelId) in channelIds.enumerated() {
            donorCorpusProgress = "Loading channel \(i + 1)/\(channelIds.count)..."
            do {
                async let s = DonorLibraryA2Service.shared.loadSentences(forChannelId: channelId)
                async let b = DonorLibraryA4Service.shared.loadBigrams(forChannelId: channelId)
                async let p = DonorLibraryA4Service.shared.loadProfiles(forChannelId: channelId)
                async let t = DonorLibraryA5Service.shared.loadTemplates(forChannelId: channelId)
                async let c = ConfusablePairService.shared.loadPairs(creatorId: channelId)

                sentences.append(contentsOf: try await s)
                bigrams.append(contentsOf: try await b)
                profiles.append(contentsOf: try await p)
                templates.append(contentsOf: try await t)
                pairs.append(contentsOf: try await c)
            } catch {
                donorCorpusState = .error("Load failed: \(error.localizedDescription)")
                return
            }
        }

        donorSentences = sentences
        donorBigrams = bigrams
        donorProfiles = profiles
        donorTemplates = templates
        donorConfusableLookup = ConfusablePairService.shared.buildLookup(from: pairs)

        donorCorpusProgress = "\(sentences.count) sentences, \(bigrams.count) bigrams, \(profiles.count) profiles, \(templates.count) templates"
        donorCorpusState = .loaded
        dataVersion += 1
    }

    /// Clear shared donor corpus data.
    func clearDonorCorpus() {
        donorSentences = []
        donorBigrams = []
        donorProfiles = []
        donorTemplates = []
        donorConfusableLookup = nil
        donorCorpusState = .notLoaded
        donorCorpusProgress = ""
    }

    /// Rebuild the matrix (e.g. when toggling parent/move level)
    func refreshMatrix() {
        guard !sequences.isEmpty else { return }
        markovMatrix = MarkovTransitionService.buildMatrix(
            from: sequences,
            useParentLevel: useParentLevel
        )
        dataVersion += 1
    }

    // MARK: - Markov Explorer

    /// Start an interactive sequence by selecting a starting move
    func startExplorerSequence(with move: RhetoricalMoveType) {
        explorerPath = [move]
    }

    /// Extend the interactive sequence by adding the next move
    func extendExplorerSequence(with move: RhetoricalMoveType) {
        explorerPath.append(move)
    }

    /// Clear the interactive sequence
    func clearExplorerSequence() {
        explorerPath = []
    }

    /// Pure N-step corpus lookup for the current explorer path.
    /// Uses the deepest history available (capped by historyDepth parameter).
    func explorerNextMoves(topK: Int = 10) -> MarkovMatrix.ContextAwareResult {
        guard let matrix = markovMatrix, let lastMove = explorerPath.last else {
            return MarkovMatrix.ContextAwareResult(moves: [], isDeadEnd: true, historyDepthUsed: 0, lookupKey: "")
        }
        return matrix.contextAwareNextMoves(
            after: lastMove,
            history: explorerPath,
            parameters: session.parameters,
            topK: topK
        )
    }

    // MARK: - Pattern Provenance ("Show Me The Proof")

    struct PatternMatch: Identifiable {
        let id = UUID()
        let videoId: String
        let title: String
        let matchStartIndex: Int            // where in the video's sequence the pattern starts
        let fullSequence: [RhetoricalMoveType]  // the entire video's move sequence (ordered)
    }

    /// Find all videos whose rhetorical sequence contains the given pattern as a contiguous subsequence.
    /// Respects `useParentLevel` — at parent level, compares categories instead of exact move types.
    func findVideosMatchingPattern(_ pattern: [RhetoricalMoveType]) -> [PatternMatch] {
        guard !pattern.isEmpty else { return [] }

        var matches: [PatternMatch] = []

        for (videoId, sequence) in sequences {
            let sortedMoves = sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            let moveTypes = sortedMoves.map { $0.moveType }
            guard moveTypes.count >= pattern.count else { continue }

            // Slide a window of pattern.count across the sequence
            let windowSize = pattern.count
            for startIdx in 0...(moveTypes.count - windowSize) {
                let window = Array(moveTypes[startIdx..<(startIdx + windowSize)])

                let isMatch: Bool
                if useParentLevel {
                    isMatch = zip(window, pattern).allSatisfy { $0.category == $1.category }
                } else {
                    isMatch = window == pattern
                }

                if isMatch {
                    let title = videoTitles[videoId] ?? videoId
                    matches.append(PatternMatch(
                        videoId: videoId,
                        title: title,
                        matchStartIndex: startIdx,
                        fullSequence: moveTypes
                    ))
                    break  // one match per video is enough
                }
            }
        }

        return matches.sorted { $0.title < $1.title }
    }

    // MARK: - Re-extraction (via existing RamblingToGistService)

    func reExtractGists() async {
        guard !session.rawRamblingText.isEmpty else {
            errorMessage = "No rambling text to extract from"
            return
        }

        isLoading = true
        loadingMessage = "Re-extracting gists..."

        do {
            let service = RamblingToGistService()
            let gists = try await service.extractGists(from: session.rawRamblingText)
            session.ramblingGists = gists
            session.importedFromGistSession = false
            hasAutoloadedData = true
            autoloadSource = "Freshly extracted"
            rebuildGistCache()
            persistSession()
            isLoading = false
            loadingMessage = ""
        } catch {
            isLoading = false
            loadingMessage = ""
            errorMessage = "Extraction failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Expansion Index

    /// Rebuild the expansion index from current gists using the 10→25 frame table
    func rebuildExpansionIndex() {
        guard !session.ramblingGists.isEmpty else {
            expansionIndex = nil
            dataVersion += 1
            return
        }
        expansionIndex = FrameExpansionIndex(gists: session.ramblingGists)
        dataVersion += 1
    }

    // MARK: - Chain Building

    /// Best chain from the current run
    var bestChain: ChainAttempt? {
        currentChainRun?.bestChain
    }

    /// Build chains: dispatches to exhaustive or tree walk based on algorithm type.
    /// Appends to run history, trims to 10.
    func buildChain() {
        guard let matrix = markovMatrix else {
            errorMessage = "No Markov matrix built. Go to the Markov tab and build the matrix first."
            return
        }
        guard !session.ramblingGists.isEmpty else {
            errorMessage = "No rambling gists loaded. Import from Gist Writer first."
            return
        }

        // Clear stale trace state from previous run
        traceSource = nil
        tracePositions = []
        traceWhatIfOverride = [:]

        // Rebuild expansion index with current gists
        rebuildExpansionIndex()
        guard let index = expansionIndex else {
            errorMessage = "Failed to build expansion index"
            return
        }

        isLoading = true
        let parameters = session.parameters
        let gists = session.ramblingGists
        let seqs = sequences

        if parameters.algorithmType == .treeWalk {
            let suffix = parameters.enableGistBranching ? " (gist branching)" : ""
            loadingMessage = "Tree walking \(parameters.monteCarloSimulations) paths\(suffix)..."
        } else {
            loadingMessage = "Building chains..."
        }

        Task.detached { [matrix, gists, index, parameters] in
            var run = ChainBuildingService.buildRun(
                matrix: matrix,
                expansionIndex: index,
                gists: gists,
                parameters: parameters
            )

            // Tree walk: Phase 1 — compute upside scores (instant)
            // Use run.parameters (not captured parameters) because buildTreeWalkRun
            // may auto-set maxMoveTypeShare for budget >= 1000
            if run.parameters.algorithmType == .treeWalk {
                let runParams = run.parameters
                let allStarters = MarkovTransitionService.sequenceStartProbabilities(in: matrix)
                let viableCount = allStarters.filter { starter in
                    index.hasEligibleGists(for: starter.move, excluding: [])
                }.count

                let effectiveMaxLength = max(runParams.maxChainLength, gists.count + 5)
                ChainBuildingService.computeDeadEndUpside(
                    deadEnds: &run.deadEnds,
                    parameters: runParams,
                    effectiveMaxLength: effectiveMaxLength,
                    totalStarters: viableCount
                )

                // Tree walk: Phase 1b — cascade analysis (what happens if you fix each move?)
                run.cascadeResults = ChainBuildingService.computeCascadeAnalysis(
                    deadEnds: run.deadEnds,
                    matrix: matrix,
                    expansionIndex: index,
                    gists: gists,
                    parameters: runParams,
                    effectiveMaxLength: effectiveMaxLength
                )
            }

            await MainActor.run { [weak self, run] in
                guard let self else { return }
                self.currentChainRun = run
                self.dataVersion += 1

                // Save full run to disk, keep lightweight summary in session
                MarkovSessionStorage.saveChainRun(run, sessionId: self.session.id)
                let summary = ChainRunSummary(from: run)
                self.session.chainRuns.append(summary)

                if self.session.chainRuns.count > 10 {
                    let removed = self.session.chainRuns.removeFirst()
                    MarkovSessionStorage.deleteChainRun(runId: removed.id, sessionId: self.session.id)
                }

                self.persistSession()

                // Tree walk: Phase 2 — async LLM guidance for top N (async)
                if parameters.algorithmType == .treeWalk && !run.deadEnds.isEmpty {
                    self.loadingMessage = "Loading creator scripts for guidance..."

                    let channelIds = self.selectedChannelIds.isEmpty ? nil : Array(self.selectedChannelIds)

                    Task {
                        // Load JohnnyGists (stored on coordinator for reuse in synthesis)
                        if self.johnnyGists.isEmpty {
                            do {
                                let loaded = try await GistMatchingService().loadJohnnyGists(channelIds: channelIds)
                                await MainActor.run { [weak self] in
                                    self?.johnnyGists = loaded
                                    self?.dataVersion += 1
                                }
                            } catch {
                                print("[MarkovCoordinator] Failed to load JohnnyGists: \(error.localizedDescription). Proceeding without creator text.")
                            }
                        }

                        let jGists = await MainActor.run { self.johnnyGists }

                        await MainActor.run { [weak self] in
                            self?.loadingMessage = "Generating guidance for top \(parameters.maxGuidanceGaps) dead end groups..."
                        }

                        var deadEnds = run.deadEnds
                        let guidanceDict = await ChainBuildingService.enrichDeadEndsWithGuidance(
                            deadEnds: &deadEnds,
                            gists: gists,
                            corpusSequences: seqs,
                            johnnyGists: jGists,
                            maxToEnrich: parameters.maxGuidanceGaps
                        )
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            self.currentChainRun?.deadEnds = deadEnds
                            self.currentChainRun?.moveTypeGuidance = guidanceDict
                            self.dataVersion += 1
                            self.isLoading = false
                            self.loadingMessage = ""

                            // Re-save enriched run to disk and update summary
                            if let enrichedRun = self.currentChainRun {
                                MarkovSessionStorage.saveChainRun(enrichedRun, sessionId: self.session.id)
                                if let idx = self.session.chainRuns.firstIndex(where: { $0.id == enrichedRun.id }) {
                                    self.session.chainRuns[idx].hasGuidance = true
                                }
                            }
                            self.persistSession()
                        }
                    }
                } else {
                    self.isLoading = false
                    self.loadingMessage = ""
                }
            }
        }
    }

    /// Switch to a different persisted chain run (loads full data from disk)
    func selectChainRun(_ summary: ChainRunSummary) {
        if let run = MarkovSessionStorage.loadChainRun(runId: summary.id, sessionId: session.id) {
            currentChainRun = run
            dataVersion += 1
        }
    }

    /// Navigate to Markov Explorer with a pre-loaded path (for dead end inspection)
    func navigateToExplorerWithPath(_ path: [RhetoricalMoveType]) {
        explorerPath = path
        phase = .markovExplorer
    }

    /// Look up a gist by ID (O(1) via cache)
    func gistForId(_ id: UUID) -> RamblingGist? {
        gistCache[id]
    }

    /// Rebuild the UUID→RamblingGist lookup cache. Call after any mutation to session.ramblingGists.
    func rebuildGistCache() {
        gistCache = Dictionary(uniqueKeysWithValues:
            session.ramblingGists.map { ($0.id, $0) }
        )
    }

    // MARK: - Gap Response Workflow

    /// Populate activeGapResponses from current chain run's dead ends.
    /// Groups by move type, ranked by upside. Only includes groups with LLM guidance.
    func loadGapResponsesFromDeadEnds() {
        guard let run = currentChainRun else {
            activeGapResponses = []
            return
        }

        // Group dead ends by move type (same logic as DeadEndsView)
        var moveGroups: [RhetoricalMoveType: [DeadEnd]] = [:]
        for de in run.deadEnds {
            for move in de.rawCandidateMoveTypes {
                moveGroups[move, default: []].append(de)
            }
        }

        // Build GapResponse entries for groups that have guidance
        activeGapResponses = moveGroups.compactMap { move, des -> GapResponse? in
            let maxUpside = des.map(\.upsideScore).max() ?? 0

            // Primary: read from per-move-type guidance dict
            let guidance: String
            let prompt: String
            if let mtg = run.moveTypeGuidance[move] {
                guidance = mtg.guidance
                prompt = mtg.prompt
            } else {
                // Backward compat fallback — filter by guidanceMoveType to avoid cross-group contamination
                let guidanceDe = des.first(where: { !$0.ramblingGuidance.isEmpty && $0.guidanceMoveType == move.displayName })
                guard let fallback = guidanceDe?.ramblingGuidance, !fallback.isEmpty else { return nil }
                guidance = fallback
                prompt = guidanceDe?.guidancePrompt ?? ""
            }

            // Reuse persisted gap response if user already typed something
            if let existing = session.gapResponses.first(where: { $0.targetMoveType == move }) {
                return existing
            }

            return GapResponse(
                targetMoveType: move,
                guidanceQuestion: guidance,
                guidancePrompt: prompt,
                sourceDeadEndIds: des.map(\.id),
                upsideScore: maxUpside
            )
        }
        .sorted { $0.upsideScore > $1.upsideScore }
    }

    /// Extract gists from the raw text of a specific gap response.
    func extractGistsForGap(at index: Int) async {
        guard index < activeGapResponses.count else { return }
        let text = activeGapResponses[index].rawRamblingText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "No text entered for this gap"
            return
        }

        activeGapResponses[index].extractionStatus = .extracting

        do {
            let service = RamblingToGistService()
            let result = try await service.extractGistsWithMetadata(from: text)
            let gapId = activeGapResponses[index].id
            let baseIndex = session.ramblingGists.count

            // Tag gists with provenance
            let taggedGists = result.gists.map { gist in
                RamblingGist(
                    chunkIndex: baseIndex + gist.chunkIndex,
                    sourceText: gist.sourceText,
                    gistA: gist.gistA,
                    gistB: gist.gistB,
                    briefDescription: gist.briefDescription,
                    moveLabel: gist.moveLabel,
                    confidence: gist.confidence,
                    telemetry: gist.telemetry,
                    gapResponseId: gapId
                )
            }

            activeGapResponses[index].extractedGists = taggedGists
            activeGapResponses[index].extractionStatus = .completed
            activeGapResponses[index].extractionDurationSeconds = result.durationSeconds

            // Analyze coverage via temporary expansion index
            let tempIndex = FrameExpansionIndex(gists: taggedGists)
            var moveCounts: [RhetoricalMoveType: Int] = [:]
            for (move, gistIds) in tempIndex.moveToGists {
                moveCounts[move] = gistIds.count
            }
            activeGapResponses[index].eligibleMoves = moveCounts
            activeGapResponses[index].coversTargetMove = (moveCounts[activeGapResponses[index].targetMoveType] ?? 0) > 0

        } catch {
            activeGapResponses[index].extractionStatus = .failed
            errorMessage = "Gap extraction failed: \(error.localizedDescription)"
        }
    }

    /// Commit all extracted gap gists to the session and rebuild the chain.
    func commitGapGistsAndRebuild() {
        // Collect all extracted gists
        let newGists = activeGapResponses.flatMap(\.extractedGists)
        guard !newGists.isEmpty else {
            errorMessage = "No extracted gists to commit"
            return
        }

        // Capture before-snapshot
        let beforeMoveCounts: [RhetoricalMoveType: Int]
        if let idx = expansionIndex {
            beforeMoveCounts = idx.moveToGists.mapValues { $0.count }
        } else {
            beforeMoveCounts = [:]
        }
        gapPreBuildSnapshot = GapPreBuildSnapshot(
            gistCountBefore: session.ramblingGists.count,
            deadEndCountBefore: currentChainRun?.deadEnds.count ?? 0,
            bestChainLengthBefore: currentChainRun?.bestChain?.positions.count,
            bestCoverageBefore: currentChainRun?.bestChain?.coverageScore,
            moveCountsBefore: beforeMoveCounts
        )

        // Append to session
        session.ramblingGists.append(contentsOf: newGists)
        rebuildGistCache()

        // Persist gap responses
        for response in activeGapResponses where response.extractionStatus == .completed {
            if !session.gapResponses.contains(where: { $0.id == response.id }) {
                session.gapResponses.append(response)
            }
        }

        persistSession()

        // Rebuild (buildChain already calls rebuildExpansionIndex internally)
        buildChain()
    }

    /// Generate before/after comparison report after gap rebuild.
    func gapResponseBeforeAfterReport() -> String? {
        guard let snapshot = gapPreBuildSnapshot, let newRun = currentChainRun else { return nil }

        var lines: [String] = []
        lines.append("=== Gap Response Before/After ===")
        lines.append("")
        lines.append("BEFORE:")
        lines.append("  Gists: \(snapshot.gistCountBefore)")
        if let len = snapshot.bestChainLengthBefore {
            lines.append("  Best chain: \(len) positions")
        }
        if let cov = snapshot.bestCoverageBefore {
            lines.append("  Coverage: \(Int(cov * 100))%")
        }
        lines.append("  Dead ends: \(snapshot.deadEndCountBefore)")
        lines.append("")
        lines.append("AFTER:")
        lines.append("  Gists: \(session.ramblingGists.count)")
        if let newBest = newRun.bestChain {
            lines.append("  Best chain: \(newBest.positions.count) positions")
            lines.append("  Coverage: \(Int(newBest.coverageScore * 100))%")
        }
        lines.append("  Dead ends: \(newRun.deadEnds.count)")
        lines.append("")

        // Per-move comparison
        let afterIndex = expansionIndex ?? FrameExpansionIndex(gists: session.ramblingGists)
        let newMoveCounts = afterIndex.moveToGists.mapValues { $0.count }
        let allMoves = Set(snapshot.moveCountsBefore.keys).union(newMoveCounts.keys)
        let changed = allMoves.filter { snapshot.moveCountsBefore[$0] != newMoveCounts[$0] }

        if !changed.isEmpty {
            lines.append("--- Move Coverage Changes ---")
            for move in changed.sorted(by: { $0.displayName < $1.displayName }) {
                let before = snapshot.moveCountsBefore[move] ?? 0
                let after = newMoveCounts[move] ?? 0
                let delta = after - before
                let sign = delta > 0 ? "+" : ""
                lines.append("  \(move.displayName): \(before) -> \(after) (\(sign)\(delta))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - UI Helpers

    func toggleGistExpansion(_ id: UUID) {
        if expandedGistIds.contains(id) {
            expandedGistIds.remove(id)
        } else {
            expandedGistIds.insert(id)
        }
    }

    func expandAllGists() {
        expandedGistIds = Set(session.ramblingGists.map(\.id))
    }

    func collapseAllGists() {
        expandedGistIds.removeAll()
    }

    // MARK: - Export

    func copyMatrixReport() -> String? {
        guard let matrix = markovMatrix else { return nil }
        return MarkovTransitionService.buildReport(from: matrix)
    }

    // MARK: - Chain Trace Explorer

    /// Navigate to Trace tab with a specific dead end
    func navigateToTraceWithDeadEnd(_ deadEnd: DeadEnd) {
        traceSource = .deadEnd(deadEnd)
        traceWhatIfOverride = [:]
        replayTrace()
        traceActiveIndex = min(deadEnd.positionIndex, max(tracePositions.count - 1, 0))
        phase = .trace
    }

    /// Navigate to Trace tab with a completed chain
    func navigateToTraceWithChain(_ chain: ChainAttempt) {
        traceSource = .chainAttempt(chain)
        traceWhatIfOverride = [:]
        replayTrace()
        traceActiveIndex = 0
        phase = .trace
    }

    /// What-if: override a position's choice and re-replay from that point
    func applyWhatIf(atPosition posIdx: Int, withMove move: RhetoricalMoveType) {
        traceWhatIfOverride[posIdx] = move
        // Clear overrides after this position (they depend on this choice)
        for key in traceWhatIfOverride.keys where key > posIdx {
            traceWhatIfOverride.removeValue(forKey: key)
        }
        replayTrace()
        // Jump to the position after the override to see the effect
        traceActiveIndex = min(posIdx + 1, max(tracePositions.count - 1, 0))
    }

    /// Clear all what-if overrides
    func clearWhatIf() {
        traceWhatIfOverride = [:]
        replayTrace()
    }

    /// Replay the chain builder's decision process for the current trace source.
    /// Deterministic: calls getFilteredCandidates() + mostConstrainedGist() with accumulated state.
    func replayTrace() {
        guard let source = traceSource,
              let matrix = markovMatrix else {
            tracePositions = []
            return
        }

        let gists = session.ramblingGists
        let index = expansionIndex ?? FrameExpansionIndex(gists: gists)
        let parameters = session.parameters
        let pathMoves = source.pathMoves

        guard !pathMoves.isEmpty else {
            tracePositions = []
            return
        }

        var positions: [TracePosition] = []
        var usedGistIds: Set<UUID> = []
        var history: [RhetoricalMoveType] = []

        for (posIdx, originalMove) in pathMoves.enumerated() {
            let actualMove = traceWhatIfOverride[posIdx] ?? originalMove
            let isOverridden = traceWhatIfOverride[posIdx] != nil

            // Get what the chain builder would see at this position
            let candidates: [TraceCandidateStatus]
            let rawCount: Int
            let filteredCount: Int
            let depthUsed: Int
            let lookupKey: String

            if posIdx == 0 {
                // Position 0 is a starter — show all starters as "candidates"
                let allStarters = MarkovTransitionService.sequenceStartProbabilities(in: matrix)
                candidates = allStarters.map { starter in
                    let total = index.moveToGists[starter.move]?.count ?? 0
                    let available = index.eligibleGists(for: starter.move, excluding: usedGistIds).count
                    return TraceCandidateStatus(
                        moveType: starter.move,
                        probability: starter.probability,
                        observationCount: 0,
                        totalGistsForMove: total,
                        availableGists: available,
                        consumedGists: total - available,
                        passesFilter: available > 0,
                        rejectionReason: available > 0 ? nil : "No gists available",
                        wasSelected: starter.move == actualMove
                    )
                }
                rawCount = allStarters.count
                filteredCount = allStarters.filter { index.hasEligibleGists(for: $0.move, excluding: usedGistIds) }.count
                depthUsed = 0
                lookupKey = "sequence_starter"
            } else {
                let lookup = ChainBuildingService.getFilteredCandidates(
                    history: history,
                    positionIndex: posIdx,
                    matrix: matrix,
                    expansionIndex: index,
                    parameters: parameters,
                    usedGistIds: usedGistIds
                )

                candidates = lookup.raw.map { candidate in
                    let total = index.moveToGists[candidate.move]?.count ?? 0
                    let available = index.eligibleGists(for: candidate.move, excluding: usedGistIds).count
                    let passes = lookup.filtered.contains { $0.move == candidate.move }
                    let rejection = lookup.alternatives.first { $0.moveType == candidate.move }?.rejectionReason

                    return TraceCandidateStatus(
                        moveType: candidate.move,
                        probability: candidate.probability,
                        observationCount: candidate.count,
                        totalGistsForMove: total,
                        availableGists: available,
                        consumedGists: total - available,
                        passesFilter: passes,
                        rejectionReason: rejection,
                        wasSelected: candidate.move == actualMove
                    )
                }
                rawCount = lookup.raw.count
                filteredCount = lookup.filtered.count
                depthUsed = lookup.depthUsed
                lookupKey = lookup.lookupKey
            }

            // Assign gist for this position
            let gistId = index.mostConstrainedGist(for: actualMove, excluding: usedGistIds, gists: gists)
            if let gid = gistId { usedGistIds.insert(gid) }
            let gist = gistId.flatMap { id in gists.first { $0.id == id } }

            positions.append(TracePosition(
                positionIndex: posIdx,
                moveType: actualMove,
                assignedGistId: gistId,
                assignedGistChunkIndex: gist?.chunkIndex,
                assignedGistFrame: gist?.gistA.frame,
                rawCandidateCount: rawCount,
                filteredCandidateCount: filteredCount,
                lookupDepthUsed: depthUsed,
                lookupKey: lookupKey,
                candidates: candidates,
                gistsConsumedSoFar: usedGistIds.count,
                totalGists: gists.count,
                isOverridden: isOverridden
            ))

            history.append(actualMove)
        }

        // If the last position had filtered candidates and we're tracing a dead end,
        // add one more "phantom" position showing the dead end's candidates
        if case .deadEnd(let de) = source,
           positions.count == pathMoves.count,
           !traceWhatIfOverride.isEmpty || positions.count <= de.positionIndex {
            // The what-if path may have created a new dead end — show it
            let lookup = ChainBuildingService.getFilteredCandidates(
                history: history,
                positionIndex: positions.count,
                matrix: matrix,
                expansionIndex: index,
                parameters: parameters,
                usedGistIds: usedGistIds
            )
            if !lookup.raw.isEmpty {
                let nextCandidates = lookup.raw.map { candidate in
                    let total = index.moveToGists[candidate.move]?.count ?? 0
                    let available = index.eligibleGists(for: candidate.move, excluding: usedGistIds).count
                    let passes = lookup.filtered.contains { $0.move == candidate.move }
                    let rejection = lookup.alternatives.first { $0.moveType == candidate.move }?.rejectionReason
                    return TraceCandidateStatus(
                        moveType: candidate.move, probability: candidate.probability,
                        observationCount: candidate.count, totalGistsForMove: total,
                        availableGists: available, consumedGists: total - available,
                        passesFilter: passes, rejectionReason: rejection, wasSelected: false
                    )
                }
                positions.append(TracePosition(
                    positionIndex: positions.count,
                    moveType: .synthesis,  // placeholder — this is the "next" position
                    assignedGistId: nil,
                    assignedGistChunkIndex: nil,
                    assignedGistFrame: nil,
                    rawCandidateCount: lookup.raw.count,
                    filteredCandidateCount: lookup.filtered.count,
                    lookupDepthUsed: lookup.depthUsed,
                    lookupKey: lookup.lookupKey,
                    candidates: nextCandidates,
                    gistsConsumedSoFar: usedGistIds.count,
                    totalGists: gists.count,
                    isOverridden: false
                ))
            }
        }

        tracePositions = positions
    }

    // MARK: - Synthesis Pipeline

    func synthesizeScript(sectionLimit: Int? = nil) {
        guard let bestChain = currentChainRun?.bestChain else {
            errorMessage = "No completed chain to synthesize. Build a chain first."
            return
        }
        guard bestChain.status == .completed else {
            errorMessage = "Chain is not completed. Build a completed chain first."
            return
        }

        // Slice chain to first N sections if limited
        var chainToSynthesize = bestChain
        if let limit = sectionLimit, limit < bestChain.positions.count {
            chainToSynthesize.positions = Array(bestChain.positions.prefix(limit))
        }

        isLoading = true
        loadingMessage = "Preparing synthesis..."
        synthesisProgress = (current: 0, total: chainToSynthesize.positions.count)

        let gists = session.ramblingGists
        let sessionId = session.id
        let channelIds = selectedChannelIds.isEmpty ? nil : Array(selectedChannelIds)

        Task.detached { [weak self, chainToSynthesize] in
            // Ensure JohnnyGists are loaded
            let jGists: [JohnnyGist]
            let currentGists = await MainActor.run { self?.johnnyGists ?? [] }
            if currentGists.isEmpty {
                await MainActor.run { self?.loadingMessage = "Loading creator corpus..." }
                do {
                    jGists = try await GistMatchingService().loadJohnnyGists(channelIds: channelIds)
                    await MainActor.run {
                        self?.johnnyGists = jGists
                        self?.dataVersion += 1
                    }
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to load creator corpus: \(error.localizedDescription)"
                        self?.isLoading = false
                        self?.loadingMessage = ""
                    }
                    return
                }
            } else {
                jGists = currentGists
            }

            let sectionCount = chainToSynthesize.positions.count
            await MainActor.run {
                self?.loadingMessage = "Writing section 1 of \(sectionCount)..."
            }

            // Build retriever
            let retriever = CorpusRetriever(johnnyGists: jGists)

            // Run synthesis
            do {
                let script = try await SynthesisService.synthesize(
                    chain: chainToSynthesize,
                    gists: gists,
                    retriever: retriever,
                    onSectionComplete: { index, section in
                        Task { @MainActor [weak self] in
                            self?.synthesisProgress = (current: index + 1, total: sectionCount)
                            self?.loadingMessage = index + 1 < sectionCount
                                ? "Writing section \(index + 2) of \(sectionCount)..."
                                : "Smoothing transitions..."
                        }
                    }
                )

                // Save to file storage
                try SynthesisStorage.save(script, sessionId: sessionId)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let summary = SynthesisRunSummary(from: script)
                    self.session.synthesisRunSummaries.append(summary)
                    self.activeSynthesis = script
                    self.dataVersion += 1
                    self.synthesisProgress = nil
                    self.isLoading = false
                    self.loadingMessage = ""
                    self.persistSession()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Synthesis failed: \(error.localizedDescription)"
                    self?.isLoading = false
                    self?.loadingMessage = ""
                    self?.synthesisProgress = nil
                }
            }
        }
    }

    func loadSynthesisRun(_ id: UUID) {
        if let loaded = SynthesisStorage.load(runId: id, sessionId: session.id) {
            activeSynthesis = loaded
            dataVersion += 1
        } else {
            errorMessage = "Failed to load synthesis run."
        }
    }

    func deleteSynthesisRun(_ id: UUID) {
        SynthesisStorage.delete(runId: id, sessionId: session.id)
        session.synthesisRunSummaries.removeAll { $0.id == id }
        if activeSynthesis?.id == id {
            activeSynthesis = nil
            dataVersion += 1
        }
        persistSession()
    }

    func deleteAllSynthesisRuns() {
        SynthesisStorage.deleteAll(sessionId: session.id)
        session.synthesisRunSummaries.removeAll()
        activeSynthesis = nil
        dataVersion += 1
        persistSession()
    }
}
