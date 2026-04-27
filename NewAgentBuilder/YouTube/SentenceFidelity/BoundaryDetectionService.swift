//
//  BoundaryDetectionService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

/// Service for detecting chunk boundaries from tagged sentences
/// Uses deterministic code rules - no LLM calls
class BoundaryDetectionService {

    static let shared = BoundaryDetectionService()
    static let currentVersion = "1.0"

    private init() {}

    // MARK: - Main Detection

    /// Detect boundaries from tagged sentences
    /// - Parameters:
    ///   - sentences: Array of tagged sentences from fidelity test
    ///   - params: Tunable detection parameters
    /// - Returns: Array of detected chunks with profiles
    func detectBoundaries(
        from sentences: [SentenceTelemetry],
        params: BoundaryDetectionParams = .default,
        excludeIndices: Set<Int>? = nil
    ) -> [Chunk] {
        // Filter out excluded indices (e.g. digression sentences) if provided
        let activeSentences = excludeIndices == nil
            ? sentences
            : sentences.filter { !excludeIndices!.contains($0.sentenceIndex) }

        guard !activeSentences.isEmpty else { return [] }

        var boundaries: [Int] = [0]  // First sentence always starts a chunk
        var triggers: [BoundaryTrigger?] = [nil]  // No trigger for first chunk

        let total = activeSentences.count
        var lastBoundary = 0

        for i in 1..<activeSentences.count {
            let current = activeSentences[i]
            let previous = activeSentences[i - 1]

            // Check minimum chunk size
            if i - lastBoundary < params.minChunkSize {
                continue
            }

            if let trigger = checkBoundary(
                current: current,
                previous: previous,
                position: i,
                total: total,
                params: params
            ) {
                boundaries.append(i)
                triggers.append(trigger)
                lastBoundary = i
            }
        }

        return buildChunks(sentences: activeSentences, boundaries: boundaries, triggers: triggers)
    }

    /// Detect boundaries and return full result with metadata
    func detectBoundaries(
        from fidelityTest: SentenceFidelityTest,
        params: BoundaryDetectionParams = .default
    ) -> BoundaryDetectionResult {
        let chunks = detectBoundaries(from: fidelityTest.sentences, params: params)

        return BoundaryDetectionResult(
            id: UUID().uuidString,
            videoId: fidelityTest.videoId,
            videoTitle: fidelityTest.videoTitle,
            channelId: fidelityTest.channelId,
            createdAt: Date(),
            totalSentences: fidelityTest.totalSentences,
            chunks: chunks,
            detectionVersion: Self.currentVersion,
            sourceFidelityTestId: fidelityTest.id
        )
    }

    // MARK: - Boundary Checking

    /// Check if current sentence starts a new chunk
    /// IMPORTANT: If you change rules here, also update auditCheckBoundary below
    private func checkBoundary(
        current: SentenceTelemetry,
        previous: SentenceTelemetry,
        position: Int,
        total: Int,
        params: BoundaryDetectionParams
    ) -> BoundaryTrigger? {
        let relativePosition = Double(position) / Double(total)

        // ============================================
        // HIGH CONFIDENCE BOUNDARIES
        // ============================================

        // Explicit transition language
        if current.isTransition {
            return BoundaryTrigger(
                type: .transition,
                sentenceIndex: position,
                confidence: .high
            )
        }

        // Sponsorship section starts
        if current.isSponsorContent && !previous.isSponsorContent {
            return BoundaryTrigger(
                type: .sponsor,
                sentenceIndex: position,
                confidence: .high
            )
        }

        // Sponsorship section ends (boundary on exit)
        if params.boundaryOnSponsorExit && !current.isSponsorContent && previous.isSponsorContent {
            return BoundaryTrigger(
                type: .sponsor,
                sentenceIndex: position,
                confidence: .high
            )
        }

        // CTA section (but not at very end if suppressed, and not within sponsor territory)
        if current.isCallToAction && !previous.isCallToAction && !previous.isSponsorContent {
            if !params.suppressEndCTAs || relativePosition < params.endCTAThreshold {
                return BoundaryTrigger(
                    type: .cta,
                    sentenceIndex: position,
                    confidence: .high
                )
            }
        }

        // ============================================
        // MEDIUM CONFIDENCE BOUNDARIES
        // ============================================

        // Contrast + Question = classic pivot pattern
        // "But what about X?" or "However, is that really true?"
        if current.hasContrastMarker && current.stance == "questioning" {
            return BoundaryTrigger(
                type: .contrastQuestion,
                sentenceIndex: position,
                confidence: .medium
            )
        }

        // Reveal language (but not at very start of video)
        if current.hasRevealLanguage && relativePosition > params.revealPositionThreshold {
            // Only trigger if it's combined with first-person or transition
            if current.hasFirstPerson || current.isTransition {
                return BoundaryTrigger(
                    type: .reveal,
                    sentenceIndex: position,
                    confidence: .medium
                )
            }
        }

        // Perspective shift: third-person explanation → first-person reflection
        if previous.perspective == "third" && current.perspective == "first" {
            if current.hasFirstPerson && current.stance == "questioning" {
                return BoundaryTrigger(
                    type: .perspectiveShift,
                    sentenceIndex: position,
                    confidence: .medium
                )
            }
        }

        return nil
    }

    // MARK: - Audit Check Boundary

    /// Audit version of checkBoundary — records every rule evaluation.
    /// IMPORTANT: If you change rules in checkBoundary, also update this method.
    private func auditCheckBoundary(
        current: SentenceTelemetry,
        previous: SentenceTelemetry,
        position: Int,
        total: Int,
        params: BoundaryDetectionParams
    ) -> (trigger: BoundaryTrigger?, rules: [RuleEvaluation]) {
        let relativePosition = Double(position) / Double(total)
        var evaluations: [RuleEvaluation] = []

        // Rule 1: Transition (HIGH)
        let r1Fired = current.isTransition
        evaluations.append(RuleEvaluation(
            ruleNumber: 1, ruleName: "Transition",
            ruleConfidence: .high, fired: r1Fired,
            conditions: [
                .init(fieldName: "current.isTransition",
                      actualValue: "\(current.isTransition)",
                      requiredValue: "true", passed: current.isTransition)
            ]
        ))
        if r1Fired {
            return (BoundaryTrigger(type: .transition, sentenceIndex: position, confidence: .high), evaluations)
        }

        // Rule 2: Sponsor Entry (HIGH)
        let r2c1 = current.isSponsorContent
        let r2c2 = !previous.isSponsorContent
        let r2Fired = r2c1 && r2c2
        evaluations.append(RuleEvaluation(
            ruleNumber: 2, ruleName: "Sponsor entry",
            ruleConfidence: .high, fired: r2Fired,
            conditions: [
                .init(fieldName: "current.isSponsorContent",
                      actualValue: "\(current.isSponsorContent)",
                      requiredValue: "true", passed: r2c1),
                .init(fieldName: "previous.isSponsorContent",
                      actualValue: "\(previous.isSponsorContent)",
                      requiredValue: "false", passed: r2c2)
            ]
        ))
        if r2Fired {
            return (BoundaryTrigger(type: .sponsor, sentenceIndex: position, confidence: .high), evaluations)
        }

        // Rule 3: Sponsor Exit (HIGH, param-gated)
        let r3c1 = params.boundaryOnSponsorExit
        let r3c2 = !current.isSponsorContent
        let r3c3 = previous.isSponsorContent
        let r3Fired = r3c1 && r3c2 && r3c3
        evaluations.append(RuleEvaluation(
            ruleNumber: 3, ruleName: "Sponsor exit",
            ruleConfidence: .high, fired: r3Fired,
            conditions: [
                .init(fieldName: "params.boundaryOnSponsorExit",
                      actualValue: "\(params.boundaryOnSponsorExit)",
                      requiredValue: "true", passed: r3c1),
                .init(fieldName: "current.isSponsorContent",
                      actualValue: "\(current.isSponsorContent)",
                      requiredValue: "false", passed: r3c2),
                .init(fieldName: "previous.isSponsorContent",
                      actualValue: "\(previous.isSponsorContent)",
                      requiredValue: "true", passed: r3c3)
            ]
        ))
        if r3Fired {
            return (BoundaryTrigger(type: .sponsor, sentenceIndex: position, confidence: .high), evaluations)
        }

        // Rule 4: CTA Entry (HIGH, position-gated)
        let r4c1 = current.isCallToAction
        let r4c2 = !previous.isCallToAction
        let r4c3 = !previous.isSponsorContent
        let r4posGate = !params.suppressEndCTAs || relativePosition < params.endCTAThreshold
        let r4Fired = r4c1 && r4c2 && r4c3 && r4posGate
        var r4Conditions: [RuleEvaluation.ConditionResult] = [
            .init(fieldName: "current.isCallToAction",
                  actualValue: "\(current.isCallToAction)",
                  requiredValue: "true", passed: r4c1),
            .init(fieldName: "previous.isCallToAction",
                  actualValue: "\(previous.isCallToAction)",
                  requiredValue: "false", passed: r4c2),
            .init(fieldName: "previous.isSponsorContent",
                  actualValue: "\(previous.isSponsorContent)",
                  requiredValue: "false", passed: r4c3)
        ]
        if params.suppressEndCTAs {
            r4Conditions.append(.init(
                fieldName: "relativePosition < endCTAThreshold",
                actualValue: String(format: "%.3f < %.1f", relativePosition, params.endCTAThreshold),
                requiredValue: "true",
                passed: relativePosition < params.endCTAThreshold
            ))
        }
        evaluations.append(RuleEvaluation(
            ruleNumber: 4, ruleName: "CTA entry",
            ruleConfidence: .high, fired: r4Fired,
            conditions: r4Conditions
        ))
        if r4Fired {
            return (BoundaryTrigger(type: .cta, sentenceIndex: position, confidence: .high), evaluations)
        }

        // Rule 5: Contrast + Question (MEDIUM)
        let r5c1 = current.hasContrastMarker
        let r5c2 = current.stance == "questioning"
        let r5Fired = r5c1 && r5c2
        evaluations.append(RuleEvaluation(
            ruleNumber: 5, ruleName: "Contrast+Question",
            ruleConfidence: .medium, fired: r5Fired,
            conditions: [
                .init(fieldName: "current.hasContrastMarker",
                      actualValue: "\(current.hasContrastMarker)",
                      requiredValue: "true", passed: r5c1),
                .init(fieldName: "current.stance",
                      actualValue: "\"\(current.stance)\"",
                      requiredValue: "\"questioning\"", passed: r5c2)
            ]
        ))
        if r5Fired {
            return (BoundaryTrigger(type: .contrastQuestion, sentenceIndex: position, confidence: .medium), evaluations)
        }

        // Rule 6: Reveal (MEDIUM, compound with position gate)
        let r6c1 = current.hasRevealLanguage
        let r6c2 = relativePosition > params.revealPositionThreshold
        let r6c3 = current.hasFirstPerson || current.isTransition
        let r6Fired = r6c1 && r6c2 && r6c3
        evaluations.append(RuleEvaluation(
            ruleNumber: 6, ruleName: "Reveal language",
            ruleConfidence: .medium, fired: r6Fired,
            conditions: [
                .init(fieldName: "current.hasRevealLanguage",
                      actualValue: "\(current.hasRevealLanguage)",
                      requiredValue: "true", passed: r6c1),
                .init(fieldName: "relativePosition > revealThreshold",
                      actualValue: String(format: "%.3f > %.1f", relativePosition, params.revealPositionThreshold),
                      requiredValue: "true", passed: r6c2),
                .init(fieldName: "current.hasFirstPerson OR current.isTransition",
                      actualValue: "hasFirstPerson=\(current.hasFirstPerson), isTransition=\(current.isTransition)",
                      requiredValue: "either true", passed: r6c3)
            ]
        ))
        if r6Fired {
            return (BoundaryTrigger(type: .reveal, sentenceIndex: position, confidence: .medium), evaluations)
        }

        // Rule 7: Perspective Shift (MEDIUM)
        let r7c1 = previous.perspective == "third"
        let r7c2 = current.perspective == "first"
        let r7c3 = current.hasFirstPerson
        let r7c4 = current.stance == "questioning"
        let r7Fired = r7c1 && r7c2 && r7c3 && r7c4
        evaluations.append(RuleEvaluation(
            ruleNumber: 7, ruleName: "Perspective shift (3rd->1st+question)",
            ruleConfidence: .medium, fired: r7Fired,
            conditions: [
                .init(fieldName: "previous.perspective",
                      actualValue: "\"\(previous.perspective)\"",
                      requiredValue: "\"third\"", passed: r7c1),
                .init(fieldName: "current.perspective",
                      actualValue: "\"\(current.perspective)\"",
                      requiredValue: "\"first\"", passed: r7c2),
                .init(fieldName: "current.hasFirstPerson",
                      actualValue: "\(current.hasFirstPerson)",
                      requiredValue: "true", passed: r7c3),
                .init(fieldName: "current.stance",
                      actualValue: "\"\(current.stance)\"",
                      requiredValue: "\"questioning\"", passed: r7c4)
            ]
        ))
        if r7Fired {
            return (BoundaryTrigger(type: .perspectiveShift, sentenceIndex: position, confidence: .medium), evaluations)
        }

        return (nil, evaluations)
    }

    // MARK: - Chunk Building

    /// Convert boundary indices into chunk objects with metadata
    private func buildChunks(
        sentences: [SentenceTelemetry],
        boundaries: [Int],
        triggers: [BoundaryTrigger?]
    ) -> [Chunk] {
        var chunks: [Chunk] = []

        for i in 0..<boundaries.count {
            let start = boundaries[i]
            let end = i + 1 < boundaries.count ? boundaries[i + 1] - 1 : sentences.count - 1

            let chunkSentences = Array(sentences[start...end])

            let chunk = Chunk(
                chunkIndex: i,
                startSentence: start,
                endSentence: end,
                sentences: chunkSentences,
                profile: calculateProfile(sentences: chunkSentences, trigger: triggers[i]),
                positionInVideo: Double(start) / Double(sentences.count),
                sentenceCount: chunkSentences.count
            )

            chunks.append(chunk)
        }

        return chunks
    }

    // MARK: - Profile Calculation

    /// Calculate aggregate metadata for a chunk
    private func calculateProfile(
        sentences: [SentenceTelemetry],
        trigger: BoundaryTrigger?
    ) -> ChunkProfile {
        let n = Double(sentences.count)
        guard n > 0 else {
            return ChunkProfile(
                dominantPerspective: .mixed,
                dominantStance: .mixed,
                tagDensity: TagDensity(
                    hasNumber: 0, hasStatistic: 0, hasNamedEntity: 0, hasQuote: 0,
                    hasContrastMarker: 0, hasRevealLanguage: 0, hasChallengeLanguage: 0,
                    hasFirstPerson: 0, hasSecondPerson: 0, isTransition: 0,
                    isSponsorContent: 0, isCallToAction: 0
                ),
                boundaryTrigger: trigger
            )
        }

        // Count tag occurrences
        var tagCounts: [String: Int] = [
            "hasNumber": 0, "hasStatistic": 0, "hasNamedEntity": 0, "hasQuote": 0,
            "hasContrastMarker": 0, "hasRevealLanguage": 0, "hasChallengeLanguage": 0,
            "hasFirstPerson": 0, "hasSecondPerson": 0, "isTransition": 0,
            "isSponsorContent": 0, "isCallToAction": 0
        ]

        var perspectiveCounts: [String: Int] = ["first": 0, "second": 0, "third": 0]
        var stanceCounts: [String: Int] = ["asserting": 0, "questioning": 0, "challenging": 0, "neutral": 0]

        for sent in sentences {
            if sent.hasNumber { tagCounts["hasNumber"]! += 1 }
            if sent.hasStatistic { tagCounts["hasStatistic"]! += 1 }
            if sent.hasNamedEntity { tagCounts["hasNamedEntity"]! += 1 }
            if sent.hasQuote { tagCounts["hasQuote"]! += 1 }
            if sent.hasContrastMarker { tagCounts["hasContrastMarker"]! += 1 }
            if sent.hasRevealLanguage { tagCounts["hasRevealLanguage"]! += 1 }
            if sent.hasChallengeLanguage { tagCounts["hasChallengeLanguage"]! += 1 }
            if sent.hasFirstPerson { tagCounts["hasFirstPerson"]! += 1 }
            if sent.hasSecondPerson { tagCounts["hasSecondPerson"]! += 1 }
            if sent.isTransition { tagCounts["isTransition"]! += 1 }
            if sent.isSponsorContent { tagCounts["isSponsorContent"]! += 1 }
            if sent.isCallToAction { tagCounts["isCallToAction"]! += 1 }

            perspectiveCounts[sent.perspective, default: 0] += 1
            stanceCounts[sent.stance, default: 0] += 1
        }

        // Calculate tag density
        let tagDensity = TagDensity(
            hasNumber: Double(tagCounts["hasNumber"]!) / n,
            hasStatistic: Double(tagCounts["hasStatistic"]!) / n,
            hasNamedEntity: Double(tagCounts["hasNamedEntity"]!) / n,
            hasQuote: Double(tagCounts["hasQuote"]!) / n,
            hasContrastMarker: Double(tagCounts["hasContrastMarker"]!) / n,
            hasRevealLanguage: Double(tagCounts["hasRevealLanguage"]!) / n,
            hasChallengeLanguage: Double(tagCounts["hasChallengeLanguage"]!) / n,
            hasFirstPerson: Double(tagCounts["hasFirstPerson"]!) / n,
            hasSecondPerson: Double(tagCounts["hasSecondPerson"]!) / n,
            isTransition: Double(tagCounts["isTransition"]!) / n,
            isSponsorContent: Double(tagCounts["isSponsorContent"]!) / n,
            isCallToAction: Double(tagCounts["isCallToAction"]!) / n
        )

        // Find dominant perspective
        let dominantPerspective = findDominant(
            counts: perspectiveCounts,
            total: sentences.count,
            threshold: 0.5
        )

        // Find dominant stance
        let dominantStance = findDominantStance(
            counts: stanceCounts,
            total: sentences.count,
            threshold: 0.5
        )

        return ChunkProfile(
            dominantPerspective: dominantPerspective,
            dominantStance: dominantStance,
            tagDensity: tagDensity,
            boundaryTrigger: trigger
        )
    }

    /// Find dominant perspective
    private func findDominant(
        counts: [String: Int],
        total: Int,
        threshold: Double
    ) -> ChunkProfile.DominantValue {
        guard total > 0 else { return .mixed }

        let sorted = counts.sorted { $0.value > $1.value }
        guard let top = sorted.first else { return .mixed }

        if Double(top.value) / Double(total) >= threshold {
            switch top.key {
            case "first": return .first
            case "second": return .second
            case "third": return .third
            default: return .mixed
            }
        }
        return .mixed
    }

    /// Find dominant stance
    private func findDominantStance(
        counts: [String: Int],
        total: Int,
        threshold: Double
    ) -> ChunkProfile.DominantValue {
        guard total > 0 else { return .mixed }

        let sorted = counts.sorted { $0.value > $1.value }
        guard let top = sorted.first else { return .mixed }

        if Double(top.value) / Double(total) >= threshold {
            switch top.key {
            case "asserting": return .asserting
            case "questioning": return .questioning
            case "challenging": return .challenging
            case "neutral": return .neutral
            default: return .mixed
            }
        }
        return .mixed
    }

    // MARK: - Analysis Helpers

    /// Generate a text report of the boundary detection
    func generateReport(for result: BoundaryDetectionResult) -> String {
        var report = """
        ════════════════════════════════════════════════════════════════
        BOUNDARY DETECTION REPORT
        ════════════════════════════════════════════════════════════════

        Video: \(result.videoTitle)
        Total Sentences: \(result.totalSentences)
        Chunks Detected: \(result.chunkCount)
        Average Chunk Size: \(String(format: "%.1f", result.averageChunkSize)) sentences

        BOUNDARY TRIGGERS:
        """

        for (type, count) in result.triggerDistribution.sorted(by: { $0.value > $1.value }) {
            report += "\n  • \(type.displayName): \(count)"
        }

        report += "\n\n────────────────────────────────────────────────────────────────\n"
        report += "CHUNKS\n"
        report += "────────────────────────────────────────────────────────────────\n\n"

        for chunk in result.chunks {
            let triggerInfo = chunk.profile.boundaryTrigger.map {
                "[\($0.type.displayName) - \($0.confidence.rawValue)]"
            } ?? "[START]"

            report += """
            CHUNK \(chunk.chunkIndex) \(triggerInfo)
            Position: \(chunk.positionLabel) | Sentences: \(chunk.startSentence)-\(chunk.endSentence) (\(chunk.sentenceCount))
            Perspective: \(chunk.profile.dominantPerspective.rawValue) | Stance: \(chunk.profile.dominantStance.rawValue)
            Top Tags: \(chunk.profile.tagDensity.topTags.map { "\($0.name) \(Int($0.value * 100))%" }.joined(separator: ", "))

            Preview: \(String(chunk.preview.prefix(150)))...

            """
        }

        report += "\n════════════════════════════════════════════════════════════════\n"
        return report
    }

    /// Export chunks as copyable text (for use in prompts)
    func exportChunksAsText(_ chunks: [Chunk]) -> String {
        chunks.enumerated().map { index, chunk in
            """
            --- CHUNK \(index + 1) [\(chunk.positionLabel)] ---
            \(chunk.fullText)
            """
        }.joined(separator: "\n\n")
    }

    // MARK: - Deep Dive Debug (Audit Trail)

    /// Run boundary detection in audit mode, capturing full evaluation trace
    func generateAuditTrail(
        from sentences: [SentenceTelemetry],
        videoTitle: String = "",
        params: BoundaryDetectionParams = .default
    ) -> BoundaryAuditTrail {
        guard !sentences.isEmpty else {
            return BoundaryAuditTrail(videoTitle: videoTitle, totalSentences: 0, params: params, records: [])
        }

        var records: [SentenceAuditRecord] = []
        var lastBoundary = 0
        let total = sentences.count

        // Sentence 0 is always a boundary start
        records.append(SentenceAuditRecord(
            sentenceIndex: 0, current: sentences[0], previous: nil,
            distanceFromLastBoundary: 0, minChunkSizeRequired: params.minChunkSize,
            wasSuppressedByMinChunkSize: false, suppressedTriggerType: nil,
            relativePosition: 0.0, rulesEvaluated: [], firedTrigger: nil, wasBoundary: true
        ))

        for i in 1..<sentences.count {
            let current = sentences[i]
            let previous = sentences[i - 1]
            let distance = i - lastBoundary
            let relPos = Double(i) / Double(total)

            if distance < params.minChunkSize {
                // Still evaluate to detect suppressions
                let (hypotheticalTrigger, rules) = auditCheckBoundary(
                    current: current, previous: previous,
                    position: i, total: total, params: params
                )
                records.append(SentenceAuditRecord(
                    sentenceIndex: i, current: current, previous: previous,
                    distanceFromLastBoundary: distance,
                    minChunkSizeRequired: params.minChunkSize,
                    wasSuppressedByMinChunkSize: hypotheticalTrigger != nil,
                    suppressedTriggerType: hypotheticalTrigger?.type,
                    relativePosition: relPos,
                    rulesEvaluated: hypotheticalTrigger != nil ? rules : [],
                    firedTrigger: nil, wasBoundary: false
                ))
                continue
            }

            let (trigger, rules) = auditCheckBoundary(
                current: current, previous: previous,
                position: i, total: total, params: params
            )

            if trigger != nil {
                lastBoundary = i
            }

            records.append(SentenceAuditRecord(
                sentenceIndex: i, current: current, previous: previous,
                distanceFromLastBoundary: distance,
                minChunkSizeRequired: params.minChunkSize,
                wasSuppressedByMinChunkSize: false,
                suppressedTriggerType: nil,
                relativePosition: relPos,
                rulesEvaluated: rules,
                firedTrigger: trigger,
                wasBoundary: trigger != nil
            ))
        }

        return BoundaryAuditTrail(
            videoTitle: videoTitle, totalSentences: sentences.count,
            params: params, records: records
        )
    }

    // MARK: - Deep Dive Report Generation

    /// Generate deep dive debug report answering WHAT/WHAT/WHY per CLAUDE.md
    /// Chronological timeline: boundaries get full detail, everything else is a compact one-liner.
    func generateDeepDiveReport(
        from fidelityTest: SentenceFidelityTest,
        params: BoundaryDetectionParams = .default
    ) -> String {
        let audit = generateAuditTrail(
            from: fidelityTest.sentences,
            videoTitle: fidelityTest.videoTitle,
            params: params
        )
        var lines: [String] = []

        lines.append("════════════════════════════════════════════════════════════════")
        lines.append("DEEP DIVE DEBUG — BOUNDARY DETECTION")
        lines.append("════════════════════════════════════════════════════════════════")
        lines.append("Video: \(audit.videoTitle)")
        lines.append("Total Sentences: \(audit.totalSentences)")
        lines.append("Params: minChunkSize=\(params.minChunkSize), revealThreshold=\(params.revealPositionThreshold), endCTAThreshold=\(params.endCTAThreshold), suppressEndCTAs=\(params.suppressEndCTAs), boundaryOnSponsorExit=\(params.boundaryOnSponsorExit)")
        lines.append("Boundaries: \(audit.boundaries.count) | Suppressions: \(audit.suppressions.count)")
        lines.append("")
        lines.append("────────────────────────────────────────────────────────────────")
        lines.append("SENTENCE TIMELINE")
        lines.append("────────────────────────────────────────────────────────────────")

        // Chronological: every sentence in order
        for record in audit.records {
            if record.wasBoundary {
                // Full deep dive for boundaries
                lines.append(formatBoundaryRecord(record, totalSentences: audit.totalSentences))
            } else if record.wasSuppressedByMinChunkSize {
                // One-liner noting suppression
                lines.append(formatSuppressionRecord(record))
            } else {
                // Compact one-liner for non-triggering sentences
                let preview = String(record.current.text.prefix(55))
                lines.append("[\(record.sentenceIndex)] ~ \"\(preview)...\" | \(record.current.stance) \(record.current.perspective)")
            }
        }

        lines.append("")
        lines.append("════════════════════════════════════════════════════════════════")
        lines.append("END OF DEEP DIVE DEBUG")
        lines.append("════════════════════════════════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting Helpers

    private func formatBoundaryRecord(_ record: SentenceAuditRecord, totalSentences: Int) -> String {
        var lines: [String] = []

        if record.sentenceIndex == 0 {
            lines.append("")
            lines.append("--- BOUNDARY at Sentence 0 [START] ---")
            lines.append("  WHAT DECIDED: First sentence always starts a chunk")
            lines.append("")
            lines.append("  WHAT -- SENTENCE [0]:")
            lines.append(formatTelemetry(record.current, highlightFields: []))
            return lines.joined(separator: "\n")
        }

        guard let trigger = record.firedTrigger else { return "" }

        lines.append("")
        lines.append("═══ BOUNDARY at Sentence \(record.sentenceIndex) ═══")
        lines.append("  WHAT DECIDED: \(trigger.type.displayName) (\(trigger.confidence.rawValue.uppercased()) confidence)")
        lines.append("")

        // Triggering sentence telemetry
        let triggerFields = fieldsForTriggerType(trigger.type)
        lines.append("  WHAT -- TRIGGERING SENTENCE [\(record.sentenceIndex)]:")
        lines.append(formatTelemetry(record.current, highlightFields: triggerFields))

        // Previous sentence telemetry
        if let prev = record.previous {
            lines.append("")
            lines.append("  WHAT -- PREVIOUS SENTENCE [\(record.sentenceIndex - 1)]:")
            lines.append(formatTelemetry(prev, highlightFields: []))
        }

        // Rule evaluation trace
        lines.append("")
        lines.append("  WHY -- RULE EVALUATION TRACE:")
        for rule in record.rulesEvaluated {
            let statusMark = rule.fired ? "TRUE" : "FALSE"
            let ruleLine = "  [\(rule.ruleNumber)] "
                + rule.ruleName.padding(toLength: 38, withPad: " ", startingAt: 0)
                + " -> \(statusMark)"
            lines.append(ruleLine)

            if rule.fired {
                // Show the passing conditions that caused the fire
                for cond in rule.conditions {
                    let mark = cond.passed ? "+" : "x"
                    lines.append("      \(mark) \(cond.fieldName)=\(cond.actualValue) (need: \(cond.requiredValue))")
                }
                let firedAt = rule.ruleNumber
                if firedAt < 7 {
                    lines.append("  --- FIRED at rule \(firedAt), rules \(firedAt + 1)-7 not evaluated ---")
                }
            } else {
                // Show which conditions failed for this non-firing rule
                let failedConds = rule.conditions.filter { !$0.passed }
                if !failedConds.isEmpty {
                    let failSummary = failedConds.map { "\($0.fieldName)=\($0.actualValue)" }.joined(separator: ", ")
                    lines.append("      failed: \(failSummary)")
                }
            }
        }

        // Position context
        lines.append("")
        lines.append("  WHY -- POSITION CONTEXT:")
        let pct = String(format: "%.1f", record.relativePosition * 100)
        lines.append("    Sentence \(record.sentenceIndex) of \(totalSentences) (\(pct)%)")
        lines.append("    Gap from last boundary: \(record.distanceFromLastBoundary) sentences (min required: \(record.minChunkSizeRequired))")

        return lines.joined(separator: "\n")
    }

    private func formatSuppressionRecord(_ record: SentenceAuditRecord) -> String {
        let triggerName = record.suppressedTriggerType?.displayName ?? "unknown"
        let preview = String(record.current.text.prefix(45))
        return "[\(record.sentenceIndex)] SUPPRESSED [\(triggerName)] gap=\(record.distanceFromLastBoundary)/\(record.minChunkSizeRequired) \"\(preview)...\""
    }

    /// Format all 21 telemetry fields for a sentence
    private func formatTelemetry(_ s: SentenceTelemetry, highlightFields: Set<String>) -> String {
        var lines: [String] = []
        lines.append("    Text: \"\(String(s.text.prefix(150)))\"")

        // Identity
        lines.append("    sentenceIndex=\(s.sentenceIndex), positionPercentile=\(String(format: "%.3f", s.positionPercentile)), wordCount=\(s.wordCount)")

        // Surface structure
        let hasNumStr = highlightFields.contains("hasNumber") ? boolUpper(s.hasNumber) : "\(s.hasNumber)"
        lines.append("    hasNumber=\(hasNumStr), endsWithQuestion=\(s.endsWithQuestion), endsWithExclamation=\(s.endsWithExclamation)")

        // Lexical signals
        let contrastStr = highlightFields.contains("hasContrastMarker") ? boolUpper(s.hasContrastMarker) : "\(s.hasContrastMarker)"
        let firstPStr = highlightFields.contains("hasFirstPerson") ? boolUpper(s.hasFirstPerson) : "\(s.hasFirstPerson)"
        lines.append("    hasContrastMarker=\(contrastStr), hasTemporalMarker=\(s.hasTemporalMarker), hasFirstPerson=\(firstPStr), hasSecondPerson=\(s.hasSecondPerson)")

        // Content markers
        lines.append("    hasStatistic=\(s.hasStatistic), hasQuote=\(s.hasQuote), hasNamedEntity=\(s.hasNamedEntity)")

        // Rhetorical markers
        let revealStr = highlightFields.contains("hasRevealLanguage") ? boolUpper(s.hasRevealLanguage) : "\(s.hasRevealLanguage)"
        lines.append("    hasRevealLanguage=\(revealStr), hasPromiseLanguage=\(s.hasPromiseLanguage), hasChallengeLanguage=\(s.hasChallengeLanguage)")

        // Stance & Perspective
        let stanceStr = highlightFields.contains("stance") ? s.stance.uppercased() : s.stance
        let perspStr = highlightFields.contains("perspective") ? s.perspective.uppercased() : s.perspective
        lines.append("    stance=\(stanceStr), perspective=\(perspStr)")

        // Structural markers
        let transStr = highlightFields.contains("isTransition") ? boolUpper(s.isTransition) : "\(s.isTransition)"
        let sponsorStr = highlightFields.contains("isSponsorContent") ? boolUpper(s.isSponsorContent) : "\(s.isSponsorContent)"
        let ctaStr = highlightFields.contains("isCallToAction") ? boolUpper(s.isCallToAction) : "\(s.isCallToAction)"
        lines.append("    isTransition=\(transStr), isSponsorContent=\(sponsorStr), isCallToAction=\(ctaStr)")

        return lines.joined(separator: "\n")
    }

    /// Returns uppercase TRUE/FALSE for highlighted fields
    private func boolUpper(_ val: Bool) -> String {
        val ? "TRUE" : "FALSE"
    }

    /// Map trigger type to the telemetry field names that contribute to it
    private func fieldsForTriggerType(_ type: BoundaryTrigger.BoundaryTriggerType) -> Set<String> {
        switch type {
        case .transition:
            return ["isTransition"]
        case .sponsor:
            return ["isSponsorContent"]
        case .cta:
            return ["isCallToAction"]
        case .contrastQuestion:
            return ["hasContrastMarker", "stance"]
        case .reveal:
            return ["hasRevealLanguage", "hasFirstPerson", "isTransition"]
        case .perspectiveShift:
            return ["perspective", "hasFirstPerson", "stance"]
        }
    }
}
