//
//  GroundTruthViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/27/26.
//

import SwiftUI

@MainActor
class GroundTruthViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isRunning = false
    @Published var progressPhase: String = ""
    @Published var progressValue: Double = 0
    @Published var result: GroundTruthResult?
    @Published var errorMessage: String?

    // Filters
    @Published var showOnlyVoted = false
    @Published var filterTier: ConsensusTier?

    // Sliding window config
    @Published var windowSize: Int = 5
    @Published var stepSize: Int = 2
    @Published var temperature: Double = 0.3
    @Published var slidingWindowRunCount: Int = 1

    // MARK: - Data

    let video: YouTubeVideo
    private var sentences: [SentenceTelemetry] = []

    init(video: YouTubeVideo) {
        self.video = video
        loadFromDefaults()
    }

    // MARK: - Load Sentences

    func loadSentences() async {
        do {
            let runs = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
            if let latestRun = runs.first {
                sentences = latestRun.sentences
            }
        } catch {
            errorMessage = "Failed to load sentences: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    func loadFromDefaults() {
        result = GroundTruthStorage.load(videoId: video.videoId)
    }

    private func saveToDefaults() {
        guard let result else { return }
        GroundTruthStorage.save(result)
    }

    // MARK: - Run Analysis

    func runAnalysis() async {
        guard !sentences.isEmpty else {
            errorMessage = "No sentence data available. Run sentence fidelity test first."
            return
        }
        guard let transcript = video.transcript, !transcript.isEmpty else {
            errorMessage = "No transcript available."
            return
        }

        isRunning = true
        errorMessage = nil
        progressPhase = "Starting..."
        progressValue = 0

        result = await GroundTruthEngine.shared.runFullAnalysis(
            video: video,
            sentences: sentences,
            transcript: transcript,
            windowSize: windowSize,
            stepSize: stepSize,
            temperature: temperature,
            slidingWindowRunCount: slidingWindowRunCount
        ) { [weak self] phase, progress in
            Task { @MainActor in
                self?.progressPhase = phase
                self?.progressValue = progress
            }
        }

        saveToDefaults()
        isRunning = false
    }

    // MARK: - Additional Run

    var currentRunCount: Int {
        result?.slidingWindowRuns?.count ?? (result != nil ? 1 : 0)
    }

    func runAdditionalPass() async {
        guard let currentResult = result, !sentences.isEmpty,
              let transcript = video.transcript, !transcript.isEmpty else {
            errorMessage = "Cannot add run — no existing result or transcript."
            return
        }

        isRunning = true
        errorMessage = nil
        progressPhase = "Running additional pass..."
        progressValue = 0

        result = await GroundTruthEngine.shared.runAdditionalSlidingWindow(
            existingResult: currentResult,
            transcript: transcript,
            windowSize: windowSize,
            stepSize: stepSize,
            temperature: temperature
        ) { [weak self] phase, progress in
            Task { @MainActor in
                self?.progressPhase = phase
                self?.progressValue = progress
            }
        }

        saveToDefaults()
        isRunning = false
    }

    // MARK: - Manual Override

    func toggleManualOverride(gapIndex: Int) {
        guard var currentResult = result,
              let idx = currentResult.gapVotes.firstIndex(where: { $0.gapAfterSentenceIndex == gapIndex }) else {
            return
        }

        // Cycle: nil → true → false → nil
        let current = currentResult.gapVotes[idx].manualOverride
        switch current {
        case nil:
            currentResult.gapVotes[idx].manualOverride = true
        case true:
            currentResult.gapVotes[idx].manualOverride = false
        case false:
            currentResult.gapVotes[idx].manualOverride = nil
        default:
            break
        }

        result = currentResult
        saveToDefaults()
    }

    // MARK: - Copy Transcript

    var hasSentences: Bool { !sentences.isEmpty }

    func copyRawTranscript() {
        guard !sentences.isEmpty else { return }
        var text = "TRANSCRIPT: \(video.title)\n"
        text += "\(sentences.count) sentences\n"
        text += "════════════════════════════════════════\n\n"
        for s in sentences {
            text += "[\(s.sentenceIndex + 1)] \(s.text)\n"
        }
        UIPasteboard.general.string = text
    }

    func copyTranscriptDigressionsRemoved() async {
        guard !sentences.isEmpty else { return }
        let digressionResult = await DigressionDetectionService.shared.detectDigressions(from: sentences, config: .default)
        let excludeSet = DigressionDetectionService.shared.buildExcludeSet(from: digressionResult.digressions)

        var text = "TRANSCRIPT (DIGRESSIONS REMOVED): \(video.title)\n"
        text += "\(sentences.count) total, \(excludeSet.count) excluded, \(sentences.count - excludeSet.count) kept\n"
        text += "════════════════════════════════════════\n\n"
        for s in sentences {
            if excludeSet.contains(s.sentenceIndex) { continue }
            text += "[\(s.sentenceIndex + 1)] \(s.text)\n"
        }
        UIPasteboard.general.string = text
    }

    // MARK: - Copy Scoring

    func copyScoring() {
        guard let result else { return }
        let tm = result.totalMethods
        var lines: [String] = []

        lines.append("════════════════════════════════════════")
        lines.append("GROUND TRUTH — SCORING REPORT")
        lines.append("════════════════════════════════════════")
        lines.append("Video: \(video.title)")
        lines.append("Methods: \(result.activeMethods.map { $0.shortLabel }.joined(separator: ", "))")
        lines.append("\(result.gapVotes.count) boundaries found")
        lines.append("")

        for vote in result.gapVotes {
            let tier = result.tier(for: vote)
            let tierLabel = tier?.label(totalMethods: tm) ?? "0/\(tm)"
            let tierName: String
            switch tier {
            case .definite: tierName = "DEFINITE"
            case .probable: tierName = "PROBABLE"
            case .contested: tierName = "CONTESTED"
            case .weak: tierName = "WEAK"
            case nil: tierName = ""
            }

            lines.append("┌─────────────────────────────────────────")
            lines.append("│  [\(vote.gapAfterSentenceIndex + 1)] — \(tierLabel) \(tierName)")
            lines.append("│  \"\(String(vote.sentenceText.prefix(70)))\"")
            lines.append("│")

            let methodDots = result.activeMethods.map { m -> String in
                let voted = vote.votes.contains(m)
                return "\(m.shortLabel) \(voted ? "●" : "○")"
            }.joined(separator: "  ")
            lines.append("│  Methods: \(methodDots)")

            for methodResult in result.methodResults {
                let m = methodResult.method
                let voted = vote.votes.contains(m)
                let detail = methodResult.detail(forGap: vote.gapAfterSentenceIndex)

                if voted {
                    switch m {
                    case .deterministicClean, .deterministicDigression:
                        let trigger = detail?.triggerType ?? "unknown"
                        let conf = detail?.triggerConfidence ?? "?"
                        lines.append("│  [\(m.shortLabel)]  \(trigger) (\(conf))")
                    case .slidingWindowP1:
                        let wv = detail?.windowVotes ?? 0
                        let wo = detail?.windowsOverlapping ?? 0
                        let pct = wo > 0 ? Int(Double(wv) / Double(wo) * 100) : 0
                        lines.append("│  [W1] \(wv)/\(wo) windows (\(pct)%)")
                    case .slidingWindowLLM:
                        let wv = detail?.windowVotes ?? 0
                        let wo = detail?.windowsOverlapping ?? 0
                        let pct = wo > 0 ? Int(Double(wv) / Double(wo) * 100) : 0
                        let change = detail?.passChange ?? ""
                        let changeLabel = change.isEmpty ? "" : " — \(change)"
                        lines.append("│  [W]  \(wv)/\(wo) windows (\(pct)%)\(changeLabel)")
                    case .singleShotLLM:
                        lines.append("│  [S]  consensus vote")
                    }
                } else {
                    if m == .slidingWindowLLM, let change = detail?.passChange, change.contains("REVOKED") {
                        lines.append("│  [\(m.shortLabel)]  — (revoked by pass 2)")
                    } else {
                        lines.append("│  [\(m.shortLabel)]  —")
                    }
                }
            }

            if let override = vote.manualOverride {
                lines.append("│  MANUAL: \(override ? "CONFIRMED" : "REJECTED")")
            }
            lines.append("└─────────────────────────────────────────")
            lines.append("")
        }

        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    // MARK: - Copy Alignment

    func copyAlignment() {
        guard let result else { return }
        let tm = result.totalMethods
        let runs = result.allAlignmentRuns
        var lines: [String] = []

        lines.append("════════════════════════════════════════")
        lines.append("GROUND TRUTH — ALIGNMENT MATRIX (\(runs.count) runs)")
        lines.append("════════════════════════════════════════")
        lines.append("Video: \(video.title)")
        lines.append("")

        // Header — use fixed-width columns for each run label
        let colWidth = max(5, (runs.map { $0.label.count }.max() ?? 4) + 1)
        let runHeaders = runs.map { $0.label.padding(toLength: colWidth, withPad: " ", startingAt: 0) }.joined()
        lines.append("Gap     \(runHeaders)Tier")
        lines.append("────────\(String(repeating: "─", count: colWidth * runs.count))────")

        for vote in result.gapVotes {
            let tier = result.tier(for: vote)
            let tierLabel = tier?.label(totalMethods: tm) ?? "?"
            let gapLabel = "[\(vote.gapAfterSentenceIndex + 1)]".padding(toLength: 8, withPad: " ", startingAt: 0)
            let dots = runs.map { run -> String in
                let voted = run.boundaryGapIndices.contains(vote.gapAfterSentenceIndex)
                return (voted ? "●" : "○").padding(toLength: colWidth, withPad: " ", startingAt: 0)
            }.joined()
            lines.append("\(gapLabel)\(dots)\(tierLabel)")
        }

        lines.append("")
        lines.append("● = boundary  ○ = no boundary")
        lines.append("Runs: \(runs.map { $0.label }.joined(separator: ", "))")

        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    // MARK: - Filtered Votes

    var filteredVotes: [SentenceGapVote] {
        guard let result else { return [] }
        var votes = result.gapVotes

        if let tier = filterTier {
            votes = votes.filter { result.tier(for: $0) == tier }
        }

        return votes
    }

    // MARK: - Export

    var exportText: String {
        generateFullReport(sentences: sentences)
    }

    /// Full variability report — sentence-by-sentence timeline showing ALL methods' decisions
    func generateFullReport(sentences: [SentenceTelemetry]) -> String {
        guard let result else { return "No results" }

        let tm = result.totalMethods
        let methods = result.activeMethods
        let methodLabels = methods.map { $0.shortLabel }.joined(separator: ", ")

        var lines: [String] = []

        // Header
        lines.append("════════════════════════════════════════")
        lines.append("GROUND TRUTH — FULL VARIABILITY REPORT")
        lines.append("════════════════════════════════════════")
        lines.append("Video: \(video.title)")
        lines.append("Sentences: \(result.totalSentences)")
        lines.append("Methods: \(methodLabels)")
        lines.append("Generated: \(result.createdAt)")
        lines.append("")

        // Method summary
        lines.append("METHOD SUMMARY:")
        for methodResult in result.methodResults {
            let m = methodResult.method
            let count = methodResult.boundaryGapIndices.count
            switch m {
            case .deterministicClean:
                lines.append("  [R]  Deterministic Clean: \(count) boundaries")
            case .deterministicDigression:
                lines.append("  [RD] Deterministic DigrEx: \(count) boundaries")
            case .slidingWindowP1:
                lines.append("  [W1] Sliding Window Pass 1: \(count) boundaries")
            case .slidingWindowLLM:
                let pass1Count = methodResult.pass1GapIndices?.count ?? methodResult.unanimousCount ?? 0
                let finalCount = methodResult.majorityCount ?? count
                lines.append("  [W]  Sliding Window (P1+P2): \(finalCount) final")
                lines.append("       Pass 1 consensus: \(pass1Count) boundaries")
                lines.append("       Final (pass 1+2): \(finalCount) boundaries")
                if let pass1Set = methodResult.pass1GapIndices {
                    let finalSet = methodResult.boundaryGapIndices
                    let bothPasses = pass1Set.intersection(finalSet)
                    let revokedByPass2 = pass1Set.subtracting(finalSet)
                    let addedByPass2 = finalSet.subtracting(pass1Set)
                    lines.append("       Confirmed: \(bothPasses.count), Revoked: \(revokedByPass2.count), Added: \(addedByPass2.count)")
                }
            case .singleShotLLM:
                if let runs = methodResult.internalRunCount {
                    lines.append("  [S]  Single-Shot (\(runs) runs): \(count) consensus")
                } else {
                    lines.append("  [S]  Single-Shot: \(count) boundaries")
                }
            }
            lines.append("       Duration: \(String(format: "%.1f", methodResult.runDuration))s")
        }

        lines.append("")
        lines.append("CONSENSUS:")
        let tierDef = ConsensusTier.definite.label(totalMethods: tm)
        let tierProb = ConsensusTier.probable.label(totalMethods: tm)
        let tierCont = ConsensusTier.contested.label(totalMethods: tm)
        lines.append("  \(tierDef) (definite):  \(result.definiteCount)")
        lines.append("  \(tierProb) (probable):  \(result.probableCount)")
        if tm >= 4 {
            lines.append("  \(tierCont) (contested): \(result.contestedCount)")
        }
        lines.append("  1/\(tm) (weak):      \(result.weakCount)")
        lines.append("  Deserts: \(result.deserts.count)")
        lines.append("")

        // Build a set of gap indices with votes for quick lookup
        let votedGaps: [Int: SentenceGapVote] = Dictionary(
            result.gapVotes.map { ($0.gapAfterSentenceIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Sentence timeline
        lines.append("════════════════════════════════════════")
        lines.append("SENTENCE TIMELINE")
        lines.append("════════════════════════════════════════")
        lines.append("")

        let totalSentences = sentences.isEmpty ? result.totalSentences : sentences.count

        for i in 0..<totalSentences {
            let sentenceText: String
            if i < sentences.count {
                sentenceText = String(sentences[i].text.prefix(60))
            } else {
                sentenceText = "(sentence \(i + 1))"
            }

            // Method status for this sentence's gap
            let methodStatus = methods.map { m -> String in
                let methodResult = result.methodResults.first { $0.method == m }
                let hasBoundary = methodResult?.boundaryGapIndices.contains(i) ?? false
                return "\(m.shortLabel):\(hasBoundary ? "B" : "-")"
            }.joined(separator: " ")

            lines.append("[\(i + 1)] \"\(sentenceText)\" | \(methodStatus)")

            // If there's a boundary after this sentence, show full detail
            if let vote = votedGaps[i] {
                let tierLabel = result.tier(for: vote)?.label(totalMethods: tm) ?? "0/\(tm)"
                let agreedMethods = vote.votes.map { $0.shortLabel }.joined(separator: ",")
                lines.append("  ═══ BOUNDARY AFTER [\(i + 1)] — \(tierLabel) [\(agreedMethods)] ═══")

                // Show each method's decision
                for methodResult in result.methodResults {
                    let m = methodResult.method
                    let hasBoundary = methodResult.boundaryGapIndices.contains(i)
                    let detail = methodResult.detail(forGap: i)

                    if hasBoundary {
                        switch m {
                        case .deterministicClean, .deterministicDigression:
                            let trigger = detail?.triggerType ?? "unknown"
                            let conf = detail?.triggerConfidence ?? "?"
                            lines.append("  [\(m.shortLabel)]  Triggered: \(trigger) (\(conf))")

                        case .slidingWindowP1:
                            let votes = detail?.windowVotes ?? 0
                            let total = detail?.windowsOverlapping ?? 0
                            lines.append("  [W1] Triggered: \(votes)/\(total) windows voted")
                            if let reasons = detail?.windowReasons, !reasons.isEmpty {
                                for reason in reasons.prefix(3) {
                                    lines.append("       reason: \"\(String(reason.prefix(80)))\"")
                                }
                            }

                        case .slidingWindowLLM:
                            let votes = detail?.windowVotes ?? 0
                            let total = detail?.windowsOverlapping ?? 0
                            let pass = detail?.passChange ?? "unknown"
                            lines.append("  [W]  Triggered: \(votes)/\(total) windows voted — \(pass)")
                            if let reasons = detail?.windowReasons, !reasons.isEmpty {
                                for reason in reasons.prefix(3) {
                                    lines.append("       reason: \"\(String(reason.prefix(80)))\"")
                                }
                            }
                            if let inP1 = detail?.inPass1, let inF = detail?.inFinal {
                                if inP1 && inF {
                                    lines.append("       Pass 1: YES → Pass 2: confirmed")
                                } else if inP1 && !inF {
                                    lines.append("       Pass 1: YES → Pass 2: REVOKED")
                                } else if !inP1 && inF {
                                    lines.append("       Pass 1: NO → Pass 2: ADDED")
                                }
                            }

                        case .singleShotLLM:
                            lines.append("  [S]  Triggered")
                        }
                    } else {
                        // Method did NOT fire at this gap
                        switch m {
                        case .deterministicDigression:
                            lines.append("  [RD] NO BOUNDARY")
                        case .slidingWindowP1:
                            lines.append("  [W1] NO BOUNDARY")
                        case .slidingWindowLLM:
                            if let pass1Set = methodResult.pass1GapIndices, pass1Set.contains(i) {
                                lines.append("  [W]  NO BOUNDARY (was in pass 1, REVOKED by pass 2)")
                                if let reasons = detail?.windowReasons, !reasons.isEmpty {
                                    lines.append("       original reasons: \"\(String(reasons.first!.prefix(80)))\"")
                                }
                            } else {
                                lines.append("  [W]  NO BOUNDARY")
                            }
                        default:
                            lines.append("  [\(m.shortLabel)]  NO BOUNDARY")
                        }
                    }
                }

                // Manual override status
                if let override = vote.manualOverride {
                    lines.append("  MANUAL: \(override ? "CONFIRMED" : "REJECTED")")
                }
                lines.append("")
            }
        }

        // Deserts
        if !result.deserts.isEmpty {
            lines.append("")
            lines.append("────────────────────────────────────────")
            lines.append("DESERTS (10+ consecutive 0-vote gaps)")
            lines.append("────────────────────────────────────────")
            for desert in result.deserts {
                lines.append("  Sentences \(desert.startSentenceIndex)-\(desert.endSentenceIndex) (\(desert.sentenceCount) gaps)")
            }
        }

        lines.append("")
        lines.append("════════════════════════════════════════")
        return lines.joined(separator: "\n")
    }
}
