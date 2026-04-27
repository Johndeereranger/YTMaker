import Foundation

/// LLM verification for ambiguous digressions + context enrichment for all digressions
/// Role A: Verify ambiguous cases (entry found but no clean exit, unusual patterns)
/// Role B: Enrich context fields (surroundingNarrativeThread, briefContent) on demand
class DigressionLLMEscalator {

    static let shared = DigressionLLMEscalator()

    private init() {}

    // MARK: - Role A: Ambiguous Case Verification

    /// Identifies sentences that should be escalated to LLM for verification
    func identifyEscalationCandidates(
        sentences: [SentenceTelemetry],
        existingDigressions: [DigressionAnnotation]
    ) -> [EscalationCandidate] {
        var candidates: [EscalationCandidate] = []

        // 1. Low-confidence detections (entry found, exit by maxScan)
        for digression in existingDigressions where digression.confidence <= 0.5 {
            candidates.append(EscalationCandidate(
                reason: .maxScanTimeout,
                sentenceRange: digression.startSentence...digression.endSentence,
                existingAnnotation: digression,
                description: "\(digression.type.displayName) at s\(digression.startSentence): exit by maxScan, needs verification"
            ))
        }

        // 2. First-person spike in third-person narrative (no entry marker found)
        let digressionIndices = Set(existingDigressions.flatMap { Array($0.sentenceRange) })
        var consecutiveFirstPerson = 0
        var spikeStart = -1

        for i in 0..<sentences.count {
            guard !digressionIndices.contains(i) else {
                consecutiveFirstPerson = 0
                spikeStart = -1
                continue
            }

            if sentences[i].hasFirstPerson && sentences[i].perspective == "first" {
                if consecutiveFirstPerson == 0 { spikeStart = i }
                consecutiveFirstPerson += 1

                if consecutiveFirstPerson > 3 {
                    // Check surrounding context is third-person
                    let before = max(0, spikeStart - 2)
                    let surroundingThirdPerson = (before..<spikeStart).allSatisfy {
                        sentences[$0].perspective == "third"
                    }

                    if surroundingThirdPerson {
                        candidates.append(EscalationCandidate(
                            reason: .firstPersonSpike,
                            sentenceRange: spikeStart...i,
                            existingAnnotation: nil,
                            description: "First-person spike s\(spikeStart)-\(i) in third-person narrative"
                        ))
                    }
                }
            } else {
                consecutiveFirstPerson = 0
                spikeStart = -1
            }
        }

        // 3. CTA mid-video outside sponsor sections
        for i in 0..<sentences.count {
            guard !digressionIndices.contains(i) else { continue }
            let s = sentences[i]
            if s.isCallToAction && !s.isSponsorContent && s.positionPercentile > 0.1 && s.positionPercentile < 0.85 {
                candidates.append(EscalationCandidate(
                    reason: .midVideoCTA,
                    sentenceRange: i...i,
                    existingAnnotation: nil,
                    description: "Mid-video CTA at s\(i) (position \(String(format: "%.0f%%", s.positionPercentile * 100)))"
                ))
            }
        }

        // 4. Mixed-perspective chunk >20 sentences
        var chunkStart = 0
        for i in 1..<sentences.count {
            guard !digressionIndices.contains(i) else {
                chunkStart = i + 1
                continue
            }

            if i - chunkStart >= 20 {
                let chunk = Array(sentences[chunkStart...i])
                let perspectives = Set(chunk.map(\.perspective))
                if perspectives.count >= 3 {
                    candidates.append(EscalationCandidate(
                        reason: .mixedPerspectiveChunk,
                        sentenceRange: chunkStart...i,
                        existingAnnotation: nil,
                        description: "Mixed-perspective chunk s\(chunkStart)-\(i) (\(i - chunkStart + 1) sentences, \(perspectives.count) perspectives)"
                    ))
                    chunkStart = i + 1
                }
            }
        }

        return candidates
    }

    /// Escalate ambiguous candidates to LLM for verification
    func escalateAmbiguous(
        candidates: [EscalationCandidate],
        sentences: [SentenceTelemetry],
        temperature: Double = 0.3,
        maxConcurrent: Int = 5,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> [DigressionAnnotation] {
        guard !candidates.isEmpty else { return [] }

        var results: [Int: DigressionAnnotation?] = [:]
        var completedCount = 0
        let lock = NSLock()

        await withTaskGroup(of: (Int, DigressionAnnotation?).self) { group in
            var iterator = candidates.enumerated().makeIterator()

            // Start initial batch with stagger
            for i in 0..<min(maxConcurrent, candidates.count) {
                if let (index, candidate) = iterator.next() {
                    let delayNs = UInt64(i) * 500_000_000
                    group.addTask {
                        if delayNs > 0 {
                            try? await Task.sleep(nanoseconds: delayNs)
                        }
                        let result = await self.verifyCandidate(candidate, sentences: sentences, temperature: temperature)
                        return (index, result)
                    }
                }
            }

            // Sliding window: as each completes, start next
            for await (index, result) in group {
                lock.lock()
                results[index] = result
                completedCount += 1
                let count = completedCount
                lock.unlock()

                await MainActor.run {
                    onProgress?(count, candidates.count)
                }

                if let (nextIndex, nextCandidate) = iterator.next() {
                    group.addTask {
                        let result = await self.verifyCandidate(nextCandidate, sentences: sentences, temperature: temperature)
                        return (nextIndex, result)
                    }
                }
            }
        }

        return (0..<candidates.count).compactMap { results[$0] ?? nil }
    }

    private func verifyCandidate(
        _ candidate: EscalationCandidate,
        sentences: [SentenceTelemetry],
        temperature: Double
    ) async -> DigressionAnnotation? {
        let range = candidate.sentenceRange
        let contextBefore = max(0, range.lowerBound - 3)
        let contextAfter = min(sentences.count - 1, range.upperBound + 3)

        let contextSentences = sentences[contextBefore...contextAfter]
        let numberedText = contextSentences.map { s in
            let marker = range.contains(s.sentenceIndex) ? ">>>" : "   "
            return "\(marker) [s\(s.sentenceIndex)] \(s.text)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are analyzing a YouTube video transcript for narrative digressions.
        A digression is when the narrator temporarily leaves the main narrative thread \
        for a personal aside, sponsor read, meta commentary, tangent, moral correction, \
        self-promotion, or foreshadowing plant.
        """

        let userPrompt = """
        The sentences marked with >>> have been flagged as a potential digression.
        Reason for flagging: \(candidate.description)

        Context:
        \(numberedText)

        Is this a digression? If so, what type?
        Respond in this exact format:
        IS_DIGRESSION: true/false
        TYPE: personalAside/sponsorRead/metaCommentary/tangent/moralCorrection/selfPromotion/foreshadowingPlant
        START_SENTENCE: <number>
        END_SENTENCE: <number>
        CONFIDENCE: <0.0-1.0>
        BRIEF: <20-40 word summary of the digression content>
        """

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 200]
        )

        return parseLLMVerification(response, candidate: candidate, sentences: sentences)
    }

    private func parseLLMVerification(
        _ response: String,
        candidate: EscalationCandidate,
        sentences: [SentenceTelemetry]
    ) -> DigressionAnnotation? {
        let lines = response.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        guard let isDigressionLine = lines.first(where: { $0.hasPrefix("IS_DIGRESSION:") }),
              isDigressionLine.contains("true") else {
            return nil
        }

        let typeLine = lines.first(where: { $0.hasPrefix("TYPE:") }) ?? ""
        let typeStr = typeLine.replacingOccurrences(of: "TYPE:", with: "").trimmingCharacters(in: .whitespaces)
        let type = DigressionType(rawValue: typeStr) ?? candidate.existingAnnotation?.type ?? .tangent

        let startLine = lines.first(where: { $0.hasPrefix("START_SENTENCE:") }) ?? ""
        let startStr = startLine.replacingOccurrences(of: "START_SENTENCE:", with: "").trimmingCharacters(in: .whitespaces)
        let start = Int(startStr) ?? candidate.sentenceRange.lowerBound

        let endLine = lines.first(where: { $0.hasPrefix("END_SENTENCE:") }) ?? ""
        let endStr = endLine.replacingOccurrences(of: "END_SENTENCE:", with: "").trimmingCharacters(in: .whitespaces)
        let end = Int(endStr) ?? candidate.sentenceRange.upperBound

        let confLine = lines.first(where: { $0.hasPrefix("CONFIDENCE:") }) ?? ""
        let confStr = confLine.replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespaces)
        let confidence = Double(confStr) ?? 0.6

        let briefLine = lines.first(where: { $0.hasPrefix("BRIEF:") }) ?? ""
        let brief = briefLine.replacingOccurrences(of: "BRIEF:", with: "").trimmingCharacters(in: .whitespaces)

        let clampedStart = max(0, min(start, sentences.count - 1))
        let clampedEnd = max(clampedStart, min(end, sentences.count - 1))

        let digressionSentences = Array(sentences[clampedStart...clampedEnd])
        let hasCTA = digressionSentences.contains { $0.isCallToAction }
        let perspectiveShift = Set(digressionSentences.map(\.perspective)).count > 1
        let stanceShift = Set(digressionSentences.map(\.stance)).count > 1

        let method: DigressionDetectionMethod = candidate.existingAnnotation != nil ? .hybrid : .llm

        return DigressionAnnotation(
            startSentence: clampedStart,
            endSentence: clampedEnd,
            entryMarker: candidate.existingAnnotation?.entryMarker ?? "LLM detected",
            exitMarker: "LLM verified (end s\(clampedEnd))",
            type: type,
            confidence: confidence,
            detectionMethod: method,
            surroundingNarrativeThread: nil,
            briefContent: brief.isEmpty ? nil : brief,
            hasCTA: hasCTA,
            perspectiveShift: perspectiveShift,
            stanceShift: stanceShift
        )
    }

    // MARK: - Role B: Context Enrichment

    /// Enrich detected digressions with surroundingNarrativeThread and briefContent
    /// Called on-demand via "Enrich Context" button in the detection view
    func enrichDigressionContext(
        sentences: [SentenceTelemetry],
        digressions: [DigressionAnnotation],
        temperature: Double = 0.3,
        maxConcurrent: Int = 5,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> [DigressionAnnotation] {
        guard !digressions.isEmpty else { return digressions }

        var enriched: [Int: DigressionAnnotation] = [:]
        var completedCount = 0
        let lock = NSLock()

        await withTaskGroup(of: (Int, DigressionAnnotation).self) { group in
            var iterator = digressions.enumerated().makeIterator()

            for i in 0..<min(maxConcurrent, digressions.count) {
                if let (index, digression) = iterator.next() {
                    let delayNs = UInt64(i) * 500_000_000
                    group.addTask {
                        if delayNs > 0 {
                            try? await Task.sleep(nanoseconds: delayNs)
                        }
                        let result = await self.enrichSingle(digression, sentences: sentences, temperature: temperature)
                        return (index, result)
                    }
                }
            }

            for await (index, result) in group {
                lock.lock()
                enriched[index] = result
                completedCount += 1
                let count = completedCount
                lock.unlock()

                await MainActor.run {
                    onProgress?(count, digressions.count)
                }

                if let (nextIndex, nextDigression) = iterator.next() {
                    group.addTask {
                        let result = await self.enrichSingle(nextDigression, sentences: sentences, temperature: temperature)
                        return (nextIndex, result)
                    }
                }
            }
        }

        return (0..<digressions.count).map { enriched[$0] ?? digressions[$0] }
    }

    private func enrichSingle(
        _ digression: DigressionAnnotation,
        sentences: [SentenceTelemetry],
        temperature: Double
    ) async -> DigressionAnnotation {
        let contextBefore = max(0, digression.startSentence - 3)
        let contextAfter = min(sentences.count - 1, digression.endSentence + 3)

        let beforeText = sentences[contextBefore..<digression.startSentence]
            .map { "[s\($0.sentenceIndex)] \($0.text)" }
            .joined(separator: "\n")

        let digressionText = sentences[digression.startSentence...digression.endSentence]
            .map { "[s\($0.sentenceIndex)] \($0.text)" }
            .joined(separator: "\n")

        let afterText = sentences[(digression.endSentence + 1)...contextAfter]
            .map { "[s\($0.sentenceIndex)] \($0.text)" }
            .joined(separator: "\n")

        let systemPrompt = "You summarize narrative context around digressions in YouTube video transcripts."

        let userPrompt = """
        A \(digression.type.displayName) digression was detected at sentences \(digression.startSentence)-\(digression.endSentence).

        BEFORE the digression:
        \(beforeText.isEmpty ? "(start of transcript)" : beforeText)

        THE DIGRESSION:
        \(digressionText)

        AFTER the digression:
        \(afterText.isEmpty ? "(end of transcript)" : afterText)

        Answer these two questions:
        1. NARRATIVE_THREAD: In 20-40 words, what was the main content doing before this interruption?
        2. BRIEF_CONTENT: In 20-40 words, summarize what this digression contains.
        """

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 200]
        )

        return parseEnrichmentResponse(response, digression: digression)
    }

    private func parseEnrichmentResponse(
        _ response: String,
        digression: DigressionAnnotation
    ) -> DigressionAnnotation {
        var updated = digression

        let lines = response.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        if let narrativeLine = lines.first(where: { $0.hasPrefix("NARRATIVE_THREAD:") }) {
            let value = narrativeLine.replacingOccurrences(of: "NARRATIVE_THREAD:", with: "").trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { updated.surroundingNarrativeThread = value }
        }

        if let briefLine = lines.first(where: { $0.hasPrefix("BRIEF_CONTENT:") }) {
            let value = briefLine.replacingOccurrences(of: "BRIEF_CONTENT:", with: "").trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { updated.briefContent = value }
        }

        return updated
    }
}

// MARK: - Escalation Models

struct EscalationCandidate {
    let reason: EscalationReason
    let sentenceRange: ClosedRange<Int>
    let existingAnnotation: DigressionAnnotation?
    let description: String
}

enum EscalationReason: String {
    case maxScanTimeout
    case firstPersonSpike
    case midVideoCTA
    case mixedPerspectiveChunk

    var displayName: String {
        switch self {
        case .maxScanTimeout: return "MaxScan Timeout"
        case .firstPersonSpike: return "First-Person Spike"
        case .midVideoCTA: return "Mid-Video CTA"
        case .mixedPerspectiveChunk: return "Mixed Perspective Chunk"
        }
    }
}
