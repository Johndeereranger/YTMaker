//
//  SequenceBookendsView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  Discovery view for opening and closing rhetorical move patterns.
//  Loads all videos with rhetorical sequences for a channel,
//  extracts the first N and last N moves, groups by frequency.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Supporting Types

private enum BookendTab: String, CaseIterable {
    case openings = "Openings"
    case closings = "Closings"
}

private struct BookendPattern: Identifiable {
    let id: String                              // the N-gram key string
    let moves: [RhetoricalMoveType]
    let categories: [RhetoricalCategory]
    let videos: [(videoId: String, title: String)]
    var frequency: Int { videos.count }
}

/// Compact copy button that only computes text on tap (not at view construction).
private struct LazyCopyButton: View {
    let textProvider: () -> String

    @State private var isCopied = false

    init(textProvider: @escaping () -> String) {
        self.textProvider = textProvider
    }

    var body: some View {
        Button {
            let text = textProvider()
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCopied = false
            }
        } label: {
            Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundColor(isCopied ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }
}

/// Bordered copy button that only computes text on tap.
private struct LazyCopyAllButton: View {
    let label: String
    let systemImage: String
    let textProvider: () -> String

    @State private var isCopied = false
    @State private var opacity: Double = 1.0

    init(label: String, systemImage: String = "doc.on.doc.fill", textProvider: @escaping () -> String) {
        self.label = label
        self.systemImage = systemImage
        self.textProvider = textProvider
    }

    var body: some View {
        Button {
            let text = textProvider()
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            withAnimation {
                isCopied = true
                opacity = 0.5
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    isCopied = false
                    opacity = 1.0
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : systemImage)
                Text(isCopied ? "Copied!" : label)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(isCopied ? .green : .blue)
        .opacity(opacity)
        .disabled(isCopied)
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }
}

/// Menu-item copy button that only computes text on tap.
private struct ChunkedCopyButton: View {
    let textProvider: () -> String
    let label: String
    let estimatedWordCount: Int

    @State private var isCopied = false

    var body: some View {
        Button {
            let text = textProvider()
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCopied = false
            }
        } label: {
            Label(
                isCopied ? "Copied!" : "\(label) (~\(estimatedWordCount.formatted()) words)",
                systemImage: isCopied ? "checkmark" : "doc.on.doc"
            )
        }
    }
}

// MARK: - Main View

struct SequenceBookendsView: View {
    let channel: YouTubeChannel

    @State private var depth: Int = 3
    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var selectedTab: BookendTab = .openings
    @State private var expandedPatternIds: Set<String> = []
    @State private var expandedVideoIds: Set<String> = []
    @State private var useParentLevel = false
    @State private var isEnriching = false
    @State private var enrichedCount = 0
    @State private var enrichTotal = 0

    private var sequenceVideos: [YouTubeVideo] {
        videos.filter { $0.rhetoricalSequence != nil }
    }

    private var videosNeedingEnrichment: [YouTubeVideo] {
        sequenceVideos.filter { video in
            guard let seq = video.rhetoricalSequence else { return false }
            return seq.moves.contains { $0.startSentence == nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if sequenceVideos.isEmpty {
                emptyState
            } else {
                controlsBar
                Divider()
                patternList
            }
        }
        .navigationTitle("Sequence Bookends")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadVideos()
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        VStack(spacing: 10) {
            // Depth stepper + video count
            HStack {
                Text("Depth")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper("\(depth) moves", value: $depth, in: 2...8)
                    .font(.caption)

                Spacer()

                Text("\(sequenceVideos.count) videos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Openings / Closings tab
            HStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(BookendTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Spacer().frame(width: 12)

                // Parent level toggle
                Toggle(isOn: $useParentLevel) {
                    Text("Categories")
                        .font(.caption2)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Enrichment backfill button
            if isEnriching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Enriching \(enrichedCount)/\(enrichTotal)...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !videosNeedingEnrichment.isEmpty {
                Button {
                    Task { await enrichMissingSentenceRanges() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("Enrich \(videosNeedingEnrichment.count) videos")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    // MARK: - Pattern List

    private var patternList: some View {
        let patterns = computePatterns()

        return ScrollView {
            LazyVStack(spacing: 8) {
                // Summary header
                if !patterns.isEmpty {
                    summaryHeader(patterns: patterns)
                }

                ForEach(patterns) { pattern in
                    patternCard(pattern)
                }

                // Copy all menu
                if !patterns.isEmpty {
                    copyAllMenu(patterns: patterns)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    // MARK: - Summary Header

    private func summaryHeader(patterns: [BookendPattern]) -> some View {
        let uniqueCount = patterns.count
        let mostCommon = patterns.first
        let tab = selectedTab == .openings ? "opening" : "closing"

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(uniqueCount) unique \(tab) \(uniqueCount == 1 ? "pattern" : "patterns") at depth \(depth)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let top = mostCommon, top.frequency > 1 {
                HStack(spacing: 4) {
                    Text("Most common:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(top.frequency)× across \(sequenceVideos.count) videos")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.teal)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: - Pattern Card

    private func patternCard(_ pattern: BookendPattern) -> some View {
        let isExpanded = expandedPatternIds.contains(pattern.id)

        return VStack(alignment: .leading, spacing: 8) {
            // Header: frequency + move badges
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedPatternIds.remove(pattern.id)
                    } else {
                        expandedPatternIds.insert(pattern.id)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    // Frequency badge
                    Text("\(pattern.frequency)x")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 28)
                        .background(frequencyColor(pattern.frequency, total: sequenceVideos.count))
                        .cornerRadius(6)

                    // Move sequence as badges
                    VStack(alignment: .leading, spacing: 4) {
                        moveBadgeRow(pattern)

                        // Category flow (always show when in move-level mode)
                        if !useParentLevel {
                            Text(pattern.categories.map(\.rawValue).joined(separator: " \u{2192} "))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    LazyCopyButton { [self] in buildPatternGroupText(pattern) }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Expanded: per-video list
            if isExpanded {
                Divider()
                ForEach(pattern.videos, id: \.videoId) { video in
                    let isVideoExpanded = expandedVideoIds.contains(video.videoId)
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isVideoExpanded {
                                    expandedVideoIds.remove(video.videoId)
                                } else {
                                    expandedVideoIds.insert(video.videoId)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(video.title)
                                    .font(.caption)
                                    .lineLimit(isVideoExpanded ? nil : 2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                LazyCopyButton { [self] in buildVideoText(videoId: video.videoId) }
                                Image(systemName: isVideoExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if isVideoExpanded {
                            videoMoveDetail(videoId: video.videoId)
                        }
                    }
                    .padding(.leading, 44)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Move Badge Row

    private func moveBadgeRow(_ pattern: BookendPattern) -> some View {
        let items: [(label: String, color: Color)]

        if useParentLevel {
            items = pattern.categories.map { cat in
                (cat.rawValue, categoryColor(cat))
            }
        } else {
            items = pattern.moves.map { move in
                (move.displayName, categoryColor(move.category))
            }
        }

        return FlowLayout(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 0) {
                    if index > 0 {
                        Text(" \u{2192} ")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Text(item.label)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.color.opacity(0.12))
                        .foregroundColor(item.color)
                        .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - Copy All Menu

    @ViewBuilder
    private func copyAllMenu(patterns: [BookendPattern]) -> some View {
        let estimates = patterns.map { estimatePatternWordCount($0) }
        let totalWords = estimates.reduce(0, +)
        let wordLimit = 50_000

        if totalWords <= wordLimit {
            // Small enough — single lazy copy button
            LazyCopyAllButton(label: "Copy All (~\(totalWords.formatted()) words)") { [self] in
                patterns.map { buildPatternGroupText($0) }.joined(separator: "\n\n")
            }
        } else {
            // Too large — split into chunks at pattern boundaries, build text lazily on tap
            let chunkRanges = buildChunkRanges(estimates: estimates, limit: wordLimit)
            Menu {
                ForEach(Array(chunkRanges.enumerated()), id: \.offset) { index, range in
                    ChunkedCopyButton(
                        textProvider: { [self] in
                            patterns[range.startIdx...range.endIdx]
                                .map { buildPatternGroupText($0) }
                                .joined(separator: "\n\n")
                        },
                        label: "Copy Part \(index + 1) of \(chunkRanges.count) \u{2014} Patterns \(range.label)",
                        estimatedWordCount: range.wordCount
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Copy All (\(chunkRanges.count) parts \u{2022} ~\(totalWords.formatted()) words)")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
    }

    private struct ChunkRange {
        let startIdx: Int
        let endIdx: Int       // inclusive
        let wordCount: Int
        let label: String     // e.g. "1–12"
    }

    private func buildChunkRanges(estimates: [Int], limit: Int) -> [ChunkRange] {
        var ranges: [ChunkRange] = []
        var currentWords = 0
        var chunkStart = 0

        for (index, words) in estimates.enumerated() {
            if currentWords + words > limit && chunkStart < index {
                let end = index - 1
                ranges.append(ChunkRange(
                    startIdx: chunkStart,
                    endIdx: end,
                    wordCount: currentWords,
                    label: "\(chunkStart + 1)\u{2013}\(end + 1)"
                ))
                chunkStart = index
                currentWords = 0
            }
            currentWords += words
        }

        // Final chunk
        let end = estimates.count - 1
        ranges.append(ChunkRange(
            startIdx: chunkStart,
            endIdx: end,
            wordCount: currentWords,
            label: chunkStart == end ? "\(chunkStart + 1)" : "\(chunkStart + 1)\u{2013}\(end + 1)"
        ))

        return ranges
    }

    /// Cheap word count estimate using transcript wordCount scaled by depth fraction.
    private func estimatePatternWordCount(_ pattern: BookendPattern) -> Int {
        var count = 20 // header overhead
        for video in pattern.videos {
            guard let v = videos.first(where: { $0.videoId == video.videoId }),
                  let seq = v.rhetoricalSequence else { continue }
            let totalMoves = seq.moves.count
            guard totalMoves > 0 else { continue }
            let fraction = Double(min(depth, totalMoves)) / Double(totalMoves)
            count += Int(fraction * Double(v.wordCount)) + (depth * 5)
            count += 10 // title line
        }
        return count
    }

    // MARK: - Text Builders for Copy

    /// Build plain-text for a single video's opening/closing breakdown.
    private func buildVideoText(videoId: String) -> String {
        guard let video = videos.first(where: { $0.videoId == videoId }),
              let seq = video.rhetoricalSequence else { return "" }

        let sortedMoves = seq.moves.sorted { $0.chunkIndex < $1.chunkIndex }
        let slice: [RhetoricalMove] = selectedTab == .openings
            ? Array(sortedMoves.prefix(depth))
            : Array(sortedMoves.suffix(depth))
        let sentences = video.transcript.map { SentenceParser.parse($0) } ?? []

        var lines: [String] = []
        lines.append("Title: \(video.title)")

        for (index, move) in slice.enumerated() {
            let prevCategory = index > 0 ? slice[index - 1].moveType.category : nil

            // Category header
            if index == 0 || move.moveType.category != prevCategory {
                lines.append("")
                lines.append("\(move.moveType.category.rawValue) \u{2014} \(move.moveType.displayName)")
            } else {
                lines.append("\(move.moveType.displayName)")
            }

            // Sentence text or fallback
            if let start = move.startSentence, let end = move.endSentence,
               !sentences.isEmpty, start < sentences.count {
                let safeEnd = min(end, sentences.count - 1)
                for i in start...safeEnd {
                    lines.append("[\(i + 1)] \(sentences[i])")
                }
            } else {
                lines.append("  \(move.briefDescription)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Build plain-text for an entire pattern group (all videos).
    private func buildPatternGroupText(_ pattern: BookendPattern) -> String {
        let label: String
        if useParentLevel {
            label = pattern.categories.map(\.rawValue).joined(separator: " \u{2192} ")
        } else {
            label = pattern.moves.map(\.displayName).joined(separator: " \u{2192} ")
        }

        var parts: [String] = []
        parts.append("\(label) (\(pattern.frequency)x)")
        parts.append(String(repeating: "=", count: 50))

        for video in pattern.videos {
            parts.append(buildVideoText(videoId: video.videoId))
        }

        return parts.joined(separator: "\n---\n")
    }

    // MARK: - Pattern Computation

    private func computePatterns() -> [BookendPattern] {
        var grouping: [String: (moves: [RhetoricalMoveType], categories: [RhetoricalCategory], videos: [(videoId: String, title: String)])] = [:]

        for video in sequenceVideos {
            guard let seq = video.rhetoricalSequence else { continue }
            let sortedMoves = seq.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            guard sortedMoves.count >= depth else { continue }

            let slice: [RhetoricalMove]
            switch selectedTab {
            case .openings:
                slice = Array(sortedMoves.prefix(depth))
            case .closings:
                slice = Array(sortedMoves.suffix(depth))
            }

            let moveTypes = slice.map(\.moveType)
            let categories = moveTypes.map(\.category)

            let key: String
            if useParentLevel {
                key = categories.map(\.rawValue).joined(separator: " \u{2192} ")
            } else {
                key = moveTypes.map(\.displayName).joined(separator: " \u{2192} ")
            }

            if grouping[key] == nil {
                grouping[key] = (moves: moveTypes, categories: categories, videos: [])
            }
            grouping[key]?.videos.append((videoId: video.videoId, title: video.title))
        }

        return grouping
            .map { BookendPattern(id: $0.key, moves: $0.value.moves, categories: $0.value.categories, videos: $0.value.videos) }
            .sorted { $0.frequency > $1.frequency }
    }

    // MARK: - Data Loading

    private func loadVideos() async {
        isLoading = true
        do {
            videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channel.channelId)
        } catch {
            print("[SequenceBookends] Failed to load videos: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Sentence Range Enrichment

    /// Backfill missing startSentence/endSentence from stored boundary chunk records.
    private func enrichMissingSentenceRanges() async {
        let toEnrich = videosNeedingEnrichment
        guard !toEnrich.isEmpty else { return }

        isEnriching = true
        enrichedCount = 0
        enrichTotal = toEnrich.count

        let boundaryService = LLMBoundaryService()
        await boundaryService.loadResults(forChannelId: channel.channelId)

        for video in toEnrich {
            guard let seq = video.rhetoricalSequence,
                  let boundaryResult = boundaryService.result(forVideoId: video.videoId) else {
                enrichedCount += 1
                continue
            }

            let enriched = enrichSequenceFromChunkRecords(
                sequence: seq,
                chunkRecords: boundaryResult.chunks
            )

            do {
                try await YouTubeFirebaseService.shared.saveRhetoricalSequence(
                    videoId: video.videoId,
                    sequence: enriched
                )
            } catch {
                print("[SequenceBookends] Failed to save enriched sequence for \(video.videoId): \(error.localizedDescription)")
            }

            enrichedCount += 1
        }

        // Reload to pick up enriched data
        await loadVideos()
        isEnriching = false
    }

    /// Lightweight enrichment — maps chunkIndex to sentence ranges without full Chunk reconstruction.
    private func enrichSequenceFromChunkRecords(
        sequence: RhetoricalSequence,
        chunkRecords: [LLMChunkRecord]
    ) -> RhetoricalSequence {
        let chunkMap = Dictionary(
            uniqueKeysWithValues: chunkRecords.map { ($0.chunkIndex, (start: $0.startSentence, end: $0.endSentence)) }
        )

        let enrichedMoves = sequence.moves.map { move -> RhetoricalMove in
            let range = chunkMap[move.chunkIndex]
            return RhetoricalMove(
                id: move.id,
                chunkIndex: move.chunkIndex,
                moveType: move.moveType,
                confidence: move.confidence,
                alternateType: move.alternateType,
                alternateConfidence: move.alternateConfidence,
                briefDescription: move.briefDescription,
                gistA: move.gistA,
                gistB: move.gistB,
                expandedDescription: move.expandedDescription,
                telemetry: move.telemetry,
                startSentence: move.startSentence ?? range?.start,
                endSentence: move.endSentence ?? range?.end
            )
        }

        return RhetoricalSequence(
            id: sequence.id,
            videoId: sequence.videoId,
            moves: enrichedMoves,
            extractedAt: sequence.extractedAt
        )
    }

    // MARK: - Video Move Detail

    @ViewBuilder
    private func videoMoveDetail(videoId: String) -> some View {
        if let video = videos.first(where: { $0.videoId == videoId }),
           let seq = video.rhetoricalSequence {
            let sortedMoves = seq.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            let slice: [RhetoricalMove] = selectedTab == .openings
                ? Array(sortedMoves.prefix(depth))
                : Array(sortedMoves.suffix(depth))
            let sentences = video.transcript.map { SentenceParser.parse($0) } ?? []

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(slice.enumerated()), id: \.offset) { index, move in
                    let prevCategory = index > 0 ? slice[index - 1].moveType.category : nil
                    let showSeparator = index > 0 && move.moveType.category != prevCategory

                    if showSeparator {
                        Divider().padding(.vertical, 6)
                    }

                    if index == 0 || move.moveType.category != prevCategory {
                        Text("\(move.moveType.category.rawValue) \u{2014} \(move.moveType.displayName)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(categoryColor(move.moveType.category))
                            .padding(.top, index == 0 ? 4 : 0)
                            .padding(.bottom, 2)
                    } else {
                        Text(move.moveType.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(categoryColor(move.moveType.category).opacity(0.8))
                            .padding(.bottom, 2)
                    }

                    if let start = move.startSentence, let end = move.endSentence,
                       !sentences.isEmpty, start < sentences.count {
                        let safeEnd = min(end, sentences.count - 1)
                        ForEach(start...safeEnd, id: \.self) { i in
                            Text("[\(i + 1)] \(sentences[i])")
                                .font(.system(size: 11))
                                .foregroundColor(.primary.opacity(0.85))
                                .padding(.leading, 8)
                                .padding(.vertical, 1)
                        }
                    } else {
                        Text(move.briefDescription)
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.85))
                            .italic()
                            .padding(.leading, 8)
                            .padding(.vertical, 1)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(6)
        }
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

    private func frequencyColor(_ frequency: Int, total: Int) -> Color {
        let ratio = Double(frequency) / Double(max(total, 1))
        if ratio >= 0.4 { return .green }
        if ratio >= 0.2 { return .teal }
        if frequency > 1 { return .blue }
        return .secondary
    }

    // MARK: - Empty / Loading States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading videos...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.quote")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Rhetorical Sequences")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Run the LLM Pipeline to extract rhetorical moves from this creator's videos first.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
