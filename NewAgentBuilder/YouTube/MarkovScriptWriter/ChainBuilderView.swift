//
//  ChainBuilderView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/3/26.
//
//  Debug surface for the chain builder (Tab 3).
//  Build controls, chain visualization with per-position expandable cards,
//  coverage stats, inline dead ends, run history, and copy/export.
//

import SwiftUI

struct ChainBuilderView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator

    @State private var expandedPositionIds: Set<UUID> = []
    @State private var showRunHistory = false
    @State private var selectedDiverseChainIndex: Int = 0
    @State private var loadedChainId: UUID? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                buildControls
                if let run = coordinator.currentChainRun {
                    runSummary(run)

                    if run.parameters.algorithmType == .treeWalk {
                        treeWalkChainSection(run)
                    } else {
                        exhaustiveChainSection(run)
                    }

                    if coordinator.session.chainRuns.count > 1 {
                        runHistorySection
                    }
                } else {
                    emptyState
                }
            }
            .padding()
        }
    }

    // MARK: - Exhaustive Chain Section

    private func exhaustiveChainSection(_ run: ChainBuildRun) -> some View {
        Group {
            if let best = run.bestChain {
                chainPathStrip(best, title: "Best Chain")
                chainPositionCards(best)
                coverageStats(best, run: run)
                unusedGistsSection(best)
                if !run.deadEnds.isEmpty {
                    deadEndsInline(run.deadEnds)
                }
            } else if !run.chainsAttempted.isEmpty {
                allFailedBanner(run)
            }
        }
    }

    // MARK: - Tree Walk Chain Section

    private func treeWalkChainSection(_ run: ChainBuildRun) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Tree walk stats
            if let summary = run.treeWalkSummary {
                treeWalkStats(summary)
            }

            // Diverse chain picker
            if !run.chainsAttempted.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top \(run.chainsAttempted.count) Diverse Chains")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    // Chain picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(run.chainsAttempted.enumerated()), id: \.element.id) { idx, chain in
                                Button {
                                    selectedDiverseChainIndex = idx
                                } label: {
                                    VStack(spacing: 2) {
                                        Text("Chain \(idx + 1)")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                        Text(pct(chain.coverageScore))
                                            .font(.system(size: 9))
                                        if chain.diversityScore > 0 {
                                            Text("div \(String(format: "%.2f", chain.diversityScore))")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(selectedDiverseChainIndex == idx
                                        ? Color.blue.opacity(0.15)
                                        : Color.secondary.opacity(0.06))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedDiverseChainIndex == idx ? Color.blue : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Category arc for selected chain
                    let safeIndex = min(selectedDiverseChainIndex, run.chainsAttempted.count - 1)
                    let selected = run.chainsAttempted[safeIndex]

                    // Tier 1: instant (pure struct data, no gist lookups)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 1) {
                            ForEach(Array(selected.categoryArc.enumerated()), id: \.offset) { _, cat in
                                Rectangle()
                                    .fill(categoryColor(cat))
                                    .frame(width: 12, height: 6)
                            }
                        }
                    }

                    chainPathStrip(selected, title: "Chain \(safeIndex + 1)")
                    coverageStats(selected, run: run)

                    // Tier 2: deferred (heavy position cards + gist lookups)
                    if loadedChainId == selected.id {
                        chainPositionCards(selected)
                        unusedGistsSection(selected)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading positions...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
                .task(id: run.chainsAttempted[min(selectedDiverseChainIndex, run.chainsAttempted.count - 1)].id) {
                    let chainId = run.chainsAttempted[min(selectedDiverseChainIndex, run.chainsAttempted.count - 1)].id
                    expandedPositionIds.removeAll()
                    loadedChainId = nil
                    await Task.yield()
                    loadedChainId = chainId
                }
            } else {
                allFailedBanner(run)
            }

            // Dead end guidance (grouped by move type, sorted by upside)
            if !run.deadEnds.isEmpty {
                deadEndGuidanceSection(run.deadEnds)
            }
        }
    }

    private func treeWalkStats(_ summary: TreeWalkSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tree Walk Stats")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Limiting factor banner
            if let diag = summary.diagnostics {
                limitingFactorBanner(diag, summary: summary)
            } else {
                // Legacy: no diagnostics available
                HStack {
                    Spacer()
                    Text(summary.budgetUsed >= summary.budgetMax ? "budget reached" : "completed")
                        .font(.caption2)
                        .foregroundColor(summary.budgetUsed >= summary.budgetMax ? .orange : .green)
                }
            }

            HStack(spacing: 16) {
                statBadge(value: "\(summary.pathsExplored)", label: "Paths")
                statBadge(value: "\(summary.pathsCompleted)", label: "Completed")
                statBadge(value: "\(summary.pathsFailed)", label: "Failed")
                statBadge(value: "\(summary.totalDeadEndsHit)", label: "Dead Ends")
                statBadge(value: "\(summary.diverseChainIndices.count)", label: "Selected")
            }

            // Gist branching stats
            if let diag = summary.diagnostics, diag.gistBranchingEnabled {
                HStack(spacing: 16) {
                    statBadge(value: String(format: "%.1f", diag.avgGistBranchesPerPosition ?? 0), label: "Avg Gist Branches")
                    statBadge(value: "\(diag.totalGistBranches ?? 0)", label: "Total Gist Branches")
                }
            }

            // Branching factor + filter attribution
            if let diag = summary.diagnostics, !diag.positionStats.isEmpty {
                branchingFactorTable(diag)
                filterAttributionSummary(diag)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Limiting Factor Banner

    private func limitingFactorBanner(_ diag: TreeWalkDiagnostics, summary: TreeWalkSummary) -> some View {
        let factor = diag.limitingFactor
        let bannerColor: Color
        let icon: String
        let detail: String

        switch factor {
        case .treeExhausted:
            bannerColor = .purple
            icon = "tree"
            detail = "Only \(summary.pathsExplored) paths exist — all explored"
        case .sparseCorpus:
            bannerColor = .orange
            icon = "exclamationmark.triangle"
            detail = "Only \(summary.pathsExplored) paths exist with \(diag.viableStarterCount) starters from \(diag.totalStartersInMatrix) in matrix"
        case .gistBottleneck:
            bannerColor = .red
            icon = "doc.text.magnifyingglass"
            detail = "Tree exhausted — most candidates filtered by gist availability"
        case .thresholdBottleneck:
            bannerColor = .yellow
            icon = "slider.horizontal.below.rectangle"
            detail = "Tree exhausted — most candidates filtered by transition threshold"
        case .budgetReached:
            bannerColor = .blue
            icon = "speedometer"
            detail = "\(summary.pathsExplored)/\(summary.budgetMax) paths explored — budget reached"
        }

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(bannerColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(factor.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(bannerColor)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(bannerColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(bannerColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Branching Factor Table

    private func branchingFactorTable(_ diag: TreeWalkDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Branching Factor by Position")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            // Find bottleneck (lowest avg filtered candidates, ignoring pos 0)
            let bottleneckPos = diag.positionStats
                .filter { $0.positionIndex > 0 }
                .min(by: { $0.avgFilteredCandidates < $1.avgFilteredCandidates })?.positionIndex

            ForEach(diag.positionStats, id: \.positionIndex) { stat in
                let isBottleneck = stat.positionIndex == bottleneckPos && stat.avgFilteredCandidates < 1.5
                HStack(spacing: 6) {
                    Text("Pos \(stat.positionIndex)")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 40, alignment: .leading)

                    Text(String(format: "%.1f", stat.avgRawCandidates))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    Text("raw")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Text(String(format: "%.1f", stat.avgFilteredCandidates))
                        .font(.system(size: 10, design: .monospaced))
                        .fontWeight(isBottleneck ? .bold : .regular)
                        .foregroundColor(isBottleneck ? .red : .primary)
                        .frame(width: 28, alignment: .trailing)
                    Text("filtered")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Text("(\(stat.timesReached)x)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    if isBottleneck {
                        Text("bottleneck")
                            .font(.system(size: 8))
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(3)
                    }

                    Spacer()
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - Filter Attribution Summary

    private func filterAttributionSummary(_ diag: TreeWalkDiagnostics) -> some View {
        // Aggregate across all positions
        let total = diag.positionStats.reduce(into: FilterAttribution()) { result, stat in
            result.killedByThreshold += stat.filterAttribution.killedByThreshold
            result.killedByObservation += stat.filterAttribution.killedByObservation
            result.killedByCategory += stat.filterAttribution.killedByCategory
            result.killedByGistAvail += stat.filterAttribution.killedByGistAvail
            result.killedByBacktrack += stat.filterAttribution.killedByBacktrack
            result.totalKilled += stat.filterAttribution.totalKilled
        }

        let filters: [(String, Int, Color)] = [
            ("Gist Availability", total.killedByGistAvail, .red),
            ("Threshold", total.killedByThreshold, .orange),
            ("Sparse Data", total.killedByObservation, .yellow),
            ("Category", total.killedByCategory, .purple),
            ("Backtrack", total.killedByBacktrack, .gray)
        ].filter { $0.1 > 0 }

        return Group {
            if total.totalKilled > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filter Attribution (\(total.totalKilled) candidates killed)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(filters, id: \.0) { name, count, color in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color)
                                .frame(width: 6, height: 6)
                            Text(name)
                                .font(.caption2)
                                .frame(width: 100, alignment: .leading)

                            // Bar
                            GeometryReader { geo in
                                let pct = total.totalKilled > 0 ? CGFloat(count) / CGFloat(total.totalKilled) : 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color.opacity(0.4))
                                    .frame(width: geo.size.width * pct, height: 10)
                            }
                            .frame(height: 10)

                            Text("\(total.totalKilled > 0 ? count * 100 / total.totalKilled : 0)%")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.03))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Dead End Guidance (Tree Walk)

    private func deadEndGuidanceSection(_ deadEnds: [DeadEnd]) -> some View {
        let grouped = groupDeadEndsByMoveType(deadEnds)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Dead Ends by Move Type (ranked by upside)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.red)

            ForEach(Array(grouped.enumerated()), id: \.element.moveType) { rank, group in
                deadEndGroupCard(rank: rank + 1, group: group)
            }
        }
    }

    private struct DeadEndGroup {
        let moveType: RhetoricalMoveType
        let deadEnds: [DeadEnd]
        let upside: Double
        let guidance: String
        let avgProgress: Double
        let distinctArcs: Int
        let cascade: CascadeResult?
    }

    private func groupDeadEndsByMoveType(_ deadEnds: [DeadEnd]) -> [DeadEndGroup] {
        var moveGroups: [RhetoricalMoveType: [DeadEnd]] = [:]
        for de in deadEnds {
            for move in de.rawCandidateMoveTypes {
                moveGroups[move, default: []].append(de)
            }
        }

        let cascadeResults = coordinator.currentChainRun?.cascadeResults ?? []
        return moveGroups.map { move, des in
            let maxUpside = des.map(\.upsideScore).max() ?? 0
            let guidance = coordinator.currentChainRun?.moveTypeGuidance[move]?.guidance
                ?? des.first(where: { !$0.ramblingGuidance.isEmpty && $0.guidanceMoveType == move.displayName })?.ramblingGuidance
                ?? ""
            let avgProg = des.map { Double($0.positionIndex) }.reduce(0, +) / Double(max(des.count, 1))
            let distinctArcs = Set(des.map { $0.pathSoFar.hashValue }).count
            let cascade = cascadeResults.first(where: { $0.moveType == move })
            return DeadEndGroup(
                moveType: move, deadEnds: des, upside: maxUpside,
                guidance: guidance, avgProgress: avgProg, distinctArcs: distinctArcs,
                cascade: cascade
            )
        }
        .sorted { $0.upside > $1.upside }
    }

    private func deadEndGroupCard(rank: Int, group: DeadEndGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(rank)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                Text(group.moveType.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("[\(group.moveType.category.rawValue)]")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(categoryColor(group.moveType.category).opacity(0.15))
                    .cornerRadius(3)

                Spacer()

                Text("\(group.deadEnds.count) dead ends")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("upside \(String(format: "%.2f", group.upside))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.blue)
            }

            HStack(spacing: 12) {
                Text("Avg depth: \(String(format: "%.0f%%", group.avgProgress / Double(max(coordinator.session.parameters.maxChainLength, 1)) * 100))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Starters blocked: \(group.distinctArcs)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Cascade analysis
            if let cascade = group.cascade {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundColor(.purple)

                        Text("fixing adds avg \(String(format: "%.1f", cascade.avgRunwayAfterFix)) positions")
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

            // LLM guidance
            if !group.guidance.isEmpty {
                Text(group.guidance)
                    .font(.caption)
                    .foregroundColor(.blue.opacity(0.9))
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
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Build Controls

    private var buildControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    coordinator.buildChain()
                } label: {
                    Label("Build Chain", systemImage: "link.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.markovMatrix == nil || coordinator.session.ramblingGists.isEmpty)

                if coordinator.session.parameters.algorithmType == .treeWalk {
                    Toggle(isOn: Binding(
                        get: { coordinator.session.parameters.enableGistBranching },
                        set: { coordinator.session.parameters.enableGistBranching = $0 }
                    )) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()

                    // Active mode indicator
                    if coordinator.session.parameters.enableGistBranching {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Gist Branching")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("max \(coordinator.session.parameters.maxGistBranchesPerMove)/move")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                    } else {
                        Text("Greedy")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                if let run = coordinator.currentChainRun, let report = chainReport(run) {
                    Menu {
                        MenuCopyButton(
                            text: report,
                            label: "Copy Chain Report",
                            systemImage: "doc.on.doc"
                        )
                        MenuCopyButton(
                            text: diagnosticReport(run),
                            label: "Copy Diagnostic Report",
                            systemImage: "stethoscope"
                        )
                        if !run.chainsAttempted.isEmpty,
                           let matrix = coordinator.markovMatrix,
                           let index = coordinator.expansionIndex {
                            MenuCopyButton(
                                text: ChainBuildingService.generateConvergenceDiagnostic(
                                    chains: run.chainsAttempted,
                                    matrix: matrix,
                                    expansionIndex: index,
                                    gists: coordinator.session.ramblingGists,
                                    parameters: run.parameters,
                                    treeWalkDiagnostics: run.treeWalkSummary?.diagnostics
                                ),
                                label: "Copy Full Convergence Report",
                                systemImage: "point.3.connected.trianglepath.dotted"
                            )
                            if let chain1 = run.chainsAttempted.first {
                                MenuCopyButton(
                                    text: ChainBuildingService.generateFilterImpactProof(
                                        chain: chain1,
                                        matrix: matrix,
                                        expansionIndex: index,
                                        parameters: run.parameters,
                                        treeWalkDiagnostics: run.treeWalkSummary?.diagnostics
                                    ),
                                    label: "Copy Filter Impact Proof",
                                    systemImage: "wand.and.stars"
                                )
                            }
                            Divider()
                            ForEach(Array(run.chainsAttempted.enumerated()), id: \.offset) { idx, chain in
                                MenuCopyButton(
                                    text: ChainBuildingService.generateSingleChainDiagnostic(
                                        chain: chain,
                                        chainIndex: idx,
                                        matrix: matrix,
                                        expansionIndex: index,
                                        gists: coordinator.session.ramblingGists,
                                        parameters: run.parameters
                                    ),
                                    label: "Copy Chain \(idx + 1) Diagnostic",
                                    systemImage: "number.\(idx + 1).circle"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }

            if coordinator.markovMatrix == nil {
                warningLabel("Build the Markov matrix first (Markov tab)")
            } else if coordinator.session.ramblingGists.isEmpty {
                warningLabel("Load gists first (Input tab)")
            }
        }
    }

    // MARK: - Run Summary

    private func runSummary(_ run: ChainBuildRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(run.parameters.algorithmType.rawValue)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(run.parameters.algorithmType == .treeWalk
                        ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                    .foregroundColor(run.parameters.algorithmType == .treeWalk ? .purple : .blue)
                    .cornerRadius(4)

                Spacer()

                Text(run.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                statBadge(value: "\(run.chainsAttempted.count)", label: run.parameters.algorithmType == .treeWalk ? "Selected" : "Attempts")
                statBadge(value: "\(run.chainsCompleted.count)", label: "Completed")
                statBadge(value: "\(run.chainsFailed.count)", label: "Failed")
                statBadge(value: "\(run.deadEnds.count)", label: "Dead Ends")

                Spacer()
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Chain Path Strip (horizontal move overview)

    private func chainPathStrip(_ chain: ChainAttempt, title: String = "Best Chain") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(chain.positions.count) positions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                statusBadge(chain.status)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(chain.positions) { pos in
                        VStack(spacing: 2) {
                            Text("\(pos.positionIndex)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Text(abbreviate(pos.moveType.displayName))
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(categoryColor(pos.category).opacity(0.15))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    // MARK: - Chain Position Cards

    private func chainPositionCards(_ chain: ChainAttempt) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(chain.positions) { pos in
                positionCard(pos)
            }
        }
    }

    private func positionCard(_ pos: ChainPosition) -> some View {
        let isExpanded = expandedPositionIds.contains(pos.id)

        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                // Position number circle
                Text("\(pos.positionIndex)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(categoryColor(pos.category))
                    .clipShape(Circle())

                Text(pos.moveType.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(pos.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor(pos.category).opacity(0.15))
                    .cornerRadius(4)

                Spacer()

                // Markov probability
                Text(pct(pos.markovProbability))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(probColor(pos.markovProbability))

                // Gist indicator
                if pos.mappedGistId != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.caption2)
                        .foregroundColor(.red)
                }

                Button {
                    withAnimation { togglePosition(pos.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }

            // Selection reason
            Text(pos.selectionReason)
                .font(.caption2)
                .foregroundColor(.secondary)

            // Mapped gist preview
            if let gistId = pos.mappedGistId, let gist = coordinator.gistForId(gistId) {
                HStack(spacing: 6) {
                    Text("C\(gist.chunkIndex + 1)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text(gist.gistA.frame.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(3)
                    Text(gist.gistB.premise)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(Color.blue.opacity(0.04))
                .cornerRadius(6)
            } else {
                Text("No gist mapped (gap)")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .italic()
            }

            // Expanded detail
            if isExpanded {
                expandedPositionDetail(pos)
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private func expandedPositionDetail(_ pos: ChainPosition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Markov context
            VStack(alignment: .leading, spacing: 4) {
                Text("Markov Context")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                ForEach(pos.markovContext, id: \.self) { ctx in
                    Text(ctx)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(6)
            .background(Color.blue.opacity(0.04))
            .cornerRadius(6)

            // Full gist detail
            if let gistId = pos.mappedGistId, let gist = coordinator.gistForId(gistId) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mapped Gist (Chunk \(gist.chunkIndex + 1))")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    Text("Frame: \(gist.gistA.frame.displayName)")
                        .font(.caption2)
                    if let moveLabel = gist.moveLabel {
                        Text("Move Label: \(moveLabel)")
                            .font(.caption2)
                    }
                    Text("Source: \(gist.sourceText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .background(Color.green.opacity(0.04))
                .cornerRadius(6)
            }

            // Alternatives
            if !pos.alternativesConsidered.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alternatives (\(pos.alternativesConsidered.count))")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)

                    ForEach(pos.alternativesConsidered.prefix(8)) { alt in
                        HStack(spacing: 4) {
                            Text(alt.moveType.displayName)
                                .font(.caption2)
                                .frame(maxWidth: 100, alignment: .leading)
                            Text(pct(alt.probability))
                                .font(.system(size: 9, design: .monospaced))
                                .frame(width: 32, alignment: .trailing)
                            Text(alt.rejectionReason)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if pos.alternativesConsidered.count > 8 {
                        Text("... and \(pos.alternativesConsidered.count - 8) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
                .background(Color.orange.opacity(0.04))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Coverage Stats

    private func coverageStats(_ chain: ChainAttempt, run: ChainBuildRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coverage")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                statBadge(value: "\(chain.positions.count)", label: "Positions")
                statBadge(
                    value: "\(chain.gistsUsed.count)/\(run.inputGistCount)",
                    label: "Gists Used"
                )
                statBadge(value: pct(chain.coverageScore), label: "Coverage")
            }

            // Category distribution
            let categoryCounts = Dictionary(grouping: chain.positions, by: { $0.category })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RhetoricalCategory.allCases, id: \.self) { cat in
                        let count = categoryCounts[cat]?.count ?? 0
                        HStack(spacing: 4) {
                            Circle()
                                .fill(categoryColor(cat))
                                .frame(width: 6, height: 6)
                            Text("\(cat.rawValue): \(count)")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(count > 0 ? categoryColor(cat).opacity(0.08) : Color.secondary.opacity(0.05))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Unused Gists

    private func unusedGistsSection(_ chain: ChainAttempt) -> some View {
        Group {
            if !chain.gistsUnused.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unused Gists (\(chain.gistsUnused.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)

                    ForEach(chain.gistsUnused, id: \.self) { gistId in
                        if let gist = coordinator.gistForId(gistId) {
                            HStack {
                                Text("C\(gist.chunkIndex + 1)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                Text(gist.gistA.frame.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(3)
                                if let moveLabel = gist.moveLabel {
                                    Text(moveLabel)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(3)
                                }
                                Spacer()
                                Text(gist.gistB.premise)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 150, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.04))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Inline Dead Ends

    private func deadEndsInline(_ deadEnds: [DeadEnd]) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Text("Dead Ends (\(deadEnds.count))")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.red)

            ForEach(deadEnds) { de in
                deadEndCard(de)
            }
        }
    }

    private func deadEndCard(_ de: DeadEnd) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                deadEndTypeBadge(de.deadEndType)

                Text("Position \(de.positionIndex)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

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

            // Path chips
            if !de.pathSoFar.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(de.pathSoFar.enumerated()), id: \.offset) { _, moveName in
                            Text(abbreviate(moveName))
                                .font(.system(size: 8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                }
            }

            Text("Needed: \(de.whatWasNeeded)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Missing: \(de.whatWasMissing)")
                .font(.caption2)
                .foregroundColor(.red.opacity(0.8))
            Text("Action: \(de.suggestedUserAction)")
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(10)
        .background(deadEndColor(de.deadEndType).opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(deadEndColor(de.deadEndType).opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - All Failed Banner

    private func allFailedBanner(_ run: ChainBuildRun) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundColor(.red)

            Text("All \(run.chainsAttempted.count) Attempts Failed")
                .font(.headline)
                .foregroundColor(.red)

            Text("No chain reached completion. Check dead ends below for diagnostics.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if !run.deadEnds.isEmpty {
                deadEndsInline(run.deadEnds)
            }
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Run History

    private var runHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showRunHistory.toggle() }
            } label: {
                HStack {
                    Text("Run History (\(coordinator.session.chainRuns.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: showRunHistory ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if showRunHistory {
                ForEach(coordinator.session.chainRuns.reversed()) { summary in
                    let isSelected = summary.id == coordinator.currentChainRun?.id

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if let starter = summary.starterMoveName {
                                    Text(starter)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                                Text(summary.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 8) {
                                Text("\(summary.chainsCompletedCount)/\(summary.chainsAttemptedCount) ok")
                                    .font(.caption2)
                                if let coverage = summary.bestCoverageScore {
                                    Text(pct(coverage))
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                                Text("\(summary.deadEndCount) dead ends")
                                    .font(.caption2)
                                    .foregroundColor(summary.deadEndCount == 0 ? .secondary : .orange)
                            }
                        }

                        Spacer()

                        if !isSelected {
                            Button("View") {
                                coordinator.selectChainRun(summary)
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        } else {
                            Text("Current")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(8)
                    .background(isSelected ? Color.blue.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "link")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Chain Built")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Build the Markov matrix, then tap Build Chain to generate a rhetorical chain from your gists.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func togglePosition(_ id: UUID) {
        if expandedPositionIds.contains(id) {
            expandedPositionIds.remove(id)
        } else {
            expandedPositionIds.insert(id)
        }
    }

    private func warningLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundColor(.orange)
            Text(text)
                .font(.caption2)
                .foregroundColor(.orange)
        }
    }

    private func statusBadge(_ status: ChainStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .foregroundColor(statusColor(status))
            .cornerRadius(4)
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

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
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

    private func statusColor(_ status: ChainStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func deadEndColor(_ type: DeadEndType) -> Color {
        switch type {
        case .missingContent: return .orange
        case .transitionImpossible: return .red
        case .sparseData: return .yellow
        case .coverageGap: return .blue
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

    private func pct(_ value: Double) -> String { "\(Int(value * 100))%" }

    // MARK: - Report Generation

    private func chainReport(_ run: ChainBuildRun) -> String? {
        var lines: [String] = []
        lines.append("=== Chain Build Report ===")
        lines.append("Built: \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("")

        // Algorithm header
        switch run.parameters.algorithmType {
        case .treeWalk:
            lines.append("Algorithm: Tree Walk (budget: \(run.parameters.monteCarloSimulations) paths)")
            lines.append("Explores all branches from each starter via depth-first search.")
            lines.append("Completed paths are diversity-selected. Dead ends reveal content gaps.")
        default:
            lines.append("Algorithm: \(run.parameters.algorithmType.rawValue)")
            lines.append("One greedy path per starter with backtracking memory.")
        }
        lines.append("")

        // Matrix stats
        if let matrix = coordinator.markovMatrix {
            lines.append("--- Matrix Stats ---")
            lines.append("Source sequences: \(matrix.sourceSequenceCount) | Total moves: \(matrix.totalMoveCount) | Unique types: \(matrix.uniqueMoveCount)")
            lines.append("Level: \(matrix.useParentLevel ? "Parent (6 categories)" : "Full (25 moves)")")
            lines.append("")
        }

        // Parameters used
        lines.append("--- Parameters ---")
        lines.append("History depth: \(run.parameters.historyDepth) | Threshold: \(pct(run.parameters.transitionThreshold)) | Min obs: \(run.parameters.minObservationCount)")
        lines.append("Max chain: \(run.parameters.maxChainLength) | Coverage target: \(pct(run.parameters.coverageTarget))")
        if run.parameters.enableGistBranching {
            lines.append("Gist branching: ON (max \(run.parameters.maxGistBranchesPerMove)/move)")
        }
        lines.append("")

        // Tree walk stats
        if let summary = run.treeWalkSummary {
            lines.append("--- Tree Walk Stats ---")

            // Limiting factor
            if let diag = summary.diagnostics {
                lines.append("LIMITING FACTOR: \(diag.limitingFactor.rawValue)")
                switch diag.limitingFactor {
                case .treeExhausted:
                    lines.append("  Only \(summary.pathsExplored) paths exist in the tree — all explored")
                case .sparseCorpus:
                    lines.append("  Only \(summary.pathsExplored) paths exist with \(diag.viableStarterCount) starters from \(diag.totalStartersInMatrix) in matrix")
                case .gistBottleneck:
                    lines.append("  Tree exhausted — most candidates filtered by gist availability")
                case .thresholdBottleneck:
                    lines.append("  Tree exhausted — most candidates filtered by transition threshold")
                case .budgetReached:
                    lines.append("  \(summary.pathsExplored)/\(summary.budgetMax) paths explored — budget was the limit")
                }
                lines.append("Viable starters: \(diag.viableStarterCount)/\(diag.totalStartersInMatrix)")
            }

            lines.append("Paths explored: \(summary.pathsExplored)/\(summary.budgetMax)")
            lines.append("Completed: \(summary.pathsCompleted) (\(summary.pathsExplored > 0 ? "\(summary.pathsCompleted * 100 / summary.pathsExplored)%" : "0%")) | Failed: \(summary.pathsFailed)")
            lines.append("Total dead ends: \(summary.totalDeadEndsHit)")
            lines.append("Diverse chains selected: \(summary.diverseChainIndices.count)")
            lines.append("")

            // Branching factor table
            if let diag = summary.diagnostics, !diag.positionStats.isEmpty {
                lines.append("--- Branching Factor by Position ---")
                let bottleneckPos = diag.positionStats
                    .filter { $0.positionIndex > 0 }
                    .min(by: { $0.avgFilteredCandidates < $1.avgFilteredCandidates })?.positionIndex

                for stat in diag.positionStats {
                    let isBottleneck = stat.positionIndex == bottleneckPos && stat.avgFilteredCandidates < 1.5
                    let marker = isBottleneck ? "  <-- bottleneck" : ""
                    lines.append("  Pos \(stat.positionIndex): \(String(format: "%.1f", stat.avgRawCandidates)) raw -> \(String(format: "%.1f", stat.avgFilteredCandidates)) filtered (reached \(stat.timesReached)x)\(marker)")
                }
                lines.append("")

                // Filter attribution
                let total = diag.positionStats.reduce(into: FilterAttribution()) { result, stat in
                    result.killedByThreshold += stat.filterAttribution.killedByThreshold
                    result.killedByObservation += stat.filterAttribution.killedByObservation
                    result.killedByCategory += stat.filterAttribution.killedByCategory
                    result.killedByGistAvail += stat.filterAttribution.killedByGistAvail
                    result.killedByBacktrack += stat.filterAttribution.killedByBacktrack
                    result.totalKilled += stat.filterAttribution.totalKilled
                }

                if total.totalKilled > 0 {
                    lines.append("--- Filter Attribution (\(total.totalKilled) candidates killed) ---")
                    let filters: [(String, Int)] = [
                        ("Gist Availability", total.killedByGistAvail),
                        ("Threshold", total.killedByThreshold),
                        ("Sparse Data", total.killedByObservation),
                        ("Category", total.killedByCategory),
                        ("Backtrack", total.killedByBacktrack)
                    ].filter { $0.1 > 0 }

                    for (name, count) in filters {
                        let pctVal = total.totalKilled > 0 ? count * 100 / total.totalKilled : 0
                        lines.append("  \(name.padding(toLength: 20, withPad: " ", startingAt: 0))\(count) (\(pctVal)%)")
                    }
                    lines.append("")
                }
            }
        }

        // Summary
        lines.append("Chains: \(run.chainsAttempted.count) (\(run.chainsCompleted.count) completed, \(run.chainsFailed.count) failed)")
        lines.append("Dead Ends: \(run.deadEnds.count)")
        lines.append("")

        // Per-chain breakdown
        for (idx, attempt) in run.chainsAttempted.enumerated() {
            let starterLabel = attempt.starterMove ?? attempt.positions.first?.moveType.displayName ?? "?"
            let chainLabel = run.parameters.algorithmType == .treeWalk ? "Chain" : "Attempt"
            lines.append("--- \(chainLabel) \(idx + 1): \(starterLabel) ---")
            let statusStr = attempt.status == .failed
                ? "failed at position \(attempt.failurePoint ?? -1)"
                : attempt.status.rawValue
            var statusLine = "Status: \(statusStr) | Positions: \(attempt.positions.count) | Coverage: \(pct(attempt.coverageScore))"
            if attempt.backtrackCount > 0 {
                statusLine += " | Backtracks: \(attempt.backtrackCount)"
            }
            if attempt.diversityScore > 0 {
                statusLine += " | Diversity: \(String(format: "%.2f", attempt.diversityScore))"
            }
            lines.append(statusLine)
            let path = attempt.positions.map { $0.moveType.displayName }.joined(separator: " -> ")
            lines.append("Path: \(path)")
            let arcStr = attempt.categoryArc.map(\.rawValue).joined(separator: " -> ")
            lines.append("Arc:  \(arcStr)")
            if let reason = attempt.failureReason {
                lines.append("Failure: \(reason)")
            }
            lines.append("")
        }

        // Best chain position details (exhaustive only — tree walk chains are lightweight)
        if run.parameters.algorithmType != .treeWalk, let best = run.bestChain {
            lines.append("--- Best Chain Position Details ---")
            for pos in best.positions {
                lines.append("P\(pos.positionIndex): \(pos.moveType.displayName) [\(pos.category.rawValue)] prob=\(pct(pos.markovProbability))")
                lines.append("  Reason: \(pos.selectionReason)")
                lines.append("  Context: \(pos.markovContext.joined(separator: ", "))")
                if let gistId = pos.mappedGistId, let gist = coordinator.gistForId(gistId) {
                    lines.append("  Gist: Chunk \(gist.chunkIndex + 1) - \(gist.gistA.frame.displayName)")
                }
                if !pos.alternativesConsidered.isEmpty {
                    lines.append("  Alternatives (\(pos.alternativesConsidered.count)):")
                    for alt in pos.alternativesConsidered.prefix(5) {
                        lines.append("    \(alt.moveType.displayName) \(pct(alt.probability)) - \(alt.rejectionReason)")
                    }
                    if pos.alternativesConsidered.count > 5 {
                        lines.append("    ... and \(pos.alternativesConsidered.count - 5) more")
                    }
                }
                lines.append("")
            }
        }

        // Dead end guidance (tree walk: grouped by move type with upside)
        if run.parameters.algorithmType == .treeWalk && !run.deadEnds.isEmpty {
            let grouped = groupDeadEndsByMoveType(run.deadEnds)

            lines.append("--- Dead Ends by Move Type (ranked by chain-completion upside) ---")
            for (rank, group) in grouped.enumerated() {
                let avgProgressPct = Int(group.avgProgress / Double(max(run.parameters.maxChainLength, 1)) * 100)
                lines.append("#\(rank + 1)  \(group.moveType.displayName) [\(group.moveType.category.rawValue)]     -- \(group.deadEnds.count) dead ends, upside \(String(format: "%.2f", group.upside))")
                lines.append("    Avg depth: \(avgProgressPct)% | Starters blocked: \(group.distinctArcs)")
                if let cascade = group.cascade {
                    lines.append("    Cascade: fixing adds avg \(String(format: "%.1f", cascade.avgRunwayAfterFix)) positions, \(cascade.completionCount)/\(cascade.deadEndCount) completions")
                    if let nextBlocker = cascade.nextBlockageMove {
                        lines.append("    Next blockage: \(nextBlocker.displayName) (\(cascade.nextBlockageCount)/\(cascade.deadEndCount) paths)")
                    }
                }
                if !group.guidance.isEmpty {
                    lines.append("  -> \"\(group.guidance)\"")
                }
                lines.append("")
            }
        }

        // Dead ends with structured diagnostics (exhaustive)
        if run.parameters.algorithmType != .treeWalk && !run.deadEnds.isEmpty {
            lines.append("--- Dead Ends ---")
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
                    lines.append("  Candidate breakdown:")
                    for cd in de.candidateDetails {
                        let probStr = "\(Int(cd.probability * 100))%"
                        lines.append("    \(cd.moveName.padding(toLength: 20, withPad: " ", startingAt: 0))prob=\(probStr.padding(toLength: 5, withPad: " ", startingAt: 0)) obs=\(cd.observationCount)  -- \(cd.rejectionReason)")
                    }
                }

                lines.append("  Missing: \(de.whatWasMissing)")
                lines.append("  Action: \(de.suggestedUserAction)")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Diagnostic Report (Why Everything Failed)

    /// Comprehensive diagnostic that answers: WHAT failed, WHAT the raw data showed, WHY the algorithm decided what it did.
    private func diagnosticReport(_ run: ChainBuildRun) -> String {
        var lines: [String] = []
        let gists = coordinator.session.ramblingGists
        let index = coordinator.expansionIndex ?? FrameExpansionIndex(gists: gists)

        lines.append("=== CHAIN DIAGNOSTIC REPORT ===")
        lines.append("Built: \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Algorithm: \(run.parameters.algorithmType.rawValue)")
        if run.parameters.enableGistBranching {
            lines.append("Gist branching: ON (max \(run.parameters.maxGistBranchesPerMove)/move, constraint score \u{2264} 5)")
        }
        lines.append("")

        // ─────────────────────────────────────────
        // SECTION 1: Gist Inventory — What do you have?
        // ─────────────────────────────────────────
        lines.append("═══ SECTION 1: YOUR GIST INVENTORY ═══")
        lines.append("Total gists: \(gists.count)")
        lines.append("")

        // Frame distribution
        let frameCounts = Dictionary(grouping: gists, by: { $0.gistA.frame })
        lines.append("--- Frame Distribution (what your gists are classified as) ---")
        for frame in GistFrame.allCases {
            let frameGists = frameCounts[frame] ?? []
            let expansionMoves = FrameExpansionIndex.expansionMoves(for: frame)
            let moveNames = expansionMoves.map(\.displayName).joined(separator: ", ")
            if frameGists.isEmpty {
                lines.append("  \(frame.displayName): 0 gists")
                lines.append("    Would map to: \(moveNames)")
            } else {
                lines.append("  \(frame.displayName): \(frameGists.count) gists")
                lines.append("    Maps to: \(moveNames)")
                for g in frameGists {
                    let premise = g.gistB.premise
                    let truncated = premise.count > 80 ? String(premise.prefix(77)) + "..." : premise
                    lines.append("      C\(g.chunkIndex + 1): \"\(truncated)\"")
                }
            }
        }
        lines.append("")

        // Per-move coverage
        lines.append("--- Per-Move Gist Coverage (what the chain builder sees) ---")
        var coveredMoveCount = 0
        var uncoveredMoves: [RhetoricalMoveType] = []
        var sparseMoves: [(RhetoricalMoveType, Int)] = []

        for move in RhetoricalMoveType.allCases {
            let eligible = index.moveToGists[move]?.count ?? 0
            let status: String
            if eligible == 0 {
                status = "ZERO"
                uncoveredMoves.append(move)
            } else if eligible == 1 {
                status = "FRAGILE (only 1)"
                sparseMoves.append((move, eligible))
                coveredMoveCount += 1
            } else {
                status = "\(eligible) gists"
                coveredMoveCount += 1
            }
            lines.append("  \(move.displayName.padding(toLength: 24, withPad: " ", startingAt: 0)) [\(move.category.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0))]  \(status)")
        }
        lines.append("")
        lines.append("  SUMMARY: \(coveredMoveCount)/\(RhetoricalMoveType.allCases.count) moves covered, \(uncoveredMoves.count) with ZERO gists")
        if !uncoveredMoves.isEmpty {
            lines.append("  UNCOVERED: \(uncoveredMoves.map(\.displayName).joined(separator: ", "))")
        }
        if !sparseMoves.isEmpty {
            lines.append("  FRAGILE (1 gist — once used, blocks all later positions): \(sparseMoves.map(\.0.displayName).joined(separator: ", "))")
        }
        lines.append("")

        // ─────────────────────────────────────────
        // SECTION 2: Matrix Demand — What does the corpus want?
        // ─────────────────────────────────────────
        lines.append("═══ SECTION 2: MATRIX DEMAND vs GIST SUPPLY ═══")

        if let matrix = coordinator.markovMatrix {
            // Starters
            let allStarters = MarkovTransitionService.sequenceStartProbabilities(in: matrix)
            lines.append("--- Sequence Starters (what the matrix offers) ---")
            for starter in allStarters {
                let eligible = index.moveToGists[starter.move]?.count ?? 0
                let status = eligible > 0 ? "\(eligible) gists available" : "NO GISTS (blocked)"
                lines.append("  \(starter.move.displayName.padding(toLength: 24, withPad: " ", startingAt: 0)) \(pct(starter.probability))  \(status)")
            }
            lines.append("")

            // Walk-forward simulation: replay the chain builder's actual logic per starter
            let viableStarters = allStarters.filter { index.hasEligibleGists(for: $0.move, excluding: []) }
            lines.append("--- Walk-Forward Simulation (demand vs supply WITH gist consumption) ---")
            lines.append("(Shows what the chain builder actually sees as gists get consumed)")
            lines.append("")

            for starter in viableStarters.prefix(4) {
                lines.append("  STARTER: \(starter.move.displayName) (\(pct(starter.probability)))")

                var simulatedUsed: Set<UUID> = []
                var simulatedHistory: [RhetoricalMoveType] = []

                guard let starterGistId = index.mostConstrainedGist(
                    for: starter.move, excluding: simulatedUsed, gists: gists
                ) else {
                    lines.append("    P0: No gist available for starter")
                    lines.append("")
                    continue
                }

                simulatedUsed.insert(starterGistId)
                simulatedHistory.append(starter.move)
                let starterGist = gists.first { $0.id == starterGistId }
                let remainingForStarter = index.eligibleGists(for: starter.move, excluding: simulatedUsed).count
                lines.append("    P0 \(starter.move.displayName): assigned \(starterGist.map { "C\($0.chunkIndex + 1)" } ?? "?"), \(remainingForStarter) remaining for this move")

                var hitDeadEnd = false
                for posIdx in 1...3 {
                    let lookup = ChainBuildingService.getFilteredCandidates(
                        history: simulatedHistory,
                        positionIndex: posIdx,
                        matrix: matrix,
                        expansionIndex: index,
                        parameters: run.parameters,
                        usedGistIds: simulatedUsed
                    )

                    if lookup.raw.isEmpty {
                        lines.append("    P\(posIdx): Matrix returned no transitions (dead end)")
                        hitDeadEnd = true
                        break
                    }

                    lines.append("    P\(posIdx) candidates (\(lookup.raw.count) raw, \(lookup.filtered.count) pass filters):")

                    for candidate in lookup.raw {
                        let totalCount = index.moveToGists[candidate.move]?.count ?? 0
                        let postConsumption = index.eligibleGists(for: candidate.move, excluding: simulatedUsed).count
                        let consumed = totalCount - postConsumption

                        let rejection = lookup.alternatives.first { $0.moveType == candidate.move }?.rejectionReason
                        let passes = lookup.filtered.contains { $0.move == candidate.move }

                        var line = "      \(candidate.move.displayName.padding(toLength: 22, withPad: " ", startingAt: 0))"
                        line += " \(pct(candidate.probability))"
                        line += "  \(candidate.count) obs"
                        line += "  \(postConsumption)/\(totalCount) gists"
                        if consumed > 0 { line += " (\(consumed) consumed)" }

                        if let reason = rejection {
                            line += "  FILTERED: \(reason)"
                        } else if passes {
                            line += "  PASSES"
                        }

                        lines.append(line)
                    }

                    if lookup.filtered.isEmpty {
                        lines.append("    P\(posIdx) RESULT: Dead end (all \(lookup.raw.count) candidates filtered)")
                        hitDeadEnd = true
                        break
                    }

                    // Pick best passing candidate (highest probability, matching chain builder behavior)
                    let best = lookup.filtered.max { $0.probability < $1.probability }!

                    if let gistId = index.mostConstrainedGist(for: best.move, excluding: simulatedUsed, gists: gists) {
                        simulatedUsed.insert(gistId)
                        let gist = gists.first { $0.id == gistId }
                        let remaining = index.eligibleGists(for: best.move, excluding: simulatedUsed).count
                        lines.append("    P\(posIdx) PICKED: \(best.move.displayName) (assigned \(gist.map { "C\($0.chunkIndex + 1)" } ?? "?"), \(remaining) remaining)")
                    } else {
                        lines.append("    P\(posIdx) PICKED: \(best.move.displayName) (no gist available — gap)")
                    }
                    simulatedHistory.append(best.move)
                }

                lines.append("    Consumed after \(simulatedHistory.count) positions: \(simulatedUsed.count)/\(gists.count)")
                lines.append("")
            }
        }

        // ─────────────────────────────────────────
        // SECTION 3: Dead End Traces — Why each path died
        // ─────────────────────────────────────────
        lines.append("═══ SECTION 3: DEAD END TRACES ═══")
        lines.append("Total dead ends: \(run.deadEnds.count)")
        lines.append("")

        // Group dead ends by path length to show the pattern
        let byLength = Dictionary(grouping: run.deadEnds, by: { $0.positionIndex })
        let sortedLengths = byLength.keys.sorted()
        lines.append("--- Dead End Distribution by Position ---")
        for pos in sortedLengths {
            let des = byLength[pos]!
            lines.append("  Position \(pos): \(des.count) dead ends")
        }
        lines.append("")

        // Detailed trace for each dead end
        for (idx, de) in run.deadEnds.enumerated() {
            lines.append("--- Dead End #\(idx + 1) at position \(de.positionIndex) ---")
            lines.append("  Path: \(de.pathSoFar.joined(separator: " -> "))")
            lines.append("  Classification: \(de.deadEndType.rawValue)")
            lines.append("  Lookup: depth=\(de.lookupDepthUsed), key=\"\(de.lookupKey)\"")
            lines.append("")

            // Reconstruct gist consumption along the path
            let pathMoves = de.pathSoFar.compactMap { RhetoricalMoveType.parse($0) }
            var simulatedUsed: Set<UUID> = []
            var consumptionLog: [String] = []
            for (posIdx, move) in pathMoves.enumerated() {
                let eligible = index.eligibleGists(for: move, excluding: simulatedUsed)
                if let gistId = index.mostConstrainedGist(for: move, excluding: simulatedUsed, gists: gists) {
                    simulatedUsed.insert(gistId)
                    let remaining = index.eligibleGists(for: move, excluding: simulatedUsed).count
                    let gist = gists.first { $0.id == gistId }
                    let chunkLabel = gist.map { "C\($0.chunkIndex + 1)" } ?? "?"
                    consumptionLog.append("    P\(posIdx) \(move.displayName): assigned \(chunkLabel), \(remaining) remaining for this move")
                } else {
                    consumptionLog.append("    P\(posIdx) \(move.displayName): NO GIST AVAILABLE (had \(eligible.count) before, 0 after exclusions)")
                }
            }
            lines.append("  Gist consumption along this path:")
            lines.append(contentsOf: consumptionLog)
            lines.append("  Total gists consumed: \(simulatedUsed.count)/\(gists.count)")
            lines.append("")

            // What moves the matrix wanted at the dead end position
            if !de.rawCandidateMoveTypes.isEmpty {
                lines.append("  Matrix offered \(de.rawCandidateMoveTypes.count) candidates at position \(de.positionIndex):")
                for rawMove in de.rawCandidateMoveTypes {
                    let totalForMove = index.moveToGists[rawMove]?.count ?? 0
                    let afterExclusions = index.eligibleGists(for: rawMove, excluding: simulatedUsed).count
                    let reason: String
                    if totalForMove == 0 {
                        reason = "ZERO gists mapped (no frame covers this move)"
                    } else if afterExclusions == 0 {
                        reason = "had \(totalForMove) gists total, but all \(totalForMove) already consumed by earlier positions"
                    } else {
                        reason = "\(afterExclusions) available (should have passed — may have been killed by threshold/category)"
                    }
                    lines.append("    \(rawMove.displayName.padding(toLength: 24, withPad: " ", startingAt: 0)) \(reason)")
                }
            }

            // Candidate details (only present for exhaustive, skipped in tree walk for memory)
            if !de.candidateDetails.isEmpty {
                lines.append("  Per-candidate rejection reasons:")
                for cd in de.candidateDetails {
                    lines.append("    \(cd.moveName.padding(toLength: 24, withPad: " ", startingAt: 0)) prob=\(pct(cd.probability))  obs=\(cd.observationCount)  \(cd.rejectionReason)")
                }
            }

            lines.append("  WHY: \(de.whatWasMissing)")
            lines.append("  FIX: \(de.suggestedUserAction)")
            lines.append("")
        }

        // ─────────────────────────────────────────
        // SECTION 4: Root Cause Summary
        // ─────────────────────────────────────────
        lines.append("═══ SECTION 4: ROOT CAUSE SUMMARY ═══")

        // Count how many dead ends were killed by each root cause
        var killedByNoMapping = 0    // move has 0 gists total
        var killedByExhaustion = 0   // move had gists but all used up
        var killedByThreshold = 0
        var killedByOther = 0

        for de in run.deadEnds {
            var thisDeadEndCause = "other"
            for rawMove in de.rawCandidateMoveTypes {
                let totalForMove = index.moveToGists[rawMove]?.count ?? 0
                if totalForMove == 0 {
                    thisDeadEndCause = "noMapping"
                    break
                }
            }
            // If all raw candidates had gists in theory, check if they were just used up
            if thisDeadEndCause == "other" && de.deadEndType == .missingContent {
                thisDeadEndCause = "exhaustion"
            }

            switch thisDeadEndCause {
            case "noMapping": killedByNoMapping += 1
            case "exhaustion": killedByExhaustion += 1
            default:
                if de.deadEndType == .transitionImpossible { killedByThreshold += 1 }
                else { killedByOther += 1 }
            }
        }

        lines.append("")
        if killedByNoMapping > 0 {
            lines.append("  NO FRAME MAPS TO MOVE: \(killedByNoMapping)/\(run.deadEnds.count) dead ends")
            lines.append("    Your gist frames don't cover certain moves the matrix demands.")
            lines.append("    The expansion table is fixed — each frame maps to specific moves.")
            lines.append("    Moves with 0 gists can NEVER be placed, killing every path through them.")
            lines.append("")
        }
        if killedByExhaustion > 0 {
            lines.append("  ALL GISTS CONSUMED: \(killedByExhaustion)/\(run.deadEnds.count) dead ends")
            lines.append("    The move had gists, but they were all used by earlier positions.")
            lines.append("    Each gist can only be used once. Fragile moves (1 gist) exhaust instantly.")
            lines.append("")
        }
        if killedByThreshold > 0 {
            lines.append("  THRESHOLD/TRANSITION: \(killedByThreshold)/\(run.deadEnds.count) dead ends")
            lines.append("    Matrix transitions existed but were below the \(pct(run.parameters.transitionThreshold)) threshold.")
            lines.append("")
        }
        if killedByOther > 0 {
            lines.append("  OTHER: \(killedByOther)/\(run.deadEnds.count) dead ends")
            lines.append("")
        }

        // Actionable recommendations
        lines.append("--- Recommendations ---")
        if !uncoveredMoves.isEmpty {
            // Figure out which frames would cover the uncovered moves
            var frameSuggestions: [GistFrame: [RhetoricalMoveType]] = [:]
            for move in uncoveredMoves {
                for frame in GistFrame.allCases {
                    if FrameExpansionIndex.expansionMoves(for: frame).contains(move) {
                        frameSuggestions[frame, default: []].append(move)
                    }
                }
            }
            lines.append("  1. ADD GISTS WITH THESE FRAMES to cover \(uncoveredMoves.count) missing moves:")
            for (frame, moves) in frameSuggestions.sorted(by: { $0.value.count > $1.value.count }) {
                let existing = frameCounts[frame]?.count ?? 0
                let moveNames = moves.map(\.displayName).joined(separator: ", ")
                lines.append("     \(frame.displayName) (currently \(existing) gists) -> would unlock: \(moveNames)")
            }
            lines.append("")
        }
        if !sparseMoves.isEmpty {
            lines.append("  2. STRENGTHEN FRAGILE MOVES (only 1 gist — once used, blocks all paths):")
            for (move, _) in sparseMoves {
                let coveringFrames = GistFrame.allCases.filter { FrameExpansionIndex.expansionMoves(for: $0).contains(move) }
                let frameNames = coveringFrames.map(\.displayName).joined(separator: " or ")
                lines.append("     \(move.displayName) -> add gists with frame: \(frameNames)")
            }
            lines.append("")
        }
        lines.append("  3. PARAMETER TWEAKS:")
        lines.append("     Lower transitionThreshold (currently \(pct(run.parameters.transitionThreshold))) to allow more matrix transitions")
        lines.append("     Lower minObservationCount (currently \(run.parameters.minObservationCount)) if sparse data is filtering")
        lines.append("     Lower coverageTarget (currently \(pct(run.parameters.coverageTarget))) to allow shorter chains")
        lines.append("")

        // ─────────────────────────────────────────
        // SECTION 5: Cascade Analysis — Fix Shopping List
        // ─────────────────────────────────────────
        if !run.cascadeResults.isEmpty {
            lines.append("═══ SECTION 5: CASCADE ANALYSIS ═══")
            lines.append("For each dead end group, what happens if you add a gist for that move?")
            lines.append("")

            let sorted = run.cascadeResults.sorted {
                ($0.completionCount, $0.avgRunwayAfterFix) > ($1.completionCount, $1.avgRunwayAfterFix)
            }

            for cascade in sorted {
                lines.append("  \(cascade.moveType.displayName) [\(cascade.moveType.category.rawValue)] — \(cascade.deadEndCount) dead ends")
                lines.append("    Avg runway after fix: \(String(format: "%.1f", cascade.avgRunwayAfterFix)) additional positions")
                lines.append("    Completions: \(cascade.completionCount)/\(cascade.deadEndCount)")

                if let nextBlocker = cascade.nextBlockageMove {
                    lines.append("    Next blockage: \(nextBlocker.displayName) (\(cascade.nextBlockageCount)/\(cascade.deadEndCount) paths)")

                    if cascade.level2CompletionCount > 0 {
                        lines.append("    FIX BOTH \(cascade.moveType.displayName) + \(nextBlocker.displayName) -> \(cascade.level2CompletionCount)/\(cascade.deadEndCount) completions")
                    }
                } else if cascade.completionCount == cascade.deadEndCount && cascade.deadEndCount > 0 {
                    lines.append("    All paths complete after this single fix!")
                }
                lines.append("")
            }

            // Shopping list summary
            var shoppingList: [(moves: String, completions: Int, total: Int)] = []
            for cascade in sorted {
                if cascade.completionCount > 0 {
                    shoppingList.append((cascade.moveType.displayName, cascade.completionCount, cascade.deadEndCount))
                }
                if cascade.level2CompletionCount > cascade.completionCount, let nb = cascade.nextBlockageMove {
                    shoppingList.append(("\(cascade.moveType.displayName) + \(nb.displayName)", cascade.level2CompletionCount, cascade.deadEndCount))
                }
            }

            if !shoppingList.isEmpty {
                lines.append("--- Fix Shopping List (prioritized) ---")
                for (idx, item) in shoppingList.sorted(by: { $0.completions > $1.completions }).prefix(10).enumerated() {
                    lines.append("  \(idx + 1). Fix \(item.moves) -> \(item.completions)/\(item.total) paths complete")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}
