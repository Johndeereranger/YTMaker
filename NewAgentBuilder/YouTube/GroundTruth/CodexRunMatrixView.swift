//
//  CodexRunMatrixView.swift
//  NewAgentBuilder
//
//  Created by Codex on 3/1/26.
//

import SwiftUI

struct CodexRunMatrixView: View {
    let runs: [CodexComparableRun]
    let comparisons: [PairwiseRunComparison]
    @Binding var selectedPairId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run Similarity Matrix")
                .font(.headline)

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        matrixHeaderCell("Run")
                        ForEach(runs) { run in
                            matrixHeaderCell(run.shortLabel)
                                .foregroundColor(run.color)
                        }
                    }

                    ForEach(runs) { rowRun in
                        HStack(spacing: 4) {
                            matrixHeaderCell(rowRun.shortLabel)
                                .foregroundColor(rowRun.color)

                            ForEach(runs) { columnRun in
                                matrixCell(rowRun: rowRun, columnRun: columnRun)
                            }
                        }
                    }
                }
            }
        }
    }

    private func matrixHeaderCell(_ label: String) -> some View {
        Text(label)
            .font(.caption2.bold().monospaced())
            .frame(width: 54, height: 28)
    }

    private func matrixCell(rowRun: CodexComparableRun, columnRun: CodexComparableRun) -> some View {
        let isDiagonal = rowRun.id == columnRun.id
        let comparison = lookupComparison(leftId: rowRun.id, rightId: columnRun.id)
        let similarity = isDiagonal ? 1.0 : (comparison?.jaccardSimilarity ?? 0.0)
        let isSelected = comparison?.id == selectedPairId

        return Button {
            if !isDiagonal {
                selectedPairId = comparison?.id
            }
        } label: {
            Text("\(Int(similarity * 100))")
                .font(.caption2.monospacedDigit())
                .foregroundColor(isDiagonal ? .primary : .white)
                .frame(width: 54, height: 28)
                .background(isDiagonal ? Color(.secondarySystemBackground) : color(for: similarity))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
                )
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(isDiagonal)
    }

    private func lookupComparison(leftId: String, rightId: String) -> PairwiseRunComparison? {
        comparisons.first {
            ($0.leftRunId == leftId && $0.rightRunId == rightId) ||
            ($0.leftRunId == rightId && $0.rightRunId == leftId)
        }
    }

    private func color(for similarity: Double) -> Color {
        if similarity >= 0.85 { return .green }
        if similarity >= 0.65 { return .blue }
        if similarity >= 0.40 { return .orange }
        return .red
    }
}
