import Foundation

/// Deterministic digression detection engine
/// Single forward pass state machine over [SentenceTelemetry]
/// No LLM calls — pure rule-based detection
class DigressionDetectorRules {

    static let shared = DigressionDetectorRules()

    private init() {}

    // MARK: - State Machine

    private enum DetectorState {
        case scanning
        case inDigression(type: DigressionType, startIndex: Int, entryMarker: String)
    }

    // MARK: - Main Detection

    func detectDigressions(
        from sentences: [SentenceTelemetry],
        enabledTypes: Set<DigressionType> = Set(DigressionType.allCases)
    ) -> [DigressionAnnotation] {
        guard !sentences.isEmpty else { return [] }

        var state: DetectorState = .scanning
        var results: [DigressionAnnotation] = []

        for i in 0..<sentences.count {
            let current = sentences[i]
            let previous: SentenceTelemetry? = i > 0 ? sentences[i - 1] : nil

            switch state {
            case .scanning:
                // Try entry detectors in priority order
                if let entry = checkEntryDetectors(
                    current: current,
                    previous: previous,
                    index: i,
                    totalSentences: sentences.count,
                    enabledTypes: enabledTypes
                ) {
                    state = .inDigression(
                        type: entry.type,
                        startIndex: i,
                        entryMarker: entry.marker
                    )
                }

            case .inDigression(let type, let startIndex, let entryMarker):
                let sentencesInDigression = i - startIndex + 1

                if let exitResult = checkExitDetector(
                    type: type,
                    current: current,
                    previous: previous,
                    sentencesInDigression: sentencesInDigression,
                    index: i,
                    sentences: sentences,
                    startIndex: startIndex
                ) {
                    // Determine end index: if exit triggered by current sentence changing back,
                    // the digression ends at the previous sentence
                    let endIndex = exitResult.endsAtPrevious ? i - 1 : i

                    // Only emit if meets minimum length
                    if endIndex >= startIndex && (endIndex - startIndex + 1) >= type.minLength {
                        let annotation = buildAnnotation(
                            type: type,
                            startIndex: startIndex,
                            endIndex: endIndex,
                            entryMarker: entryMarker,
                            exitMarker: exitResult.marker,
                            exitByMaxScan: exitResult.isMaxScan,
                            sentences: sentences
                        )
                        results.append(annotation)
                    }

                    state = .scanning

                    // Re-check this sentence for a new entry (adjacent digressions)
                    if exitResult.endsAtPrevious {
                        if let entry = checkEntryDetectors(
                            current: current,
                            previous: previous,
                            index: i,
                            totalSentences: sentences.count,
                            enabledTypes: enabledTypes
                        ) {
                            state = .inDigression(
                                type: entry.type,
                                startIndex: i,
                                entryMarker: entry.marker
                            )
                        }
                    }
                }
            }
        }

        // Handle unclosed digression at end of transcript
        if case .inDigression(let type, let startIndex, let entryMarker) = state {
            let endIndex = sentences.count - 1
            if (endIndex - startIndex + 1) >= type.minLength {
                let annotation = buildAnnotation(
                    type: type,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    entryMarker: entryMarker,
                    exitMarker: "end of transcript",
                    exitByMaxScan: true,
                    sentences: sentences
                )
                results.append(annotation)
            }
        }

        return results
    }

    // MARK: - Entry Detectors

    private struct EntryResult {
        let type: DigressionType
        let marker: String
    }

    private func checkEntryDetectors(
        current: SentenceTelemetry,
        previous: SentenceTelemetry?,
        index: Int,
        totalSentences: Int,
        enabledTypes: Set<DigressionType>
    ) -> EntryResult? {
        let text = current.text.lowercased()
        let position = current.positionPercentile

        // Check in priority order
        for type in DigressionType.byPriority {
            guard enabledTypes.contains(type) else { continue }

            switch type {
            case .sponsorRead:
                if let result = checkSponsorEntry(current: current, previous: previous, text: text) {
                    return result
                }
            case .personalAside:
                if let result = checkPersonalAsideEntry(current: current, previous: previous, text: text) {
                    return result
                }
            case .metaCommentary:
                if let result = checkMetaCommentaryEntry(current: current, text: text, position: position) {
                    return result
                }
            case .tangent:
                if let result = checkTangentEntry(current: current, previous: previous, text: text) {
                    return result
                }
            case .moralCorrection:
                if let result = checkMoralCorrectionEntry(current: current, text: text) {
                    return result
                }
            case .selfPromotion:
                if let result = checkSelfPromotionEntry(current: current, text: text, position: position) {
                    return result
                }
            case .foreshadowingPlant:
                if let result = checkForeshadowingEntry(text: text) {
                    return result
                }
            }
        }

        return nil
    }

    // MARK: Sponsor Entry

    private func checkSponsorEntry(
        current: SentenceTelemetry,
        previous: SentenceTelemetry?,
        text: String
    ) -> EntryResult? {
        // isSponsorContent flag when previous wasn't
        if current.isSponsorContent && !(previous?.isSponsorContent ?? false) {
            return EntryResult(type: .sponsorRead, marker: "isSponsorContent flag")
        }

        // Text pattern fallback
        let sponsorPatterns = ["sponsored by", "brought to you by"]
        for pattern in sponsorPatterns {
            if text.contains(pattern) {
                return EntryResult(type: .sponsorRead, marker: "text: \"\(pattern)\"")
            }
        }

        return nil
    }

    // MARK: Personal Aside Entry

    private func checkPersonalAsideEntry(
        current: SentenceTelemetry,
        previous: SentenceTelemetry?,
        text: String
    ) -> EntryResult? {
        guard current.hasFirstPerson else { return nil }
        guard previous?.perspective == "third" else { return nil }

        let asidePhrases = [
            "wait a minute", "wait,", "so i actually", "so i lived",
            "i remember when"
        ]

        for phrase in asidePhrases {
            if text.contains(phrase) {
                return EntryResult(type: .personalAside, marker: "1P shift + \"\(phrase)\"")
            }
        }

        return nil
    }

    // MARK: Meta Commentary Entry

    private func checkMetaCommentaryEntry(
        current: SentenceTelemetry,
        text: String,
        position: Double
    ) -> EntryResult? {
        guard current.hasSecondPerson else { return nil }
        guard position > 0.05 && position < 0.9 else { return nil }

        let metaPhrases = [
            "how are you liking", "let me know in the comments",
            "by the way"
        ]

        for phrase in metaPhrases {
            if text.contains(phrase) {
                return EntryResult(type: .metaCommentary, marker: "2P mid-video + \"\(phrase)\"")
            }
        }

        // Secondary: production discussion terms
        let productionTerms = ["video", "editing", "production", "camera", "footage"]
        if current.hasSecondPerson {
            for term in productionTerms {
                if text.contains(term) && (text.contains("this") || text.contains("my")) {
                    return EntryResult(type: .metaCommentary, marker: "2P + production ref: \"\(term)\"")
                }
            }
        }

        return nil
    }

    // MARK: Tangent Entry

    private func checkTangentEntry(
        current: SentenceTelemetry,
        previous: SentenceTelemetry?,
        text: String
    ) -> EntryResult? {
        guard current.stance == "questioning" else { return nil }
        guard previous?.stance == "asserting" else { return nil }

        let tangentPhrases = [
            "i wonder if", "speaking of which", "that reminds me",
            "i wonder"
        ]

        for phrase in tangentPhrases {
            if text.contains(phrase) {
                return EntryResult(type: .tangent, marker: "stance shift + \"\(phrase)\"")
            }
        }

        return nil
    }

    // MARK: Moral Correction Entry (Lexical-First)

    private func checkMoralCorrectionEntry(
        current: SentenceTelemetry,
        text: String
    ) -> EntryResult? {
        // Primary: lexical pattern match MUST come first
        let moralPhrases = [
            "but don't be fooled", "we should remember",
            "we should just remember", "not a robin hood",
            "not a hero", "doesn't make him",
            "let's be clear", "make no mistake"
        ]

        for phrase in moralPhrases {
            if text.contains(phrase) {
                // Secondary confirmation (optional, boosts confidence)
                let hasConfirmation = current.hasChallengeLanguage || current.hasContrastMarker
                let marker = hasConfirmation
                    ? "moral phrase \"\(phrase)\" + telemetry confirmation"
                    : "moral phrase \"\(phrase)\""
                return EntryResult(type: .moralCorrection, marker: marker)
            }
        }

        return nil
    }

    // MARK: Self-Promotion Entry

    private func checkSelfPromotionEntry(
        current: SentenceTelemetry,
        text: String,
        position: Double
    ) -> EntryResult? {
        guard current.isCallToAction else { return nil }
        guard !current.isSponsorContent else { return nil }
        guard position < 0.9 else { return nil }

        let promoPatterns = [
            "my course", "my book", "my channel", "my newsletter",
            "check out my", "sign up for", "enroll in",
            "new series", "new video", "patreon", "my podcast"
        ]

        for pattern in promoPatterns {
            if text.contains(pattern) {
                return EntryResult(type: .selfPromotion, marker: "CTA + \"\(pattern)\"")
            }
        }

        return nil
    }

    // MARK: Foreshadowing Plant Entry

    private func checkForeshadowingEntry(text: String) -> EntryResult? {
        let foreshadowPhrases = [
            "which will come in later", "that was foreshadowing",
            "remember this", "keep that in mind",
            "we'll come back to", "this will matter"
        ]

        for phrase in foreshadowPhrases {
            if text.contains(phrase) {
                return EntryResult(type: .foreshadowingPlant, marker: "foreshadow: \"\(phrase)\"")
            }
        }

        return nil
    }

    // MARK: - Exit Detectors

    private struct ExitResult {
        let marker: String
        let endsAtPrevious: Bool  // true = digression ends at i-1, current sentence is clean
        let isMaxScan: Bool
    }

    private func checkExitDetector(
        type: DigressionType,
        current: SentenceTelemetry,
        previous: SentenceTelemetry?,
        sentencesInDigression: Int,
        index: Int,
        sentences: [SentenceTelemetry],
        startIndex: Int
    ) -> ExitResult? {
        // maxScan check (applies to all types)
        if sentencesInDigression >= type.maxScan {
            return ExitResult(
                marker: "maxScan (\(type.maxScan)) reached",
                endsAtPrevious: false,
                isMaxScan: true
            )
        }

        switch type {
        case .sponsorRead:
            return checkSponsorExit(current: current, previous: previous)
        case .personalAside:
            return checkPersonalAsideExit(current: current, sentences: sentences, index: index)
        case .metaCommentary:
            return checkMetaCommentaryExit(current: current)
        case .tangent:
            return checkTangentExit(current: current)
        case .moralCorrection:
            return checkMoralCorrectionExit(current: current, sentencesInDigression: sentencesInDigression)
        case .selfPromotion:
            return checkSelfPromotionExit(current: current)
        case .foreshadowingPlant:
            return checkForeshadowingExit(sentencesInDigression: sentencesInDigression)
        }
    }

    // MARK: Sponsor Exit

    private func checkSponsorExit(
        current: SentenceTelemetry,
        previous: SentenceTelemetry?
    ) -> ExitResult? {
        if !current.isSponsorContent && (previous?.isSponsorContent ?? false) {
            return ExitResult(
                marker: "isSponsorContent flipped false",
                endsAtPrevious: true,
                isMaxScan: false
            )
        }
        return nil
    }

    // MARK: Personal Aside Exit

    private func checkPersonalAsideExit(
        current: SentenceTelemetry,
        sentences: [SentenceTelemetry],
        index: Int
    ) -> ExitResult? {
        let text = current.text.lowercased()

        // "anyway" + dismissal
        if text.contains("anyway") {
            return ExitResult(
                marker: "\"anyway\" dismissal",
                endsAtPrevious: false,
                isMaxScan: false
            )
        }

        // Return to third person
        if current.perspective == "third" {
            return ExitResult(
                marker: "return to third person",
                endsAtPrevious: true,
                isMaxScan: false
            )
        }

        return nil
    }

    // MARK: Meta Commentary Exit

    private func checkMetaCommentaryExit(current: SentenceTelemetry) -> ExitResult? {
        let text = current.text.lowercased()

        // CTA + return marker
        let returnMarkers = ["alright, back to", "back to", "so anyway", "moving on", "let's get back"]
        for marker in returnMarkers {
            if text.contains(marker) {
                return ExitResult(
                    marker: "return marker: \"\(marker)\"",
                    endsAtPrevious: false,
                    isMaxScan: false
                )
            }
        }

        // Perspective shifts away from second person
        if !current.hasSecondPerson && current.perspective != "second" {
            return ExitResult(
                marker: "perspective left second person",
                endsAtPrevious: true,
                isMaxScan: false
            )
        }

        return nil
    }

    // MARK: Tangent Exit

    private func checkTangentExit(current: SentenceTelemetry) -> ExitResult? {
        let text = current.text.lowercased()

        // "anyway" / self-correction
        let corrections = ["anyway", "but anyway", "regardless", "but i digress"]
        for correction in corrections {
            if text.contains(correction) {
                return ExitResult(
                    marker: "self-correction: \"\(correction)\"",
                    endsAtPrevious: false,
                    isMaxScan: false
                )
            }
        }

        // Return to asserting + third person
        if current.stance == "asserting" && current.perspective == "third" {
            return ExitResult(
                marker: "return to asserting + third person",
                endsAtPrevious: true,
                isMaxScan: false
            )
        }

        return nil
    }

    // MARK: Moral Correction Exit

    private func checkMoralCorrectionExit(
        current: SentenceTelemetry,
        sentencesInDigression: Int
    ) -> ExitResult? {
        // Need at least 2 sentences of evaluative content before allowing exit
        guard sentencesInDigression >= 2 else { return nil }

        // Return to asserting + third person
        if current.stance == "asserting" && current.perspective == "third" {
            return ExitResult(
                marker: "return to asserting + third person after evaluation",
                endsAtPrevious: true,
                isMaxScan: false
            )
        }

        return nil
    }

    // MARK: Self-Promotion Exit

    private func checkSelfPromotionExit(current: SentenceTelemetry) -> ExitResult? {
        let text = current.text.lowercased()

        // CTA ends + return marker
        if !current.isCallToAction {
            let returnMarkers = ["alright", "back to", "so anyway", "moving on", "now"]
            for marker in returnMarkers {
                if text.contains(marker) {
                    return ExitResult(
                        marker: "CTA ended + return: \"\(marker)\"",
                        endsAtPrevious: true,
                        isMaxScan: false
                    )
                }
            }

            // CTA simply ended
            return ExitResult(
                marker: "CTA ended",
                endsAtPrevious: true,
                isMaxScan: false
            )
        }

        return nil
    }

    // MARK: Foreshadowing Exit

    private func checkForeshadowingExit(sentencesInDigression: Int) -> ExitResult? {
        // Auto-close after 1-2 sentences
        if sentencesInDigression >= 1 {
            return ExitResult(
                marker: "auto-close (foreshadowing plant)",
                endsAtPrevious: false,
                isMaxScan: false
            )
        }
        return nil
    }

    // MARK: - Annotation Builder

    private func buildAnnotation(
        type: DigressionType,
        startIndex: Int,
        endIndex: Int,
        entryMarker: String,
        exitMarker: String,
        exitByMaxScan: Bool,
        sentences: [SentenceTelemetry]
    ) -> DigressionAnnotation {
        let digressionSentences = Array(sentences[startIndex...min(endIndex, sentences.count - 1)])

        // Check for CTA in digression range
        let hasCTA = digressionSentences.contains { $0.isCallToAction }

        // Check for perspective shift
        let perspectives = Set(digressionSentences.map(\.perspective))
        let perspectiveShift = perspectives.count > 1

        // Check for stance shift
        let stances = Set(digressionSentences.map(\.stance))
        let stanceShift = stances.count > 1

        // Calculate confidence
        let confidence: Double
        if exitByMaxScan {
            confidence = 0.5  // entry only, exit by timeout
        } else {
            // Check if entry had full expected signals
            let entryHasMultipleSignals = entryMarker.contains("+") || entryMarker.contains("confirmation")
            confidence = entryHasMultipleSignals ? 0.9 : 0.7
        }

        return DigressionAnnotation(
            startSentence: startIndex,
            endSentence: endIndex,
            entryMarker: entryMarker,
            exitMarker: exitMarker,
            type: type,
            confidence: confidence,
            detectionMethod: .deterministic,
            surroundingNarrativeThread: nil,  // populated by LLM enrichment
            briefContent: nil,                 // populated by LLM enrichment
            hasCTA: hasCTA,
            perspectiveShift: perspectiveShift,
            stanceShift: stanceShift
        )
    }

    // MARK: - Debug Report

    func generateDebugReport(
        sentences: [SentenceTelemetry],
        digressions: [DigressionAnnotation]
    ) -> String {
        var report = """
        ════════════════════════════════════════════════════════════════
        DIGRESSION DETECTION DEBUG REPORT
        ════════════════════════════════════════════════════════════════

        Total Sentences: \(sentences.count)
        Digressions Found: \(digressions.count)

        """

        // WHAT: List all detected digressions
        report += "WHAT — Detected Digressions:\n"
        report += "────────────────────────────────────────────────────────────────\n"
        for (idx, d) in digressions.enumerated() {
            report += """
              [\(idx + 1)] \(d.type.displayName) — sentences \(d.startSentence)-\(d.endSentence) (\(d.sentenceCount) sentences)
                  Confidence: \(String(format: "%.1f", d.confidence))
                  Entry: \(d.entryMarker)
                  Exit: \(d.exitMarker)
                  CTA: \(d.hasCTA) | Perspective Shift: \(d.perspectiveShift) | Stance Shift: \(d.stanceShift)

            """
        }

        // WHAT: Show raw data at each entry/exit point
        report += "\nWHAT — Raw Data at Entry/Exit Points:\n"
        report += "────────────────────────────────────────────────────────────────\n"
        for d in digressions {
            let entrySentence = sentences[d.startSentence]
            report += """
              Entry [s\(d.startSentence)]: "\(String(entrySentence.text.prefix(80)))..."
                perspective=\(entrySentence.perspective), stance=\(entrySentence.stance)
                1P=\(entrySentence.hasFirstPerson), 2P=\(entrySentence.hasSecondPerson)
                sponsor=\(entrySentence.isSponsorContent), CTA=\(entrySentence.isCallToAction)
                contrast=\(entrySentence.hasContrastMarker), challenge=\(entrySentence.hasChallengeLanguage)

            """

            let exitSentence = sentences[min(d.endSentence, sentences.count - 1)]
            if d.endSentence != d.startSentence {
                report += """
                  Exit [s\(d.endSentence)]: "\(String(exitSentence.text.prefix(80)))..."
                    perspective=\(exitSentence.perspective), stance=\(exitSentence.stance)

                """
            }
        }

        // WHY: Explain scoring/threshold logic
        report += "\nWHY — Detection Logic Applied:\n"
        report += "────────────────────────────────────────────────────────────────\n"
        for d in digressions {
            let confidenceReason: String
            if d.confidence >= 0.9 {
                confidenceReason = "0.9 — all expected signals present (entry marker contains multi-signal confirmation)"
            } else if d.confidence >= 0.7 {
                confidenceReason = "0.7 — entry + exit both matched (single-signal entry)"
            } else {
                confidenceReason = "0.5 — entry only, exit by maxScan timeout (no explicit exit signal found within \(d.type.maxScan) sentences)"
            }
            report += """
              \(d.type.displayName) [s\(d.startSentence)-\(d.endSentence)]:
                Entry trigger: \(d.entryMarker)
                Exit trigger: \(d.exitMarker)
                Confidence: \(confidenceReason)

            """
        }

        report += "════════════════════════════════════════════════════════════════\n"
        return report
    }
}
