//
//  CodexRunDetailView.swift
//  NewAgentBuilder
//
//  Created by Codex on 3/1/26.
//

import SwiftUI

struct CodexRunDetailView: View {
    let result: GroundTruthResult
    let run: CodexComparableRun
    let averageSimilarity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(run.color)
                    .frame(width: 10, height: 10)
                Text(run.displayName)
                    .font(.headline)
                Spacer()
                Text("\(run.boundaryGapIndices.count) boundaries")
                    .font(.caption)
                    .foregroundColor(run.color)
            }

            HStack(spacing: 16) {
                stat("Family", run.family)
                stat("Avg similarity", "\(Int(averageSimilarity * 100))%")
                stat("Duration", durationLabel)
            }

            Text(run.debugSummary)
                .font(.caption)
                .foregroundColor(.secondary)

            if run.boundaryGapIndices.isEmpty {
                Text("This run produced no boundaries.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Boundary Transcript Gaps")
                    .font(.subheadline.bold())

                ForEach(Array(run.boundaryGapIndices).sorted(), id: \.self) { gapIndex in
                    boundaryRow(gapIndex: gapIndex)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var durationLabel: String {
        guard let runDuration = run.runDuration else { return "n/a" }
        return String(format: "%.1fs", runDuration)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func boundaryRow(gapIndex: Int) -> some View {
        let detail = run.detail(forGap: gapIndex)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("[\(gapIndex + 1)]")
                    .font(.caption.bold().monospaced())
                if let detail {
                    if let trigger = detail.triggerType {
                        Text(trigger)
                            .font(.caption2)
                            .foregroundColor(run.color)
                    } else if let windowVotes = detail.windowVotes, let windows = detail.windowsOverlapping {
                        Text("\(windowVotes)/\(windows) windows")
                            .font(.caption2)
                            .foregroundColor(run.color)
                    }
                }
            }

            if let vote = result.codexActiveVotes.first(where: { $0.gapAfterSentenceIndex == gapIndex }) {
                Text(vote.sentenceText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(vote.nextSentenceText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
