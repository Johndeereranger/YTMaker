//
//  VideoRhetoricalSequenceView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/28/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// View for displaying and analyzing a single video's rhetorical sequence
struct VideoRhetoricalSequenceView: View {
    let video: YouTubeVideo

    @State private var showParentLevel = false
    @State private var expandedMoveIndex: Int? = nil
    @State private var chunks: [Chunk] = []
    @State private var isLoadingChunks = false
    @State private var sentenceSheetChunk: Chunk? = nil

    // Chunk search state
    @State private var chunkSearchText = ""
    @State private var chunkSearchResults: [(chunkIndex: Int, moveType: String, category: String)] = []
    @State private var isChunkSearchActive = false

    // Re-analysis state
    @State private var isReanalyzing = false
    @State private var reanalyzingMoveIndex: Int? = nil
    @State private var reanalysisError: String? = nil
    @State private var reanalysisProgress: String = ""
    @State private var updatedSequence: RhetoricalSequence? = nil

    // Toggle for showing enhanced gist details
    @State private var showEnhancedDetails = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Video header
                videoHeader

                if let sequence = video.rhetoricalSequence {
                    // Summary stats
                    summarySection(sequence)

                    Divider()

                    // Toggle for parent/full view
                    Toggle(isOn: $showParentLevel) {
                        VStack(alignment: .leading) {
                            Text("Show Parent Categories")
                            Text("Group by HOOK/SETUP/TENSION/etc.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)

                    Divider()

                    // Sequence visualization
                    sequenceVisualization(sequence)

                    Divider()

                    // Chunk search
                    chunkSearchSection

                    // Move list
                    movesList(sequence)

                } else {
                    noSequenceView
                }
            }
            .padding()
        }
        .navigationTitle("Rhetorical Sequence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if video.rhetoricalSequence != nil {
                    Menu {
                        Button {
                            copySequenceWithText()
                        } label: {
                            Label("Copy All (with Full Text)", systemImage: "doc.on.doc.fill")
                        }

                        Button {
                            copySequenceGistOnly()
                        } label: {
                            Label("Copy Gist Only", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button {
                            copyAllSentencesWithTags()
                        } label: {
                            Label("Copy All Sentences + Tags", systemImage: "list.bullet.rectangle.fill")
                        }
                        .disabled(chunks.isEmpty)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
        .task {
            await loadChunks()
        }
        .sheet(item: $sentenceSheetChunk) { chunk in
            SentenceBreakdownSheet(chunk: chunk)
        }
    }

    // MARK: - Load Chunks

    private func loadChunks() async {
        guard chunks.isEmpty else { return }
        isLoadingChunks = true

        do {
            // Load sentence fidelity test for this video
            let tests = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)

            if let latestTest = tests.first {
                // Run boundary detection to get chunks
                let boundaryResult = BoundaryDetectionService.shared.detectBoundaries(from: latestTest)
                chunks = boundaryResult.chunks
            }
        } catch {
            print("Failed to load chunks: \(error)")
        }

        isLoadingChunks = false
    }

    /// Get chunk text for a move
    private func chunkText(for move: RhetoricalMove) -> String? {
        guard let chunk = chunks.first(where: { $0.chunkIndex == move.chunkIndex }) else {
            return nil
        }
        return chunk.fullText
    }

    // MARK: - Video Header

    private var videoHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Text(video.durationFormatted)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)

                if video.wordCount > 0 {
                    Text("\(video.wordCount.formatted()) words")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Summary Section

    /// Get the sequence (updated or original)
    private var activeSequence: RhetoricalSequence? {
        updatedSequence ?? video.rhetoricalSequence
    }

    /// Check if enhanced gist data is missing
    private var missingEnhancedCount: Int {
        guard let sequence = activeSequence else { return 0 }
        return sequence.moves.filter { !$0.hasEnhancedGist }.count
    }

    private func summarySection(_ sequence: RhetoricalSequence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sequence Summary")
                    .font(.headline)

                Spacer()

                // Enhanced data indicator
                if missingEnhancedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("\(missingEnhancedCount) missing enhanced data")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } else if sequence.moves.first?.hasEnhancedGist == true {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Enhanced")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }

            HStack(spacing: 20) {
                VStack {
                    Text("\(sequence.moves.count)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Moves")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Category breakdown
                ForEach(RhetoricalCategory.allCases, id: \.self) { category in
                    let count = sequence.moves.filter { $0.moveType.category == category }.count
                    if count > 0 {
                        VStack {
                            Text("\(count)")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(categoryColor(category))
                            Text(category.rawValue)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }

            // Sequence strings
            VStack(alignment: .leading, spacing: 4) {
                Text("Parent Sequence:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(sequence.parentSequenceString)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .padding(8)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
            }

            // Toggle for enhanced details
            if sequence.moves.contains(where: { $0.hasEnhancedGist }) {
                Toggle(isOn: $showEnhancedDetails) {
                    Text("Show Gist Details (A/B)")
                        .font(.caption)
                }
                .toggleStyle(.switch)
            }

            // Re-analyze button if missing enhanced data
            if missingEnhancedCount > 0 {
                Button {
                    Task { await reanalyzeVideo() }
                } label: {
                    HStack {
                        if isReanalyzing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isReanalyzing ? "Re-analyzing..." : "Re-analyze for Enhanced Data")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isReanalyzing || chunks.isEmpty)

                // Progress message
                if isReanalyzing && !reanalysisProgress.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(reanalysisProgress)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if chunks.isEmpty {
                    Text("Load sentence analysis first to enable re-analysis")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let error = reanalysisError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Sequence Visualization

    private func sequenceVisualization(_ sequence: RhetoricalSequence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visual Flow")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }) { move in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(categoryColor(move.moveType.category))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Text("\(move.chunkIndex + 1)")
                                        .font(.system(size: 10))
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }

                            Text(showParentLevel ? String(move.moveType.category.rawValue.prefix(1)) : String(move.moveType.displayName.prefix(3)))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }

                        if move.chunkIndex < sequence.moves.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)

            // Legend
            HStack(spacing: 16) {
                ForEach(RhetoricalCategory.allCases, id: \.self) { category in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(categoryColor(category))
                            .frame(width: 10, height: 10)
                        Text(category.rawValue)
                            .font(.caption2)
                    }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Chunk Search

    private var chunkSearchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search transcript...", text: $chunkSearchText)
                        .autocorrectionDisabled()
                        .onSubmit { executeChunkSearch() }
                    if !chunkSearchText.isEmpty {
                        Button {
                            clearChunkSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)

                Button {
                    executeChunkSearch()
                } label: {
                    Text("Search")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            if isChunkSearchActive {
                if chunkSearchResults.isEmpty {
                    Text("No matches for \"\(chunkSearchText)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(chunkSearchResults.count) section\(chunkSearchResults.count == 1 ? "" : "s") contain \"\(chunkSearchText)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(spacing: 6) {
                        ForEach(chunkSearchResults, id: \.chunkIndex) { result in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedMoveIndex = result.chunkIndex
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Section \(result.chunkIndex + 1)")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue)
                                        .cornerRadius(6)

                                    Text("\(result.category): \(result.moveType)")
                                        .font(.caption)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Image(systemName: expandedMoveIndex == result.chunkIndex ? "checkmark.circle.fill" : "arrow.right.circle")
                                        .font(.caption)
                                        .foregroundColor(expandedMoveIndex == result.chunkIndex ? .green : .secondary)
                                }
                                .padding(8)
                                .background(Color.blue.opacity(0.08))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    private func executeChunkSearch() {
        let query = chunkSearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            clearChunkSearch()
            return
        }

        let lowerQuery = query.lowercased()
        guard let sequence = activeSequence else {
            chunkSearchResults = []
            isChunkSearchActive = true
            return
        }

        var results: [(chunkIndex: Int, moveType: String, category: String)] = []
        let sortedMoves = sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }

        for move in sortedMoves {
            if let text = chunkText(for: move),
               text.lowercased().contains(lowerQuery) {
                results.append((
                    chunkIndex: move.chunkIndex,
                    moveType: move.moveType.displayName,
                    category: move.moveType.category.rawValue
                ))
            }
        }

        chunkSearchResults = results
        isChunkSearchActive = true
    }

    private func clearChunkSearch() {
        chunkSearchText = ""
        chunkSearchResults = []
        isChunkSearchActive = false
    }

    // MARK: - Moves List

    private func movesList(_ sequence: RhetoricalSequence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move Details")
                .font(.headline)

            ForEach(sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }) { move in
                moveRow(move)
            }
        }
    }

    private func moveRow(_ move: RhetoricalMove) -> some View {
        let isExpanded = expandedMoveIndex == move.chunkIndex
        let fullText = chunkText(for: move)

        return VStack(alignment: .leading, spacing: 8) {
            // Header row - tappable to expand
            HStack {
                // Index badge
                Text("\(move.chunkIndex + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(categoryColor(move.moveType.category))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(move.moveType.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(move.moveType.category.rawValue)
                        .font(.caption)
                        .foregroundColor(categoryColor(move.moveType.category))
                }

                Spacer()

                Text("\(Int(move.confidence * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedMoveIndex = nil
                    } else {
                        expandedMoveIndex = move.chunkIndex
                    }
                }
            }

            // Example phrase hint
            Text("\"\(move.moveType.examplePhrase)\"")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()

            // Brief description from AI
            if !move.briefDescription.isEmpty {
                Text(move.briefDescription)
                    .font(.caption)
                    .lineLimit(isExpanded ? nil : 2)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(4)
            }

            // Expanded: Enhanced gist data and full chunk text
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {

                    // Enhanced Gist Section (if available and enabled)
                    if showEnhancedDetails {
                        enhancedGistSection(for: move)
                    }

                    Divider()

                    // Full Chunk Text Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "text.quote")
                                .foregroundColor(.secondary)
                            Text("Full Chunk Text")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()

                            if let text = fullText {
                                // Word count
                                let wordCount = text.split(separator: " ").count
                                Text("\(wordCount) words")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if isLoadingChunks {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading chunk text...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if let text = fullText {
                            Text(text)
                                .font(.caption)
                                .padding(12)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)

                            // Buttons row
                            HStack(spacing: 12) {
                                // Copy chunk button
                                Button {
                                    copyChunkText(text, move: move)
                                } label: {
                                    Label("Copy Chunk", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)

                                // Sentence breakdown button
                                if let chunk = chunks.first(where: { $0.chunkIndex == move.chunkIndex }) {
                                    Button {
                                        sentenceSheetChunk = chunk
                                    } label: {
                                        Label("Sentence Breakdown", systemImage: "list.bullet.rectangle")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        copySentenceBreakdown(chunk: chunk, move: move)
                                    } label: {
                                        Label("Copy Sentences", systemImage: "doc.on.doc.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        } else {
                            Text("Chunk text not available. Run sentence analysis first.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(categoryColor(move.moveType.category).opacity(isExpanded ? 0.15 : 0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isExpanded ? categoryColor(move.moveType.category) : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Enhanced Gist Section

    @ViewBuilder
    private func enhancedGistSection(for move: RhetoricalMove) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with status
            HStack {
                Image(systemName: move.hasEnhancedGist ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(move.hasEnhancedGist ? .green : .orange)
                Text("Enhanced Gist Data")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()

                if !move.hasEnhancedGist {
                    Text("Not Available")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            if move.hasEnhancedGist {
                // Gist A (Deterministic)
                if let gistA = move.gistA {
                    gistCard(
                        title: "Gist A (Deterministic)",
                        subtitle: "Strict, minimal, routing-safe",
                        gist: gistA,
                        color: .blue
                    )
                }

                // Gist B (Flexible)
                if let gistB = move.gistB {
                    gistCard(
                        title: "Gist B (Flexible)",
                        subtitle: "Natural language, semantic matching",
                        gist: gistB,
                        color: .purple
                    )
                }

                // Expanded Description
                if let expanded = move.expandedDescription, !expanded.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundColor(.secondary)
                            Text("Expanded Description")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        Text(expanded)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)
                    }
                }

                // Telemetry
                if let telemetry = move.telemetry {
                    telemetryCard(telemetry)
                }
            } else {
                // Placeholder for missing data
                VStack(alignment: .leading, spacing: 8) {
                    Text("This chunk was analyzed before enhanced gist extraction was available.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Re-analyze the video to extract:")
                        .font(.caption)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Gist A: Deterministic structural description", systemImage: "a.square")
                        Label("Gist B: Flexible semantic description", systemImage: "b.square")
                        Label("Expanded Description: 3-5 sentence analysis", systemImage: "doc.text")
                        Label("Telemetry: Countable signals (stance, perspective, flags)", systemImage: "chart.bar")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    private func gistCard(title: String, subtitle: String, gist: any GistProtocol, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                Spacer()
                Text(gist.frame.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15))
                    .foregroundColor(color)
                    .cornerRadius(4)
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)

            // Subject tags
            HStack(spacing: 4) {
                Text("Subject:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach(gist.subject, id: \.self) { subj in
                    Text(subj)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            // Premise
            Text(gist.premise)
                .font(.caption)
                .italic()
                .padding(6)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(4)
        }
        .padding(10)
        .background(color.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    private func telemetryCard(_ telemetry: ChunkTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundColor(.secondary)
                Text("Telemetry")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()

                // Dominant stance badge
                Text(telemetry.dominantStance.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(stanceColor(telemetry.dominantStance).opacity(0.15))
                    .foregroundColor(stanceColor(telemetry.dominantStance))
                    .cornerRadius(4)
            }

            // Perspective counts
            HStack(spacing: 12) {
                telemetryBadge(label: "1st", count: telemetry.firstPersonCount, color: .cyan)
                telemetryBadge(label: "2nd", count: telemetry.secondPersonCount, color: .green)
                telemetryBadge(label: "3rd", count: telemetry.thirdPersonCount, color: .gray)
            }

            // Sentence flags
            HStack(spacing: 8) {
                if telemetry.numberCount > 0 {
                    flagBadge(label: "#", count: telemetry.numberCount)
                }
                if telemetry.temporalCount > 0 {
                    flagBadge(label: "time", count: telemetry.temporalCount)
                }
                if telemetry.contrastCount > 0 {
                    flagBadge(label: "but", count: telemetry.contrastCount)
                }
                if telemetry.questionCount > 0 {
                    flagBadge(label: "?", count: telemetry.questionCount)
                }
                if telemetry.quoteCount > 0 {
                    flagBadge(label: "\"\"", count: telemetry.quoteCount)
                }
                if telemetry.spatialCount > 0 {
                    flagBadge(label: "loc", count: telemetry.spatialCount)
                }
                if telemetry.technicalCount > 0 {
                    flagBadge(label: "tech", count: telemetry.technicalCount)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private func telemetryBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }

    private func flagBadge(label: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(3)
    }

    private func stanceColor(_ stance: DominantStance) -> Color {
        switch stance {
        case .asserting: return .green
        case .questioning: return .blue
        case .mixed: return .orange
        }
    }

    // MARK: - Re-analyze Video

    private func reanalyzeVideo() async {
        guard !chunks.isEmpty else {
            reanalysisError = "No chunks available. Run sentence analysis first."
            return
        }

        isReanalyzing = true
        reanalysisError = nil
        reanalysisProgress = "Starting analysis of \(chunks.count) chunks..."
        print("🔄 Re-analysis started for video: \(video.videoId) with \(chunks.count) chunks")

        do {
            reanalysisProgress = "Calling Claude API (this may take 30-60 seconds)..."
            print("🔄 Calling RhetoricalMoveService.extractRhetoricalSequence...")

            let startTime = Date()

            // Use RhetoricalMoveService to re-extract with enhanced gists
            let newSequence = try await RhetoricalMoveService.shared.extractRhetoricalSequence(
                videoId: video.videoId,
                chunks: chunks,
                temperature: 0.1
            )

            let elapsed = Date().timeIntervalSince(startTime)
            print("✅ API call completed in \(String(format: "%.1f", elapsed))s - got \(newSequence.moves.count) moves")

            reanalysisProgress = "Saving to Firebase..."

            // Update local state
            updatedSequence = newSequence

            // Save to Firebase
            try await saveUpdatedSequence(newSequence)

            reanalysisProgress = "Complete! \(newSequence.moves.count) moves extracted."
            print("✅ Re-analysis complete and saved")

        } catch {
            print("❌ Re-analysis failed: \(error)")
            reanalysisError = "Re-analysis failed: \(error.localizedDescription)"
            reanalysisProgress = ""
        }

        // Keep showing for a moment before clearing
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        isReanalyzing = false
        reanalysisProgress = ""
    }

    private func saveUpdatedSequence(_ sequence: RhetoricalSequence) async throws {
        // Save rhetorical sequence to Firebase
        try await YouTubeFirebaseService.shared.saveRhetoricalSequence(
            videoId: video.videoId,
            sequence: sequence
        )
    }

    // MARK: - Copy Functions

    private func copyChunkText(_ text: String, move: RhetoricalMove) {
        let content = """
        CHUNK \(move.chunkIndex + 1): \(move.moveType.displayName)
        Category: \(move.moveType.category.rawValue)
        Confidence: \(Int(move.confidence * 100))%

        \(text)
        """

        #if canImport(UIKit)
        UIPasteboard.general.string = content
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #endif
    }

    private func copySentenceBreakdown(chunk: Chunk, move: RhetoricalMove) {
        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        SENTENCE BREAKDOWN: CHUNK \(chunk.chunkIndex + 1) - \(move.moveType.displayName.uppercased())
        ═══════════════════════════════════════════════════════════════════════════════
        Category: \(move.moveType.category.rawValue)
        Sentences: \(chunk.sentences.count)
        Position: \(chunk.positionLabel)

        ───────────────────────────────────────────────────────────────────────────────
        SENTENCES WITH TELEMETRY
        ───────────────────────────────────────────────────────────────────────────────

        """

        for sentence in chunk.sentences {
            let flags = buildSentenceFlags(sentence)

            report += """

        ┌─────────────────────────────────────────────────────────────────────────────
        │ SENTENCE \(sentence.sentenceIndex + 1) (\(sentence.wordCount) words)
        ├─────────────────────────────────────────────────────────────────────────────
        │ "\(sentence.text)"
        ├─────────────────────────────────────────────────────────────────────────────
        │ Stance: \(sentence.stance.uppercased())  |  Perspective: \(sentence.perspective.uppercased())
        │ Flags: \(flags.isEmpty ? "None" : flags.joined(separator: ", "))
        └─────────────────────────────────────────────────────────────────────────────

        """
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }

    private func copyAllSentencesWithTags() {
        guard let sequence = activeSequence else { return }
        let sortedMoves = sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }

        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        ALL SENTENCES WITH TAGS: \(video.title)
        ═══════════════════════════════════════════════════════════════════════════════
        Duration: \(video.durationFormatted)
        Chunks: \(sortedMoves.count)
        Total Sentences: \(chunks.reduce(0) { $0 + $1.sentences.count })

        """

        for move in sortedMoves {
            guard let chunk = chunks.first(where: { $0.chunkIndex == move.chunkIndex }) else { continue }

            report += """

        ───────────────────────────────────────────────────────────────────────────────
        CHUNK \(move.chunkIndex + 1): \(move.moveType.displayName.uppercased()) (\(move.moveType.category.rawValue) > \(move.moveType.displayName))
        ───────────────────────────────────────────────────────────────────────────────

        """

            for sentence in chunk.sentences {
                let flags = buildSentenceFlags(sentence)
                let tagString = flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"

                report += """
        [\(sentence.sentenceIndex + 1)] (\(sentence.stance) | \(sentence.perspective))\(tagString)
        \(sentence.text)

        """
            }
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }

    private func buildSentenceFlags(_ sentence: SentenceTelemetry) -> [String] {
        var flags: [String] = []
        if sentence.hasNumber { flags.append("number") }
        if sentence.endsWithQuestion { flags.append("question") }
        if sentence.endsWithExclamation { flags.append("exclamation") }
        if sentence.hasContrastMarker { flags.append("contrast") }
        if sentence.hasTemporalMarker { flags.append("temporal") }
        if sentence.hasFirstPerson { flags.append("1st-person") }
        if sentence.hasSecondPerson { flags.append("2nd-person") }
        if sentence.hasStatistic { flags.append("statistic") }
        if sentence.hasQuote { flags.append("quote") }
        if sentence.hasNamedEntity { flags.append("named-entity") }
        if sentence.hasRevealLanguage { flags.append("REVEAL") }
        if sentence.hasPromiseLanguage { flags.append("PROMISE") }
        if sentence.hasChallengeLanguage { flags.append("CHALLENGE") }
        if sentence.isTransition { flags.append("TRANSITION") }
        if sentence.isSponsorContent { flags.append("sponsor") }
        if sentence.isCallToAction { flags.append("CTA") }
        return flags
    }

    // MARK: - No Sequence View

    private var noSequenceView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Rhetorical Sequence")
                .font(.headline)

            Text("This video hasn't been analyzed for rhetorical moves yet. Run rhetorical extraction from the creator detail view.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
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

    // MARK: - Copy

    private func copySequenceWithText() {
        guard let sequence = video.rhetoricalSequence else { return }

        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        RHETORICAL SEQUENCE: \(video.title)
        ═══════════════════════════════════════════════════════════════════════════════

        Duration: \(video.durationFormatted)
        Total Moves: \(sequence.moves.count)
        Extracted: \(sequence.extractedAt.formatted())

        ───────────────────────────────────────────────────────────────────────────────
        PARENT SEQUENCE
        ───────────────────────────────────────────────────────────────────────────────
        \(sequence.parentSequenceString)

        ───────────────────────────────────────────────────────────────────────────────
        FULL SEQUENCE
        ───────────────────────────────────────────────────────────────────────────────
        \(sequence.moveSequenceString)

        ───────────────────────────────────────────────────────────────────────────────
        MOVE DETAILS (with full text)
        ───────────────────────────────────────────────────────────────────────────────

        """

        for move in sequence.moves.sorted(by: { $0.chunkIndex < $1.chunkIndex }) {
            let fullText = chunkText(for: move)
            let wordCount = fullText?.split(separator: " ").count ?? 0

            report += """

        ╔═══════════════════════════════════════════════════════════════════════════════
        ║ CHUNK \(move.chunkIndex + 1): \(move.moveType.displayName.uppercased())
        ╠═══════════════════════════════════════════════════════════════════════════════
        ║ Category: \(move.moveType.category.rawValue)
        ║ Confidence: \(Int(move.confidence * 100))%
        ║ Example Phrase: "\(move.moveType.examplePhrase)"
        ╠───────────────────────────────────────────────────────────────────────────────
        ║ GIST (AI Summary):
        ║ \(move.briefDescription)
        """

            if let text = fullText {
                report += """

        ╠───────────────────────────────────────────────────────────────────────────────
        ║ FULL TEXT (\(wordCount) words):
        ╠───────────────────────────────────────────────────────────────────────────────
        \(text)
        """
            } else {
                report += """

        ╠───────────────────────────────────────────────────────────────────────────────
        ║ FULL TEXT: [Not loaded - expand move in UI first or run sentence analysis]
        """
            }

            report += "\n╚═══════════════════════════════════════════════════════════════════════════════\n"
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }

    private func copySequenceGistOnly() {
        guard let sequence = video.rhetoricalSequence else { return }

        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        RHETORICAL SEQUENCE (GIST ONLY): \(video.title)
        ═══════════════════════════════════════════════════════════════════════════════

        Duration: \(video.durationFormatted)
        Total Moves: \(sequence.moves.count)
        Extracted: \(sequence.extractedAt.formatted())

        ───────────────────────────────────────────────────────────────────────────────
        PARENT SEQUENCE
        ───────────────────────────────────────────────────────────────────────────────
        \(sequence.parentSequenceString)

        ───────────────────────────────────────────────────────────────────────────────
        FULL SEQUENCE
        ───────────────────────────────────────────────────────────────────────────────
        \(sequence.moveSequenceString)

        ───────────────────────────────────────────────────────────────────────────────
        MOVE GISTS
        ───────────────────────────────────────────────────────────────────────────────

        """

        for move in sequence.moves.sorted(by: { $0.chunkIndex < $1.chunkIndex }) {
            report += """

        [\(move.chunkIndex + 1)] \(move.moveType.displayName.uppercased()) (\(move.moveType.category.rawValue))
            \(move.briefDescription)

        """
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }
}

// MARK: - Sentence Breakdown Sheet

struct SentenceBreakdownSheet: View {
    let chunk: Chunk
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chunk \(chunk.chunkIndex + 1)")
                            .font(.headline)
                        Text("\(chunk.sentences.count) sentences • \(chunk.positionLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)

                    // Sentences
                    ForEach(chunk.sentences) { sentence in
                        sentenceCard(sentence)
                    }
                }
                .padding()
            }
            .navigationTitle("Sentence Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sentenceCard(_ sentence: SentenceTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sentence number and text
            HStack(alignment: .top) {
                Text("\(sentence.sentenceIndex + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.blue)
                    .clipShape(Circle())

                Text(sentence.text)
                    .font(.callout)
            }

            // Stance and Perspective
            HStack(spacing: 8) {
                Label(sentence.stance, systemImage: "bubble.left")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stanceColor(sentence.stance).opacity(0.2))
                    .foregroundColor(stanceColor(sentence.stance))
                    .cornerRadius(4)

                Label(sentence.perspective, systemImage: "person")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)

                Text("\(sentence.wordCount) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // Flags
            let flags = buildFlagViews(sentence)
            if !flags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(flags, id: \.name) { flag in
                        Text(flag.name)
                            .font(.system(size: 9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(flag.color.opacity(0.2))
                            .foregroundColor(flag.color)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    private func stanceColor(_ stance: String) -> Color {
        switch stance {
        case "asserting": return .green
        case "questioning": return .blue
        case "challenging": return .orange
        default: return .gray
        }
    }

    private func buildFlagViews(_ sentence: SentenceTelemetry) -> [(name: String, color: Color)] {
        var flags: [(String, Color)] = []
        if sentence.hasNumber { flags.append(("number", .gray)) }
        if sentence.endsWithQuestion { flags.append(("?", .blue)) }
        if sentence.endsWithExclamation { flags.append(("!", .orange)) }
        if sentence.hasContrastMarker { flags.append(("contrast", .purple)) }
        if sentence.hasTemporalMarker { flags.append(("temporal", .gray)) }
        if sentence.hasFirstPerson { flags.append(("I/me", .cyan)) }
        if sentence.hasSecondPerson { flags.append(("you", .green)) }
        if sentence.hasStatistic { flags.append(("stat", .indigo)) }
        if sentence.hasQuote { flags.append(("quote", .brown)) }
        if sentence.hasNamedEntity { flags.append(("entity", .teal)) }
        if sentence.hasRevealLanguage { flags.append(("REVEAL", .red)) }
        if sentence.hasPromiseLanguage { flags.append(("PROMISE", .green)) }
        if sentence.hasChallengeLanguage { flags.append(("CHALLENGE", .orange)) }
        if sentence.isTransition { flags.append(("TRANSITION", .purple)) }
        if sentence.isSponsorContent { flags.append(("sponsor", .yellow)) }
        if sentence.isCallToAction { flags.append(("CTA", .pink)) }
        return flags
    }
}

// FlowLayout moved to Helpers/FlowLayout.swift

// MARK: - Preview

#Preview {
    NavigationStack {
        VideoRhetoricalSequenceView(video: YouTubeVideo(
            videoId: "test",
            channelId: "test",
            title: "Test Video",
            description: "Test description",
            publishedAt: Date(),
            duration: "PT10M30S",
            thumbnailUrl: "",
            stats: VideoStats(viewCount: 1000, likeCount: 100, commentCount: 10, viewHistory: nil),
            createdAt: Date()
        ))
    }
}
