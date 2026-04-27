//
//  RhetoricalAlignmentView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/28/26.
//

import SwiftUI

/// Side-by-side visualization of two videos' rhetorical sequences
/// Shows how the argumentative structures align (or don't)
struct RhetoricalAlignmentView: View {
    let result: RhetoricalTwinResult

    @Environment(\.dismiss) private var dismiss
    @State private var showDescriptions = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Summary header
                    summaryHeader

                    Divider()

                    // Alignment grid
                    alignmentGrid
                }
            }
            .navigationTitle("Rhetorical Alignment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $showDescriptions) {
                        Image(systemName: "text.quote")
                    }
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            // Match score
            HStack {
                matchScoreView
                Spacer()
                statsView
            }

            Divider()

            // Video IDs
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Label("Video A", systemImage: "a.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(result.video1Id)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading) {
                    Label("Video B", systemImage: "b.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(result.video2Id)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
    }

    private var matchScoreView: some View {
        let percentage = Int(result.matchScore * 100)

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(percentage)%")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(scoreColor(percentage))

            Text("Rhetorical Match")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statsView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text("Edit Distance:")
                    .foregroundColor(.secondary)
                Text("\(result.editDistance)")
                    .fontWeight(.semibold)
            }
            .font(.caption)

            HStack {
                Text("Aligned Moves:")
                    .foregroundColor(.secondary)
                Text("\(result.alignedMoves.count)")
                    .fontWeight(.semibold)
            }
            .font(.caption)

            HStack {
                Text("Exact Matches:")
                    .foregroundColor(.secondary)
                Text("\(exactMatchCount)")
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
            .font(.caption)
        }
    }

    private var exactMatchCount: Int {
        result.alignedMoves.filter { $0.isMatch }.count
    }

    // MARK: - Alignment Grid

    private var alignmentGrid: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 30)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Video A")
                    .frame(maxWidth: .infinity)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)

                Text("Video B")
                    .frame(maxWidth: .infinity)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color.secondary.opacity(0.1))

            // Aligned rows
            ForEach(Array(result.alignedMoves.enumerated()), id: \.offset) { index, pair in
                AlignedMoveRow(
                    index: index,
                    pair: pair,
                    showDescription: showDescriptions
                )

                if index < result.alignedMoves.count - 1 {
                    Divider()
                        .padding(.leading, 30)
                }
            }
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ percentage: Int) -> Color {
        if percentage >= 80 { return .green }
        if percentage >= 60 { return .orange }
        return .red
    }
}

// MARK: - Aligned Move Row

struct AlignedMoveRow: View {
    let index: Int
    let pair: AlignedMovePair
    let showDescription: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Row number
            Text("\(index + 1)")
                .frame(width: 30)
                .font(.caption)
                .foregroundColor(.secondary)

            // Move 1 (Video A)
            moveCell(pair.move1, isVideoA: true)
                .frame(maxWidth: .infinity)

            // Match indicator
            matchIndicator
                .frame(width: 30)

            // Move 2 (Video B)
            moveCell(pair.move2, isVideoA: false)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(pair.isMatch ? Color.green.opacity(0.05) : Color.clear)
    }

    @ViewBuilder
    private func moveCell(_ move: RhetoricalMove?, isVideoA: Bool) -> some View {
        if let move = move {
            VStack(alignment: .leading, spacing: 4) {
                // Move label with category color
                HStack(spacing: 4) {
                    Circle()
                        .fill(categoryColor(move.moveType.category))
                        .frame(width: 8, height: 8)

                    Text(move.moveType.displayName)
                        .font(.caption)
                        .fontWeight(.medium)

                    if move.isLowConfidence {
                        Image(systemName: "questionmark.circle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                // Confidence
                Text("\(Int(move.confidence * 100))% conf")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Description (if enabled)
                if showDescription && !move.briefDescription.isEmpty {
                    Text(move.briefDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        } else {
            // Gap
            VStack {
                Image(systemName: "minus")
                    .foregroundColor(.secondary)
                Text("(gap)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var matchIndicator: some View {
        Group {
            if pair.isMatch {
                Image(systemName: "equal.circle.fill")
                    .foregroundColor(.green)
            } else if pair.isGap {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(.orange)
                    .font(.caption)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
            }
        }
    }

    private func categoryColor(_ category: RhetoricalCategory) -> Color {
        switch category {
        case .hook: return .blue
        case .setup: return .green
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .gray
        case .closing: return .red
        }
    }
}

// MARK: - Copy Report

extension RhetoricalAlignmentView {
    func generateReport() -> String {
        var report = """
        RHETORICAL TWIN ANALYSIS
        ========================

        Video A: \(result.video1Id)
        Video B: \(result.video2Id)

        Match Score: \(Int(result.matchScore * 100))%
        Edit Distance: \(result.editDistance)
        Exact Matches: \(exactMatchCount) of \(result.alignedMoves.count)

        ALIGNED SEQUENCE:
        -----------------

        """

        for (index, pair) in result.alignedMoves.enumerated() {
            let move1Label = pair.move1?.moveType.displayName ?? "(gap)"
            let move2Label = pair.move2?.moveType.displayName ?? "(gap)"
            let matchSymbol = pair.isMatch ? "=" : pair.isGap ? "~" : "≠"

            report += "[\(index + 1)] \(move1Label.padding(toLength: 20, withPad: " ", startingAt: 0)) \(matchSymbol) \(move2Label)\n"

            if let desc1 = pair.move1?.briefDescription, !desc1.isEmpty {
                report += "     A: \(desc1)\n"
            }
            if let desc2 = pair.move2?.briefDescription, !desc2.isEmpty {
                report += "     B: \(desc2)\n"
            }
            report += "\n"
        }

        return report
    }
}

// MARK: - Preview

#Preview {
    Text("Preview requires data")
}
