//
//  MarkovExplorerView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/17/26.
//
//  Debug View 2: Markov Explorer
//  Visualizes transition probability landscape from the creator's corpus.
//  Channel selector, parent/move toggle, transition cards, move drill-down,
//  global n-gram patterns, and interactive sequence builder.
//

import SwiftUI

struct MarkovExplorerView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @State private var showMoveDetail: RhetoricalMoveType?
    @State private var showGlobalPatterns = false
    @State private var showSequenceBuilder = false
    @State private var showProofSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Controls
                controlsSection

                // Matrix stats
                if let matrix = coordinator.markovMatrix {
                    matrixStatsSection(matrix)
                }

                // Interactive Sequence Builder
                if coordinator.markovMatrix != nil {
                    sequenceBuilderSection
                }

                // Transition overview
                if let matrix = coordinator.markovMatrix {
                    transitionOverviewSection(matrix)
                }

                // Global patterns
                if let matrix = coordinator.markovMatrix {
                    globalPatternsSection(matrix)
                }
            }
            .padding()
        }
        .sheet(item: $showMoveDetail) { move in
            NavigationView {
                moveDetailSheet(move)
                    .navigationTitle(coordinator.useParentLevel ? move.category.rawValue : move.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showMoveDetail = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showProofSheet) {
            NavigationView {
                patternProofSheet
                    .navigationTitle("Source Videos")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showProofSheet = false }
                        }
                    }
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Channel selector
            if !coordinator.availableChannels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channels")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            // All channels button
                            Button {
                                coordinator.selectedChannelIds.removeAll()
                            } label: {
                                Text("All")
                                    .font(.caption2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(coordinator.selectedChannelIds.isEmpty ? Color.accentColor : Color.secondary.opacity(0.15))
                                    .foregroundColor(coordinator.selectedChannelIds.isEmpty ? .white : .primary)
                                    .cornerRadius(6)
                            }

                            ForEach(coordinator.availableChannels, id: \.channelId) { channel in
                                let isSelected = coordinator.selectedChannelIds.contains(channel.channelId)
                                Button {
                                    if isSelected {
                                        coordinator.selectedChannelIds.remove(channel.channelId)
                                    } else {
                                        coordinator.selectedChannelIds.insert(channel.channelId)
                                    }
                                } label: {
                                    Text(channel.name)
                                        .font(.caption2)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
            }

            // Level toggle + build button
            HStack {
                Toggle(isOn: $coordinator.useParentLevel) {
                    Text(coordinator.useParentLevel ? "Parent (6 categories)" : "Full (25 moves)")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .onChange(of: coordinator.useParentLevel) { _ in
                    coordinator.refreshMatrix()
                }

                Spacer()

                Button {
                    Task { await coordinator.loadCorpusAndBuildMatrix() }
                } label: {
                    Label(
                        coordinator.markovMatrix == nil ? "Build Matrix" : "Rebuild",
                        systemImage: "chart.dots.scatter"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isLoading)
            }
        }
    }

    // MARK: - Matrix Stats

    private func matrixStatsSection(_ matrix: MarkovMatrix) -> some View {
        HStack(spacing: 20) {
            statBadge(value: "\(matrix.sourceSequenceCount)", label: "Videos")
            statBadge(value: "\(matrix.totalMoveCount)", label: "Total Moves")
            statBadge(value: "\(matrix.uniqueMoveCount)", label: "Unique Types")

            Spacer()

            CopyAllButton(
                items: [MarkovTransitionService.buildReport(from: matrix)],
                separator: "",
                label: "Copy Report"
            )
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Interactive Sequence Builder

    private var sequenceBuilderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sequence Builder")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if !coordinator.explorerPath.isEmpty {
                    Button("Clear") {
                        coordinator.clearExplorerSequence()
                    }
                    .font(.caption)
                }
            }

            // History depth control
            HStack {
                Stepper("History Depth: \(coordinator.session.parameters.historyDepth)",
                        value: $coordinator.session.parameters.historyDepth,
                        in: 1...8)
                    .font(.caption)
                    .onChange(of: coordinator.session.parameters.historyDepth) { _ in
                        coordinator.persistSession()
                    }
            }

            if coordinator.explorerPath.isEmpty {
                // Show sequence starters
                Text("Tap a move to start building a sequence:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let matrix = coordinator.markovMatrix {
                    let starters = matrix.sequenceStarters(topK: 8)
                    let totalStarts = starters.reduce(0) { $0 + $1.count }

                    FlowLayout(spacing: 6) {
                        ForEach(starters, id: \.move) { starter in
                            let pct = totalStarts > 0 ? Double(starter.count) / Double(totalStarts) * 100 : 0
                            Button {
                                coordinator.startExplorerSequence(with: starter.move)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(coordinator.useParentLevel ? starter.move.category.rawValue : starter.move.displayName)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                    Text("\(String(format: "%.0f", pct))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            } else {
                // Show current path
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(coordinator.explorerPath.enumerated()), id: \.offset) { index, move in
                            Text(coordinator.useParentLevel ? move.category.rawValue : move.displayName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(5)

                            if index < coordinator.explorerPath.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Next move options (pure N-step corpus lookup)
                let result = coordinator.explorerNextMoves(topK: 8)

                // Lookup info + Show Proof button
                HStack(spacing: 6) {
                    Text("\(result.historyDepthUsed)-step lookup")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)

                    if !result.lookupKey.isEmpty {
                        Text(result.lookupKey)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if coordinator.explorerPath.count >= 2 {
                        Button {
                            showProofSheet = true
                        } label: {
                            Label("Source Videos", systemImage: "film.stack")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if result.isDeadEnd {
                    // Dead end — this sequence doesn't exist in the corpus
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dead End")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                                Text("This sequence doesn't exist in the corpus.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.06))
                    .cornerRadius(8)
                } else {
                    // Show corpus results
                    Text("Next moves:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(result.moves, id: \.move) { next in
                            Button {
                                coordinator.extendExplorerSequence(with: next.move)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(coordinator.useParentLevel ? next.move.category.rawValue : next.move.displayName)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                    Text("\(String(format: "%.0f", next.probability * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(probabilityBackground(next.probability))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Transition Overview

    private func transitionOverviewSection(_ matrix: MarkovMatrix) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Move Transitions")
                .font(.subheadline)
                .fontWeight(.semibold)

            let sortedMoves = matrix.transitions.sorted { $0.value.totalOccurrences > $1.value.totalOccurrences }

            LazyVStack(spacing: 6) {
                ForEach(sortedMoves, id: \.key) { move, data in
                    moveTransitionCard(move: move, data: data, matrix: matrix)
                }
            }
        }
    }

    private func moveTransitionCard(move: RhetoricalMoveType, data: MoveTransitions, matrix: MarkovMatrix) -> some View {
        Button {
            showMoveDetail = move
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Header row
                HStack {
                    Text(coordinator.useParentLevel ? move.category.rawValue : move.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(data.totalOccurrences)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if data.startsSequenceCount > 0 {
                        Text("S:\(data.startsSequenceCount)")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if data.endsSequenceCount > 0 {
                        Text("E:\(data.endsSequenceCount)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Top 3 successors
                let nextMoves = matrix.topNextMoves(after: move, topK: 3)
                if !nextMoves.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(nextMoves, id: \.move) { next in
                            HStack(spacing: 2) {
                                Text("→")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(coordinator.useParentLevel ? next.move.category.rawValue : next.move.displayName)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                Text("\(String(format: "%.0f", next.probability * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(probabilityBackground(next.probability))
                            .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        }
    }

    // MARK: - Move Detail Sheet

    private func moveDetailSheet(_ move: RhetoricalMoveType) -> some View {
        guard let matrix = coordinator.markovMatrix,
              let data = matrix.transitions[move] else {
            return AnyView(Text("No data for this move"))
        }

        return AnyView(ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Overview
                HStack(spacing: 20) {
                    statBadge(value: "\(data.totalOccurrences)", label: "Total")
                    statBadge(value: "\(data.startsSequenceCount)", label: "Starts")
                    statBadge(value: "\(data.endsSequenceCount)", label: "Ends")
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)

                // After (successors)
                let nextMoves = matrix.topNextMoves(after: move, topK: 15)
                if !nextMoves.isEmpty {
                    sectionHeader("Followed By")
                    ForEach(nextMoves, id: \.move) { next in
                        transitionRow(
                            name: coordinator.useParentLevel ? next.move.category.rawValue : next.move.displayName,
                            probability: next.probability,
                            count: next.count
                        )
                    }
                }

                // Before (predecessors)
                let prevMoves = matrix.topPreviousMoves(before: move, topK: 15)
                if !prevMoves.isEmpty {
                    sectionHeader("Preceded By")
                    ForEach(prevMoves, id: \.move) { prev in
                        transitionRow(
                            name: coordinator.useParentLevel ? prev.move.category.rawValue : prev.move.displayName,
                            probability: prev.probability,
                            count: prev.count
                        )
                    }
                }

                // Position distribution
                if !data.positionDistribution.isEmpty {
                    sectionHeader("Position Distribution")
                    positionChart(data.positionDistribution)
                }

                // 2-step histories
                let topTwoStep = data.twoStepHistory.sorted { $0.value > $1.value }.prefix(10)
                if !topTwoStep.isEmpty {
                    sectionHeader("2-Step History (what leads here)")
                    ForEach(Array(topTwoStep), id: \.key) { history, count in
                        HStack {
                            Text(history)
                                .font(.caption)
                            Spacer()
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 3-step histories
                let topThreeStep = data.topThreeStepHistories.prefix(10)
                if !topThreeStep.isEmpty {
                    sectionHeader("3-Step History")
                    ForEach(topThreeStep, id: \.history) { item in
                        HStack {
                            Text(item.history)
                                .font(.caption)
                            Spacer()
                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Full 5-gram contexts
                let topContexts = data.topFullContexts.prefix(10)
                if !topContexts.isEmpty {
                    sectionHeader("Full 5-gram Contexts")
                    ForEach(topContexts, id: \.context) { item in
                        HStack {
                            Text(item.context)
                                .font(.caption2)
                            Spacer()
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Common trigrams
                let topTrigrams = data.commonTrigrams.prefix(10)
                if !topTrigrams.isEmpty {
                    sectionHeader("Common Trigrams")
                    ForEach(topTrigrams) { trigram in
                        HStack {
                            Text(trigram.pattern)
                                .font(.caption)
                            Spacer()
                            Text("\(trigram.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        })
    }

    // MARK: - Global Patterns

    private func globalPatternsSection(_ matrix: MarkovMatrix) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Global Patterns")
                .font(.subheadline)
                .fontWeight(.semibold)

            // Top 3-grams
            let top3 = matrix.globalPatterns.topThreeGrams.prefix(8)
            if !top3.isEmpty {
                Text("Top 3-grams")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(top3, id: \.pattern) { gram in
                    HStack {
                        Text(gram.pattern)
                            .font(.caption2)
                        Spacer()
                        Text("\(gram.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Top 4-grams
            let top4 = matrix.globalPatterns.topFourGrams.prefix(5)
            if !top4.isEmpty {
                Text("Top 4-grams")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                ForEach(top4, id: \.pattern) { gram in
                    HStack {
                        Text(gram.pattern)
                            .font(.caption2)
                        Spacer()
                        Text("\(gram.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Top 5-grams
            let top5 = matrix.globalPatterns.topFiveGrams.prefix(5)
            if !top5.isEmpty {
                Text("Top 5-grams")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                ForEach(top5, id: \.pattern) { gram in
                    HStack {
                        Text(gram.pattern)
                            .font(.caption2)
                        Spacer()
                        Text("\(gram.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Pattern Proof Sheet

    private var patternProofSheet: some View {
        let pattern = coordinator.explorerPath
        let matches = coordinator.findVideosMatchingPattern(pattern)
        let patternLabel = pattern.map { coordinator.useParentLevel ? $0.category.rawValue : $0.displayName }.joined(separator: " → ")

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Pattern being searched
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pattern (\(pattern.count)-step)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(patternLabel)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(8)

                // Results count
                Text("\(matches.count) video\(matches.count == 1 ? "" : "s") found")
                    .font(.caption)
                    .fontWeight(.semibold)

                if matches.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No videos in the corpus contain this exact sequence.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Text("This pattern may be a data collection artifact.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { match in
                            proofMatchRow(match: match, patternLength: pattern.count)
                        }
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func proofMatchRow(match: MarkovScriptWriterCoordinator.PatternMatch, patternLength: Int) -> some View {
        let matchEnd = match.matchStartIndex + patternLength
        let content = VStack(alignment: .leading, spacing: 6) {
            // Video title
            HStack {
                Text(match.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                Spacer()
                if coordinator.corpusVideos[match.videoId] != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Match position
            Text("Match at position \(match.matchStartIndex + 1) of \(match.fullSequence.count)")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Full sequence with matched portion highlighted
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(match.fullSequence.enumerated()), id: \.offset) { idx, move in
                        let isInMatch = idx >= match.matchStartIndex && idx < matchEnd
                        Text(coordinator.useParentLevel ? move.category.rawValue : move.displayName)
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(isInMatch ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.08))
                            .foregroundColor(isInMatch ? .primary : .secondary)
                            .fontWeight(isInMatch ? .bold : .regular)
                            .cornerRadius(3)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)

        if let video = coordinator.corpusVideos[match.videoId] {
            NavigationLink(destination: VideoRhetoricalSequenceView(video: video)) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.accentColor)
            .padding(.top, 4)
    }

    private func transitionRow(name: String, probability: Double, count: Int) -> some View {
        HStack {
            // Probability bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 20)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(probabilityColor(probability))
                        .frame(width: geo.size.width * probability, height: 20)
                        .cornerRadius(4)
                }
            }
            .frame(height: 20)
            .frame(maxWidth: 120)

            Text(name)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(String(format: "%.1f", probability * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .trailing)

            Text("(\(count))")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func positionChart(_ distribution: [Int: Int]) -> some View {
        let maxCount = distribution.values.max() ?? 1

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(0...10, id: \.self) { pos in
                let count = distribution[pos, default: 0]
                let height = maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) * 60 : 0

                VStack(spacing: 2) {
                    Text("\(count)")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Rectangle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 20, height: max(height, 2))
                        .cornerRadius(2)

                    Text("\(pos * 10)%")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func probabilityBackground(_ prob: Double) -> Color {
        if prob >= 0.3 { return Color.green.opacity(0.15) }
        if prob >= 0.15 { return Color.yellow.opacity(0.15) }
        return Color.secondary.opacity(0.1)
    }

    private func probabilityColor(_ prob: Double) -> Color {
        if prob >= 0.3 { return .green.opacity(0.6) }
        if prob >= 0.15 { return .orange.opacity(0.6) }
        return .secondary.opacity(0.4)
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
    }
}

// MARK: - RhetoricalMoveType Identifiable conformance for sheet

extension RhetoricalMoveType: @retroactive Identifiable {
    public var id: String { rawValue }
}
