import Foundation

/// Diagnostic validator for LLM-detected digressions
/// Checks whether sentence telemetry supports, is neutral toward, or contradicts each detection
/// Does NOT filter or remove detections — purely diagnostic
class DigressionRulesValidator {

    static let shared = DigressionRulesValidator()

    private init() {}

    // MARK: - Main Validation

    func validate(
        digressions: [DigressionAnnotation],
        sentences: [SentenceTelemetry]
    ) -> [ValidatedDigression] {
        digressions.map { digression in
            let checks = runGateChecks(digression: digression, sentences: sentences)

            let hasContradiction = checks.contains { !$0.passed && isContradictionCheck($0.name) }
            let allConfirmsPassed = checks.filter { isConfirmCheck($0.name) }.allSatisfy(\.passed)

            let verdict: RulesVerdict
            let contradictionReason: String?

            if hasContradiction {
                verdict = .contradicted
                contradictionReason = checks
                    .filter { !$0.passed && isContradictionCheck($0.name) }
                    .map(\.detail)
                    .joined(separator: "; ")
            } else if allConfirmsPassed && !checks.filter({ isConfirmCheck($0.name) }).isEmpty {
                verdict = .confirmed
                contradictionReason = nil
            } else {
                verdict = .neutral
                contradictionReason = nil
            }

            return ValidatedDigression(
                annotation: digression,
                verdict: verdict,
                checks: checks,
                contradictionReason: contradictionReason
            )
        }
    }

    // MARK: - Gate Check Dispatch

    private func runGateChecks(
        digression: DigressionAnnotation,
        sentences: [SentenceTelemetry]
    ) -> [ValidatedDigression.GateCheck] {
        let startIdx = digression.startSentence
        let endIdx = digression.endSentence
        guard startIdx >= 0, endIdx < sentences.count, startIdx <= endIdx else { return [] }

        let entrySentence = sentences[startIdx]
        let previousSentence: SentenceTelemetry? = startIdx > 0 ? sentences[startIdx - 1] : nil
        let rangeSentences = Array(sentences[startIdx...endIdx])

        switch digression.type {
        case .sponsorRead:
            return sponsorGateChecks(entry: entrySentence, range: rangeSentences)
        case .personalAside:
            return personalAsideGateChecks(entry: entrySentence, previous: previousSentence, range: rangeSentences)
        case .metaCommentary:
            return metaCommentaryGateChecks(entry: entrySentence, range: rangeSentences)
        case .tangent:
            return tangentGateChecks(range: rangeSentences)
        case .moralCorrection:
            return moralCorrectionGateChecks(entry: entrySentence, range: rangeSentences)
        case .selfPromotion:
            return selfPromotionGateChecks(range: rangeSentences)
        case .foreshadowingPlant:
            return foreshadowingGateChecks(range: rangeSentences)
        }
    }

    // MARK: - Sponsor Read Gates

    private func sponsorGateChecks(
        entry: SentenceTelemetry,
        range: [SentenceTelemetry]
    ) -> [ValidatedDigression.GateCheck] {
        let sponsorCount = range.filter(\.isSponsorContent).count
        let majorityIsSponsor = sponsorCount > range.count / 2

        return [
            .init(
                name: "confirm:sponsorFlagMajority",
                passed: majorityIsSponsor,
                detail: "\(sponsorCount)/\(range.count) sentences have isSponsorContent"
            ),
            .init(
                name: "confirm:lengthAtLeast3",
                passed: range.count >= 3,
                detail: "range is \(range.count) sentences"
            )
        ]
    }

    // MARK: - Personal Aside Gates

    private func personalAsideGateChecks(
        entry: SentenceTelemetry,
        previous: SentenceTelemetry?,
        range: [SentenceTelemetry]
    ) -> [ValidatedDigression.GateCheck] {
        let allThirdPerson = range.allSatisfy { $0.perspective == "third" }

        return [
            .init(
                name: "confirm:firstPersonAtEntry",
                passed: entry.hasFirstPerson,
                detail: "s\(entry.sentenceIndex): hasFirstPerson=\(entry.hasFirstPerson)"
            ),
            .init(
                name: "confirm:previousThirdPerson",
                passed: previous?.perspective == "third",
                detail: previous.map { "s\($0.sentenceIndex): perspective=\($0.perspective)" } ?? "no previous sentence"
            ),
            .init(
                name: "contradict:allThirdPerson",
                passed: !allThirdPerson,
                detail: allThirdPerson
                    ? "perspective stays third throughout entire range — unlikely personal aside"
                    : "perspective shifts present in range"
            )
        ]
    }

    // MARK: - Meta Commentary Gates

    private func metaCommentaryGateChecks(
        entry: SentenceTelemetry,
        range: [SentenceTelemetry]
    ) -> [ValidatedDigression.GateCheck] {
        let hasSecondPerson = range.contains { $0.hasSecondPerson }
        let avgPosition = range.map(\.positionPercentile).reduce(0, +) / Double(range.count)
        let inLastTenPercent = avgPosition > 0.9

        return [
            .init(
                name: "confirm:secondPersonPresent",
                passed: hasSecondPerson,
                detail: "hasSecondPerson in range: \(hasSecondPerson)"
            ),
            .init(
                name: "confirm:midVideoPosition",
                passed: avgPosition > 0.05 && avgPosition < 0.9,
                detail: "avg position: \(String(format: "%.0f%%", avgPosition * 100))"
            ),
            .init(
                name: "contradict:closingCTA",
                passed: !inLastTenPercent,
                detail: inLastTenPercent
                    ? "position in last 10% — likely closing CTA, not meta commentary"
                    : "position within video body"
            )
        ]
    }

    // MARK: - Tangent Gates

    private func tangentGateChecks(
        range: [SentenceTelemetry]
    ) -> [ValidatedDigression.GateCheck] {
        let hasSponsor = range.contains { $0.isSponsorContent }

        return [
            .init(
                name: "confirm:reasonableLength",
                passed: range.count >= 2 && range.count <= 8,
                detail: "range is \(range.count) sentences (expected 2-8)"
            ),
            .init(
                name: "contradict:sponsorInRange",
                passed: !hasSponsor,
                detail: hasSponsor
                    ? "isSponsorContent found in range — likely sponsor, not tangent"
                    : "no sponsor flags in range"
            )
        ]
    }

    // MARK: - Moral Correction Gates

    private func moralCorrectionGateChecks(
        entry: SentenceTelemetry,
        range: [SentenceTelemetry]
    ) -> [ValidatedDigression.GateCheck] {
        let hasChallenge = range.contains { $0.hasChallengeLanguage }
        let hasContrast = range.contains { $0.hasContrastMarker }
        let hasSponsor = range.contains { $0.isSponsorContent }

        return [
            .init(
                name: "confirm:challengeOrContrast",
                passed: hasChallenge || hasContrast,
                detail: "hasChallengeLanguage: \(hasChallenge), hasContrastMarker: \(hasContrast)"
            ),
            .init(
                name: "contradict:sponsorInRange",
                passed: !hasSponsor,
                detail: hasSponsor
                    ? "isSponsorContent found in range — likely sponsor, not moral correction"
                    : "no sponsor flags in range"
            )
        ]
    }

    // MARK: - Self-Promotion Gates

    private func selfPromotionGateChecks(
        range: [SentenceTelemetry]
    ) -> [ValidatedDigression.GateCheck] {
        let hasCTA = range.contains { $0.isCallToAction }
        let hasSponsor = range.contains { $0.isSponsorContent }

        return [
            .init(
                name: "confirm:ctaPresent",
                passed: hasCTA,
                detail: "isCallToAction in range: \(hasCTA)"
            ),
            .init(
                name: "contradict:sponsorInRange",
                passed: !hasSponsor,
                detail: hasSponsor
                    ? "isSponsorContent found in range — may be sponsor read, not self-promotion"
                    : "no sponsor flags in range"
            )
        ]
    }

    // MARK: - Foreshadowing Plant Gates

    private func foreshadowingGateChecks(
        range: [SentenceTelemetry]
    ) -> [ValidatedDigression.GateCheck] {
        return [
            .init(
                name: "confirm:briefLength",
                passed: range.count <= 2,
                detail: "range is \(range.count) sentences (expected 1-2)"
            ),
            .init(
                name: "contradict:tooLong",
                passed: range.count <= 5,
                detail: range.count > 5
                    ? "\(range.count) sentences — too long for foreshadowing plant"
                    : "length within acceptable range"
            )
        ]
    }

    // MARK: - Check Classification

    private func isContradictionCheck(_ name: String) -> Bool {
        name.hasPrefix("contradict:")
    }

    private func isConfirmCheck(_ name: String) -> Bool {
        name.hasPrefix("confirm:")
    }

    // MARK: - Debug Report

    func generateDebugReport(validations: [ValidatedDigression]) -> String {
        guard !validations.isEmpty else {
            return "No validations to report."
        }

        var report = """
        ════════════════════════════════════════════════════════════════
        RULES VALIDATION DEBUG REPORT
        ════════════════════════════════════════════════════════════════

        WHAT — Validation results:
          \(validations.count) digressions validated
          Confirmed: \(validations.filter { $0.verdict == .confirmed }.count)
          Neutral: \(validations.filter { $0.verdict == .neutral }.count)
          Contradicted: \(validations.filter { $0.verdict == .contradicted }.count)

        """

        for (idx, v) in validations.enumerated() {
            let d = v.annotation
            report += """

            WHAT — [\(idx + 1)] \(d.type.displayName) s\(d.startSentence)-\(d.endSentence):
              Verdict: \(v.verdict.rawValue.uppercased())
              Checks:

            """

            for check in v.checks {
                let icon = check.passed ? "PASS" : "FAIL"
                report += "    [\(icon)] \(check.name): \(check.detail)\n"
            }

            if let reason = v.contradictionReason {
                report += """

              WHY contradicted: \(reason)

              """
            } else {
                report += """

              WHY \(v.verdict.rawValue): \(v.checks.filter(isConfirmCheck).count) confirm checks, \
              \(v.checks.filter { !$0.passed && isContradictionCheck($0.name) }.count) contradiction checks fired

              """
            }
        }

        report += "════════════════════════════════════════════════════════════════\n"
        return report
    }

    private func isConfirmCheck(_ check: ValidatedDigression.GateCheck) -> Bool {
        check.name.hasPrefix("confirm:") && check.passed
    }

    private func isContradictionCheck(_ check: ValidatedDigression.GateCheck) -> Bool {
        check.name.hasPrefix("contradict:") && !check.passed
    }
}
