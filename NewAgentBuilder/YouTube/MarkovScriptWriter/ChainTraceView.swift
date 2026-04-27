//
//  ChainTraceView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/5/26.
//
//  Interactive chain trace explorer.
//  Replays the chain builder's decision process step-by-step,
//  showing candidates, gist consumption, and filtering at each position.
//  Supports what-if branching: pick an alternate candidate and see
//  the cascading effect on downstream positions.
//

import SwiftUI

struct ChainTraceView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourceSelector

                if !coordinator.tracePositions.isEmpty {
                    pathOverviewStrip
                    consumptionProgressBar

                    if coordinator.traceActiveIndex < coordinator.tracePositions.count {
                        positionDetailCard(coordinator.tracePositions[coordinator.traceActiveIndex])
                    }

                    if !coordinator.traceWhatIfOverride.isEmpty {
                        whatIfResetBar
                    }

                    traceReportCopyButton
                } else if coordinator.traceSource != nil {
                    Text("No trace data. Build a chain first.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    emptyState
                }
            }
            .padding()
        }
    }

    // MARK: - Source Selector

    private var sourceSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trace Source")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let run = coordinator.currentChainRun {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Dead ends grouped by starter
                        ForEach(Array(run.deadEnds.enumerated()), id: \.element.id) { idx, de in
                            let isSelected: Bool = {
                                if case .deadEnd(let current) = coordinator.traceSource {
                                    return current.id == de.id
                                }
                                return false
                            }()

                            Button {
                                coordinator.navigateToTraceWithDeadEnd(de)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("DE #\(idx + 1)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                    Text("P\(de.positionIndex)")
                                        .font(.system(size: 9))
                                    Text(abbreviate(de.pathSoFar.last ?? "?"))
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.red.opacity(0.15) : Color.secondary.opacity(0.06))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.red : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Completed chains
                        ForEach(Array(run.chainsCompleted.enumerated()), id: \.element.id) { idx, chain in
                            let isSelected: Bool = {
                                if case .chainAttempt(let current) = coordinator.traceSource {
                                    return current.id == chain.id
                                }
                                return false
                            }()

                            Button {
                                coordinator.navigateToTraceWithChain(chain)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("Chain \(idx + 1)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                    Text("\(chain.positions.count) pos")
                                        .font(.system(size: 9))
                                    Text("\(Int(chain.coverageScore * 100))%")
                                        .font(.system(size: 8))
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.green.opacity(0.15) : Color.secondary.opacity(0.06))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("No chain run available. Build a chain first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Path Overview Strip

    private var pathOverviewStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Path")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(coordinator.tracePositions.count) positions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(coordinator.tracePositions) { pos in
                        let isActive = pos.positionIndex == coordinator.traceActiveIndex
                        let isDeadEnd = pos.positionIndex == coordinator.tracePositions.count - 1
                            && pos.filteredCandidateCount == 0
                            && pos.assignedGistId == nil

                        Button {
                            coordinator.traceActiveIndex = pos.positionIndex
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(pos.positionIndex)")
                                    .font(.system(size: 8))
                                    .foregroundColor(isActive ? .white : .secondary)
                                Text(abbreviate(pos.moveType.displayName))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(isActive ? .white : .primary)
                                    .lineLimit(1)
                                HStack(spacing: 2) {
                                    if pos.assignedGistId != nil {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 7))
                                            .foregroundColor(isActive ? .white : .green)
                                    } else {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 7))
                                            .foregroundColor(isActive ? .white : .red)
                                    }
                                    if pos.isOverridden {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.system(size: 7))
                                            .foregroundColor(isActive ? .white : .purple)
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                isActive ? Color.accentColor
                                : isDeadEnd ? Color.red.opacity(0.15)
                                : categoryColor(pos.moveType.category).opacity(0.15)
                            )
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(pos.isOverridden ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Consumption Progress Bar

    private var consumptionProgressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            let consumed = coordinator.tracePositions.last?.gistsConsumedSoFar ?? 0
            let total = coordinator.tracePositions.first?.totalGists ?? 1

            HStack {
                Text("Gists consumed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(consumed)/\(total)")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(consumed == total ? Color.red : Color.blue)
                        .frame(width: geo.size.width * CGFloat(consumed) / CGFloat(max(total, 1)), height: 6)

                    // Notches for each position
                    HStack(spacing: 0) {
                        ForEach(coordinator.tracePositions) { pos in
                            let frac = CGFloat(pos.gistsConsumedSoFar) / CGFloat(max(total, 1))
                            Color.clear.frame(width: 0)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.3))
                                        .frame(width: 1, height: 8)
                                        .offset(x: geo.size.width * frac)
                                    , alignment: .leading
                                )
                        }
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Position Detail Card

    private func positionDetailCard(_ pos: TracePosition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Text("P\(pos.positionIndex)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(categoryColor(pos.moveType.category))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(pos.moveType.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if pos.isOverridden {
                            Text("WHAT-IF")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15))
                                .foregroundColor(.purple)
                                .cornerRadius(3)
                        }
                    }

                    Text("[\(pos.moveType.category.rawValue)]  lookup: \(pos.lookupDepthUsed)-step  key: \"\(pos.lookupKey)\"")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(pos.gistsConsumedSoFar)/\(pos.totalGists)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                    Text("consumed")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }

            // Assigned gist
            if let chunkIdx = pos.assignedGistChunkIndex, let frame = pos.assignedGistFrame {
                let gist = coordinator.gistForId(pos.assignedGistId ?? UUID())
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("C\(chunkIdx + 1)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text(frame.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(3)
                    if let g = gist {
                        Text(g.gistB.premise)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(6)
                .background(Color.green.opacity(0.04))
                .cornerRadius(6)
            } else if pos.positionIndex < coordinator.tracePositions.count - 1 || pos.assignedGistId == nil {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text("No gist assigned")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .italic()
                }
            }

            // Candidates table
            candidateTable(pos)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
    }

    // MARK: - Candidate Table

    private func candidateTable(_ pos: TracePosition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Candidates")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(pos.rawCandidateCount) raw, \(pos.filteredCandidateCount) pass")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Header row
            HStack(spacing: 0) {
                Text("Move")
                    .frame(width: 100, alignment: .leading)
                Text("Prob")
                    .frame(width: 36, alignment: .trailing)
                Text("Obs")
                    .frame(width: 30, alignment: .trailing)
                Text("Gists")
                    .frame(width: 50, alignment: .trailing)
                Spacer()
                Text("Status")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(.secondary)

            ForEach(pos.candidates) { candidate in
                candidateRow(candidate, positionIndex: pos.positionIndex)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(8)
    }

    private func candidateRow(_ candidate: TraceCandidateStatus, positionIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                // Move name
                HStack(spacing: 3) {
                    Circle()
                        .fill(categoryColor(candidate.moveType.category))
                        .frame(width: 5, height: 5)
                    Text(candidate.moveType.displayName)
                        .lineLimit(1)
                }
                .frame(width: 100, alignment: .leading)

                // Probability
                Text("\(Int(candidate.probability * 100))%")
                    .foregroundColor(probColor(candidate.probability))
                    .frame(width: 36, alignment: .trailing)

                // Observations
                Text("\(candidate.observationCount)")
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)

                // Gists (post-consumption)
                HStack(spacing: 1) {
                    Text("\(candidate.availableGists)/\(candidate.totalGistsForMove)")
                    if candidate.consumedGists > 0 {
                        Text("(\(candidate.consumedGists)used)")
                            .foregroundColor(.orange)
                    }
                }
                .frame(width: 50, alignment: .trailing)

                Spacer()

                // Status
                if candidate.wasSelected {
                    Text("PICKED")
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .frame(width: 60, alignment: .trailing)
                } else if candidate.passesFilter {
                    // What-if button for passing candidates
                    Button {
                        coordinator.applyWhatIf(atPosition: positionIndex, withMove: candidate.moveType)
                    } label: {
                        Text("What if?")
                            .foregroundColor(.purple)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 60, alignment: .trailing)
                } else {
                    Text("FILTERED")
                        .foregroundColor(.red.opacity(0.7))
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .font(.system(size: 10, design: .monospaced))

            // Rejection reason
            if let reason = candidate.rejectionReason {
                Text(reason)
                    .font(.system(size: 8))
                    .foregroundColor(.red.opacity(0.6))
                    .padding(.leading, 108)
            }
        }
        .padding(.vertical, 3)
        .background(
            candidate.wasSelected ? Color.blue.opacity(0.04)
            : candidate.passesFilter ? Color.green.opacity(0.02)
            : Color.red.opacity(0.02)
        )
        .cornerRadius(4)
    }

    // MARK: - What-If Reset Bar

    private var whatIfResetBar: some View {
        HStack {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption)
                .foregroundColor(.purple)

            Text("\(coordinator.traceWhatIfOverride.count) position(s) overridden")
                .font(.caption)
                .foregroundColor(.purple)

            Spacer()

            Button {
                coordinator.clearWhatIf()
            } label: {
                Text("Reset All")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
            .controlSize(.mini)
        }
        .padding(10)
        .background(Color.purple.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Copy Button

    private var traceReportCopyButton: some View {
        FadeOutCopyButton(
            text: traceReportText(),
            label: "Copy Trace",
            systemImage: "doc.on.doc"
        )
    }

    private func traceReportText() -> String {
        var lines: [String] = []
        lines.append("=== Chain Trace Report ===")
        if let source = coordinator.traceSource {
            lines.append("Source: \(source.label)")
        }
        if !coordinator.traceWhatIfOverride.isEmpty {
            lines.append("What-if overrides: \(coordinator.traceWhatIfOverride.count)")
        }
        lines.append("")

        for pos in coordinator.tracePositions {
            let gistLabel: String
            if let idx = pos.assignedGistChunkIndex {
                gistLabel = "C\(idx + 1)"
            } else {
                gistLabel = "no gist"
            }
            let overrideTag = pos.isOverridden ? " [WHAT-IF]" : ""
            lines.append("P\(pos.positionIndex) \(pos.moveType.displayName) [\(pos.moveType.category.rawValue)] \(gistLabel) (\(pos.gistsConsumedSoFar)/\(pos.totalGists) consumed)\(overrideTag)")
            lines.append("  Lookup: \(pos.lookupDepthUsed)-step, key=\"\(pos.lookupKey)\"")
            lines.append("  Candidates (\(pos.rawCandidateCount) raw, \(pos.filteredCandidateCount) pass):")

            for c in pos.candidates {
                let status: String
                if c.wasSelected { status = "PICKED" }
                else if c.passesFilter { status = "passes" }
                else { status = "FILTERED: \(c.rejectionReason ?? "unknown")" }

                lines.append("    \(c.moveType.displayName.padding(toLength: 22, withPad: " ", startingAt: 0)) \(Int(c.probability * 100))%  \(c.observationCount) obs  \(c.availableGists)/\(c.totalGistsForMove) gists\(c.consumedGists > 0 ? " (\(c.consumedGists) consumed)" : "")  \(status)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Chain Trace Explorer")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Build a chain, then tap \"Trace\" on any dead end to step through the chain builder's decisions position by position.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

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

    private func probColor(_ prob: Double) -> Color {
        if prob >= 0.3 { return .green }
        if prob >= 0.1 { return .primary }
        return .orange
    }

    private func abbreviate(_ name: String) -> String {
        if name.count <= 8 { return name }
        let firstWord = name.split(separator: " ").first.map(String.init) ?? name
        if firstWord.count <= 8 { return firstWord }
        return String(name.prefix(7)) + "."
    }
}
