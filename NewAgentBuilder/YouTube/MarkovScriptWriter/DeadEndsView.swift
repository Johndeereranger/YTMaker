//
//  DeadEndsView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/3/26.
//
//  Debug surface for dead ends across all chain attempts (Tab 4).
//  Summary by type, per-dead-end diagnostic cards, cross-attempt pattern
//  detection, and "View in Explorer" navigation.
//

import SwiftUI

struct DeadEndsView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @State private var expandedGroupMoves: Set<RhetoricalMoveType> = []
    @State private var showLLMDebugForMoves: Set<RhetoricalMoveType> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let run = coordinator.currentChainRun {
                    if run.deadEnds.isEmpty {
                        noDeadEndsState(run)
                    } else if run.parameters.algorithmType == .treeWalk {
                        treeWalkDeadEndsView(run)
                    } else {
                        typeSummary(run.deadEnds)
                        crossAttemptPatterns(run)
                        deadEndList(run)
                    }
                } else {
                    emptyState
                }
            }
            .padding()
        }
    }

    // MARK: - Tree Walk Grouped View

    private func treeWalkDeadEndsView(_ run: ChainBuildRun) -> some View {
        let grouped = groupByMoveType(run.deadEnds, run: run)

        return VStack(alignment: .leading, spacing: 12) {
            // Summary header
            HStack {
                Text("Dead Ends by Move Type")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(run.deadEnds.count) total across \(grouped.count) move types")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    coordinator.phase = .gapResponse
                } label: {
                    Label("Fill Gaps", systemImage: "pencil.and.outline")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    if let report = treeWalkDeadEndReport(run, grouped: grouped) {
                        MenuCopyButton(
                            text: report,
                            label: "Copy Dead End Report",
                            systemImage: "doc.on.doc"
                        )
                    }
                    MenuCopyButton(
                        text: guidanceSummaryReport(grouped: grouped),
                        label: "Copy Guidance Summary",
                        systemImage: "lightbulb"
                    )
                    if let matrix = coordinator.markovMatrix,
                       let expansionIndex = coordinator.expansionIndex {
                        MenuCopyButton(
                            text: ChainBuildingService.generateDeadEndIntegrityReport(
                                deadEnds: run.deadEnds,
                                gists: coordinator.session.ramblingGists,
                                expansionIndex: expansionIndex,
                                matrix: matrix,
                                parameters: run.parameters,
                                effectiveMaxLength: run.parameters.maxChainLength
                            ),
                            label: "Copy Integrity Audit",
                            systemImage: "checkmark.shield"
                        )
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
            }

            // Type summary bar
            typeSummary(run.deadEnds)

            // Position bottlenecks (from diagnostics)
            if let summary = run.treeWalkSummary, let diag = summary.diagnostics {
                positionBottlenecks(diag)
            }

            // Grouped cards sorted by upside
            ForEach(Array(grouped.enumerated()), id: \.element.moveType) { rank, group in
                treeWalkGroupCard(rank: rank + 1, group: group, run: run)
            }
        }
    }

    private struct MoveTypeGroup {
        let moveType: RhetoricalMoveType
        let deadEnds: [DeadEnd]
        let maxUpside: Double
        let guidance: String
        let guidancePrompt: String
        let debugTrace: String
    }

    private func groupByMoveType(_ deadEnds: [DeadEnd], run: ChainBuildRun) -> [MoveTypeGroup] {
        var moveGroups: [RhetoricalMoveType: [DeadEnd]] = [:]
        for de in deadEnds {
            for move in de.rawCandidateMoveTypes {
                moveGroups[move, default: []].append(de)
            }
        }

        return moveGroups.map { move, des in
            // Primary: read from per-move-type guidance dict
            let guidance: String
            let prompt: String
            let trace: String
            if let mtg = run.moveTypeGuidance[move] {
                guidance = mtg.guidance
                prompt = mtg.prompt
                trace = mtg.debugTrace
            } else {
                // Backward compat fallback — must match guidanceMoveType to avoid
                // cross-group contamination (dead ends appear in multiple groups,
                // and the last enrichment writer overwrites ramblingGuidance)
                let fallbackDe = des.first(where: {
                    !$0.ramblingGuidance.isEmpty && $0.guidanceMoveType == move.displayName
                })
                guidance = fallbackDe?.ramblingGuidance ?? ""
                prompt = fallbackDe?.guidancePrompt ?? ""
                trace = ""
            }

            return MoveTypeGroup(
                moveType: move,
                deadEnds: des,
                maxUpside: des.map(\.upsideScore).max() ?? 0,
                guidance: guidance,
                guidancePrompt: prompt,
                debugTrace: trace
            )
        }
        .sorted { $0.maxUpside > $1.maxUpside }
    }

    private func treeWalkGroupCard(rank: Int, group: MoveTypeGroup, run: ChainBuildRun) -> some View {
        let isExpanded = expandedGroupMoves.contains(group.moveType)

        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("#\(rank)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                moveTypeBadge(group.moveType)

                Text("[\(group.moveType.category.rawValue)]")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(group.deadEnds.count) dead ends")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("upside \(String(format: "%.2f", group.maxUpside))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.blue)

                Button {
                    withAnimation {
                        if isExpanded {
                            expandedGroupMoves.remove(group.moveType)
                        } else {
                            expandedGroupMoves.insert(group.moveType)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }

            // Stats row
            let avgProgress = group.deadEnds.map { Double($0.positionIndex) }.reduce(0, +) / Double(max(group.deadEnds.count, 1))
            let avgProgressPct = Int(avgProgress / Double(max(coordinator.session.parameters.maxChainLength, 1)) * 100)
            let distinctArcs = Set(group.deadEnds.map { $0.pathSoFar.hashValue }).count

            HStack(spacing: 12) {
                Text("Avg depth: \(avgProgressPct)%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Starters blocked: \(distinctArcs)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Cascade analysis
            if let cascade = coordinator.currentChainRun?.cascadeResults.first(where: { $0.moveType == group.moveType }) {
                cascadeInfoSection(cascade)
            }

            // LLM Guidance
            if !group.guidance.isEmpty {
                let showDebug = showLLMDebugForMoves.contains(group.moveType)

                VStack(alignment: .leading, spacing: 6) {
                    // Guidance text + debug toggle
                    HStack(alignment: .top) {
                        Text(group.guidance)
                            .font(.caption)
                            .foregroundColor(.blue.opacity(0.9))

                        Spacer()

                        Button {
                            withAnimation {
                                if showDebug {
                                    showLLMDebugForMoves.remove(group.moveType)
                                } else {
                                    showLLMDebugForMoves.insert(group.moveType)
                                }
                            }
                        } label: {
                            Image(systemName: showDebug ? "terminal.fill" : "terminal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // LLM Debug: decision trace + prompt + response
                    if showDebug && !group.guidancePrompt.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            // Copy menu
                            HStack {
                                Text("Decision Trace")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)

                                Spacer()

                                Menu {
                                    MenuCopyButton(
                                        text: group.debugTrace,
                                        label: "Copy Full Trace",
                                        systemImage: "doc.on.doc"
                                    )
                                    MenuCopyButton(
                                        text: group.guidancePrompt,
                                        label: "Copy Prompt Only",
                                        systemImage: "doc.on.doc"
                                    )
                                    MenuCopyButton(
                                        text: "TRACE:\n\(group.debugTrace)\n\nPROMPT:\n\(group.guidancePrompt)\n\nRESPONSE:\n\(group.guidance)",
                                        label: "Copy Everything",
                                        systemImage: "doc.on.doc.fill"
                                    )
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                }
                            }

                            // Decision trace (the full debug)
                            if !group.debugTrace.isEmpty {
                                Text(group.debugTrace)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.orange.opacity(0.85))
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.04))
                                    .cornerRadius(4)
                            } else {
                                Text("No trace data (run was built before trace capture was added)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }

                            // Raw prompt
                            Text("LLM Prompt")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Text(group.guidancePrompt)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.04))
                                .cornerRadius(4)

                            // LLM response
                            Text("LLM Response")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Text(group.guidance)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.blue)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.04))
                                .cornerRadius(4)
                        }
                    } else if showDebug && group.guidancePrompt.isEmpty {
                        Text("No prompt data stored (run was built before debug storage was added)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.04))
                .cornerRadius(6)
            } else if coordinator.isLoading && coordinator.loadingMessage.contains("guidance") {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating guidance...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Expanded: show individual dead ends
            if isExpanded {
                Divider()
                ForEach(group.deadEnds.prefix(20)) { de in
                    deadEndCard(de, run: run)
                }
                if group.deadEnds.count > 20 {
                    Text("... and \(group.deadEnds.count - 20) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func cascadeInfoSection(_ cascade: CascadeResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundColor(.purple)

                Text("fixing adds avg \(String(format: "%.1f", 1.0 + cascade.avgRunwayAfterFix)) positions")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if cascade.completionCount > 0 {
                    Text("\(cascade.completionCount)/\(cascade.deadEndCount) complete")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                } else {
                    Text("0 completions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let nextBlocker = cascade.nextBlockageMove {
                HStack(spacing: 4) {
                    Text("Next blockage:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(nextBlocker.displayName)
                        .font(.system(size: 9))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(categoryColor(nextBlocker.category).opacity(0.15))
                        .cornerRadius(3)
                    Text("(\(cascade.nextBlockageCount)/\(cascade.deadEndCount) paths)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                if cascade.level2CompletionCount > cascade.completionCount {
                    HStack(spacing: 4) {
                        Text("Fix both:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("\(cascade.level2CompletionCount)/\(cascade.deadEndCount) complete")
                            .font(.system(size: 9))
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.04))
        .cornerRadius(6)
    }

    private func moveTypeBadge(_ moveType: RhetoricalMoveType) -> some View {
        Text(moveType.displayName)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor(moveType.category).opacity(0.15))
            .foregroundColor(categoryColor(moveType.category))
            .cornerRadius(4)
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

    // MARK: - Position Bottlenecks

    private func positionBottlenecks(_ diag: TreeWalkDiagnostics) -> some View {
        let bottlenecks = diag.positionStats.filter { $0.avgFilteredCandidates < 1.5 && $0.timesReached > 0 }
            .sorted { $0.avgFilteredCandidates < $1.avgFilteredCandidates }

        return Group {
            if !bottlenecks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Position Bottlenecks")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }

                    Text("Positions where most chains die — avg filtered candidates < 1.5")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    ForEach(bottlenecks, id: \.positionIndex) { stat in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Position \(stat.positionIndex)")
                                    .font(.caption)
                                    .fontWeight(.semibold)

                                Text("\(stat.timesReached) paths reached")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text("avg \(String(format: "%.1f", stat.avgFilteredCandidates)) filtered")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.red)
                            }

                            // Show top filter killer for this position
                            let attr = stat.filterAttribution
                            if attr.totalKilled > 0 {
                                let topFilters: [(String, Int)] = [
                                    ("gist availability", attr.killedByGistAvail),
                                    ("threshold", attr.killedByThreshold),
                                    ("sparse data", attr.killedByObservation),
                                    ("category constraint", attr.killedByCategory),
                                    ("backtrack", attr.killedByBacktrack)
                                ].filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }

                                if let top = topFilters.first {
                                    let pctVal = attr.totalKilled > 0 ? top.1 * 100 / attr.totalKilled : 0
                                    Text("\(pctVal)% killed by \(top.0)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .padding(.leading, 4)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.03))
                .cornerRadius(10)
            }
        }
    }

    private func treeWalkDeadEndReport(_ run: ChainBuildRun, grouped: [MoveTypeGroup]) -> String? {
        guard !run.deadEnds.isEmpty else { return nil }
        var lines: [String] = []
        lines.append("=== Tree Walk Dead End Report ===")
        lines.append("Run: \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Total Dead Ends: \(run.deadEnds.count)")
        lines.append("Move Type Groups: \(grouped.count)")
        lines.append("")

        // Position bottlenecks
        if let summary = run.treeWalkSummary, let diag = summary.diagnostics {
            let bottlenecks = diag.positionStats.filter { $0.avgFilteredCandidates < 1.5 && $0.timesReached > 0 }
                .sorted { $0.avgFilteredCandidates < $1.avgFilteredCandidates }

            if !bottlenecks.isEmpty {
                lines.append("--- Position Bottlenecks ---")
                for stat in bottlenecks {
                    var line = "  Position \(stat.positionIndex): \(stat.timesReached) paths reached, avg \(String(format: "%.1f", stat.avgFilteredCandidates)) filtered candidates"
                    let attr = stat.filterAttribution
                    if attr.totalKilled > 0 {
                        let topFilters: [(String, Int)] = [
                            ("gist availability", attr.killedByGistAvail),
                            ("threshold", attr.killedByThreshold),
                            ("sparse data", attr.killedByObservation),
                            ("category constraint", attr.killedByCategory),
                            ("backtrack", attr.killedByBacktrack)
                        ].filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }

                        if let top = topFilters.first {
                            let pctVal = attr.totalKilled > 0 ? top.1 * 100 / attr.totalKilled : 0
                            line += " (\(pctVal)% killed by \(top.0))"
                        }
                    }
                    lines.append(line)
                }
                lines.append("")
            }
        }

        for (rank, group) in grouped.enumerated() {
            let avgProgress = group.deadEnds.map { Double($0.positionIndex) }.reduce(0, +) / Double(max(group.deadEnds.count, 1))
            let avgProgressPct = Int(avgProgress / Double(max(run.parameters.maxChainLength, 1)) * 100)
            let distinctArcs = Set(group.deadEnds.map { $0.pathSoFar.hashValue }).count

            lines.append("#\(rank + 1)  \(group.moveType.displayName) [\(group.moveType.category.rawValue)]  -- \(group.deadEnds.count) dead ends, upside \(String(format: "%.2f", group.maxUpside))")
            lines.append("    Avg depth: \(avgProgressPct)% | Starters blocked: \(distinctArcs)")
            if let cascade = coordinator.currentChainRun?.cascadeResults.first(where: { $0.moveType == group.moveType }) {
                lines.append("    Cascade: fixing adds avg \(String(format: "%.1f", cascade.avgRunwayAfterFix)) positions, \(cascade.completionCount)/\(cascade.deadEndCount) completions")
                if let nextBlocker = cascade.nextBlockageMove {
                    lines.append("    Next blockage: \(nextBlocker.displayName) (\(cascade.nextBlockageCount)/\(cascade.deadEndCount) paths)")
                }
                if cascade.level2CompletionCount > cascade.completionCount, let nb = cascade.nextBlockageMove {
                    lines.append("    Fix both \(group.moveType.displayName) + \(nb.displayName) -> \(cascade.level2CompletionCount)/\(cascade.deadEndCount) completions")
                }
            }
            if !group.guidance.isEmpty {
                lines.append("  -> \"\(group.guidance)\"")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Copies the top 5 dead end groups with their LLM prompt, guidance output,
    /// starters blocked, and next blockage info.
    private func guidanceSummaryReport(grouped: [MoveTypeGroup]) -> String {
        let top5 = Array(grouped.prefix(5))
        var lines: [String] = []

        lines.append("=== Top \(top5.count) Dead End Guidance Summary ===")
        lines.append("")

        for (rank, group) in top5.enumerated() {
            let distinctArcs = Set(group.deadEnds.map { $0.pathSoFar.hashValue }).count

            lines.append(String(repeating: "-", count: 50))
            lines.append("#\(rank + 1)  \(group.moveType.displayName) [\(group.moveType.category.rawValue)]")
            lines.append("Dead ends: \(group.deadEnds.count) | Upside: \(String(format: "%.2f", group.maxUpside)) | Starters blocked: \(distinctArcs)")

            // Cascade / next blockage
            if let cascade = coordinator.currentChainRun?.cascadeResults.first(where: { $0.moveType == group.moveType }) {
                lines.append("Fixing adds avg \(String(format: "%.1f", cascade.avgRunwayAfterFix)) positions, \(cascade.completionCount)/\(cascade.deadEndCount) completions")
                if let nextBlocker = cascade.nextBlockageMove {
                    lines.append("Next blockage: \(nextBlocker.displayName) (\(cascade.nextBlockageCount)/\(cascade.deadEndCount) paths)")
                }
                if cascade.level2CompletionCount > cascade.completionCount, let nb = cascade.nextBlockageMove {
                    lines.append("Fix both \(group.moveType.displayName) + \(nb.displayName) -> \(cascade.level2CompletionCount)/\(cascade.deadEndCount) completions")
                }
            }

            // Decision trace
            if !group.debugTrace.isEmpty {
                lines.append("")
                lines.append("DECISION TRACE:")
                lines.append(group.debugTrace)
            }

            // LLM prompt
            if !group.guidancePrompt.isEmpty {
                lines.append("")
                lines.append("PROMPT:")
                lines.append(group.guidancePrompt)
            }

            // LLM output
            if !group.guidance.isEmpty {
                lines.append("")
                lines.append("GUIDANCE:")
                lines.append(group.guidance)
            } else {
                lines.append("")
                lines.append("GUIDANCE: (none generated)")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Type Summary

    private func typeSummary(_ deadEnds: [DeadEnd]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dead End Summary")
                .font(.subheadline)
                .fontWeight(.semibold)

            let grouped = Dictionary(grouping: deadEnds, by: { $0.deadEndType })

            HStack(spacing: 12) {
                ForEach(DeadEndType.allCases, id: \.self) { type in
                    let count = grouped[type]?.count ?? 0
                    VStack(spacing: 4) {
                        Text("\(count)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(count > 0 ? deadEndColor(type) : .secondary)
                        Text(typeShortName(type))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(count > 0 ? deadEndColor(type).opacity(0.08) : Color.secondary.opacity(0.04))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Cross-Attempt Patterns

    private func crossAttemptPatterns(_ run: ChainBuildRun) -> some View {
        let positionFailures = Dictionary(grouping: run.deadEnds, by: { $0.positionIndex })
        let systemic = positionFailures.filter { $0.value.count >= 2 }

        return Group {
            if !systemic.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("Systemic Gaps")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }

                    Text("These positions failed across multiple chain attempts — a systemic issue, not a single-path problem.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    ForEach(systemic.sorted(by: { $0.key < $1.key }), id: \.key) { posIndex, deadEnds in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Position \(posIndex)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("failed in \(deadEnds.count) attempts")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            // Show the types of failures at this position
                            let types = Set(deadEnds.map(\.deadEndType))
                            HStack(spacing: 4) {
                                ForEach(Array(types), id: \.self) { type in
                                    Text(type.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(deadEndColor(type).opacity(0.15))
                                        .foregroundColor(deadEndColor(type))
                                        .cornerRadius(4)
                                }
                            }

                            // Common missing cause
                            let commonMissing = mostCommon(deadEnds.map(\.whatWasMissing))
                            if let common = commonMissing {
                                Text("Common cause: \(common)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Dead End List

    private func deadEndList(_ run: ChainBuildRun) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All Dead Ends (\(run.deadEnds.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if let report = deadEndReport(run) {
                    Menu {
                        MenuCopyButton(
                            text: report,
                            label: "Copy Dead End Report",
                            systemImage: "doc.on.doc"
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                    }
                }
            }

            ForEach(run.deadEnds) { de in
                deadEndCard(de, run: run)
            }
        }
    }

    private func deadEndCard(_ de: DeadEnd, run: ChainBuildRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                deadEndTypeBadge(de.deadEndType)

                if de.wasBacktrackRetry {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 8))
                        Text("retry")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
                }

                Text("Position \(de.positionIndex)")
                    .font(.caption)
                    .fontWeight(.semibold)

                // Which attempt
                if let attemptIdx = run.chainsAttempted.firstIndex(where: { $0.id == de.chainAttemptId }) {
                    Text("Attempt \(attemptIdx + 1)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    coordinator.navigateToTraceWithDeadEnd(de)
                } label: {
                    Label("Trace", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    let moves = de.pathSoFar.compactMap { RhetoricalMoveType.parse($0) }
                    if !moves.isEmpty {
                        coordinator.navigateToExplorerWithPath(moves)
                    }
                } label: {
                    Label("Explorer", systemImage: "arrow.right.circle")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            // Path so far
            if !de.pathSoFar.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(de.pathSoFar.enumerated()), id: \.offset) { idx, moveName in
                            Text(abbreviate(moveName))
                                .font(.system(size: 8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(idx == de.pathSoFar.count - 1
                                    ? Color.red.opacity(0.15)
                                    : Color.secondary.opacity(0.1))
                                .cornerRadius(3)
                        }
                        // Dead end marker
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
            }

            // Lookup info
            if de.lookupDepthUsed > 0 || !de.lookupKey.isEmpty {
                HStack(spacing: 4) {
                    Text("Lookup:")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text("depth \(de.lookupDepthUsed)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(de.lookupKey)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Candidate details
            if de.candidatesFound > 0 && !de.candidateDetails.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Candidates: \(de.candidatesFound)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(de.candidateDetails.prefix(8)) { cd in
                        HStack(spacing: 4) {
                            Text(abbreviate(cd.moveName))
                                .font(.system(size: 9, design: .monospaced))
                                .frame(width: 65, alignment: .leading)
                            Text("\(Int(cd.probability * 100))%")
                                .font(.system(size: 9, design: .monospaced))
                                .frame(width: 24, alignment: .trailing)
                            Text("\(cd.observationCount) obs")
                                .font(.system(size: 9, design: .monospaced))
                                .frame(width: 36, alignment: .trailing)
                            Text(cd.rejectionReason)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(6)
                .background(Color.purple.opacity(0.04))
                .cornerRadius(6)
            }

            // Diagnostic details
            VStack(alignment: .leading, spacing: 4) {
                diagnosticRow(label: "Missing", text: de.whatWasMissing, color: .red)
                diagnosticRow(label: "Action", text: de.suggestedUserAction, color: .blue)
            }
        }
        .padding(10)
        .background(deadEndColor(de.deadEndType).opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(deadEndColor(de.deadEndType).opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Empty / No Dead Ends States

    private func noDeadEndsState(_ run: ChainBuildRun) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("No Dead Ends")
                .font(.headline)
                .foregroundColor(.green)

            Text("All \(run.chainsAttempted.count) chain attempts completed without hitting any dead ends.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Chain Run")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Build a chain first to see dead end diagnostics.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func diagnosticRow(label: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(text)
                .font(.caption2)
                .foregroundColor(color.opacity(0.8))
        }
    }

    private func deadEndTypeBadge(_ type: DeadEndType) -> some View {
        Text(type.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(deadEndColor(type).opacity(0.15))
            .foregroundColor(deadEndColor(type))
            .cornerRadius(4)
    }

    private func deadEndColor(_ type: DeadEndType) -> Color {
        switch type {
        case .missingContent: return .orange
        case .transitionImpossible: return .red
        case .sparseData: return .yellow
        case .coverageGap: return .blue
        }
    }

    private func typeShortName(_ type: DeadEndType) -> String {
        switch type {
        case .missingContent: return "Content"
        case .transitionImpossible: return "Transition"
        case .sparseData: return "Sparse"
        case .coverageGap: return "Coverage"
        }
    }

    private func abbreviate(_ name: String) -> String {
        if name.count <= 8 { return name }
        let firstWord = name.split(separator: " ").first.map(String.init) ?? name
        if firstWord.count <= 8 { return firstWord }
        return String(name.prefix(7)) + "."
    }

    /// Find the most common string in a list
    private func mostCommon(_ strings: [String]) -> String? {
        let counts = Dictionary(grouping: strings, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Report Generation

    private func deadEndReport(_ run: ChainBuildRun) -> String? {
        guard !run.deadEnds.isEmpty else { return nil }
        var lines: [String] = []
        lines.append("=== Dead End Report ===")
        lines.append("Run: \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Total Dead Ends: \(run.deadEnds.count)")
        lines.append("")

        // Summary by type
        let grouped = Dictionary(grouping: run.deadEnds, by: { $0.deadEndType })
        lines.append("--- By Type ---")
        for type in DeadEndType.allCases {
            lines.append("  \(type.rawValue): \(grouped[type]?.count ?? 0)")
        }
        lines.append("")

        // Systemic gaps
        let posFailures = Dictionary(grouping: run.deadEnds, by: { $0.positionIndex })
        let systemic = posFailures.filter { $0.value.count >= 2 }
        if !systemic.isEmpty {
            lines.append("--- Systemic Gaps ---")
            for (pos, des) in systemic.sorted(by: { $0.key < $1.key }) {
                lines.append("  Position \(pos): failed in \(des.count) attempts")
            }
            lines.append("")
        }

        // Individual dead ends with structured data
        lines.append("--- Details ---")
        for de in run.deadEnds {
            let attemptLabel: String
            if let idx = run.chainsAttempted.firstIndex(where: { $0.id == de.chainAttemptId }) {
                attemptLabel = "Attempt \(idx + 1)"
            } else {
                attemptLabel = "Unknown attempt"
            }

            let retryTag = de.wasBacktrackRetry ? " (backtrack retry)" : ""
            lines.append("[\(de.deadEndType.rawValue)] \(attemptLabel), position \(de.positionIndex)\(retryTag)")
            lines.append("  Path: \(de.pathSoFar.joined(separator: " -> "))")

            if de.lookupDepthUsed > 0 || !de.lookupKey.isEmpty {
                lines.append("  Lookup: depth=\(de.lookupDepthUsed), key=\"\(de.lookupKey)\"")
            }

            lines.append("  Candidates found: \(de.candidatesFound)")
            if !de.candidateDetails.isEmpty {
                for cd in de.candidateDetails {
                    let probStr = "\(Int(cd.probability * 100))%"
                    lines.append("    \(cd.moveName.padding(toLength: 20, withPad: " ", startingAt: 0))prob=\(probStr.padding(toLength: 5, withPad: " ", startingAt: 0)) obs=\(cd.observationCount)  -- \(cd.rejectionReason)")
                }
            }

            lines.append("  Missing: \(de.whatWasMissing)")
            lines.append("  Action: \(de.suggestedUserAction)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - DeadEndType CaseIterable

extension DeadEndType: CaseIterable {
    static var allCases: [DeadEndType] {
        [.missingContent, .transitionImpossible, .sparseData, .coverageGap]
    }
}
