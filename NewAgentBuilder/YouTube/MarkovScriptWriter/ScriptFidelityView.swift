//
//  ScriptFidelityView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/18/26.
//
//  Results display for the Script Fidelity Evaluator.
//  Shows per-method bar charts, per-section drill-down,
//  hard-fail callouts, and baseline range overlays.
//

import SwiftUI

// MARK: - Method-Level Fidelity Card

struct FidelityScoreCard: View {
    let methodLabel: String
    let fidelityScore: FidelityScore
    let sectionResults: [SectionFidelityResult]
    let baseline: BaselineProfile?

    @State private var expandedSections = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: method label + composite score + hard-fail badge
            HStack {
                Text(methodLabel)
                    .font(.headline)
                Spacer()
                if fidelityScore.hardFailCount > 0 {
                    Label("\(fidelityScore.hardFailCount) FAIL", systemImage: "xmark.octagon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red, in: Capsule())
                }
                if fidelityScore.warningCount > 0 {
                    Label("\(fidelityScore.warningCount) WARN", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange, in: Capsule())
                }
                compositeScoreBadge(fidelityScore.compositeScore)
            }

            // Dimension bar chart
            VStack(alignment: .leading, spacing: 6) {
                ForEach(FidelityDimension.allCases) { dim in
                    if let dimScore = fidelityScore.score(for: dim) {
                        dimensionRow(dim: dim, score: dimScore)
                    }
                }
            }

            // Hard-fail details (if any)
            let allFails = sectionResults.flatMap(\.failedRules)
            let allWarns = sectionResults.flatMap(\.warningRules)
            if !allFails.isEmpty || !allWarns.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allFails) { fail in
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text(fail.displayMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    ForEach(allWarns) { warn in
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(warn.displayMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // Per-section drill-down
            if sectionResults.count > 1 {
                DisclosureGroup("Per-Section Breakdown (\(sectionResults.count) sections)", isExpanded: $expandedSections) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sectionResults) { section in
                            sectionRow(section)
                        }
                    }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Subviews

    private func dimensionRow(dim: FidelityDimension, score: DimensionScore) -> some View {
        HStack(spacing: 8) {
            Text(dim.shortLabel)
                .font(.caption.monospaced())
                .frame(width: 50, alignment: .trailing)

            // Bar with baseline range overlay
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)

                    // Baseline range band (gray)
                    if let range = score.baselineRange ?? baseline?.dimensionRanges[dim.rawValue] {
                        let startX = geo.size.width * (range.p25 / 100.0)
                        let endX = geo.size.width * (range.p75 / 100.0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.secondary.opacity(0.25))
                            .frame(width: max(0, endX - startX))
                            .offset(x: startX)
                    }

                    // Score bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(for: score.score))
                        .frame(width: max(0, geo.size.width * (score.score / 100.0)))
                }
            }
            .frame(height: 14)

            Text(String(format: "%.0f", score.score))
                .font(.caption.monospaced().bold())
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(barColor(for: score.score))

            // Baseline range label
            if let range = score.baselineRange ?? baseline?.dimensionRanges[dim.rawValue] {
                Text("\(Int(range.p25))-\(Int(range.p75))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 45, alignment: .leading)
            }
        }
    }

    private func sectionRow(_ section: SectionFidelityResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Section \(section.sectionIndex + 1)")
                    .font(.caption.bold())
                Text("\(section.sentenceCount)s / \(section.wordCount)w")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if section.hasHardFail {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                }
                if section.hasWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
                Text(String(format: "%.0f", section.compositeScore))
                    .font(.caption.bold())
                    .foregroundStyle(barColor(for: section.compositeScore))
            }

            // Mini bar chart for this section
            HStack(spacing: 2) {
                ForEach(FidelityDimension.allCases) { dim in
                    if let dimScore = section.dimensionScores[dim] {
                        VStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(barColor(for: dimScore.score))
                                .frame(width: 12, height: max(2, 20 * (dimScore.score / 100.0)))
                            Text(dim.shortLabel.prefix(2))
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Section-level hard-fail messages
            ForEach(section.failedRules) { fail in
                Text(fail.displayMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func compositeScoreBadge(_ score: Double) -> some View {
        Text(String(format: "%.0f", score))
            .font(.title3.bold().monospaced())
            .foregroundStyle(barColor(for: score))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(barColor(for: score).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private func barColor(for score: Double) -> Color {
        switch score {
        case 80...:   return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default:      return .red
        }
    }
}

// MARK: - Comparison Summary View (all methods side-by-side)

struct FidelityComparisonSummary: View {
    let evaluations: [(label: String, score: FidelityScore, sections: [SectionFidelityResult])]
    let baseline: BaselineProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Ranking table
            if evaluations.count > 1 {
                rankingTable
            }

            // Individual cards
            ForEach(evaluations.indices, id: \.self) { i in
                FidelityScoreCard(
                    methodLabel: evaluations[i].label,
                    fidelityScore: evaluations[i].score,
                    sectionResults: evaluations[i].sections,
                    baseline: baseline
                )
            }
        }
    }

    private var rankingTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ranking")
                .font(.headline)

            let sorted = evaluations.sorted { $0.score.compositeScore > $1.score.compositeScore }
            ForEach(sorted.indices, id: \.self) { i in
                HStack {
                    Text("#\(i + 1)")
                        .font(.caption.bold())
                        .frame(width: 30)
                    Text(sorted[i].label)
                        .font(.subheadline)
                    Spacer()
                    if sorted[i].score.hardFailCount > 0 {
                        Text("\(sorted[i].score.hardFailCount)F")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                    }
                    Text(String(format: "%.0f", sorted[i].score.compositeScore))
                        .font(.subheadline.bold().monospaced())
                        .foregroundStyle(scoreColor(sorted[i].score.compositeScore))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...:   return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default:      return .red
        }
    }
}

// MARK: - Baseline Status Badge

struct BaselineStatusBadge: View {
    let baseline: BaselineProfile?

    var body: some View {
        if let b = baseline {
            Label("\(b.sampleCount) sections baselined", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label("No baseline — scores are relative to theoretical ideal", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Inline Fidelity Breakdown (for method result cards)

/// Compact DisclosureGroup showing fidelity results inline in a method card.
/// Collapsed: one-line summary with composite + 8 dimension scores + fail count.
/// Expanded: full bar chart + per-section sub-metrics + per-sentence detail.
struct InlineFidelityBreakdown: View {
    let fidelityScore: FidelityScore
    let sections: [SectionFidelityResult]
    let corpusStats: CorpusStats
    let baseline: BaselineProfile?
    var slotDebug: [SlotDebugData]? = nil

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            expandedContent
        } label: {
            compactLabel
        }
        .font(.caption)
    }

    // MARK: - Compact Label (always visible)

    private var compactLabel: some View {
        HStack(spacing: 6) {
            Text("Fidelity:")
                .font(.caption.bold())

            Text(String(format: "%.0f", fidelityScore.compositeScore))
                .font(.caption.bold().monospaced())
                .foregroundStyle(scoreColor(fidelityScore.compositeScore))

            // 8 dimension scores as compact pills
            ForEach(FidelityDimension.allCases) { dim in
                if let ds = fidelityScore.score(for: dim) {
                    Text("\(dim.shortLabel.prefix(2))\(String(format: "%.0f", ds.score))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(scoreColor(ds.score))
                }
            }

            Spacer()

            if fidelityScore.hardFailCount > 0 {
                Text("\(fidelityScore.hardFailCount)F")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.red, in: Capsule())
            }
            if fidelityScore.warningCount > 0 {
                Text("\(fidelityScore.warningCount)W")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.orange, in: Capsule())
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Dimension bar chart
            VStack(alignment: .leading, spacing: 4) {
                ForEach(FidelityDimension.allCases) { dim in
                    if let dimScore = fidelityScore.score(for: dim) {
                        dimensionBar(dim: dim, score: dimScore)
                    }
                }
            }

            Divider()

            // Per-section detail (flat, scrollable — no nested DisclosureGroups)
            ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                sectionDetail(section, slotDebug: slotDebug?[safe: idx])
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Dimension Bar

    private func dimensionBar(dim: FidelityDimension, score: DimensionScore) -> some View {
        HStack(spacing: 6) {
            Text(dim.shortLabel)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 42, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)

                    if let range = score.baselineRange ?? baseline?.dimensionRanges[dim.rawValue] {
                        let startX = geo.size.width * (range.p25 / 100.0)
                        let endX = geo.size.width * (range.p75 / 100.0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.2))
                            .frame(width: max(0, endX - startX))
                            .offset(x: startX)
                    }

                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor(score.score))
                        .frame(width: max(0, geo.size.width * (score.score / 100.0)))
                }
            }
            .frame(height: 12)

            Text(String(format: "%.0f", score.score))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(scoreColor(score.score))

            if let range = score.baselineRange ?? baseline?.dimensionRanges[dim.rawValue] {
                Text("[\(Int(range.p25))-\(Int(range.p75))]")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
        }
    }

    // MARK: - Per-Section Detail

    private func sectionDetail(_ section: SectionFidelityResult, slotDebug: SlotDebugData? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section header
            HStack {
                Text("Section \(section.sectionIndex + 1)")
                    .font(.caption.bold())
                Text("\(section.sentenceCount)s / \(section.wordCount)w")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if section.hasHardFail {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.caption2).foregroundStyle(.red)
                }
                Text(String(format: "%.0f", section.compositeScore))
                    .font(.caption.bold())
                    .foregroundStyle(scoreColor(section.compositeScore))
            }

            // Sub-metrics table (all dimensions, flat)
            ForEach(FidelityDimension.allCases) { dim in
                if let ds = section.dimensionScores[dim] {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dim.shortLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(scoreColor(ds.score))
                        ForEach(ds.subMetrics.indices, id: \.self) { idx in
                            let sub = ds.subMetrics[idx]
                            HStack(spacing: 4) {
                                Text(sub.name)
                                    .frame(width: 140, alignment: .leading)
                                Text("RAW=\(String(format: "%.2f", sub.rawValue))")
                                    .frame(width: 72, alignment: .trailing)
                                Text("CRP=\(String(format: "%.2f", sub.corpusMean))")
                                    .frame(width: 72, alignment: .trailing)
                                Text(String(format: "%.0f", sub.score))
                                    .fontWeight(.bold)
                                    .foregroundStyle(scoreColor(sub.score))
                                    .frame(width: 24, alignment: .trailing)
                            }
                            .font(.system(size: 9, design: .monospaced))
                        }
                    }
                }
            }

            // Per-sentence rows (re-parsed from sectionText)
            let parsed = ScriptFidelityService.parseSection(
                text: section.sectionText,
                index: section.sectionIndex,
                moveType: nil
            )
            let corpusRolledSigs = corpusStats.rolledSlotSignatures(forMove: "")

            Divider()
            Text("Sentences")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            ForEach(parsed.sentences.indices, id: \.self) { idx in
                let sent = parsed.sentences[idx]
                let sig = ScriptFidelityService.extractSlotSignature(from: sent)
                let rolled = SignatureRollupService.rollupDominantSlot(sig)
                let matched = corpusRolledSigs.contains(rolled)
                let bucket = sentenceBucket(wordCount: sent.wordCount)

                VStack(alignment: .leading, spacing: 2) {
                    Text("[\(idx + 1)] \(sent.text)")
                        .font(.system(size: 10))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text("\(sent.wordCount)w")
                        Text(bucket)
                            .foregroundStyle(bucketColor(bucket))
                        Text("sig=\(rolled)")
                        Text(matched ? "MATCH" : "MISS")
                            .fontWeight(.bold)
                            .foregroundStyle(matched ? .green : .red)
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 1)
            }

            // Slot Debugger
            if let debug = slotDebug {
                SlotDebugSection(debug: debug)
            }

            // Hard-fail messages
            ForEach(section.failedRules) { fail in
                Text(fail.displayMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: - Helpers

    // Visible to slot debug section
    fileprivate func sentenceBucket(wordCount: Int) -> String {
        if wordCount <= corpusStats.shortSentenceMax { return "S" }
        if wordCount >= corpusStats.longSentenceMin { return "L" }
        return "M"
    }

    private func bucketColor(_ bucket: String) -> Color {
        switch bucket {
        case "S": return .blue
        case "L": return .purple
        default:  return .secondary
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...:   return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default:      return .red
        }
    }
}

// MARK: - Slot Debugger View

private struct SlotDebugSection: View {
    let debug: SlotDebugData
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup("Slot Debugger (D4 + S2)", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                scoreExplanation
                Divider()
                corpusContext
                Divider()
                sentenceBreakdown
                Divider()
                bigramAnalysis

                FadeOutCopyButton(text: buildCopyText(), label: "Copy Slot Debug")
            }
            .padding(.top, 4)
        }
        .font(.system(size: 9, design: .monospaced))
    }

    private var scoreExplanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SCORE ARITHMETIC")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(debug.d4ScoreExplanation)
                .font(.system(size: 9, design: .monospaced))
            Text(debug.s2ScoreExplanation)
                .font(.system(size: 9, design: .monospaced))
        }
    }

    private var corpusContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CORPUS CONTEXT")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            Text("D4 rolled sigs (\(debug.corpusRolledSigs.count) unique):")
                .font(.system(size: 9, weight: .semibold))
            FlowLayout(spacing: 4) {
                ForEach(debug.corpusRolledSigs.prefix(20), id: \.sig) { item in
                    Text("\(item.sig)(\(item.count))")
                        .font(.system(size: 8, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(3)
                }
            }

            Text("S2 raw sigs (\(debug.corpusRawSigs.count) unique):")
                .font(.system(size: 9, weight: .semibold))
            FlowLayout(spacing: 4) {
                ForEach(debug.corpusRawSigs.prefix(20), id: \.sig) { item in
                    Text("\(item.sig)(\(item.count))")
                        .font(.system(size: 8, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(3)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("D4 openers:")
                        .font(.system(size: 8, weight: .semibold))
                    ForEach(debug.corpusRolledOpeners, id: \.self) { sig in
                        Text(sig).font(.system(size: 8, design: .monospaced)).foregroundStyle(.blue)
                    }
                }
                VStack(alignment: .leading) {
                    Text("S2 openers:")
                        .font(.system(size: 8, weight: .semibold))
                    ForEach(debug.corpusRawOpeners.prefix(10), id: \.self) { sig in
                        Text(sig).font(.system(size: 8, design: .monospaced)).foregroundStyle(.purple)
                    }
                }
            }
        }
    }

    private var sentenceBreakdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PER-SENTENCE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            ForEach(debug.sentences) { sent in
                VStack(alignment: .leading, spacing: 2) {
                    Text("[\(sent.id + 1)] \(sent.text)")
                        .font(.system(size: 9))
                        .lineLimit(2)

                    // Prompt spec (what was ASKED for)
                    if sent.targetSig != nil || sent.targetWordRange != nil {
                        HStack(spacing: 6) {
                            Text("ASK:")
                                .fontWeight(.bold)
                                .foregroundStyle(.orange)
                            if let sig = sent.targetSig {
                                Text("sig=\(sig)")
                            }
                            if let range = sent.targetWordRange {
                                Text("wc=\(range)")
                            }
                            if let type = sent.targetSentenceType {
                                Text("type=\(type)")
                            }
                        }
                        .font(.system(size: 8, design: .monospaced))

                        if let topic = sent.targetTopic {
                            Text("Topic: \(topic)")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange.opacity(0.8))
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("\(sent.wordCount)w")
                        Text("Hints: \(sent.hints.isEmpty ? "none" : sent.hints.joined(separator: " "))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 8, design: .monospaced))

                    HStack(spacing: 6) {
                        Text("Heur: \(sent.heuristicSig)")
                        Text("→ Rolled: \(sent.rolledSig)")
                        Text(sent.d4Matched ? "MATCH" : "MISS")
                            .fontWeight(.bold)
                            .foregroundStyle(sent.d4Matched ? .green : .red)
                    }
                    .font(.system(size: 8, design: .monospaced))

                    HStack(spacing: 6) {
                        Text("S2[\(sent.s2Source)]: \(sent.s2Sig)")
                        Text(sent.s2Matched ? "MATCH" : "MISS")
                            .fontWeight(.bold)
                            .foregroundStyle(sent.s2Matched ? .green : .red)
                    }
                    .font(.system(size: 8, design: .monospaced))
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(4)
            }
        }
    }

    private var bigramAnalysis: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BIGRAMS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            let d4Hits = debug.d4Bigrams.filter(\.matched).count
            let s2Hits = debug.s2Bigrams.filter(\.matched).count

            Text("D4 rolled: \(d4Hits)/\(debug.d4Bigrams.count) matched")
                .font(.system(size: 9, weight: .semibold))
            ForEach(debug.d4Bigrams) { bg in
                HStack(spacing: 4) {
                    Text("\(bg.from)→\(bg.to)")
                    Text(bg.matched ? "MATCH" : "MISS")
                        .fontWeight(.bold)
                        .foregroundStyle(bg.matched ? .green : .red)
                }
                .font(.system(size: 8, design: .monospaced))
            }

            Text("S2 raw: \(s2Hits)/\(debug.s2Bigrams.count) matched")
                .font(.system(size: 9, weight: .semibold))
                .padding(.top, 2)
            ForEach(debug.s2Bigrams) { bg in
                HStack(spacing: 4) {
                    Text("\(bg.from)→\(bg.to)")
                    Text(bg.matched ? "MATCH" : "MISS")
                        .fontWeight(.bold)
                        .foregroundStyle(bg.matched ? .green : .red)
                }
                .font(.system(size: 8, design: .monospaced))
            }
        }
    }

    private func buildCopyText() -> String {
        var lines: [String] = ["=== SLOT DEBUGGER ===", ""]
        lines.append(debug.d4ScoreExplanation)
        lines.append("")
        lines.append(debug.s2ScoreExplanation)
        lines.append("")
        lines.append("--- CORPUS D4 ROLLED SIGS ---")
        for item in debug.corpusRolledSigs { lines.append("  \(item.sig) (\(item.count))") }
        lines.append("")
        lines.append("--- CORPUS S2 RAW SIGS ---")
        for item in debug.corpusRawSigs { lines.append("  \(item.sig) (\(item.count))") }
        lines.append("")
        lines.append("--- CORPUS D4 OPENERS ---")
        for sig in debug.corpusRolledOpeners { lines.append("  \(sig)") }
        lines.append("")
        lines.append("--- CORPUS S2 OPENERS ---")
        for sig in debug.corpusRawOpeners { lines.append("  \(sig)") }
        lines.append("")
        lines.append("--- PER-SENTENCE ---")
        for sent in debug.sentences {
            lines.append("[\(sent.id + 1)] \(sent.text)")
            let specParts = [
                sent.targetSig.map { "sig=\($0)" },
                sent.targetWordRange.map { "wc=\($0)" },
                sent.targetSentenceType.map { "type=\($0)" }
            ].compactMap { $0 }
            if !specParts.isEmpty {
                lines.append("  ASK: \(specParts.joined(separator: "  "))")
            }
            if let topic = sent.targetTopic {
                lines.append("  Topic: \(topic)")
            }
            lines.append("  \(sent.wordCount)w  Hints: \(sent.hints.isEmpty ? "none" : sent.hints.joined(separator: " "))")
            lines.append("  Heur: \(sent.heuristicSig) → Rolled: \(sent.rolledSig) D4=\(sent.d4Matched ? "MATCH" : "MISS")")
            lines.append("  S2[\(sent.s2Source)]: \(sent.s2Sig) S2=\(sent.s2Matched ? "MATCH" : "MISS")")
        }
        lines.append("")
        lines.append("--- D4 BIGRAMS ---")
        for bg in debug.d4Bigrams { lines.append("  \(bg.from)→\(bg.to) \(bg.matched ? "MATCH" : "MISS")") }
        lines.append("")
        lines.append("--- S2 BIGRAMS ---")
        for bg in debug.s2Bigrams { lines.append("  \(bg.from)→\(bg.to) \(bg.matched ? "MATCH" : "MISS")") }
        return lines.joined(separator: "\n")
    }
}
