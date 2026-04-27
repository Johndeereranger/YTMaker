//
//  CreatorRhetoricalStyleView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/28/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Analyzes a creator's rhetorical patterns across all their videos
/// Shows transition probabilities: what comes before/after each move type
struct CreatorRhetoricalStyleView: View {
    let channelId: String
    let channelName: String

    @State private var videos: [YouTubeVideo] = []
    @State private var sequences: [String: RhetoricalSequence] = [:]
    @State private var isLoading = true
    @State private var isExtracting = false
    @State private var extractionProgress: (current: Int, total: Int) = (0, 0)
    @State private var errorMessage: String?

    // Analysis results
    @State private var transitionMatrix: [RhetoricalMoveType: MoveTransitions] = [:]
    @State private var globalPatterns = GlobalPatternAnalysis()
    @State private var selectedMove: RhetoricalMoveType?
    @State private var showParentLevel = false

    private let firebaseService = YouTubeFirebaseService.shared
    private let rhetoricalService = RhetoricalMoveService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status section
                statusSection

                if isLoading {
                    ProgressView("Loading videos...")
                        .padding()
                } else if sequences.isEmpty {
                    noSequencesView
                } else {
                    // Analysis controls
                    controlsSection

                    Divider()

                    // Transition analysis
                    if let selected = selectedMove {
                        moveDetailView(for: selected)
                    } else {
                        transitionOverviewGrid

                        Divider()

                        // Global patterns section
                        globalPatternsSection
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Rhetorical Style")
        .onAppear {
            loadVideosAndSequences()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(channelName)
                    .font(.headline)
                Spacer()

                // 3 Copy buttons
                HStack(spacing: 8) {
                    Button { copyAnalysis(mode: .all) } label: {
                        Label("All", systemImage: "doc.on.doc.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button { copyAnalysis(mode: .parent) } label: {
                        Label("Parent", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)

                    Button { copyAnalysis(mode: .full) } label: {
                        Label("Full", systemImage: "list.bullet.rectangle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
            }

            HStack(spacing: 20) {
                VStack {
                    Text("\(videos.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(sequences.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Analyzed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(totalMoves)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Total Moves")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if videosNeedingExtraction.count > 0 {
                    Button(action: extractMissing) {
                        if isExtracting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Analyze \(videosNeedingExtraction.count)", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExtracting)
                }
            }

            if isExtracting {
                ProgressView(value: Double(extractionProgress.current), total: Double(extractionProgress.total))
                Text("Extracting \(extractionProgress.current)/\(extractionProgress.total)...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - No Sequences View

    private var noSequencesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Rhetorical Sequences Found")
                .font(.headline)

            Text("Videos need rhetorical analysis before we can identify style patterns.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if !videosNeedingExtraction.isEmpty {
                Button(action: extractMissing) {
                    Label("Analyze \(videosNeedingExtraction.count) Videos", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $showParentLevel) {
                VStack(alignment: .leading) {
                    Text("Show Parent Categories")
                    Text("Group by HOOK/SETUP/TENSION/etc. instead of 25 specific moves")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: showParentLevel) { _ in
                buildTransitionMatrix()
            }

            if selectedMove != nil {
                Button(action: { selectedMove = nil }) {
                    Label("Back to Overview", systemImage: "arrow.left")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Transition Overview Grid

    private var transitionOverviewGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transition Patterns")
                .font(.headline)

            Text("Tap a move to see what comes before/after it")
                .font(.caption)
                .foregroundColor(.secondary)

            if showParentLevel {
                // Simple grid for parent level
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(sortedMoveTypes, id: \.self) { moveType in
                        if let transitions = transitionMatrix[moveType], transitions.totalOccurrences > 0 {
                            MoveTransitionCard(
                                moveType: moveType,
                                transitions: transitions,
                                showParentLevel: showParentLevel
                            )
                            .onTapGesture {
                                selectedMove = moveType
                            }
                        }
                    }
                }
            } else {
                // Organized by parent category
                ForEach(RhetoricalCategory.allCases, id: \.self) { category in
                    categorySection(for: category)
                }
            }
        }
    }

    private func categorySection(for category: RhetoricalCategory) -> some View {
        let movesInCategory = movesForCategory(category)
        let hasData = movesInCategory.contains { transitionMatrix[$0]?.totalOccurrences ?? 0 > 0 }

        return Group {
            if hasData {
                VStack(alignment: .leading, spacing: 8) {
                    // Category header
                    HStack {
                        Circle()
                            .fill(categoryColor(category))
                            .frame(width: 12, height: 12)
                        Text(category.rawValue.uppercased())
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(categoryColor(category))

                        // Category total
                        let categoryTotal = movesInCategory.reduce(0) { $0 + (transitionMatrix[$1]?.totalOccurrences ?? 0) }
                        Text("(\(categoryTotal) total)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.top, 8)

                    // Moves grid for this category
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(movesInCategory, id: \.self) { moveType in
                            if let transitions = transitionMatrix[moveType], transitions.totalOccurrences > 0 {
                                MoveTransitionCard(
                                    moveType: moveType,
                                    transitions: transitions,
                                    showParentLevel: false
                                )
                                .onTapGesture {
                                    selectedMove = moveType
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(categoryColor(category).opacity(0.05))
                .cornerRadius(12)
            }
        }
    }

    private func movesForCategory(_ category: RhetoricalCategory) -> [RhetoricalMoveType] {
        RhetoricalMoveType.allCases.filter { $0.category == category }
    }

    private var sortedMoveTypes: [RhetoricalMoveType] {
        if showParentLevel {
            // Return one representative from each category
            return [.personalStake, .commonBelief, .complication, .hiddenTruth, .evidenceStack, .synthesis]
        } else {
            return transitionMatrix.keys.sorted { a, b in
                (transitionMatrix[a]?.totalOccurrences ?? 0) > (transitionMatrix[b]?.totalOccurrences ?? 0)
            }
        }
    }

    // MARK: - Global Patterns Section

    private var globalPatternsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Sequence Patterns")
                .font(.headline)

            Text("Most common rhetorical sequences across all videos")
                .font(.caption)
                .foregroundColor(.secondary)

            // 5-gram patterns (full context)
            if !globalPatterns.topFiveGrams.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "5.square.fill")
                            .foregroundColor(.indigo)
                        Text("Top 5-Move Sequences")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    ForEach(globalPatterns.topFiveGrams.prefix(8), id: \.pattern) { item in
                        HStack {
                            Text(item.pattern)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.count)x")
                                .fontWeight(.medium)
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding()
                .background(Color.indigo.opacity(0.1))
                .cornerRadius(12)
            }

            // 4-gram patterns
            if !globalPatterns.topFourGrams.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "4.square.fill")
                            .foregroundColor(.cyan)
                        Text("Top 4-Move Sequences")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    ForEach(globalPatterns.topFourGrams.prefix(8), id: \.pattern) { item in
                        HStack {
                            Text(item.pattern)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.count)x")
                                .fontWeight(.medium)
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding()
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(12)
            }

            // 3-gram patterns
            if !globalPatterns.topThreeGrams.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "3.square.fill")
                            .foregroundColor(.purple)
                        Text("Top 3-Move Sequences (Trigrams)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    ForEach(globalPatterns.topThreeGrams.prefix(10), id: \.pattern) { item in
                        HStack {
                            Text(item.pattern)
                                .font(.caption)
                                .fontDesign(.monospaced)
                            Spacer()
                            Text("\(item.count)x")
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Move Detail View

    @ViewBuilder
    private func moveDetailView(for moveType: RhetoricalMoveType) -> some View {
        if let transitions = transitionMatrix[moveType] {
            MoveDetailContent(
                moveType: moveType,
                transitions: transitions,
                showParentLevel: showParentLevel,
                categoryColor: categoryColor(moveType.category)
            )
        } else {
            Text("No data for this move")
        }
    }

    // MARK: - Helpers

    private var totalMoves: Int {
        sequences.values.reduce(0) { $0 + $1.moves.count }
    }

    private var videosNeedingExtraction: [YouTubeVideo] {
        videos.filter { $0.rhetoricalSequence == nil && $0.hasTranscript }
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

    // MARK: - Data Loading

    private func loadVideosAndSequences() {
        isLoading = true

        Task {
            do {
                let fetchedVideos = try await firebaseService.getVideos(forChannel: channelId)

                await MainActor.run {
                    videos = fetchedVideos

                    // Load sequences from videos that have them
                    for video in fetchedVideos {
                        if let seq = video.rhetoricalSequence {
                            sequences[video.videoId] = seq
                        }
                    }

                    buildTransitionMatrix()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func extractMissing() {
        let toExtract = videosNeedingExtraction
        guard !toExtract.isEmpty else { return }

        isExtracting = true
        extractionProgress = (0, toExtract.count)

        Task {
            // We need chunks for extraction - this requires boundary detection
            // For now, we'll show an error if videos don't have chunks
            // In a full implementation, you'd run boundary detection first

            await MainActor.run {
                errorMessage = "Videos need boundary detection before rhetorical extraction. Run from Template Extractor first."
                isExtracting = false
            }
        }
    }

    // MARK: - Transition Matrix Building (5-State Markov Chain)

    private func buildTransitionMatrix() {
        var matrix: [RhetoricalMoveType: MoveTransitions] = [:]
        var global = GlobalPatternAnalysis()

        for (_, sequence) in sequences {
            let moves = sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            let totalMoves = moves.count

            for (index, move) in moves.enumerated() {
                let key = showParentLevel ? representativeMove(for: move.moveType.category) : move.moveType

                if matrix[key] == nil {
                    matrix[key] = MoveTransitions()
                }

                matrix[key]?.totalOccurrences += 1

                // Track normalized position (0-10 scale)
                if totalMoves > 1 {
                    let normalizedPos = Int((Double(index) / Double(totalMoves - 1)) * 10)
                    matrix[key]?.positionDistribution[normalizedPos, default: 0] += 1
                }

                // Get context moves (prev3, prev2, prev1, next)
                let prev3: RhetoricalMoveType? = index >= 3 ? getMoveKey(moves[index - 3].moveType) : nil
                let prev2: RhetoricalMoveType? = index >= 2 ? getMoveKey(moves[index - 2].moveType) : nil
                let prev1: RhetoricalMoveType? = index >= 1 ? getMoveKey(moves[index - 1].moveType) : nil
                let next: RhetoricalMoveType? = index < moves.count - 1 ? getMoveKey(moves[index + 1].moveType) : nil

                // 1-step transitions (basic before/after)
                if index == 0 {
                    matrix[key]?.startsSequenceCount += 1
                } else if let p1 = prev1 {
                    matrix[key]?.beforeCounts[p1, default: 0] += 1
                }

                if index == moves.count - 1 {
                    matrix[key]?.endsSequenceCount += 1
                } else if let n = next {
                    matrix[key]?.afterCounts[n, default: 0] += 1
                }

                // 2-step history: track "prev2 → prev1" → leads to current
                if let p2 = prev2, let p1 = prev1 {
                    let twoStepKey = "\(getName(p2)) → \(getName(p1))"
                    matrix[key]?.twoStepHistory[twoStepKey, default: 0] += 1
                }

                // 3-step history: track "prev3 → prev2 → prev1" → leads to current
                if let p3 = prev3, let p2 = prev2, let p1 = prev1 {
                    let threeStepKey = "\(getName(p3)) → \(getName(p2)) → \(getName(p1))"
                    matrix[key]?.threeStepHistory[threeStepKey, default: 0] += 1
                }

                // Full 5-gram context: prev3 → prev2 → prev1 → current → next
                let p3Name = prev3 != nil ? getName(prev3!) : "⊥"
                let p2Name = prev2 != nil ? getName(prev2!) : "⊥"
                let p1Name = prev1 != nil ? getName(prev1!) : "⊥"
                let currName = getName(key)
                let nextName = next != nil ? getName(next!) : "⊥"

                let fullContext = "\(p3Name) → \(p2Name) → \(p1Name) → \(currName) → \(nextName)"
                matrix[key]?.fullContexts[fullContext, default: 0] += 1

                // Build global n-grams
                // 3-gram (trigram)
                if let p1 = prev1, let n = next {
                    let trigram = "\(getName(p1)) → \(currName) → \(getName(n))"
                    global.threeGrams[trigram, default: 0] += 1
                    matrix[key]?.trigramCounts[trigram, default: 0] += 1
                }

                // 4-gram
                if let p2 = prev2, let p1 = prev1, let n = next {
                    let fourGram = "\(getName(p2)) → \(getName(p1)) → \(currName) → \(getName(n))"
                    global.fourGrams[fourGram, default: 0] += 1
                }

                // 5-gram (only when we have full context)
                if let p3 = prev3, let p2 = prev2, let p1 = prev1, let n = next {
                    let fiveGram = "\(getName(p3)) → \(getName(p2)) → \(getName(p1)) → \(currName) → \(getName(n))"
                    global.fiveGrams[fiveGram, default: 0] += 1
                }
            }
        }

        // Convert trigram counts to sorted array for each move
        for key in matrix.keys {
            let sorted = matrix[key]!.trigramCounts.map { TrigramPattern(pattern: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
            matrix[key]?.commonTrigrams = sorted
        }

        transitionMatrix = matrix
        globalPatterns = global
    }

    /// Get move key based on parent level setting
    private func getMoveKey(_ move: RhetoricalMoveType) -> RhetoricalMoveType {
        showParentLevel ? representativeMove(for: move.category) : move
    }

    /// Get display name based on parent level setting
    private func getName(_ move: RhetoricalMoveType) -> String {
        showParentLevel ? move.category.rawValue : move.displayName
    }

    private func representativeMove(for category: RhetoricalCategory) -> RhetoricalMoveType {
        switch category {
        case .hook: return .personalStake
        case .setup: return .commonBelief
        case .tension: return .complication
        case .revelation: return .hiddenTruth
        case .evidence: return .evidenceStack
        case .closing: return .synthesis
        }
    }

    // MARK: - Copy Analysis

    enum CopyMode {
        case all      // Both parent and full
        case parent   // Parent categories only (6)
        case full     // Full 25 moves only
    }

    private func copyAnalysis(mode: CopyMode) {
        var report = ""

        switch mode {
        case .all:
            report = buildReport(forParentLevel: true, title: "PARENT LEVEL (6 Categories)")
            report += "\n\n"
            report += buildReport(forParentLevel: false, title: "FULL LEVEL (25 Moves)")
            report += buildVideoSequences()
        case .parent:
            report = buildReport(forParentLevel: true, title: "PARENT LEVEL (6 Categories)")
            report += buildVideoSequences()
        case .full:
            report = buildReport(forParentLevel: false, title: "FULL LEVEL (25 Moves)")
            report += buildVideoSequences()
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }

    private func buildReport(forParentLevel useParent: Bool, title: String) -> String {
        // Build matrix for requested level
        let (matrix, global) = buildMatrixForLevel(useParent: useParent)

        let sortedTypes: [RhetoricalMoveType] = {
            if useParent {
                return [.personalStake, .commonBelief, .complication, .hiddenTruth, .evidenceStack, .synthesis]
            } else {
                return matrix.keys.sorted { a, b in
                    (matrix[a]?.totalOccurrences ?? 0) > (matrix[b]?.totalOccurrences ?? 0)
                }
            }
        }()

        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        CREATOR RHETORICAL STYLE ANALYSIS - \(title)
        ═══════════════════════════════════════════════════════════════════════════════

        Creator: \(channelName)
        Videos Analyzed: \(sequences.count)
        Total Moves: \(totalMoves)

        ═══════════════════════════════════════════════════════════════════════════════
        TRANSITION PROBABILITIES
        ═══════════════════════════════════════════════════════════════════════════════

        """

        for moveType in sortedTypes {
            guard let transitions = matrix[moveType], transitions.totalOccurrences > 0 else { continue }

            let name = useParent ? moveType.category.rawValue : moveType.displayName

            report += """

        ───────────────────────────────────────────────────────────────────────────────
        \(name) (\(transitions.totalOccurrences) occurrences)
        ───────────────────────────────────────────────────────────────────────────────

        BEFORE (what leads to \(name)):
        """

            if transitions.startsSequenceCount > 0 {
                let pct = Int(Double(transitions.startsSequenceCount) / Double(transitions.totalOccurrences) * 100)
                report += "\n  [START] \(transitions.startsSequenceCount)x (\(pct)%)"
            }

            for (move, count) in transitions.beforeCounts.sorted(by: { $0.value > $1.value }) {
                let pct = Int(Double(count) / Double(transitions.totalOccurrences) * 100)
                let moveName = useParent ? move.category.rawValue : move.displayName
                report += "\n  \(moveName): \(count)x (\(pct)%)"
            }

            report += "\n\nAFTER (what follows \(name)):"

            if transitions.endsSequenceCount > 0 {
                let pct = Int(Double(transitions.endsSequenceCount) / Double(transitions.totalOccurrences) * 100)
                report += "\n  [END] \(transitions.endsSequenceCount)x (\(pct)%)"
            }

            for (move, count) in transitions.afterCounts.sorted(by: { $0.value > $1.value }) {
                let pct = Int(Double(count) / Double(transitions.totalOccurrences) * 100)
                let moveName = useParent ? move.category.rawValue : move.displayName
                report += "\n  \(moveName): \(count)x (\(pct)%)"
            }

            if !transitions.commonTrigrams.isEmpty {
                report += "\n\nCOMMON 3-MOVE PATTERNS:"
                for trigram in transitions.commonTrigrams.prefix(5) {
                    report += "\n  \(trigram.pattern): \(trigram.count)x"
                }
            }

            if !transitions.threeStepHistory.isEmpty {
                report += "\n\n3-STEP HISTORY (prev₃ → prev₂ → prev₁ → [THIS]):"
                for item in transitions.topThreeStepHistories.prefix(5) {
                    let pct = Int(Double(item.count) / Double(transitions.totalOccurrences) * 100)
                    report += "\n  \(item.history) → [THIS]: \(item.count)x (\(pct)%)"
                }
            }

            if !transitions.fullContexts.isEmpty {
                report += "\n\n5-STATE CONTEXTS (prev₃ → prev₂ → prev₁ → [THIS] → next):"
                for item in transitions.topFullContexts.prefix(5) {
                    report += "\n  \(item.context): \(item.count)x"
                }
            }

            report += "\n"
        }

        // Add global n-gram patterns
        report += """

        ═══════════════════════════════════════════════════════════════════════════════
        GLOBAL SEQUENCE PATTERNS
        ═══════════════════════════════════════════════════════════════════════════════

        TOP 5-MOVE SEQUENCES:
        """

        for item in global.topFiveGrams.prefix(10) {
            report += "\n  \(item.pattern): \(item.count)x"
        }

        report += "\n\nTOP 4-MOVE SEQUENCES:"
        for item in global.topFourGrams.prefix(10) {
            report += "\n  \(item.pattern): \(item.count)x"
        }

        report += "\n\nTOP 3-MOVE SEQUENCES (TRIGRAMS):"
        for item in global.topThreeGrams.prefix(10) {
            report += "\n  \(item.pattern): \(item.count)x"
        }

        return report
    }

    private func buildVideoSequences() -> String {
        var report = """


        ═══════════════════════════════════════════════════════════════════════════════
        ALL VIDEO SEQUENCES
        ═══════════════════════════════════════════════════════════════════════════════

        """

        for video in videos.sorted(by: { $0.title < $1.title }) {
            if let seq = sequences[video.videoId] {
                report += """

        \(video.title)
        Duration: \(video.durationFormatted) | Chunks: \(seq.moves.count)
        Parent: \(seq.parentSequenceString)
        Full: \(seq.moveSequenceString)

        """
            }
        }

        return report
    }

    /// Build matrix for a specific level (reusable for copy modes)
    private func buildMatrixForLevel(useParent: Bool) -> ([RhetoricalMoveType: MoveTransitions], GlobalPatternAnalysis) {
        var matrix: [RhetoricalMoveType: MoveTransitions] = [:]
        var global = GlobalPatternAnalysis()

        func getKey(_ move: RhetoricalMoveType) -> RhetoricalMoveType {
            useParent ? representativeMove(for: move.category) : move
        }

        func getName(_ move: RhetoricalMoveType) -> String {
            useParent ? move.category.rawValue : move.displayName
        }

        for (_, sequence) in sequences {
            let moves = sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            let total = moves.count

            for (index, move) in moves.enumerated() {
                let key = getKey(move.moveType)

                if matrix[key] == nil {
                    matrix[key] = MoveTransitions()
                }

                matrix[key]?.totalOccurrences += 1

                if total > 1 {
                    let normalizedPos = Int((Double(index) / Double(total - 1)) * 10)
                    matrix[key]?.positionDistribution[normalizedPos, default: 0] += 1
                }

                let prev3: RhetoricalMoveType? = index >= 3 ? getKey(moves[index - 3].moveType) : nil
                let prev2: RhetoricalMoveType? = index >= 2 ? getKey(moves[index - 2].moveType) : nil
                let prev1: RhetoricalMoveType? = index >= 1 ? getKey(moves[index - 1].moveType) : nil
                let next: RhetoricalMoveType? = index < moves.count - 1 ? getKey(moves[index + 1].moveType) : nil

                if index == 0 {
                    matrix[key]?.startsSequenceCount += 1
                } else if let p1 = prev1 {
                    matrix[key]?.beforeCounts[p1, default: 0] += 1
                }

                if index == moves.count - 1 {
                    matrix[key]?.endsSequenceCount += 1
                } else if let n = next {
                    matrix[key]?.afterCounts[n, default: 0] += 1
                }

                if let p2 = prev2, let p1 = prev1 {
                    let twoStepKey = "\(getName(p2)) → \(getName(p1))"
                    matrix[key]?.twoStepHistory[twoStepKey, default: 0] += 1
                }

                if let p3 = prev3, let p2 = prev2, let p1 = prev1 {
                    let threeStepKey = "\(getName(p3)) → \(getName(p2)) → \(getName(p1))"
                    matrix[key]?.threeStepHistory[threeStepKey, default: 0] += 1
                }

                let p3Name = prev3 != nil ? getName(prev3!) : "⊥"
                let p2Name = prev2 != nil ? getName(prev2!) : "⊥"
                let p1Name = prev1 != nil ? getName(prev1!) : "⊥"
                let currName = getName(key)
                let nextName = next != nil ? getName(next!) : "⊥"

                let fullContext = "\(p3Name) → \(p2Name) → \(p1Name) → \(currName) → \(nextName)"
                matrix[key]?.fullContexts[fullContext, default: 0] += 1

                if let p1 = prev1, let n = next {
                    let trigram = "\(getName(p1)) → \(currName) → \(getName(n))"
                    global.threeGrams[trigram, default: 0] += 1
                    matrix[key]?.trigramCounts[trigram, default: 0] += 1
                }

                if let p2 = prev2, let p1 = prev1, let n = next {
                    let fourGram = "\(getName(p2)) → \(getName(p1)) → \(currName) → \(getName(n))"
                    global.fourGrams[fourGram, default: 0] += 1
                }

                if let p3 = prev3, let p2 = prev2, let p1 = prev1, let n = next {
                    let fiveGram = "\(getName(p3)) → \(getName(p2)) → \(getName(p1)) → \(currName) → \(getName(n))"
                    global.fiveGrams[fiveGram, default: 0] += 1
                }
            }
        }

        for key in matrix.keys {
            let sorted = matrix[key]!.trigramCounts.map { TrigramPattern(pattern: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
            matrix[key]?.commonTrigrams = sorted
        }

        return (matrix, global)
    }
}

// MARK: - Supporting Types

/// Represents a 5-state Markov context: [prev3, prev2, prev1, current, next]
struct MarkovContext: Hashable, Codable {
    let prev3: RhetoricalMoveType?
    let prev2: RhetoricalMoveType?
    let prev1: RhetoricalMoveType?
    let current: RhetoricalMoveType
    let next: RhetoricalMoveType?

    var contextKey: String {
        let p3 = prev3?.displayName ?? "⊥"
        let p2 = prev2?.displayName ?? "⊥"
        let p1 = prev1?.displayName ?? "⊥"
        let n = next?.displayName ?? "⊥"
        return "\(p3) → \(p2) → \(p1) → \(current.displayName) → \(n)"
    }

    var shortKey: String {
        let p1 = prev1?.displayName ?? "START"
        let n = next?.displayName ?? "END"
        return "\(p1) → \(current.displayName) → \(n)"
    }

    /// Context string for the 3 previous states
    var historyKey: String {
        let p3 = prev3?.displayName ?? "⊥"
        let p2 = prev2?.displayName ?? "⊥"
        let p1 = prev1?.displayName ?? "⊥"
        return "\(p3) → \(p2) → \(p1)"
    }
}

struct MoveTransitions {
    var totalOccurrences: Int = 0

    // Simple before/after (1-step)
    var beforeCounts: [RhetoricalMoveType: Int] = [:]
    var afterCounts: [RhetoricalMoveType: Int] = [:]

    // 2-step history: P(current | prev2, prev1)
    var twoStepHistory: [String: Int] = [:]  // "prev2 → prev1" → count

    // 3-step history: P(current | prev3, prev2, prev1)
    var threeStepHistory: [String: Int] = [:]  // "prev3 → prev2 → prev1" → count

    // Full 5-gram contexts where this move is the center
    var fullContexts: [String: Int] = [:]  // "p3 → p2 → p1 → current → next" → count

    // Position tracking
    var startsSequenceCount: Int = 0
    var endsSequenceCount: Int = 0
    var positionDistribution: [Int: Int] = [:]  // normalized position (0-10) → count

    // Generalized N-step histories (depths 2-8). Key = step count, Value = "prev_n → ... → prev_1" → count
    var nStepHistories: [Int: [String: Int]] = [:]

    // Legacy trigram support
    var trigramCounts: [String: Int] = [:]
    var commonTrigrams: [TrigramPattern] = []

    // Computed: most common contexts
    var topFullContexts: [(context: String, count: Int)] {
        fullContexts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    }

    var topThreeStepHistories: [(history: String, count: Int)] {
        threeStepHistory.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    }
}

struct TrigramPattern: Identifiable {
    let pattern: String
    let count: Int
    var id: String { pattern }
}

/// Global pattern storage for analyzing common sequences across all moves
struct GlobalPatternAnalysis {
    var fiveGrams: [String: Int] = [:]  // Full 5-gram patterns
    var fourGrams: [String: Int] = [:]  // 4-gram patterns
    var threeGrams: [String: Int] = [:] // Trigram patterns

    var topFiveGrams: [(pattern: String, count: Int)] {
        fiveGrams.sorted { $0.value > $1.value }.prefix(20).map { ($0.key, $0.value) }
    }

    var topFourGrams: [(pattern: String, count: Int)] {
        fourGrams.sorted { $0.value > $1.value }.prefix(20).map { ($0.key, $0.value) }
    }

    var topThreeGrams: [(pattern: String, count: Int)] {
        threeGrams.sorted { $0.value > $1.value }.prefix(20).map { ($0.key, $0.value) }
    }
}

// MARK: - Move Transition Card

struct MoveTransitionCard: View {
    let moveType: RhetoricalMoveType
    let transitions: MoveTransitions
    let showParentLevel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle()
                    .fill(categoryColor)
                    .frame(width: 10, height: 10)
                Text(showParentLevel ? moveType.category.rawValue : moveType.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(transitions.totalOccurrences)x")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Top transition
            if let topBefore = transitions.beforeCounts.max(by: { $0.value < $1.value }) {
                let pct = Int(Double(topBefore.value) / Double(transitions.totalOccurrences) * 100)
                HStack {
                    Text("←")
                        .foregroundColor(.orange)
                    Text(showParentLevel ? topBefore.key.category.rawValue : topBefore.key.displayName)
                        .font(.caption2)
                    Text("\(pct)%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let topAfter = transitions.afterCounts.max(by: { $0.value < $1.value }) {
                let pct = Int(Double(topAfter.value) / Double(transitions.totalOccurrences) * 100)
                HStack {
                    Text("→")
                        .foregroundColor(.green)
                    Text(showParentLevel ? topAfter.key.category.rawValue : topAfter.key.displayName)
                        .font(.caption2)
                    Text("\(pct)%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }

    private var categoryColor: Color {
        switch moveType.category {
        case .hook: return .blue
        case .setup: return .green
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .gray
        case .closing: return .red
        }
    }
}

// MARK: - Transition Row

struct TransitionRow: View {
    let move: RhetoricalMoveType
    let count: Int
    let percentage: Double
    let showParentLevel: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(categoryColor)
                .frame(width: 8, height: 8)
            Text(showParentLevel ? move.category.rawValue : move.displayName)
                .font(.caption)
            Spacer()
            Text("\(count)x")
                .font(.caption)
                .fontWeight(.medium)
            Text("(\(Int(percentage))%)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Visual bar
            Rectangle()
                .fill(categoryColor.opacity(0.3))
                .frame(width: CGFloat(percentage), height: 4)
                .cornerRadius(2)
        }
        .padding(.vertical, 2)
    }

    private var categoryColor: Color {
        switch move.category {
        case .hook: return .blue
        case .setup: return .green
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .gray
        case .closing: return .red
        }
    }
}

// MARK: - Move Detail Content (Extracted for compiler performance)

struct MoveDetailContent: View {
    let moveType: RhetoricalMoveType
    let transitions: MoveTransitions
    let showParentLevel: Bool
    let categoryColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            beforeSection
            afterSection
            trigramSection
            threeStepHistorySection
            fiveStateContextSection
            positionSection
        }
    }

    private var headerSection: some View {
        HStack {
            Circle()
                .fill(categoryColor)
                .frame(width: 12, height: 12)
            Text(showParentLevel ? moveType.category.rawValue : moveType.displayName)
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            Text("\(transitions.totalOccurrences) occurrences")
                .foregroundColor(.secondary)
        }
    }

    private var beforeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.right")
                    .foregroundColor(.orange)
                Text("What comes BEFORE this move:")
                    .font(.headline)
            }

            ForEach(transitions.beforeCounts.sorted { $0.value > $1.value }, id: \.key) { move, count in
                let percentage = Double(count) / Double(transitions.totalOccurrences) * 100
                TransitionRow(
                    move: move,
                    count: count,
                    percentage: percentage,
                    showParentLevel: showParentLevel
                )
            }

            if transitions.startsSequenceCount > 0 {
                startsVideoRow
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private var startsVideoRow: some View {
        HStack {
            Text("🎬 Starts video")
                .font(.caption)
            Spacer()
            Text("\(transitions.startsSequenceCount)x")
                .fontWeight(.medium)
            Text("(\(Int(Double(transitions.startsSequenceCount) / Double(transitions.totalOccurrences) * 100))%)")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var afterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.left")
                    .foregroundColor(.green)
                Text("What comes AFTER this move:")
                    .font(.headline)
            }

            ForEach(transitions.afterCounts.sorted { $0.value > $1.value }, id: \.key) { move, count in
                let percentage = Double(count) / Double(transitions.totalOccurrences) * 100
                TransitionRow(
                    move: move,
                    count: count,
                    percentage: percentage,
                    showParentLevel: showParentLevel
                )
            }

            if transitions.endsSequenceCount > 0 {
                endsVideoRow
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private var endsVideoRow: some View {
        HStack {
            Text("🏁 Ends video")
                .font(.caption)
            Spacer()
            Text("\(transitions.endsSequenceCount)x")
                .fontWeight(.medium)
            Text("(\(Int(Double(transitions.endsSequenceCount) / Double(transitions.totalOccurrences) * 100))%)")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var trigramSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Common 3-Move Patterns:")
                .font(.headline)

            ForEach(transitions.commonTrigrams.prefix(5), id: \.pattern) { trigram in
                HStack {
                    Text(trigram.pattern)
                        .font(.caption)
                        .fontDesign(.monospaced)
                    Spacer()
                    Text("\(trigram.count)x")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var threeStepHistorySection: some View {
        if !transitions.threeStepHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.cyan)
                    Text("3-Step History (what leads here):")
                        .font(.headline)
                }

                Text("prev₃ → prev₂ → prev₁ → [THIS]")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)

                ForEach(transitions.topThreeStepHistories.prefix(5), id: \.history) { item in
                    threeStepRow(item)
                }
            }
            .padding()
            .background(Color.cyan.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private func threeStepRow(_ item: (history: String, count: Int)) -> some View {
        HStack {
            Text(item.history)
                .font(.caption)
                .fontDesign(.monospaced)
            Spacer()
            Text("\(item.count)x")
                .fontWeight(.medium)
            Text("(\(Int(Double(item.count) / Double(transitions.totalOccurrences) * 100))%)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var fiveStateContextSection: some View {
        if !transitions.fullContexts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "rectangle.split.3x3")
                        .foregroundColor(.indigo)
                    Text("Full 5-State Contexts:")
                        .font(.headline)
                }

                Text("prev₃ → prev₂ → prev₁ → [THIS] → next")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)

                ForEach(transitions.topFullContexts.prefix(5), id: \.context) { item in
                    fiveStateRow(item)
                }
            }
            .padding()
            .background(Color.indigo.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private func fiveStateRow(_ item: (context: String, count: Int)) -> some View {
        HStack {
            Text(item.context)
                .font(.caption2)
                .fontDesign(.monospaced)
                .lineLimit(1)
            Spacer()
            Text("\(item.count)x")
                .fontWeight(.medium)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var positionSection: some View {
        if !transitions.positionDistribution.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.yellow)
                    Text("Position in Video:")
                        .font(.headline)
                }

                PositionBarChart(distribution: transitions.positionDistribution)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Position Bar Chart

struct PositionBarChart: View {
    let distribution: [Int: Int]

    private var maxCount: Int {
        distribution.values.max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<11, id: \.self) { pos in
                positionBar(for: pos)
            }
        }
    }

    private func positionBar(for pos: Int) -> some View {
        let count = distribution[pos] ?? 0
        let height = maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) * 40 : 0

        return VStack(spacing: 2) {
            Rectangle()
                .fill(Color.yellow.opacity(0.7))
                .frame(width: 20, height: max(height, 2))
            Text(positionLabel(pos))
                .font(.system(size: 6))
                .foregroundColor(.secondary)
        }
    }

    private func positionLabel(_ pos: Int) -> String {
        if pos == 0 { return "Start" }
        if pos == 10 { return "End" }
        return "\(pos * 10)%"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CreatorRhetoricalStyleView(channelId: "test", channelName: "Test Creator")
    }
}
