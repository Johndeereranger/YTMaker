//
//  StructureWorkbenchViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/16/26.
//
//  ViewModel for the Structure Workbench tab.
//  Loads corpus data from Firebase, reconstructs real sections,
//  and provides 3 deterministic approaches for generating target
//  slot signature sequences. No LLM calls — pure data exploration.
//

import Foundation

@MainActor
class StructureWorkbenchViewModel: ObservableObject {

    // MARK: - Dependencies

    let coordinator: MarkovScriptWriterCoordinator

    // MARK: - Loading State

    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published var loadingState: LoadingState = .idle
    @Published var loadingProgress = ""

    // MARK: - Corpus Data (read from coordinator)

    var allSentences: [CreatorSentence] { coordinator.donorSentences }
    var allBigrams: [SlotBigram] { coordinator.donorBigrams }
    var allProfiles: [SectionProfile] { coordinator.donorProfiles }
    var allTemplates: [RhythmTemplate] { coordinator.donorTemplates }
    var confusableLookup: ConfusableLookup? { coordinator.donorConfusableLookup }

    // MARK: - Fidelity Baseline

    @Published var isComputingBaseline = false
    @Published var baselineStatus: String?

    // MARK: - Move Type Selection

    @Published var selectedMoveType: String?

    var availableMoveTypes: [String] {
        let moveTypes = Set(allSentences.map(\.moveType))
        return moveTypes.sorted()
    }

    // MARK: - Reconstructed Sections

    @Published var sectionsForMove: [ReconstructedSection] = []

    struct ReconstructedSection: Identifiable {
        let id: String
        let videoId: String
        let sectionIndex: Int
        let sentences: [CreatorSentence]

        var signatureSequence: [String] { sentences.map(\.slotSignature) }
        var sentenceCount: Int { sentences.count }
    }

    // MARK: - Approach Selection

    enum SequenceApproach: String, CaseIterable {
        case realSection = "Real Section"
        case bigramWalk = "Bigram Walk"
        case statistical = "Statistical"
    }

    @Published var selectedApproach: SequenceApproach = .statistical

    // MARK: - Approach A: Real Section

    @Published var selectedRealSectionId: String?

    // MARK: - Approach B: Bigram Walk

    @Published var bigramSentenceCount: Int = 5
    @Published var bigramStartingSignature: String?
    @Published var bigramUseTopOne: Bool = false
    @Published var bigramSeed: UInt64 = 0
    @Published var bigramWalkResult: [BigramWalkStep] = []

    struct BigramWalkStep: Identifiable {
        let id: Int
        let positionIndex: Int
        let chosenSignature: String
        let coarseSignature: String?       // rolled-up signature (nil when no rollup)
        let probability: Double
        let alternatives: [(signature: String, probability: Double)]
        let exactCandidateCount: Int
        let expandedCandidateCount: Int
        let rollupCandidateCount: Int      // candidates in coarse space
    }

    // MARK: - Rollup Configuration

    @Published var selectedRollupStrategy: RollupStrategy = .none
    @Published var rollupDiagnostics: [RollupDiagnostic] = []

    // MARK: - Approach C: Statistical

    @Published var statisticalSentenceCount: Int = 5
    @Published var statisticalResult: [PositionalSignatureStat] = []

    struct PositionalSignatureStat: Identifiable {
        let id: Int
        let positionIndex: Int
        let topSignature: String
        let frequency: Int
        let totalAtPosition: Int
        let alternatives: [(signature: String, count: Int)]
    }

    // MARK: - Rhythm Overrides

    @Published var rhythmOverrides: [Int: ApprovedStructuralSpec.RhythmOverride] = [:]

    /// How many corpus sentences each rhythm position's stats are derived from.
    @Published var rhythmMatchCounts: [Int: Int] = [:]

    // MARK: - Donor Previews

    @Published var donorPreviews: [DonorPreview] = []

    struct DonorPreview: Identifiable {
        let id: Int
        let positionIndex: Int
        let targetSignature: String
        let exactMatchCount: Int
        let expandedMatchCount: Int
        let topDonors: [CreatorSentence]
    }

    // MARK: - Skeleton Compliance Test

    @Published var complianceResult: ComplianceTestResult?
    @Published var complianceIsRunning = false
    @Published var complianceProgress: (current: Int, total: Int, text: String)?
    @Published var complianceTopic: String = "chronic wasting disease spreading through whitetail deer populations"

    // MARK: - Move Probe

    @Published var probeInputText: String = ""
    @Published var probeResult: SectionFidelityResult?
    @Published var otherMoveEntries: [ProbeEntry] = []
    @Published var isLoadingOtherMoves = false
    @Published var isAnnotatingS2 = false
    @Published var s2CoverageInfo: (withS2: Int, total: Int)?
    @Published var batchLoadDiagnostic: String?

    struct ProbeEntry: Identifiable {
        let id: String          // videoId
        let videoTitle: String
        let moveType: String
        let text: String
        var s2Signatures: [String]?           // LLM-assigned raw slot sigs from Firebase
        var result: SectionFidelityResult?
    }

    struct DimensionDistribution: Identifiable {
        var id: String { dimension.rawValue }
        let dimension: FidelityDimension
        let scores: [Double]
        let min: Double
        let max: Double
        let mean: Double
        let median: Double
        let baselineP25: Double?
        let baselineP75: Double?
        let baselineMedian: Double?
        let separation: Double      // |baselineMedian - mean| — higher = better discriminator
    }

    // MARK: - Atom-Level Diagnostic Views

    @Published var flattenedChains: [FlattenedChain] = []
    @Published var atomTransitionMatrix: [AtomTransitionRow] = []
    @Published var atomTransitionTotalCount: Int = 0
    @Published var boundaryAnalysis: BoundaryAnalysisResult?

    struct FlattenedChain: Identifiable {
        let id: String                          // matches ReconstructedSection.id
        let videoId: String
        let sectionIndex: Int
        let atoms: [FlattenedAtom]
        let sentenceBoundaryIndices: Set<Int>   // indices in atoms[] where a new sentence begins
        var sentenceCount: Int { sentenceBoundaryIndices.count + 1 }
    }

    struct FlattenedAtom: Identifiable {
        let id: Int                 // position in the flattened array
        let slotType: String        // raw value e.g. "narrative_action"
        let sentenceIndex: Int      // which sentence this atom belongs to
    }

    struct AtomTransitionRow: Identifiable {
        let id: String              // source slot type raw value
        let sourceSlotType: String
        let totalTransitions: Int
        let transitions: [(targetSlotType: String, count: Int, probability: Double)]

        var top3: [(targetSlotType: String, count: Int, probability: Double)] {
            Array(transitions.prefix(3))
        }

        var entropy: Double {
            let probs = transitions.map(\.probability)
            return -probs.reduce(0.0) { sum, p in
                p > 0 ? sum + p * log2(p) : sum
            }
        }

        var maxEntropy: Double {
            transitions.isEmpty ? 0 : log2(Double(transitions.count))
        }

        var normalizedEntropy: Double {
            maxEntropy > 0 ? entropy / maxEntropy : 0
        }
    }

    struct BoundaryAnalysisResult {
        let crossBoundaryTransitions: [String: [String: Int]]
        let withinSentenceTransitions: [String: [String: Int]]
        let crossBoundaryTotal: Int
        let withinSentenceTotal: Int
        let topBoundaryBiased: [TransitionComparison]
        let topInteriorBiased: [TransitionComparison]
        let jsDivergence: Double

        struct TransitionComparison: Identifiable {
            let id: String              // "from -> to"
            let fromSlotType: String
            let toSlotType: String
            let crossBoundaryCount: Int
            let crossBoundaryPct: Double
            let withinSentenceCount: Int
            let withinSentencePct: Double
            let delta: Double           // crossBoundaryPct - withinSentencePct
        }
    }

    // MARK: - Atom-Length Analysis Models

    @Published var atomLengthAnalysis: AtomLengthAnalysis?

    struct AtomLengthAnalysis {
        let atomCountDistribution: [AtomCountBucket]
        let wordCountByAtomCount: [WordCountByAtomBucket]
        let perAtomWordBudget: [AtomWordBudget]
        let atomCoOccurrence: [AtomCoOccurrenceRow]
        let atomPositionDistribution: [AtomPositionRow]
        let sentenceBreakMatrix: [SentenceBreakRow]
        let totalSentences: Int
        let totalAtoms: Int
    }

    struct AtomCountBucket: Identifiable {
        let id: Int
        let atomCount: Int
        let sentenceCount: Int
        let fraction: Double
        let avgWordCount: Double
    }

    struct WordCountByAtomBucket: Identifiable {
        let id: Int
        let atomCount: Int
        let sampleSize: Int
        let min: Int
        let q1: Double
        let median: Double
        let q3: Double
        let max: Int
        let mean: Double
        let sd: Double
    }

    struct AtomWordBudget: Identifiable {
        let id: String
        let atomType: String
        let totalOccurrences: Int
        let soloSentenceCount: Int
        let soloAvgWordCount: Double
        let avgWordsInSentence: Double
        let avgAtomsInSentence: Double
    }

    struct AtomCoOccurrenceRow: Identifiable {
        let id: String
        let atomType: String
        let totalSentencesContaining: Int
        let topCoOccurring: [(atomType: String, count: Int, conditionalProb: Double)]
    }

    struct AtomPositionRow: Identifiable {
        let id: String
        let atomType: String
        let positionCounts: [Int: Int]
        let totalOccurrences: Int
        let firstPositionFraction: Double
        let lastPositionFraction: Double
    }

    struct SentenceBreakRow: Identifiable {
        let id: String
        let fromAtom: String
        let toAtom: String
        let breakCount: Int
        let continueCount: Int
        let breakProbability: Double
    }

    // MARK: - Init

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator

        // Show existing baseline status if persisted
        if let cache = coordinator.fidelityCache {
            let dateStr = cache.computedAt.formatted(date: .abbreviated, time: .shortened)
            baselineStatus = "Baseline: \(dateStr) — \(cache.sentenceCount) sentences"
        }
    }

    // MARK: - Fidelity Baseline Computation

    /// Compute fidelity baseline from the loaded corpus. Persists the result so the
    /// compare tab can evaluate scripts without re-loading from Firebase.
    func computeFidelityBaseline() {
        guard loadingState == .loaded else { return }
        guard let creatorId = coordinator.selectedChannelIds.first else { return }

        isComputingBaseline = true
        baselineStatus = "Computing baseline..."

        // 1. Build pre-aggregated corpus stats
        let corpusStats = ScriptFidelityService.buildCorpusStats(
            creatorId: creatorId,
            donorSentences: allSentences,
            rhythmTemplates: allTemplates
        )

        // 2. Compute baseline profile (scores creator's own corpus)
        let baseline = ScriptFidelityService.computeBaseline(
            creatorId: creatorId,
            donorSentences: allSentences,
            rhythmTemplates: allTemplates,
            corpusStats: corpusStats,
            sectionProfiles: allProfiles
        )

        // 3. Bundle into cache
        let cache = FidelityCorpusCache(
            creatorId: creatorId,
            computedAt: Date(),
            corpusStats: corpusStats,
            baseline: baseline,
            sectionProfiles: allProfiles,
            rhythmTemplates: allTemplates,
            sentenceCount: allSentences.count
        )

        // 4. Persist
        FidelityStorage.saveCorpusCache(cache)

        // 5. Update coordinator
        coordinator.fidelityCache = cache

        let dateStr = cache.computedAt.formatted(date: .abbreviated, time: .shortened)
        baselineStatus = "Baseline: \(dateStr) — \(allSentences.count) sentences"
        isComputingBaseline = false
    }

    /// Build a copyable text report of corpus stats + baseline ranges.
    func copyBaselineReport() -> String {
        guard let cache = coordinator.fidelityCache else { return "No baseline computed." }
        var parts: [String] = []
        parts.append(ScriptFidelityService.buildCorpusStatsReport(cache.corpusStats))
        parts.append("")
        parts.append(ScriptFidelityService.buildBaselineReport(cache.baseline))
        return parts.joined(separator: "\n")
    }

    /// Per-dimension debug trace — scores all ~77 sections for one dimension, worst-first.
    func debugCopy(_ dimension: FidelityDimension) -> String {
        guard let cache = coordinator.fidelityCache, !allSentences.isEmpty else {
            return "No baseline computed."
        }
        return ScriptFidelityService.buildDimensionDebugReport(
            dimension: dimension,
            donorSentences: allSentences,
            cache: cache
        )
    }

    /// Copy just the corpus text with sentence boundaries marked — what the fidelity system scores.
    func copyCorpus() -> String {
        guard !allSentences.isEmpty else { return "No corpus loaded." }

        let grouped = Dictionary(grouping: allSentences) { "\($0.videoId)_\($0.sectionIndex)" }
        let sortedKeys = grouped.keys.sorted()

        var lines: [String] = []
        lines.append("═══ CORPUS TEXT ═══")
        lines.append("Total: \(allSentences.count) sentences across \(sortedKeys.count) sections")
        lines.append("")

        for key in sortedKeys {
            guard let sentences = grouped[key] else { continue }
            let sorted = sentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            guard let first = sorted.first else { continue }

            lines.append("── Section \(first.sectionIndex) | Video: \(first.videoId) | Move: \(first.moveType) ──")
            for s in sorted {
                lines.append("[\(s.sentenceIndex + 1)] \(s.rawText)")
            }
            lines.append("")
        }

        let uniqueVideos = Set(allSentences.map(\.videoId)).count
        lines.append("═══ \(allSentences.count) sentences, \(uniqueVideos) videos, \(sortedKeys.count) sections ═══")

        return lines.joined(separator: "\n")
    }

    /// Dump full corpus details with all metadata per sentence.
    func copyCorpusDetails() -> String {
        guard !allSentences.isEmpty else { return "No corpus loaded." }

        let grouped = Dictionary(grouping: allSentences) { "\($0.videoId)_\($0.sectionIndex)" }
        let sortedKeys = grouped.keys.sorted()

        var lines: [String] = []
        lines.append("═══ RAW CORPUS DUMP ═══")
        lines.append("Total: \(allSentences.count) sentences across \(sortedKeys.count) sections")
        lines.append("")

        for key in sortedKeys {
            guard let sentences = grouped[key] else { continue }
            let sorted = sentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            guard let first = sorted.first else { continue }

            lines.append("── Video: \(first.videoId) | Section \(first.sectionIndex) | Move: \(first.moveType) ──")

            for s in sorted {
                let hints = (s.deterministicHints ?? []).joined(separator: ", ")
                lines.append("  [\(s.sentenceIndex)] (\(s.wordCount)w, \(s.clauseCount)cl) sig=\(s.slotSignature) | hints=[\(hints)] | \"\(s.rawText)\"")
            }
            lines.append("")
        }

        let uniqueVideos = Set(allSentences.map(\.videoId)).count
        let uniqueMoves = Set(allSentences.map(\.moveType)).count
        lines.append("═══ SUMMARY: \(allSentences.count) sentences, \(uniqueVideos) videos, \(sortedKeys.count) sections, \(uniqueMoves) move types ═══")

        return lines.joined(separator: "\n")
    }

    /// Copy corpus text filtered to the currently selected move type only.
    func copyCorpusForMoveType() -> String {
        guard let mt = selectedMoveType else { return "No move type selected." }
        let filtered = allSentences.filter { $0.moveType == mt }
        guard !filtered.isEmpty else { return "No sentences for move type \(mt)." }

        let grouped = Dictionary(grouping: filtered) { "\($0.videoId)_\($0.sectionIndex)" }
        let sortedKeys = grouped.keys.sorted()

        var lines: [String] = []
        lines.append("═══ CORPUS TEXT — Move Type: \(mt) ═══")
        lines.append("Total: \(filtered.count) sentences across \(sortedKeys.count) sections")
        lines.append("")

        for key in sortedKeys {
            guard let sentences = grouped[key] else { continue }
            let sorted = sentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            guard let first = sorted.first else { continue }

            lines.append("── Section \(first.sectionIndex) | Video: \(first.videoId) ──")
            for s in sorted {
                lines.append("[\(s.sentenceIndex + 1)] \(s.rawText)")
            }
            lines.append("")
        }

        let uniqueVideos = Set(filtered.map(\.videoId)).count
        lines.append("═══ \(filtered.count) sentences, \(uniqueVideos) videos, \(sortedKeys.count) sections — \(mt) only ═══")

        return lines.joined(separator: "\n")
    }

    /// Dump full corpus details filtered to the currently selected move type only.
    func copyCorpusDetailsForMoveType() -> String {
        guard let mt = selectedMoveType else { return "No move type selected." }
        let filtered = allSentences.filter { $0.moveType == mt }
        guard !filtered.isEmpty else { return "No sentences for move type \(mt)." }

        let grouped = Dictionary(grouping: filtered) { "\($0.videoId)_\($0.sectionIndex)" }
        let sortedKeys = grouped.keys.sorted()

        var lines: [String] = []
        lines.append("═══ RAW CORPUS DUMP — Move Type: \(mt) ═══")
        lines.append("Total: \(filtered.count) sentences across \(sortedKeys.count) sections")
        lines.append("")

        for key in sortedKeys {
            guard let sentences = grouped[key] else { continue }
            let sorted = sentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            guard let first = sorted.first else { continue }

            lines.append("── Video: \(first.videoId) | Section \(first.sectionIndex) ──")

            for s in sorted {
                let hints = (s.deterministicHints ?? []).joined(separator: ", ")
                lines.append("  [\(s.sentenceIndex)] (\(s.wordCount)w, \(s.clauseCount)cl) sig=\(s.slotSignature) | hints=[\(hints)] | \"\(s.rawText)\"")
            }
            lines.append("")
        }

        let uniqueVideos = Set(filtered.map(\.videoId)).count
        lines.append("═══ SUMMARY: \(filtered.count) sentences, \(uniqueVideos) videos, \(sortedKeys.count) sections — \(mt) only ═══")

        return lines.joined(separator: "\n")
    }

    // MARK: - Data Loading

    func loadData() async {
        guard loadingState != .loading else { return }

        // If coordinator already has data, skip Firebase load
        if coordinator.donorCorpusState == .loaded {
            loadingProgress = "\(allSentences.count) sentences, \(allBigrams.count) bigrams, \(allProfiles.count) profiles (cached)"
            loadingState = .loaded
            if selectedMoveType == nil, let first = availableMoveTypes.first {
                selectMoveType(first)
            }
            return
        }

        loadingState = .loading
        loadingProgress = "Loading corpus..."

        await coordinator.loadDonorCorpus()

        if case .error(let msg) = coordinator.donorCorpusState {
            loadingState = .error(msg)
            return
        }

        loadingProgress = "\(allSentences.count) sentences, \(allBigrams.count) bigrams, \(allProfiles.count) profiles"
        loadingState = .loaded

        // Reload persisted fidelity cache if coordinator missed it at init
        if coordinator.fidelityCache == nil, let creatorId = coordinator.selectedChannelIds.first {
            if let cached = FidelityStorage.loadCorpusCache(creatorId: creatorId) {
                coordinator.fidelityCache = cached
                let dateStr = cached.computedAt.formatted(date: .abbreviated, time: .shortened)
                baselineStatus = "Baseline: \(dateStr) — \(cached.sentenceCount) sentences"
            }
        }

        // Auto-select first move type if available
        if selectedMoveType == nil, let first = availableMoveTypes.first {
            selectMoveType(first)
        }
    }

    // MARK: - Move Type Selection

    func selectMoveType(_ moveType: String) {
        selectedMoveType = moveType
        reconstructSections()
        computeRollupDiagnostics()

        // Set defaults for sentence count from profile
        let profile = profileForSelectedMove
        let median = Int(profile?.medianSentences ?? 5.0)
        bigramSentenceCount = median
        statisticalSentenceCount = median

        // Default starting signature for bigram walk
        bigramStartingSignature = availableOpeningSignatures.first ?? profile?.commonOpeningSignatures.first

        // Reset approach-specific state
        selectedRealSectionId = nil
        bigramWalkResult = []
        statisticalResult = []
        rhythmOverrides = [:]
        donorPreviews = []

        // Reset probe other-move data (user re-loads via button in Move Probe)
        otherMoveEntries = []

        // Reset atom diagnostic views
        flattenedChains = []
        atomTransitionMatrix = []
        atomTransitionTotalCount = 0
        boundaryAnalysis = nil

        // Auto-generate for current approach
        regenerateForCurrentApproach()
    }

    var profileForSelectedMove: SectionProfile? {
        guard let mt = selectedMoveType else { return nil }
        return allProfiles.first { $0.moveType == mt }
    }

    // MARK: - Section Reconstruction

    func reconstructSections() {
        guard let mt = selectedMoveType else {
            sectionsForMove = []
            return
        }

        let moveSentences = allSentences.filter { $0.moveType == mt }

        // Group by (videoId, sectionIndex)
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
            return ReconstructedSection(
                id: key,
                videoId: videoId,
                sectionIndex: sectionIdx,
                sentences: sorted
            )
        }.sorted { a, b in
            if a.sentenceCount != b.sentenceCount { return a.sentenceCount > b.sentenceCount }
            return a.id < b.id
        }
    }

    // MARK: - Sentence Count Distribution

    func computeSentenceCountDistribution() -> [(length: Int, count: Int)] {
        var freq: [Int: Int] = [:]
        for section in sectionsForMove {
            freq[section.sentenceCount, default: 0] += 1
        }
        return freq.sorted { $0.key < $1.key }.map { (length: $0.key, count: $0.value) }
    }

    // MARK: - Signature Frequencies

    func computeSignatureFrequencies() -> [(signature: String, count: Int)] {
        guard let mt = selectedMoveType else { return [] }
        let moveSentences = allSentences.filter { $0.moveType == mt }
        var freq: [String: Int] = [:]
        for s in moveSentences {
            freq[s.slotSignature, default: 0] += 1
        }
        return freq.sorted { $0.value > $1.value }.map { (signature: $0.key, count: $0.value) }
    }

    // MARK: - Rollup Diagnostics

    func computeRollupDiagnostics() {
        let sigFreqs = computeSignatureFrequencies()
        rollupDiagnostics = RollupStrategy.allCases.filter { $0 != .none }.map { strategy in
            SignatureRollupService.buildDiagnostic(strategy: strategy, signatures: sigFreqs)
        }
    }

    // MARK: - Active Sequence (routes to current approach)

    var activeSignatureSequence: [String] {
        switch selectedApproach {
        case .realSection:
            guard let id = selectedRealSectionId,
                  let section = sectionsForMove.first(where: { $0.id == id }) else { return [] }
            return section.signatureSequence
        case .bigramWalk:
            return bigramWalkResult.map(\.chosenSignature)
        case .statistical:
            return statisticalResult.map(\.topSignature)
        }
    }

    // MARK: - Regenerate for Current Approach

    func regenerateForCurrentApproach() {
        switch selectedApproach {
        case .realSection:
            break // user picks manually
        case .bigramWalk:
            generateBigramWalk()
        case .statistical:
            generateStatisticalSequence()
        }
        buildRhythmDefaults()
        buildDonorPreviews()
    }

    // MARK: - Approach A: Select Real Section

    func selectRealSection(_ id: String) {
        selectedRealSectionId = id
        buildRhythmDefaults()
        buildDonorPreviews()
    }

    // MARK: - Approach B: Bigram Walk

    func generateBigramWalk() {
        guard let mt = selectedMoveType else { return }

        let strategy = selectedRollupStrategy
        let moveBigrams = allBigrams.filter {
            $0.fromMove == mt || $0.toMove == mt
        }
        let sigFreqs = computeSignatureFrequencies()

        // If rollup active, build rolled-up bigram table
        let walkBigrams: [(from: String, to: String, count: Int)]
        if strategy != .none {
            var merged: [String: [String: Int]] = [:]
            for b in moveBigrams {
                let fromR = SignatureRollupService.rollup(b.fromSignature, strategy: strategy)
                let toR = SignatureRollupService.rollup(b.toSignature, strategy: strategy)
                merged[fromR, default: [:]][toR, default: 0] += b.count
            }
            walkBigrams = merged.flatMap { from, tos in
                tos.map { to, count in (from: from, to: to, count: count) }
            }
        } else {
            walkBigrams = moveBigrams.map { (from: $0.fromSignature, to: $0.toSignature, count: $0.count) }
        }

        var rng = SeededRNG(seed: bigramSeed)
        var steps: [BigramWalkStep] = []
        var previousSig: String? = nil  // Always in walk space (coarse if rollup, full if raw)

        for i in 0..<bigramSentenceCount {
            let chosenWalkSig: String  // In walk space
            let chosenProb: Double
            var alts: [(signature: String, probability: Double)] = []
            var exactCount = 0
            var expandedCount = 0
            var rollupCount = 0

            if i == 0 {
                // Use starting signature (always full), roll up for walk if needed
                let startFull: String
                if let start = bigramStartingSignature {
                    startFull = start
                } else {
                    let profile = allProfiles.first { $0.moveType == mt }
                    startFull = profile?.commonOpeningSignatures.first ?? "narrative_action"
                }
                chosenWalkSig = strategy != .none ? SignatureRollupService.rollup(startFull, strategy: strategy) : startFull
                chosenProb = 1.0
            } else {
                // Find candidates from previousSig in walk space
                let candidates: [(signature: String, count: Int, probability: Double)]

                if strategy != .none {
                    // Rollup mode: look up in coarse bigram table (skip confusable expansion — rollup subsumes it)
                    let rawCandidates = walkBigrams.filter { $0.from == previousSig }
                    rollupCount = rawCandidates.count

                    if rawCandidates.isEmpty {
                        // Fallback: highest-count bigram in walk space
                        let fallback = walkBigrams.max(by: { $0.count < $1.count })
                        chosenWalkSig = fallback?.to ?? "narrative_action"
                        chosenProb = 0
                        alts = []
                    } else {
                        let totalCount = rawCandidates.reduce(0) { $0 + $1.count }
                        let merged = rawCandidates.map { c in
                            (signature: c.to, count: c.count, probability: totalCount > 0 ? Double(c.count) / Double(totalCount) : 0.0)
                        }.sorted { $0.probability > $1.probability }

                        alts = merged.map { ($0.signature, $0.probability) }
                        let picked = pickFromCandidates(merged, rng: &rng)
                        chosenWalkSig = picked.signature
                        chosenProb = picked.probability
                    }
                } else {
                    // Raw mode: expand via confusable pairs (original behavior)
                    let expandedFromSigs: [String]
                    if let lookup = confusableLookup, let prev = previousSig {
                        expandedFromSigs = ConfusablePairService.shared.expandSignature(
                            prev, using: lookup, moveType: mt
                        )
                    } else {
                        expandedFromSigs = previousSig.map { [$0] } ?? []
                    }
                    let expandedFromSet = Set(expandedFromSigs)

                    let exactCandidates = walkBigrams.filter { $0.from == previousSig }
                    let rawCandidates = walkBigrams.filter { expandedFromSet.contains($0.from) }
                    exactCount = exactCandidates.count
                    expandedCount = rawCandidates.count

                    if rawCandidates.isEmpty {
                        let fallback = moveBigrams.max(by: { $0.probability < $1.probability })
                        chosenWalkSig = fallback?.toSignature ?? "narrative_action"
                        chosenProb = fallback?.probability ?? 0
                    } else {
                        var mergedByTo: [String: Int] = [:]
                        for bigram in rawCandidates {
                            mergedByTo[bigram.to, default: 0] += bigram.count
                        }
                        let totalMergedCount = mergedByTo.values.reduce(0, +)

                        let merged = mergedByTo.map { (toSig, count) in
                            (signature: toSig, count: count, probability: totalMergedCount > 0 ? Double(count) / Double(totalMergedCount) : 0.0)
                        }.sorted { $0.probability > $1.probability }

                        alts = merged.map { ($0.signature, $0.probability) }
                        let picked = pickFromCandidates(merged, rng: &rng)
                        chosenWalkSig = picked.signature
                        chosenProb = picked.probability
                    }
                }
            }

            // Map back to full signature if rollup is active
            let fullSig: String
            let coarseSig: String?
            if strategy != .none {
                coarseSig = chosenWalkSig
                fullSig = SignatureRollupService.mapBack(
                    coarseSignature: chosenWalkSig,
                    strategy: strategy,
                    corpus: sigFreqs,
                    useWeightedRandom: !bigramUseTopOne,
                    rng: &rng
                )
            } else {
                coarseSig = nil
                fullSig = chosenWalkSig
            }

            steps.append(BigramWalkStep(
                id: i,
                positionIndex: i,
                chosenSignature: fullSig,
                coarseSignature: coarseSig,
                probability: chosenProb,
                alternatives: alts,
                exactCandidateCount: exactCount,
                expandedCandidateCount: expandedCount,
                rollupCandidateCount: rollupCount
            ))
            previousSig = chosenWalkSig  // Walk continues in walk space
        }

        bigramWalkResult = steps
    }

    /// Pick a candidate from sorted candidates using greedy or weighted-random.
    private func pickFromCandidates(
        _ candidates: [(signature: String, count: Int, probability: Double)],
        rng: inout SeededRNG
    ) -> (signature: String, probability: Double) {
        guard !candidates.isEmpty else { return ("narrative_action", 0) }

        if bigramUseTopOne {
            return (candidates[0].signature, candidates[0].probability)
        }

        // Weighted random
        let totalProb = candidates.reduce(0.0) { $0 + $1.probability }
        guard totalProb > 0 else { return (candidates[0].signature, candidates[0].probability) }

        var roll = Double.random(in: 0..<totalProb, using: &rng)
        for candidate in candidates {
            roll -= candidate.probability
            if roll <= 0 {
                return (candidate.signature, candidate.probability)
            }
        }
        return (candidates[0].signature, candidates[0].probability)
    }

    func rerollBigramWalk() {
        bigramSeed += 1
        generateBigramWalk()
        buildRhythmDefaults()
        buildDonorPreviews()
    }

    // MARK: - Approach C: Statistical / Positional

    func generateStatisticalSequence() {
        let count = statisticalSentenceCount
        guard count > 0 else {
            statisticalResult = []
            return
        }

        var result: [PositionalSignatureStat] = []

        for position in 0..<count {
            // Collect signatures at this position from all sections that are long enough
            var sigCounts: [String: Int] = [:]
            var total = 0

            for section in sectionsForMove where section.sentenceCount > position {
                let sig = section.sentences[position].slotSignature
                sigCounts[sig, default: 0] += 1
                total += 1
            }

            let sorted = sigCounts.sorted { $0.value > $1.value }
            let topSig = sorted.first?.key ?? "narrative_action"
            let topFreq = sorted.first?.value ?? 0
            let alts = sorted.map { (signature: $0.key, count: $0.value) }

            result.append(PositionalSignatureStat(
                id: position,
                positionIndex: position,
                topSignature: topSig,
                frequency: topFreq,
                totalAtPosition: total,
                alternatives: alts
            ))
        }

        statisticalResult = result
    }

    // MARK: - Rhythm Defaults

    func buildRhythmDefaults() {
        let sequence = activeSignatureSequence
        guard !sequence.isEmpty, let mt = selectedMoveType else {
            rhythmOverrides = [:]
            rhythmMatchCounts = [:]
            return
        }

        let moveSentences = allSentences.filter { $0.moveType == mt }
        var overrides: [Int: ApprovedStructuralSpec.RhythmOverride] = [:]
        var matchCounts: [Int: Int] = [:]

        for (i, sig) in sequence.enumerated() {
            // Find sentences with this signature in the corpus
            let matching = moveSentences.filter { $0.slotSignature == sig }
            matchCounts[i] = matching.count

            let wordCounts = matching.map(\.wordCount)
            let clauseCounts = matching.map(\.clauseCount)

            let wcMin = wordCounts.min() ?? 5
            let wcMax = wordCounts.max() ?? 30
            let ccMin = clauseCounts.min() ?? 1
            let ccMax = clauseCounts.max() ?? 4

            // Common openers from matching sentences
            let openerCounts = matching.reduce(into: [String: Int]()) { dict, s in
                dict[s.openingPattern, default: 0] += 1
            }
            let topOpeners = openerCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key)

            overrides[i] = ApprovedStructuralSpec.RhythmOverride(
                positionIndex: i,
                wordCountMin: wcMin,
                wordCountMax: wcMax,
                clauseCountMin: ccMin,
                clauseCountMax: ccMax,
                commonOpeners: topOpeners
            )
        }

        rhythmOverrides = overrides
        rhythmMatchCounts = matchCounts
    }

    // MARK: - Donor Previews

    func buildDonorPreviews() {
        let sequence = activeSignatureSequence
        guard !sequence.isEmpty, let mt = selectedMoveType else {
            donorPreviews = []
            return
        }

        let moveSentences = allSentences.filter { $0.moveType == mt }

        // Build signature index
        var sigIndex: [String: [CreatorSentence]] = [:]
        for s in moveSentences {
            sigIndex[s.slotSignature, default: []].append(s)
        }

        donorPreviews = sequence.enumerated().map { i, sig in
            // Exact matches
            let exact = sigIndex[sig] ?? []

            // Expanded matches (via confusable pairs)
            var expandedCount = exact.count
            var allMatches = exact
            if let lookup = confusableLookup {
                let expanded = ConfusablePairService.shared.expandSignature(
                    sig, using: lookup, moveType: mt
                )
                var seenIds = Set(exact.map(\.id))
                for expSig in expanded where expSig != sig {
                    for s in sigIndex[expSig] ?? [] {
                        if seenIds.insert(s.id).inserted {
                            allMatches.append(s)
                        }
                    }
                }
                expandedCount = allMatches.count
            }

            return DonorPreview(
                id: i,
                positionIndex: i,
                targetSignature: sig,
                exactMatchCount: exact.count,
                expandedMatchCount: expandedCount,
                topDonors: Array(allMatches.prefix(3))
            )
        }
    }

    // MARK: - Spec Preview Text

    func generateSpecPreviewText() -> String {
        let sequence = activeSignatureSequence
        guard !sequence.isEmpty, let mt = selectedMoveType else { return "(No sequence generated)" }

        let profile = profileForSelectedMove
        var parts: [String] = []
        parts.append("## STRUCTURAL SPECIFICATION")
        parts.append("Target move type: \(mt)")
        parts.append("Target sentence count: \(sequence.count)")
        parts.append("")
        parts.append("### Sentence-by-Sentence Slot Signatures")

        for (i, sig) in sequence.enumerated() {
            let position: String
            if i == 0 { position = "(opening)" }
            else if i == sequence.count - 1 { position = "(closing)" }
            else { position = "(mid)" }

            var line = "Sentence \(i + 1) \(position): \(sig)"
            if let rhythm = rhythmOverrides[i] {
                line += " | \(rhythm.wordCountMin)-\(rhythm.wordCountMax) words, \(rhythm.clauseCountMin)-\(rhythm.clauseCountMax) clauses"
            }
            parts.append(line)
        }

        if let profile {
            parts.append("")
            parts.append("### Section Profile")
            parts.append("Typical range: \(profile.minSentences)-\(profile.maxSentences) sentences (median \(String(format: "%.0f", profile.medianSentences)))")
            parts.append("Based on \(profile.totalSections) examples from this creator")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Apply Spec

    func applySpec() {
        let sequence = activeSignatureSequence
        guard !sequence.isEmpty, let mt = selectedMoveType else { return }

        let overrides = sequence.indices.map { i in
            rhythmOverrides[i] ?? ApprovedStructuralSpec.RhythmOverride(
                positionIndex: i,
                wordCountMin: 5, wordCountMax: 30,
                clauseCountMin: 1, clauseCountMax: 4,
                commonOpeners: []
            )
        }

        let sourceDesc: String
        switch selectedApproach {
        case .realSection:
            sourceDesc = "Real section: \(selectedRealSectionId ?? "unknown")"
        case .bigramWalk:
            let rollupNote = selectedRollupStrategy != .none ? ", rollup: \(selectedRollupStrategy.rawValue)" : ""
            sourceDesc = "Bigram walk (seed \(bigramSeed), \(bigramUseTopOne ? "top-1" : "weighted")\(rollupNote))"
        case .statistical:
            sourceDesc = "Statistical (positional frequency)"
        }

        coordinator.approvedStructuralSpec = ApprovedStructuralSpec(
            moveType: mt,
            signatureSequence: sequence,
            rhythmOverrides: overrides,
            approachUsed: selectedApproach.rawValue,
            sourceDescription: sourceDesc,
            approvedAt: Date()
        )
    }

    // MARK: - Observed Sentence Count Range

    var observedMinSentences: Int {
        sectionsForMove.map(\.sentenceCount).min() ?? 1
    }

    var observedMaxSentences: Int {
        sectionsForMove.map(\.sentenceCount).max() ?? 10
    }

    // MARK: - Opening Signatures (for bigram walk picker)

    /// All signatures observed at position 0 across reconstructed sections,
    /// merged with profile's commonOpeningSignatures. Sorted by frequency.
    var availableOpeningSignatures: [String] {
        // Collect from real sections at position 0
        var freq: [String: Int] = [:]
        for section in sectionsForMove where !section.sentences.isEmpty {
            let sig = section.sentences[0].slotSignature
            freq[sig, default: 0] += 1
        }

        // Merge in profile's common openers (in case they weren't in reconstructed sections)
        if let profile = profileForSelectedMove {
            for sig in profile.commonOpeningSignatures {
                freq[sig, default: 0] += 0  // ensure present
            }
        }

        return freq.sorted { $0.value > $1.value }.map(\.key)
    }

    // MARK: - Move Probe Methods

    /// Evaluate the current probeInputText as a single section against the cached baseline.
    func evaluateProbe() {
        guard let cache = coordinator.fidelityCache else { return }
        let text = probeInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let weightProfile = FidelityStorage.loadActiveWeightProfile()
            ?? FidelityWeightProfile.equalWeights()

        probeResult = ScriptFidelityService.evaluateSingleSection(
            sectionText: text,
            moveType: selectedMoveType,
            cache: cache,
            weightProfile: weightProfile
        )
    }

    /// Evaluate probe text with S2 slot annotation via live LLM call.
    /// Falls back to heuristic-only evaluation on LLM failure.
    /// Uses disk cache for S2 annotations to avoid redundant LLM calls.
    func evaluateProbeWithS2() async {
        guard let cache = coordinator.fidelityCache else { return }
        let text = probeInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let weightProfile = FidelityStorage.loadActiveWeightProfile()
            ?? FidelityWeightProfile.equalWeights()

        let sentences = SentenceParser.parse(text)
        guard !sentences.isEmpty else {
            evaluateProbe()
            return
        }

        isAnnotatingS2 = true
        defer { isAnnotatingS2 = false }

        // Check S2 disk cache first
        let textHash = FidelityStorage.s2TextHash(text)
        if let cached = FidelityStorage.loadS2Cache(textHash: textHash) {
            print("[S2 Cache] HIT for hash \(textHash) (\(cached.s2Signatures.count) sigs)")
            probeResult = ScriptFidelityService.evaluateSingleSection(
                sectionText: text,
                moveType: selectedMoveType,
                cache: cache,
                weightProfile: weightProfile,
                s2Signatures: cached.s2Signatures
            )
            return
        }

        // Cache miss — call LLM
        let hints = sentences.map { DeterministicHints.compute(for: $0) }
        let moveType = selectedMoveType ?? ""

        do {
            let annotations = try await DonorLibraryA2Service.shared.callSlotAnnotation(
                sentences: sentences,
                hints: hints,
                moveType: moveType,
                category: ""
            )
            let s2Sigs = annotations.map { $0.slotSequence.joined(separator: "|") }

            // Save to disk cache
            let cachedAnnotations = annotations.enumerated().map { (i, ann) in
                CachedSlotAnnotation(
                    sentenceText: i < sentences.count ? sentences[i] : "",
                    slotSequence: ann.slotSequence,
                    sentenceFunction: ann.sentenceFunction
                )
            }
            FidelityStorage.saveS2Cache(S2CacheEntry(
                textHash: textHash,
                sectionText: text,
                s2Signatures: s2Sigs,
                annotations: cachedAnnotations,
                timestamp: Date(),
                modelUsed: "claude4Sonnet"
            ))
            print("[S2 Cache] MISS for hash \(textHash) — annotated \(s2Sigs.count) sigs via LLM")

            probeResult = ScriptFidelityService.evaluateSingleSection(
                sectionText: text,
                moveType: selectedMoveType,
                cache: cache,
                weightProfile: weightProfile,
                s2Signatures: s2Sigs
            )
        } catch {
            // On LLM failure, evaluate without S2 (heuristic fallback)
            print("[S2 Annotation] LLM call failed: \(error.localizedDescription)")
            probeResult = ScriptFidelityService.evaluateSingleSection(
                sectionText: text,
                moveType: selectedMoveType,
                cache: cache,
                weightProfile: weightProfile,
                s2Signatures: nil
            )
        }
    }

    /// Load a specific real corpus section (by ID) into the probe input.
    func loadSectionAsProbe(sectionId: String) {
        guard let section = sectionsForMove.first(where: { $0.id == sectionId }) else { return }
        probeInputText = section.sentences.map(\.rawText).joined(separator: " ")
        probeResult = nil
    }

    /// Load a probe entry's text into the TextEditor for detailed inspection.
    func loadProbeEntry(_ entry: ProbeEntry) {
        probeInputText = entry.text
        probeResult = entry.result
    }

    /// Load position-1 section text for every video NOT in the loaded corpus.
    /// One entry per video — fetches from video rhetorical sequences.
    func loadOtherMoveTypes() async {
        guard let channelId = coordinator.selectedChannelIds.first else { return }
        isLoadingOtherMoves = true
        defer { isLoadingOtherMoves = false }

        do {
            let videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channelId)

            // Only exclude videos that contributed the selected move type to the baseline.
            // Other videos (different first-move types) are evaluation candidates.
            let corpusVideoIds: Set<String>
            if let moveType = selectedMoveType {
                corpusVideoIds = Set(allSentences.filter { $0.moveType == moveType }.map(\.videoId))
            } else {
                corpusVideoIds = Set(allSentences.map(\.videoId))
            }

            var entries: [ProbeEntry] = []
            var skipReasons: [String: Int] = [:]

            for video in videos {
                if corpusVideoIds.contains(video.videoId) {
                    skipReasons["in_corpus", default: 0] += 1; continue
                }
                guard let sequence = video.rhetoricalSequence else {
                    skipReasons["no_rhetorical_sequence", default: 0] += 1; continue
                }
                guard let transcript = video.transcript else {
                    skipReasons["no_transcript", default: 0] += 1; continue
                }
                guard let firstMove = sequence.moves.first else {
                    skipReasons["no_moves", default: 0] += 1; continue
                }
                guard let start = firstMove.startSentence,
                      let end = firstMove.endSentence else {
                    skipReasons["no_sentence_indices", default: 0] += 1; continue
                }

                let sentences = SentenceParser.parse(transcript)
                guard start >= 0, end < sentences.count, start <= end else {
                    skipReasons["invalid_range(\(start)-\(end) vs \(sentences.count))", default: 0] += 1; continue
                }

                let text = sentences[start...end].joined(separator: " ")
                guard !text.isEmpty else {
                    skipReasons["empty_text", default: 0] += 1; continue
                }

                entries.append(ProbeEntry(
                    id: video.videoId,
                    videoTitle: video.title,
                    moveType: firstMove.moveType.rawValue,
                    text: text
                ))
            }

            // Diagnostic summary
            let skipSummary = skipReasons.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            print("[loadOtherMoveTypes] \(videos.count) videos, \(entries.count) entries. Skips: {\(skipSummary)}")
            batchLoadDiagnostic = "\(entries.count) of \(videos.count) videos" + (skipReasons.isEmpty ? "" : " — skipped: \(skipSummary)")

            // Load S2 annotations from Firebase for all channel videos
            let allCreatorSentences = try await DonorLibraryA2Service.shared.loadSentences(forChannelId: channelId)
            let sentencesByVideo = Dictionary(grouping: allCreatorSentences, by: \.videoId)

            for i in entries.indices {
                if let videoSentences = sentencesByVideo[entries[i].id] {
                    let section0Sigs = videoSentences
                        .filter { $0.sectionIndex == 0 }
                        .sorted { $0.sentenceIndex < $1.sentenceIndex }
                        .map(\.slotSignature)
                    if !section0Sigs.isEmpty {
                        entries[i].s2Signatures = section0Sigs
                    }
                }
            }

            let sortedEntries = entries.sorted {
                if $0.moveType != $1.moveType { return $0.moveType < $1.moveType }
                return $0.videoTitle < $1.videoTitle
            }
            otherMoveEntries = sortedEntries

            // S2 coverage diagnostic
            let withS2 = sortedEntries.filter { $0.s2Signatures != nil && !($0.s2Signatures?.isEmpty ?? true) }.count
            let total = sortedEntries.count
            s2CoverageInfo = (withS2: withS2, total: total)
            let fallback = total - withS2
            print("[S2 Coverage] \(withS2) of \(total) entries have Firebase S2 annotations, \(fallback) entries will use heuristic fallback")
        } catch {
            otherMoveEntries = []
            s2CoverageInfo = nil
            batchLoadDiagnostic = "Error: \(error.localizedDescription)"
        }
    }

    /// Batch-evaluate all loaded probe entries against the corpus baseline.
    /// Pure deterministic computation — no network calls.
    func evaluateAllProbes() {
        guard let cache = coordinator.fidelityCache else { return }
        let weightProfile = FidelityStorage.loadActiveWeightProfile()
            ?? FidelityWeightProfile.equalWeights()

        for i in otherMoveEntries.indices {
            let text = otherMoveEntries[i].text
            otherMoveEntries[i].result = ScriptFidelityService.evaluateSingleSection(
                sectionText: text,
                moveType: selectedMoveType,
                cache: cache,
                weightProfile: weightProfile,
                s2Signatures: otherMoveEntries[i].s2Signatures
            )
        }
    }

    /// Compute per-dimension distribution across all evaluated probe entries.
    /// Sorted by separation (best discriminators first).
    func computeDimensionDistributions() -> [DimensionDistribution] {
        let evaluated = otherMoveEntries.compactMap(\.result)
        guard !evaluated.isEmpty else { return [] }

        return FidelityDimension.allCases.compactMap { dim in
            let scores = evaluated.compactMap { $0.dimensionScores[dim]?.score }
            guard !scores.isEmpty else { return nil }

            let sorted = scores.sorted()
            let min = sorted.first ?? 0
            let max = sorted.last ?? 0
            let mean = sorted.reduce(0, +) / Double(sorted.count)
            let median = sorted[sorted.count / 2]

            // Baseline range from any evaluated result's dimension score
            let baselineRange = evaluated.first?.dimensionScores[dim]?.baselineRange
            let bP25 = baselineRange?.p25
            let bP75 = baselineRange?.p75
            let bMedian = baselineRange?.median

            let separation = abs((bMedian ?? 50) - mean)

            return DimensionDistribution(
                dimension: dim,
                scores: sorted,
                min: min,
                max: max,
                mean: mean,
                median: median,
                baselineP25: bP25,
                baselineP75: bP75,
                baselineMedian: bMedian,
                separation: separation
            )
        }.sorted { $0.separation > $1.separation }
    }

    /// Copyable batch report with all entries + dimension distribution.
    func copyBatchReport() -> String {
        let evaluated = otherMoveEntries.filter { $0.result != nil }
        let distributions = computeDimensionDistributions()

        var lines: [String] = []
        lines.append("=== BATCH PROBE REPORT ===")
        lines.append("Baseline move: \(selectedMoveType ?? "Unknown")")
        lines.append("Entries: \(otherMoveEntries.count) loaded, \(evaluated.count) evaluated")
        lines.append("")

        // Dimension distribution summary
        lines.append("--- DIMENSION DISCRIMINATION (sorted by separation) ---")
        for dist in distributions {
            let baselineStr: String
            if let bP25 = dist.baselineP25, let bP75 = dist.baselineP75, let bMed = dist.baselineMedian {
                baselineStr = "Baseline P25=\(String(format: "%.0f", bP25)) Med=\(String(format: "%.0f", bMed)) P75=\(String(format: "%.0f", bP75))"
            } else {
                baselineStr = "Baseline N/A"
            }
            lines.append("\(dist.dimension.displayName): OtherMean=\(String(format: "%.0f", dist.mean)) OtherRange=[\(String(format: "%.0f", dist.min))-\(String(format: "%.0f", dist.max))] | \(baselineStr) | Separation=\(String(format: "%.0f", dist.separation))")
        }

        lines.append("")
        lines.append("--- PER-VIDEO SCORECARD (sorted by composite) ---")

        let sortedEntries = evaluated.sorted { ($0.result?.compositeScore ?? 0) < ($1.result?.compositeScore ?? 0) }
        for entry in sortedEntries {
            guard let result = entry.result else { continue }
            let dimScores = FidelityDimension.allCases.map { dim in
                let score = result.dimensionScores[dim]?.score ?? 0
                return "\(dim.shortLabel)=\(String(format: "%.0f", score))"
            }.joined(separator: " ")
            lines.append("\(String(format: "%.0f", result.compositeScore)) | \(entry.moveType) | \(entry.videoTitle) | \(dimScores)")
        }

        return lines.joined(separator: "\n")
    }

    /// Format a copyable probe report with WHAT/WHAT/WHY debug trace.
    func copyProbeReport() -> String {
        guard let result = probeResult else { return "No probe result" }

        var lines: [String] = []
        lines.append("=== MOVE PROBE RESULT ===")
        lines.append("Move Type: \(selectedMoveType ?? "Unknown")")
        lines.append("Composite: \(String(format: "%.1f", result.compositeScore))")
        lines.append("Sentences: \(result.sentenceCount) | Words: \(result.wordCount)")
        lines.append("")

        // Hard-fail summary
        let fails = result.hardFailResults.filter { !$0.passed && $0.rule.severity == .fail }
        let warns = result.hardFailResults.filter { !$0.passed && $0.rule.severity == .warn }
        if !fails.isEmpty || !warns.isEmpty {
            lines.append("--- Hard Fails ---")
            for hf in fails { lines.append("FAIL: \(hf.displayMessage)") }
            for hf in warns { lines.append("WARN: \(hf.displayMessage)") }
            lines.append("")
        }

        // Per-dimension WHAT/WHAT/WHY
        lines.append("--- Dimension Breakdown ---")
        for dim in FidelityDimension.allCases {
            guard let dimScore = result.dimensionScores[dim] else { continue }
            lines.append("\n\(dim.displayName): \(String(format: "%.1f", dimScore.score))")

            if let range = dimScore.baselineRange {
                lines.append("  Corpus range: P25=\(String(format: "%.1f", range.p25)) | Median=\(String(format: "%.1f", range.median)) | P75=\(String(format: "%.1f", range.p75))")
            }

            for sub in dimScore.subMetrics {
                let tolStr: String
                if let tol = sub.tolerance {
                    let distance = abs(sub.rawValue - sub.corpusMean)
                    tolStr = " | Distance=\(String(format: "%.2f", distance)) Tolerance=\(String(format: "%.2f", tol))"
                } else {
                    tolStr = ""
                }
                lines.append("  \(sub.name): Raw=\(String(format: "%.2f", sub.rawValue)) Corpus=\(String(format: "%.2f", sub.corpusMean)) Score=\(String(format: "%.0f", sub.score))\(tolStr)")
            }
        }

        lines.append("")
        lines.append("--- Input Text ---")
        lines.append(probeInputText)

        return lines.joined(separator: "\n")
    }

    // MARK: - Skeleton Compliance Test Methods

    /// Pick a skeleton section (~9 sentences) and donor sentences from different videos,
    /// then run the full compliance test.
    func runComplianceTest() async {
        guard let cache = coordinator.fidelityCache else { return }
        guard !sectionsForMove.isEmpty else { return }

        complianceIsRunning = true
        complianceResult = nil
        complianceProgress = nil

        let (skeleton, donors) = pickSkeletonAndDonors()
        guard !skeleton.isEmpty else {
            complianceIsRunning = false
            return
        }

        let result = await SkeletonComplianceService.runComplianceTest(
            skeleton: skeleton,
            donors: donors,
            contentTopic: complianceTopic,
            moveType: selectedMoveType,
            cache: cache,
            onProgress: { current, total, text in
                Task { @MainActor in
                    self.complianceProgress = (current: current, total: total, text: text)
                }
            }
        )

        complianceResult = result
        complianceIsRunning = false
    }

    /// Select a skeleton section (closest to 9 sentences) and find donor sentences
    /// from a different video at the same move type + position.
    func pickSkeletonAndDonors() -> (skeleton: [PositionSpec], donors: [String]) {
        guard !sectionsForMove.isEmpty else { return ([], []) }

        // Pick the section closest to 9 sentences
        let targetLength = 9
        let sorted = sectionsForMove.sorted {
            abs($0.sentenceCount - targetLength) < abs($1.sentenceCount - targetLength)
        }
        let skeletonSection = sorted[0]

        // Build position specs from skeleton
        let skeleton: [PositionSpec] = skeletonSection.sentences.enumerated().map { i, sentence in
            let sentenceType: String
            if sentence.isQuestion { sentenceType = "question" }
            else if sentence.isFragment { sentenceType = "fragment" }
            else { sentenceType = "statement" }

            return PositionSpec(
                index: i,
                slotSignature: sentence.slotSignature,
                wordCount: sentence.wordCount,
                sentenceType: sentenceType,
                originalText: sentence.rawText
            )
        }

        // Find donors from different videos at same move type
        let otherSections = sectionsForMove.filter { $0.videoId != skeletonSection.videoId }

        var donors: [String] = []
        for (i, _) in skeleton.enumerated() {
            var donorText: String?

            // Try exact position match in another video
            for otherSection in otherSections {
                if i < otherSection.sentences.count {
                    donorText = otherSection.sentences[i].rawText
                    break
                }
            }

            // Fallback: nearest position in another video
            if donorText == nil {
                for otherSection in otherSections where !otherSection.sentences.isEmpty {
                    let nearestIdx = min(i, otherSection.sentences.count - 1)
                    donorText = otherSection.sentences[nearestIdx].rawText
                    break
                }
            }

            // Last resort: use skeleton's own sentence
            if donorText == nil {
                donorText = skeletonSection.sentences[i].rawText
            }

            donors.append(donorText ?? "")
        }

        return (skeleton, donors)
    }

    /// The auto-selected skeleton section for preview (closest to 9 sentences).
    var complianceSkeletonSection: ReconstructedSection? {
        guard !sectionsForMove.isEmpty else { return nil }
        return sectionsForMove.sorted {
            abs($0.sentenceCount - 9) < abs($1.sentenceCount - 9)
        }.first
    }

    // MARK: - Atom Diagnostic: Flattened Chains

    func computeFlattenedChains() {
        flattenedChains = sectionsForMove.map { section in
            var atoms: [FlattenedAtom] = []
            var boundaries: Set<Int> = []
            var globalIdx = 0
            for (sentIdx, sentence) in section.sentences.enumerated() {
                if sentIdx > 0 { boundaries.insert(globalIdx) }
                for slot in sentence.slotSequence {
                    atoms.append(FlattenedAtom(id: globalIdx, slotType: slot, sentenceIndex: sentIdx))
                    globalIdx += 1
                }
            }
            return FlattenedChain(
                id: section.id,
                videoId: section.videoId,
                sectionIndex: section.sectionIndex,
                atoms: atoms,
                sentenceBoundaryIndices: boundaries
            )
        }
    }

    func copyFlattenedChain(_ chain: FlattenedChain) -> String {
        var parts: [String] = []
        var currentSentence = -1
        var currentParts: [String] = []

        for atom in chain.atoms {
            if atom.sentenceIndex != currentSentence {
                if !currentParts.isEmpty {
                    parts.append(currentParts.joined(separator: " → "))
                }
                currentParts = []
                currentSentence = atom.sentenceIndex
            }
            currentParts.append(atom.slotType)
        }
        if !currentParts.isEmpty {
            parts.append(currentParts.joined(separator: " → "))
        }
        return parts.joined(separator: " | ")
    }

    func copyAllFlattenedChains() -> String {
        var lines: [String] = []
        lines.append("=== FLATTENED ATOM CHAINS ===")
        lines.append("Move: \(selectedMoveType ?? "none") | \(flattenedChains.count) sections")
        lines.append("")
        for chain in flattenedChains {
            lines.append("-- \(chain.videoId) S\(chain.sectionIndex) (\(chain.atoms.count) atoms, \(chain.sentenceCount) sentences) --")
            lines.append(copyFlattenedChain(chain))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Atom Diagnostic: Transition Matrix

    func computeAtomTransitionMatrix() {
        guard selectedMoveType != nil else { return }

        var transitionCounts: [String: [String: Int]] = [:]
        var totalCount = 0

        for section in sectionsForMove {
            for sentence in section.sentences {
                let slots = sentence.slotSequence
                for i in 0..<(slots.count - 1) {
                    transitionCounts[slots[i], default: [:]][slots[i + 1], default: 0] += 1
                    totalCount += 1
                }
            }
        }

        atomTransitionTotalCount = totalCount

        atomTransitionMatrix = transitionCounts.map { source, targets in
            let totalForSource = targets.values.reduce(0, +)
            let sorted = targets.sorted { $0.value > $1.value }
            let transitions = sorted.map { target, count in
                (targetSlotType: target, count: count, probability: totalForSource > 0 ? Double(count) / Double(totalForSource) : 0.0)
            }
            return AtomTransitionRow(
                id: source,
                sourceSlotType: source,
                totalTransitions: totalForSource,
                transitions: transitions
            )
        }.sorted { $0.totalTransitions > $1.totalTransitions }
    }

    func copyAtomTransitionMatrix() -> String {
        var lines: [String] = []
        lines.append("=== ATOM-LEVEL TRANSITION MATRIX ===")
        lines.append("Move: \(selectedMoveType ?? "none") | \(atomTransitionTotalCount) total transitions")
        lines.append("")

        // Full matrix as TSV
        let allTargets = Set(atomTransitionMatrix.flatMap { $0.transitions.map(\.targetSlotType) }).sorted()
        lines.append("FROM \\ TO\t" + allTargets.joined(separator: "\t"))

        for row in atomTransitionMatrix {
            let targetMap = Dictionary(row.transitions.map { ($0.targetSlotType, $0.probability) }, uniquingKeysWith: { a, _ in a })
            let cells = allTargets.map { target -> String in
                if let p = targetMap[target] {
                    return String(format: "%.2f", p)
                }
                return "."
            }
            lines.append("\(row.sourceSlotType)\t" + cells.joined(separator: "\t"))
        }

        lines.append("")
        lines.append("--- TOP 3 PER SOURCE ---")
        for row in atomTransitionMatrix {
            let top3Str = row.top3.map {
                "\($0.targetSlotType) (\(String(format: "%.1f%%", $0.probability * 100)))"
            }.joined(separator: ", ")
            lines.append("\(row.sourceSlotType) [\(row.totalTransitions)x]: \(top3Str)  H=\(String(format: "%.2f", row.entropy))/\(String(format: "%.2f", row.maxEntropy)) normH=\(String(format: "%.2f", row.normalizedEntropy))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Atom Diagnostic: Boundary Analysis

    func computeBoundaryAnalysis() {
        guard selectedMoveType != nil else { return }

        var crossBoundary: [String: [String: Int]] = [:]
        var withinSentence: [String: [String: Int]] = [:]
        var crossTotal = 0
        var withinTotal = 0

        for section in sectionsForMove {
            let sentences = section.sentences

            // Within-sentence transitions
            for sentence in sentences {
                let slots = sentence.slotSequence
                for i in 0..<(slots.count - 1) {
                    withinSentence[slots[i], default: [:]][slots[i + 1], default: 0] += 1
                    withinTotal += 1
                }
            }

            // Cross-boundary transitions
            for i in 0..<(sentences.count - 1) {
                let lastSlots = sentences[i].slotSequence
                let firstSlots = sentences[i + 1].slotSequence
                guard let lastAtom = lastSlots.last, let firstAtom = firstSlots.first else { continue }
                crossBoundary[lastAtom, default: [:]][firstAtom, default: 0] += 1
                crossTotal += 1
            }
        }

        // Build comparison table
        let allFromAtoms = Set(crossBoundary.keys).union(withinSentence.keys)
        let allToAtoms = Set(crossBoundary.values.flatMap(\.keys)).union(withinSentence.values.flatMap(\.keys))

        var comparisons: [BoundaryAnalysisResult.TransitionComparison] = []
        for from in allFromAtoms {
            for to in allToAtoms {
                let crossCount = crossBoundary[from]?[to] ?? 0
                let withinCount = withinSentence[from]?[to] ?? 0
                guard crossCount > 0 || withinCount > 0 else { continue }

                let crossPct = crossTotal > 0 ? Double(crossCount) / Double(crossTotal) : 0
                let withinPct = withinTotal > 0 ? Double(withinCount) / Double(withinTotal) : 0

                comparisons.append(.init(
                    id: "\(from) → \(to)",
                    fromSlotType: from,
                    toSlotType: to,
                    crossBoundaryCount: crossCount,
                    crossBoundaryPct: crossPct,
                    withinSentenceCount: withinCount,
                    withinSentencePct: withinPct,
                    delta: crossPct - withinPct
                ))
            }
        }

        let boundaryBiased = comparisons
            .sorted { $0.delta > $1.delta }
            .filter { $0.crossBoundaryCount >= 2 }
        let interiorBiased = comparisons
            .sorted { $0.delta < $1.delta }
            .filter { $0.withinSentenceCount >= 2 }

        let js = jensenShannonDivergence(crossBoundary, withinSentence, crossTotal, withinTotal)

        boundaryAnalysis = BoundaryAnalysisResult(
            crossBoundaryTransitions: crossBoundary,
            withinSentenceTransitions: withinSentence,
            crossBoundaryTotal: crossTotal,
            withinSentenceTotal: withinTotal,
            topBoundaryBiased: Array(boundaryBiased.prefix(15)),
            topInteriorBiased: Array(interiorBiased.prefix(15)),
            jsDivergence: js
        )
    }

    private func jensenShannonDivergence(
        _ dist1: [String: [String: Int]], _ dist2: [String: [String: Int]],
        _ total1: Int, _ total2: Int
    ) -> Double {
        var p: [String: Double] = [:]
        var q: [String: Double] = [:]

        for (from, targets) in dist1 {
            for (to, count) in targets {
                p["\(from)|\(to)"] = Double(count) / max(1, Double(total1))
            }
        }
        for (from, targets) in dist2 {
            for (to, count) in targets {
                q["\(from)|\(to)"] = Double(count) / max(1, Double(total2))
            }
        }

        let allKeys = Set(p.keys).union(q.keys)
        var js = 0.0
        for key in allKeys {
            let pVal = p[key] ?? 0
            let qVal = q[key] ?? 0
            let m = (pVal + qVal) / 2.0
            if pVal > 0 && m > 0 { js += 0.5 * pVal * log2(pVal / m) }
            if qVal > 0 && m > 0 { js += 0.5 * qVal * log2(qVal / m) }
        }
        return js
    }

    func copyBoundaryAnalysis() -> String {
        guard let analysis = boundaryAnalysis else { return "No boundary analysis computed." }

        var lines: [String] = []
        lines.append("=== SENTENCE BOUNDARY ANALYSIS ===")
        lines.append("Move: \(selectedMoveType ?? "none")")
        lines.append("Cross-boundary transitions: \(analysis.crossBoundaryTotal)")
        lines.append("Within-sentence transitions: \(analysis.withinSentenceTotal)")
        lines.append("Jensen-Shannon divergence: \(String(format: "%.4f", analysis.jsDivergence))")
        lines.append("")

        if analysis.jsDivergence > 0.1 {
            lines.append("VERDICT: Boundary transitions are SUBSTANTIALLY DIFFERENT from within-sentence transitions.")
            lines.append("Sentence breaks carry structural meaning — atom chains should respect sentence boundaries.")
        } else if analysis.jsDivergence > 0.03 {
            lines.append("VERDICT: Moderate difference between boundary and within-sentence transitions.")
            lines.append("Some structural signal at sentence breaks, but not overwhelming.")
        } else {
            lines.append("VERDICT: Boundary transitions look SIMILAR to within-sentence transitions.")
            lines.append("Sentence breaks may be arbitrary — pure atom-level chains could work without boundaries.")
        }

        lines.append("")
        lines.append("--- TOP BOUNDARY-ENRICHED TRANSITIONS (more common at sentence breaks) ---")
        for t in analysis.topBoundaryBiased {
            lines.append("\(t.fromSlotType) → \(t.toSlotType): boundary=\(String(format: "%.1f%%", t.crossBoundaryPct * 100)) (\(t.crossBoundaryCount)x) vs within=\(String(format: "%.1f%%", t.withinSentencePct * 100)) (\(t.withinSentenceCount)x) delta=\(String(format: "%+.1f%%", t.delta * 100))")
        }

        lines.append("")
        lines.append("--- TOP INTERIOR-ENRICHED TRANSITIONS (more common within sentences) ---")
        for t in analysis.topInteriorBiased {
            lines.append("\(t.fromSlotType) → \(t.toSlotType): within=\(String(format: "%.1f%%", t.withinSentencePct * 100)) (\(t.withinSentenceCount)x) vs boundary=\(String(format: "%.1f%%", t.crossBoundaryPct * 100)) (\(t.crossBoundaryCount)x) delta=\(String(format: "%+.1f%%", t.delta * 100))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Atom-Length Analysis Computation

    func computeAtomLengthAnalysis() {
        guard selectedMoveType != nil else { return }

        let sentences = sectionsForMove.flatMap(\.sentences)
        guard !sentences.isEmpty else { return }

        let totalSentences = sentences.count
        let totalAtoms = sentences.reduce(0) { $0 + $1.slotSequence.count }

        // ── Analysis 1: Atom Count Distribution ──────────────────────

        var bucketSentences: [Int: [CreatorSentence]] = [:]  // atomCount → sentences
        for s in sentences {
            let count = min(s.slotSequence.count, 5)  // cap at 5+
            bucketSentences[count, default: []].append(s)
        }

        let atomCountDistribution: [AtomCountBucket] = (1...5).compactMap { bucket in
            let group = bucketSentences[bucket] ?? []
            guard !group.isEmpty else { return nil }
            let avgWC = Double(group.reduce(0) { $0 + $1.wordCount }) / Double(group.count)
            return AtomCountBucket(
                id: bucket,
                atomCount: bucket,
                sentenceCount: group.count,
                fraction: Double(group.count) / Double(totalSentences),
                avgWordCount: avgWC
            )
        }

        // ── Analysis 2: Word Count by Atom Count (box-plot stats) ────

        let wordCountByAtomCount: [WordCountByAtomBucket] = (1...5).compactMap { bucket in
            let group = bucketSentences[bucket] ?? []
            guard !group.isEmpty else { return nil }
            let wcs = group.map(\.wordCount).sorted()
            let n = wcs.count
            let mean = Double(wcs.reduce(0, +)) / Double(n)
            let variance = n > 1
                ? wcs.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(n - 1)
                : 0.0
            return WordCountByAtomBucket(
                id: bucket,
                atomCount: bucket,
                sampleSize: n,
                min: wcs.first ?? 0,
                q1: percentile(wcs, 0.25),
                median: percentile(wcs, 0.5),
                q3: percentile(wcs, 0.75),
                max: wcs.last ?? 0,
                mean: mean,
                sd: sqrt(variance)
            )
        }

        // ── Analysis 3: Per-Atom Word Budget ─────────────────────────

        var atomOccurrences: [String: [(wordCount: Int, atomCount: Int)]] = [:]
        var atomSoloWordCounts: [String: [Int]] = [:]

        for s in sentences {
            let atomSet = Set(s.slotSequence)
            for atom in atomSet {
                atomOccurrences[atom, default: []].append((wordCount: s.wordCount, atomCount: s.slotSequence.count))
            }
            if s.slotSequence.count == 1, let only = s.slotSequence.first {
                atomSoloWordCounts[only, default: []].append(s.wordCount)
            }
        }

        let perAtomWordBudget: [AtomWordBudget] = atomOccurrences.map { atom, occurrences in
            let soloWCs = atomSoloWordCounts[atom] ?? []
            let soloAvg = soloWCs.isEmpty ? 0.0 : Double(soloWCs.reduce(0, +)) / Double(soloWCs.count)
            let avgWords = Double(occurrences.reduce(0) { $0 + $1.wordCount }) / Double(occurrences.count)
            let avgAtoms = Double(occurrences.reduce(0) { $0 + $1.atomCount }) / Double(occurrences.count)
            return AtomWordBudget(
                id: atom,
                atomType: atom,
                totalOccurrences: occurrences.count,
                soloSentenceCount: soloWCs.count,
                soloAvgWordCount: soloAvg,
                avgWordsInSentence: avgWords,
                avgAtomsInSentence: avgAtoms
            )
        }.sorted { $0.totalOccurrences > $1.totalOccurrences }

        // ── Analysis 4: Atom Co-Occurrence ───────────────────────────

        // For each sentence, build set of unique atoms present
        var sentenceAtomSets: [(atoms: Set<String>, sentence: CreatorSentence)] = []
        var atomToSentenceCount: [String: Int] = [:]
        var pairCount: [String: [String: Int]] = [:]  // atomA → { atomB: count }

        for s in sentences {
            let atomSet = Set(s.slotSequence)
            sentenceAtomSets.append((atoms: atomSet, sentence: s))
            for atom in atomSet {
                atomToSentenceCount[atom, default: 0] += 1
            }
            let atomList = Array(atomSet).sorted()
            for i in 0..<atomList.count {
                for j in 0..<atomList.count where i != j {
                    pairCount[atomList[i], default: [:]][atomList[j], default: 0] += 1
                }
            }
        }

        let atomCoOccurrence: [AtomCoOccurrenceRow] = atomToSentenceCount.map { atom, total in
            let coOccurring = (pairCount[atom] ?? [:]).map { other, count in
                (atomType: other, count: count, conditionalProb: Double(count) / Double(total))
            }.sorted { $0.conditionalProb > $1.conditionalProb }
            return AtomCoOccurrenceRow(
                id: atom,
                atomType: atom,
                totalSentencesContaining: total,
                topCoOccurring: coOccurring
            )
        }.sorted { $0.totalSentencesContaining > $1.totalSentencesContaining }

        // ── Analysis 5: Atom Position Distribution ───────────────────

        var positionData: [String: (counts: [Int: Int], total: Int, firstCount: Int, lastCount: Int)] = [:]

        for s in sentences {
            let slots = s.slotSequence
            for (idx, atom) in slots.enumerated() {
                var entry = positionData[atom] ?? (counts: [:], total: 0, firstCount: 0, lastCount: 0)
                entry.counts[idx, default: 0] += 1
                entry.total += 1
                if idx == 0 { entry.firstCount += 1 }
                if idx == slots.count - 1 { entry.lastCount += 1 }
                positionData[atom] = entry
            }
        }

        let atomPositionDistribution: [AtomPositionRow] = positionData.map { atom, data in
            AtomPositionRow(
                id: atom,
                atomType: atom,
                positionCounts: data.counts,
                totalOccurrences: data.total,
                firstPositionFraction: data.total > 0 ? Double(data.firstCount) / Double(data.total) : 0,
                lastPositionFraction: data.total > 0 ? Double(data.lastCount) / Double(data.total) : 0
            )
        }.sorted { $0.totalOccurrences > $1.totalOccurrences }

        // ── Analysis 6: Sentence Break Probability ───────────────────

        var breakCounts: [String: [String: Int]] = [:]     // fromAtom → toAtom → break count
        var continueCounts: [String: [String: Int]] = [:]  // fromAtom → toAtom → continue count

        for section in sectionsForMove {
            let sents = section.sentences
            // Within-sentence continuations
            for s in sents {
                let slots = s.slotSequence
                for i in 0..<(slots.count - 1) {
                    continueCounts[slots[i], default: [:]][slots[i + 1], default: 0] += 1
                }
            }
            // Cross-sentence breaks
            for i in 0..<(sents.count - 1) {
                guard let lastAtom = sents[i].slotSequence.last,
                      let firstAtom = sents[i + 1].slotSequence.first else { continue }
                breakCounts[lastAtom, default: [:]][firstAtom, default: 0] += 1
            }
        }

        let allFromAtoms = Set(breakCounts.keys).union(continueCounts.keys)
        var sentenceBreakMatrix: [SentenceBreakRow] = []

        for from in allFromAtoms {
            let breakTargets = breakCounts[from] ?? [:]
            let continueTargets = continueCounts[from] ?? [:]
            let allTo = Set(breakTargets.keys).union(continueTargets.keys)
            for to in allTo {
                let bk = breakTargets[to] ?? 0
                let ct = continueTargets[to] ?? 0
                let total = bk + ct
                guard total >= 3 else { continue }  // filter noise
                sentenceBreakMatrix.append(SentenceBreakRow(
                    id: "\(from) → \(to)",
                    fromAtom: from,
                    toAtom: to,
                    breakCount: bk,
                    continueCount: ct,
                    breakProbability: Double(bk) / Double(total)
                ))
            }
        }
        sentenceBreakMatrix.sort { $0.breakProbability > $1.breakProbability }

        // ── Assemble result ──────────────────────────────────────────

        atomLengthAnalysis = AtomLengthAnalysis(
            atomCountDistribution: atomCountDistribution,
            wordCountByAtomCount: wordCountByAtomCount,
            perAtomWordBudget: perAtomWordBudget,
            atomCoOccurrence: atomCoOccurrence,
            atomPositionDistribution: atomPositionDistribution,
            sentenceBreakMatrix: sentenceBreakMatrix,
            totalSentences: totalSentences,
            totalAtoms: totalAtoms
        )
    }

    /// Percentile helper for sorted Int arrays (linear interpolation)
    private func percentile(_ sorted: [Int], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let n = Double(sorted.count)
        let rank = p * (n - 1)
        let lower = Int(floor(rank))
        let upper = min(lower + 1, sorted.count - 1)
        let frac = rank - Double(lower)
        return Double(sorted[lower]) * (1 - frac) + Double(sorted[upper]) * frac
    }

    // MARK: - Atom-Length Copy

    func copyAtomLengthAnalysis() -> String {
        guard let a = atomLengthAnalysis else { return "No atom-length analysis computed." }

        var lines: [String] = []
        lines.append("=== ATOM-LENGTH ANALYSIS ===")
        lines.append("Move: \(selectedMoveType ?? "none")")
        lines.append("Total sentences: \(a.totalSentences) | Total atoms: \(a.totalAtoms)")
        lines.append("Avg atoms/sentence: \(String(format: "%.2f", Double(a.totalAtoms) / max(1, Double(a.totalSentences))))")
        lines.append("")

        // Analysis 1
        lines.append("--- ATOM COUNT DISTRIBUTION ---")
        for b in a.atomCountDistribution {
            let label = b.atomCount == 5 ? "5+" : "\(b.atomCount)"
            lines.append("  \(label)-atom: \(b.sentenceCount) sentences (\(String(format: "%.1f%%", b.fraction * 100))) avg \(String(format: "%.1f", b.avgWordCount)) words")
        }
        lines.append("")

        // Analysis 2
        lines.append("--- WORD COUNT BY ATOM COUNT ---")
        lines.append("  Atoms |   N | Min |  Q1 |  Med |  Q3 | Max | Mean |   SD")
        for b in a.wordCountByAtomCount {
            let label = b.atomCount == 5 ? "   5+" : String(format: "%4d", b.atomCount)
            lines.append("  \(label) | \(String(format: "%3d", b.sampleSize)) | \(String(format: "%3d", b.min)) | \(String(format: "%4.1f", b.q1)) | \(String(format: "%4.1f", b.median)) | \(String(format: "%4.1f", b.q3)) | \(String(format: "%3d", b.max)) | \(String(format: "%4.1f", b.mean)) | \(String(format: "%4.1f", b.sd))")
        }
        lines.append("")

        // Analysis 3
        lines.append("--- PER-ATOM WORD BUDGET ---")
        lines.append("  Atom Type              | Total | Solo |  Solo Avg WC | Avg WC in Sent | Avg Atoms")
        for b in a.perAtomWordBudget {
            let name = b.atomType.padding(toLength: 24, withPad: " ", startingAt: 0)
            lines.append("  \(name) | \(String(format: "%5d", b.totalOccurrences)) | \(String(format: "%4d", b.soloSentenceCount)) | \(String(format: "%12.1f", b.soloAvgWordCount)) | \(String(format: "%14.1f", b.avgWordsInSentence)) | \(String(format: "%9.2f", b.avgAtomsInSentence))")
        }
        lines.append("")

        // Analysis 4
        lines.append("--- ATOM CO-OCCURRENCE (P(B|A) in same sentence) ---")
        for row in a.atomCoOccurrence {
            let top = row.topCoOccurring.prefix(5).map { "\($0.atomType) \(String(format: "%.0f%%", $0.conditionalProb * 100))" }.joined(separator: ", ")
            lines.append("  \(row.atomType) (\(row.totalSentencesContaining) sents): \(top)")
        }
        lines.append("")

        // Analysis 5
        lines.append("--- ATOM POSITION DISTRIBUTION ---")
        for row in a.atomPositionDistribution {
            lines.append("  \(row.atomType) (\(row.totalOccurrences)x): first=\(String(format: "%.0f%%", row.firstPositionFraction * 100)) last=\(String(format: "%.0f%%", row.lastPositionFraction * 100))")
        }
        lines.append("")

        // Analysis 6
        lines.append("--- SENTENCE BREAK PROBABILITY (P(break) between atom pairs) ---")
        lines.append("  From → To                              | Break | Cont | P(break)")
        for row in a.sentenceBreakMatrix {
            let pair = "\(row.fromAtom) → \(row.toAtom)".padding(toLength: 40, withPad: " ", startingAt: 0)
            lines.append("  \(pair) | \(String(format: "%5d", row.breakCount)) | \(String(format: "%4d", row.continueCount)) | \(String(format: "%.2f", row.breakProbability))")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Seeded RNG

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
