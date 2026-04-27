import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ExperimentCopyService {

    // MARK: - Copy All Summary

    /// Per-experiment summary with each sister run's pass 1 and final boundaries
    static func copyAllSummary(experiments: [PromptExperiment], videoTitle: String, digressions: [DigressionAnnotation], sentences: [String]) -> String {
        var lines: [String] = []
        lines.append(String(repeating: "═", count: 60))
        lines.append("PROMPT EXPERIMENT SUMMARY")
        lines.append("Video: \(videoTitle)")
        lines.append(String(repeating: "═", count: 60))

        // Digression summary
        lines.append(formatDigressionSection(digressions, sentences: sentences))

        for (i, exp) in experiments.enumerated() {
            lines.append("")
            lines.append(String(repeating: "─", count: 60))
            lines.append("[\(i + 1)] \"\(exp.displayLabel)\"")
            lines.append("    Config: \(exp.configSummary) | \(exp.promptVariantName) | \(formatDate(exp.createdAt))")

            for sister in exp.sisterRuns {
                lines.append("")
                lines.append("    Sister Run \(sister.runNumber):")
                lines.append(formatSisterRunSummary(sister, indent: "      "))
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Same as copyAllSummary but includes the full prompt text for each experiment
    static func copySummaryWithPrompts(experiments: [PromptExperiment], videoTitle: String, digressions: [DigressionAnnotation], sentences: [String]) -> String {
        var lines: [String] = []
        lines.append(String(repeating: "═", count: 60))
        lines.append("PROMPT EXPERIMENT SUMMARY (WITH PROMPTS)")
        lines.append("Video: \(videoTitle)")
        lines.append(String(repeating: "═", count: 60))

        // Digression summary
        lines.append(formatDigressionSection(digressions, sentences: sentences))

        for (i, exp) in experiments.enumerated() {
            lines.append("")
            lines.append(String(repeating: "─", count: 60))
            lines.append("[\(i + 1)] \"\(exp.displayLabel)\"")
            lines.append("    Config: \(exp.configSummary) | \(exp.promptVariantName) | \(formatDate(exp.createdAt))")
            lines.append("")
            lines.append("    PROMPT:")
            lines.append("    " + String(repeating: "·", count: 40))
            for promptLine in exp.promptText.components(separatedBy: "\n") {
                lines.append("    \(promptLine)")
            }
            lines.append("    " + String(repeating: "·", count: 40))

            for sister in exp.sisterRuns {
                lines.append("")
                lines.append("    Sister Run \(sister.runNumber):")
                lines.append(formatSisterRunSummary(sister, indent: "      "))
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Copy Run Detail

    /// Full forensic dump for one experiment
    static func copyRunDetail(experiment: PromptExperiment, sentences: [String]) -> String {
        var lines: [String] = []
        lines.append(String(repeating: "═", count: 50))
        lines.append("EXPERIMENT DETAIL: \"\(experiment.displayLabel)\"")
        lines.append(String(repeating: "═", count: 50))
        lines.append("")

        // Config
        lines.append("CONFIG:")
        lines.append("  Window Size: \(experiment.windowSize)")
        lines.append("  Step Size: \(experiment.stepSize)")
        lines.append("  Temperature: \(String(format: "%.2f", experiment.temperature))")
        lines.append("  Prompt Variant: \(experiment.promptVariantName)")
        lines.append("  Sister Runs: \(experiment.sisterRunCount)")
        lines.append("")

        // Prompt text
        lines.append("PROMPT TEXT:")
        lines.append(String(repeating: "─", count: 40))
        lines.append(experiment.promptText)
        lines.append(String(repeating: "─", count: 40))
        lines.append("")

        // Sister runs
        for sister in experiment.sisterRuns {
            lines.append(String(repeating: "─", count: 50))
            lines.append("SISTER RUN \(sister.runNumber) — \(formatDate(sister.timestamp))")
            lines.append(String(repeating: "─", count: 50))

            // With digressions
            lines.append("")
            lines.append(formatVariant(sister.withDigressions, sentenceCount: sister.totalSentences, sentences: sentences))

            // Without digressions
            if let clean = sister.withoutDigressions {
                lines.append("")
                lines.append(formatVariant(clean, sentenceCount: sister.cleanSentenceCount ?? sister.totalSentences, sentences: sentences))
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Copy Comparison

    /// ASCII alignment matrix for selected runs
    static func copyComparison(selectedRuns: [SelectableRun], sentences: [String]) -> String {
        guard !selectedRuns.isEmpty else { return "No runs selected." }

        // Collect all gap indices across selected runs
        let allGaps = selectedRuns.reduce(into: Set<Int>()) { $0.formUnion($1.gapIndices) }.sorted()
        guard !allGaps.isEmpty else { return "No boundaries found in selected runs." }

        var lines: [String] = []
        lines.append(String(repeating: "═", count: 50))
        lines.append("EXPERIMENT COMPARISON (\(selectedRuns.count) runs)")
        lines.append(String(repeating: "═", count: 50))
        lines.append("")

        // Header
        let gapCol = "Gap".padding(toLength: 8, withPad: " ", startingAt: 0)
        let runCols = selectedRuns.map { $0.shortLabel.padding(toLength: 12, withPad: " ", startingAt: 0) }.joined()
        let agreeCol = "Agree"
        lines.append("\(gapCol)\(runCols)\(agreeCol)")
        lines.append(String(repeating: "─", count: 8 + selectedRuns.count * 12 + 6))

        // Rows
        for gap in allGaps {
            let gapStr = "[\(gap)]".padding(toLength: 8, withPad: " ", startingAt: 0)
            var voteCount = 0
            var cells = ""
            for run in selectedRuns {
                let hit = run.gapIndices.contains(gap)
                if hit { voteCount += 1 }
                let symbol = (hit ? "●" : "○").padding(toLength: 12, withPad: " ", startingAt: 0)
                cells += symbol
            }
            let agree = "\(voteCount)/\(selectedRuns.count)"
            lines.append("\(gapStr)\(cells)\(agree)")

            // Sentence context
            if gap < sentences.count {
                let before = sentences[gap]
                let preview = String(before.prefix(60))
                lines.append("         \"\(preview)\"")
            }
        }

        lines.append("")
        lines.append("● = boundary  ○ = no boundary")

        // Agreement summary
        let unanimous = allGaps.filter { gap in selectedRuns.allSatisfy { $0.gapIndices.contains(gap) } }.count
        let partial = allGaps.filter { gap in
            let count = selectedRuns.filter { $0.gapIndices.contains(gap) }.count
            return count > 1 && count < selectedRuns.count
        }.count
        let single = allGaps.filter { gap in selectedRuns.filter { $0.gapIndices.contains(gap) }.count == 1 }.count

        lines.append("")
        lines.append("Agreement: \(unanimous) unanimous, \(partial) partial, \(single) single-run-only")

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Formats the digression section showing what was removed for -Dig runs
    private static func formatDigressionSection(_ digressions: [DigressionAnnotation], sentences: [String]) -> String {
        guard !digressions.isEmpty else {
            return "\nDIGRESSIONS: None detected\n"
        }

        var lines: [String] = []
        let totalExcluded = digressions.reduce(0) { $0 + $1.sentenceCount }
        lines.append("")
        lines.append("DIGRESSIONS REMOVED (\(digressions.count) found, \(totalExcluded) sentences excluded):")
        lines.append(String(repeating: "─", count: 50))

        let sorted = digressions.sorted { $0.startSentence < $1.startSentence }
        for dig in sorted {
            let typeStr = dig.type.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)
            let rangeStr = "[\(dig.startSentence + 1)]-[\(dig.endSentence + 1)]"
            let countStr = "(\(dig.sentenceCount) sent)"
            lines.append("  \(typeStr) \(rangeStr) \(countStr)")

            // Show first sentence of digression
            if dig.startSentence < sentences.count {
                let firstSent = String(sentences[dig.startSentence].prefix(70))
                lines.append("    START: \"\(firstSent)\"")
            }
            // Show last sentence if multi-sentence
            if dig.sentenceCount > 1, dig.endSentence < sentences.count {
                let lastSent = String(sentences[dig.endSentence].prefix(70))
                lines.append("    END:   \"\(lastSent)\"")
            }
            // Brief content if available
            if let brief = dig.briefContent, !brief.isEmpty {
                lines.append("    ABOUT: \(String(brief.prefix(80)))")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Compact summary of one sister run showing pass 1 and final for both variants
    private static func formatSisterRunSummary(_ sister: ExperimentSisterRun, indent: String) -> String {
        var lines: [String] = []

        let dig = sister.withDigressions
        let digP1 = dig.pass1GapIndices.sorted()
        let digFinal = dig.finalGapIndices.sorted()
        let digResult = dig.splitterResult

        lines.append("\(indent)+Dig (\(sister.totalSentences) sentences, \(String(format: "%.1f", dig.runDuration))s):")
        lines.append("\(indent)  Pass 1: \(digP1.count) boundaries -> [\(digP1.map { "\($0)" }.joined(separator: ","))]")
        lines.append("\(indent)  Final:  \(digFinal.count) boundaries -> [\(digFinal.map { "\($0)" }.joined(separator: ","))]")

        let revoked = digResult.pass2RevokedCount
        let added = digResult.pass2AddedBoundaries.count
        let moved = digResult.pass2MovedCount
        if revoked > 0 || added > 0 || moved > 0 {
            lines.append("\(indent)  Pass 2 changes: \(revoked) revoked, \(added) added, \(moved) moved")
        }

        if let clean = sister.withoutDigressions {
            let cleanP1 = clean.pass1GapIndices.sorted()
            let cleanFinal = clean.finalGapIndices.sorted()
            let cleanResult = clean.splitterResult
            let cleanCount = sister.cleanSentenceCount ?? (sister.totalSentences - (sister.digressionExcludeIndices?.count ?? 0))

            lines.append("\(indent)-Dig (\(cleanCount) sentences, \(String(format: "%.1f", clean.runDuration))s):")
            lines.append("\(indent)  Pass 1: \(cleanP1.count) boundaries -> [\(cleanP1.map { "\($0)" }.joined(separator: ","))]")
            lines.append("\(indent)  Final:  \(cleanFinal.count) boundaries -> [\(cleanFinal.map { "\($0)" }.joined(separator: ","))]")

            let cRevoked = cleanResult.pass2RevokedCount
            let cAdded = cleanResult.pass2AddedBoundaries.count
            let cMoved = cleanResult.pass2MovedCount
            if cRevoked > 0 || cAdded > 0 || cMoved > 0 {
                lines.append("\(indent)  Pass 2 changes: \(cRevoked) revoked, \(cAdded) added, \(cMoved) moved")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatVariant(_ variant: ExperimentVariant, sentenceCount: Int, sentences: [String]) -> String {
        var lines: [String] = []
        let typeLabel = variant.variantType == .withDigressions ? "WITH DIGRESSIONS" : "WITHOUT DIGRESSIONS"
        lines.append("  \(typeLabel) (\(sentenceCount) sentences):")

        let p1Gaps = variant.pass1GapIndices.sorted()
        let finalGaps = variant.finalGapIndices.sorted()
        let p1Str = p1Gaps.map { "\($0)" }.joined(separator: ",")
        let finalStr = finalGaps.map { "\($0)" }.joined(separator: ",")

        let result = variant.splitterResult
        lines.append("    Pass 1: \(p1Gaps.count) boundaries -> [\(p1Str)]")
        lines.append("    Final:  \(finalGaps.count) boundaries -> [\(finalStr)]")
        lines.append("    Revoked: \(result.pass2RevokedCount) | Added: \(result.pass2AddedBoundaries.count) | Moved: \(result.pass2MovedCount)")
        lines.append("    Duration: \(String(format: "%.1f", variant.runDuration))s")
        lines.append("    Windows: \(variant.windowCount)")

        // Window details
        lines.append("")
        lines.append("    Window Details:")
        for w in variant.rawWindowOutputs {
            let range = "[\(w.startSentence)-\(w.endSentence)]"
            let p1Preview = String(w.pass1Raw.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            lines.append("      W\(w.windowIndex) \(range): \(p1Preview)")
            if let p2 = w.pass2Raw {
                let p2Preview = String(p2.prefix(80)).replacingOccurrences(of: "\n", with: " ")
                lines.append("        P2: \(p2Preview)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }

    // MARK: - Pasteboard

    static func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
