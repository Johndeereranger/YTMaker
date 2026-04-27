import SwiftUI

struct ExperimentComparisonView: View {
    let selectedRuns: [SelectableRun]
    let sentences: [String]
    let experiments: [PromptExperiment]

    @State private var expandedGaps: Set<Int> = []
    @State private var isCopied = false

    // All gap indices that appear in at least one selected run
    private var allGapIndices: [Int] {
        selectedRuns.reduce(into: Set<Int>()) { $0.formUnion($1.gapIndices) }.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            alignmentMatrix
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        let totalGaps = allGapIndices.count
        let unanimous = allGapIndices.filter { gap in
            selectedRuns.allSatisfy { $0.gapIndices.contains(gap) }
        }.count
        let singleOnly = allGapIndices.filter { gap in
            selectedRuns.filter { $0.gapIndices.contains(gap) }.count == 1
        }.count
        let partial = totalGaps - unanimous - singleOnly

        return HStack(spacing: 12) {
            agreementPill(count: unanimous, label: "Unanimous", color: .green)
            agreementPill(count: partial, label: "Partial", color: .yellow)
            agreementPill(count: singleOnly, label: "Single", color: .red)

            Spacer()

            Text("\(selectedRuns.count) runs")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func agreementPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.caption.bold())
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Alignment Matrix

    private var alignmentMatrix: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                matrixHeader

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(allGapIndices, id: \.self) { gapIndex in
                            matrixRow(gapIndex: gapIndex)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Matrix Header

    private var matrixHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Split")
                    .font(.caption2.bold())
                Text("After")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(width: 44, alignment: .leading)

            ForEach(selectedRuns) { run in
                verticalRunLabel(run)
                    .frame(width: 36)
            }

            Text("Agree")
                .font(.caption2.bold())
                .frame(width: 44)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private func verticalRunLabel(_ run: SelectableRun) -> some View {
        // Break label into parts for vertical stacking
        let parts = [
            "E\(run.experimentIndex)",
            "S\(run.sisterRunNumber)",
            run.variantType.shortLabel,
            run.passType.shortLabel
        ]

        return VStack(spacing: 1) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
            }
        }
        .foregroundColor(run.color)
        .lineLimit(1)
    }

    // MARK: - Matrix Row

    private func matrixRow(gapIndex: Int) -> some View {
        let voteCount = selectedRuns.filter { $0.gapIndices.contains(gapIndex) }.count
        let totalRuns = selectedRuns.count
        let isExpanded = expandedGaps.contains(gapIndex)
        let agreeColor = agreementColor(votes: voteCount, total: totalRuns)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedGaps.remove(gapIndex)
                    } else {
                        expandedGaps.insert(gapIndex)
                    }
                }
            } label: {
                HStack(spacing: 0) {
                    Text("[\(gapIndex + 1)]")
                        .font(.caption.monospaced())
                        .frame(width: 44, alignment: .leading)

                    ForEach(selectedRuns) { run in
                        let voted = run.gapIndices.contains(gapIndex)
                        Circle()
                            .fill(voted ? run.color : run.color.opacity(0.08))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(run.color.opacity(0.3), lineWidth: voted ? 0 : 0.5)
                            )
                            .frame(width: 36)
                    }

                    Text("\(voteCount)/\(totalRuns)")
                        .font(.caption2.bold())
                        .foregroundColor(agreeColor)
                        .frame(width: 44)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(agreeColor.opacity(0.04))
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                expandedRowDetail(gapIndex: gapIndex, voteCount: voteCount)
            }

            Divider().padding(.leading, 8)
        }
    }

    private func expandedRowDetail(gapIndex: Int, voteCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sentence context — gap is AFTER this sentence, so gapIndex = last sentence of outgoing section
            if gapIndex < sentences.count {
                HStack(alignment: .top, spacing: 4) {
                    Text("END")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.red.opacity(0.7))
                        .frame(width: 28)
                    Text("[\(gapIndex + 1)] \"\(sentences[gapIndex])\"")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
            if gapIndex + 1 < sentences.count {
                HStack(alignment: .top, spacing: 4) {
                    Text("START")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7))
                        .frame(width: 28)
                    Text("[\(gapIndex + 2)] \"\(sentences[gapIndex + 1])\"")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .padding(.bottom, 2)
            }

            Text("\(voteCount)/\(selectedRuns.count) runs voted boundary")
                .font(.caption2.bold())

            // Show which runs voted — with reasoning
            ForEach(selectedRuns.filter { $0.gapIndices.contains(gapIndex) }) { run in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(run.color)
                            .frame(width: 6, height: 6)
                        Text(run.label)
                            .font(.caption2.bold().monospaced())
                            .foregroundColor(run.color)
                        Text("(\(run.experimentLabel))")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    // Show boundary reasoning from the splitter result
                    let info = lookupBoundaryInfo(run: run, gapIndex: gapIndex)
                    if let moves = info.moves {
                        Text(moves)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(run.color.opacity(0.8))
                            .padding(.leading, 14)
                    }
                    if !info.reasons.isEmpty {
                        ForEach(Array(info.reasons.enumerated()), id: \.offset) { _, reason in
                            Text(reason)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .padding(.leading, 14)
                        }
                    }
                    if let confidence = info.confidence {
                        Text("Confidence: \(String(format: "%.0f%%", confidence * 100)) (\(info.windowVotes)/\(info.windowsOverlapping) windows)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.leading, 14)
                    }
                }
            }

            // Show which runs did NOT vote
            let nonVoters = selectedRuns.filter { !$0.gapIndices.contains(gapIndex) }
            if !nonVoters.isEmpty {
                Text("Not detected by: \(nonVoters.map { $0.shortLabel }.joined(separator: ", "))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
    }

    // MARK: - Config Comparison (shown at top when runs from different experiments)

    private var hasMultipleExperiments: Bool {
        Set(selectedRuns.map { $0.experimentId }).count > 1
    }

    // MARK: - Boundary Info Lookup

    private struct BoundaryInfo {
        var moves: String?              // "outgoing → incoming"
        var reasons: [String]           // Why this split was detected
        var confidence: Double?         // Vote ratio
        var windowVotes: Int = 0
        var windowsOverlapping: Int = 0
    }

    /// Look up the reasoning for why a specific run detected a boundary at a given gap
    private func lookupBoundaryInfo(run: SelectableRun, gapIndex: Int) -> BoundaryInfo {
        // Find the experiment and sister run
        guard let experiment = experiments.first(where: { $0.id == run.experimentId }),
              let sister = experiment.sisterRuns.first(where: { $0.runNumber == run.sisterRunNumber })
        else { return BoundaryInfo(reasons: []) }

        // Get the right variant
        let variant: ExperimentVariant?
        switch run.variantType {
        case .withDigressions:
            variant = sister.withDigressions
        case .withoutDigressions:
            variant = sister.withoutDigressions
        }

        guard let v = variant else { return BoundaryInfo(reasons: []) }

        let result = v.splitterResult

        // Get the boundaries list based on pass type
        let boundaries: [SectionBoundary]
        switch run.passType {
        case .pass1:
            boundaries = result.pass1Boundaries
        case .final:
            boundaries = result.boundaries
        }

        // The gap index is 0-indexed, but SectionBoundary.sentenceNumber is 1-indexed
        // For without-digressions, gap indices were already remapped to full transcript space
        // So we need to find the boundary that maps to this gap
        // gapIndex (0-indexed) corresponds to sentenceNumber = gapIndex + 1 (split AFTER sentence gapIndex+1)

        // For with-digressions variant, direct match
        // For without-digressions, the gapIndices were remapped, so we need to reverse-map
        let matchingSentenceNumber: Int
        if run.variantType == .withoutDigressions, let map = v.cleanToFullIndexMap {
            // Reverse lookup: find the clean index that maps to this full index
            let reverseMap = Dictionary(uniqueKeysWithValues: map.map { ($0.value, $0.key) })
            if let cleanIdx = reverseMap[gapIndex] {
                matchingSentenceNumber = cleanIdx + 1
            } else {
                return BoundaryInfo(reasons: [])
            }
        } else {
            matchingSentenceNumber = gapIndex + 1
        }

        guard let boundary = boundaries.first(where: { $0.sentenceNumber == matchingSentenceNumber })
        else { return BoundaryInfo(reasons: []) }

        // Also look for window-level moves from the merged results
        var moves: String?
        let windowResults = run.passType == .pass1 ? result.pass1Results : result.mergedResults
        let votingWindows = windowResults.filter { $0.splitAfterSentence == matchingSentenceNumber }
        if let firstVote = votingWindows.first {
            let outgoing = firstVote.outgoingMove ?? "?"
            let incoming = firstVote.incomingMove ?? "?"
            moves = "\(outgoing) → \(incoming)"
        }

        // Deduplicate reasons
        let uniqueReasons = Array(Set(boundary.reasons)).sorted()

        return BoundaryInfo(
            moves: moves,
            reasons: uniqueReasons,
            confidence: boundary.confidence,
            windowVotes: boundary.windowVotes,
            windowsOverlapping: boundary.windowsOverlapping
        )
    }

    // MARK: - Helpers

    private func agreementColor(votes: Int, total: Int) -> Color {
        if votes == total { return .green }
        if votes == 1 { return .red }
        let ratio = Double(votes) / Double(total)
        if ratio >= 0.5 { return .yellow }
        return .orange
    }
}
