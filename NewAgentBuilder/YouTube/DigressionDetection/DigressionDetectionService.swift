import Foundation

/// Orchestration layer for digression detection
/// Coordinates deterministic rules + optional LLM escalation
class DigressionDetectionService {

    static let shared = DigressionDetectionService()

    private init() {}

    // MARK: - Main Detection

    /// Run full digression detection pipeline
    /// - Parameters:
    ///   - sentences: Tagged sentence telemetry from fidelity test
    ///   - config: Detection configuration (LLM toggle, enabled types, etc.)
    ///   - onProgress: Progress callback (current step, total steps, phase description)
    /// - Returns: Complete detection result with digressions and clean stream
    func detectDigressions(
        from sentences: [SentenceTelemetry],
        config: DigressionDetectionConfig = .default,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> DigressionDetectionResult {
        guard !sentences.isEmpty else {
            return DigressionDetectionResult(
                videoId: "",
                digressions: [],
                cleanSentenceIndices: Array(0..<sentences.count),
                totalSentences: sentences.count,
                config: config
            )
        }

        switch config.detectionMode {
        case .rulesFirst:
            return await detectRulesFirst(sentences: sentences, config: config, onProgress: onProgress)
        case .llmFirst:
            return await detectLLMFirst(sentences: sentences, config: config, onProgress: onProgress)
        }
    }

    // MARK: - Rules-First Pipeline (existing)

    private func detectRulesFirst(
        sentences: [SentenceTelemetry],
        config: DigressionDetectionConfig,
        onProgress: ((Int, Int, String) -> Void)?
    ) async -> DigressionDetectionResult {
        // Pass 1: Deterministic detection (synchronous)
        onProgress?(1, config.enableLLMEscalation ? 4 : 2, "Running deterministic detection...")

        var digressions = DigressionDetectorRules.shared.detectDigressions(
            from: sentences,
            enabledTypes: config.enabledTypes
        )

        // Pass 2: LLM escalation (async, optional)
        if config.enableLLMEscalation {
            onProgress?(2, 4, "Identifying escalation candidates...")

            let candidates = DigressionLLMEscalator.shared.identifyEscalationCandidates(
                sentences: sentences,
                existingDigressions: digressions
            )

            if !candidates.isEmpty {
                onProgress?(3, 4, "Escalating \(candidates.count) ambiguous cases to LLM...")

                let llmDigressions = await DigressionLLMEscalator.shared.escalateAmbiguous(
                    candidates: candidates,
                    sentences: sentences,
                    temperature: config.temperature,
                    maxConcurrent: config.maxConcurrentLLMCalls
                ) { current, total in
                    onProgress?(3, 4, "LLM escalation: \(current)/\(total)")
                }

                digressions = mergeDigressions(
                    deterministic: digressions,
                    llm: llmDigressions
                )
            }
        }

        // Filter by confidence threshold
        if config.minConfidenceThreshold > 0 {
            digressions = digressions.filter { $0.confidence >= config.minConfidenceThreshold }
        }

        // Build clean stream
        let phaseNum = config.enableLLMEscalation ? 4 : 2
        let phaseTotal = config.enableLLMEscalation ? 4 : 2
        onProgress?(phaseNum, phaseTotal, "Building clean stream...")

        let cleanIndices = buildCleanStream(
            totalSentences: sentences.count,
            digressions: digressions
        )

        return DigressionDetectionResult(
            videoId: "",
            digressions: digressions.sorted { $0.startSentence < $1.startSentence },
            cleanSentenceIndices: cleanIndices,
            totalSentences: sentences.count,
            config: config
        )
    }

    // MARK: - LLM-First Pipeline

    private func detectLLMFirst(
        sentences: [SentenceTelemetry],
        config: DigressionDetectionConfig,
        onProgress: ((Int, Int, String) -> Void)?
    ) async -> DigressionDetectionResult {
        // Phase 1: Send full transcript to LLM
        onProgress?(1, 3, "Sending transcript to Claude...")

        let digressions = await DigressionLLMDetector.shared.detectDigressions(
            sentences: sentences,
            enabledTypes: config.enabledTypes,
            temperature: config.temperature
        ) { phase in
            onProgress?(1, 3, phase)
        }

        // Phase 2: Rules validation (diagnostic)
        onProgress?(2, 3, "Checking \(digressions.count) detections with rules...")

        lastValidations = DigressionRulesValidator.shared.validate(
            digressions: digressions,
            sentences: sentences
        )

        // Phase 3: Build clean stream (all detections stay, including contradicted)
        onProgress?(3, 3, "Building clean stream...")

        let cleanIndices = buildCleanStream(
            totalSentences: sentences.count,
            digressions: digressions
        )

        return DigressionDetectionResult(
            videoId: "",
            digressions: digressions.sorted { $0.startSentence < $1.startSentence },
            cleanSentenceIndices: cleanIndices,
            totalSentences: sentences.count,
            config: config
        )
    }

    /// Most recent validation results from LLM-first mode
    private(set) var lastValidations: [ValidatedDigression] = []

    /// Convenience: detect with videoId
    func detectDigressions(
        videoId: String,
        from sentences: [SentenceTelemetry],
        config: DigressionDetectionConfig = .default,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> DigressionDetectionResult {
        var result = await detectDigressions(from: sentences, config: config, onProgress: onProgress)
        // Re-create with videoId since the base method doesn't have it
        return DigressionDetectionResult(
            videoId: videoId,
            digressions: result.digressions,
            cleanSentenceIndices: result.cleanSentenceIndices,
            totalSentences: result.totalSentences,
            config: result.config
        )
    }

    // MARK: - Clean Stream Builder

    /// Build array of sentence indices NOT in any digression range
    func buildCleanStream(
        totalSentences: Int,
        digressions: [DigressionAnnotation]
    ) -> [Int] {
        let digressionIndices = Set(digressions.flatMap { Array($0.sentenceRange) })
        return (0..<totalSentences).filter { !digressionIndices.contains($0) }
    }

    /// Build set of digression indices for use with excludeIndices parameters
    func buildExcludeSet(from digressions: [DigressionAnnotation]) -> Set<Int> {
        Set(digressions.flatMap { Array($0.sentenceRange) })
    }

    // MARK: - Chunk Annotation

    /// Map detected digressions onto boundary-detected chunks
    /// Use after boundary detection to annotate which chunks contain digressions
    func annotateChunksWithDigressions(
        chunks: [Chunk],
        digressions: [DigressionAnnotation]
    ) -> [(chunk: Chunk, containedDigressions: [DigressionAnnotation], isEntirelyDigression: Bool)] {
        chunks.map { chunk in
            let chunkRange = chunk.startSentence...chunk.endSentence

            let contained = digressions.filter { digression in
                // Digression overlaps with this chunk
                digression.sentenceRange.overlaps(chunkRange)
            }

            let chunkIndices = Set(Array(chunkRange))
            let digressionIndices = Set(contained.flatMap { Array($0.sentenceRange) })
            let isEntirelyDigression = !contained.isEmpty && chunkIndices.isSubset(of: digressionIndices)

            return (chunk: chunk, containedDigressions: contained, isEntirelyDigression: isEntirelyDigression)
        }
    }

    // MARK: - Boundary Confidence Boost

    /// Boost digression confidence when Section Splitter agrees a boundary exists nearby
    func boostConfidenceFromBoundaries(
        digressions: [DigressionAnnotation],
        boundaryIndices: Set<Int>,
        boostAmount: Double = 0.2,
        proximityThreshold: Int = 2
    ) -> [DigressionAnnotation] {
        digressions.map { digression in
            var updated = digression

            // Check if any boundary index is near the digression start or end
            let nearEntry = boundaryIndices.contains(where: {
                abs($0 - digression.startSentence) <= proximityThreshold
            })
            let nearExit = boundaryIndices.contains(where: {
                abs($0 - digression.endSentence) <= proximityThreshold
            })

            if nearEntry || nearExit {
                updated.confidence = min(1.0, updated.confidence + boostAmount)
            }

            return updated
        }
    }

    // MARK: - Merging

    /// Merge deterministic and LLM-detected digressions
    /// LLM results for existing annotations replace them (hybrid)
    /// New LLM detections are added
    private func mergeDigressions(
        deterministic: [DigressionAnnotation],
        llm: [DigressionAnnotation]
    ) -> [DigressionAnnotation] {
        var result = deterministic

        for llmDigression in llm {
            // Check if this overlaps with an existing deterministic detection
            if let existingIndex = result.firstIndex(where: { existing in
                existing.sentenceRange.overlaps(llmDigression.sentenceRange)
            }) {
                // Replace with hybrid result (LLM refined the boundaries/type)
                result[existingIndex] = llmDigression
            } else {
                // New detection from LLM
                result.append(llmDigression)
            }
        }

        return result.sorted { $0.startSentence < $1.startSentence }
    }
}
