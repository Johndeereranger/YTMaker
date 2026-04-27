//
//  ScriptFidelityService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/18/26.
//
//  Pure deterministic computation engine for the Script Fidelity Evaluator.
//  Zero LLM calls. All scoring is based on string parsing, counting,
//  and statistical comparison against precomputed corpus data.
//

import Foundation

enum ScriptFidelityService {

    // MARK: - Top-Level Evaluator

    /// Evaluate a generated script against the creator's corpus.
    /// Returns per-section results + overall fidelity score.
    static func evaluate(
        outputText: String,
        cache: FidelityCorpusCache,
        weightProfile: FidelityWeightProfile,
        s2Signatures: [String]? = nil,
        moveType: String? = nil
    ) -> (score: FidelityScore, sections: [SectionFidelityResult]) {

        let corpusStats = cache.corpusStats
        let baseline: BaselineProfile? = cache.baseline
        let rhythmTemplates = cache.rhythmTemplates

        let parsed = parseScript(outputText, moveType: moveType)

        var sectionResults: [SectionFidelityResult] = []
        var allDimensionScores: [FidelityDimension: [Double]] = [:]
        var totalHardFails = 0
        var totalWarnings = 0

        for section in parsed {
            // Layer 1: Hard-fail checks
            let hardFailResults = checkHardFails(
                section: section,
                corpusStats: corpusStats,
                rules: weightProfile.hardFailRules
            )
            totalHardFails += hardFailResults.filter { !$0.passed && $0.rule.severity == .fail }.count
            totalWarnings += hardFailResults.filter { !$0.passed && $0.rule.severity == .warn }.count

            // Layer 2: Dimension scoring
            var dimScores: [FidelityDimension: DimensionScore] = [:]

            dimScores[.sentenceMechanics] = scoreSentenceMechanics(
                section: section, corpusStats: corpusStats, baseline: baseline
            )
            dimScores[.vocabularyRegister] = scoreVocabularyRegister(
                section: section, corpusStats: corpusStats, baseline: baseline
            )
            dimScores[.slotSignatureFidelity] = scoreSlotSignatureFidelity(
                section: section, corpusStats: corpusStats, baseline: baseline
            )
            dimScores[.rhythmCadence] = scoreRhythmCadence(
                section: section, rhythmTemplates: rhythmTemplates,
                corpusStats: corpusStats, baseline: baseline
            )
            dimScores[.contentCoverage] = scoreContentCoverage(
                section: section, corpusStats: corpusStats, baseline: baseline
            )
            dimScores[.stanceTempo] = scoreStanceTempo(
                section: section, corpusStats: corpusStats, baseline: baseline
            )
            dimScores[.donorSentenceSimilarity] = scoreDonorSimilarity(
                section: section, corpusStats: corpusStats, baseline: baseline
            )

            dimScores[.structuralShape] = scoreStructuralShape(
                section: section,
                sectionProfiles: cache.sectionProfiles,
                corpusStats: corpusStats,
                baseline: baseline
            )
            dimScores[.slotSignatureS2] = scoreSlotSignatureS2(
                section: section, corpusStats: corpusStats, baseline: baseline,
                s2Signatures: s2Signatures
            )

            // Composite (weighted average)
            var composite = 0.0
            for dim in FidelityDimension.allCases {
                let weight = weightProfile.weight(for: dim)
                let score = dimScores[dim]?.score ?? 50.0
                composite += weight * score
                allDimensionScores[dim, default: []].append(score)
            }

            sectionResults.append(SectionFidelityResult(
                sectionIndex: section.index,
                sectionText: section.rawText,
                sentenceCount: section.sentenceCount,
                wordCount: section.wordCount,
                dimensionScores: dimScores,
                hardFailResults: hardFailResults,
                compositeScore: composite
            ))
        }

        // Aggregate dimension scores across sections
        var aggregateDimScores: [FidelityDimension: DimensionScore] = [:]
        for dim in FidelityDimension.allCases {
            let scores = allDimensionScores[dim] ?? [50.0]
            let avgScore = scores.reduce(0.0, +) / Double(scores.count)
            let baselineRange = baseline.flatMap { b in
                b.dimensionRanges[dim.rawValue]
            }
            aggregateDimScores[dim] = DimensionScore(
                dimension: dim, score: avgScore, subMetrics: [], baselineRange: baselineRange
            )
        }

        // Overall composite
        var overallComposite = 0.0
        for dim in FidelityDimension.allCases {
            overallComposite += weightProfile.weight(for: dim) * (aggregateDimScores[dim]?.score ?? 50.0)
        }

        let fidelityScore = FidelityScore(
            compositeScore: overallComposite,
            dimensionScores: aggregateDimScores,
            hardFailCount: totalHardFails,
            warningCount: totalWarnings,
            weightProfileName: weightProfile.name
        )

        return (fidelityScore, sectionResults)
    }

    // MARK: - Single Section Evaluation (Move Probe)

    /// Evaluate a single section of text against the cached corpus baseline.
    /// Used by the Move Probe to test individual moves without a full script.
    static func evaluateSingleSection(
        sectionText: String,
        moveType: String?,
        cache: FidelityCorpusCache,
        weightProfile: FidelityWeightProfile,
        s2Signatures: [String]? = nil
    ) -> SectionFidelityResult {

        let parsed = parseSection(text: sectionText, index: 0, moveType: moveType)
        let corpusStats = cache.corpusStats
        let baseline: BaselineProfile? = cache.baseline
        let rhythmTemplates = cache.rhythmTemplates
        let sectionProfiles = cache.sectionProfiles

        // Layer 1: Hard-fail checks
        let hardFailResults = checkHardFails(
            section: parsed,
            corpusStats: corpusStats,
            rules: weightProfile.hardFailRules
        )

        // Layer 2: Dimension scoring
        var dimScores: [FidelityDimension: DimensionScore] = [:]

        dimScores[.sentenceMechanics] = scoreSentenceMechanics(
            section: parsed, corpusStats: corpusStats, baseline: baseline
        )
        dimScores[.vocabularyRegister] = scoreVocabularyRegister(
            section: parsed, corpusStats: corpusStats, baseline: baseline
        )
        dimScores[.slotSignatureFidelity] = scoreSlotSignatureFidelity(
            section: parsed, corpusStats: corpusStats, baseline: baseline
        )
        dimScores[.rhythmCadence] = scoreRhythmCadence(
            section: parsed, rhythmTemplates: rhythmTemplates,
            corpusStats: corpusStats, baseline: baseline
        )
        dimScores[.contentCoverage] = scoreContentCoverage(
            section: parsed, corpusStats: corpusStats, baseline: baseline
        )
        dimScores[.stanceTempo] = scoreStanceTempo(
            section: parsed, corpusStats: corpusStats, baseline: baseline
        )
        dimScores[.donorSentenceSimilarity] = scoreDonorSimilarity(
            section: parsed, corpusStats: corpusStats, baseline: baseline
        )
        dimScores[.structuralShape] = scoreStructuralShape(
            section: parsed, sectionProfiles: sectionProfiles,
            corpusStats: corpusStats, baseline: baseline
        )
        dimScores[.slotSignatureS2] = scoreSlotSignatureS2(
            section: parsed, corpusStats: corpusStats, baseline: baseline,
            s2Signatures: s2Signatures
        )

        // Composite (weighted average)
        var composite = 0.0
        for dim in FidelityDimension.allCases {
            let weight = weightProfile.weight(for: dim)
            let score = dimScores[dim]?.score ?? 50.0
            composite += weight * score
        }

        return SectionFidelityResult(
            sectionIndex: 0,
            sectionText: sectionText,
            sentenceCount: parsed.sentenceCount,
            wordCount: parsed.wordCount,
            dimensionScores: dimScores,
            hardFailResults: hardFailResults,
            compositeScore: composite
        )
    }

    // MARK: - Baseline Computation

    /// Compute baseline ranges from the creator's own corpus.
    /// Runs each corpus section through the same scorers to establish
    /// the "normal range" that makes evaluation scores meaningful.
    static func computeBaseline(
        creatorId: String,
        donorSentences: [CreatorSentence],
        rhythmTemplates: [RhythmTemplate],
        corpusStats: CorpusStats,
        sectionProfiles: [SectionProfile]
    ) -> BaselineProfile {

        // Group sentences by (videoId, sectionIndex) to reconstruct real individual sections.
        // This gives ~77 sections instead of 1 giant pseudo-section per moveType.
        let grouped = Dictionary(grouping: donorSentences) { "\($0.videoId)_\($0.sectionIndex)" }

        var allScores: [FidelityDimension: [Double]] = [:]
        var perMoveScores: [String: [FidelityDimension: [Double]]] = [:]
        var sectionCount = 0

        for (_, sentences) in grouped {
            let sorted = sentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            guard !sorted.isEmpty else { continue }

            let moveType = sorted[0].moveType
            let sectionText = sorted.map(\.rawText).joined(separator: " ")
            let parsed = parseSection(text: sectionText, index: sectionCount, moveType: moveType)
            sectionCount += 1

            for dim in FidelityDimension.allCases {
                let score: Double
                switch dim {
                case .sentenceMechanics:
                    score = scoreSentenceMechanics(section: parsed, corpusStats: corpusStats, baseline: nil).score
                case .vocabularyRegister:
                    score = scoreVocabularyRegister(section: parsed, corpusStats: corpusStats, baseline: nil).score
                case .structuralShape:
                    score = scoreStructuralShape(section: parsed, sectionProfiles: sectionProfiles, corpusStats: corpusStats, baseline: nil).score
                case .slotSignatureFidelity:
                    score = scoreSlotSignatureFidelity(section: parsed, corpusStats: corpusStats, baseline: nil).score
                case .rhythmCadence:
                    score = scoreRhythmCadence(section: parsed, rhythmTemplates: rhythmTemplates, corpusStats: corpusStats, baseline: nil).score
                case .contentCoverage:
                    score = scoreContentCoverage(section: parsed, corpusStats: corpusStats, baseline: nil).score
                case .stanceTempo:
                    score = scoreStanceTempo(section: parsed, corpusStats: corpusStats, baseline: nil).score
                case .donorSentenceSimilarity:
                    score = scoreDonorSimilarity(section: parsed, corpusStats: corpusStats, baseline: nil).score
                case .slotSignatureS2:
                    let sectionS2Sigs = sorted.map(\.slotSignature)
                    score = scoreSlotSignatureS2(section: parsed, corpusStats: corpusStats, baseline: nil, s2Signatures: sectionS2Sigs, excludeSectionSigs: sectionS2Sigs).score
                }
                allScores[dim, default: []].append(score)
                perMoveScores[moveType, default: [:]][dim, default: []].append(score)
            }
        }

        // Compute percentiles from ~77 real section scores
        let dimensionRanges = Dictionary(uniqueKeysWithValues:
            allScores.map { (dim, scores) in
                (dim.rawValue, computeRange(from: scores))
            }
        )

        let sectionBaselines = Dictionary(uniqueKeysWithValues:
            perMoveScores.map { (moveType, dimScores) in
                let ranges = Dictionary(uniqueKeysWithValues:
                    dimScores.map { (dim, scores) in
                        (dim.rawValue, computeRange(from: scores))
                    }
                )
                return (moveType, ranges)
            }
        )

        return BaselineProfile(
            creatorId: creatorId,
            computedAt: Date(),
            dimensionRanges: dimensionRanges,
            sectionBaselines: sectionBaselines,
            sampleCount: sectionCount
        )
    }

    // MARK: - Hard-Fail Checker (Layer 1)

    static func checkHardFails(
        section: ParsedSection,
        corpusStats: CorpusStats,
        rules: [HardFailRule]
    ) -> [HardFailResult] {

        rules.filter(\.isEnabled).map { rule in
            let (actual, corpus) = measureMetric(rule.metric, section: section, corpusStats: corpusStats)
            let effectiveThreshold: Double
            switch rule.thresholdMode {
            case .absolute:
                effectiveThreshold = rule.threshold
            case .corpusMultiplier:
                effectiveThreshold = corpus * rule.threshold
            }

            let passed: Bool
            switch rule.comparison {
            case .greaterThan:
                passed = actual <= effectiveThreshold
            case .lessThan:
                passed = actual >= effectiveThreshold
            }

            return HardFailResult(
                rule: rule,
                actualValue: actual,
                corpusValue: corpus,
                effectiveThreshold: effectiveThreshold,
                passed: passed
            )
        }
    }

    // MARK: - Dimension Scorers

    // MARK: D1: Sentence Mechanics

    static func scoreSentenceMechanics(
        section: ParsedSection,
        corpusStats: CorpusStats,
        baseline: BaselineProfile?
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []

        // Sentence count — IQR-based tolerance from actual corpus distribution
        let corpusSentCount = corpusStats.sentencesPerMove[section.moveType ?? ""] ?? 5.0
        let sentCountTolerance = max(corpusStats.sentenceCountIQR, 3.0)
        let sentCountScore = proximityScore(actual: Double(section.sentenceCount), corpus: corpusSentCount, tolerance: sentCountTolerance)
        subMetrics.append(SubMetricScore(name: "Sentence Count", rawValue: Double(section.sentenceCount), corpusMean: corpusSentCount, score: sentCountScore, tolerance: sentCountTolerance))

        // Avg sentence length — corpus SD tolerance
        let avgLen = section.avgSentenceLength
        let d1AvgLenTol = max(corpusStats.corpusAvgSentenceLengthSD, 1.0)
        let avgLenScore = proximityScore(actual: avgLen, corpus: corpusStats.avgSentenceLength, tolerance: d1AvgLenTol)
        subMetrics.append(SubMetricScore(name: "Avg Sentence Length", rawValue: avgLen, corpusMean: corpusStats.avgSentenceLength, score: avgLenScore, tolerance: d1AvgLenTol))

        // Sentence length variance — IQR-based tolerance from actual corpus distribution
        let lengths = section.sentences.map { Double($0.wordCount) }
        let variance = Self.variance(of: lengths)
        let varTolerance = max(corpusStats.lengthVarianceIQR, 10.0)
        let varScore = proximityScore(actual: variance, corpus: corpusStats.sentenceLengthVariance, tolerance: varTolerance)
        subMetrics.append(SubMetricScore(name: "Length Variance", rawValue: variance, corpusMean: corpusStats.sentenceLengthVariance, score: varScore, tolerance: varTolerance))

        // Question density — corpus SD tolerance
        let qDensity = section.sentences.isEmpty ? 0 : Double(section.sentences.filter(\.isQuestion).count) / Double(section.sentences.count)
        let d1QTol = max(corpusStats.corpusQuestionDensitySD, 0.05)
        let qScore = proximityScore(actual: qDensity, corpus: corpusStats.questionRate, tolerance: d1QTol)
        subMetrics.append(SubMetricScore(name: "Question Density", rawValue: qDensity, corpusMean: corpusStats.questionRate, score: qScore, tolerance: d1QTol))

        // Fragment rate — corpus SD tolerance
        let fRate = section.sentences.isEmpty ? 0 : Double(section.sentences.filter(\.isFragment).count) / Double(section.sentences.count)
        let d1FTol = max(corpusStats.corpusFragmentRateSD, 0.05)
        let fScore = proximityScore(actual: fRate, corpus: corpusStats.fragmentRate, tolerance: d1FTol)
        subMetrics.append(SubMetricScore(name: "Fragment Rate", rawValue: fRate, corpusMean: corpusStats.fragmentRate, score: fScore, tolerance: d1FTol))

        let avgScore = subMetrics.map(\.score).reduce(0, +) / Double(subMetrics.count)
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.sentenceMechanics.rawValue] }

        return DimensionScore(dimension: .sentenceMechanics, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: D2: Vocabulary & Register

    static func scoreVocabularyRegister(
        section: ParsedSection,
        corpusStats: CorpusStats,
        baseline: BaselineProfile?
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []
        let totalSentences = Double(max(section.sentences.count, 1))

        // RANGE-scored: "within creator's observed distribution" not "close to median"

        // First-person rate — binary per-sentence (has any FP word or not)
        let fpRate = Double(section.sentences.filter { $0.firstPersonCount > 0 }.count) / totalSentences
        let fpScore: Double
        if let fpRange = corpusStats.metricRange("firstPersonRate") {
            fpScore = rangeScore(actual: fpRate, range: fpRange)
        } else {
            fpScore = proximityScore(actual: fpRate, corpus: corpusStats.firstPersonRate, tolerance: max(corpusStats.corpusFirstPersonRateSD, 0.05))
        }
        subMetrics.append(SubMetricScore(name: "First-Person Rate", rawValue: fpRate, corpusMean: corpusStats.firstPersonRate, score: fpScore, tolerance: corpusStats.metricRange("firstPersonRate")?.iqr))

        // Contraction rate — binary per-sentence
        let cRate = Double(section.sentences.filter { $0.contractionCount > 0 }.count) / totalSentences
        let cScore: Double
        if let cRange = corpusStats.metricRange("contractionRate") {
            cScore = rangeScore(actual: cRate, range: cRange)
        } else {
            cScore = proximityScore(actual: cRate, corpus: corpusStats.contractionRate, tolerance: max(corpusStats.corpusContractionRateSD, 0.05))
        }
        subMetrics.append(SubMetricScore(name: "Contraction Rate", rawValue: cRate, corpusMean: corpusStats.contractionRate, score: cScore, tolerance: corpusStats.metricRange("contractionRate")?.iqr))

        // Opening word distribution — PROXIMITY-scored (overlap-based, kept as-is)
        let openerResult = scoreOpenerDistribution(section: section, corpusStats: corpusStats)
        subMetrics.append(SubMetricScore(name: "Opener Distribution", rawValue: openerResult.rawOverlapRate, corpusMean: corpusStats.corpusOpenerOverlapMedian, score: openerResult.score, tolerance: openerResult.tolerance))

        // Casual marker presence
        let casualHits = countCasualMarkers(section: section, markers: corpusStats.casualMarkerSet)
        let casualScore: Double
        if let casualRange = corpusStats.metricRange("casualMarkers") {
            casualScore = rangeScore(actual: Double(casualHits), range: casualRange)
        } else {
            casualScore = proximityScore(actual: Double(casualHits), corpus: corpusStats.corpusCasualMarkerMedian, tolerance: max(corpusStats.corpusCasualMarkerSD, 0.5))
        }
        subMetrics.append(SubMetricScore(name: "Casual Markers", rawValue: Double(casualHits), corpusMean: corpusStats.corpusCasualMarkerMedian, score: casualScore, tolerance: corpusStats.metricRange("casualMarkers")?.iqr))

        // Direct address rate
        let daRate = section.sentences.isEmpty ? 0 : Double(section.sentences.filter(\.hasDirectAddress).count) / totalSentences
        let daScore: Double
        if let daRange = corpusStats.metricRange("directAddressRate") {
            daScore = rangeScore(actual: daRate, range: daRange)
        } else {
            daScore = proximityScore(actual: daRate, corpus: corpusStats.directAddressRate, tolerance: max(corpusStats.corpusDirectAddressRateSD, 0.05))
        }
        subMetrics.append(SubMetricScore(name: "Direct Address Rate", rawValue: daRate, corpusMean: corpusStats.directAddressRate, score: daScore, tolerance: corpusStats.metricRange("directAddressRate")?.iqr))

        let avgScore = subMetrics.map(\.score).reduce(0, +) / Double(subMetrics.count)
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.vocabularyRegister.rawValue] }

        return DimensionScore(dimension: .vocabularyRegister, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: D4: Slot Signature Fidelity

    static func scoreSlotSignatureFidelity(
        section: ParsedSection,
        corpusStats: CorpusStats,
        baseline: BaselineProfile?
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []

        // Use rolled-up (dominant-slot) signatures for matching.
        // Corpus side uses LLM-assigned sigs rolled up; eval side uses heuristic sigs rolled up.
        let moveKey = section.moveType ?? ""
        let corpusRolledSigs = corpusStats.rolledSlotSignatures(forMove: moveKey)
        let corpusRolledOpenerSigs = corpusStats.rolledOpenerSlotSignatures(forMove: moveKey)

        // Extract heuristic signatures from generated sentences, then roll up
        let generatedSigs = section.sentences.map { extractSlotSignature(from: $0) }
        let generatedRolledSigs = generatedSigs.map { SignatureRollupService.rollupDominantSlot($0) }

        // Match rate in dominant-slot space — corpus-calibrated
        let matchCount = generatedRolledSigs.filter { corpusRolledSigs.contains($0) }.count
        let matchRate = generatedRolledSigs.isEmpty ? 0 : Double(matchCount) / Double(generatedRolledSigs.count)
        let d4MatchTol = max(corpusStats.corpusSignatureMatchSD, 0.1)
        let matchScore = proximityScore(actual: matchRate, corpus: corpusStats.corpusSignatureMatchMedian, tolerance: d4MatchTol)
        subMetrics.append(SubMetricScore(name: "Signature Match Rate", rawValue: matchRate, corpusMean: corpusStats.corpusSignatureMatchMedian, score: matchScore, tolerance: d4MatchTol))

        // Opening signature match — MEMBERSHIP-scored: does this opener sig exist in corpus?
        if let firstRolled = generatedRolledSigs.first {
            let openerMatch = corpusRolledOpenerSigs.contains(firstRolled) ? 1.0 : 0.0
            let openerScore = openerMatch * 100.0
            subMetrics.append(SubMetricScore(name: "Opener Sig Match", rawValue: openerMatch, corpusMean: 1.0, score: openerScore))
        }

        // Bigram match in rolled-up space
        let corpusRolledBigrams = corpusStats.rolledSlotBigrams(forMove: moveKey)
        var bigramHits = 0
        for i in 0..<max(0, generatedRolledSigs.count - 1) {
            let bigram = "\(generatedRolledSigs[i])→\(generatedRolledSigs[i + 1])"
            if corpusRolledBigrams.contains(bigram) { bigramHits += 1 }
        }
        let bigramRate = generatedRolledSigs.count > 1 ? Double(bigramHits) / Double(generatedRolledSigs.count - 1) : 0
        let corpusBigramRate = corpusStats.corpusBigramMatchRate
        let d4BigramTol = max(corpusStats.corpusBigramRateSD, 0.1)
        let bigramScore = proximityScore(actual: bigramRate, corpus: corpusBigramRate, tolerance: d4BigramTol)
        subMetrics.append(SubMetricScore(name: "Bigram Match Rate", rawValue: bigramRate, corpusMean: corpusBigramRate, score: bigramScore, tolerance: d4BigramTol))

        let avgScore = subMetrics.map(\.score).reduce(0, +) / Double(subMetrics.count)
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.slotSignatureFidelity.rawValue] }

        return DimensionScore(dimension: .slotSignatureFidelity, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: S2: Slot Signature S2 (LLM-assigned, unrolled)

    /// Scores slot signatures using raw 19-type LLM-assigned vocabulary on BOTH sides.
    /// Corpus side: uses raw CreatorSentence.slotSignature from slotSignaturesByMove.
    /// Eval side: uses pre-computed s2Signatures (from Firebase or live LLM annotation).
    /// Falls back to heuristic extraction (same as D4 pre-rollup) if s2Signatures is nil.
    /// - Parameter excludeSectionSigs: Ordered signatures of the section being scored, used for leave-one-out
    ///   during baseline computation so a section doesn't match against itself.
    static func scoreSlotSignatureS2(
        section: ParsedSection,
        corpusStats: CorpusStats,
        baseline: BaselineProfile?,
        s2Signatures: [String]? = nil,
        excludeSectionSigs: [String]? = nil
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []

        let moveKey = section.moveType ?? ""

        // Use provided S2 signatures or fall back to heuristic extraction
        let generatedSigs: [String]
        if let s2 = s2Signatures, !s2.isEmpty {
            generatedSigs = s2
        } else {
            generatedSigs = section.sentences.map { extractSlotSignature(from: $0) }
        }

        // Sub-metric 1: Slot Distribution Cosine — compare frequency distributions
        var genSlotCounts: [String: Int] = [:]
        for sig in generatedSigs { genSlotCounts[sig, default: 0] += 1 }
        let genTotal = Double(genSlotCounts.values.reduce(0, +))
        let genDist = genTotal > 0 ? genSlotCounts.mapValues { Double($0) / genTotal } : [:]
        let corpusDist = corpusStats.rawSlotDistribution(forMove: moveKey)
        let slotCosin = cosineSimilarity(genDist, corpusDist)
        let slotDistTol = max(corpusStats.corpusSlotDistCosinSD, 0.05)
        let slotDistScore = proximityScore(actual: slotCosin, corpus: corpusStats.corpusSlotDistCosinMedian, tolerance: slotDistTol)
        subMetrics.append(SubMetricScore(name: "Slot Dist Cosine", rawValue: slotCosin, corpusMean: corpusStats.corpusSlotDistCosinMedian, score: slotDistScore, tolerance: slotDistTol))

        // Sub-metric 2: Opener Slot Frequency — how common is this opener slot in corpus
        if let firstSig = generatedSigs.first {
            let openerDist = corpusStats.rawOpenerDistribution(forMove: moveKey)
            let openerFreq = openerDist[firstSig] ?? 0.0
            let openerScore = openerFreq * 100.0
            subMetrics.append(SubMetricScore(name: "Opener Slot Freq", rawValue: openerFreq, corpusMean: 1.0, score: openerScore))
        }

        // Sub-metric 3: Bigram Distribution Cosine — compare bigram frequency distributions
        if generatedSigs.count > 1 {
            var genBigramCounts: [String: Int] = [:]
            for i in 0..<(generatedSigs.count - 1) {
                genBigramCounts["\(generatedSigs[i])→\(generatedSigs[i + 1])", default: 0] += 1
            }
            let bigramTotal = Double(genBigramCounts.values.reduce(0, +))
            let genBigramDist = bigramTotal > 0 ? genBigramCounts.mapValues { Double($0) / bigramTotal } : [:]
            let corpusBigramDist = corpusStats.rawBigramDistribution(forMove: moveKey)
            let bigramCosin = cosineSimilarity(genBigramDist, corpusBigramDist)
            let bigramDistTol = max(corpusStats.corpusBigramDistCosinSD, 0.05)
            let bigramDistScore = proximityScore(actual: bigramCosin, corpus: corpusStats.corpusBigramDistCosinMedian, tolerance: bigramDistTol)
            subMetrics.append(SubMetricScore(name: "Bigram Dist Cosine", rawValue: bigramCosin, corpusMean: corpusStats.corpusBigramDistCosinMedian, score: bigramDistScore, tolerance: bigramDistTol))
        }

        let avgScore = subMetrics.map(\.score).reduce(0, +) / Double(max(1, subMetrics.count))
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.slotSignatureS2.rawValue] }

        return DimensionScore(dimension: .slotSignatureS2, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: D5: Rhythm & Cadence

    static func scoreRhythmCadence(
        section: ParsedSection,
        rhythmTemplates: [RhythmTemplate],
        corpusStats: CorpusStats,
        baseline: BaselineProfile?
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []

        // Match sentences against rhythm templates for the moveType
        let relevantTemplates = rhythmTemplates.filter { $0.moveType == (section.moveType ?? "") }

        // Word count in-range rate
        var inRangeCount = 0
        for (i, sentence) in section.sentences.enumerated() {
            let position = sectionPosition(index: i, total: section.sentences.count)
            let template = relevantTemplates.first { $0.positionInSection == position }
            if let t = template {
                if sentence.wordCount >= t.wordCountMin && sentence.wordCount <= t.wordCountMax {
                    inRangeCount += 1
                }
            } else {
                // No template for this position — generous scoring
                inRangeCount += 1
            }
        }
        let inRangeRate = section.sentences.isEmpty ? 0 : Double(inRangeCount) / Double(section.sentences.count)
        let d5InRangeTol = max(corpusStats.corpusWordCountInRangeSD, 0.1)
        let inRangeScore = proximityScore(actual: inRangeRate, corpus: corpusStats.corpusWordCountInRangeMedian, tolerance: d5InRangeTol)
        subMetrics.append(SubMetricScore(name: "Word Count In Range", rawValue: inRangeRate, corpusMean: corpusStats.corpusWordCountInRangeMedian, score: inRangeScore, tolerance: d5InRangeTol))

        // Sentence type match (statement/question/fragment)
        var typeMatchCount = 0
        for (i, sentence) in section.sentences.enumerated() {
            let position = sectionPosition(index: i, total: section.sentences.count)
            let template = relevantTemplates.first { $0.positionInSection == position }
            if let t = template {
                let actualType: String
                if sentence.isQuestion { actualType = "question" }
                else if sentence.isFragment { actualType = "fragment" }
                else { actualType = "statement" }
                if actualType == t.sentenceType { typeMatchCount += 1 }
            } else {
                typeMatchCount += 1
            }
        }
        let typeMatchRate = section.sentences.isEmpty ? 0 : Double(typeMatchCount) / Double(section.sentences.count)
        let d5TypeTol = max(corpusStats.corpusTypeMatchSD, 0.1)
        let typeScore = proximityScore(actual: typeMatchRate, corpus: corpusStats.corpusTypeMatchMedian, tolerance: d5TypeTol)
        subMetrics.append(SubMetricScore(name: "Type Match Rate", rawValue: typeMatchRate, corpusMean: corpusStats.corpusTypeMatchMedian, score: typeScore, tolerance: d5TypeTol))

        // Long-short alternation score
        let alternationResult = scoreAlternation(section: section, corpusStats: corpusStats)
        subMetrics.append(SubMetricScore(name: "Alternation Pattern", rawValue: alternationResult.rawRate, corpusMean: corpusStats.corpusAlternationMedian, score: alternationResult.score, tolerance: alternationResult.tolerance))

        // Length Bucket Transitions — RANGE-scored: does the sequence of short/medium/long
        // transitions follow the creator's cadence patterns?
        if section.sentences.count >= 2, let cadenceRange = corpusStats.metricRange("cadenceFit") {
            let buckets = section.sentences.map { sent -> String in
                if sent.wordCount <= corpusStats.shortSentenceMax { return "short" }
                if sent.wordCount >= corpusStats.longSentenceMin { return "long" }
                return "medium"
            }
            var totalProb = 0.0
            for i in 0..<(buckets.count - 1) {
                let key = "\(buckets[i])→\(buckets[i + 1])"
                totalProb += corpusStats.cadenceTransitionMatrix[key] ?? 0.0
            }
            let avgTransitionProb = totalProb / Double(buckets.count - 1)
            let cadenceScore = rangeScore(actual: avgTransitionProb, range: cadenceRange)
            let cadenceCorpusMean = (cadenceRange.p25 + cadenceRange.p75) / 2.0
            subMetrics.append(SubMetricScore(name: "Bucket Transitions", rawValue: avgTransitionProb, corpusMean: cadenceCorpusMean, score: cadenceScore, tolerance: cadenceRange.iqr))
        }

        let avgScore = subMetrics.map(\.score).reduce(0, +) / Double(subMetrics.count)
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.rhythmCadence.rawValue] }

        return DimensionScore(dimension: .rhythmCadence, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: D6: Content Coverage

    static func scoreContentCoverage(
        section: ParsedSection,
        corpusStats: CorpusStats,
        baseline: BaselineProfile?
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []

        // Word count — RANGE-scored: within creator's observed word count range
        let expectedWords = corpusStats.wordCountPerMove[section.moveType ?? ""] ?? corpusStats.avgWordCountPerSection
        let wcScore: Double
        if let wcRange = corpusStats.metricRange("wordCount") {
            wcScore = rangeScore(actual: Double(section.wordCount), range: wcRange)
        } else {
            wcScore = proximityScore(actual: Double(section.wordCount), corpus: expectedWords, tolerance: max(corpusStats.corpusWordCountSD, 10.0))
        }
        subMetrics.append(SubMetricScore(name: "Word Count vs Expected", rawValue: Double(section.wordCount), corpusMean: expectedWords, score: wcScore, tolerance: corpusStats.metricRange("wordCount")?.iqr))

        // Information density proxy: unique words / total words — corpus SD tolerance
        let allWords = section.sentences.flatMap(\.words).map { $0.lowercased() }
        let uniqueRatio = allWords.isEmpty ? 0 : Double(Set(allWords).count) / Double(allWords.count)
        let corpusDensity = corpusStats.vocabularyDensity
        let d6DenTol = max(corpusStats.corpusVocabularyDensitySD, 0.05)
        let densityScore = proximityScore(actual: uniqueRatio, corpus: corpusDensity, tolerance: d6DenTol)
        subMetrics.append(SubMetricScore(name: "Vocabulary Density", rawValue: uniqueRatio, corpusMean: corpusDensity, score: densityScore, tolerance: d6DenTol))

        let avgScore = subMetrics.map(\.score).reduce(0, +) / Double(subMetrics.count)
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.contentCoverage.rawValue] }

        return DimensionScore(dimension: .contentCoverage, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: D7: Stance & Tempo

    static func scoreStanceTempo(
        section: ParsedSection,
        corpusStats: CorpusStats,
        baseline: BaselineProfile?
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []

        // Deterministic tempo proxy: words per sentence → fast/medium/slow classification
        let avgLen = section.avgSentenceLength
        let tempoClass: String
        if avgLen < 12 { tempoClass = "fast" }
        else if avgLen < 22 { tempoClass = "medium" }
        else { tempoClass = "slow" }

        // Score: how well does this match corpus tempo
        let d7TempoTol = max(corpusStats.corpusAvgSentenceLengthSD, 1.0)
        let tempoScore = proximityScore(actual: avgLen, corpus: corpusStats.avgSentenceLength, tolerance: d7TempoTol)
        subMetrics.append(SubMetricScore(name: "Tempo (\(tempoClass))", rawValue: avgLen, corpusMean: corpusStats.avgSentenceLength, score: tempoScore, tolerance: d7TempoTol))

        // Deterministic stance proxy: question density + first-person + direct-address
        let qRate = section.sentences.isEmpty ? 0 : Double(section.sentences.filter(\.isQuestion).count) / Double(section.sentences.count)
        let daRate = section.sentences.isEmpty ? 0 : Double(section.sentences.filter(\.hasDirectAddress).count) / Double(section.sentences.count)
        let fpRate = section.sentences.isEmpty ? 0 : Double(section.sentences.filter { $0.firstPersonCount > 0 }.count) / Double(section.sentences.count)

        // Conversational engagement score — RANGE-scored: within creator's observed engagement range
        let engagement = qRate * 0.4 + daRate * 0.3 + min(fpRate * 0.3, 0.3)
        let corpusEng = corpusStats.corpusEngagement
        let engagementScore: Double
        if let engRange = corpusStats.metricRange("engagement") {
            engagementScore = rangeScore(actual: engagement, range: engRange)
        } else {
            engagementScore = proximityScore(actual: engagement, corpus: corpusEng, tolerance: max(corpusStats.corpusEngagementSD, 0.05))
        }
        subMetrics.append(SubMetricScore(name: "Engagement Level", rawValue: engagement, corpusMean: corpusEng, score: engagementScore, tolerance: corpusStats.metricRange("engagement")?.iqr))

        let avgScore = subMetrics.map(\.score).reduce(0, +) / Double(subMetrics.count)
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.stanceTempo.rawValue] }

        return DimensionScore(dimension: .stanceTempo, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: D8: Donor Sentence Similarity

    static func scoreDonorSimilarity(
        section: ParsedSection,
        corpusStats: CorpusStats,
        baseline: BaselineProfile?
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []

        // 3-gram overlap against corpus
        let allGeneratedTrigrams = section.sentences.flatMap(\.trigrams)
        guard !allGeneratedTrigrams.isEmpty else {
            return DimensionScore(dimension: .donorSentenceSimilarity, score: 0.0, subMetrics: [], baselineRange: nil)
        }

        var trigramHits = 0
        for trigram in allGeneratedTrigrams {
            if corpusStats.trigramIndex[trigram] != nil {
                trigramHits += 1
            }
        }
        let trigramOverlap = Double(trigramHits) / Double(allGeneratedTrigrams.count)
        let d8TriTol = max(corpusStats.corpusTrigramOverlapSD, 0.05)
        let trigramScore = proximityScore(actual: trigramOverlap, corpus: corpusStats.corpusTrigramOverlapMedian, tolerance: d8TriTol)
        subMetrics.append(SubMetricScore(name: "3-gram Overlap", rawValue: trigramOverlap, corpusMean: corpusStats.corpusTrigramOverlapMedian, score: trigramScore, tolerance: d8TriTol))

        // Opening pattern match — corpus-derived fixed tolerance (SD across ~77 sections)
        let corpusOpeners = corpusStats.openingPatterns
        let openerHits = section.sentences.filter { corpusOpeners.contains($0.firstWord) }.count
        let openerRate = section.sentences.isEmpty ? 0 : Double(openerHits) / Double(section.sentences.count)
        let d8OpTol = max(corpusStats.corpusOpenerPatternMatchSD, 0.05)
        let openerScore = proximityScore(
            actual: openerRate,
            corpus: corpusStats.corpusOpenerPatternMatchMedian,
            tolerance: d8OpTol
        )
        subMetrics.append(SubMetricScore(name: "Opener Pattern Match", rawValue: openerRate, corpusMean: corpusStats.corpusOpenerPatternMatchMedian, score: openerScore, tolerance: d8OpTol))

        // Hint distribution match — corpus-derived fixed tolerance (SD across ~77 sections)
        // Raw metric: average absolute difference between section hint rates and corpus hint rates.
        let corpusHintRates = corpusStats.hintRates
        var totalAbsDiff = 0.0
        var hintCount = 0
        for (hint, corpusRate) in corpusHintRates {
            let genRate = section.sentences.isEmpty ? 0 :
                Double(section.sentences.filter { $0.deterministicHints.contains(hint) }.count) / Double(section.sentences.count)
            totalAbsDiff += abs(genRate - corpusRate)
            hintCount += 1
        }
        if hintCount > 0 {
            let avgAbsDiff = totalAbsDiff / Double(hintCount)
            let d8HintTol = max(corpusStats.corpusHintDiffSD, 0.05)
            let hintScore = proximityScore(
                actual: avgAbsDiff,
                corpus: corpusStats.corpusHintDiffMedian,
                tolerance: d8HintTol
            )
            subMetrics.append(SubMetricScore(name: "Hint Distribution Match", rawValue: avgAbsDiff, corpusMean: corpusStats.corpusHintDiffMedian, score: hintScore, tolerance: d8HintTol))
        }

        let avgScore = subMetrics.map(\.score).reduce(0, +) / Double(max(subMetrics.count, 1))
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.donorSentenceSimilarity.rawValue] }

        return DimensionScore(dimension: .donorSentenceSimilarity, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: D3: Structural Shape

    static func scoreStructuralShape(
        section: ParsedSection,
        sectionProfiles: [SectionProfile],
        corpusStats: CorpusStats,
        baseline: BaselineProfile?
    ) -> DimensionScore {

        var subMetrics: [SubMetricScore] = []
        let moveKey = section.moveType ?? ""

        // 1. Sentence Length Distribution — RANGE-scored per bucket
        // Measures whether the section's mix of short/medium/long sentences
        // falls within the creator's observed distribution.
        let sentLengths = section.sentences.map(\.wordCount)
        let shortCount = sentLengths.filter { $0 <= corpusStats.shortSentenceMax }.count
        let longCount = sentLengths.filter { $0 >= corpusStats.longSentenceMin }.count
        let mediumCount = sentLengths.count - shortCount - longCount
        let bucketTotal = max(Double(sentLengths.count), 1.0)

        let shortPct = Double(shortCount) / bucketTotal
        let mediumPct = Double(mediumCount) / bucketTotal
        let longPct = Double(longCount) / bucketTotal

        let shortScore: Double
        let mediumScore: Double
        let longScore: Double
        if let sRange = corpusStats.metricRange("shortPct"),
           let mRange = corpusStats.metricRange("mediumPct"),
           let lRange = corpusStats.metricRange("longPct") {
            shortScore = rangeScore(actual: shortPct, range: sRange)
            mediumScore = rangeScore(actual: mediumPct, range: mRange)
            longScore = rangeScore(actual: longPct, range: lRange)
        } else {
            shortScore = 50.0; mediumScore = 50.0; longScore = 50.0
        }
        let distScore = (shortScore + mediumScore + longScore) / 3.0
        // Report median short% as corpusMean for display; rawValue is the composite score
        let corpusShortMedian = corpusStats.metricRange("shortPct").map { ($0.p25 + $0.p75) / 2.0 } ?? 0.33
        subMetrics.append(SubMetricScore(name: "Sent Length Distrib", rawValue: distScore, corpusMean: corpusShortMedian * 100, score: distScore,
            tolerance: corpusStats.metricRange("shortPct")?.iqr))

        // 2. Opening Signature Match — MEMBERSHIP-scored: does this opener sig exist in corpus?
        if let firstSent = section.sentences.first {
            let firstRolled = SignatureRollupService.rollupDominantSlot(extractSlotSignature(from: firstSent))
            let corpusOpenerSigs = corpusStats.rolledOpenerSlotSignatures(forMove: moveKey)
            let openerMatch = corpusOpenerSigs.contains(firstRolled) ? 1.0 : 0.0
            let openScore = openerMatch * 100.0
            subMetrics.append(SubMetricScore(name: "Opening Sig Match", rawValue: openerMatch, corpusMean: 1.0, score: openScore))
        }

        // 3. Closing Signature Match — MEMBERSHIP-scored: does this closer sig exist in corpus?
        if let lastSent = section.sentences.last, section.sentences.count > 1 {
            let lastRolled = SignatureRollupService.rollupDominantSlot(extractSlotSignature(from: lastSent))
            let corpusCloserSigs = corpusStats.rolledCloserSlotSignatures(forMove: moveKey)
            let closerMatch = corpusCloserSigs.contains(lastRolled) ? 1.0 : 0.0
            let closeScore = closerMatch * 100.0
            subMetrics.append(SubMetricScore(name: "Closing Sig Match", rawValue: closerMatch, corpusMean: 1.0, score: closeScore))
        }

        let avgScore = subMetrics.isEmpty ? 50.0 : subMetrics.map(\.score).reduce(0, +) / Double(subMetrics.count)
        let baselineRange = baseline.flatMap { $0.dimensionRanges[FidelityDimension.structuralShape.rawValue] }

        return DimensionScore(dimension: .structuralShape, score: avgScore, subMetrics: subMetrics, baselineRange: baselineRange)
    }

    // MARK: - Corpus Stats Builder

    /// Build pre-aggregated corpus statistics from raw donor data.
    /// Called once in the Structure Workbench when computing the fidelity baseline.
    static func buildCorpusStats(
        creatorId: String,
        donorSentences: [CreatorSentence],
        rhythmTemplates: [RhythmTemplate] = []
    ) -> CorpusStats {
        let total = Double(max(donorSentences.count, 1))

        // Sentence-level aggregates
        let avgLen = donorSentences.map { Double($0.wordCount) }.reduce(0, +) / total
        let lengths = donorSentences.map { Double($0.wordCount) }
        let mean = lengths.reduce(0, +) / total
        let sentenceVariance = lengths.count > 1
            ? lengths.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lengths.count - 1)
            : 0.0

        // D3: Sentence length tertile boundaries (short/medium/long bucket thresholds)
        let sortedAllLengths = lengths.sorted()
        let shortSentenceMax: Int
        let longSentenceMin: Int
        if sortedAllLengths.count >= 3 {
            let t33 = sortedAllLengths[Int(Double(sortedAllLengths.count - 1) * 0.33)]
            let t67 = sortedAllLengths[Int(Double(sortedAllLengths.count - 1) * 0.67)]
            shortSentenceMax = Int(t33)
            longSentenceMin = Int(t67) + 1
        } else {
            shortSentenceMax = 7
            longSentenceMin = 18
        }

        let avgClauses = donorSentences.map { Double($0.clauseCount) }.reduce(0, +) / total
        let questionRate = Double(donorSentences.filter(\.isQuestion).count) / total
        let fragmentRate = Double(donorSentences.filter(\.isFragment).count) / total

        // Pronoun rates from deterministic hints
        let fpCount = donorSentences.filter { ($0.deterministicHints ?? []).contains("hasFirstPerson") }.count
        let spCount = donorSentences.filter { ($0.deterministicHints ?? []).contains("hasSecondPerson") }.count

        // Contraction rate via raw text scan
        let contractionPattern = #"(?i)\b\w+(?:'|')\w+\b"#
        let contractionRegex = try? NSRegularExpression(pattern: contractionPattern)
        var totalContractions = 0
        for s in donorSentences {
            let range = NSRange(s.rawText.startIndex..., in: s.rawText)
            totalContractions += contractionRegex?.numberOfMatches(in: s.rawText, range: range) ?? 0
        }
        let contractionRate = Double(totalContractions) / total

        // Opener distribution
        var openerCounts: [String: Int] = [:]
        for s in donorSentences {
            let firstWord = s.openingPattern.split(separator: " ").first.map(String.init) ?? ""
            if !firstWord.isEmpty {
                openerCounts[firstWord.lowercased(), default: 0] += 1
            }
        }
        let openerDist = openerCounts.mapValues { Double($0) / total }
        let uniqueOpenerRatio = donorSentences.isEmpty ? 1.0 : Double(Set(openerCounts.keys).count) / total

        // Group by moveType
        let byMove = Dictionary(grouping: donorSentences, by: \.moveType)

        // Group by real sections (videoId + sectionIndex) for per-section aggregates
        let allSections = Dictionary(grouping: donorSentences) { "\($0.videoId)_\($0.sectionIndex)" }

        // Per-move: median sentences per section and median words per section
        var sentencesPerMove: [String: Double] = [:]
        var wordCountPerMove: [String: Double] = [:]
        for (moveType, sentences) in byMove {
            let bySection = Dictionary(grouping: sentences) { "\($0.videoId)_\($0.sectionIndex)" }
            let countsPerSection = bySection.values.map { Double($0.count) }.sorted()
            sentencesPerMove[moveType] = median(of: countsPerSection)
            let wordsPerSection = bySection.values.map { group in
                group.map { Double($0.wordCount) }.reduce(0, +)
            }.sorted()
            wordCountPerMove[moveType] = median(of: wordsPerSection)
        }

        // Average words per section (total words / total sections)
        let sectionWordCounts = allSections.values.map { group in
            group.map { Double($0.wordCount) }.reduce(0, +)
        }
        let avgWordCountPerSection = sectionWordCounts.reduce(0, +) / Double(max(sectionWordCounts.count, 1))

        // Vocabulary density: median unique-words/total-words per section
        let densities = allSections.values.map { group -> Double in
            let words = group.flatMap { $0.rawText.lowercased().split(separator: " ").map(String.init) }
            return words.isEmpty ? 0 : Double(Set(words).count) / Double(words.count)
        }
        let vocabularyDensity = median(of: densities.sorted())

        // Corpus engagement: median per-section engagement score
        let engagements = allSections.values.map { group -> Double in
            let sTotal = Double(max(group.count, 1))
            let qRate = Double(group.filter(\.isQuestion).count) / sTotal
            let daRate = Double(group.filter(\.hasDirectAddress).count) / sTotal
            let fpHints = group.filter { ($0.deterministicHints ?? []).contains("hasFirstPerson") }
            let fpRate = Double(fpHints.count) / sTotal
            return qRate * 0.4 + daRate * 0.3 + min(fpRate * 0.3, 0.3)
        }
        let corpusEngagement = median(of: engagements.sorted())

        // Per-section distribution quartiles (for IQR-based tolerances)
        let sectionSentenceCounts = allSections.values.map { Double($0.count) }.sorted()
        let sentenceCountP25 = percentile25(of: sectionSentenceCounts)
        let sentenceCountP75 = percentile75(of: sectionSentenceCounts)

        let sortedWordCounts = sectionWordCounts.sorted()
        let wordCountPerSectionP25 = percentile25(of: sortedWordCounts)
        let wordCountPerSectionP75 = percentile75(of: sortedWordCounts)

        // Per-section length variance distribution
        let sectionLengthVariances: [Double] = allSections.values.map { group -> Double in
            let lens = group.map { Double($0.wordCount) }
            guard lens.count > 1 else { return 0 }
            let m = lens.reduce(0, +) / Double(lens.count)
            return lens.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(lens.count - 1)
        }.sorted()
        let lengthVarianceP25 = percentile25(of: sectionLengthVariances)
        let lengthVarianceP75 = percentile75(of: sectionLengthVariances)

        // Trigram index
        var trigramIndex: [String: Int] = [:]
        for s in donorSentences {
            let words = s.rawText.lowercased().split(separator: " ").map(String.init)
            if words.count >= 3 {
                for i in 0..<(words.count - 2) {
                    let tri = "\(words[i]) \(words[i+1]) \(words[i+2])"
                    trigramIndex[tri, default: 0] += 1
                }
            }
        }

        // Direct address rate
        let daRate = Double(donorSentences.filter(\.hasDirectAddress).count) / total

        // Hint rates
        var hintCounts: [String: Int] = [:]
        for s in donorSentences {
            for hint in s.deterministicHints ?? [] {
                hintCounts[hint, default: 0] += 1
            }
        }
        let hintRates = hintCounts.mapValues { Double($0) / total }

        // Pre-aggregated slot data per move type.
        // Uses LLM-assigned CreatorSentence.slotSignature for corpus truth,
        // plus dominant-slot rollup for cross-granularity matching at eval time.
        // Heuristic-extracted sigs kept for backward-compatible debug reports.
        var slotSignaturesByMove: [String: [String]] = [:]
        var openerSlotSignaturesByMove: [String: [String]] = [:]
        var closerSlotSignaturesByMove: [String: [String]] = [:]
        var slotBigramsByMove: [String: [String]] = [:]
        var rolledSlotSignaturesByMove: [String: [String]] = [:]
        var rolledOpenerSlotSignaturesByMove: [String: [String]] = [:]
        var rolledCloserSlotSignaturesByMove: [String: [String]] = [:]
        var rolledSlotBigramsByMove: [String: [String]] = [:]

        // S2 distribution accumulators (frequency-aware, not deduplicated)
        var rawSlotDistributionByMove: [String: [String: Double]] = [:]
        var rawBigramDistributionByMove: [String: [String: Double]] = [:]
        var rawOpenerDistributionByMove: [String: [String: Double]] = [:]

        for (moveType, sentences) in byMove {
            var rawSigs: Set<String> = []
            var rawOpenerSigs: Set<String> = []
            var rawCloserSigs: Set<String> = []
            var rawBigrams: Set<String> = []
            var rolledSigs: Set<String> = []
            var rolledOpenerSigs: Set<String> = []
            var rolledCloserSigs: Set<String> = []
            var rolledBigrams: Set<String> = []
            var prevRawSig: String?
            var prevRolledSig: String?

            // S2 distribution counters (count every occurrence, not just unique)
            var rawSigCounts: [String: Int] = [:]
            var rawBigramCounts: [String: Int] = [:]
            var rawOpenerSigCounts: [String: Int] = [:]

            let bySection = Dictionary(grouping: sentences) { "\($0.videoId)_\($0.sectionIndex)" }

            for s in sentences.sorted(by: { $0.sentenceIndex < $1.sentenceIndex }) {
                // Use LLM-assigned signature; fall back to heuristic if empty
                let rawSig: String
                if !s.slotSignature.isEmpty {
                    rawSig = s.slotSignature
                } else {
                    let parsed = parseSentence(text: s.rawText, index: s.sentenceIndex)
                    rawSig = extractSlotSignature(from: parsed)
                }
                let rolledSig = SignatureRollupService.rollupDominantSlot(rawSig)

                rawSigs.insert(rawSig)
                rolledSigs.insert(rolledSig)
                rawSigCounts[rawSig, default: 0] += 1
                if s.sentenceIndex == 0 {
                    rawOpenerSigs.insert(rawSig)
                    rolledOpenerSigs.insert(rolledSig)
                    rawOpenerSigCounts[rawSig, default: 0] += 1
                }
                if let prev = prevRawSig {
                    rawBigrams.insert("\(prev)→\(rawSig)")
                    rawBigramCounts["\(prev)→\(rawSig)", default: 0] += 1
                }
                if let prev = prevRolledSig { rolledBigrams.insert("\(prev)→\(rolledSig)") }
                prevRawSig = rawSig
                prevRolledSig = rolledSig
            }

            // Closer sigs: last sentence per section
            for (_, sectionSentences) in bySection {
                if let lastSent = sectionSentences.max(by: { $0.sentenceIndex < $1.sentenceIndex }) {
                    let closerRaw = !lastSent.slotSignature.isEmpty ? lastSent.slotSignature : {
                        let p = parseSentence(text: lastSent.rawText, index: lastSent.sentenceIndex)
                        return extractSlotSignature(from: p)
                    }()
                    rawCloserSigs.insert(closerRaw)
                    rolledCloserSigs.insert(SignatureRollupService.rollupDominantSlot(closerRaw))
                }
            }

            slotSignaturesByMove[moveType] = Array(rawSigs)
            openerSlotSignaturesByMove[moveType] = Array(rawOpenerSigs)
            closerSlotSignaturesByMove[moveType] = Array(rawCloserSigs)
            slotBigramsByMove[moveType] = Array(rawBigrams)
            rolledSlotSignaturesByMove[moveType] = Array(rolledSigs)
            rolledOpenerSlotSignaturesByMove[moveType] = Array(rolledOpenerSigs)
            rolledCloserSlotSignaturesByMove[moveType] = Array(rolledCloserSigs)
            rolledSlotBigramsByMove[moveType] = Array(rolledBigrams)

            // Normalize S2 distribution counters to proportions
            let totalSigs = Double(rawSigCounts.values.reduce(0, +))
            rawSlotDistributionByMove[moveType] = totalSigs > 0
                ? rawSigCounts.mapValues { Double($0) / totalSigs } : [:]

            let totalBigrams = Double(rawBigramCounts.values.reduce(0, +))
            rawBigramDistributionByMove[moveType] = totalBigrams > 0
                ? rawBigramCounts.mapValues { Double($0) / totalBigrams } : [:]

            let totalOpeners = Double(rawOpenerSigCounts.values.reduce(0, +))
            rawOpenerDistributionByMove[moveType] = totalOpeners > 0
                ? rawOpenerSigCounts.mapValues { Double($0) / totalOpeners } : [:]
        }

        // Corpus bigram match rate: for each section, compute rolled-up bigram match rate
        // against the per-move rolled bigram set, then take the median across all sections.
        var bigramRates: [Double] = []
        for (_, sectionSentences) in allSections {
            guard sectionSentences.count > 1 else { continue }
            let moveType = sectionSentences.first?.moveType ?? ""
            let corpusRolledBigrams = Set(rolledSlotBigramsByMove[moveType] ?? [])
            let sorted = sectionSentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            var rolledSigs: [String] = []
            for s in sorted {
                let rawSig = !s.slotSignature.isEmpty ? s.slotSignature : {
                    let p = parseSentence(text: s.rawText, index: s.sentenceIndex)
                    return extractSlotSignature(from: p)
                }()
                rolledSigs.append(SignatureRollupService.rollupDominantSlot(rawSig))
            }
            var hits = 0
            for i in 0..<(rolledSigs.count - 1) {
                if corpusRolledBigrams.contains("\(rolledSigs[i])→\(rolledSigs[i + 1])") { hits += 1 }
            }
            bigramRates.append(Double(hits) / Double(rolledSigs.count - 1))
        }
        let corpusBigramMatchRate = median(of: bigramRates.sorted())

        // Opening patterns — uses heuristic extraction (parseSentence firstWord)
        // so the comparison is apples-to-apples with evaluation-time extraction.
        var openingPatterns: Set<String> = []
        for s in donorSentences {
            let parsed = parseSentence(text: s.rawText, index: s.sentenceIndex)
            if !parsed.firstWord.isEmpty {
                openingPatterns.insert(parsed.firstWord)
            }
        }
        let openingPatternSet = Array(openingPatterns)

        // Casual markers — known set
        let casualMarkers = ["right", "look", "now", "so", "okay", "actually", "basically", "honestly", "literally", "sure"]

        // --- Precompute per-section sub-metric distributions ---
        // Every proximityScore tolerance must be a precomputed corpus constant.
        // For each of the ~77 real sections, compute every raw sub-metric value,
        // then derive median + SD to use as fixed tolerances.

        let corpusOpenerSet = Set(openerDist.filter { $0.value > 0.01 }.keys)
        let corpusHintRates = hintCounts.mapValues { Double($0) / total }

        var openerOverlapRates: [Double] = []
        var openerPatternMatchRates: [Double] = []
        var hintDiffs: [Double] = []
        var perSectionAvgLengths: [Double] = []
        var perSectionQuestionDensities: [Double] = []
        var perSectionFragmentRates: [Double] = []
        var perSectionFPRates: [Double] = []
        var perSectionContractionRates: [Double] = []
        var perSectionDARates: [Double] = []
        var perSectionWordCounts: [Double] = []
        var perSectionVocabDensities: [Double] = []
        var perSectionEngagements: [Double] = []
        var perSectionAlternationRates: [Double] = []
        var perSectionBigramRates: [Double] = []
        // New accumulators for previously-hardcoded metrics
        var perSectionCasualMarkerCounts: [Double] = []
        var perSectionSignatureMatchRates: [Double] = []
        var perSectionRawSigMatchRates: [Double] = []
        var perSectionRawBigramRates: [Double] = []
        var perSectionSlotDistCosin: [Double] = []
        var perSectionBigramDistCosin: [Double] = []
        var perSectionWordCountInRangeRates: [Double] = []
        var perSectionTypeMatchRates: [Double] = []
        var perSectionTrigramOverlapRates: [Double] = []
        var perSectionOpenerSigOverlaps: [Double] = []
        var perSectionCloserSigOverlaps: [Double] = []
        var collectedOpenerSigs: [(moveType: String, sig: String)] = []
        var collectedCloserSigs: [(moveType: String, sig: String)] = []
        // D3: Per-section bucket percentages for sentence length distribution
        var perSectionShortPcts: [Double] = []
        var perSectionMediumPcts: [Double] = []
        var perSectionLongPcts: [Double] = []
        // D5: Cadence transition counts and per-section fit values
        var cadenceTransitionCounts: [String: Int] = [:]  // "short→long" → count
        var cadenceRowTotals: [String: Int] = [:]          // "short" → total transitions from short
        var perSectionCadenceFits: [Double] = []
        let casualMarkerSet = Set(casualMarkers.map { $0.lowercased() })

        for (_, sectionSentences) in allSections {
            let parsedSents = sectionSentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
                .map { parseSentence(text: $0.rawText, index: $0.sentenceIndex) }
            guard !parsedSents.isEmpty else { continue }
            let sentCount = Double(parsedSents.count)

            // D1: Avg sentence length
            let sectionWordCount = parsedSents.map { Double($0.wordCount) }.reduce(0, +)
            let sAvgLen = sectionWordCount / sentCount
            perSectionAvgLengths.append(sAvgLen)

            // D1: Question density
            perSectionQuestionDensities.append(Double(parsedSents.filter(\.isQuestion).count) / sentCount)

            // D1: Fragment rate
            perSectionFragmentRates.append(Double(parsedSents.filter(\.isFragment).count) / sentCount)

            // D2: First-person rate (binary per-sentence)
            perSectionFPRates.append(Double(parsedSents.filter { $0.firstPersonCount > 0 }.count) / sentCount)

            // D2: Contraction rate (binary per-sentence)
            perSectionContractionRates.append(Double(parsedSents.filter { $0.contractionCount > 0 }.count) / sentCount)

            // D2: Direct address rate
            perSectionDARates.append(Double(parsedSents.filter(\.hasDirectAddress).count) / sentCount)

            // D2: Opener overlap rate
            let sectionOpeners = Set(parsedSents.map(\.firstWord))
            if !sectionOpeners.isEmpty {
                let overlap = sectionOpeners.filter { corpusOpenerSet.contains($0) }.count
                openerOverlapRates.append(Double(overlap) / Double(sectionOpeners.count))
            }

            // D6: Word count per section
            perSectionWordCounts.append(sectionWordCount)

            // D6: Vocabulary density
            let allWords = parsedSents.flatMap(\.words).map { $0.lowercased() }
            if !allWords.isEmpty {
                perSectionVocabDensities.append(Double(Set(allWords).count) / Double(allWords.count))
            }

            // D7: Engagement score
            let sQRate = Double(parsedSents.filter(\.isQuestion).count) / sentCount
            let sDARate = Double(parsedSents.filter(\.hasDirectAddress).count) / sentCount
            let sFPRate = Double(parsedSents.filter { $0.firstPersonCount > 0 }.count) / sentCount
            perSectionEngagements.append(sQRate * 0.4 + sDARate * 0.3 + min(sFPRate * 0.3, 0.3))

            // D5: Alternation rate
            if parsedSents.count >= 3 {
                let lengths = parsedSents.map(\.wordCount)
                let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
                var alternations = 0
                for i in 1..<lengths.count {
                    if (Double(lengths[i - 1]) > mean) != (Double(lengths[i]) > mean) { alternations += 1 }
                }
                perSectionAlternationRates.append(Double(alternations) / Double(lengths.count - 1))
            }

            // D4: Bigram match rate
            let moveType = sectionSentences.first?.moveType ?? ""
            let corpusBigrams = Set(slotBigramsByMove[moveType] ?? [])
            if parsedSents.count > 1 {
                let sigs = parsedSents.map { extractSlotSignature(from: $0) }
                var hits = 0
                for i in 0..<(sigs.count - 1) {
                    if corpusBigrams.contains("\(sigs[i])→\(sigs[i + 1])") { hits += 1 }
                }
                perSectionBigramRates.append(Double(hits) / Double(sigs.count - 1))
            }

            // D8: Opener Pattern Match rate
            let openerHits = parsedSents.filter { openingPatterns.contains($0.firstWord) }.count
            openerPatternMatchRates.append(Double(openerHits) / sentCount)

            // D8: Hint Distribution diff
            var totalAbsDiff = 0.0
            var hCount = 0
            for (hint, corpusRate) in corpusHintRates {
                let genRate = Double(parsedSents.filter { $0.deterministicHints.contains(hint) }.count) / sentCount
                totalAbsDiff += abs(genRate - corpusRate)
                hCount += 1
            }
            if hCount > 0 {
                hintDiffs.append(totalAbsDiff / Double(hCount))
            }

            // --- New accumulators for previously-hardcoded metrics ---

            // D2: Casual marker count per section
            let sectionFullText = sectionSentences.map(\.rawText).joined(separator: " ").lowercased()
            let casualCount = casualMarkerSet.filter { sectionFullText.contains($0) }.count
            perSectionCasualMarkerCounts.append(Double(casualCount))

            // D4: Signature match rate (heuristic sigs vs corpus rolled set)
            let moveType2 = sectionSentences.first?.moveType ?? ""
            let corpusRolledSigSet = Set(rolledSlotSignaturesByMove[moveType2] ?? [])
            let heuristicSigs = parsedSents.map { extractSlotSignature(from: $0) }
            let rolledHeuristicSigs = heuristicSigs.map { SignatureRollupService.rollupDominantSlot($0) }
            if !rolledHeuristicSigs.isEmpty {
                let sigMatchCount = rolledHeuristicSigs.filter { corpusRolledSigSet.contains($0) }.count
                perSectionSignatureMatchRates.append(Double(sigMatchCount) / Double(rolledHeuristicSigs.count))
            }

            // S2: Raw (unrolled) signature match rate — uses LLM-assigned slotSignature directly
            let corpusRawSigSet = Set(slotSignaturesByMove[moveType2] ?? [])
            let rawSigsForSection = sectionSentences
                .sorted { $0.sentenceIndex < $1.sentenceIndex }
                .map(\.slotSignature)
                .filter { !$0.isEmpty }
            if !rawSigsForSection.isEmpty {
                let rawSigMatchCount = rawSigsForSection.filter { corpusRawSigSet.contains($0) }.count
                perSectionRawSigMatchRates.append(Double(rawSigMatchCount) / Double(rawSigsForSection.count))
            }

            // S2: Raw bigram match rate (unrolled sigs, no rollup)
            let corpusRawBigramSet = Set(slotBigramsByMove[moveType2] ?? [])
            if rawSigsForSection.count > 1 {
                var rawBigramHits = 0
                for i in 0..<(rawSigsForSection.count - 1) {
                    if corpusRawBigramSet.contains("\(rawSigsForSection[i])→\(rawSigsForSection[i + 1])") {
                        rawBigramHits += 1
                    }
                }
                perSectionRawBigramRates.append(Double(rawBigramHits) / Double(rawSigsForSection.count - 1))
            }

            // S2: Per-section slot distribution cosine similarity vs corpus distribution
            if !rawSigsForSection.isEmpty {
                var sectionSlotCounts: [String: Int] = [:]
                for sig in rawSigsForSection { sectionSlotCounts[sig, default: 0] += 1 }
                let sectionTotal = Double(sectionSlotCounts.values.reduce(0, +))
                let sectionDist = sectionTotal > 0 ? sectionSlotCounts.mapValues { Double($0) / sectionTotal } : [:]
                let corpusDist = rawSlotDistributionByMove[moveType2] ?? [:]
                perSectionSlotDistCosin.append(cosineSimilarity(sectionDist, corpusDist))
            }

            // S2: Per-section bigram distribution cosine similarity vs corpus distribution
            if rawSigsForSection.count > 1 {
                var sectionBigramCounts: [String: Int] = [:]
                for i in 0..<(rawSigsForSection.count - 1) {
                    sectionBigramCounts["\(rawSigsForSection[i])→\(rawSigsForSection[i + 1])", default: 0] += 1
                }
                let sectionTotal = Double(sectionBigramCounts.values.reduce(0, +))
                let sectionDist = sectionTotal > 0 ? sectionBigramCounts.mapValues { Double($0) / sectionTotal } : [:]
                let corpusDist = rawBigramDistributionByMove[moveType2] ?? [:]
                perSectionBigramDistCosin.append(cosineSimilarity(sectionDist, corpusDist))
            }

            // D5: Word count in-range rate (against rhythm templates)
            let relevantTemplates = rhythmTemplates.filter { $0.moveType == moveType2 }
            if !relevantTemplates.isEmpty {
                var inRangeCount = 0
                for (i, sent) in parsedSents.enumerated() {
                    let position = sectionPosition(index: i, total: parsedSents.count)
                    let template = relevantTemplates.first { $0.positionInSection == position }
                    if let t = template {
                        if sent.wordCount >= t.wordCountMin && sent.wordCount <= t.wordCountMax {
                            inRangeCount += 1
                        }
                    } else {
                        inRangeCount += 1  // No template → generous
                    }
                }
                perSectionWordCountInRangeRates.append(Double(inRangeCount) / sentCount)
            }

            // D5: Type match rate (against rhythm templates)
            if !relevantTemplates.isEmpty {
                var typeMatchCount = 0
                for (i, sent) in parsedSents.enumerated() {
                    let position = sectionPosition(index: i, total: parsedSents.count)
                    let template = relevantTemplates.first { $0.positionInSection == position }
                    if let t = template {
                        let actualType: String
                        if sent.isQuestion { actualType = "question" }
                        else if sent.isFragment { actualType = "fragment" }
                        else { actualType = "statement" }
                        if actualType == t.sentenceType { typeMatchCount += 1 }
                    } else {
                        typeMatchCount += 1
                    }
                }
                perSectionTypeMatchRates.append(Double(typeMatchCount) / sentCount)
            }

            // D8: Trigram overlap rate
            let sectionTrigrams = parsedSents.flatMap(\.trigrams)
            if !sectionTrigrams.isEmpty {
                let triHits = sectionTrigrams.filter { trigramIndex[$0] != nil }.count
                perSectionTrigramOverlapRates.append(Double(triHits) / Double(sectionTrigrams.count))
            }

            // D3: Sentence length distribution — compute short/medium/long bucket percentages
            let sectionSentLengths = parsedSents.map(\.wordCount)
            let shortCount = sectionSentLengths.filter { $0 <= shortSentenceMax }.count
            let longCount = sectionSentLengths.filter { $0 >= longSentenceMin }.count
            let mediumCount = sectionSentLengths.count - shortCount - longCount
            let bucketTotal = max(Double(sectionSentLengths.count), 1.0)
            perSectionShortPcts.append(Double(shortCount) / bucketTotal)
            perSectionMediumPcts.append(Double(mediumCount) / bucketTotal)
            perSectionLongPcts.append(Double(longCount) / bucketTotal)

            // D5: Cadence transitions — classify each sentence and count adjacent transitions
            let sectionBuckets = sectionSentLengths.map { wc -> String in
                if wc <= shortSentenceMax { return "short" }
                if wc >= longSentenceMin { return "long" }
                return "medium"
            }
            for i in 0..<max(0, sectionBuckets.count - 1) {
                let key = "\(sectionBuckets[i])→\(sectionBuckets[i + 1])"
                cadenceTransitionCounts[key, default: 0] += 1
                cadenceRowTotals[sectionBuckets[i], default: 0] += 1
            }

            // D3: Opener/Closer sig — collect for frequency computation (second pass)
            if let firstSent = parsedSents.first {
                let openerSig = SignatureRollupService.rollupDominantSlot(extractSlotSignature(from: firstSent))
                collectedOpenerSigs.append((moveType: moveType2, sig: openerSig))
            }
            if let lastSent = parsedSents.last, parsedSents.count > 1 {
                let closerSig = SignatureRollupService.rollupDominantSlot(extractSlotSignature(from: lastSent))
                collectedCloserSigs.append((moveType: moveType2, sig: closerSig))
            }
        }

        // --- Second pass: compute opener/closer sig frequency distributions ---
        // For each move type, count how many sections use each rolled sig, then convert to fractions.
        // This produces continuous RAW values (0.0–1.0) instead of binary 0/1 for D3 sig matching.
        var openerSigCountsByMove: [String: [String: Int]] = [:]
        for item in collectedOpenerSigs {
            openerSigCountsByMove[item.moveType, default: [:]][item.sig, default: 0] += 1
        }
        var rolledOpenerSigFreqByMove: [String: [String: Double]] = [:]
        for (move, sigCounts) in openerSigCountsByMove {
            let totalSections = Double(sigCounts.values.reduce(0, +))
            guard totalSections > 0 else { continue }
            rolledOpenerSigFreqByMove[move] = sigCounts.mapValues { Double($0) / totalSections }
        }

        var closerSigCountsByMove: [String: [String: Int]] = [:]
        for item in collectedCloserSigs {
            closerSigCountsByMove[item.moveType, default: [:]][item.sig, default: 0] += 1
        }
        var rolledCloserSigFreqByMove: [String: [String: Double]] = [:]
        for (move, sigCounts) in closerSigCountsByMove {
            let totalSections = Double(sigCounts.values.reduce(0, +))
            guard totalSections > 0 else { continue }
            rolledCloserSigFreqByMove[move] = sigCounts.mapValues { Double($0) / totalSections }
        }

        // Populate per-section overlap arrays using frequency (not binary)
        for item in collectedOpenerSigs {
            perSectionOpenerSigOverlaps.append(rolledOpenerSigFreqByMove[item.moveType]?[item.sig] ?? 0.0)
        }
        for item in collectedCloserSigs {
            perSectionCloserSigOverlaps.append(rolledCloserSigFreqByMove[item.moveType]?[item.sig] ?? 0.0)
        }

        // Compute median + SD for every sub-metric
        let corpusOpenerOverlapMedian = median(of: openerOverlapRates.sorted())
        let corpusOpenerOverlapSD = standardDeviation(of: openerOverlapRates)
        let corpusOpenerPatternMatchMedian = median(of: openerPatternMatchRates.sorted())
        let corpusOpenerPatternMatchSD = standardDeviation(of: openerPatternMatchRates)
        let corpusHintDiffMedian = median(of: hintDiffs.sorted())
        let corpusHintDiffSD = standardDeviation(of: hintDiffs)
        let corpusAvgSentenceLengthSD = standardDeviation(of: perSectionAvgLengths)
        let corpusQuestionDensitySD = standardDeviation(of: perSectionQuestionDensities)
        let corpusFragmentRateSD = standardDeviation(of: perSectionFragmentRates)
        let corpusFirstPersonRateSD = standardDeviation(of: perSectionFPRates)
        let corpusContractionRateSD = standardDeviation(of: perSectionContractionRates)
        let corpusDirectAddressRateSD = standardDeviation(of: perSectionDARates)
        let corpusBigramRateSD = standardDeviation(of: perSectionBigramRates)
        let corpusWordCountSD = standardDeviation(of: perSectionWordCounts)
        let corpusVocabularyDensitySD = standardDeviation(of: perSectionVocabDensities)
        let corpusEngagementSD = standardDeviation(of: perSectionEngagements)
        let corpusAlternationSD = standardDeviation(of: perSectionAlternationRates)

        // New median + SD for previously-hardcoded metrics
        let corpusCasualMarkerMedian = median(of: perSectionCasualMarkerCounts.sorted())
        let corpusCasualMarkerSD = standardDeviation(of: perSectionCasualMarkerCounts)
        let corpusSignatureMatchMedian = median(of: perSectionSignatureMatchRates.sorted())
        let corpusSignatureMatchSD = standardDeviation(of: perSectionSignatureMatchRates)
        let corpusWordCountInRangeMedian = median(of: perSectionWordCountInRangeRates.sorted())
        let corpusWordCountInRangeSD = standardDeviation(of: perSectionWordCountInRangeRates)
        let corpusTypeMatchMedian = median(of: perSectionTypeMatchRates.sorted())
        let corpusTypeMatchSD = standardDeviation(of: perSectionTypeMatchRates)
        let corpusAlternationMedian = median(of: perSectionAlternationRates.sorted())
        let corpusTrigramOverlapMedian = median(of: perSectionTrigramOverlapRates.sorted())
        let corpusTrigramOverlapSD = standardDeviation(of: perSectionTrigramOverlapRates)
        let corpusOpenerSigOverlapMedian = median(of: perSectionOpenerSigOverlaps.sorted())
        let corpusOpenerSigOverlapSD = standardDeviation(of: perSectionOpenerSigOverlaps)
        let corpusCloserSigOverlapMedian = median(of: perSectionCloserSigOverlaps.sorted())
        let corpusCloserSigOverlapSD = standardDeviation(of: perSectionCloserSigOverlaps)

        // S2: Raw signature match stats
        let corpusRawSignatureMatchMedian = median(of: perSectionRawSigMatchRates.sorted())
        let corpusRawSignatureMatchSD = standardDeviation(of: perSectionRawSigMatchRates)
        let corpusRawBigramMatchRate = median(of: perSectionRawBigramRates.sorted())
        let corpusRawBigramRateSD = standardDeviation(of: perSectionRawBigramRates)

        // S2: Distribution-based cosine similarity baselines
        let corpusSlotDistCosinMedian = median(of: perSectionSlotDistCosin.sorted())
        let corpusSlotDistCosinSD = standardDeviation(of: perSectionSlotDistCosin)
        let corpusBigramDistCosinMedian = median(of: perSectionBigramDistCosin.sorted())
        let corpusBigramDistCosinSD = standardDeviation(of: perSectionBigramDistCosin)

        // D5: Build normalized cadence transition matrix from accumulated counts
        var cadenceTransitionMatrix: [String: Double] = [:]
        for (key, count) in cadenceTransitionCounts {
            let fromBucket = String(key.prefix(while: { $0 != "→" && $0 != "\u{2192}" }))
            // Handle both "→" (unicode arrow) formats
            let from = key.components(separatedBy: "→").first ?? fromBucket
            let rowTotal = cadenceRowTotals[from] ?? 1
            cadenceTransitionMatrix[key] = Double(count) / Double(max(rowTotal, 1))
        }

        // D5: Compute per-section cadence fit — avg transition probability for each section
        for (_, sectionSentences) in allSections {
            let sorted = sectionSentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            let sentLengths = sorted.map { $0.wordCount }
            guard sentLengths.count >= 2 else { continue }
            let buckets = sentLengths.map { wc -> String in
                if wc <= shortSentenceMax { return "short" }
                if wc >= longSentenceMin { return "long" }
                return "medium"
            }
            var totalProb = 0.0
            for i in 0..<(buckets.count - 1) {
                let key = "\(buckets[i])→\(buckets[i + 1])"
                totalProb += cadenceTransitionMatrix[key] ?? 0.0
            }
            perSectionCadenceFits.append(totalProb / Double(buckets.count - 1))
        }

        // Build MetricRange distributions for rangeScore()-based metrics.
        // All per-section arrays already exist above — just sort and extract percentiles.
        func buildRange(from values: [Double]) -> MetricRange {
            let sorted = values.sorted()
            return MetricRange(
                min: sorted.first ?? 0,
                p25: percentile25(of: sorted),
                p75: percentile75(of: sorted),
                max: sorted.last ?? 0
            )
        }

        var rangeDistributions: [String: MetricRange] = [:]
        rangeDistributions["firstPersonRate"] = buildRange(from: perSectionFPRates)
        rangeDistributions["contractionRate"] = buildRange(from: perSectionContractionRates)
        rangeDistributions["casualMarkers"] = buildRange(from: perSectionCasualMarkerCounts)
        rangeDistributions["directAddressRate"] = buildRange(from: perSectionDARates)
        rangeDistributions["sentenceCount"] = buildRange(from: sectionSentenceCounts)
        rangeDistributions["wordCount"] = buildRange(from: perSectionWordCounts)
        rangeDistributions["alternation"] = buildRange(from: perSectionAlternationRates)
        rangeDistributions["engagement"] = buildRange(from: perSectionEngagements)
        rangeDistributions["shortPct"] = buildRange(from: perSectionShortPcts)
        rangeDistributions["mediumPct"] = buildRange(from: perSectionMediumPcts)
        rangeDistributions["longPct"] = buildRange(from: perSectionLongPcts)
        rangeDistributions["cadenceFit"] = buildRange(from: perSectionCadenceFits)

        return CorpusStats(
            creatorId: creatorId,
            avgSentenceLength: avgLen,
            sentenceLengthVariance: sentenceVariance,
            avgClauseCount: avgClauses,
            questionRate: questionRate,
            fragmentRate: fragmentRate,
            firstPersonRate: Double(fpCount) / total,
            secondPersonRate: Double(spCount) / total,
            contractionRate: contractionRate,
            openerDistribution: openerDist,
            uniqueOpenerRatio: uniqueOpenerRatio,
            sentencesPerMove: sentencesPerMove,
            avgWordCountPerSection: avgWordCountPerSection,
            wordCountPerMove: wordCountPerMove,
            trigramIndex: trigramIndex,
            directAddressRate: daRate,
            hintRates: hintRates,
            casualMarkers: casualMarkers,
            vocabularyDensity: vocabularyDensity,
            corpusEngagement: corpusEngagement,
            slotSignaturesByMove: slotSignaturesByMove,
            openerSlotSignaturesByMove: openerSlotSignaturesByMove,
            slotBigramsByMove: slotBigramsByMove,
            openingPatternSet: openingPatternSet,
            sentenceCountP25: sentenceCountP25,
            sentenceCountP75: sentenceCountP75,
            wordCountPerSectionP25: wordCountPerSectionP25,
            wordCountPerSectionP75: wordCountPerSectionP75,
            lengthVarianceP25: lengthVarianceP25,
            lengthVarianceP75: lengthVarianceP75,
            closerSlotSignaturesByMove: closerSlotSignaturesByMove,
            corpusBigramMatchRate: corpusBigramMatchRate,
            corpusOpenerOverlapMedian: corpusOpenerOverlapMedian,
            corpusOpenerOverlapSD: corpusOpenerOverlapSD,
            corpusOpenerPatternMatchMedian: corpusOpenerPatternMatchMedian,
            corpusOpenerPatternMatchSD: corpusOpenerPatternMatchSD,
            corpusHintDiffMedian: corpusHintDiffMedian,
            corpusHintDiffSD: corpusHintDiffSD,
            corpusAvgSentenceLengthSD: corpusAvgSentenceLengthSD,
            corpusQuestionDensitySD: corpusQuestionDensitySD,
            corpusFragmentRateSD: corpusFragmentRateSD,
            corpusFirstPersonRateSD: corpusFirstPersonRateSD,
            corpusContractionRateSD: corpusContractionRateSD,
            corpusDirectAddressRateSD: corpusDirectAddressRateSD,
            corpusBigramRateSD: corpusBigramRateSD,
            corpusWordCountSD: corpusWordCountSD,
            corpusVocabularyDensitySD: corpusVocabularyDensitySD,
            corpusEngagementSD: corpusEngagementSD,
            corpusAlternationSD: corpusAlternationSD,
            corpusCasualMarkerMedian: corpusCasualMarkerMedian,
            corpusCasualMarkerSD: corpusCasualMarkerSD,
            corpusSignatureMatchMedian: corpusSignatureMatchMedian,
            corpusSignatureMatchSD: corpusSignatureMatchSD,
            corpusWordCountInRangeMedian: corpusWordCountInRangeMedian,
            corpusWordCountInRangeSD: corpusWordCountInRangeSD,
            corpusTypeMatchMedian: corpusTypeMatchMedian,
            corpusTypeMatchSD: corpusTypeMatchSD,
            corpusAlternationMedian: corpusAlternationMedian,
            corpusTrigramOverlapMedian: corpusTrigramOverlapMedian,
            corpusTrigramOverlapSD: corpusTrigramOverlapSD,
            corpusOpenerSigOverlapMedian: corpusOpenerSigOverlapMedian,
            corpusOpenerSigOverlapSD: corpusOpenerSigOverlapSD,
            corpusCloserSigOverlapMedian: corpusCloserSigOverlapMedian,
            corpusCloserSigOverlapSD: corpusCloserSigOverlapSD,
            corpusRawSignatureMatchMedian: corpusRawSignatureMatchMedian,
            corpusRawSignatureMatchSD: corpusRawSignatureMatchSD,
            corpusRawBigramMatchRate: corpusRawBigramMatchRate,
            corpusRawBigramRateSD: corpusRawBigramRateSD,
            rawSlotDistributionByMove: rawSlotDistributionByMove,
            rawBigramDistributionByMove: rawBigramDistributionByMove,
            rawOpenerDistributionByMove: rawOpenerDistributionByMove,
            corpusSlotDistCosinMedian: corpusSlotDistCosinMedian,
            corpusSlotDistCosinSD: corpusSlotDistCosinSD,
            corpusBigramDistCosinMedian: corpusBigramDistCosinMedian,
            corpusBigramDistCosinSD: corpusBigramDistCosinSD,
            rolledSlotSignaturesByMove: rolledSlotSignaturesByMove,
            rolledOpenerSlotSignaturesByMove: rolledOpenerSlotSignaturesByMove,
            rolledCloserSlotSignaturesByMove: rolledCloserSlotSignaturesByMove,
            rolledSlotBigramsByMove: rolledSlotBigramsByMove,
            rolledOpenerSigFreqByMove: rolledOpenerSigFreqByMove,
            rolledCloserSigFreqByMove: rolledCloserSigFreqByMove,
            shortSentenceMax: shortSentenceMax,
            longSentenceMin: longSentenceMin,
            cadenceTransitionMatrix: cadenceTransitionMatrix,
            rangeDistributions: rangeDistributions
        )
    }

    // MARK: - Text Parsing

    /// Parse a full script into sections (split on double newlines or section markers).
    static func parseScript(_ text: String, moveType: String? = nil) -> [ParsedSection] {
        // Split on double newlines (paragraph boundaries)
        let rawSections = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawSections.isEmpty else {
            return [parseSection(text: text, index: 0, moveType: moveType)]
        }

        return rawSections.enumerated().map { (i, sectionText) in
            parseSection(text: sectionText, index: i, moveType: moveType)
        }
    }

    static func parseSection(text: String, index: Int, moveType: String?) -> ParsedSection {
        let sentenceTexts = SentenceParser.parse(text)
        let sentences = sentenceTexts.enumerated().map { (i, sentText) in
            parseSentence(text: sentText, index: i)
        }
        return ParsedSection(index: index, rawText: text, sentences: sentences, moveType: moveType)
    }

    static func parseSentence(text: String, index: Int) -> ParsedSentence {
        let words = text.split(separator: " ").map(String.init)
        let lowered = text.lowercased()

        let firstPersonWords: Set<String> = ["i", "me", "my", "mine", "myself", "we", "us", "our", "ours", "ourselves"]
        let secondPersonWords: Set<String> = ["you", "your", "yours", "yourself", "yourselves"]

        let wordLower = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let fpCount = wordLower.filter { firstPersonWords.contains($0) }.count
        let spCount = wordLower.filter { secondPersonWords.contains($0) }.count

        // Contraction detection
        let contractionPattern = #"(?i)\b\w+(?:'|')\w+\b"#
        let contractionCount: Int
        if let regex = try? NSRegularExpression(pattern: contractionPattern) {
            contractionCount = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        } else {
            contractionCount = 0
        }

        let isQuestion = text.trimmingCharacters(in: .whitespaces).hasSuffix("?")
        let isFragment: Bool = {
            if isQuestion { return false }
            if words.count >= 8 { return false }
            if words.count <= 2 { return true }
            if words.count < 5 {
                // Check for verb presence — fragments lack a main verb
                let commonVerbs: Set<String> = [
                    "is", "are", "was", "were", "am", "be", "been",
                    "has", "have", "had", "do", "does", "did",
                    "can", "could", "will", "would", "shall", "should", "may", "might", "must",
                    "get", "got", "go", "goes", "went", "come", "came", "make", "made",
                    "take", "took", "run", "ran", "see", "saw", "say", "said",
                    "know", "knew", "think", "thought", "tell", "told", "find", "found",
                    "want", "need", "let", "put", "keep", "kept"
                ]
                let hasVerb = wordLower.contains { commonVerbs.contains($0) }
                let hasVerbEnding = wordLower.contains { $0.hasSuffix("ed") || $0.hasSuffix("ing") }
                return !hasVerb && !hasVerbEnding
            }
            return false
        }()
        let hasDA = wordLower.contains("you") || wordLower.contains("your")

        let firstWord = wordLower.first ?? ""

        // Build trigrams
        var trigrams: [String] = []
        if wordLower.count >= 3 {
            for i in 0..<(wordLower.count - 2) {
                trigrams.append("\(wordLower[i]) \(wordLower[i+1]) \(wordLower[i+2])")
            }
        }

        // Deterministic hints (matching DonorLibraryA2Service.SentenceHints)
        var hints = Set<String>()
        if wordLower.contains(where: { Int($0) != nil }) || lowered.contains(where: \.isNumber) {
            hints.insert("hasNumber")
        }
        if isQuestion { hints.insert("endsWithQuestion") }

        let contrastMarkers: Set<String> = ["but", "however", "yet", "actually", "instead", "although", "though", "nevertheless"]
        if wordLower.contains(where: { contrastMarkers.contains($0) }) {
            hints.insert("hasContrastMarker")
        }

        let temporalPatterns = ["ago", "last year", "last month", "per week", "per year", "century", "decade"]
        if temporalPatterns.contains(where: { lowered.contains($0) }) || lowered.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil {
            hints.insert("hasTemporalMarker")
        }

        if fpCount > 0 { hints.insert("hasFirstPerson") }
        if spCount > 0 { hints.insert("hasSecondPerson") }

        let reactionWords: Set<String> = ["oh", "wow", "yeah", "right", "man", "look"]
        if words.count <= 3 && wordLower.contains(where: { reactionWords.contains($0) }) {
            hints.insert("isReactionBeat")
        }

        let deicticWords: Set<String> = ["this", "that", "these", "those", "here"]
        if wordLower.prefix(2).contains(where: { deicticWords.contains($0) }) {
            hints.insert("isVisualAnchor")
        }

        return ParsedSentence(
            index: index,
            text: text,
            words: words,
            wordCount: words.count,
            isQuestion: isQuestion,
            isFragment: isFragment,
            hasDirectAddress: hasDA,
            firstWord: firstWord,
            firstPersonCount: fpCount,
            secondPersonCount: spCount,
            contractionCount: contractionCount,
            trigrams: trigrams,
            deterministicHints: hints
        )
    }

    // MARK: - Measurement Helpers

    private static func measureMetric(
        _ metric: HardFailMetric,
        section: ParsedSection,
        corpusStats: CorpusStats
    ) -> (actual: Double, corpus: Double) {
        let totalSentences = Double(max(section.sentences.count, 1))

        switch metric {
        case .firstPersonRate:
            let actual = section.sentences.map { Double($0.firstPersonCount) }.reduce(0, +) / totalSentences
            return (actual, corpusStats.firstPersonRate)

        case .secondPersonRate:
            let actual = section.sentences.map { Double($0.secondPersonCount) }.reduce(0, +) / totalSentences
            return (actual, corpusStats.secondPersonRate)

        case .contractionRate:
            let actual = section.sentences.map { Double($0.contractionCount) }.reduce(0, +) / totalSentences
            return (actual, corpusStats.contractionRate)

        case .sentenceCount:
            let expected = corpusStats.sentencesPerMove[section.moveType ?? ""] ?? 5.0
            return (Double(section.sentenceCount), expected)

        case .avgSentenceLength:
            return (section.avgSentenceLength, corpusStats.avgSentenceLength)

        case .questionDensity:
            let actual = Double(section.sentences.filter(\.isQuestion).count) / totalSentences
            return (actual, corpusStats.questionRate)

        case .fragmentRate:
            let actual = Double(section.sentences.filter(\.isFragment).count) / totalSentences
            return (actual, corpusStats.fragmentRate)

        case .wordCount:
            let expected = corpusStats.wordCountPerMove[section.moveType ?? ""] ?? corpusStats.avgWordCountPerSection
            return (Double(section.wordCount), expected)

        case .maxConsecutiveSameOpener:
            let openers = section.sentences.map(\.firstWord)
            var maxRun = 0
            var currentRun = 1
            for i in 1..<openers.count {
                if openers[i] == openers[i - 1] {
                    currentRun += 1
                    maxRun = max(maxRun, currentRun)
                } else {
                    currentRun = 1
                }
            }
            maxRun = max(maxRun, currentRun)
            return (Double(maxRun), 2.0)

        case .uniqueOpenerRatio:
            let openers = section.sentences.map(\.firstWord)
            let ratio = openers.isEmpty ? 1.0 : Double(Set(openers).count) / Double(openers.count)
            return (ratio, corpusStats.uniqueOpenerRatio)
        }
    }

    // MARK: - Scoring Utilities

    /// PROXIMITY-scored: how close `actual` is to `corpus` median. Returns 0-100.
    /// tolerance controls how wide the "acceptable" band is.
    /// Use for similarity metrics where closeness to the median IS the goal.
    private static func proximityScore(actual: Double, corpus: Double, tolerance: Double) -> Double {
        guard tolerance > 0 else { return actual == corpus ? 100.0 : 0.0 }
        let distance = abs(actual - corpus)
        let normalized = distance / tolerance
        // 0 → 100, 1 tolerance → 50, 2 → 0
        return max(0.0, min(100.0, 100.0 - normalized * 50.0))
    }

    /// Cosine similarity between two sparse frequency distributions keyed by slot type.
    /// Returns 0.0-1.0 where 1.0 = identical distribution shape.
    private static func cosineSimilarity(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let allKeys = Set(a.keys).union(b.keys)
        var dot = 0.0, normA = 0.0, normB = 0.0
        for key in allKeys {
            let aVal = a[key] ?? 0.0
            let bVal = b[key] ?? 0.0
            dot += aVal * bVal
            normA += aVal * aVal
            normB += bVal * bVal
        }
        guard normA > 0, normB > 0 else { return 0.0 }
        return dot / (sqrt(normA) * sqrt(normB))
    }

    /// RANGE-scored: is `actual` within the corpus distribution? Returns 0-100.
    /// 100 if within IQR, degrades toward corpus extremes, 0 beyond min/max + IQR buffer.
    /// Use for authenticity metrics ("within creator's observed range" not "close to median").
    private static func rangeScore(actual: Double, range: MetricRange) -> Double {
        let p25 = range.p25
        let p75 = range.p75
        let cMin = range.min
        let cMax = range.max

        // Within IQR → full score
        if actual >= p25 && actual <= p75 { return 100.0 }

        // Between min and P25 → 50-100
        if actual >= cMin && actual < p25 {
            guard p25 > cMin else { return 100.0 }
            return 50.0 + 50.0 * (actual - cMin) / (p25 - cMin)
        }

        // Between P75 and max → 50-100
        if actual > p75 && actual <= cMax {
            guard cMax > p75 else { return 100.0 }
            return 50.0 + 50.0 * (cMax - actual) / (cMax - p75)
        }

        // Beyond corpus range: degrade with IQR-width buffer
        let buffer = max(range.iqr, 0.01)
        if actual < cMin {
            return max(0.0, 50.0 * (1.0 - (cMin - actual) / buffer))
        }
        // actual > cMax
        return max(0.0, 50.0 * (1.0 - (actual - cMax) / buffer))
    }

    /// Compute median of a pre-sorted array.
    private static func median(of sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let n = sorted.count
        return n % 2 == 0 ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0 : sorted[n / 2]
    }

    /// Compute 25th percentile of a pre-sorted array (linear interpolation).
    private static func percentile25(of sorted: [Double]) -> Double {
        guard sorted.count >= 2 else { return sorted.first ?? 0 }
        let idx = Double(sorted.count - 1) * 0.25
        let lower = Int(idx)
        let frac = idx - Double(lower)
        return sorted[lower] + frac * (sorted[min(lower + 1, sorted.count - 1)] - sorted[lower])
    }

    /// Compute 75th percentile of a pre-sorted array (linear interpolation).
    private static func percentile75(of sorted: [Double]) -> Double {
        guard sorted.count >= 2 else { return sorted.first ?? 0 }
        let idx = Double(sorted.count - 1) * 0.75
        let lower = Int(idx)
        let frac = idx - Double(lower)
        return sorted[lower] + frac * (sorted[min(lower + 1, sorted.count - 1)] - sorted[lower])
    }

    /// Compute variance of a double array.
    private static func variance(of values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquares = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        return sumSquares / Double(values.count - 1)
    }

    /// Compute standard deviation of a double array.
    private static func standardDeviation(of values: [Double]) -> Double {
        sqrt(variance(of: values))
    }

    /// Compute percentile-based range from a score array.
    private static func computeRange(from scores: [Double]) -> DimensionRange {
        let sorted = scores.sorted()
        guard !sorted.isEmpty else {
            return DimensionRange(min: 0, p25: 0, median: 0, p75: 0, max: 0, sampleCount: 0)
        }
        let n = sorted.count
        return DimensionRange(
            min: sorted.first!,
            p25: sorted[max(0, n / 4)],
            median: sorted[n / 2],
            p75: sorted[max(0, (3 * n) / 4)],
            max: sorted.last!,
            sampleCount: n
        )
    }

    /// Score opener word distribution match using simplified chi-squared.
    private static func scoreOpenerDistribution(section: ParsedSection, corpusStats: CorpusStats) -> (score: Double, rawOverlapRate: Double, tolerance: Double) {
        guard !section.sentences.isEmpty else { return (50.0, 0.0, 0.0) }

        // Overlap rate: fraction of the section's distinct openers in the corpus opener set
        let genOpeners = Set(section.sentences.map(\.firstWord))
        let corpusOpeners = Set(corpusStats.openerDistribution.filter { $0.value > 0.01 }.keys)
        guard !genOpeners.isEmpty else { return (50.0, 0.0, 0.0) }

        let overlapCount = genOpeners.filter { corpusOpeners.contains($0) }.count
        let overlapRate = Double(overlapCount) / Double(genOpeners.count)

        // Corpus-derived fixed tolerance: SD of overlap rates across all ~77 corpus sections.
        // Same tolerance for every section regardless of size.
        let tol = max(corpusStats.corpusOpenerOverlapSD, 0.1)
        let score = proximityScore(actual: overlapRate, corpus: corpusStats.corpusOpenerOverlapMedian, tolerance: tol)
        return (score, overlapRate, tol)
    }

    /// Count how many of the creator's known casual markers appear in the section.
    private static func countCasualMarkers(section: ParsedSection, markers: Set<String>) -> Int {
        let fullText = section.rawText.lowercased()
        return markers.filter { fullText.contains($0.lowercased()) }.count
    }

    /// Score long-short sentence alternation pattern.
    /// RANGE-scored: within creator's observed alternation distribution
    private static func scoreAlternation(section: ParsedSection, corpusStats: CorpusStats) -> (score: Double, rawRate: Double, tolerance: Double) {
        let lengths = section.sentences.map(\.wordCount)
        guard lengths.count >= 3 else { return (60.0, 0.5, 0.0) }

        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        var alternations = 0
        for i in 1..<lengths.count {
            let prevAbove = Double(lengths[i - 1]) > mean
            let currAbove = Double(lengths[i]) > mean
            if prevAbove != currAbove { alternations += 1 }
        }
        let maxAlternations = lengths.count - 1
        let rate = Double(alternations) / Double(maxAlternations)

        let score: Double
        let tol: Double
        if let altRange = corpusStats.metricRange("alternation") {
            score = rangeScore(actual: rate, range: altRange)
            tol = altRange.iqr
        } else {
            tol = max(corpusStats.corpusAlternationSD, 0.1)
            score = proximityScore(actual: rate, corpus: corpusStats.corpusAlternationMedian, tolerance: tol)
        }
        return (score, rate, tol)
    }

    /// Map sentence index to section position label matching RhythmTemplate.
    private static func sectionPosition(index: Int, total: Int) -> String {
        if index == 0 { return "opening" }
        if index == total - 1 { return "closing" }
        return "mid"
    }

    /// Extract a deterministic slot signature from a parsed sentence using hint-based heuristics.
    static func extractSlotSignature(from sentence: ParsedSentence) -> String {
        var slots: [String] = []

        if sentence.deterministicHints.contains("hasTemporalMarker") {
            slots.append("temporal_marker")
        }
        if sentence.deterministicHints.contains("hasNumber") {
            slots.append("quantitative_claim")
        }
        if sentence.deterministicHints.contains("hasContrastMarker") {
            slots.append("contradiction")
        }
        if sentence.deterministicHints.contains("hasSecondPerson") {
            slots.append("direct_address")
        }
        if sentence.deterministicHints.contains("isReactionBeat") {
            slots.append("reaction_beat")
        }
        if sentence.deterministicHints.contains("isVisualAnchor") {
            slots.append("visual_anchor")
        }
        if sentence.deterministicHints.contains("hasFirstPerson") && !slots.contains("direct_address") {
            slots.append("narrative_action")
        }

        if slots.isEmpty {
            // Default classification based on sentence structure
            if sentence.isQuestion { slots.append("rhetorical_question") }
            else if sentence.isFragment { slots.append("empty_connector") }
            else { slots.append("factual_relay") }
        }

        return slots.joined(separator: "|")
    }

    // MARK: - Slot Debugger

    /// Build detailed debug data for both Slots (D4) and S2 dimensions.
    /// Shows per-sentence hints, signatures, match status, bigrams, and score arithmetic.
    static func buildSlotDebugData(
        section: ParsedSection,
        corpusStats: CorpusStats,
        s2Signatures: [String]?,
        bundle: StructuredInputBundle? = nil,
        topicText: String? = nil
    ) -> SlotDebugData {
        let moveKey = section.moveType ?? ""

        // Corpus sets
        let corpusRolledSigSet = corpusStats.rolledSlotSignatures(forMove: moveKey)
        let corpusRawSigSet = corpusStats.slotSignatures(forMove: moveKey)
        let corpusRolledOpenerSet = corpusStats.rolledOpenerSlotSignatures(forMove: moveKey)
        let corpusRawOpenerSet = corpusStats.openerSlotSignatures(forMove: moveKey)
        let corpusRolledBigramSet = corpusStats.rolledSlotBigrams(forMove: moveKey)
        let corpusRawBigramSet = corpusStats.slotBigrams(forMove: moveKey)

        // Corpus frequency counts (from raw arrays)
        let rolledSigCounts = frequencyCounts(corpusStats.rolledSlotSignaturesByMove[moveKey] ?? [])
        let rawSigCounts = frequencyCounts(corpusStats.slotSignaturesByMove[moveKey] ?? [])
        let rolledBigramCounts = frequencyCounts(corpusStats.rolledSlotBigramsByMove[moveKey] ?? [])
        let rawBigramCounts = frequencyCounts(corpusStats.slotBigramsByMove[moveKey] ?? [])

        // Determine S2 source
        let hasLLM = s2Signatures != nil && !(s2Signatures?.isEmpty ?? true)
        let s2Source = hasLLM ? "LLM" : "hint"

        // Per-sentence analysis
        var sentenceDebugs: [SlotDebugData.SentenceSlotDebug] = []
        for (idx, sent) in section.sentences.enumerated() {
            let heuristicSig = extractSlotSignature(from: sent)
            let rolledSig = SignatureRollupService.rollupDominantSlot(heuristicSig)
            let d4Matched = corpusRolledSigSet.contains(rolledSig)

            let s2Sig: String
            if let s2 = s2Signatures, idx < s2.count {
                s2Sig = s2[idx]
            } else {
                s2Sig = heuristicSig
            }
            let s2Matched = corpusRawSigSet.contains(s2Sig)

            let hints = Array(sent.deterministicHints).sorted()

            // Prompt spec from bundle (if structured method)
            let targetSig: String? = bundle.flatMap { b in
                idx < b.targetSignatureSequence.count ? b.targetSignatureSequence[idx] : nil
            }
            let sentCount = bundle?.targetSentenceCount ?? 0
            let posLabel = idx == 0 ? "opening" : (idx == sentCount - 1 ? "closing" : "mid")
            let rhythm = bundle?.rhythmTemplates.first { $0.positionInSection == posLabel }
            let targetWordRange: String? = rhythm.map { "\($0.wordCountMin)-\($0.wordCountMax)" }
            let targetSentenceType: String? = rhythm?.sentenceType
            let targetTopic: String? = topicText

            sentenceDebugs.append(.init(
                id: idx,
                text: sent.text,
                wordCount: sent.wordCount,
                hints: hints,
                heuristicSig: heuristicSig,
                rolledSig: rolledSig,
                d4Matched: d4Matched,
                s2Source: s2Source,
                s2Sig: s2Sig,
                s2Matched: s2Matched,
                targetSig: targetSig,
                targetWordRange: targetWordRange,
                targetSentenceType: targetSentenceType,
                targetTopic: targetTopic
            ))
        }

        // Bigram analysis (D4 rolled)
        let rolledSigs = sentenceDebugs.map(\.rolledSig)
        var d4Bigrams: [SlotDebugData.BigramDebug] = []
        for i in 0..<max(0, rolledSigs.count - 1) {
            let bg = "\(rolledSigs[i])→\(rolledSigs[i + 1])"
            d4Bigrams.append(.init(from: rolledSigs[i], to: rolledSigs[i + 1], matched: corpusRolledBigramSet.contains(bg)))
        }

        // Bigram analysis (S2 raw)
        let s2Sigs = sentenceDebugs.map(\.s2Sig)
        var s2Bigrams: [SlotDebugData.BigramDebug] = []
        for i in 0..<max(0, s2Sigs.count - 1) {
            let bg = "\(s2Sigs[i])→\(s2Sigs[i + 1])"
            s2Bigrams.append(.init(from: s2Sigs[i], to: s2Sigs[i + 1], matched: corpusRawBigramSet.contains(bg)))
        }

        // D4 score arithmetic
        let d4MatchCount = sentenceDebugs.filter(\.d4Matched).count
        let d4MatchRate = sentenceDebugs.isEmpty ? 0.0 : Double(d4MatchCount) / Double(sentenceDebugs.count)
        let d4OpenerMatched = rolledSigs.first.map { corpusRolledOpenerSet.contains($0) } ?? false
        let d4BigramHits = d4Bigrams.filter(\.matched).count
        let d4BigramRate = d4Bigrams.isEmpty ? 0.0 : Double(d4BigramHits) / Double(d4Bigrams.count)
        let d4MatchTol = max(corpusStats.corpusSignatureMatchSD, 0.1)
        let d4MatchScore = proximityScore(actual: d4MatchRate, corpus: corpusStats.corpusSignatureMatchMedian, tolerance: d4MatchTol)
        let d4OpenerScore = d4OpenerMatched ? 100.0 : 0.0
        let d4BigramTol = max(corpusStats.corpusBigramRateSD, 0.1)
        let d4BigramScore = proximityScore(actual: d4BigramRate, corpus: corpusStats.corpusBigramMatchRate, tolerance: d4BigramTol)
        let d4Avg = (d4MatchScore + d4OpenerScore + d4BigramScore) / 3.0

        let d4Explanation = """
        D4 Slots = \(String(format: "%.0f", d4Avg))
          Sig match:   \(d4MatchCount)/\(sentenceDebugs.count) rolled sigs matched (\(String(format: "%.2f", d4MatchRate))) vs corpus median \(String(format: "%.2f", corpusStats.corpusSignatureMatchMedian)) tol=\(String(format: "%.2f", d4MatchTol)) → \(String(format: "%.0f", d4MatchScore))
          Opener:      "\(rolledSigs.first ?? "?")" \(d4OpenerMatched ? "IN" : "NOT in") corpus openers → \(String(format: "%.0f", d4OpenerScore))
          Bigram rate: \(d4BigramHits)/\(d4Bigrams.count) = \(String(format: "%.2f", d4BigramRate)) vs corpus \(String(format: "%.2f", corpusStats.corpusBigramMatchRate)) tol=\(String(format: "%.2f", d4BigramTol)) → \(String(format: "%.0f", d4BigramScore))
          Average: (\(String(format: "%.0f", d4MatchScore)) + \(String(format: "%.0f", d4OpenerScore)) + \(String(format: "%.0f", d4BigramScore))) / 3 = \(String(format: "%.0f", d4Avg))
        """

        // S2 score arithmetic — distribution-based (cosine similarity)
        let s2CorpusDist = corpusStats.rawSlotDistribution(forMove: moveKey)
        var s2GenSlotCounts: [String: Int] = [:]
        for s in sentenceDebugs { s2GenSlotCounts[s.s2Sig, default: 0] += 1 }
        let s2GenTotal = Double(s2GenSlotCounts.values.reduce(0, +))
        let s2GenDist = s2GenTotal > 0 ? s2GenSlotCounts.mapValues { Double($0) / s2GenTotal } : [:]
        let s2SlotCosin = cosineSimilarity(s2GenDist, s2CorpusDist)
        let s2SlotDistTol = max(corpusStats.corpusSlotDistCosinSD, 0.05)
        let s2SlotDistScore = proximityScore(actual: s2SlotCosin, corpus: corpusStats.corpusSlotDistCosinMedian, tolerance: s2SlotDistTol)

        let s2OpenerDist = corpusStats.rawOpenerDistribution(forMove: moveKey)
        let s2OpenerFreq = s2OpenerDist[s2Sigs.first ?? ""] ?? 0.0
        let s2OpenerScore = s2OpenerFreq * 100.0

        var s2BigramCosin = 0.0
        var s2BigramDistTol = 0.05
        var s2BigramDistScore = 0.0
        if s2Sigs.count > 1 {
            var s2GenBigramCounts: [String: Int] = [:]
            for i in 0..<(s2Sigs.count - 1) {
                s2GenBigramCounts["\(s2Sigs[i])→\(s2Sigs[i + 1])", default: 0] += 1
            }
            let bigramTotal = Double(s2GenBigramCounts.values.reduce(0, +))
            let genBigramDist = bigramTotal > 0 ? s2GenBigramCounts.mapValues { Double($0) / bigramTotal } : [:]
            let corpusBigramDist = corpusStats.rawBigramDistribution(forMove: moveKey)
            s2BigramCosin = cosineSimilarity(genBigramDist, corpusBigramDist)
            s2BigramDistTol = max(corpusStats.corpusBigramDistCosinSD, 0.05)
            s2BigramDistScore = proximityScore(actual: s2BigramCosin, corpus: corpusStats.corpusBigramDistCosinMedian, tolerance: s2BigramDistTol)
        }

        let s2Avg = (s2SlotDistScore + s2OpenerScore + s2BigramDistScore) / 3.0

        // Old membership counts kept for reference
        let s2OldMatchCount = sentenceDebugs.filter(\.s2Matched).count
        let s2OldBigramHits = s2Bigrams.filter(\.matched).count

        // Build distribution display strings
        let corpusDistSorted = s2CorpusDist.sorted { $0.value > $1.value }
        let genDistSorted = s2GenDist.sorted { $0.value > $1.value }
        let corpusDistStr = corpusDistSorted.prefix(6).map { "\($0.key)(\(String(format: "%.2f", $0.value)))" }.joined(separator: " ")
        let genDistStr = genDistSorted.prefix(6).map { "\($0.key)(\(String(format: "%.2f", $0.value)))" }.joined(separator: " ")

        let s2Explanation = """
        S2 = \(String(format: "%.0f", s2Avg)) [\(s2Source)]
          Slot dist cosine:   \(String(format: "%.3f", s2SlotCosin)) vs corpus median \(String(format: "%.3f", corpusStats.corpusSlotDistCosinMedian)) tol=\(String(format: "%.3f", s2SlotDistTol)) → \(String(format: "%.0f", s2SlotDistScore))
          Opener freq:        "\(s2Sigs.first ?? "?")" = \(String(format: "%.2f", s2OpenerFreq)) of corpus openers → \(String(format: "%.0f", s2OpenerScore))
          Bigram dist cosine: \(String(format: "%.3f", s2BigramCosin)) vs corpus median \(String(format: "%.3f", corpusStats.corpusBigramDistCosinMedian)) tol=\(String(format: "%.3f", s2BigramDistTol)) → \(String(format: "%.0f", s2BigramDistScore))
          Average: (\(String(format: "%.0f", s2SlotDistScore)) + \(String(format: "%.0f", s2OpenerScore)) + \(String(format: "%.0f", s2BigramDistScore))) / 3 = \(String(format: "%.0f", s2Avg))

          CORPUS DISTRIBUTION (\(moveKey)):
            \(corpusDistSorted.map { "  \($0.key.padding(toLength: 22, withPad: " ", startingAt: 0)) \(String(format: "%.3f", $0.value))  \(String(repeating: "\u{2588}", count: max(1, Int($0.value * 40))))" }.joined(separator: "\n    "))

          GENERATED DISTRIBUTION:
            \(genDistSorted.map { "  \($0.key.padding(toLength: 22, withPad: " ", startingAt: 0)) \(String(format: "%.3f", $0.value))  \(String(repeating: "\u{2588}", count: max(1, Int($0.value * 40))))" }.joined(separator: "\n    "))

          (Old membership: \(s2OldMatchCount)/\(sentenceDebugs.count) raw sigs matched, \(s2OldBigramHits)/\(s2Bigrams.count) bigrams matched)
        """

        // S2 distribution data for SlotDebugData
        let corpusSlotDistForDebug = corpusDistSorted.map { (sig: $0.key, fraction: $0.value) }
        let genSlotDistForDebug = genDistSorted.map { (sig: $0.key, fraction: $0.value) }

        return SlotDebugData(
            sentences: sentenceDebugs,
            d4Bigrams: d4Bigrams,
            s2Bigrams: s2Bigrams,
            corpusRolledSigs: rolledSigCounts.sorted { $0.count > $1.count },
            corpusRawSigs: rawSigCounts.sorted { $0.count > $1.count },
            corpusRolledOpeners: Array(corpusRolledOpenerSet).sorted(),
            corpusRawOpeners: Array(corpusRawOpenerSet).sorted(),
            corpusRolledBigrams: rolledBigramCounts.sorted { $0.count > $1.count }.prefix(15).map { $0 },
            corpusRawBigrams: rawBigramCounts.sorted { $0.count > $1.count }.prefix(15).map { $0 },
            d4ScoreExplanation: d4Explanation,
            s2ScoreExplanation: s2Explanation,
            corpusSlotDistribution: corpusSlotDistForDebug,
            generatedSlotDistribution: genSlotDistForDebug,
            slotDistCosine: s2SlotCosin,
            bigramDistCosine: s2BigramCosin,
            openerSlotFrequency: s2OpenerFreq
        )
    }

    private static func frequencyCounts(_ items: [String]) -> [(sig: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts.map { (sig: $0.key, count: $0.value) }
    }

    // MARK: - Debug Report Builders

    /// Dump all corpus stats in a copyable text format.
    static func buildCorpusStatsReport(_ stats: CorpusStats) -> String {
        var lines: [String] = []

        lines.append("═══ CORPUS STATS: \(stats.creatorId) ═══")
        lines.append("")

        // Sentence aggregates
        lines.append("SENTENCE AGGREGATES")
        lines.append("  Avg Sentence Length:    \(String(format: "%.1f", stats.avgSentenceLength)) words")
        lines.append("  Length Variance:        \(String(format: "%.1f", stats.sentenceLengthVariance))")
        lines.append("  Avg Clause Count:       \(String(format: "%.1f", stats.avgClauseCount))")
        lines.append("  Question Rate:          \(String(format: "%.3f", stats.questionRate)) (\(String(format: "%.1f", stats.questionRate * 100))%)")
        lines.append("  Fragment Rate:          \(String(format: "%.3f", stats.fragmentRate)) (\(String(format: "%.1f", stats.fragmentRate * 100))%)")
        lines.append("")

        // Word frequency rates
        lines.append("WORD FREQUENCY RATES (per sentence)")
        lines.append("  First-Person:     \(String(format: "%.3f", stats.firstPersonRate))")
        lines.append("  Second-Person:    \(String(format: "%.3f", stats.secondPersonRate))")
        lines.append("  Contraction:      \(String(format: "%.3f", stats.contractionRate))")
        lines.append("  Direct Address:   \(String(format: "%.3f", stats.directAddressRate)) (\(String(format: "%.1f", stats.directAddressRate * 100))%)")
        lines.append("  Unique Opener Ratio: \(String(format: "%.3f", stats.uniqueOpenerRatio))")
        lines.append("")

        // Opener distribution (top 20)
        let sortedOpeners = stats.openerDistribution.sorted { $0.value > $1.value }
        let topCount = min(20, sortedOpeners.count)
        lines.append("TOP OPENERS (\(topCount) of \(sortedOpeners.count))")
        for opener in sortedOpeners.prefix(topCount) {
            let barLen = Int(opener.value * 50)
            let bar = String(repeating: "\u{2588}", count: max(1, barLen))
            lines.append("  \(opener.key.padding(toLength: 14, withPad: " ", startingAt: 0)) \(String(format: "%.3f", opener.value))  \(bar)")
        }
        lines.append("")

        // Per-move stats
        let moveTypes = Set(Array(stats.sentencesPerMove.keys) + Array(stats.wordCountPerMove.keys)).sorted()
        if !moveTypes.isEmpty {
            lines.append("PER-MOVE STATS")
            lines.append("  \("Move Type".padding(toLength: 28, withPad: " ", startingAt: 0)) \("Sentences".padding(toLength: 12, withPad: " ", startingAt: 0)) Avg Words")
            for move in moveTypes {
                let sentCount = stats.sentencesPerMove[move] ?? 0
                let wordCount = stats.wordCountPerMove[move] ?? 0
                lines.append("  \(move.padding(toLength: 28, withPad: " ", startingAt: 0)) \(String(format: "%-12.1f", sentCount)) \(String(format: "%.1f", wordCount))")
            }
            lines.append("  Avg Words Per Section: \(String(format: "%.1f", stats.avgWordCountPerSection))")
            lines.append("")
        }

        // Distribution quartiles (IQR tolerances)
        lines.append("DISTRIBUTION QUARTILES (for scorer tolerances)")
        lines.append("  Sentence Count:  P25=\(String(format: "%.1f", stats.sentenceCountP25))  P75=\(String(format: "%.1f", stats.sentenceCountP75))  IQR=\(String(format: "%.1f", stats.sentenceCountIQR))")
        lines.append("  Word Count/Sec:  P25=\(String(format: "%.1f", stats.wordCountPerSectionP25))  P75=\(String(format: "%.1f", stats.wordCountPerSectionP75))  IQR=\(String(format: "%.1f", stats.wordCountIQR))")
        lines.append("  Length Variance: P25=\(String(format: "%.1f", stats.lengthVarianceP25))  P75=\(String(format: "%.1f", stats.lengthVarianceP75))  IQR=\(String(format: "%.1f", stats.lengthVarianceIQR))")
        lines.append("  Corpus Bigram Match Rate: \(String(format: "%.3f", stats.corpusBigramMatchRate))")
        lines.append("")

        // Sentence length tertile boundaries
        lines.append("SENTENCE LENGTH BUCKETS")
        lines.append("  Short: \u{2264}\(stats.shortSentenceMax) words  |  Long: \u{2265}\(stats.longSentenceMin) words")
        if let sRange = stats.metricRange("shortPct"), let mRange = stats.metricRange("mediumPct"), let lRange = stats.metricRange("longPct") {
            lines.append("  Short%:  P25=\(String(format: "%.1f%%", sRange.p25 * 100))  P75=\(String(format: "%.1f%%", sRange.p75 * 100))  range=[\(String(format: "%.1f", sRange.min * 100))-\(String(format: "%.1f", sRange.max * 100))%]")
            lines.append("  Medium%: P25=\(String(format: "%.1f%%", mRange.p25 * 100))  P75=\(String(format: "%.1f%%", mRange.p75 * 100))  range=[\(String(format: "%.1f", mRange.min * 100))-\(String(format: "%.1f", mRange.max * 100))%]")
            lines.append("  Long%:   P25=\(String(format: "%.1f%%", lRange.p25 * 100))  P75=\(String(format: "%.1f%%", lRange.p75 * 100))  range=[\(String(format: "%.1f", lRange.min * 100))-\(String(format: "%.1f", lRange.max * 100))%]")
        }
        lines.append("")

        // Cadence transition matrix
        if !stats.cadenceTransitionMatrix.isEmpty {
            lines.append("CADENCE TRANSITION MATRIX")
            for from in ["short", "medium", "long"] {
                var row: [String] = []
                for to in ["short", "medium", "long"] {
                    let prob = stats.cadenceTransitionMatrix["\(from)→\(to)"] ?? 0.0
                    row.append("\(to)=\(String(format: "%.0f%%", prob * 100))")
                }
                lines.append("  \(from.padding(toLength: 8, withPad: " ", startingAt: 0)) → \(row.joined(separator: "  "))")
            }
            if let cfRange = stats.metricRange("cadenceFit") {
                lines.append("  Cadence Fit: P25=\(String(format: "%.3f", cfRange.p25))  P75=\(String(format: "%.3f", cfRange.p75))  range=[\(String(format: "%.3f", cfRange.min))-\(String(format: "%.3f", cfRange.max))]")
            }
            lines.append("")
        }

        // Sub-metric SD tolerances (precomputed from ~77 sections)
        lines.append("SUB-METRIC SD TOLERANCES (precomputed from ~77 sections)")
        lines.append("  D1 Avg Sentence Length SD: \(String(format: "%.3f", stats.corpusAvgSentenceLengthSD))")
        lines.append("  D1 Question Density SD:    \(String(format: "%.3f", stats.corpusQuestionDensitySD))")
        lines.append("  D1 Fragment Rate SD:       \(String(format: "%.3f", stats.corpusFragmentRateSD))")
        lines.append("  D2 First-Person Rate SD:   \(String(format: "%.3f", stats.corpusFirstPersonRateSD))")
        lines.append("  D2 Contraction Rate SD:    \(String(format: "%.3f", stats.corpusContractionRateSD))")
        lines.append("  D2 Direct Address Rate SD: \(String(format: "%.3f", stats.corpusDirectAddressRateSD))")
        lines.append("  D2 Opener Overlap:         median=\(String(format: "%.3f", stats.corpusOpenerOverlapMedian))  SD=\(String(format: "%.3f", stats.corpusOpenerOverlapSD))")
        lines.append("  D4 Bigram Rate SD:         \(String(format: "%.3f", stats.corpusBigramRateSD))")
        lines.append("  D5 Alternation Rate SD:    \(String(format: "%.3f", stats.corpusAlternationSD))")
        lines.append("  D6 Word Count SD:          \(String(format: "%.1f", stats.corpusWordCountSD))")
        lines.append("  D6 Vocabulary Density SD:  \(String(format: "%.3f", stats.corpusVocabularyDensitySD))")
        lines.append("  D7 Engagement SD:          \(String(format: "%.3f", stats.corpusEngagementSD))")
        lines.append("  D8 Opener Pattern Match:   median=\(String(format: "%.3f", stats.corpusOpenerPatternMatchMedian))  SD=\(String(format: "%.3f", stats.corpusOpenerPatternMatchSD))")
        lines.append("  D8 Hint Rate Diff:         median=\(String(format: "%.3f", stats.corpusHintDiffMedian))  SD=\(String(format: "%.3f", stats.corpusHintDiffSD))")
        lines.append("")

        // Corpus-calibrated metrics (previously hardcoded)
        lines.append("CORPUS-CALIBRATED METRICS (previously hardcoded)")
        lines.append("  D2 Casual Markers:         median=\(String(format: "%.2f", stats.corpusCasualMarkerMedian))  SD=\(String(format: "%.2f", stats.corpusCasualMarkerSD))")
        lines.append("  D4 Signature Match Rate:   median=\(String(format: "%.3f", stats.corpusSignatureMatchMedian))  SD=\(String(format: "%.3f", stats.corpusSignatureMatchSD))")
        lines.append("  D5 Word Count In Range:    median=\(String(format: "%.3f", stats.corpusWordCountInRangeMedian))  SD=\(String(format: "%.3f", stats.corpusWordCountInRangeSD))")
        lines.append("  D5 Type Match Rate:        median=\(String(format: "%.3f", stats.corpusTypeMatchMedian))  SD=\(String(format: "%.3f", stats.corpusTypeMatchSD))")
        lines.append("  D5 Alternation Rate:       median=\(String(format: "%.3f", stats.corpusAlternationMedian))  SD=\(String(format: "%.3f", stats.corpusAlternationSD))")
        lines.append("  D8 Trigram Overlap:        median=\(String(format: "%.3f", stats.corpusTrigramOverlapMedian))  SD=\(String(format: "%.3f", stats.corpusTrigramOverlapSD))")
        lines.append("  D3 Opener Sig Freq:        median=\(String(format: "%.3f", stats.corpusOpenerSigOverlapMedian))  SD=\(String(format: "%.3f", stats.corpusOpenerSigOverlapSD))")
        lines.append("  D3 Closer Sig Freq:        median=\(String(format: "%.3f", stats.corpusCloserSigOverlapMedian))  SD=\(String(format: "%.3f", stats.corpusCloserSigOverlapSD))")
        lines.append("")

        // Opener sig frequency distributions per move type
        if !stats.rolledOpenerSigFreqByMove.isEmpty {
            lines.append("OPENER SIG FREQUENCY DISTRIBUTIONS")
            for move in stats.rolledOpenerSigFreqByMove.keys.sorted() {
                if let freqs = stats.rolledOpenerSigFreqByMove[move] {
                    let sorted = freqs.sorted { $0.value > $1.value }
                    let topSigs = sorted.prefix(5).map { "\($0.key)=\(String(format: "%.0f", $0.value * 100))%" }
                    lines.append("  \(move.padding(toLength: 28, withPad: " ", startingAt: 0)) \(sorted.count) unique | \(topSigs.joined(separator: ", "))")
                }
            }
            lines.append("")
        }

        // Hint rates
        let sortedHints = stats.hintRates.sorted { $0.value > $1.value }
        if !sortedHints.isEmpty {
            lines.append("HINT RATES")
            for hint in sortedHints {
                lines.append("  \(hint.key.padding(toLength: 28, withPad: " ", startingAt: 0)) \(String(format: "%.3f", hint.value))")
            }
            lines.append("")
        }

        // Casual markers
        lines.append("CASUAL MARKERS: \(stats.casualMarkers.joined(separator: ", "))")
        lines.append("")

        // Slot data summary
        let slotMoves = Set(
            Array(stats.slotSignaturesByMove.keys) +
            Array(stats.openerSlotSignaturesByMove.keys) +
            Array(stats.closerSlotSignaturesByMove.keys) +
            Array(stats.slotBigramsByMove.keys)
        ).sorted()
        if !slotMoves.isEmpty {
            lines.append("SLOT SIGNATURES PER MOVE (LLM-assigned)")
            for move in slotMoves {
                let sigCount = stats.slotSignaturesByMove[move]?.count ?? 0
                let openerCount = stats.openerSlotSignaturesByMove[move]?.count ?? 0
                let closerCount = stats.closerSlotSignaturesByMove[move]?.count ?? 0
                let bigramCount = stats.slotBigramsByMove[move]?.count ?? 0
                let rolledCount = stats.rolledSlotSignaturesByMove[move]?.count ?? 0
                let rolledBigramCount = stats.rolledSlotBigramsByMove[move]?.count ?? 0
                lines.append("  \(move.padding(toLength: 28, withPad: " ", startingAt: 0)) \(sigCount) sigs (\(rolledCount) rolled), \(openerCount) opener, \(closerCount) closer, \(bigramCount) bigrams (\(rolledBigramCount) rolled)")
            }
            lines.append("")
        }

        // S2 raw slot frequency distributions per move type
        let distMoves = stats.rawSlotDistributionByMove.keys.sorted()
        if !distMoves.isEmpty {
            lines.append("RAW SLOT DISTRIBUTIONS PER MOVE (S2)")
            for move in distMoves {
                if let dist = stats.rawSlotDistributionByMove[move] {
                    let sorted = dist.sorted { $0.value > $1.value }
                    lines.append("  \(move):")
                    for entry in sorted {
                        let barLen = max(1, Int(entry.value * 40))
                        let bar = String(repeating: "\u{2588}", count: barLen)
                        lines.append("    \(entry.key.padding(toLength: 22, withPad: " ", startingAt: 0)) \(String(format: "%.3f", entry.value))  \(bar)")
                    }
                }
            }
            lines.append("")

            lines.append("S2 CORPUS BASELINES")
            lines.append("  Slot Dist Cosine:   median=\(String(format: "%.3f", stats.corpusSlotDistCosinMedian))  SD=\(String(format: "%.3f", stats.corpusSlotDistCosinSD))")
            lines.append("  Bigram Dist Cosine: median=\(String(format: "%.3f", stats.corpusBigramDistCosinMedian))  SD=\(String(format: "%.3f", stats.corpusBigramDistCosinSD))")
            lines.append("")
        }

        lines.append("TRIGRAM INDEX: \(stats.trigramIndex.count) unique trigrams")
        lines.append("OPENING PATTERNS: \(stats.openingPatternSet.count) unique first words")

        return lines.joined(separator: "\n")
    }

    /// Dump baseline ranges in a copyable text format.
    static func buildBaselineReport(_ baseline: BaselineProfile) -> String {
        var lines: [String] = []

        let dateStr = baseline.computedAt.formatted(date: .abbreviated, time: .shortened)
        lines.append("═══ BASELINE PROFILE: \(baseline.creatorId) ═══")
        lines.append("Computed: \(dateStr)  |  Sample Count: \(baseline.sampleCount)")
        lines.append("")

        // Global dimension ranges
        lines.append("GLOBAL DIMENSION RANGES")
        lines.append("  \("Dimension".padding(toLength: 28, withPad: " ", startingAt: 0)) \("Min".padding(toLength: 8, withPad: " ", startingAt: 0)) \("P25".padding(toLength: 8, withPad: " ", startingAt: 0)) \("Median".padding(toLength: 8, withPad: " ", startingAt: 0)) \("P75".padding(toLength: 8, withPad: " ", startingAt: 0)) \("Max".padding(toLength: 8, withPad: " ", startingAt: 0)) IQR    N")
        for dim in FidelityDimension.allCases {
            if let range = baseline.dimensionRanges[dim.rawValue] {
                let row = "  \(dim.displayName.padding(toLength: 28, withPad: " ", startingAt: 0)) " +
                    "\(String(format: "%-8.1f", range.min))" +
                    "\(String(format: "%-8.1f", range.p25))" +
                    "\(String(format: "%-8.1f", range.median))" +
                    "\(String(format: "%-8.1f", range.p75))" +
                    "\(String(format: "%-8.1f", range.max))" +
                    "\(String(format: "%-7.1f", range.iqr))" +
                    "\(range.sampleCount)"
                lines.append(row)
            }
        }
        lines.append("")

        // Per-move section baselines
        let moveTypes = baseline.sectionBaselines.keys.sorted()
        if !moveTypes.isEmpty {
            lines.append("PER-MOVE SECTION BASELINES")
            for move in moveTypes {
                guard let dimRanges = baseline.sectionBaselines[move] else { continue }
                lines.append("")
                lines.append("  ── \(move) ──")
                for dim in FidelityDimension.allCases {
                    if let range = dimRanges[dim.rawValue] {
                        lines.append("    \(dim.shortLabel.padding(toLength: 8, withPad: " ", startingAt: 0)) median=\(String(format: "%.1f", range.median))  IQR=[\(String(format: "%.1f", range.p25))-\(String(format: "%.1f", range.p75))]  range=[\(String(format: "%.1f", range.min))-\(String(format: "%.1f", range.max))]  n=\(range.sampleCount)")
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Full evaluation report with WHAT/RAW/WHY for every decision point.
    static func buildEvaluationReport(
        evaluations: [(label: String, score: FidelityScore, sections: [SectionFidelityResult], slotDebug: [SlotDebugData]?)],
        cache: FidelityCorpusCache,
        weightProfile: FidelityWeightProfile
    ) -> String {
        var lines: [String] = []

        let dateStr = cache.computedAt.formatted(date: .abbreviated, time: .shortened)
        lines.append("═══ FIDELITY EVALUATION REPORT ═══")
        lines.append("Weight Profile: \(weightProfile.name)")
        lines.append("Baseline: \(cache.sentenceCount) sentences  |  Computed: \(dateStr)")
        lines.append("")

        // Active weights
        lines.append("ACTIVE WEIGHTS")
        for dim in FidelityDimension.allCases {
            let w = weightProfile.weight(for: dim)
            lines.append("  \(dim.displayName.padding(toLength: 28, withPad: " ", startingAt: 0)) \(String(format: "%5.1f", w * 100))%")
        }
        lines.append("")

        // Active hard-fail rules
        let enabledRules = weightProfile.hardFailRules.filter(\.isEnabled)
        if !enabledRules.isEmpty {
            lines.append("ACTIVE HARD-FAIL RULES")
            for rule in enabledRules {
                let comp = rule.comparison == .greaterThan ? ">" : "<"
                let mode = rule.thresholdMode == .absolute ? "absolute" : "\(String(format: "%.1f", rule.threshold))\u{00D7} corpus"
                let sev = rule.severity == .fail ? "FAIL" : "WARN"
                lines.append("  [\(sev)] \(rule.label): \(rule.metric.displayName) \(comp) \(mode)")
            }
            lines.append("")
        }

        guard !evaluations.isEmpty else {
            lines.append("No evaluations to report.")
            return lines.joined(separator: "\n")
        }

        // Ranking summary
        lines.append("RANKING")
        for (i, eval) in evaluations.enumerated() {
            let failStr = eval.score.hardFailCount > 0 ? "\(eval.score.hardFailCount) fails" : "0 fails"
            let warnStr = eval.score.warningCount > 0 ? "\(eval.score.warningCount) warn" : "0 warn"
            lines.append("  #\(i + 1)  \(eval.label.padding(toLength: 24, withPad: " ", startingAt: 0)) \(String(format: "%5.1f", eval.score.compositeScore))  (\(failStr), \(warnStr))")
        }
        lines.append("")

        // Per-method detail
        for eval in evaluations {
            lines.append("─── \(eval.label) (\(String(format: "%.1f", eval.score.compositeScore))) ───")
            lines.append("")

            // Aggregate hard-fail results from all sections
            let allHardFails = eval.sections.flatMap(\.hardFailResults)
            // Deduplicate by rule label — show worst case for each rule
            var ruleResults: [String: HardFailResult] = [:]
            for hf in allHardFails {
                let key = hf.rule.label
                if let existing = ruleResults[key] {
                    // Keep the worst (failed over passed, or highest actual value)
                    if !hf.passed && existing.passed { ruleResults[key] = hf }
                    else if !hf.passed && !existing.passed && hf.actualValue > existing.actualValue { ruleResults[key] = hf }
                } else {
                    ruleResults[key] = hf
                }
            }

            if !ruleResults.isEmpty {
                lines.append("  HARD-FAIL CHECKS")
                for hf in ruleResults.values.sorted(by: { $0.rule.label < $1.rule.label }) {
                    let icon = hf.passed ? "\u{2713}" : "\u{2717}"
                    let what = hf.passed ? "passed" : (hf.rule.severity == .fail ? "FAIL" : "WARN")
                    let comp = hf.rule.comparison == .greaterThan ? "\u{2264}" : "\u{2265}"
                    let modeExplain: String
                    if hf.rule.thresholdMode == .absolute {
                        modeExplain = "absolute \(String(format: "%.2f", hf.rule.threshold))"
                    } else {
                        modeExplain = "\(String(format: "%.1f", hf.rule.threshold))\u{00D7} corpus"
                    }
                    lines.append("    \(icon) \(hf.rule.label.padding(toLength: 28, withPad: " ", startingAt: 0)) WHAT: \(what.padding(toLength: 8, withPad: " ", startingAt: 0)) RAW: \(String(format: "%.2f", hf.actualValue)) vs corpus \(String(format: "%.2f", hf.corpusValue))   WHY: threshold \(String(format: "%.2f", hf.effectiveThreshold)) (\(modeExplain)), actual \(comp) limit \(hf.passed ? "OK" : "VIOLATED")")
                }
                lines.append("")
            }

            // Dimension scores
            lines.append("  DIMENSION SCORES")
            for dim in FidelityDimension.allCases {
                guard let ds = eval.score.score(for: dim) else { continue }
                let w = weightProfile.weight(for: dim)
                let contribution = w * ds.score
                lines.append("    \(dim.displayName.padding(toLength: 28, withPad: " ", startingAt: 0)) \(String(format: "%5.1f", ds.score))  (weight \(String(format: "%.1f", w * 100))% \u{2192} contributes \(String(format: "%.1f", contribution)))")

                // Sub-metrics
                for sub in ds.subMetrics {
                    var subLine = "      \(sub.name.padding(toLength: 26, withPad: " ", startingAt: 0)) RAW: \(String(format: "%-8.3f", sub.rawValue)) CORPUS: \(String(format: "%-8.3f", sub.corpusMean)) SCORE: \(String(format: "%5.1f", sub.score))"

                    // Add baseline range context if available
                    if let br = ds.baselineRange {
                        subLine += "   BASELINE: [\(String(format: "%.1f", br.p25))-\(String(format: "%.1f", br.p75))]"
                    }

                    lines.append(subLine)
                }
            }
            lines.append("")

            // Per-section summary
            if eval.sections.count > 1 {
                lines.append("  PER-SECTION BREAKDOWN")
                for section in eval.sections {
                    var secLine = "    Section \(section.sectionIndex): \(section.sentenceCount) sent, \(section.wordCount) words, composite=\(String(format: "%.1f", section.compositeScore))"
                    if section.hasHardFail {
                        let failNames = section.failedRules.map { $0.rule.label }.joined(separator: ", ")
                        secLine += "  FAILS: \(failNames)"
                    }
                    if section.hasWarning {
                        let warnNames = section.warningRules.map { $0.rule.label }.joined(separator: ", ")
                        secLine += "  WARNS: \(warnNames)"
                    }
                    lines.append(secLine)
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Per-Dimension Debug Report

    /// Build a detailed debug trace for one dimension across all corpus sections.
    /// Reconstructs ~77 sections, scores each, sorts worst-first, and dumps
    /// full WHAT/RAW/WHY for every sub-metric so scoring bugs are immediately visible.
    static func buildDimensionDebugReport(
        dimension: FidelityDimension,
        donorSentences: [CreatorSentence],
        cache: FidelityCorpusCache
    ) -> String {
        let corpusStats = cache.corpusStats
        let rhythmTemplates = cache.rhythmTemplates
        let sectionProfiles = cache.sectionProfiles

        // Reconstruct sections from raw sentences
        let grouped = Dictionary(grouping: donorSentences) { "\($0.videoId)_\($0.sectionIndex)" }

        struct ScoredSection {
            let videoId: String
            let sectionIndex: Int
            let moveType: String
            let sentenceCount: Int
            let wordCount: Int
            let parsed: ParsedSection
            let dimScore: DimensionScore
            let rawSentences: [CreatorSentence]
        }

        var scored: [ScoredSection] = []

        for (_, sentences) in grouped {
            let sorted = sentences.sorted { $0.sentenceIndex < $1.sentenceIndex }
            guard let first = sorted.first else { continue }

            let sectionText = sorted.map(\.rawText).joined(separator: " ")
            let parsed = parseSection(text: sectionText, index: first.sectionIndex, moveType: first.moveType)

            let dimScore: DimensionScore
            switch dimension {
            case .sentenceMechanics:
                dimScore = scoreSentenceMechanics(section: parsed, corpusStats: corpusStats, baseline: nil)
            case .vocabularyRegister:
                dimScore = scoreVocabularyRegister(section: parsed, corpusStats: corpusStats, baseline: nil)
            case .structuralShape:
                dimScore = scoreStructuralShape(section: parsed, sectionProfiles: sectionProfiles, corpusStats: corpusStats, baseline: nil)
            case .slotSignatureFidelity:
                dimScore = scoreSlotSignatureFidelity(section: parsed, corpusStats: corpusStats, baseline: nil)
            case .rhythmCadence:
                dimScore = scoreRhythmCadence(section: parsed, rhythmTemplates: rhythmTemplates, corpusStats: corpusStats, baseline: nil)
            case .contentCoverage:
                dimScore = scoreContentCoverage(section: parsed, corpusStats: corpusStats, baseline: nil)
            case .stanceTempo:
                dimScore = scoreStanceTempo(section: parsed, corpusStats: corpusStats, baseline: nil)
            case .donorSentenceSimilarity:
                dimScore = scoreDonorSimilarity(section: parsed, corpusStats: corpusStats, baseline: nil)
            case .slotSignatureS2:
                let sectionSigs = sorted.map(\.slotSignature)
                dimScore = scoreSlotSignatureS2(section: parsed, corpusStats: corpusStats, baseline: nil, s2Signatures: sectionSigs, excludeSectionSigs: sectionSigs)
            }

            scored.append(ScoredSection(
                videoId: first.videoId,
                sectionIndex: first.sectionIndex,
                moveType: first.moveType,
                sentenceCount: parsed.sentenceCount,
                wordCount: parsed.wordCount,
                parsed: parsed,
                dimScore: dimScore,
                rawSentences: sorted
            ))
        }

        // Sort worst-first for debugging
        scored.sort { $0.dimScore.score < $1.dimScore.score }

        var lines: [String] = []
        lines.append("═══ DIMENSION DEBUG: \(dimension.displayName) ═══")
        lines.append("Sections: \(scored.count)  |  Corpus: \(donorSentences.count) sentences")
        lines.append("")

        // Distribution summary at top
        let allScores = scored.map(\.dimScore.score).sorted()
        if !allScores.isEmpty {
            let range = computeRange(from: allScores)
            let belowFifty = allScores.filter { $0 < 50.0 }.count
            lines.append("DISTRIBUTION")
            lines.append("  Min=\(String(format: "%.1f", range.min))  P25=\(String(format: "%.1f", range.p25))  Median=\(String(format: "%.1f", range.median))  P75=\(String(format: "%.1f", range.p75))  Max=\(String(format: "%.1f", range.max))  IQR=\(String(format: "%.1f", range.iqr))  n=\(range.sampleCount)")
            lines.append("  Sections below 50: \(belowFifty)/\(scored.count)")
            lines.append("")
        }

        // Per-section detail
        for (i, s) in scored.enumerated() {
            lines.append("── #\(i + 1) Score=\(String(format: "%.1f", s.dimScore.score)) | Video: \(s.videoId) | Sec \(s.sectionIndex) | Move: \(s.moveType) | \(s.sentenceCount) sent, \(s.wordCount) words ──")

            // Sub-metrics with WHAT/RAW/WHY trace (three scoring modes)
            let rangeMetricKeys: [String: String] = [
                "First-Person Rate": "firstPersonRate", "Contraction Rate": "contractionRate",
                "Casual Markers": "casualMarkers", "Direct Address Rate": "directAddressRate",
                "Alternation Pattern": "alternation", "Word Count vs Expected": "wordCount",
                "Engagement Level": "engagement", "Bucket Transitions": "cadenceFit"
            ]
            let membershipMetrics: Set<String> = ["Opening Sig Match", "Closing Sig Match", "Opener Sig Match"]

            for sub in s.dimScore.subMetrics {
                var why = ""
                if sub.name == "Sent Length Distrib" {
                    // Composite of 3 bucket range scores — show per-bucket breakdown
                    let sentLens = s.parsed.sentences.map(\.wordCount)
                    let sc = sentLens.filter { $0 <= corpusStats.shortSentenceMax }.count
                    let lc = sentLens.filter { $0 >= corpusStats.longSentenceMin }.count
                    let mc = sentLens.count - sc - lc
                    let bt = max(Double(sentLens.count), 1.0)
                    func pctStr(_ n: Int) -> String { String(format: "%.1f%%", Double(n) / bt * 100) }
                    why = "RANGE (composite): short=\(pctStr(sc)) medium=\(pctStr(mc)) long=\(pctStr(lc)) → avg of 3 bucket rangeScores"
                } else if membershipMetrics.contains(sub.name) {
                    // MEMBERSHIP-scored: binary exists-in-corpus check
                    why = sub.rawValue >= 1.0 ? "MEMBERSHIP: sig found in corpus \u{2192} 100" : "MEMBERSHIP: sig NOT in corpus \u{2192} 0"
                } else if let rangeKey = rangeMetricKeys[sub.name], let range = corpusStats.metricRange(rangeKey) {
                    // RANGE-scored: within creator's observed distribution
                    let inIQR = sub.rawValue >= range.p25 && sub.rawValue <= range.p75
                    let inRange = sub.rawValue >= range.min && sub.rawValue <= range.max
                    let status = inIQR ? "within IQR" : (inRange ? "within range" : "OUTSIDE range")
                    why = "RANGE: \(status) IQR=[\(String(format: "%.3f", range.p25))-\(String(format: "%.3f", range.p75))] full=[\(String(format: "%.3f", range.min))-\(String(format: "%.3f", range.max))]"
                } else if let tol = sub.tolerance, tol > 0 {
                    // PROXIMITY-scored: close to corpus median
                    let distance = abs(sub.rawValue - sub.corpusMean)
                    let normalized = distance / tol
                    why = "PROXIMITY: distance=\(String(format: "%.3f", distance)) tol=\(String(format: "%.3f", tol)) norm=\(String(format: "%.3f", normalized))"
                } else if sub.score >= 100 {
                    why = "exact or near-exact match"
                } else if sub.score <= 0 {
                    let distance = abs(sub.rawValue - sub.corpusMean)
                    why = "distance=\(String(format: "%.3f", distance)) exceeded 2\u{00D7} tolerance \u{2192} clamped to 0"
                } else {
                    let distance = abs(sub.rawValue - sub.corpusMean)
                    why = "distance=\(String(format: "%.3f", distance)) (non-proximity scorer)"
                }
                lines.append("  \(sub.name.padding(toLength: 24, withPad: " ", startingAt: 0)) RAW=\(String(format: "%-8.3f", sub.rawValue)) CORPUS=\(String(format: "%-8.3f", sub.corpusMean)) SCORE=\(String(format: "%5.1f", sub.score))  WHY: \(why)")
            }

            // Dimension-specific extra detail
            switch dimension {
            case .structuralShape:
                // Show sentence length distribution bucket breakdown
                let sentLens = s.parsed.sentences.map(\.wordCount)
                let sc = sentLens.filter { $0 <= corpusStats.shortSentenceMax }.count
                let lc = sentLens.filter { $0 >= corpusStats.longSentenceMin }.count
                let mc = sentLens.count - sc - lc
                let bt = max(Double(sentLens.count), 1.0)
                let sPct = String(format: "%.1f", Double(sc) / bt * 100)
                let mPct = String(format: "%.1f", Double(mc) / bt * 100)
                let lPct = String(format: "%.1f", Double(lc) / bt * 100)
                lines.append("    Buckets: short(\u{2264}\(corpusStats.shortSentenceMax)w)=\(sc)/\(sentLens.count) (\(sPct)%)  medium=\(mc) (\(mPct)%)  long(\u{2265}\(corpusStats.longSentenceMin)w)=\(lc) (\(lPct)%)")
                lines.append("    Sentence lengths: \(sentLens)")

                // Show membership-based signature comparison
                let moveKey = s.moveType
                let corpusOpenerSigs = corpusStats.rolledOpenerSlotSignatures(forMove: moveKey)
                let corpusCloserSigs = corpusStats.rolledCloserSlotSignatures(forMove: moveKey)
                if let firstSent = s.parsed.sentences.first {
                    let heuristicSig = extractSlotSignature(from: firstSent)
                    let rolledSig = SignatureRollupService.rollupDominantSlot(heuristicSig)
                    let inCorpus = corpusOpenerSigs.contains(rolledSig)
                    lines.append("    Opening: heuristic=\"\(heuristicSig)\" rolled=\"\(rolledSig)\" \(inCorpus ? "IN CORPUS" : "NOT IN CORPUS") (corpus has \(corpusOpenerSigs.count) opener sigs)")
                }
                if let lastSent = s.parsed.sentences.last, s.parsed.sentences.count > 1 {
                    let heuristicSig = extractSlotSignature(from: lastSent)
                    let rolledSig = SignatureRollupService.rollupDominantSlot(heuristicSig)
                    let inCorpus = corpusCloserSigs.contains(rolledSig)
                    lines.append("    Closing: heuristic=\"\(heuristicSig)\" rolled=\"\(rolledSig)\" \(inCorpus ? "IN CORPUS" : "NOT IN CORPUS") (corpus has \(corpusCloserSigs.count) closer sigs)")
                }

            case .slotSignatureFidelity:
                // Per-sentence signature extraction with rolled-up matching
                let moveKey = s.moveType
                let corpusRolledSigs = corpusStats.rolledSlotSignatures(forMove: moveKey)
                for (idx, sent) in s.parsed.sentences.enumerated() {
                    let heuristicSig = extractSlotSignature(from: sent)
                    let rolledSig = SignatureRollupService.rollupDominantSlot(heuristicSig)
                    let matched = corpusRolledSigs.contains(rolledSig)
                    let preview = String(sent.text.prefix(60))
                    lines.append("    [\(idx)] heuristic=\"\(heuristicSig)\" rolled=\"\(rolledSig)\" \(matched ? "MATCH" : "MISS") hints=\(Array(sent.deterministicHints).sorted()) text=\"\(preview)\"")
                }

            case .slotSignatureS2:
                // Per-sentence raw (unrolled) LLM-assigned signature matching
                let moveKey2 = s.moveType
                let corpusRawSigs = corpusStats.slotSignatures(forMove: moveKey2)
                for (idx, rawSent) in s.rawSentences.enumerated() {
                    let rawSig = rawSent.slotSignature
                    let matched = corpusRawSigs.contains(rawSig)
                    let preview = String(rawSent.rawText.prefix(60))
                    lines.append("    [\(idx)] rawSig=\"\(rawSig)\" \(matched ? "MATCH" : "MISS") text=\"\(preview)\"")
                }

            case .sentenceMechanics:
                // Show sentence count and lengths for context
                let lengths = s.parsed.sentences.map(\.wordCount)
                lines.append("    Sentence lengths: \(lengths)")

            case .donorSentenceSimilarity:
                // Show trigram stats
                let allTrigrams = s.parsed.sentences.flatMap(\.trigrams)
                let hits = allTrigrams.filter { corpusStats.trigramIndex[$0] != nil }.count
                lines.append("    Trigrams: \(hits)/\(allTrigrams.count) matched corpus index")
                let openerHits = s.parsed.sentences.filter { corpusStats.openingPatterns.contains($0.firstWord) }.count
                lines.append("    Opener matches: \(openerHits)/\(s.parsed.sentences.count)")

            case .stanceTempo:
                // Show engagement breakdown — binary fpRate (matches scorer)
                let total = Double(max(s.parsed.sentences.count, 1))
                let qRate = Double(s.parsed.sentences.filter(\.isQuestion).count) / total
                let daRate = Double(s.parsed.sentences.filter(\.hasDirectAddress).count) / total
                let fpRate = Double(s.parsed.sentences.filter { $0.firstPersonCount > 0 }.count) / total
                lines.append("    Engagement breakdown: qRate=\(String(format: "%.3f", qRate)) daRate=\(String(format: "%.3f", daRate)) fpRate=\(String(format: "%.3f", fpRate)) (binary) → weighted=\(String(format: "%.3f", qRate * 0.4 + daRate * 0.3 + min(fpRate * 0.3, 0.3)))")

            case .rhythmCadence:
                // Show per-sentence template match
                for (idx, sent) in s.parsed.sentences.enumerated() {
                    let pos = sectionPosition(index: idx, total: s.parsed.sentences.count)
                    let template = rhythmTemplates.filter { $0.moveType == s.moveType }.first { $0.positionInSection == pos }
                    let wc = sent.wordCount
                    if let t = template {
                        let inRange = wc >= t.wordCountMin && wc <= t.wordCountMax
                        let sentType = sent.isQuestion ? "question" : (sent.isFragment ? "fragment" : "statement")
                        let typeMatch = sentType == t.sentenceType
                        lines.append("    [\(idx)] pos=\(pos) wc=\(wc) range=[\(t.wordCountMin)-\(t.wordCountMax)] \(inRange ? "IN" : "OUT") | type=\(sentType) expected=\(t.sentenceType) \(typeMatch ? "MATCH" : "MISS")")
                    } else {
                        lines.append("    [\(idx)] pos=\(pos) wc=\(wc) (no template \u{2192} generous)")
                    }
                }
                // Show cadence bucket transition sequence
                if s.parsed.sentences.count >= 2 {
                    let cadenceBuckets = s.parsed.sentences.map { sent -> String in
                        if sent.wordCount <= corpusStats.shortSentenceMax { return "S" }
                        if sent.wordCount >= corpusStats.longSentenceMin { return "L" }
                        return "M"
                    }
                    lines.append("    Cadence seq: \(cadenceBuckets.joined(separator: "\u{2192}"))")
                }

            default:
                break
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
