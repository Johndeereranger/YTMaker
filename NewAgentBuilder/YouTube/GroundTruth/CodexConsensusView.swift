//
//  CodexConsensusView.swift
//  NewAgentBuilder
//
//  Created by Codex on 3/1/26.
//

import SwiftUI

private enum CodexConsensusTab: Int {
    case consensus
    case pairs
    case runs
}

private enum CodexConsensusFilter: String, CaseIterable {
    case all = "All"
    case unanimous = "Unanimous"
    case strong = "Strong"
    case split = "Split"
    case weak = "Weak"
    case disagreements = "Disagreements"
}

struct CodexConsensusView: View {
    let result: GroundTruthResult

    @State private var selectedTab: CodexConsensusTab = .consensus
    @State private var selectedFilter: CodexConsensusFilter = .all
    @State private var selectedPairId: String?
    @State private var selectedRunId: String?

    private var runs: [CodexComparableRun] { result.codexActiveRuns }
    private var votes: [CodexGapVote] { result.codexActiveVotes }
    private var pairwise: [PairwiseRunComparison] { result.codexActivePairwiseComparisons }

    private var selectedPair: PairwiseRunComparison? {
        if let selectedPairId {
            return pairwise.first { $0.id == selectedPairId }
        }
        return pairwise.first
    }

    private var selectedRun: CodexComparableRun? {
        if let selectedRunId {
            return runs.first { $0.id == selectedRunId }
        }
        return runs.first
    }

    var body: some View {
        Group {
            if runs.isEmpty || votes.isEmpty {
                unavailableState
            } else {
                VStack(spacing: 0) {
                    summarySection
                    tabPicker
                    tabContent
                }
                .onAppear {
                    if selectedPairId == nil {
                        selectedPairId = pairwise.first?.id
                    }
                    if selectedRunId == nil {
                        selectedRunId = runs.first?.id
                    }
                }
            }
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Codex Consensus data is not available for this saved run.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Text("Run the analysis again to generate run-level consensus data.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
        .padding(.horizontal)
    }

    private var summarySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                codexPill("Runs", count: runs.count, color: .primary)
                codexPill("Boundaries", count: votes.filter(\.isBoundary).count, color: .green)
                codexPill("Unanimous", count: result.codexTierCount(.unanimous), color: .green)
                codexPill("Strong", count: result.codexTierCount(.strong), color: .blue)
                codexPill("Split", count: result.codexTierCount(.split), color: .orange)
                codexPill("Weak", count: result.codexTierCount(.weak), color: .gray)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func codexPill(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(8)
    }

    private var tabPicker: some View {
        Picker("Codex Tab", selection: $selectedTab) {
            Text("Consensus").tag(CodexConsensusTab.consensus)
            Text("Pairs").tag(CodexConsensusTab.pairs)
            Text("Runs").tag(CodexConsensusTab.runs)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .consensus:
            consensusTab
        case .pairs:
            pairsTab
        case .runs:
            runsTab
        }
    }

    private var consensusTab: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CodexConsensusFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedFilter == filter ? Color.accentColor : Color.gray.opacity(0.18))
                                .foregroundColor(selectedFilter == filter ? .white : .primary)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredVotes) { vote in
                        codexVoteCard(vote)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private var pairsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CodexRunMatrixView(
                    runs: runs,
                    comparisons: pairwise,
                    selectedPairId: $selectedPairId
                )

                if let selectedPair {
                    CodexPairwiseDetailView(
                        result: result,
                        comparison: selectedPair
                    )
                } else {
                    Text("No run pairs available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private var runsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(runs) { run in
                    Button {
                        selectedRunId = run.id
                    } label: {
                        runCard(run)
                    }
                    .buttonStyle(.plain)
                }

                if let selectedRun {
                    CodexRunDetailView(
                        result: result,
                        run: selectedRun,
                        averageSimilarity: averageSimilarity(for: selectedRun.id)
                    )
                }
            }
            .padding()
        }
    }

    private var filteredVotes: [CodexGapVote] {
        switch selectedFilter {
        case .all:
            return votes
        case .unanimous:
            return votes.filter { $0.consensusTier == .unanimous }
        case .strong:
            return votes.filter { $0.consensusTier == .strong }
        case .split:
            return votes.filter { $0.consensusTier == .split }
        case .weak:
            return votes.filter { $0.consensusTier == .weak }
        case .disagreements:
            return votes.filter { $0.runCount > 0 && $0.runCount < $0.totalRuns }
        }
    }

    private func codexVoteCard(_ vote: CodexGapVote) -> some View {
        let participatingRuns = vote.runIds.compactMap { id in
            result.codexRun(withId: id)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("[\(vote.gapAfterSentenceIndex + 1)]")
                    .font(.headline.monospaced())
                Text("\(vote.runCount)/\(vote.totalRuns)")
                    .font(.headline.bold())
                    .foregroundColor(vote.consensusTier.color)
                Text(vote.consensusTier.label)
                    .font(.subheadline)
                    .foregroundColor(vote.consensusTier.color)
                Spacer()
                if vote.isBoundary {
                    Text("Boundary")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
            }

            Text(vote.sentenceText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                ForEach(participatingRuns) { run in
                    Text(run.shortLabel)
                        .font(.caption2.bold().monospaced())
                        .foregroundColor(run.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(run.color.opacity(0.12))
                        .cornerRadius(6)
                }
            }

            let familyBreakdown = Dictionary(grouping: participatingRuns, by: \.family)
                .map { key, value in "\(key):\(value.count)" }
                .sorted()
                .joined(separator: "  ")
            if !familyBreakdown.isEmpty {
                Text(familyBreakdown)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }

            let hints = reasoningHints(for: vote, runs: participatingRuns)
            if !hints.isEmpty {
                Text(hints.joined(separator: " • "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Divider()

            Text(vote.nextSentenceText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(vote.consensusTier.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(vote.consensusTier.color.opacity(0.18), lineWidth: 1)
        )
    }

    private func runCard(_ run: CodexComparableRun) -> some View {
        let similarity = averageSimilarity(for: run.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(run.color)
                    .frame(width: 10, height: 10)
                Text(run.displayName)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(run.boundaryGapIndices.count) boundaries")
                    .font(.caption)
                    .foregroundColor(run.color)
            }

            HStack(spacing: 12) {
                Text(run.family)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Avg similarity \(Int(similarity * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(run.debugSummary)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding()
        .background(selectedRunId == run.id ? run.color.opacity(0.10) : Color(.tertiarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selectedRunId == run.id ? run.color.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func averageSimilarity(for runId: String) -> Double {
        let related = pairwise.filter { $0.leftRunId == runId || $0.rightRunId == runId }
        guard !related.isEmpty else { return 1.0 }
        return related.map(\.jaccardSimilarity).reduce(0, +) / Double(related.count)
    }

    private func reasoningHints(for vote: CodexGapVote, runs: [CodexComparableRun]) -> [String] {
        var hints: [String] = []
        for run in runs.prefix(3) {
            guard let detail = run.detail(forGap: vote.gapAfterSentenceIndex) else { continue }
            if let trigger = detail.triggerType {
                hints.append("\(run.shortLabel): \(trigger)")
            } else if let windowVotes = detail.windowVotes, let overlapping = detail.windowsOverlapping {
                hints.append("\(run.shortLabel): \(windowVotes)/\(overlapping) windows")
            }
        }
        return hints
    }
}
