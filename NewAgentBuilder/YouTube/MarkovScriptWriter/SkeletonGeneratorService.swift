//
//  SkeletonGeneratorService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/24/26.
//  v2 revision: 3/24/26 — trigram conditioning, position-aware breaks, per-path fixes.
//  v3 revision: 3/24/26 — three-zone break ramp, content pointer (P2), dynamic intent (P1),
//      dual scoring (P4), recency penalty (P5), ScriptFidelityService tagger (P3).
//
//  Stateless service: all 6 skeleton generation algorithms + shared utilities.
//  Each path takes an AtomTransitionMatrix, config, and corpus sections,
//  returns a SkeletonResult.
//
//  See CHANGELOG v1→v2 and v2→v3 comments throughout for what changed and why.
//

import Foundation

enum SkeletonGeneratorService {

    typealias Section = StructureWorkbenchViewModel.ReconstructedSection

    // MARK: - Run Any Path

    static func run(
        path: SkeletonPath,
        matrix: AtomTransitionMatrix,
        config: SkeletonLabConfig,
        sections: [Section]
    ) async -> SkeletonResult {
        let start = CFAbsoluteTimeGetCurrent()

        var result: SkeletonResult
        switch path {
        case .pureProbabilistic:
            result = runPureProbabilistic(matrix: matrix, config: config, sections: sections)
        case .planFirst:
            result = await runPlanFirst(matrix: matrix, config: config, sections: sections)
        case .entropyHandoff:
            result = runEntropyHandoff(matrix: matrix, config: config, sections: sections)
        case .collapseReExpand:
            result = await runCollapseReExpand(matrix: matrix, config: config, sections: sections)
        case .templateBlending:
            result = runTemplateBlending(matrix: matrix, config: config, sections: sections)
        case .contentTypedSubChain:
            result = await runContentTypedSubChain(matrix: matrix, config: config, sections: sections)
        case .corpusSeededFirst:
            result = runCorpusSeededFirst(matrix: matrix, config: config, sections: sections)
        }

        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        result = SkeletonResult(
            id: result.id,
            path: result.path,
            createdAt: result.createdAt,
            atoms: result.atoms,
            sentenceBreaks: result.sentenceBreaks,
            status: result.status,
            durationMs: elapsed,
            llmCallCount: result.llmCallCount,
            promptTokensTotal: result.promptTokensTotal,
            completionTokensTotal: result.completionTokensTotal,
            estimatedCost: result.estimatedCost,
            intermediateOutputs: result.intermediateOutputs,
            llmCalls: result.llmCalls
        )
        return result
    }

    // MARK: - Build Atom Transition Matrix from Corpus Sections

    // CHANGELOG v1→v2:
    // v1: Computed 5 fields (transitions, openers, break probabilities, atom counts, total transitions).
    //     Constructor returned AtomTransitionMatrix with 5 args.
    // v2: Added trigram counting inside transition loop (when i >= 1, forms "prev|current" key → next atom count).
    //     Added position break ramp computation: collects corpus sentence lengths, computes discrete hazard rate
    //     per position (P(ends at N | lasted >= N)), normalizes so median sentence length = 1.0 multiplier, caps at 3.0.
    //     Now returns 7-field constructor (adding trigramTransitions, positionBreakRamp).
    // Fixes: Trigrams propagate to P6, P2, P1, P5. Position ramp propagates to applySentenceBreaks() which P6, P2, P1 use.
    static func buildAtomTransitionMatrix(from sections: [Section]) -> AtomTransitionMatrix {
        var transitions: [String: [String: Double]] = [:]
        var openerDist: [String: Double] = [:]
        var breakProbs: [String: [String: Double]] = [:]
        var atomCounts: [String: Int] = [:]
        var totalTransitions = 0
        var trigramCounts: [String: [String: Double]] = [:]
        var sentenceLengths: [Int] = []

        // Track break vs no-break for each adjacent pair
        var breakNumerator: [String: [String: Int]] = [:]   // pairs at sentence boundary
        var breakDenominator: [String: [String: Int]] = [:]  // all adjacent pairs

        for section in sections {
            let allAtoms = section.sentences.flatMap(\.slotSequence)
            guard !allAtoms.isEmpty else { continue }

            // Opener distribution
            openerDist[allAtoms[0], default: 0] += 1

            // Atom counts
            for atom in allAtoms {
                atomCounts[atom, default: 0] += 1
            }

            // Collect sentence lengths for position break ramp
            for sentence in section.sentences {
                if !sentence.slotSequence.isEmpty {
                    sentenceLengths.append(sentence.slotSequence.count)
                }
            }

            // Build flat atom sequence with sentence boundary markers
            var flatAtoms: [String] = []
            var boundaryIndices: Set<Int> = []

            for (sentIdx, sentence) in section.sentences.enumerated() {
                if sentIdx > 0 && !flatAtoms.isEmpty {
                    boundaryIndices.insert(flatAtoms.count)
                }
                flatAtoms.append(contentsOf: sentence.slotSequence)
            }

            // Transitions + break tracking + trigrams
            for i in 0..<(flatAtoms.count - 1) {
                let from = flatAtoms[i]
                let to = flatAtoms[i + 1]

                transitions[from, default: [:]][to, default: 0] += 1
                totalTransitions += 1

                breakDenominator[from, default: [:]][to, default: 0] += 1
                if boundaryIndices.contains(i + 1) {
                    breakNumerator[from, default: [:]][to, default: 0] += 1
                }

                // Trigram: (flatAtoms[i-1], flatAtoms[i]) → flatAtoms[i+1]
                if i >= 1 {
                    let triKey = "\(flatAtoms[i - 1])|\(flatAtoms[i])"
                    trigramCounts[triKey, default: [:]][flatAtoms[i + 1], default: 0] += 1
                }
            }
        }

        // Within-sentence-only bigram/trigram counts (for accurate n-gram display)
        var withinSentBigrams: [String: Int] = [:]
        var withinSentTrigrams: [String: Int] = [:]
        for section in sections {
            for sentence in section.sentences {
                let slots = sentence.slotSequence
                for i in 0..<max(slots.count - 1, 0) {
                    let key = "\(slots[i]) \u{2192} \(slots[i + 1])"
                    withinSentBigrams[key, default: 0] += 1
                }
                for i in 0..<max(slots.count - 2, 0) {
                    let key = "\(slots[i]) \u{2192} \(slots[i + 1]) \u{2192} \(slots[i + 2])"
                    withinSentTrigrams[key, default: 0] += 1
                }
            }
        }

        // Compute break probabilities
        for (from, targets) in breakDenominator {
            for (to, denom) in targets {
                let num = breakNumerator[from]?[to] ?? 0
                breakProbs[from, default: [:]][to] = denom > 0 ? Double(num) / Double(denom) : 0
            }
        }

        // CHANGELOG v2→v3:
        // v2: Hazard-rate ramp normalized so median position = 1.0 multiplier, capped at 3.0.
        //     Shape was corpus-driven but uncalibrated — 1-atom sentences possible, no hard upper bound.
        // v3: Three-zone model using corpus min/median/p95 sentence lengths:
        //     Zone 1 (pos < min): multiplier = 0.0 (never break before minimum corpus sentence length)
        //     Zone 2 (min ≤ pos < median): linear ramp 0.0 → 1.0 (increasing break likelihood)
        //     Zone 3 (median ≤ pos < p95): linear ramp 1.0 → 3.0 (strong push toward breaking)
        //     Position ≥ p95: multiplier = 3.0 (applySentenceBreaks forces break at p95 anyway)
        // Fixes: Sentences bounded by corpus-calibrated min/p95. Three-zone is deterministic and interpretable.
        var positionBreakRamp: [Int: Double] = [:]
        let corpusMin: Int
        let corpusMedian: Int
        let corpusP95: Int

        if !sentenceLengths.isEmpty {
            let sorted = sentenceLengths.sorted()
            corpusMin = sorted.first ?? 2
            corpusMedian = sorted[sorted.count / 2]
            corpusP95 = sorted[min(Int(Double(sorted.count) * 0.95), sorted.count - 1)]
            let maxLen = sorted.last ?? corpusP95

            for pos in 1...maxLen {
                if pos < corpusMin {
                    // Zone 1: never break before corpus minimum
                    positionBreakRamp[pos] = 0.0
                } else if pos < corpusMedian {
                    // Zone 2: linear ramp 0.0 → 1.0
                    let range = Double(corpusMedian - corpusMin)
                    positionBreakRamp[pos] = range > 0 ? Double(pos - corpusMin) / range : 0.5
                } else if pos < corpusP95 {
                    // Zone 3: linear ramp 1.0 → 3.0
                    let range = Double(corpusP95 - corpusMedian)
                    positionBreakRamp[pos] = range > 0 ? 1.0 + 2.0 * Double(pos - corpusMedian) / range : 2.0
                } else {
                    // Beyond p95: max multiplier (forced break handled by applySentenceBreaks)
                    positionBreakRamp[pos] = 3.0
                }
            }
        } else {
            corpusMin = 2
            corpusMedian = 4
            corpusP95 = 8
        }

        return AtomTransitionMatrix(
            transitions: transitions,
            openerDistribution: openerDist,
            breakProbabilities: breakProbs,
            atomCounts: atomCounts,
            totalTransitionCount: totalTransitions,
            trigramTransitions: trigramCounts,
            positionBreakRamp: positionBreakRamp,
            corpusMinSentenceLen: corpusMin,
            corpusMedianSentenceLen: corpusMedian,
            corpusP95SentenceLen: corpusP95,
            withinSentenceBigrams: withinSentBigrams,
            withinSentenceTrigrams: withinSentTrigrams
        )
    }

    // MARK: - Apply Sentence Breaks

    // CHANGELOG v1→v2:
    // v1: Signature was (atoms, breakProbs, targetCount, rng). Used flat breakProbs[prev][next] ?? 0.3 for every position.
    //     No awareness of how far into a sentence we were. Produced 22-atom sentences because break probability was constant.
    // v2: Added positionRamp parameter. Tracks sentencePosition counter (resets to 1 on each break). Multiplies base break
    //     probability by positionRamp[sentencePosition] — early positions get suppressed (<1.0), late positions get boosted
    //     (up to 3.0), capped at 0.95. Adjustment pass also uses position-aware probabilities for candidate scoring.
    // Affects: P6, P2, P1 call sites all pass matrix.positionBreakRamp. P5 inherits through P6.
    //     P3 uses parsed sentence boundaries (not this function). P4 uses real corpus breaks (not this function).
    //
    // CHANGELOG v2→v3:
    // v2: No minimum sentence length floor, no forced upper bound. Short (1-atom) and long (22-atom) sentences still possible
    //     because the ramp only nudges probability — it never guarantees a break or prevents one.
    // v3: Added minSentenceLen and forcedBreakAt parameters.
    //     (a) Minimum floor: when sentencePosition < minSentenceLen, skip break entirely (don't roll). Prevents 1-atom sentences.
    //     (b) Forced break: when sentencePosition >= forcedBreakAt, insert break unconditionally (no roll). Prevents runaway sentences.
    //     (c) Adjustment pass respects min floor: candidate breaks below minSentenceLen are excluded.
    // Fixes: Sentences are hard-bounded by [minSentenceLen, forcedBreakAt]. Combined with three-zone ramp, produces
    //     corpus-typical sentence lengths without degenerate edge cases.
    static func applySentenceBreaks(
        atoms: [String],
        breakProbs: [String: [String: Double]],
        positionRamp: [Int: Double],
        targetCount: Int,
        minSentenceLen: Int = 1,
        forcedBreakAt: Int? = nil,
        rng: inout SeededRNG
    ) -> Set<Int> {
        guard atoms.count > 1, targetCount > 1 else { return [] }

        var breaks: Set<Int> = []
        var sentencePosition = 1 // atoms into current sentence

        for i in 1..<atoms.count {
            // v3: Forced break at p95 — no roll, unconditional
            if let forced = forcedBreakAt, sentencePosition >= forced {
                breaks.insert(i)
                sentencePosition = 1
                continue
            }
            // v3: Minimum floor — skip break entirely below corpus minimum
            if sentencePosition < minSentenceLen {
                sentencePosition += 1
                continue
            }

            let baseProb = breakProbs[atoms[i - 1]]?[atoms[i]] ?? 0.3
            let multiplier = positionRamp[sentencePosition] ?? 1.0
            let adjusted = min(baseProb * multiplier, 0.95)
            let roll = Double(rng.next() % 10000) / 10000.0
            if roll < adjusted {
                breaks.insert(i)
                sentencePosition = 1
            } else {
                sentencePosition += 1
            }
        }

        // Adjust toward target sentence count
        let currentCount = breaks.count + 1
        if currentCount < targetCount {
            // Add breaks at highest adjusted-probability points (respecting min floor)
            var candidates: [(index: Int, prob: Double)] = []
            var pos = 1
            for i in 1..<atoms.count {
                if breaks.contains(i) {
                    pos = 1
                } else {
                    // v3: Only consider candidates at or above minimum sentence length
                    if pos >= minSentenceLen {
                        let baseProb = breakProbs[atoms[i - 1]]?[atoms[i]] ?? 0.3
                        let multiplier = positionRamp[pos] ?? 1.0
                        candidates.append((index: i, prob: min(baseProb * multiplier, 0.95)))
                    }
                    pos += 1
                }
            }
            candidates.sort { $0.prob > $1.prob }
            let needed = targetCount - currentCount
            for c in candidates.prefix(needed) {
                breaks.insert(c.index)
            }
        } else if currentCount > targetCount {
            // Remove breaks at lowest adjusted-probability points
            var existing = breaks.sorted().map { idx -> (index: Int, prob: Double) in
                let baseProb = breakProbs[atoms[idx - 1]]?[atoms[idx]] ?? 0.3
                return (index: idx, prob: baseProb)
            }
            existing.sort { $0.prob < $1.prob }
            let excess = currentCount - targetCount
            for c in existing.prefix(excess) {
                breaks.remove(c.index)
            }
        }

        return breaks
    }

    // MARK: - Target Atom Count from Corpus

    static func corpusAtomStats(sections: [Section]) -> (mean: Int, min: Int, max: Int) {
        let counts = sections.map { $0.sentences.flatMap(\.slotSequence).count }
        guard !counts.isEmpty else { return (20, 10, 30) }
        let mean = counts.reduce(0, +) / counts.count
        return (mean: mean, min: counts.min() ?? 10, max: counts.max() ?? 30)
    }

    // MARK: - Path 6: Pure Probabilistic Walk

    // CHANGELOG v2→v3:
    // v2: No recency penalty — same atom types could dominate in clusters with skewed distributions.
    //     applySentenceBreaks had no min floor or forced break.
    // v3: (a) Added optional recencyPenalty parameter (default nil = no change for P6 callers).
    //     When non-nil, counts each candidate's appearances K in last-5 window and multiplies probability
    //     by recencyPenalty^K. P5 passes 0.8 to break atom dominance in narrow cluster sub-matrices.
    //     (b) applySentenceBreaks now receives minSentenceLen and forcedBreakAt from corpus stats.
    // Fixes: P6 unchanged (nil penalty). P5 gets diversity within cluster walks.
    static func runPureProbabilistic(
        matrix: AtomTransitionMatrix,
        config: SkeletonLabConfig,
        sections: [Section],
        recencyPenalty: Double? = nil
    ) -> SkeletonResult {
        var rng = SeededRNG(seed: config.seed)
        let stats = corpusAtomStats(sections: sections)
        let targetAtoms = stats.mean

        var atoms: [String] = []
        var walkTrace: [String] = []

        // Sample opener
        guard let opener = matrix.sampleOpener(using: &rng) else {
            return failedResult(path: .pureProbabilistic, reason: "No opener distribution")
        }
        atoms.append(opener)
        walkTrace.append("Step 0: opener=\(opener) (sampled from opener distribution)")

        // CHANGELOG v1→v2:
        // v1: Used matrix.sampleNext(from: current) — bigram only. Trace logged step/from/to/prob/alts.
        // Problem: Bounce patterns like factual_relay → geographic_location → factual_relay due to 1st-order Markov
        //     having no memory of where it came from. The walk oscillated between high-frequency atom pairs.
        // v2: Uses sampleNextWithContext(from: current, context: prev) — trigram with bigram fallback.
        //     Trace now logs [TRIGRAM]/[BIGRAM] per step + context atom, showing WHAT decided and WHY.
        // Fixes: Kills A→B→A bounce patterns. Trigram conditions on last 2 atoms so the walk "remembers."

        // Walk with trigram conditioning
        for step in 1..<targetAtoms {
            guard let current = atoms.last else { break }
            let prev = atoms.count >= 2 ? atoms[atoms.count - 2] : nil

            // v3: When recencyPenalty is set, apply decay to penalize recently-used atom types
            if let penalty = recencyPenalty {
                let recentWindow = atoms.suffix(5)
                let candidates = matrix.validNextAtoms(from: current, minProbability: 0.02)
                guard !candidates.isEmpty else {
                    walkTrace.append("Step \(step): DEAD END from \(current)")
                    break
                }

                // Apply recency decay: probability *= penalty^K where K = count in last-5 window
                let penalized = candidates.map { c -> (atom: String, score: Double) in
                    let k = recentWindow.filter { $0 == c.atom }.count
                    let decay = pow(penalty, Double(k))
                    return (atom: c.atom, score: c.probability * decay)
                }

                // Weighted sample from penalized distribution
                let total = penalized.reduce(0.0) { $0 + $1.score }
                var roll = Double(rng.next() % 10000) / 10000.0 * total
                var picked = penalized[0].atom
                for p in penalized {
                    roll -= p.score
                    if roll <= 0 { picked = p.atom; break }
                }

                let prob = matrix.probability(from: current, to: picked)
                let recencyK = recentWindow.filter { $0 == picked }.count
                let recencyNote = recencyK > 0 ? " [recency K=\(recencyK) decay=\(String(format: "%.2f", pow(penalty, Double(recencyK))))]" : ""
                atoms.append(picked)
                walkTrace.append("Step \(step): \(current)->\(picked) [RECENCY] p=\(String(format: "%.1f%%", prob * 100))\(recencyNote)")
                continue
            }

            guard let sample = matrix.sampleNextWithContext(
                from: current,
                context: prev,
                using: &rng
            ) else {
                walkTrace.append("Step \(step): DEAD END from \(current)")
                break
            }
            let next = sample.atom
            let source = sample.usedTrigram ? "TRIGRAM" : "BIGRAM"
            let prob = matrix.probability(from: current, to: next)
            let alts = matrix.validNextAtoms(from: current, minProbability: 0.05)
                .prefix(5)
                .map { "\($0.atom)(\(String(format: "%.0f%%", $0.probability * 100)))" }
                .joined(separator: ", ")
            atoms.append(next)
            walkTrace.append("Step \(step): \(current)->\(next) [\(source)] p=\(String(format: "%.1f%%", prob * 100)) ctx=\(prev ?? "none") alts=[\(alts)]")
        }

        // Sentence breaks (position-aware, v3: with min floor + forced break)
        let breaks = applySentenceBreaks(
            atoms: atoms,
            breakProbs: matrix.breakProbabilities,
            positionRamp: matrix.positionBreakRamp,
            targetCount: config.targetSentenceCount,
            minSentenceLen: matrix.corpusMinSentenceLen,
            forcedBreakAt: matrix.corpusP95SentenceLen,
            rng: &rng
        )

        return SkeletonResult(
            id: UUID(),
            path: .pureProbabilistic,
            createdAt: Date(),
            atoms: atoms,
            sentenceBreaks: breaks,
            status: .completed,
            durationMs: 0,
            llmCallCount: 0,
            promptTokensTotal: 0,
            completionTokensTotal: 0,
            estimatedCost: 0,
            intermediateOutputs: ["walkTrace": walkTrace.joined(separator: "\n")],
            llmCalls: []
        )
    }

    // MARK: - Path 7: Corpus-Seeded First Sentence

    // Randomly draws a real first sentence from the corpus, locks it as sentence 1,
    // then Markov-walks sentences 2+ using the same trigram-conditioned walk as P6.
    // No LLM calls. The skeleton's opening sentence is guaranteed to match a real
    // creator's structure.

    static func runCorpusSeededFirst(
        matrix: AtomTransitionMatrix,
        config: SkeletonLabConfig,
        sections: [Section]
    ) -> SkeletonResult {
        var rng = SeededRNG(seed: config.seed)
        let stats = corpusAtomStats(sections: sections)
        let targetAtoms = stats.mean

        // --- Step 1: Collect all first sentences from corpus ---
        let firstSentences: [(sectionId: String, atoms: [String])] = sections.compactMap { section in
            guard let first = section.sentences.first,
                  !first.slotSequence.isEmpty else { return nil }
            return (sectionId: section.id, atoms: first.slotSequence)
        }
        guard !firstSentences.isEmpty else {
            return failedResult(path: .corpusSeededFirst, reason: "No first sentences in corpus")
        }

        // --- Step 2: Random draw ---
        let drawIndex = Int(rng.next() % UInt64(firstSentences.count))
        let drawn = firstSentences[drawIndex]

        var atoms = drawn.atoms
        var walkTrace: [String] = []
        walkTrace.append("WHAT: Drew first sentence from section \(drawn.sectionId)")
        walkTrace.append("WHAT: Locked S1 atoms = [\(drawn.atoms.joined(separator: " -> "))]")
        walkTrace.append("WHY: Random draw index \(drawIndex) of \(firstSentences.count) candidates (seed=\(config.seed))")

        // --- Step 3: Pre-insert sentence break after S1 ---
        let s1BreakIndex = atoms.count  // break BEFORE next atom

        // --- Step 4: Markov-walk from last atom of S1 ---
        let remainingAtoms = max(targetAtoms - atoms.count, 0)
        walkTrace.append("WHAT: Walking \(remainingAtoms) more atoms from \"\(atoms.last ?? "?")\" (target total=\(targetAtoms))")

        for step in 1...remainingAtoms {
            guard let current = atoms.last else { break }
            let prev = atoms.count >= 2 ? atoms[atoms.count - 2] : nil

            guard let sample = matrix.sampleNextWithContext(
                from: current,
                context: prev,
                using: &rng
            ) else {
                walkTrace.append("Step \(step): DEAD END from \(current)")
                break
            }
            let next = sample.atom
            let source = sample.usedTrigram ? "TRIGRAM" : "BIGRAM"
            let prob = matrix.probability(from: current, to: next)
            let alts = matrix.validNextAtoms(from: current, minProbability: 0.05)
                .prefix(5)
                .map { "\($0.atom)(\(String(format: "%.0f%%", $0.probability * 100)))" }
                .joined(separator: ", ")
            atoms.append(next)
            walkTrace.append("Step \(step): \(current)->\(next) [\(source)] p=\(String(format: "%.1f%%", prob * 100)) alts=[\(alts)]")
        }

        // --- Step 5: Apply sentence breaks, then protect S1 ---
        var breaks = applySentenceBreaks(
            atoms: atoms,
            breakProbs: matrix.breakProbabilities,
            positionRamp: matrix.positionBreakRamp,
            targetCount: config.targetSentenceCount,
            minSentenceLen: matrix.corpusMinSentenceLen,
            forcedBreakAt: matrix.corpusP95SentenceLen,
            rng: &rng
        )
        // Remove any breaks inside S1, ensure S1 boundary is present
        breaks = breaks.filter { $0 >= s1BreakIndex }
        breaks.insert(s1BreakIndex)

        walkTrace.append("WHAT: Final atom count = \(atoms.count), sentence breaks at \(breaks.sorted())")
        walkTrace.append("WHAT: S1 locked at indices 0..<\(s1BreakIndex) (\(drawn.atoms.count) atoms)")

        return SkeletonResult(
            id: UUID(),
            path: .corpusSeededFirst,
            createdAt: Date(),
            atoms: atoms,
            sentenceBreaks: breaks,
            status: .completed,
            durationMs: 0,
            llmCallCount: 0,
            promptTokensTotal: 0,
            completionTokensTotal: 0,
            estimatedCost: 0,
            intermediateOutputs: [
                "walkTrace": walkTrace.joined(separator: "\n"),
                "drawnSectionId": drawn.sectionId,
                "drawnFirstSentence": drawn.atoms.joined(separator: "|")
            ],
            llmCalls: []
        )
    }

    // MARK: - Path 4: Template Blending

    static func runTemplateBlending(
        matrix: AtomTransitionMatrix,
        config: SkeletonLabConfig,
        sections: [Section]
    ) -> SkeletonResult {
        guard sections.count >= 3 else {
            return failedResult(path: .templateBlending, reason: "Need >= 3 corpus sections for template blending")
        }

        var rng = SeededRNG(seed: config.seed)
        var intermediates: [String: String] = [:]

        // Partition each section into zones: opening (first 2 sentences), development (middle), landing (last 2)
        struct SectionZone {
            let sectionId: String
            let atoms: [String]
            let sentenceBreaks: Set<Int>
        }

        var openings: [SectionZone] = []
        var developments: [SectionZone] = []
        var landings: [SectionZone] = []

        for section in sections {
            let sentCount = section.sentences.count
            guard sentCount >= 3 else { continue }

            let openingEnd = min(2, sentCount)
            let landingStart = max(sentCount - 2, openingEnd)

            func zoneAtoms(_ sentRange: Range<Int>) -> (atoms: [String], breaks: Set<Int>) {
                var atoms: [String] = []
                var breaks: Set<Int> = []
                for i in sentRange {
                    guard i < section.sentences.count else { break }
                    if !atoms.isEmpty { breaks.insert(atoms.count) }
                    atoms.append(contentsOf: section.sentences[i].slotSequence)
                }
                return (atoms, breaks)
            }

            let (oAtoms, oBreaks) = zoneAtoms(0..<openingEnd)
            let (dAtoms, dBreaks) = zoneAtoms(openingEnd..<landingStart)
            let (lAtoms, lBreaks) = zoneAtoms(landingStart..<sentCount)

            if !oAtoms.isEmpty { openings.append(SectionZone(sectionId: section.id, atoms: oAtoms, sentenceBreaks: oBreaks)) }
            if !dAtoms.isEmpty { developments.append(SectionZone(sectionId: section.id, atoms: dAtoms, sentenceBreaks: dBreaks)) }
            if !lAtoms.isEmpty { landings.append(SectionZone(sectionId: section.id, atoms: lAtoms, sentenceBreaks: lBreaks)) }
        }

        guard !openings.isEmpty, !developments.isEmpty, !landings.isEmpty else {
            return failedResult(path: .templateBlending, reason: "Insufficient zone data")
        }

        // CHANGELOG v1→v2:
        // v1: Purely random zone selection: Int(rng.next() % UInt64(openings.count)) for each position.
        // Problem: Ignored content input entirely. Random picks chose ill-fitting zones unrelated to topic.
        // v2: Content-aware selection — scores each zone by average contentRelevanceScore() across its atoms.
        //     Highest-scoring zone wins per position (opening/development/landing). Falls back to random if no
        //     content input provided. Logs all zone scores + selection method in intermediates["zoneScoring"].
        // Fixes: With content input, zones now match the topic. Without content, behavior is same as v1.
        //
        // CHANGELOG v2→v3:
        // v2: Content-only scoring. No content → random. Structural quality of zone transitions ignored.
        // Problem: High-content zones could have poor internal transitions (low probability atom sequences).
        // v3: Dual scoring: 0.4 * structural + 0.6 * content. Structural score = average transition probability
        //     across adjacent atom pairs in the zone, normalized to [0,1] by dividing by max score in that position.
        //     No content → structural-only (instead of random). Both sub-scores logged.
        // Fixes: Zones with smooth internal transitions are preferred even when content is strong.

        // Content-aware zone selection: score each zone by content relevance
        let contentKeywords = Set(config.contentInput.lowercased().split(separator: " ").map(String.init))

        func contentScore(_ zone: SectionZone) -> Double {
            guard !contentKeywords.isEmpty else { return 0 }
            let atomScores = zone.atoms.map { contentRelevanceScore(atom: $0, keywords: contentKeywords) }
            return atomScores.isEmpty ? 0 : atomScores.reduce(0, +) / Double(atomScores.count)
        }

        // v3: Structural typicality — average transition probability across adjacent pairs
        func structuralScore(_ zone: SectionZone) -> Double {
            guard zone.atoms.count > 1 else { return 0 }
            var total = 0.0
            for i in 0..<(zone.atoms.count - 1) {
                total += matrix.probability(from: zone.atoms[i], to: zone.atoms[i + 1])
            }
            return total / Double(zone.atoms.count - 1)
        }

        // v3: Score and rank all zones with dual scoring
        func bestZoneIndex<T: RandomAccessCollection>(
            zones: T,
            label: String,
            log: inout [String]
        ) -> Int where T.Element == SectionZone, T.Index == Int {
            let rawScores = zones.enumerated().map { (idx: $0.offset, structural: structuralScore($0.element), content: contentScore($0.element), id: $0.element.sectionId) }
            // Normalize structural scores to [0,1] within this position
            let maxStructural = rawScores.map(\.structural).max() ?? 1.0
            let normalizer = maxStructural > 0 ? maxStructural : 1.0

            let combined = rawScores.map { s -> (idx: Int, combined: Double, structural: Double, content: Double, id: String) in
                let normStruct = s.structural / normalizer
                let combo: Double
                if !contentKeywords.isEmpty {
                    combo = 0.4 * normStruct + 0.6 * s.content
                } else {
                    combo = normStruct // structural-only when no content
                }
                return (idx: s.idx, combined: combo, structural: normStruct, content: s.content, id: s.id)
            }.sorted { $0.combined > $1.combined }

            log.append("\(label): \(combined.prefix(3).map { "\($0.id) combined=\(String(format: "%.3f", $0.combined)) struct=\(String(format: "%.3f", $0.structural)) content=\(String(format: "%.3f", $0.content))" }.joined(separator: " | "))")
            return combined[0].idx
        }

        var zoneScoreLog: [String] = []
        let oIdx = bestZoneIndex(zones: openings, label: "Opening", log: &zoneScoreLog)
        let dIdx = bestZoneIndex(zones: developments, label: "Development", log: &zoneScoreLog)
        let lIdx = bestZoneIndex(zones: landings, label: "Landing", log: &zoneScoreLog)
        zoneScoreLog.append("Selection method: \(!contentKeywords.isEmpty ? "DUAL (0.4 structural + 0.6 content)" : "STRUCTURAL-ONLY (no content input)")")

        let opening = openings[oIdx]
        let development = developments[dIdx]
        let landing = landings[lIdx]

        intermediates["zoneScoring"] = zoneScoreLog.joined(separator: "\n")
        intermediates["sourceZones"] = """
        Opening: \(opening.sectionId) (\(opening.atoms.count) atoms)
        Development: \(development.sectionId) (\(development.atoms.count) atoms)
        Landing: \(landing.sectionId) (\(landing.atoms.count) atoms)
        """

        // Concatenate
        var atoms = opening.atoms
        var breaks = opening.sentenceBreaks
        var seamRepairs: [String] = []

        // Seam 1: opening -> development
        let seam1From = atoms.last ?? ""
        let seam1To = development.atoms.first ?? ""
        let seam1Prob = matrix.probability(from: seam1From, to: seam1To)
        breaks.insert(atoms.count) // sentence break at zone boundary
        if seam1Prob < 0.03, let bridge = findBridgeAtom(from: seam1From, to: seam1To, matrix: matrix) {
            atoms.append(bridge)
            seamRepairs.append("Seam1: inserted bridge \(bridge) between \(seam1From)->\(seam1To) (p=\(String(format: "%.1f%%", seam1Prob * 100)))")
        }

        let devOffset = atoms.count
        atoms.append(contentsOf: development.atoms)
        for b in development.sentenceBreaks { breaks.insert(b + devOffset) }

        // Seam 2: development -> landing
        let seam2From = atoms.last ?? ""
        let seam2To = landing.atoms.first ?? ""
        let seam2Prob = matrix.probability(from: seam2From, to: seam2To)
        breaks.insert(atoms.count)
        if seam2Prob < 0.03, let bridge = findBridgeAtom(from: seam2From, to: seam2To, matrix: matrix) {
            atoms.append(bridge)
            seamRepairs.append("Seam2: inserted bridge \(bridge) between \(seam2From)->\(seam2To) (p=\(String(format: "%.1f%%", seam2Prob * 100)))")
        }

        let landOffset = atoms.count
        atoms.append(contentsOf: landing.atoms)
        for b in landing.sentenceBreaks { breaks.insert(b + landOffset) }

        intermediates["seamRepairs"] = seamRepairs.isEmpty ? "No seam repairs needed" : seamRepairs.joined(separator: "\n")

        return SkeletonResult(
            id: UUID(),
            path: .templateBlending,
            createdAt: Date(),
            atoms: atoms,
            sentenceBreaks: breaks,
            status: .completed,
            durationMs: 0,
            llmCallCount: 0,
            promptTokensTotal: 0,
            completionTokensTotal: 0,
            estimatedCost: 0,
            intermediateOutputs: intermediates,
            llmCalls: []
        )
    }

    // MARK: - Path 2: Entropy Handoff

    static func runEntropyHandoff(
        matrix: AtomTransitionMatrix,
        config: SkeletonLabConfig,
        sections: [Section]
    ) -> SkeletonResult {
        var rng = SeededRNG(seed: config.seed)
        let stats = corpusAtomStats(sections: sections)
        let targetAtoms = stats.mean

        var atoms: [String] = []
        var stepLog: [String] = []

        guard let opener = matrix.sampleOpener(using: &rng) else {
            return failedResult(path: .entropyHandoff, reason: "No opener distribution")
        }
        atoms.append(opener)
        stepLog.append("Step 0: opener=\(opener)")

        // CHANGELOG v2→v3:
        // v2: Content scorer used keyword overlap heuristics (contentRelevanceScore) — a hand-built keyword-to-atom
        //     mapping that disagreed with the deterministic detectors used by corpus ingestion (ScriptFidelityService).
        //     Content scoring was flat: probability*0.5 + keywordOverlap*0.5 regardless of sequence position.
        // v3: Replaced keyword overlap with content pointer scoring:
        //     (a) Pre-analyze content into ordered atom list using ScriptFidelityService (same detectors as corpus).
        //     (b) Maintain contentPointer — advances when a matching atom is placed.
        //     (c) Scoring: exact match to pointer = +2.0, proximity (next 3 positions) = +1.0/distance, base probability.
        //     (d) Diversity penalty (0.3x for last-3 window) and max-consecutive cap (3-in-a-row) unchanged.
        // Fixes: Content scoring now uses corpus-consistent atom types and follows content order.
        let contentAtoms = preAnalyzeContentAtoms(contentInput: config.contentInput)
        var contentPointer = 0
        stepLog.append("ContentAtoms: [\(contentAtoms.joined(separator: ", "))]")

        // CHANGELOG v1→v2:
        // v1: Matrix-decides branch picked greedy highest probability (no trigram). Content-decides branch scored
        //     candidates by probability*0.5 + contentRelevance*0.5, always picking the top scorer. No diversity
        //     penalty, no consecutive cap. Step log showed atom/entropy/threshold/decider only.
        // Problem: Content scorer always picked the same top atom → 41 factual_relays in a single run. Same-atom
        //     repetition went unchecked because nothing penalized recent duplicates.
        // v2: (a) Matrix-decides uses sampleNextWithContext (trigram-aware). Logged as MATRIX[TRI] or MATRIX[BI].
        //     (b) Diversity penalty: rolling window of last 3 atoms, any matching candidate gets score *= 0.3.
        //     (c) Max-consecutive cap: if chosen atom would be 3rd in a row, swap to next-best non-duplicate.
        //     Step log now shows diversity penalty and [DEDUP] entries.
        // Fixes: Breaks factual_relay dominance. Forces atom variety even when one type scores highest.

        for step in 1..<targetAtoms {
            guard let current = atoms.last else { break }
            let prev = atoms.count >= 2 ? atoms[atoms.count - 2] : nil
            let entropy = matrix.normalizedEntropy(from: current)
            let candidates = matrix.validNextAtoms(from: current, minProbability: 0.05)
            guard !candidates.isEmpty else {
                stepLog.append("Step \(step): DEAD END from \(current)")
                break
            }

            // Rolling window of last 3 atoms for diversity penalty
            let recentWindow = Array(atoms.suffix(3))

            var chosen: String
            var decider: String
            var diversityNote = ""

            if entropy < config.entropyThreshold {
                // Matrix decides — trigram-aware sampling
                if let sample = matrix.sampleNextWithContext(from: current, context: prev, using: &rng) {
                    chosen = sample.atom
                    decider = "MATRIX[\(sample.usedTrigram ? "TRI" : "BI")] (H=\(String(format: "%.2f", entropy))<\(String(format: "%.2f", config.entropyThreshold)))"
                } else {
                    chosen = candidates[0].atom
                    decider = "MATRIX[FALLBACK] (H=\(String(format: "%.2f", entropy)))"
                }
            } else {
                // v3: Content pointer scoring with ScriptFidelityService-analyzed atoms
                let scored = candidates.map { c -> (atom: String, score: Double) in
                    var score = c.probability

                    // Content pointer scoring
                    if contentPointer < contentAtoms.count {
                        if c.atom == contentAtoms[contentPointer] {
                            // Exact match to current pointer position
                            score += 2.0
                        } else {
                            // Proximity: check next 3 content positions
                            for offset in 1...3 {
                                let lookAhead = contentPointer + offset
                                if lookAhead < contentAtoms.count && c.atom == contentAtoms[lookAhead] {
                                    score += 1.0 / Double(offset)
                                    break
                                }
                            }
                        }
                    }

                    // Diversity penalty: atoms seen in last 3 get 0.3x
                    if recentWindow.contains(c.atom) {
                        score *= 0.3
                    }
                    return (atom: c.atom, score: score)
                }.sorted { $0.score > $1.score }
                chosen = scored[0].atom
                if recentWindow.contains(chosen) {
                    diversityNote = " [diversity-penalized but still best]"
                }
                let ptrNote = contentPointer < contentAtoms.count ? " ptr=\(contentPointer)/\(contentAtoms.count) target=\(contentAtoms[contentPointer])" : " ptr=END"
                decider = "CONTENT (H=\(String(format: "%.2f", entropy))>=\(String(format: "%.2f", config.entropyThreshold)))\(ptrNote)"
            }

            // Max-consecutive cap: same atom can't appear 3+ times in a row
            let consecutiveCount = atoms.suffix(2).filter { $0 == chosen }.count
            if consecutiveCount >= 2 {
                let alt = candidates.first { $0.atom != chosen }
                if let alt = alt {
                    diversityNote += " [DEDUP: \(chosen) would be 3rd consecutive, swapped to \(alt.atom)]"
                    chosen = alt.atom
                }
            }

            atoms.append(chosen)

            // v3: Advance content pointer when exact match placed
            if contentPointer < contentAtoms.count && chosen == contentAtoms[contentPointer] {
                contentPointer = min(contentPointer + 1, contentAtoms.count - 1)
            }

            let alts = candidates.prefix(3).map { "\($0.atom)(\(String(format: "%.0f%%", $0.probability * 100)))" }.joined(separator: ", ")
            stepLog.append("Step \(step): \(current)->\(chosen) | \(decider)\(diversityNote) | alts=[\(alts)]")
        }

        // v3: Sentence breaks with min floor + forced break
        let breaks = applySentenceBreaks(
            atoms: atoms,
            breakProbs: matrix.breakProbabilities,
            positionRamp: matrix.positionBreakRamp,
            targetCount: config.targetSentenceCount,
            minSentenceLen: matrix.corpusMinSentenceLen,
            forcedBreakAt: matrix.corpusP95SentenceLen,
            rng: &rng
        )

        return SkeletonResult(
            id: UUID(),
            path: .entropyHandoff,
            createdAt: Date(),
            atoms: atoms,
            sentenceBreaks: breaks,
            status: .completed,
            durationMs: 0,
            llmCallCount: 0,
            promptTokensTotal: 0,
            completionTokensTotal: 0,
            estimatedCost: 0,
            intermediateOutputs: ["stepLog": stepLog.joined(separator: "\n")],
            llmCalls: []
        )
    }

    // MARK: - Path 1: Plan First, Then Walk

    static func runPlanFirst(
        matrix: AtomTransitionMatrix,
        config: SkeletonLabConfig,
        sections: [Section]
    ) async -> SkeletonResult {
        var rng = SeededRNG(seed: config.seed)
        var intermediates: [String: String] = [:]
        var llmCalls: [SkeletonLLMCall] = []

        let moveType = config.moveType.isEmpty ? "general" : config.moveType
        let topic = config.contentInput.isEmpty ? "a general topic" : config.contentInput

        // LLM call: produce intent plan
        let systemPrompt = """
        You are a structural planner for YouTube video scripts. Given a section type and topic, \
        produce an ordered list of 4-7 intent categories that would make a compelling section.

        Available intents:
        - Ground: Orient the viewer in place/time (geographic_location, temporal_marker, visual_detail)
        - Introduce: Bring a person or group into the story (actor_reference, narrative_action)
        - Claim: Assert something with evidence or judgment (quantitative_claim, factual_relay, evaluative_claim)
        - Pivot: Change direction or challenge (contradiction, pivot_phrase, rhetorical_question)
        - Connect: Engage the viewer or bridge segments (direct_address, empty_connector, reaction_beat)
        - Frame: Provide conceptual scaffolding (abstract_framing, comparison, sensory_detail, visual_anchor)

        Reply with ONLY a JSON array of intent names. Example: ["Ground", "Introduce", "Claim", "Pivot", "Claim", "Connect"]
        """

        let userPrompt = "Section type: \(moveType)\nTopic: \(topic)\nTarget sentences: \(config.targetSentenceCount)"

        let callStart = CFAbsoluteTimeGetCurrent()
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let bundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.7, "max_tokens": 500]
        )
        let callDuration = Int((CFAbsoluteTimeGetCurrent() - callStart) * 1000)

        let responseText = bundle?.content ?? ""
        let promptTokens = bundle?.promptTokens ?? 0
        let completionTokens = bundle?.completionTokens ?? 0

        llmCalls.append(SkeletonLLMCall(
            callIndex: 0,
            callLabel: "Intent Plan",
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            rawResponse: responseText,
            durationMs: callDuration,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        ))

        // Parse intent plan from JSON
        let intents = parseIntentPlan(responseText)
        guard !intents.isEmpty else {
            return failedResult(path: .planFirst, reason: "Failed to parse intent plan from LLM response")
        }
        intermediates["intentPlan"] = intents.map(\.rawValue).joined(separator: " -> ")

        // Walk each intent using matrix filtered to that intent's atom subset
        var atoms: [String] = []
        var breaks: Set<Int> = []
        var intentMapping: [String] = []
        var bridgeLog: [String] = []

        // CHANGELOG v1→v2:
        // v1: Hard-filtered candidates to intent's atomTypes only.
        // v2: Soft scoring — intent atoms: prob * 2.0, non-intent: prob * 0.5.
        //
        // CHANGELOG v2→v3:
        // v2: Fixed 2.0x/0.5x multipliers. Fixed atomsPerIntent loop count (no dynamic boundary).
        //     1-atom sentences possible because no minimum enforcement.
        // v3: (a) Three-tier multipliers: current intent 3.0x, next intent 1.5x, other 0.5x.
        //     Allows natural drift into the next intent before the formal boundary.
        //     (b) Dynamic intent boundary: while-loop with min 2 atoms, max cap. If last atom
        //     belongs to next intent's atomTypes after minAtoms reached, advance early.
        //     (c) After walk, remove breaks that create <2-atom sentences.
        // Fixes: Smoother intent transitions, no 1-atom sentences, dynamic pacing.

        let minAtomsPerIntent = 2
        let corpusMean = corpusAtomStats(sections: sections).mean
        let maxAtomsPerIntent = max(3, (corpusMean / intents.count) * 3 / 2)

        for (intentIdx, intent) in intents.enumerated() {
            let allowedAtoms = intent.atomTypes
            let nextIntentAtoms: Set<String> = intentIdx + 1 < intents.count ? intents[intentIdx + 1].atomTypes : []

            // Bridge from previous intent
            if let lastAtom = atoms.last {
                let bestFirst = allowedAtoms.max(by: {
                    matrix.probability(from: lastAtom, to: $0) < matrix.probability(from: lastAtom, to: $1)
                })
                if let first = bestFirst, matrix.probability(from: lastAtom, to: first) > 0 {
                    // Direct transition works
                } else if let bridge = findBridgeAtom(from: lastAtom, to: allowedAtoms.first ?? "", matrix: matrix) {
                    atoms.append(bridge)
                    bridgeLog.append("Bridge at intent \(intentIdx): \(lastAtom)->\(bridge)->\(allowedAtoms.first ?? "?")")
                }
                breaks.insert(atoms.count) // sentence break between intents
            }

            // Walk within this intent
            let intentStartIdx = atoms.count
            // Pick best opener for this intent
            let intentOpener: String
            if let lastAtom = atoms.last {
                intentOpener = allowedAtoms.max(by: {
                    matrix.probability(from: lastAtom, to: $0) < matrix.probability(from: lastAtom, to: $1)
                }) ?? allowedAtoms.first ?? ""
            } else {
                intentOpener = allowedAtoms.first { (matrix.openerDistribution[$0] ?? 0) > 0 }
                    ?? allowedAtoms.first ?? ""
            }

            if !intentOpener.isEmpty { atoms.append(intentOpener) }

            // v3: Dynamic intent boundary with while-loop
            var atomsSinceIntentStart = 1
            while atomsSinceIntentStart < maxAtomsPerIntent {
                guard let current = atoms.last else { break }
                let prev = atoms.count >= 2 ? atoms[atoms.count - 2] : nil

                // v3: Three-tier scoring: current intent 3.0x, next intent 1.5x, other 0.5x
                let allCandidates = matrix.validNextAtoms(from: current, minProbability: 0.02)
                guard !allCandidates.isEmpty else { break }

                let scored = allCandidates.map { c -> (atom: String, score: Double) in
                    let multiplier: Double
                    if allowedAtoms.contains(c.atom) {
                        multiplier = 3.0
                    } else if nextIntentAtoms.contains(c.atom) {
                        multiplier = 1.5
                    } else {
                        multiplier = 0.5
                    }
                    return (atom: c.atom, score: c.probability * multiplier)
                }

                // Trigram-aware: try trigram first for the actual pick
                var picked: String
                if let sample = matrix.sampleNextWithContext(from: current, context: prev, using: &rng) {
                    let triPick = sample.atom
                    let triMultiplier: Double = allowedAtoms.contains(triPick) ? 3.0 : (nextIntentAtoms.contains(triPick) ? 1.5 : 0.5)
                    if triMultiplier >= 1.5 || matrix.probability(from: current, to: triPick) > 0.1 {
                        picked = triPick
                    } else {
                        let total = scored.reduce(0.0) { $0 + $1.score }
                        var roll = Double(rng.next() % 10000) / 10000.0 * total
                        picked = scored[0].atom
                        for s in scored {
                            roll -= s.score
                            if roll <= 0 { picked = s.atom; break }
                        }
                    }
                } else {
                    let total = scored.reduce(0.0) { $0 + $1.score }
                    var roll = Double(rng.next() % 10000) / 10000.0 * total
                    picked = scored[0].atom
                    for s in scored {
                        roll -= s.score
                        if roll <= 0 { picked = s.atom; break }
                    }
                }
                atoms.append(picked)
                atomsSinceIntentStart += 1

                // v3: Dynamic boundary — if past min atoms and picked belongs to next intent, advance
                if atomsSinceIntentStart >= minAtomsPerIntent && !nextIntentAtoms.isEmpty && nextIntentAtoms.contains(picked) {
                    bridgeLog.append("Dynamic advance at intent \(intentIdx) (\(intent.rawValue)) after \(atomsSinceIntentStart) atoms: \(picked) belongs to next intent")
                    break
                }
            }

            let intentAtoms = Array(atoms[intentStartIdx...])
            intentMapping.append("\(intent.rawValue) [\(intentAtoms.count) atoms]: \(intentAtoms.joined(separator: " -> "))")
        }

        intermediates["intentAtomMapping"] = intentMapping.joined(separator: "\n")
        intermediates["bridgeAtoms"] = bridgeLog.isEmpty ? "No bridges needed" : bridgeLog.joined(separator: "\n")

        // v3: Add sub-sentence breaks within intents (position-aware, with min floor + forced break)
        let intraBreaks = applySentenceBreaks(
            atoms: atoms,
            breakProbs: matrix.breakProbabilities,
            positionRamp: matrix.positionBreakRamp,
            targetCount: config.targetSentenceCount,
            minSentenceLen: matrix.corpusMinSentenceLen,
            forcedBreakAt: matrix.corpusP95SentenceLen,
            rng: &rng
        )
        breaks.formUnion(intraBreaks)

        // v3: Remove breaks that create <2-atom sentences
        var minSentenceRemovals: [String] = []
        let sortedBreaks = breaks.sorted()
        var breaksCopy = breaks
        var prevBreakPos = 0
        for b in sortedBreaks {
            let sentLen = b - prevBreakPos
            if sentLen < 2 {
                breaksCopy.remove(b)
                minSentenceRemovals.append("Removed break at \(b): would create \(sentLen)-atom sentence")
            } else {
                prevBreakPos = b
            }
        }
        breaks = breaksCopy
        if !minSentenceRemovals.isEmpty {
            intermediates["minSentenceRemovals"] = minSentenceRemovals.joined(separator: "\n")
        }

        let cost = estimateCost(promptTokens: promptTokens, completionTokens: completionTokens)

        return SkeletonResult(
            id: UUID(),
            path: .planFirst,
            createdAt: Date(),
            atoms: atoms,
            sentenceBreaks: breaks,
            status: .completed,
            durationMs: 0,
            llmCallCount: 1,
            promptTokensTotal: promptTokens,
            completionTokensTotal: completionTokens,
            estimatedCost: cost,
            intermediateOutputs: intermediates,
            llmCalls: llmCalls
        )
    }

    // MARK: - Path 5: Content-Typed Sub-Chains

    // CHANGELOG v1→v2:
    // v1 & v2: Zero code changes to P5 itself. P5 calls buildAtomTransitionMatrix(from: clusterSections)
    //     then runPureProbabilistic(matrix: subMatrix, ...).
    // Inherits: buildAtomTransitionMatrix now returns trigrams + position ramp (v2). runPureProbabilistic now
    //     uses trigram walk + position-aware breaks (v2). So P5 gets all shared fixes automatically —
    //     no bounce patterns, reasonable sentence lengths — scoped to the cluster-specific sub-matrix.
    //
    // CHANGELOG v2→v3:
    // v2: No recency penalty in sub-matrix walk — same atom type could dominate in narrow clusters.
    //     No minimum cluster size — tiny clusters (1-2 sections) produced unreliable sub-matrices.
    // v3: (a) Recency penalty: passes recencyPenalty: 0.8 to runPureProbabilistic. Walk penalizes
    //     atoms appearing K times in last-5 window by 0.8^K, breaking atom dominance in narrow clusters.
    //     (b) Minimum cluster size: after k-means, clusters < 10 sections merge into nearest larger
    //     cluster by centroid Euclidean distance. Logs merge operations. If ALL clusters < 10 (tiny corpus),
    //     skips merge with warning.
    // Fixes: More diverse walks within clusters. Reliable sub-matrices from adequately-sized clusters.

    static func runContentTypedSubChain(
        matrix: AtomTransitionMatrix,
        config: SkeletonLabConfig,
        sections: [Section]
    ) async -> SkeletonResult {
        var rng = SeededRNG(seed: config.seed)
        var intermediates: [String: String] = [:]
        var llmCalls: [SkeletonLLMCall] = []

        guard sections.count >= config.clusterCount else {
            return failedResult(path: .contentTypedSubChain, reason: "Need >= \(config.clusterCount) sections for clustering")
        }

        // Compute atom frequency vectors for each section
        let allAtomTypes = SlotType.allCases.map(\.rawValue)
        let sectionVectors: [[Double]] = sections.map { section in
            let atoms = section.sentences.flatMap(\.slotSequence)
            let total = max(Double(atoms.count), 1)
            return allAtomTypes.map { type in
                Double(atoms.filter { $0 == type }.count) / total
            }
        }

        // K-means clustering
        var clusters = kMeansCluster(vectors: sectionVectors, k: config.clusterCount, rng: &rng)

        // v3: Minimum cluster size — merge tiny clusters (<10 sections) into nearest larger cluster
        let minClusterSize = 10
        var clusterMergeLog: [String] = []
        let hasLargeCluster = clusters.contains { $0.count >= minClusterSize }
        if hasLargeCluster {
            // Compute centroids for merge distance calculation
            let dim = allAtomTypes.count
            func centroid(of indices: [Int]) -> [Double] {
                guard !indices.isEmpty else { return [Double](repeating: 0, count: dim) }
                var avg = [Double](repeating: 0, count: dim)
                for idx in indices {
                    for d in 0..<dim { avg[d] += sectionVectors[idx][d] }
                }
                let n = Double(indices.count)
                return avg.map { $0 / n }
            }
            func euclidean(_ a: [Double], _ b: [Double]) -> Double {
                zip(a, b).reduce(0.0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
            }

            var centroids = clusters.map { centroid(of: $0) }
            var merged = true
            while merged {
                merged = false
                for i in 0..<clusters.count {
                    guard !clusters[i].isEmpty && clusters[i].count < minClusterSize else { continue }
                    // Find nearest cluster with >= minClusterSize
                    var bestTarget = -1
                    var bestDist = Double.infinity
                    for j in 0..<clusters.count {
                        guard i != j && clusters[j].count >= minClusterSize else { continue }
                        let dist = euclidean(centroids[i], centroids[j])
                        if dist < bestDist { bestDist = dist; bestTarget = j }
                    }
                    if bestTarget >= 0 {
                        clusterMergeLog.append("Merged cluster \(i) (\(clusters[i].count) sections) into cluster \(bestTarget) (\(clusters[bestTarget].count) sections), dist=\(String(format: "%.3f", bestDist))")
                        clusters[bestTarget].append(contentsOf: clusters[i])
                        clusters[i] = []
                        centroids[bestTarget] = centroid(of: clusters[bestTarget])
                        merged = true
                    }
                }
            }
            // Remove empty clusters
            clusters = clusters.filter { !$0.isEmpty }
        } else {
            clusterMergeLog.append("WARNING: All clusters < \(minClusterSize) sections (corpus too small for merge)")
        }
        intermediates["clusterMerges"] = clusterMergeLog.isEmpty ? "No merges needed" : clusterMergeLog.joined(separator: "\n")

        // Build cluster profiles
        var clusterProfiles: [String] = []
        for (cIdx, sectionIndices) in clusters.enumerated() {
            guard !sectionIndices.isEmpty else { continue }
            // Average frequency vector for cluster
            var avgVector = [Double](repeating: 0, count: allAtomTypes.count)
            for idx in sectionIndices {
                for (j, v) in sectionVectors[idx].enumerated() {
                    avgVector[j] += v
                }
            }
            let n = Double(sectionIndices.count)
            avgVector = avgVector.map { $0 / n }

            // Top 3 atoms
            let ranked = avgVector.enumerated().sorted { $0.element > $1.element }
            let top3 = ranked.prefix(3).map { "\(allAtomTypes[$0.offset])(\(String(format: "%.0f%%", $0.element * 100)))" }
            clusterProfiles.append("Cluster \(cIdx) [\(sectionIndices.count) sections]: \(top3.joined(separator: ", "))")
        }
        intermediates["clusterProfiles"] = clusterProfiles.joined(separator: "\n")
        intermediates["clusterSizes"] = clusters.enumerated().map { "C\($0.offset): \($0.element.count)" }.joined(separator: ", ")

        // LLM call: which cluster best matches the content
        let systemPrompt = "You are picking which corpus cluster best matches the user's content. Reply with ONLY the cluster number (0-indexed)."
        let userPrompt = """
        Content: \(config.contentInput.isEmpty ? "general topic" : config.contentInput)
        Move type: \(config.moveType)

        Cluster profiles:
        \(clusterProfiles.joined(separator: "\n"))

        Which cluster number (0-\(clusters.count - 1)) best matches this content?
        """

        let callStart = CFAbsoluteTimeGetCurrent()
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let bundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 50]
        )
        let callDuration = Int((CFAbsoluteTimeGetCurrent() - callStart) * 1000)

        let responseText = bundle?.content ?? ""
        let promptTokens = bundle?.promptTokens ?? 0
        let completionTokens = bundle?.completionTokens ?? 0

        llmCalls.append(SkeletonLLMCall(
            callIndex: 0,
            callLabel: "Cluster Selection",
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            rawResponse: responseText,
            durationMs: callDuration,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        ))

        // Parse cluster choice
        let chosenCluster = Int(responseText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let clampedCluster = min(max(chosenCluster, 0), clusters.count - 1)
        intermediates["selectedCluster"] = "Cluster \(clampedCluster)"

        // Build sub-matrix for selected cluster
        let clusterSections = clusters[clampedCluster].map { sections[$0] }
        let subMatrix = buildAtomTransitionMatrix(from: clusterSections)
        intermediates["selectedClusterMatrix"] = "Cluster \(clampedCluster): \(subMatrix.totalTransitionCount) transitions from \(clusterSections.count) sections"

        // Walk using sub-matrix (Path 6 logic)
        let subConfig = SkeletonLabConfig(
            moveType: config.moveType,
            contentInput: config.contentInput,
            targetSentenceCount: config.targetSentenceCount,
            seed: config.seed
        )
        // v3: Pass recencyPenalty 0.8 to break atom dominance in narrow cluster sub-matrices
        let walkResult = runPureProbabilistic(matrix: subMatrix, config: subConfig, sections: clusterSections, recencyPenalty: 0.8)

        // Merge intermediates
        var allIntermediates = intermediates
        for (k, v) in walkResult.intermediateOutputs {
            allIntermediates["walk_\(k)"] = v
        }

        let cost = estimateCost(promptTokens: promptTokens, completionTokens: completionTokens)

        return SkeletonResult(
            id: UUID(),
            path: .contentTypedSubChain,
            createdAt: Date(),
            atoms: walkResult.atoms,
            sentenceBreaks: walkResult.sentenceBreaks,
            status: walkResult.atoms.isEmpty ? .failed : .completed,
            durationMs: 0,
            llmCallCount: 1,
            promptTokensTotal: promptTokens,
            completionTokensTotal: completionTokens,
            estimatedCost: cost,
            intermediateOutputs: allIntermediates,
            llmCalls: llmCalls
        )
    }

    // MARK: - Path 3: Collapse & Re-Expand

    // CHANGELOG v2→v3:
    // v2: (a) tagSentenceToAtoms() used keyword heuristics that disagreed with corpus ingestion
    //     (ScriptFidelityService). (b) LLM prompt included sentence count, biasing output length.
    //     (c) Single correction pass: bridge insertion + diversity check against approximate corpus median.
    // v3: (a) Replace tagSentenceToAtoms with ScriptFidelityService.parseSentence + extractSlotSignature
    //     per clause — same deterministic detectors as corpus ingestion → consistent atom assignments.
    //     (b) Remove sentence count from LLM prompt — let LLM write freely, we control structure via atoms.
    //     (c) Three correction checks:
    //         Check 1 — Atom diversity vs corpus p10 distinct count threshold.
    //         Check 2 — Atom distribution: trim types exceeding corpus p90 proportion.
    //         Check 3 — Consecutive repetition: replace 3+ identical atom runs.
    // Fixes: Corpus-consistent tagging, unbiased LLM output, comprehensive correction.

    static func runCollapseReExpand(
        matrix: AtomTransitionMatrix,
        config: SkeletonLabConfig,
        sections: [Section]
    ) async -> SkeletonResult {
        var intermediates: [String: String] = [:]
        var llmCalls: [SkeletonLLMCall] = []

        let topic = config.contentInput.isEmpty ? "a compelling topic" : config.contentInput

        // v3: LLM prompt without sentence count — let it write freely
        let systemPrompt = """
        Write a natural, compelling paragraph about the given topic. \
        Write as if for a YouTube documentary script. No templates, no bullet points — just write naturally and conversationally.
        """
        let userPrompt = "Topic: \(topic)\nSection type: \(config.moveType)"

        let callStart = CFAbsoluteTimeGetCurrent()
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let bundle = await adapter.generate_response_bundle(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": config.collapseTemperature, "max_tokens": 2000]
        )
        let callDuration = Int((CFAbsoluteTimeGetCurrent() - callStart) * 1000)

        let responseText = bundle?.content ?? ""
        let promptTokens = bundle?.promptTokens ?? 0
        let completionTokens = bundle?.completionTokens ?? 0

        llmCalls.append(SkeletonLLMCall(
            callIndex: 0,
            callLabel: "Free Write",
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            rawResponse: responseText,
            durationMs: callDuration,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        ))

        intermediates["freeText"] = responseText

        // Parse into sentences
        let sentences = SentenceParser.parse(responseText)
        intermediates["parsedSentences"] = sentences.enumerated()
            .map { "S\($0.offset + 1): \($0.element)" }
            .joined(separator: "\n")

        // v3: Clause-aware tagging using ScriptFidelityService (replaces tagSentenceToAtoms)
        var allAtoms: [String] = []
        var breaks: Set<Int> = []
        var tagging: [String] = []

        for (sIdx, sentence) in sentences.enumerated() {
            if sIdx > 0 && !allAtoms.isEmpty {
                breaks.insert(allAtoms.count)
            }
            let clauses = splitIntoClauses(sentence)
            var sentenceAtoms: [String] = []
            var clauseDetails: [String] = []
            for clause in clauses {
                // v3: Use ScriptFidelityService deterministic hints instead of keyword heuristics
                let parsed = ScriptFidelityService.parseSentence(text: clause, index: sIdx)
                let sig = ScriptFidelityService.extractSlotSignature(from: parsed)
                let atoms = sig.isEmpty ? ["factual_relay"] : sig.split(separator: "|").map(String.init)
                sentenceAtoms.append(contentsOf: atoms)
                clauseDetails.append("  clause: \"\(clause.prefix(50))\" → [\(atoms.joined(separator: ", "))] hints=\(parsed.deterministicHints)")
            }
            tagging.append("S\(sIdx + 1) (\(clauses.count) clauses):")
            tagging.append(contentsOf: clauseDetails)
            allAtoms.append(contentsOf: sentenceAtoms)
        }
        intermediates["initialAtomTagging"] = tagging.joined(separator: "\n")

        // Score each adjacent pair against the transition matrix and correct (bridge insertion)
        var corrections: [String] = []
        var correctedAtoms = allAtoms

        var i = 0
        while i < correctedAtoms.count - 1 {
            let prob = matrix.probability(from: correctedAtoms[i], to: correctedAtoms[i + 1])
            if prob < 0.03 {
                if let bridge = findBridgeAtom(from: correctedAtoms[i], to: correctedAtoms[i + 1], matrix: matrix) {
                    corrections.append("Insert bridge \(bridge) between pos \(i)(\(correctedAtoms[i])) and pos \(i + 1)(\(correctedAtoms[i + 1])) — original p=\(String(format: "%.1f%%", prob * 100))")
                    correctedAtoms.insert(bridge, at: i + 1)
                    breaks = Set(breaks.map { $0 > i ? $0 + 1 : $0 })
                    i += 2
                    continue
                } else {
                    let alts = matrix.validNextAtoms(from: correctedAtoms[i], minProbability: 0.05)
                    if let best = alts.first, best.probability > prob * 3 {
                        corrections.append("Swap pos \(i + 1): \(correctedAtoms[i + 1]) -> \(best.atom) — p improved \(String(format: "%.1f%%", prob * 100)) -> \(String(format: "%.1f%%", best.probability * 100))")
                        correctedAtoms[i + 1] = best.atom
                    }
                }
            }
            i += 1
        }
        intermediates["corrections"] = corrections.isEmpty ? "No corrections needed" : corrections.joined(separator: "\n")

        // v3: Three correction checks (replacing single diversity correction)

        // Compute corpus per-section stats for calibration
        let corpusSectionDistincts = sections.map { section -> Int in
            Set(section.sentences.flatMap(\.slotSequence)).count
        }.sorted()
        let corpusSectionAtomProportions: [String: [Double]] = {
            var result: [String: [Double]] = [:]
            for section in sections {
                let atoms = section.sentences.flatMap(\.slotSequence)
                let total = max(Double(atoms.count), 1)
                let counts = Dictionary(atoms.map { ($0, 1) }, uniquingKeysWith: +)
                for (atom, count) in counts {
                    result[atom, default: []].append(Double(count) / total)
                }
            }
            return result
        }()

        // Check 1 — Atom diversity vs corpus p10
        var check1Log: [String] = []
        let p10Idx = max(0, Int(Double(corpusSectionDistincts.count) * 0.1))
        let corpusP10Distinct = corpusSectionDistincts.isEmpty ? 5 : corpusSectionDistincts[min(p10Idx, corpusSectionDistincts.count - 1)]
        let sequenceDistinct = Set(correctedAtoms).count
        check1Log.append("WHAT: sequence has \(sequenceDistinct) distinct types, corpus p10=\(corpusP10Distinct)")

        if sequenceDistinct < corpusP10Distinct {
            let corpusAtomTypes = Set(matrix.atomCounts.keys)
            let missing = corpusAtomTypes.subtracting(Set(correctedAtoms))
                .sorted { (matrix.atomCounts[$0] ?? 0) > (matrix.atomCounts[$1] ?? 0) }
            var insertions: [String] = []
            for missingAtom in missing.prefix(corpusP10Distinct - sequenceDistinct) {
                var bestPos = -1
                var bestScore = 0.0
                for j in 1..<correctedAtoms.count {
                    let pIn = matrix.probability(from: correctedAtoms[j - 1], to: missingAtom)
                    let pOut = matrix.probability(from: missingAtom, to: correctedAtoms[j])
                    if pIn > 0.03 && pOut > 0.03 {
                        let score = pIn * pOut
                        if score > bestScore { bestScore = score; bestPos = j }
                    }
                }
                if bestPos >= 0 {
                    correctedAtoms.insert(missingAtom, at: bestPos)
                    breaks = Set(breaks.map { $0 >= bestPos ? $0 + 1 : $0 })
                    insertions.append("Inserted \(missingAtom) at pos \(bestPos)")
                }
            }
            check1Log.append("WHAT: inserted \(insertions.count) missing atom types")
            check1Log.append("WHY: sequence distinct (\(sequenceDistinct)) < corpus p10 (\(corpusP10Distinct))")
            if !insertions.isEmpty { check1Log.append(contentsOf: insertions) }
        } else {
            check1Log.append("WHY: diversity sufficient (\(sequenceDistinct) >= \(corpusP10Distinct))")
        }
        intermediates["check1_diversity"] = check1Log.joined(separator: "\n")

        // Check 2 — Atom distribution vs corpus p90
        var check2Log: [String] = []
        let totalAtoms = max(correctedAtoms.count, 1)
        let atomFreqs = Dictionary(correctedAtoms.map { ($0, 1) }, uniquingKeysWith: +)
        var trimmed = 0
        for (atom, count) in atomFreqs {
            let proportion = Double(count) / Double(totalAtoms)
            let corpusProportions = (corpusSectionAtomProportions[atom] ?? [0]).sorted()
            let p90Idx = min(Int(Double(corpusProportions.count) * 0.9), corpusProportions.count - 1)
            let corpusP90 = corpusProportions.isEmpty ? 1.0 : corpusProportions[p90Idx]

            if proportion > corpusP90 && count > 2 {
                // Trim excess: find weakest-transition occurrences and replace
                let excess = count - max(Int(corpusP90 * Double(totalAtoms)), 1)
                if excess > 0 {
                    // Find positions of this atom, score by transition quality
                    var positions: [(pos: Int, transitionScore: Double)] = []
                    for (pos, a) in correctedAtoms.enumerated() where a == atom {
                        let pIn = pos > 0 ? matrix.probability(from: correctedAtoms[pos - 1], to: a) : 1.0
                        let pOut = pos < correctedAtoms.count - 1 ? matrix.probability(from: a, to: correctedAtoms[pos + 1]) : 1.0
                        positions.append((pos: pos, transitionScore: pIn * pOut))
                    }
                    positions.sort { $0.transitionScore < $1.transitionScore }
                    for p in positions.prefix(excess) {
                        let prevAtom = p.pos > 0 ? correctedAtoms[p.pos - 1] : ""
                        if let alt = matrix.validNextAtoms(from: prevAtom, minProbability: 0.05).first(where: { $0.atom != atom }) {
                            check2Log.append("Replaced \(atom) at pos \(p.pos) with \(alt.atom) (proportion \(String(format: "%.0f%%", proportion * 100)) > corpus p90 \(String(format: "%.0f%%", corpusP90 * 100)))")
                            correctedAtoms[p.pos] = alt.atom
                            trimmed += 1
                        }
                    }
                }
            }
        }
        check2Log.insert("WHAT: checked \(atomFreqs.count) atom types, trimmed \(trimmed) excess occurrences", at: 0)
        check2Log.insert("WHY: any atom type exceeding its corpus p90 proportion gets trimmed to prevent dominance", at: 1)
        intermediates["check2_distribution"] = check2Log.joined(separator: "\n")

        // Check 3 — Consecutive repetition (3+ identical atoms in a row)
        var check3Log: [String] = []
        var repairCount = 0
        var j = 1
        while j < correctedAtoms.count - 1 {
            if correctedAtoms[j] == correctedAtoms[j - 1] && j + 1 < correctedAtoms.count && correctedAtoms[j] == correctedAtoms[j + 1] {
                // 3+ consecutive — replace middle occurrence(s)
                let repeatedAtom = correctedAtoms[j]
                let prevAtom = j > 0 ? correctedAtoms[j - 1] : ""
                if let alt = matrix.validNextAtoms(from: prevAtom, minProbability: 0.03).first(where: { $0.atom != repeatedAtom }) {
                    check3Log.append("Replaced consecutive \(repeatedAtom) at pos \(j) with \(alt.atom)")
                    correctedAtoms[j] = alt.atom
                    repairCount += 1
                }
            }
            j += 1
        }
        check3Log.insert("WHAT: scanned for 3+ consecutive identical atoms, repaired \(repairCount)", at: 0)
        check3Log.insert("WHY: 3+ consecutive same atom creates monotonous patterns not seen in corpus", at: 1)
        intermediates["check3_repetition"] = check3Log.joined(separator: "\n")

        let cost = estimateCost(promptTokens: promptTokens, completionTokens: completionTokens)

        return SkeletonResult(
            id: UUID(),
            path: .collapseReExpand,
            createdAt: Date(),
            atoms: correctedAtoms,
            sentenceBreaks: breaks,
            status: .completed,
            durationMs: 0,
            llmCallCount: 1,
            promptTokensTotal: promptTokens,
            completionTokensTotal: completionTokens,
            estimatedCost: cost,
            intermediateOutputs: intermediates,
            llmCalls: llmCalls
        )
    }

    // MARK: - Shared Helpers

    // CHANGELOG v2→v3: New helper. Converts free-text content into an ordered atom list using the same
    // deterministic hint detectors as corpus ingestion (ScriptFidelityService). Used by P2 (content pointer)
    // and P3 (replacing keyword-based tagSentenceToAtoms). Ensures content analysis matches corpus tagging.
    /// Pre-analyze content input into an ordered atom list using ScriptFidelityService detectors.
    private static func preAnalyzeContentAtoms(contentInput: String) -> [String] {
        guard !contentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ["factual_relay"]
        }
        let sentences = SentenceParser.parse(contentInput)
        var atoms: [String] = []
        for (i, sentence) in sentences.enumerated() {
            let parsed = ScriptFidelityService.parseSentence(text: sentence, index: i)
            let sig = ScriptFidelityService.extractSlotSignature(from: parsed)
            if sig.isEmpty {
                atoms.append("factual_relay")
            } else {
                atoms.append(contentsOf: sig.split(separator: "|").map(String.init))
            }
        }
        return atoms.isEmpty ? ["factual_relay"] : atoms
    }

    /// Find a single bridge atom that connects `from` to `to` with reasonable probability.
    private static func findBridgeAtom(from: String, to: String, matrix: AtomTransitionMatrix) -> String? {
        let candidates = matrix.validNextAtoms(from: from, minProbability: 0.05)
        return candidates.first { candidate in
            matrix.probability(from: candidate.atom, to: to) > 0.03
        }?.atom
    }

    /// Content relevance score: simple keyword/semantic overlap heuristic.
    private static func contentRelevanceScore(atom: String, keywords: Set<String>) -> Double {
        let atomKeywords: [String: Set<String>] = [
            "geographic_location": ["location", "place", "city", "country", "area", "region", "state", "town"],
            "temporal_marker": ["year", "decade", "century", "time", "date", "ago", "since", "when"],
            "quantitative_claim": ["number", "percent", "million", "billion", "thousand", "data", "statistic"],
            "visual_detail": ["see", "look", "watch", "visible", "image", "picture", "footage"],
            "actor_reference": ["person", "people", "group", "team", "company", "organization", "who"],
            "narrative_action": ["did", "went", "made", "built", "started", "created", "found"],
            "evaluative_claim": ["good", "bad", "best", "worst", "important", "significant", "crucial"],
            "factual_relay": ["fact", "true", "actually", "evidence", "study", "research", "found"],
            "contradiction": ["but", "however", "despite", "although", "yet", "instead", "opposite"],
            "comparison": ["like", "similar", "different", "compared", "versus", "than", "more"],
            "abstract_framing": ["idea", "concept", "theory", "philosophy", "principle", "meaning"],
            "sensory_detail": ["feel", "smell", "taste", "sound", "hear", "touch", "cold", "hot"],
            "direct_address": ["you", "your", "we", "us", "our", "imagine"],
            "rhetorical_question": ["why", "how", "what", "?"],
            "pivot_phrase": ["now", "thing", "here", "problem", "twist"],
            "empty_connector": ["so", "and", "well", "basically"],
            "reaction_beat": ["wow", "crazy", "insane", "amazing", "wild"],
            "visual_anchor": ["screen", "map", "chart", "graph", "clip"]
        ]

        guard let atomWords = atomKeywords[atom] else { return 0 }
        let overlap = keywords.intersection(atomWords).count
        return min(Double(overlap) / 3.0, 1.0)
    }

    // CHANGELOG v1→v2: New in v2. Didn't exist in v1. Enables clause-aware tagging for P3.
    /// Split a sentence into clause-level fragments for finer-grained tagging.
    /// Breaks at commas+space, semicolons, em-dashes, and conjunctions (but, and, while, although, because, though, yet).
    /// Minimum clause length of 3 chars to avoid trivially short fragments.
    private static func splitIntoClauses(_ sentence: String) -> [String] {
        // Split at clause boundaries
        var result: [String] = []
        let remaining = sentence

        // Pattern: split at ", " / "; " / " — " / " – " / " - " and conjunctions
        let conjunctionPattern = #"\s*(?:,\s+|\s*;\s*|\s+—\s+|\s+–\s+|\s+-\s+|\s+(?:but|and|while|although|because|though|yet)\s+)"#

        if let regex = try? NSRegularExpression(pattern: conjunctionPattern, options: .caseInsensitive) {
            let nsRange = NSRange(remaining.startIndex..., in: remaining)
            let matches = regex.matches(in: remaining, range: nsRange)

            var lastEnd = remaining.startIndex
            for match in matches {
                guard let range = Range(match.range, in: remaining) else { continue }
                let clause = String(remaining[lastEnd..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if clause.count >= 3 { result.append(clause) }
                lastEnd = range.upperBound
            }
            let tail = String(remaining[lastEnd...]).trimmingCharacters(in: .whitespaces)
            if tail.count >= 3 { result.append(tail) }
        }

        // Fallback: if regex fails or produces no clauses, return whole sentence
        if result.isEmpty { result = [sentence] }
        return result
    }

    // CHANGELOG v2→v3: tagSentenceToAtoms and containsAny removed — replaced by
    // ScriptFidelityService.parseSentence + extractSlotSignature in P3 (corpus-consistent tagging).

    /// Parse intent categories from LLM JSON response.
    private static func parseIntentPlan(_ response: String) -> [IntentCategory] {
        // Try to find JSON array in response
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            // Try to extract from markdown code block
            let lines = cleaned.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    return arr.compactMap { IntentCategory(rawValue: $0) }
                }
            }
            return []
        }
        return array.compactMap { IntentCategory(rawValue: $0) }
    }

    /// K-means clustering on feature vectors.
    static func kMeansCluster(vectors: [[Double]], k: Int, rng: inout SeededRNG) -> [[Int]] {
        guard vectors.count >= k, let dim = vectors.first?.count, dim > 0 else {
            return [Array(0..<vectors.count)]
        }

        // Initialize centroids randomly
        var centroids: [[Double]] = []
        var used: Set<Int> = []
        for _ in 0..<k {
            var idx = Int(rng.next() % UInt64(vectors.count))
            while used.contains(idx) { idx = (idx + 1) % vectors.count }
            used.insert(idx)
            centroids.append(vectors[idx])
        }

        var assignments = [Int](repeating: 0, count: vectors.count)

        for _ in 0..<20 { // max iterations
            // Assign each vector to nearest centroid
            var changed = false
            for (i, vec) in vectors.enumerated() {
                var bestDist = Double.infinity
                var bestC = 0
                for (c, centroid) in centroids.enumerated() {
                    let dist = zip(vec, centroid).reduce(0.0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
                    if dist < bestDist { bestDist = dist; bestC = c }
                }
                if assignments[i] != bestC { changed = true; assignments[i] = bestC }
            }
            if !changed { break }

            // Recompute centroids
            for c in 0..<k {
                let members = vectors.enumerated().filter { assignments[$0.offset] == c }.map(\.element)
                guard !members.isEmpty else { continue }
                centroids[c] = (0..<dim).map { d in
                    members.reduce(0.0) { $0 + $1[d] } / Double(members.count)
                }
            }
        }

        // Group indices by cluster
        var clusters = [[Int]](repeating: [], count: k)
        for (i, c) in assignments.enumerated() {
            clusters[c].append(i)
        }
        return clusters
    }

    /// Estimate API cost (Claude Sonnet pricing approximation).
    private static func estimateCost(promptTokens: Int, completionTokens: Int) -> Double {
        // Approximate: $3/M input, $15/M output for Sonnet
        return (Double(promptTokens) * 3.0 + Double(completionTokens) * 15.0) / 1_000_000.0
    }

    /// Create a failed result with a reason.
    private static func failedResult(path: SkeletonPath, reason: String) -> SkeletonResult {
        SkeletonResult(
            id: UUID(),
            path: path,
            createdAt: Date(),
            atoms: [],
            sentenceBreaks: [],
            status: .failed,
            durationMs: 0,
            llmCallCount: 0,
            promptTokensTotal: 0,
            completionTokensTotal: 0,
            estimatedCost: 0,
            intermediateOutputs: ["error": reason],
            llmCalls: []
        )
    }
}
