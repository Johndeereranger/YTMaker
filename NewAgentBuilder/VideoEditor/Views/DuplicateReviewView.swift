//
//  DuplicateReviewView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/31/26.
//
//  REFACTORED 2026-02-03: Updated to use seconds accessors for CodableCMTime models.
//

import SwiftUI
import AVKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Duplicate Review View

struct DuplicateReviewView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var viewModel: DuplicateReviewViewModel

    init(project: VideoProject) {
        _viewModel = StateObject(wrappedValue: DuplicateReviewViewModel(project: project))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Video player
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .frame(height: min(geometry.size.height * 0.3, 250))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .padding(.top, 8)
                } else {
                    ProgressView("Loading video...")
                        .frame(height: 200)
                }

                // Playback time indicator
                HStack {
                    Text(formatTime(viewModel.currentTime))
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    // REFACTOR NOTE: Using videoDurationSeconds for TimeInterval
                    if let duration = viewModel.project.videoDurationSeconds {
                        Text(formatTime(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)

                Divider()
                    .padding(.top, 8)

                // Main content
                if viewModel.phrases.isEmpty {
                    emptyState
                } else if let selectedPhrase = viewModel.selectedPhrase {
                    // Show phrase comparison view
                    phraseComparisonView(phrase: selectedPhrase)
                } else {
                    // Show phrase list to select from
                    phraseSelectionList
                }

                Divider()

                // Bottom bar
                bottomBar
            }
        }
        .navigationTitle("Review Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    copyDebugReport()
                } label: {
                    Label("Copy Debug", systemImage: "doc.on.clipboard")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    viewModel.saveAndExit()
                    nav.pop()
                }
            }
        }
        .onAppear {
            viewModel.loadVideo()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("No Duplicates Found")
                .font(.headline)
            Text("Your recording has no repeated phrases")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Phrase Selection List

    private var phraseSelectionList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select a duplicate to review")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.pendingCount) pending")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding()

            List {
                ForEach(viewModel.phrases) { phrase in
                    Button {
                        viewModel.selectedPhrase = phrase
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\"\(phrase.normalizedPhrase.prefix(40))...\"")
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Text("\(phrase.occurrences.count) takes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if phrase.selectedOccurrenceId != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Phrase Comparison View

    private func phraseComparisonView(phrase: RepeatedPhrase) -> some View {
        VStack(spacing: 0) {
            // Overview waveform with all takes highlighted
            if let waveform = viewModel.project.waveformData {
                overviewWaveform(waveform: waveform, phrase: phrase)
                    .frame(height: 50)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            // Phrase header
            VStack(spacing: 4) {
                Text("Compare \(phrase.occurrences.count) Takes")
                    .font(.headline)

                Text("\"\(phrase.normalizedPhrase)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)

            // Stacked take panels
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(phrase.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                        takePanel(
                            occurrence: occurrence,
                            takeNumber: index + 1,
                            isSelected: phrase.selectedOccurrenceId == occurrence.id,
                            isLongest: occurrence.id == viewModel.longestOccurrenceId(for: phrase),
                            isPlaying: viewModel.currentlyPlayingOccurrenceId == occurrence.id
                        )
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Overview Waveform

    private func overviewWaveform(waveform: WaveformData, phrase: RepeatedPhrase) -> some View {
        VStack(spacing: 0) {
            // Waveform canvas
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let totalDuration = waveform.duration

                Canvas { context, size in
                    // Draw waveform background
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: height))

                    let sampleCount = Int(width)
                    for i in 0..<sampleCount {
                        let time = (Double(i) / Double(sampleCount)) * totalDuration
                        let amplitude = CGFloat(waveform.amplitude(at: time))
                        let x = CGFloat(i)
                        let y = height - (amplitude * height * 0.85)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                    context.fill(path, with: .color(.blue.opacity(0.2)))

                    // Draw each take's region
                    let colors: [Color] = [.red, .orange, .purple, .green, .cyan]
                    for (index, occurrence) in phrase.occurrences.enumerated() {
                        let startX = (occurrence.startSeconds / totalDuration) * Double(width)
                        let endX = (occurrence.endSeconds / totalDuration) * Double(width)
                        let color = colors[index % colors.count]

                        let isSelected = phrase.selectedOccurrenceId == occurrence.id

                        // Take region
                        let rect = CGRect(x: startX, y: 0, width: max(4, endX - startX), height: height)
                        context.fill(Path(rect), with: .color(color.opacity(isSelected ? 0.6 : 0.3)))

                        // Border
                        context.stroke(Path(rect), with: .color(color), lineWidth: isSelected ? 2 : 1)

                        // Take number label
                        let label = Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        context.draw(label, at: CGPoint(x: startX + 8, y: height / 2))
                    }

                    // Draw playhead
                    let playheadX = (viewModel.currentTime / totalDuration) * Double(width)
                    let playheadPath = Path { p in
                        p.move(to: CGPoint(x: playheadX, y: 0))
                        p.addLine(to: CGPoint(x: playheadX, y: height))
                    }
                    context.stroke(playheadPath, with: .color(.red), lineWidth: 2)
                }
                // Force Canvas to redraw when selection changes
                .id(phrase.selectedOccurrenceId ?? UUID())
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            .frame(height: 50)

            // Text transcript below waveform
            transcriptOverlay(totalDuration: waveform.duration)
        }
    }

    // MARK: - Transcript Overlay

    private func transcriptOverlay(totalDuration: TimeInterval) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Background
                Color.secondary.opacity(0.05)

                // Words positioned by timestamp
                ForEach(viewModel.project.transcribedWords) { word in
                    let startX = (word.startSeconds / totalDuration) * width
                    let wordWidth = ((word.endSeconds - word.startSeconds) / totalDuration) * width

                    // Only show words that have some visibility
                    if wordWidth > 2 {
                        Text(word.text)
                            .font(.system(size: 8))
                            .foregroundColor(isWordInCurrentPhrase(word) ? .blue : .secondary)
                            .fontWeight(isWordInCurrentPhrase(word) ? .bold : .regular)
                            .lineLimit(1)
                            .frame(width: max(wordWidth, 20), alignment: .leading)
                            .position(x: startX + wordWidth / 2, y: 10)
                    }
                }

                // Current time indicator
                let playheadX = (viewModel.currentTime / totalDuration) * width
                Rectangle()
                    .fill(Color.red.opacity(0.5))
                    .frame(width: 2, height: 20)
                    .position(x: playheadX, y: 10)
            }
        }
        .frame(height: 20)
        .cornerRadius(4)
    }

    private func isWordInCurrentPhrase(_ word: TranscribedWord) -> Bool {
        guard let phrase = viewModel.selectedPhrase else { return false }
        return phrase.occurrences.contains { occ in
            word.startSeconds >= occ.startSeconds && word.endSeconds <= occ.endSeconds
        }
    }

    // MARK: - Take Panel

    private func takePanel(
        occurrence: PhraseOccurrence,
        takeNumber: Int,
        isSelected: Bool,
        isLongest: Bool,
        isPlaying: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Take number badge
                Text("Take \(takeNumber)")
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(takeColor(takeNumber).opacity(0.2))
                    .foregroundColor(takeColor(takeNumber))
                    .cornerRadius(6)

                // Time info
                Text("\(formatTime(occurrence.startSeconds)) - \(formatTime(occurrence.endSeconds))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Duration
                Text(String(format: "(%.1fs)", occurrence.durationSeconds))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Badges
                if isLongest {
                    Text("Longest")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }

                if isSelected {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Selected")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                }
            }

            // Zoomed waveform for this take
            if let waveform = viewModel.project.waveformData {
                takeWaveform(waveform: waveform, occurrence: occurrence, takeNumber: takeNumber, isPlaying: isPlaying)
                    .frame(height: 50)
            }

            // Text content
            Text(occurrence.originalText)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)

            // Action buttons
            HStack(spacing: 12) {
                // Play button
                Button {
                    viewModel.playOccurrence(occurrence)
                } label: {
                    HStack {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        Text(isPlaying ? "Playing..." : "Play")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(BorderedButtonStyle())
                .tint(isPlaying ? .orange : .blue)

                Spacer()

                // Select button
                Button {
                    viewModel.selectOccurrence(occurrence, for: viewModel.selectedPhrase!)
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
                        Text(isSelected ? "Selected" : "Use This Take")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSelected ? Color.green : Color.green.opacity(0.2))
                    .foregroundColor(isSelected ? .white : .green)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(isSelected ? Color.green.opacity(0.08) : Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.green : takeColor(takeNumber).opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }

    // MARK: - Take Waveform (Zoomed)

    private func takeWaveform(
        waveform: WaveformData,
        occurrence: PhraseOccurrence,
        takeNumber: Int,
        isPlaying: Bool
    ) -> some View {
        // REFINE occurrence boundaries using waveform FIRST
        // Then calculate view bounds that include both original and refined boundaries
        let refiner = CutBoundaryRefiner.shared

        // REFACTOR NOTE: Using CodableCMTime for refineCutPoint (it expects CodableCMTime)
        let startResult = refiner.refineCutPoint(whisperTime: occurrence.startTime, waveform: waveform, direction: .backward)
        let endResult = refiner.refineCutPoint(whisperTime: occurrence.endTime, waveform: waveform, direction: .forward)

        // Same 80ms buffer as PreviewCompositionService uses for actual cuts
        // This ensures the visual matches what will actually be cut
        let silenceBuffer: TimeInterval = 0.08

        // For occurrence (kept speech):
        // - Start: move EARLIER (into preceding silence) by buffer
        // - End: move LATER (into following silence) by buffer
        // REFACTOR NOTE: Using seconds for arithmetic with TimeInterval
        let refinedStart = startResult.foundSilence ? max(0, startResult.refinedTime.seconds - silenceBuffer) : occurrence.startSeconds
        let refinedEnd = endResult.foundSilence ? min(waveform.duration, endResult.refinedTime.seconds + silenceBuffer) : occurrence.endSeconds

        // Calculate how much refinement was applied
        let startAdjustment = refinedStart - occurrence.startSeconds
        let endAdjustment = refinedEnd - occurrence.endSeconds

        // Calculate view bounds to include BOTH original and refined boundaries
        let padding: TimeInterval = 0.5
        let viewStart = max(0, min(occurrence.startSeconds, refinedStart) - padding)
        let viewEnd = min(waveform.duration, max(occurrence.endSeconds, refinedEnd) + padding)
        let viewDuration = viewEnd - viewStart

        return VStack(spacing: 0) {
            // Show refinement info if boundaries were adjusted
            if startResult.foundSilence || endResult.foundSilence {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.caption2)
                    Text("Refined:")
                        .font(.caption2)
                    if startResult.foundSilence {
                        Text(String(format: "start %+.0fms", startAdjustment * 1000))
                            .font(.caption2)
                            .foregroundColor(startAdjustment < 0 ? .green : .orange)
                    }
                    if endResult.foundSilence {
                        Text(String(format: "end %+.0fms", endAdjustment * 1000))
                            .font(.caption2)
                            .foregroundColor(endAdjustment > 0 ? .green : .orange)
                    }
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }

            // Waveform canvas
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height

                Canvas { context, size in
                    // Draw waveform
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: height))

                    let sampleCount = Int(width)
                    for i in 0..<sampleCount {
                        let time = viewStart + (Double(i) / Double(sampleCount)) * viewDuration
                        let amplitude = CGFloat(waveform.amplitude(at: time))
                        let x = CGFloat(i)
                        let y = height - (amplitude * height * 0.85)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()

                    // Fill with take color
                    let color = takeColor(takeNumber)
                    context.fill(path, with: .color(color.opacity(0.3)))
                    context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 1)

                    // Calculate positions for BOTH Whisper (original) and refined boundaries
                    let whisperStartX = ((occurrence.startSeconds - viewStart) / viewDuration) * Double(width)
                    let whisperEndX = ((occurrence.endSeconds - viewStart) / viewDuration) * Double(width)
                    let refinedStartX = ((refinedStart - viewStart) / viewDuration) * Double(width)
                    let refinedEndX = ((refinedEnd - viewStart) / viewDuration) * Double(width)

                    // Draw Whisper boundaries (gray dashed) - what the transcription thinks
                    if startResult.foundSilence {
                        let whisperStartLine = Path { p in
                            p.move(to: CGPoint(x: whisperStartX, y: 0))
                            p.addLine(to: CGPoint(x: whisperStartX, y: height))
                        }
                        context.stroke(whisperStartLine, with: .color(.gray.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                    if endResult.foundSilence {
                        let whisperEndLine = Path { p in
                            p.move(to: CGPoint(x: whisperEndX, y: 0))
                            p.addLine(to: CGPoint(x: whisperEndX, y: height))
                        }
                        context.stroke(whisperEndLine, with: .color(.gray.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }

                    // Highlight the REFINED occurrence region (where we'll actually cut)
                    let occRect = CGRect(x: refinedStartX, y: 0, width: refinedEndX - refinedStartX, height: height)
                    context.fill(Path(occRect), with: .color(color.opacity(0.2)))

                    // Draw REFINED boundaries (solid green) - where we'll actually cut
                    let startLine = Path { p in
                        p.move(to: CGPoint(x: refinedStartX, y: 0))
                        p.addLine(to: CGPoint(x: refinedStartX, y: height))
                    }
                    context.stroke(startLine, with: .color(.green), lineWidth: 2)

                    let endLine = Path { p in
                        p.move(to: CGPoint(x: refinedEndX, y: 0))
                        p.addLine(to: CGPoint(x: refinedEndX, y: height))
                    }
                    context.stroke(endLine, with: .color(.green), lineWidth: 2)

                    // Draw playhead if in view
                    if viewModel.currentTime >= viewStart && viewModel.currentTime <= viewEnd {
                        let playheadX = ((viewModel.currentTime - viewStart) / viewDuration) * Double(width)
                        let playheadPath = Path { p in
                            p.move(to: CGPoint(x: playheadX, y: 0))
                            p.addLine(to: CGPoint(x: playheadX, y: height))
                        }
                        context.stroke(playheadPath, with: .color(.red), lineWidth: 2)
                    }
                }
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }
            .frame(height: 35)

            // Word-level transcript for this zoomed view
            takeTranscriptOverlay(viewStart: viewStart, viewDuration: viewDuration, takeNumber: takeNumber)
        }
    }

    // MARK: - Take Transcript Overlay

    private func takeTranscriptOverlay(viewStart: TimeInterval, viewDuration: TimeInterval, takeNumber: Int) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Background
                Color.secondary.opacity(0.05)

                // Words in this time range
                let wordsInView = viewModel.project.transcribedWords.filter { word in
                    word.endSeconds > viewStart && word.startSeconds < (viewStart + viewDuration)
                }

                ForEach(wordsInView) { word in
                    let startX = ((word.startSeconds - viewStart) / viewDuration) * width
                    let wordWidth = ((word.endSeconds - word.startSeconds) / viewDuration) * width

                    Text(word.text)
                        .font(.system(size: 9))
                        .foregroundColor(takeColor(takeNumber))
                        .lineLimit(1)
                        .frame(width: max(wordWidth, 25), alignment: .leading)
                        .position(x: startX + wordWidth / 2, y: 8)
                }

                // Current time indicator
                if viewModel.currentTime >= viewStart && viewModel.currentTime <= viewStart + viewDuration {
                    let playheadX = ((viewModel.currentTime - viewStart) / viewDuration) * width
                    Rectangle()
                        .fill(Color.red.opacity(0.5))
                        .frame(width: 2, height: 16)
                        .position(x: playheadX, y: 8)
                }
            }
        }
        .frame(height: 16)
        .cornerRadius(2)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Back to list
            if viewModel.selectedPhrase != nil {
                Button {
                    viewModel.selectedPhrase = nil
                } label: {
                    Label("All Duplicates", systemImage: "list.bullet")
                }
                .buttonStyle(BorderedButtonStyle())
            }

            Spacer()

            // Navigation between phrases
            if viewModel.selectedPhrase != nil {
                HStack(spacing: 12) {
                    Button {
                        viewModel.selectPreviousPhrase()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!viewModel.canSelectPrevious)

                    Text("\(viewModel.currentPhraseIndex + 1) of \(viewModel.phrases.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        viewModel.selectNextPhrase()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!viewModel.canSelectNext)
                }
            }

            Spacer()

            // Status
            if viewModel.pendingCount > 0 {
                Text("\(viewModel.pendingCount) remaining")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Label("All resolved", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func takeColor(_ takeNumber: Int) -> Color {
        let colors: [Color] = [.red, .orange, .purple, .green, .cyan]
        return colors[(takeNumber - 1) % colors.count]
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }

    // MARK: - Debug Report

    private func copyDebugReport() {
        var report = """
        ════════════════════════════════════════════════════════════════
        DUPLICATE DETECTION DEBUG REPORT
        Generated: \(Date())
        ════════════════════════════════════════════════════════════════

        PROJECT: \(viewModel.project.name)
        VIDEO DURATION: \(viewModel.project.videoDurationSeconds.map { formatTime($0) } ?? "unknown")
        TOTAL WORDS: \(viewModel.project.transcribedWords.count)
        DETECTED PHRASES: \(viewModel.phrases.count)

        ════════════════════════════════════════════════════════════════
        FULL TRANSCRIPT (with word indices and timestamps)
        ════════════════════════════════════════════════════════════════

        """

        let sortedWords = viewModel.project.transcribedWords.sorted { $0.startTime < $1.startTime }

        for (index, word) in sortedWords.enumerated() {
            let timeStr = formatTime(word.startSeconds)
            report += "[\(String(format: "%03d", index))] \(timeStr): \"\(word.text)\"\n"
        }

        report += """

        ════════════════════════════════════════════════════════════════
        DETECTED DUPLICATE PHRASES (\(viewModel.phrases.count) total)
        ════════════════════════════════════════════════════════════════

        """

        if viewModel.phrases.isEmpty {
            report += "No duplicates detected.\n"
        } else {
            for (phraseIndex, phrase) in viewModel.phrases.enumerated() {
                report += """

                ────────────────────────────────────────────────────────────────
                PHRASE \(phraseIndex + 1): "\(phrase.normalizedPhrase)"
                Occurrences: \(phrase.occurrences.count)
                Selected: \(phrase.selectedOccurrenceId?.uuidString ?? "none")
                ────────────────────────────────────────────────────────────────

                """

                for (occIndex, occ) in phrase.occurrences.enumerated() {
                    let isSelected = phrase.selectedOccurrenceId == occ.id
                    report += """
                      TAKE \(occIndex + 1)\(isSelected ? " ★ SELECTED" : ""):
                        Time: \(formatTime(occ.startSeconds)) - \(formatTime(occ.endSeconds)) (duration: \(String(format: "%.2f", occ.durationSeconds))s)
                        Word indices: \(occ.wordRange.lowerBound) to \(occ.wordRange.upperBound - 1)
                        Text: "\(occ.originalText)"

                    """
                }
            }
        }

        // Add gap info
        let autoRemovedGaps = viewModel.project.detectedGaps.filter { $0.removalStatus == .autoRemoved }
        report += """

        ════════════════════════════════════════════════════════════════
        GAPS (from duplicate rejection)
        ════════════════════════════════════════════════════════════════
        Total gaps: \(viewModel.project.detectedGaps.count)
        Auto-removed (from duplicates): \(autoRemovedGaps.count)

        """

        for gap in autoRemovedGaps {
            report += "  • \(formatTime(gap.startSeconds)) - \(formatTime(gap.endSeconds)) (\(String(format: "%.2f", gap.durationSeconds))s)\n"
        }

        report += """

        ════════════════════════════════════════════════════════════════
        SETTINGS
        ════════════════════════════════════════════════════════════════
        Min phrase length: \(viewModel.project.settings.minPhraseLength) words
        Similarity threshold: \(viewModel.project.settings.duplicateSimilarityThreshold)

        ════════════════════════════════════════════════════════════════
        END OF REPORT
        ════════════════════════════════════════════════════════════════
        """

        #if os(iOS)
        UIPasteboard.general.string = report
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif

        print("📋 Debug report copied to clipboard (\(report.count) characters)")
    }
}

// MARK: - Duplicate Review ViewModel

@MainActor
class DuplicateReviewViewModel: ObservableObject {
    @Published var project: VideoProject
    @Published var selectedPhrase: RepeatedPhrase?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var currentlyPlayingOccurrenceId: UUID?

    var player: AVPlayer?
    private var videoURL: URL?
    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private let duplicateService = DuplicateDetectionService.shared

    var phrases: [RepeatedPhrase] {
        project.repeatedPhrases
    }

    var pendingCount: Int {
        phrases.filter { $0.needsReview }.count
    }

    var resolvedCount: Int {
        phrases.filter { $0.selectedOccurrenceId != nil }.count
    }

    var currentPhraseIndex: Int {
        guard let selected = selectedPhrase else { return 0 }
        return phrases.firstIndex { $0.id == selected.id } ?? 0
    }

    var canSelectPrevious: Bool {
        currentPhraseIndex > 0
    }

    var canSelectNext: Bool {
        currentPhraseIndex < phrases.count - 1
    }

    init(project: VideoProject) {
        self.project = project

        // Auto-select first unresolved phrase
        if let firstPending = project.repeatedPhrases.first(where: { $0.needsReview }) {
            self.selectedPhrase = firstPending
        } else if let first = project.repeatedPhrases.first {
            self.selectedPhrase = first
        }
    }

    func loadVideo() {
        guard let url = project.resolveVideoURL() else { return }
        _ = url.startAccessingSecurityScopedResource()
        videoURL = url
        player = AVPlayer(url: url)

        setupTimeObserver()

        // Seek to first occurrence of selected phrase
        // REFACTOR NOTE: Using startSeconds for TimeInterval arithmetic
        if let phrase = selectedPhrase, let first = phrase.occurrences.first {
            seekTo(time: first.startSeconds - 0.5)
        }
    }

    private func setupTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
    }

    func cleanup() {
        player?.pause()
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        if let endObserver = playbackEndObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        playbackEndObserver = nil
        player = nil
        videoURL?.stopAccessingSecurityScopedResource()
    }

    func longestOccurrenceId(for phrase: RepeatedPhrase) -> UUID? {
        phrase.occurrences.max(by: { $0.duration < $1.duration })?.id
    }

    func playOccurrence(_ occurrence: PhraseOccurrence) {
        guard let player = player else { return }

        // If already playing this one, pause
        if currentlyPlayingOccurrenceId == occurrence.id && isPlaying {
            player.pause()
            isPlaying = false
            currentlyPlayingOccurrenceId = nil
            return
        }

        // Seek to start and play
        let startTime = max(0, occurrence.startSeconds - 0.3)
        seekTo(time: startTime)
        player.play()
        isPlaying = true
        currentlyPlayingOccurrenceId = occurrence.id

        // Stop after occurrence ends
        let duration = (occurrence.startSeconds - startTime) + occurrence.durationSeconds + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard self?.currentlyPlayingOccurrenceId == occurrence.id else { return }
            self?.player?.pause()
            self?.isPlaying = false
            self?.currentlyPlayingOccurrenceId = nil
        }
    }

    func selectOccurrence(_ occurrence: PhraseOccurrence, for phrase: RepeatedPhrase) {
        print("🎯 selectOccurrence called:")
        print("   Occurrence: \(occurrence.id) at \(occurrence.startSeconds)-\(occurrence.endSeconds)")
        print("   Phrase: \(phrase.normalizedPhrase)")

        guard let phraseIndex = project.repeatedPhrases.firstIndex(where: { $0.id == phrase.id }) else {
            print("   ❌ Could not find phrase in project.repeatedPhrases!")
            return
        }
        print("   ✓ Found phrase at index \(phraseIndex)")

        // STEP 1: Remove any existing gaps that were created for this phrase's occurrences
        // This is critical when changing selection - old rejection gaps must be removed
        // REFACTOR NOTE: Using seconds for TimeInterval comparisons
        let allOccurrenceTimeRanges = phrase.occurrences.map { ($0.startSeconds, $0.endSeconds) }
        let beforeRemoval = project.detectedGaps.count

        project.detectedGaps.removeAll { gap in
            // Remove gap if it matches any occurrence's time range (with small tolerance)
            allOccurrenceTimeRanges.contains { (start, end) in
                abs(gap.startSeconds - start) < 0.1 && abs(gap.endSeconds - end) < 0.1
            }
        }

        let removedCount = beforeRemoval - project.detectedGaps.count
        if removedCount > 0 {
            print("🗑️ Removed \(removedCount) old duplicate rejection gaps")
        }

        // STEP 2: Update the selected occurrence
        project.repeatedPhrases[phraseIndex].selectedOccurrenceId = occurrence.id

        // STEP 3: Create gaps for rejected occurrences (not the selected one)
        // Pass waveform data so boundaries can be refined to actual silence
        let newGaps = duplicateService.createGapsForRejectedDuplicates(
            phrase: project.repeatedPhrases[phraseIndex],
            selectedId: occurrence.id,
            existingGaps: project.detectedGaps,
            waveformData: project.waveformData
        )

        // Add new gaps to project
        project.detectedGaps.append(contentsOf: newGaps)

        // STEP 4: Merge overlapping gaps
        // Duplicate rejection gaps often overlap with existing silence gaps
        let beforeMerge = project.detectedGaps.count
        project.detectedGaps = mergeAllOverlappingGaps(project.detectedGaps)
        let afterMerge = project.detectedGaps.count
        if beforeMerge != afterMerge {
            print("🔗 Merged \(beforeMerge) gaps → \(afterMerge) gaps")
        }

        // Update local selected phrase
        selectedPhrase = project.repeatedPhrases[phraseIndex]

        // Save immediately
        saveProject()

        // Verify the selection was saved
        print("✅ Selected take at \(formatTime(occurrence.startSeconds)), created \(newGaps.count) gaps for rejected takes")
        print("   Verification - selectedOccurrenceId: \(project.repeatedPhrases[phraseIndex].selectedOccurrenceId?.uuidString ?? "NIL!")")
        print("   Total gaps now: \(project.detectedGaps.count)")
    }

    func selectPreviousPhrase() {
        guard canSelectPrevious else { return }
        selectedPhrase = phrases[currentPhraseIndex - 1]
        // REFACTOR NOTE: Using startSeconds for TimeInterval arithmetic
        if let first = selectedPhrase?.occurrences.first {
            seekTo(time: first.startSeconds - 0.5)
        }
    }

    func selectNextPhrase() {
        guard canSelectNext else { return }
        selectedPhrase = phrases[currentPhraseIndex + 1]
        // REFACTOR NOTE: Using startSeconds for TimeInterval arithmetic
        if let first = selectedPhrase?.occurrences.first {
            seekTo(time: first.startSeconds - 0.5)
        }
    }

    func seekTo(time: TimeInterval) {
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func saveProject() {
        if let data = UserDefaults.standard.data(forKey: "VideoEditorProjects"),
           var projects = try? JSONDecoder().decode([VideoProject].self, from: data) {
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                project.updatedAt = Date()
                projects[index] = project
                if let encoded = try? JSONEncoder().encode(projects) {
                    UserDefaults.standard.set(encoded, forKey: "VideoEditorProjects")
                }
            }
        }
    }

    func saveAndExit() {
        // Update project status
        if pendingCount == 0 && project.pendingGapsCount == 0 {
            project.status = .readyToExport
        }
        saveProject()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Merge all overlapping gaps in the list
    /// Gaps that overlap or are adjacent get combined into single gaps
    /// This is critical when duplicate rejection creates a large gap that contains existing silence gaps
    // REFACTOR NOTE: Updated to use seconds accessors for TimeInterval comparisons
    private func mergeAllOverlappingGaps(_ gaps: [DetectedGap]) -> [DetectedGap] {
        guard !gaps.isEmpty else { return [] }

        // Sort by start time
        let sorted = gaps.sorted { $0.startTime < $1.startTime }
        var merged: [DetectedGap] = []
        var current = sorted[0]

        for i in 1..<sorted.count {
            let next = sorted[i]

            // Check if next gap overlaps with or is adjacent to current (within 1ms)
            // REFACTOR NOTE: Using seconds for comparison with Double threshold
            if next.startSeconds <= current.endSeconds + 0.001 {
                // Merge: extend current gap to include next
                let newEndSeconds = max(current.endSeconds, next.endSeconds)
                // Keep the removal status of whichever was more aggressive (remove > keep)
                let newStatus: GapRemovalStatus = {
                    if current.removalStatus == .remove || next.removalStatus == .remove {
                        return .remove
                    } else if current.removalStatus == .autoRemoved || next.removalStatus == .autoRemoved {
                        return .autoRemoved
                    } else {
                        return current.removalStatus
                    }
                }()

                // REFACTOR NOTE: Using convenience initializer with seconds
                current = DetectedGap(
                    id: current.id,
                    startSeconds: current.startSeconds,
                    endSeconds: newEndSeconds,
                    precedingSegmentId: current.precedingSegmentId,
                    followingSegmentId: next.followingSegmentId,
                    removalStatus: newStatus
                )
            } else {
                // No overlap, save current and start new
                merged.append(current)
                current = next
            }
        }

        // Don't forget the last one
        merged.append(current)

        return merged
    }
}
