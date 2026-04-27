//
//  CodexPairwiseDetailView.swift
//  NewAgentBuilder
//
//  Created by Codex on 3/1/26.
//

import SwiftUI

struct CodexPairwiseDetailView: View {
    let result: GroundTruthResult
    let comparison: PairwiseRunComparison

    private var leftRun: CodexComparableRun? { result.codexRun(withId: comparison.leftRunId) }
    private var rightRun: CodexComparableRun? { result.codexRun(withId: comparison.rightRunId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(leftRun?.displayName ?? comparison.leftRunId)
                    .font(.headline)
                    .foregroundColor(leftRun?.color ?? .primary)
                Image(systemName: "arrow.left.and.right")
                    .foregroundColor(.secondary)
                Text(rightRun?.displayName ?? comparison.rightRunId)
                    .font(.headline)
                    .foregroundColor(rightRun?.color ?? .primary)
            }

            HStack(spacing: 16) {
                stat("Similarity", "\(Int(comparison.jaccardSimilarity * 100))%")
                stat("Shared", "\(comparison.sharedBoundaryCount)")
                stat("Left Only", "\(comparison.leftOnlyCount)")
                stat("Right Only", "\(comparison.rightOnlyCount)")
            }

            if comparison.disagreementGapIndices.isEmpty {
                Text("These runs have no disagreement gaps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Disagreement Gaps")
                    .font(.subheadline.bold())

                ForEach(comparison.disagreementGapIndices, id: \.self) { gapIndex in
                    disagreementRow(gapIndex: gapIndex)
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func disagreementRow(gapIndex: Int) -> some View {
        let leftHas = leftRun?.boundaryGapIndices.contains(gapIndex) ?? false
        let rightHas = rightRun?.boundaryGapIndices.contains(gapIndex) ?? false

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("[\(gapIndex + 1)]")
                    .font(.caption.bold().monospaced())
                Text(leftHas ? "Left" : "Right")
                    .font(.caption2.bold())
                    .foregroundColor(leftHas ? (leftRun?.color ?? .primary) : (rightRun?.color ?? .primary))
                Text("only")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let before = transcriptLine(at: gapIndex) {
                Text(before)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let after = transcriptLine(at: gapIndex + 1) {
                Text(after)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if let leftRun {
                    labelForRun(leftRun, isActive: leftHas, gapIndex: gapIndex)
                }
                if let rightRun {
                    labelForRun(rightRun, isActive: rightHas, gapIndex: gapIndex)
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func labelForRun(_ run: CodexComparableRun, isActive: Bool, gapIndex: Int) -> some View {
        let detailText: String
        if let detail = run.detail(forGap: gapIndex), isActive {
            if let trigger = detail.triggerType {
                detailText = trigger
            } else if let windowVotes = detail.windowVotes, let windows = detail.windowsOverlapping {
                detailText = "\(windowVotes)/\(windows) windows"
            } else {
                detailText = "boundary"
            }
        } else {
            detailText = isActive ? "boundary" : "no boundary"
        }

        return HStack(spacing: 4) {
            Text(run.shortLabel)
                .font(.caption2.bold().monospaced())
                .foregroundColor(run.color)
            Text(detailText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func transcriptLine(at sentenceIndex: Int) -> String? {
        let vote = result.codexActiveVotes.first { $0.gapAfterSentenceIndex == sentenceIndex }
        if let vote {
            return sentenceIndex == vote.gapAfterSentenceIndex ? vote.sentenceText : vote.nextSentenceText
        }

        let previousVote = result.codexActiveVotes.first { $0.gapAfterSentenceIndex == sentenceIndex - 1 }
        if let previousVote, sentenceIndex > 0 {
            return previousVote.nextSentenceText
        }

        return nil
    }
}
