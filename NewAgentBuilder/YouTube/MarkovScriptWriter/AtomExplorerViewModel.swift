//
//  AtomExplorerViewModel.swift
//  NewAgentBuilder
//
//  ViewModel for the Atom Explorer tab.
//  Loads corpus sentences, rebuilds atom transition matrix per move type,
//  and manages the interactive sequence builder state.
//

import Foundation

@MainActor
class AtomExplorerViewModel: ObservableObject {

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

    // MARK: - Move Type Selection

    @Published var selectedMoveType: String?

    var availableMoveTypes: [String] {
        let moveTypes = Set(coordinator.donorSentences.map(\.moveType))
        return moveTypes.sorted()
    }

    // MARK: - Sections & Matrix

    var sectionsForMove: [StructureWorkbenchViewModel.ReconstructedSection] = []
    @Published var atomMatrix: AtomTransitionMatrix?

    // MARK: - Sequence Builder State

    @Published var explorerPath: [String] = []
    @Published var historyDepth: Int = 2  // 1 = bigram, 2 = trigram

    // MARK: - Init

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Data Loading

    func loadCorpusData() async {
        guard dataState != .loading else { return }

        // If coordinator already has data, skip Firebase load
        if coordinator.donorCorpusState == .loaded {
            loadingProgress = "\(coordinator.donorSentences.count) sentences (cached)"
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

        loadingProgress = "\(coordinator.donorSentences.count) sentences loaded"
        dataState = .ready

        if selectedMoveType == nil, let first = availableMoveTypes.first {
            selectMoveType(first)
        }
    }

    // MARK: - Move Type Selection

    func selectMoveType(_ moveType: String) {
        selectedMoveType = moveType
        explorerPath = []

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

        atomMatrix = SkeletonGeneratorService.buildAtomTransitionMatrix(from: sectionsForMove)
    }

    // MARK: - Sequence Builder

    func startSequence(with atom: String) {
        explorerPath = [atom]
    }

    func extendSequence(with atom: String) {
        explorerPath.append(atom)
    }

    func clearSequence() {
        explorerPath = []
    }

    /// Returns ranked next atoms, trigram-aware if depth >= 2 and path has 2+ atoms
    func nextAtoms(topK: Int = 10) -> [(atom: String, probability: Double, count: Int)] {
        guard let matrix = atomMatrix, let last = explorerPath.last else { return [] }

        if historyDepth >= 2, explorerPath.count >= 2 {
            let prev = explorerPath[explorerPath.count - 2]
            let trigramResults = matrix.trigramNextAtoms(prev: prev, current: last, topK: topK)
            if !trigramResults.isEmpty {
                return trigramResults
            }
        }

        return matrix.topNextAtoms(after: last, topK: topK)
    }

    /// Whether the current path is a dead end (no continuations)
    var isDeadEnd: Bool {
        !explorerPath.isEmpty && nextAtoms(topK: 1).isEmpty
    }

    /// Which lookup type was used for the current path end
    var lookupType: String {
        guard let matrix = atomMatrix, explorerPath.count >= 2, historyDepth >= 2 else {
            return "bigram"
        }
        let prev = explorerPath[explorerPath.count - 2]
        let current = explorerPath.last!
        let trigramResults = matrix.trigramNextAtoms(prev: prev, current: current, topK: 1)
        return trigramResults.isEmpty ? "bigram (trigram fallback)" : "trigram"
    }

    /// Break probability between last two atoms in path
    var lastBreakProbability: Double? {
        guard let matrix = atomMatrix, explorerPath.count >= 2 else { return nil }
        let prev = explorerPath[explorerPath.count - 2]
        let current = explorerPath[explorerPath.count - 1]
        return matrix.breakProbabilities[prev]?[current]
    }

    // MARK: - Source Proof

    struct SentenceMatch: Identifiable {
        let id = UUID()
        let videoId: String
        let sectionKey: String
        let sentenceText: String
        let fullSlotSequence: [String]
        let matchStartIndex: Int
    }

    /// Find corpus sentences whose slotSequence contains the pattern as a contiguous subsequence
    func findSentencesMatchingPattern(_ pattern: [String]) -> [SentenceMatch] {
        guard !pattern.isEmpty else { return [] }
        let moveSentences = coordinator.donorSentences.filter { $0.moveType == selectedMoveType }

        var matches: [SentenceMatch] = []
        for sentence in moveSentences {
            let slots = sentence.slotSequence
            guard slots.count >= pattern.count else { continue }
            for start in 0...(slots.count - pattern.count) {
                let slice = Array(slots[start..<(start + pattern.count)])
                if slice == pattern {
                    matches.append(SentenceMatch(
                        videoId: sentence.videoId,
                        sectionKey: "\(sentence.videoId)_\(sentence.sectionIndex)",
                        sentenceText: sentence.rawText,
                        fullSlotSequence: slots,
                        matchStartIndex: start
                    ))
                    break
                }
            }
        }
        return matches
    }

    // MARK: - Phrase Drill-Down

    struct PhraseMatch: Identifiable {
        let id = UUID()
        let sentenceText: String
        let phraseTexts: [String]
        let combinedPhrase: String
        let videoId: String
    }

    /// Find actual phrase text for every occurrence of an atom n-gram pattern in the corpus.
    /// Captures all matches per sentence (a sentence with the pattern at positions 0-1 AND 4-5 yields two entries).
    func findPhrasesForPattern(_ atomPattern: [String]) -> [PhraseMatch] {
        guard !atomPattern.isEmpty else { return [] }
        let moveSentences = coordinator.donorSentences.filter { $0.moveType == selectedMoveType }

        var matches: [PhraseMatch] = []
        for sentence in moveSentences {
            guard let phrases = sentence.phrases, !phrases.isEmpty else { continue }
            let roles = phrases.map(\.role)
            guard roles.count >= atomPattern.count else { continue }

            for start in 0...(roles.count - atomPattern.count) {
                let slice = Array(roles[start..<(start + atomPattern.count)])
                if slice == atomPattern {
                    let matchedPhrases = phrases[start..<(start + atomPattern.count)]
                    let texts = matchedPhrases.map(\.text)
                    matches.append(PhraseMatch(
                        sentenceText: sentence.rawText,
                        phraseTexts: texts,
                        combinedPhrase: texts.joined(separator: " "),
                        videoId: sentence.videoId
                    ))
                }
            }
        }
        return matches
    }

    /// Count within-sentence occurrences using slotSequence (always present, matches row count).
    func countSlotSequenceMatches(_ pattern: [String]) -> Int {
        guard !pattern.isEmpty else { return 0 }
        let moveSentences = coordinator.donorSentences.filter { $0.moveType == selectedMoveType }
        var count = 0
        for sentence in moveSentences {
            let slots = sentence.slotSequence
            guard slots.count >= pattern.count else { continue }
            for start in 0...(slots.count - pattern.count) {
                if Array(slots[start..<(start + pattern.count)]) == pattern {
                    count += 1
                }
            }
        }
        return count
    }

    /// Format all phrase matches for clipboard — one combined phrase per line
    func copyablePhrasesReport(_ atomPattern: [String]) -> String {
        let matches = findPhrasesForPattern(atomPattern)
        let patternLabel = atomPattern.joined(separator: " \u{2192} ")
        var lines: [String] = []
        lines.append("Phrases for: \(patternLabel)")
        lines.append("\(matches.count) matches")
        lines.append("")
        for match in matches {
            lines.append(match.combinedPhrase)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - N-gram Computation

    /// Compute 4-grams within sentences only (no cross-boundary inflation)
    func computeFourgrams(topK: Int = 20) -> [(pattern: String, count: Int)] {
        var fourgrams: [String: Int] = [:]
        for section in sectionsForMove {
            for sentence in section.sentences {
                let slots = sentence.slotSequence
                guard slots.count >= 4 else { continue }
                for i in 0..<(slots.count - 3) {
                    let key = "\(slots[i]) \u{2192} \(slots[i+1]) \u{2192} \(slots[i+2]) \u{2192} \(slots[i+3])"
                    fourgrams[key, default: 0] += 1
                }
            }
        }
        return fourgrams.sorted { $0.value > $1.value }.prefix(topK).map { ($0.key, $0.value) }
    }

    // MARK: - Report

    func buildReport() -> String {
        guard let matrix = atomMatrix, let move = selectedMoveType else {
            return "No matrix built."
        }

        var lines: [String] = []
        lines.append("Atom Explorer Report — Move: \(move)")
        lines.append("Sections: \(sectionsForMove.count)")
        lines.append("Total Transitions: \(matrix.totalTransitionCount)")
        lines.append("Unique Atom Types: \(matrix.atomCounts.count)")
        lines.append("Total Atoms: \(matrix.atomCounts.values.reduce(0, +))")
        lines.append("")

        lines.append("--- Atoms by Frequency ---")
        for item in matrix.atomsByFrequency() {
            lines.append("  \(item.atom): \(item.count)")
        }
        lines.append("")

        lines.append("--- Top Bigrams ---")
        for item in matrix.globalAtomBigrams(topK: 30) {
            lines.append("  \(item.pattern): \(item.count)")
        }
        lines.append("")

        lines.append("--- Top Trigrams ---")
        for item in matrix.globalAtomTrigrams(topK: 30) {
            lines.append("  \(item.pattern): \(item.count)")
        }
        lines.append("")

        lines.append("--- Top 4-grams ---")
        for item in computeFourgrams(topK: 20) {
            lines.append("  \(item.pattern): \(item.count)")
        }

        return lines.joined(separator: "\n")
    }
}
