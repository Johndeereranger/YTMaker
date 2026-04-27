//
//  DigressionChunkComparisonView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/27/26.
//

import SwiftUI

// MARK: - Chunk Color Palette

private let chunkColors: [Color] = [
    .blue.opacity(0.12),
    .green.opacity(0.12),
    .purple.opacity(0.12),
    .orange.opacity(0.12),
    .cyan.opacity(0.12),
    .pink.opacity(0.12)
]

private func chunkColor(for index: Int) -> Color {
    chunkColors[index % chunkColors.count]
}

private let digressionTint = Color.red.opacity(0.10)

// MARK: - Main View

struct DigressionChunkComparisonView: View {
    let channel: YouTubeChannel
    @StateObject private var viewModel: DigressionChunkComparisonViewModel
    @State private var copyConfirmed = false
    @State private var debugCopyConfirmed = false

    init(channel: YouTubeChannel) {
        self.channel = channel
        self._viewModel = StateObject(wrappedValue: DigressionChunkComparisonViewModel(channel: channel))
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            detailContent
        }
        .navigationTitle("Chunk Comparison")
        .task {
            await viewModel.loadVideoList()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Sort picker
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(ChunkComparisonSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Stats header
            if !viewModel.videoSummaries.isEmpty {
                HStack {
                    Text("\(viewModel.videoSummaries.count) videos with digressions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            Divider()

            // Video list
            if viewModel.isLoadingList {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading videos...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.videoSummaries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No videos with digressions found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.sortedSummaries, selection: $viewModel.selectedVideoId) { summary in
                    videoRow(summary)
                        .tag(summary.videoId)
                }
                .listStyle(.sidebar)
                .onChange(of: viewModel.selectedVideoId) { _, newValue in
                    print("🔍 [ChunkComparisonView] onChange fired, selectedVideoId: \(newValue ?? "nil")")
                    if let videoId = newValue {
                        Task { await viewModel.selectVideo(videoId) }
                    }
                }
            }
        }
    }

    private func videoRow(_ summary: VideoDigressionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.videoTitle)
                .font(.subheadline)
                .lineLimit(2)

            HStack(spacing: 8) {
                // Digression count badge
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("\(summary.digressionCount)")
                        .font(.caption2.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.8))
                .cornerRadius(6)

                // Chunk delta
                HStack(spacing: 2) {
                    Text("\(summary.originalChunkCount)")
                        .font(.caption2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                    Text("\(summary.cleanedChunkCount)")
                        .font(.caption2.bold())
                }
                .foregroundColor(summary.chunkDelta > 0 ? .green : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)

                if summary.chunkDelta > 0 {
                    Text("-\(summary.chunkDelta)")
                        .font(.caption2.bold())
                        .foregroundColor(.green)
                }

                Spacer()
            }

            // Sentence coverage
            Text("\(summary.digressedSentenceCount) of \(summary.totalSentences) sentences (\(String(format: "%.0f", summary.digressionPercent))%)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if viewModel.isLoadingComparison {
            VStack(spacing: 12) {
                ProgressView()
                Text("Computing chunk comparison...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if let data = viewModel.comparisonData {
            comparisonView(data)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "arrow.left.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a video from the sidebar")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Choose a video to compare original vs cleaned chunks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Comparison View

    private func comparisonView(_ data: ChunkComparisonData) -> some View {
        VStack(spacing: 0) {
            // Stats bar
            statsBar(data)

            Divider()

            // Column headers
            columnHeaders(data)

            Divider()

            // Side-by-side transcript
            transcriptComparison(data)
        }
    }

    private func statsBar(_ data: ChunkComparisonData) -> some View {
        HStack(spacing: 20) {
            Text(data.videoTitle)
                .font(.subheadline.bold())
                .lineLimit(1)

            Spacer()

            statBadge(label: "Original", value: "\(data.originalChunks.count) chunks", color: .blue)
            statBadge(label: "Cleaned", value: "\(data.cleanedChunks.count) chunks", color: .green)

            let delta = data.originalChunks.count - data.cleanedChunks.count
            if delta != 0 {
                statBadge(
                    label: "Delta",
                    value: delta > 0 ? "-\(delta)" : "+\(abs(delta))",
                    color: delta > 0 ? .green : .orange
                )
            }

            statBadge(
                label: "Removed",
                value: "\(data.digressionRanges.count) digressions (\(data.excludedIndices.count) sentences)",
                color: .red
            )

            Button {
                copyComparison(data)
            } label: {
                Image(systemName: copyConfirmed ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundColor(copyConfirmed ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy transcript comparison")

            Button {
                copyDebugDeepDive(data)
            } label: {
                Image(systemName: debugCopyConfirmed ? "checkmark.circle.fill" : "ladybug")
                    .foregroundColor(debugCopyConfirmed ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy boundary detection debug deep-dive")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    private func statBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }

    private func columnHeaders(_ data: ChunkComparisonData) -> some View {
        HStack(spacing: 0) {
            // Left header
            HStack {
                Image(systemName: "doc.text")
                Text("Original (\(data.originalChunks.count) chunks)")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.06))

            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1)

            // Right header
            HStack {
                Image(systemName: "doc.text.fill")
                Text("Cleaned (\(data.cleanedChunks.count) chunks)")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.06))
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(.caption)
    }

    // MARK: - Transcript Comparison

    private func transcriptComparison(_ data: ChunkComparisonData) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(data.allSentences) { sentence in
                    sentenceRow(sentence: sentence, data: data)
                }
            }
        }
    }

    private func sentenceRow(sentence: SentenceTelemetry, data: ChunkComparisonData) -> some View {
        let idx = sentence.sentenceIndex
        let isDigression = data.isDigression(idx)
        let origChunkIdx = data.originalChunkIndex(for: idx)
        let cleanChunkIdx = data.cleanedChunkIndex(for: idx)
        let origIsStart = data.isOriginalChunkStart(idx)
        let cleanIsStart = data.isCleanedChunkStart(idx)
        let origTrigger = data.originalBoundaryTrigger(at: idx)
        let cleanTrigger = data.cleanedBoundaryTrigger(at: idx)

        return VStack(spacing: 0) {
            // Boundary trigger labels (above the sentence row)
            if origIsStart || cleanIsStart {
                boundaryTriggerRow(
                    originalTrigger: origIsStart ? origTrigger : nil,
                    cleanedTrigger: cleanIsStart ? cleanTrigger : nil,
                    isOriginalStart: origIsStart,
                    isCleanedStart: cleanIsStart
                )
            }

            // The sentence content
            HStack(spacing: 0) {
                // LEFT: Original
                originalSentenceCell(
                    sentence: sentence,
                    chunkIndex: origChunkIdx,
                    isDigression: isDigression,
                    digressionType: data.digressionType(for: idx)
                )

                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)

                // RIGHT: Cleaned
                cleanedSentenceCell(
                    sentence: sentence,
                    chunkIndex: cleanChunkIdx,
                    isDigression: isDigression,
                    digressionType: data.digressionType(for: idx)
                )
            }
        }
    }

    // MARK: - Boundary Trigger Row

    private func boundaryTriggerRow(
        originalTrigger: BoundaryTrigger?,
        cleanedTrigger: BoundaryTrigger?,
        isOriginalStart: Bool,
        isCleanedStart: Bool
    ) -> some View {
        HStack(spacing: 0) {
            // Left trigger
            HStack {
                if isOriginalStart {
                    triggerLabel(originalTrigger)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)

            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1)

            // Right trigger
            HStack {
                if isCleanedStart {
                    triggerLabel(cleanedTrigger)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.02))
    }

    private func triggerLabel(_ trigger: BoundaryTrigger?) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(height: 1)
                .frame(maxWidth: 20)

            if let trigger {
                Text(trigger.type.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            } else {
                Text("Start")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sentence Cells

    private func originalSentenceCell(
        sentence: SentenceTelemetry,
        chunkIndex: Int?,
        isDigression: Bool,
        digressionType: DigressionType?
    ) -> some View {
        HStack(spacing: 0) {
            // Red left bar for digressions
            if isDigression {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 3)
            }

            HStack(alignment: .top, spacing: 8) {
                // Sentence index
                Text("\(sentence.sentenceIndex)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)

                // Sentence text
                Text(sentence.text)
                    .font(.system(size: 12))
                    .foregroundColor(isDigression ? .secondary : .primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isDigression
                ? digressionTint
                : (chunkIndex.map { chunkColor(for: $0) } ?? Color.clear)
        )
    }

    private func cleanedSentenceCell(
        sentence: SentenceTelemetry,
        chunkIndex: Int?,
        isDigression: Bool,
        digressionType: DigressionType?
    ) -> some View {
        Group {
            if isDigression {
                // Empty placeholder row maintaining alignment
                HStack(spacing: 8) {
                    Text("\(sentence.sentenceIndex)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(width: 30, alignment: .trailing)

                    Text("— removed (\(digressionType?.displayName ?? "digression")) —")
                        .font(.system(size: 11, design: .default))
                        .italic()
                        .foregroundColor(.secondary.opacity(0.4))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.02))
            } else {
                // Normal sentence with cleaned chunk coloring
                HStack(alignment: .top, spacing: 8) {
                    Text("\(sentence.sentenceIndex)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .trailing)

                    Text(sentence.text)
                        .font(.system(size: 12))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(chunkIndex.map { chunkColor(for: $0) } ?? Color.clear)
            }
        }
    }

    // MARK: - Copy

    private func copyComparison(_ data: ChunkComparisonData) {
        let delta = data.originalChunks.count - data.cleanedChunks.count

        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        CHUNK COMPARISON: \(data.videoTitle)
        ═══════════════════════════════════════════════════════════════════════════════
        Original: \(data.originalChunks.count) chunks
        Cleaned:  \(data.cleanedChunks.count) chunks (delta: \(delta > 0 ? "-" : "+")\(abs(delta)))
        Digressions removed: \(data.digressionRanges.count) (\(data.excludedIndices.count) sentences)

        The "Cleaned" version removes detected digressions (sponsor reads, personal
        asides, tangents, etc.) before running boundary detection, producing chunks
        that reflect only the core argument structure.

        ═══════════════════════════════════════════════════════════════════════════════
        ORIGINAL TRANSCRIPT (\(data.originalChunks.count) chunks)
        ═══════════════════════════════════════════════════════════════════════════════

        """

        var lastOrigChunk: Int? = nil
        for sentence in data.allSentences {
            let idx = sentence.sentenceIndex
            let origChunk = data.originalChunkIndex(for: idx)
            let isDigr = data.isDigression(idx)

            // Chunk boundary marker
            if let chunk = origChunk, chunk != lastOrigChunk {
                let trigger = data.originalBoundaryTrigger(at: idx)
                let triggerStr = trigger.map { " [\($0.type.displayName)]" } ?? ""
                report += "\n--- Chunk \(chunk + 1)\(triggerStr) ---\n"
                lastOrigChunk = chunk
            }

            let digrMarker = isDigr ? " [DIGRESSION]" : ""
            report += "[\(idx)] \(sentence.text)\(digrMarker)\n"
        }

        report += """

        ═══════════════════════════════════════════════════════════════════════════════
        CLEANED TRANSCRIPT (\(data.cleanedChunks.count) chunks, digressions removed)
        ═══════════════════════════════════════════════════════════════════════════════

        """

        var lastCleanChunk: Int? = nil
        for sentence in data.allSentences {
            let idx = sentence.sentenceIndex
            if data.isDigression(idx) { continue }

            let cleanChunk = data.cleanedChunkIndex(for: idx)

            // Chunk boundary marker
            if let chunk = cleanChunk, chunk != lastCleanChunk {
                let trigger = data.cleanedBoundaryTrigger(at: idx)
                let triggerStr = trigger.map { " [\($0.type.displayName)]" } ?? ""
                report += "\n--- Chunk \(chunk + 1)\(triggerStr) ---\n"
                lastCleanChunk = chunk
            }

            report += "[\(idx)] \(sentence.text)\n"
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif

        copyConfirmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyConfirmed = false
        }
    }

    // MARK: - Debug Deep-Dive Copy

    /// Types for replaying and evaluating all 7 trigger rules on each sentence

    private struct TriggerEvaluation {
        let ruleResults: [RuleResult]

        /// First rule that fired (matches algorithm's first-match-wins order)
        var firstFiredRule: RuleResult? {
            ruleResults.first(where: { $0.fired })
        }

        /// Rules where >50% of conditions passed but didn't fully fire
        var nearMisses: [RuleResult] {
            ruleResults.filter { !$0.fired && !$0.ctaPositionSuppressed && $0.partialMatchFraction > 0.5 }
        }
    }

    private struct RuleResult {
        let triggerType: BoundaryTrigger.BoundaryTriggerType
        let confidence: BoundaryTrigger.BoundaryConfidence
        let fired: Bool
        let conditions: [(name: String, passed: Bool, detail: String)]
        let whyText: String
        var ctaPositionSuppressed: Bool = false

        var partialMatchFraction: Double {
            guard !conditions.isEmpty else { return 0 }
            let passed = conditions.filter { $0.passed }.count
            return Double(passed) / Double(conditions.count)
        }
    }

    private func copyDebugDeepDive(_ data: ChunkComparisonData) {
        let params = BoundaryDetectionParams.default

        var report = buildDebugHeader(data, params: params)

        // ORIGINAL RUN
        report += "\n\n"
        report += buildRunDebugSection(
            sectionTitle: "ORIGINAL RUN (all \(data.allSentences.count) sentences)",
            allSentences: data.allSentences,
            excludeIndices: nil,
            params: params,
            digressionRanges: data.digressionRanges
        )

        // CLEANED RUN
        let activeCount = data.allSentences.count - data.excludedIndices.count
        report += "\n\n"
        report += buildRunDebugSection(
            sectionTitle: "CLEANED RUN (digressions removed, \(activeCount) active sentences)",
            allSentences: data.allSentences,
            excludeIndices: data.excludedIndices,
            params: params,
            digressionRanges: data.digressionRanges
        )

        // DIFF SECTION
        report += "\n\n"
        report += buildBoundaryDiffSection(data)

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif

        debugCopyConfirmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            debugCopyConfirmed = false
        }
    }

    // MARK: - Debug Header

    private func buildDebugHeader(_ data: ChunkComparisonData, params: BoundaryDetectionParams) -> String {
        """
        BOUNDARY DETECTION DEBUG: "\(data.videoTitle)"
        \(String(repeating: "=", count: 72))
        Algorithm: BoundaryDetectionService v\(BoundaryDetectionService.currentVersion)
        Params: minChunkSize=\(params.minChunkSize), boundaryOnSponsorExit=\(params.boundaryOnSponsorExit), suppressEndCTAs=\(params.suppressEndCTAs), endCTAThreshold=\(params.endCTAThreshold), revealPositionThreshold=\(params.revealPositionThreshold)
        Total Sentences: \(data.allSentences.count)
        Excluded (digressions): \(data.excludedIndices.count)
        Original Chunks: \(data.originalChunks.count)
        Cleaned Chunks: \(data.cleanedChunks.count)

        LEGEND:
          \u{2705} BOUNDARY    -- trigger fired, boundary placed here
          \u{26D4} SUPPRESSED  -- trigger WOULD fire but minChunkSize not met
          ~  NEAR-MISS   -- partial conditions met but rule didn't fire
          .  NO TRIGGER  -- no conditions met (compact line)
          >> EXCLUDED    -- digression sentence removed (cleaned run only)

        TRIGGER RULES (checked in priority order, first match wins):
          1. Transition:         current.isTransition == true                                      [HIGH]
          2. Sponsor Entry:      current.isSponsorContent && !previous.isSponsorContent            [HIGH]
          3. Sponsor Exit:       !current.isSponsorContent && previous.isSponsorContent             [HIGH]
          4. CTA:                current.isCallToAction && !prev.isCallToAction && !prev.isSponsor  [HIGH]
          5. Contrast+Question:  hasContrastMarker && stance=="questioning"                         [MEDIUM]
          6. Reveal:             hasRevealLanguage && pos>0.1 && (hasFirstPerson||isTransition)     [MEDIUM]
          7. Perspective Shift:  prev.persp=="third" && persp=="first" && has1P && questioning      [MEDIUM]
        """
    }

    // MARK: - Run Debug Section

    private func buildRunDebugSection(
        sectionTitle: String,
        allSentences: [SentenceTelemetry],
        excludeIndices: Set<Int>?,
        params: BoundaryDetectionParams,
        digressionRanges: [DigressionRangeInfo]
    ) -> String {
        var report = String(repeating: "=", count: 72) + "\n"
        report += sectionTitle + "\n"
        report += String(repeating: "=", count: 72) + "\n"

        // Filter to active sentences — exactly as BoundaryDetectionService does
        let activeSentences: [SentenceTelemetry]
        if let exclude = excludeIndices {
            activeSentences = allSentences.filter { !exclude.contains($0.sentenceIndex) }
        } else {
            activeSentences = allSentences
        }

        guard !activeSentences.isEmpty else {
            report += "(no active sentences)\n"
            return report
        }

        let total = activeSentences.count
        var lastBoundary = 0
        var currentChunkIdx = 0

        report += "\n--- Chunk 1 [START] ---\n"

        // Walk all sentences in order, tracking position in activeSentences for algorithm replay
        var activeIdx = 0

        for sentence in allSentences {
            let origIdx = sentence.sentenceIndex

            // Check if excluded
            if let exclude = excludeIndices, exclude.contains(origIdx) {
                let digrType = digressionRanges.first(where: { $0.contains(origIdx) })?.type
                report += "[\(origIdx)] >> excluded (\(digrType?.displayName ?? "digression"))\n"
                continue
            }

            guard activeIdx < activeSentences.count else { break }
            let current = activeSentences[activeIdx]

            // First sentence always starts chunk 1, no evaluation needed
            if activeIdx == 0 {
                report += compactSentenceLine(origIdx: origIdx, sentence: current) + "\n"
                activeIdx += 1
                continue
            }

            let previous = activeSentences[activeIdx - 1]
            let sinceLastBoundary = activeIdx - lastBoundary
            let minChunkMet = sinceLastBoundary >= params.minChunkSize

            // Replay ALL 7 trigger rules
            let evaluation = evaluateAllTriggers(
                current: current,
                previous: previous,
                activeIndex: activeIdx,
                total: total,
                params: params
            )

            if let firedRule = evaluation.firstFiredRule {
                if minChunkMet {
                    // BOUNDARY FIRED
                    currentChunkIdx += 1
                    report += formatBoundaryBlock(
                        origIdx: origIdx,
                        sentence: current,
                        previous: previous,
                        rule: firedRule,
                        relativePosition: Double(activeIdx) / Double(total)
                    )
                    report += "\n--- Chunk \(currentChunkIdx + 1) [\(firedRule.triggerType.displayName)] ---\n"
                    lastBoundary = activeIdx
                } else {
                    // SUPPRESSED BY minChunkSize
                    let lastBoundaryOrigIdx = activeSentences[lastBoundary].sentenceIndex
                    report += formatSuppressedBlock(
                        origIdx: origIdx,
                        sentence: current,
                        previous: previous,
                        rule: firedRule,
                        sinceLastBoundary: sinceLastBoundary,
                        lastBoundaryOrigIdx: lastBoundaryOrigIdx,
                        minChunkSize: params.minChunkSize,
                        relativePosition: Double(activeIdx) / Double(total)
                    )
                }
            } else if !evaluation.nearMisses.isEmpty {
                // NEAR MISS
                report += formatNearMissLine(
                    origIdx: origIdx,
                    sentence: current,
                    nearMisses: evaluation.nearMisses
                ) + "\n"
            } else {
                // NO TRIGGER
                report += compactSentenceLine(origIdx: origIdx, sentence: current) + "\n"
            }

            activeIdx += 1
        }

        report += "\n[End of run: \(currentChunkIdx + 1) chunks detected]\n"
        return report
    }

    // MARK: - Trigger Evaluation Engine

    private func evaluateAllTriggers(
        current: SentenceTelemetry,
        previous: SentenceTelemetry,
        activeIndex: Int,
        total: Int,
        params: BoundaryDetectionParams
    ) -> TriggerEvaluation {
        let relativePosition = Double(activeIndex) / Double(total)
        var results: [RuleResult] = []

        // Rule 1: Transition
        results.append(RuleResult(
            triggerType: .transition,
            confidence: .high,
            fired: current.isTransition,
            conditions: [
                ("current.isTransition", current.isTransition, "= \(current.isTransition)")
            ],
            whyText: current.isTransition
                ? "current.isTransition == true -> HIGH CONFIDENCE boundary"
                : "current.isTransition == false -> no match"
        ))

        // Rule 2: Sponsor Entry
        let sponsorEntry = current.isSponsorContent && !previous.isSponsorContent
        results.append(RuleResult(
            triggerType: .sponsor,
            confidence: .high,
            fired: sponsorEntry,
            conditions: [
                ("current.isSponsorContent", current.isSponsorContent, "= \(current.isSponsorContent)"),
                ("!previous.isSponsorContent", !previous.isSponsorContent, "previous.isSponsorContent = \(previous.isSponsorContent)")
            ],
            whyText: sponsorEntry
                ? "Sponsor content starts here -> HIGH CONFIDENCE boundary"
                : "Not a sponsor entry transition"
        ))

        // Rule 3: Sponsor Exit
        let sponsorExitConditions = !current.isSponsorContent && previous.isSponsorContent
        let sponsorExit = params.boundaryOnSponsorExit && sponsorExitConditions
        results.append(RuleResult(
            triggerType: .sponsor,
            confidence: .high,
            fired: sponsorExit,
            conditions: [
                ("boundaryOnSponsorExit", params.boundaryOnSponsorExit, "= \(params.boundaryOnSponsorExit)"),
                ("!current.isSponsorContent", !current.isSponsorContent, "= \(!current.isSponsorContent)"),
                ("previous.isSponsorContent", previous.isSponsorContent, "= \(previous.isSponsorContent)")
            ],
            whyText: sponsorExit
                ? "Exiting sponsor content -> HIGH CONFIDENCE boundary"
                : "Not a sponsor exit"
        ))

        // Rule 4: CTA
        let ctaBase = current.isCallToAction && !previous.isCallToAction && !previous.isSponsorContent
        let ctaPositionOK = !params.suppressEndCTAs || relativePosition < params.endCTAThreshold
        let ctaFired = ctaBase && ctaPositionOK
        results.append(RuleResult(
            triggerType: .cta,
            confidence: .high,
            fired: ctaFired,
            conditions: [
                ("current.isCallToAction", current.isCallToAction, "= \(current.isCallToAction)"),
                ("!previous.isCallToAction", !previous.isCallToAction, "prev = \(previous.isCallToAction)"),
                ("!previous.isSponsorContent", !previous.isSponsorContent, "prev = \(previous.isSponsorContent)"),
                ("position < endCTAThreshold", ctaPositionOK, "relPos=\(String(format: "%.3f", relativePosition)) vs threshold=\(params.endCTAThreshold)")
            ],
            whyText: ctaFired
                ? "CTA starts here (not suppressed) -> HIGH CONFIDENCE boundary"
                : ctaBase && !ctaPositionOK
                    ? "CTA conditions met but SUPPRESSED by endCTAThreshold (\(String(format: "%.3f", relativePosition)) >= \(params.endCTAThreshold))"
                    : "Not a CTA entry",
            ctaPositionSuppressed: ctaBase && !ctaPositionOK
        ))

        // Rule 5: Contrast + Question
        let contrastQ = current.hasContrastMarker && current.stance == "questioning"
        results.append(RuleResult(
            triggerType: .contrastQuestion,
            confidence: .medium,
            fired: contrastQ,
            conditions: [
                ("current.hasContrastMarker", current.hasContrastMarker, "= \(current.hasContrastMarker)"),
                ("stance == \"questioning\"", current.stance == "questioning", "stance = \"\(current.stance)\"")
            ],
            whyText: contrastQ
                ? "Contrast marker + questioning stance -> MEDIUM CONFIDENCE boundary"
                : "Missing: \(!current.hasContrastMarker ? "no contrast marker" : "stance is \"\(current.stance)\" not \"questioning\"")"
        ))

        // Rule 6: Reveal
        let revealPos = current.hasRevealLanguage && relativePosition > params.revealPositionThreshold
        let revealPerson = current.hasFirstPerson || current.isTransition
        let revealFired = revealPos && revealPerson
        results.append(RuleResult(
            triggerType: .reveal,
            confidence: .medium,
            fired: revealFired,
            conditions: [
                ("current.hasRevealLanguage", current.hasRevealLanguage, "= \(current.hasRevealLanguage)"),
                ("relPos > \(params.revealPositionThreshold)", relativePosition > params.revealPositionThreshold, "relPos = \(String(format: "%.3f", relativePosition))"),
                ("hasFirstPerson || isTransition", revealPerson, "hasFirstPerson=\(current.hasFirstPerson), isTransition=\(current.isTransition)")
            ],
            whyText: revealFired
                ? "Reveal language + position + (firstPerson or transition) -> MEDIUM CONFIDENCE boundary"
                : "Reveal conditions not fully met"
        ))

        // Rule 7: Perspective Shift
        let perspShift = previous.perspective == "third" && current.perspective == "first"
            && current.hasFirstPerson && current.stance == "questioning"
        results.append(RuleResult(
            triggerType: .perspectiveShift,
            confidence: .medium,
            fired: perspShift,
            conditions: [
                ("prev.perspective == \"third\"", previous.perspective == "third", "prev.perspective = \"\(previous.perspective)\""),
                ("current.perspective == \"first\"", current.perspective == "first", "current.perspective = \"\(current.perspective)\""),
                ("current.hasFirstPerson", current.hasFirstPerson, "= \(current.hasFirstPerson)"),
                ("stance == \"questioning\"", current.stance == "questioning", "stance = \"\(current.stance)\"")
            ],
            whyText: perspShift
                ? "Third->first perspective + firstPerson + questioning -> MEDIUM CONFIDENCE boundary"
                : "Perspective shift conditions not fully met"
        ))

        return TriggerEvaluation(ruleResults: results)
    }

    // MARK: - Debug Formatting Helpers

    private func compactSentenceLine(origIdx: Int, sentence: SentenceTelemetry) -> String {
        let truncText = String(sentence.text.prefix(60))
        let ellipsis = sentence.text.count > 60 ? "..." : ""
        return "[\(origIdx)] . \"\(truncText)\(ellipsis)\" | stance=\(sentence.stance) persp=\(sentence.perspective)"
    }

    private func formatNearMissLine(origIdx: Int, sentence: SentenceTelemetry, nearMisses: [RuleResult]) -> String {
        let truncText = String(sentence.text.prefix(50))
        let ellipsis = sentence.text.count > 50 ? "..." : ""
        let nearLabels = nearMisses.map { rule in
            let passedConds = rule.conditions.filter { $0.passed }.map { $0.name }.joined(separator: " + ")
            let failedConds = rule.conditions.filter { !$0.passed }.map { $0.name }.joined(separator: " + ")
            return "\(rule.triggerType.displayName)(pass: \(passedConds); fail: \(failedConds))"
        }.joined(separator: ", ")
        return "[\(origIdx)] ~ \"\(truncText)\(ellipsis)\" | stance=\(sentence.stance) persp=\(sentence.perspective) | near: \(nearLabels)"
    }

    private func formatBoundaryBlock(
        origIdx: Int,
        sentence: SentenceTelemetry,
        previous: SentenceTelemetry,
        rule: RuleResult,
        relativePosition: Double
    ) -> String {
        let truncText = String(sentence.text.prefix(80))
        let ellipsis = sentence.text.count > 80 ? "..." : ""
        let rawFields = relevantRawFields(for: rule.triggerType, current: sentence, previous: previous, relativePosition: relativePosition)

        return """
        [\(origIdx)] \u{2705} BOUNDARY [\(rule.triggerType.displayName)] (\(rule.confidence.rawValue) confidence)
            TEXT: "\(truncText)\(ellipsis)"
            WHAT: Boundary placed -- trigger: \(rule.triggerType.displayName)
            RAW:  \(rawFields)
            WHY:  \(rule.whyText)
        """
    }

    private func formatSuppressedBlock(
        origIdx: Int,
        sentence: SentenceTelemetry,
        previous: SentenceTelemetry,
        rule: RuleResult,
        sinceLastBoundary: Int,
        lastBoundaryOrigIdx: Int,
        minChunkSize: Int,
        relativePosition: Double
    ) -> String {
        let truncText = String(sentence.text.prefix(80))
        let ellipsis = sentence.text.count > 80 ? "..." : ""
        let rawFields = relevantRawFields(for: rule.triggerType, current: sentence, previous: previous, relativePosition: relativePosition)

        return """
        [\(origIdx)] \u{26D4} SUPPRESSED [\(rule.triggerType.displayName)] -- minChunkSize not met (\(sinceLastBoundary) < \(minChunkSize) since boundary at [\(lastBoundaryOrigIdx)])
            TEXT: "\(truncText)\(ellipsis)"
            WHAT: Trigger WOULD fire -- \(rule.triggerType.displayName), but suppressed
            RAW:  \(rawFields)
            WHY:  \(rule.whyText) -> BUT distance since last boundary = \(sinceLastBoundary), minChunkSize requires \(minChunkSize)
        """
    }

    private func relevantRawFields(
        for triggerType: BoundaryTrigger.BoundaryTriggerType,
        current: SentenceTelemetry,
        previous: SentenceTelemetry,
        relativePosition: Double
    ) -> String {
        switch triggerType {
        case .transition:
            return "isTransition=\(current.isTransition), stance=\(current.stance), perspective=\(current.perspective)"
        case .sponsor:
            return "current.isSponsorContent=\(current.isSponsorContent), previous.isSponsorContent=\(previous.isSponsorContent)"
        case .cta:
            return "current.isCallToAction=\(current.isCallToAction), previous.isCallToAction=\(previous.isCallToAction), previous.isSponsorContent=\(previous.isSponsorContent), relPos=\(String(format: "%.3f", relativePosition))"
        case .contrastQuestion:
            return "hasContrastMarker=\(current.hasContrastMarker), stance=\(current.stance)"
        case .reveal:
            return "hasRevealLanguage=\(current.hasRevealLanguage), relPos=\(String(format: "%.3f", relativePosition)), hasFirstPerson=\(current.hasFirstPerson), isTransition=\(current.isTransition)"
        case .perspectiveShift:
            return "prev.perspective=\(previous.perspective), current.perspective=\(current.perspective), hasFirstPerson=\(current.hasFirstPerson), stance=\(current.stance)"
        }
    }

    // MARK: - Boundary Diff Section

    private func buildBoundaryDiffSection(_ data: ChunkComparisonData) -> String {
        var report = String(repeating: "=", count: 72) + "\n"
        report += "BOUNDARY DIFF (Original vs Cleaned)\n"
        report += String(repeating: "=", count: 72) + "\n\n"

        // Collect boundary sentence indices using original sentence indices
        let originalBoundaryIndices: Set<Int> = Set(
            data.originalChunks.compactMap { $0.sentences.first?.sentenceIndex }
        )
        let cleanedBoundaryIndices: Set<Int> = Set(
            data.cleanedChunks.compactMap { $0.sentences.first?.sentenceIndex }
        )

        let onlyInOriginal = originalBoundaryIndices.subtracting(cleanedBoundaryIndices).sorted()
        let onlyInCleaned = cleanedBoundaryIndices.subtracting(originalBoundaryIndices).sorted()
        let inBoth = originalBoundaryIndices.intersection(cleanedBoundaryIndices).sorted()

        report += "Boundaries in BOTH runs (\(inBoth.count)): \(inBoth)\n\n"

        report += "Boundaries in ORIGINAL only (\(onlyInOriginal.count)): \(onlyInOriginal)\n"
        if !onlyInOriginal.isEmpty {
            for idx in onlyInOriginal {
                let trigger = data.originalBoundaryTrigger(at: idx)
                let isNearDigression = data.digressionRanges.contains { range in
                    abs(range.startSentence - idx) <= 2 || abs(range.endSentence - idx) <= 2
                }
                let triggerName = trigger?.type.displayName ?? "Start"
                let context = isNearDigression ? " (near digression boundary)" : ""
                let isExcluded = data.excludedIndices.contains(idx)
                let excNote = isExcluded ? " [sentence itself is a digression]" : ""
                report += "  [\(idx)]: \(triggerName)\(context)\(excNote)\n"
            }
        }

        report += "\nBoundaries in CLEANED only (\(onlyInCleaned.count)): \(onlyInCleaned)\n"
        if !onlyInCleaned.isEmpty {
            for idx in onlyInCleaned {
                let trigger = data.cleanedBoundaryTrigger(at: idx)
                let triggerName = trigger?.type.displayName ?? "Start"
                report += "  [\(idx)]: \(triggerName) (exposed after digression removal)\n"
            }
        }

        report += "\nSummary: \(inBoth.count) shared, \(onlyInOriginal.count) original-only, \(onlyInCleaned.count) cleaned-only\n"

        // Digression range reference
        if !data.digressionRanges.isEmpty {
            report += "\nDigression Ranges (for reference):\n"
            for range in data.digressionRanges {
                report += "  s\(range.startSentence)-s\(range.endSentence) (\(range.type.displayName), confidence: \(String(format: "%.0f%%", range.confidence * 100)))\n"
            }
        }

        return report
    }
}

// MARK: - Preview

#Preview {
    DigressionChunkComparisonView(
        channel: YouTubeChannel(
            channelId: "test",
            name: "Test Channel",
            handle: "@test",
            thumbnailUrl: "",
            videoCount: 10,
            lastSynced: Date(),
            isPinned: false,
            notHunting: false
        )
    )
}
