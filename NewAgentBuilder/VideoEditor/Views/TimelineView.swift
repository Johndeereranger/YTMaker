//
//  TimelineView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//
//  REFACTORED 2026-02-03: Updated to use seconds accessors for CodableCMTime models.
//

import SwiftUI
import AVFoundation

// MARK: - Timeline View

struct TimelineView: View {
    let duration: TimeInterval
    let words: [TranscribedWord]
    let segments: [SpeechSegment]
    let gaps: [DetectedGap]
    let waveformData: WaveformData?

    /// How much pause to keep when cutting gaps (0 = remove entirely)
    let targetPauseDuration: TimeInterval

    @Binding var currentTime: TimeInterval
    @Binding var zoomLevel: Double // pixels per second
    @Binding var previewMode: Bool // true = collapsed cuts, false = show all

    let onSeek: (TimeInterval) -> Void

    // Zoom constraints
    private let minZoom: Double = 10   // 10 pixels per second (zoomed out)
    private let maxZoom: Double = 200  // 200 pixels per second (zoomed in)

    // Layout constants
    private let waveformHeight: CGFloat = 60
    private let segmentHeight: CGFloat = 30
    private let wordHeight: CGFloat = 24

    // MARK: - Cut Calculations
    //
    // The kept pause is SPLIT between start and end of the gap:
    // - Half at the end of preceding speech (natural breath)
    // - Half at the start of following speech (natural breath)
    //
    // Example: 10s gap with 0.5s targetPauseDuration
    // - Keep 0.25s at start, Cut 9.5s in middle, Keep 0.25s at end

    /// Gaps that will be cut (filtered to only those marked for removal)
    private var cutsToApply: [DetectedGap] {
        gaps.filter { $0.removalStatus == .remove || $0.removalStatus == .autoRemoved }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Calculate actual cut amount for a gap (accounting for kept pause split at both ends)
    // REFACTOR NOTE: Using durationSeconds for TimeInterval arithmetic
    private func actualCutAmount(for gap: DetectedGap) -> TimeInterval {
        // We keep half the target pause at start and half at end
        // So total kept = targetPauseDuration (but never more than gap duration)
        let totalKeep = min(targetPauseDuration, gap.durationSeconds)
        return max(0, gap.durationSeconds - totalKeep)
    }

    /// Calculate where the actual cut starts (after kept pause at start)
    // REFACTOR NOTE: Using startSeconds/durationSeconds for TimeInterval arithmetic
    private func actualCutStart(for gap: DetectedGap) -> TimeInterval {
        let halfKeep = min(targetPauseDuration / 2.0, gap.durationSeconds / 2.0)
        return gap.startSeconds + halfKeep
    }

    /// Calculate where the actual cut ends (before kept pause at end)
    // REFACTOR NOTE: Using endSeconds/durationSeconds for TimeInterval arithmetic
    private func actualCutEnd(for gap: DetectedGap) -> TimeInterval {
        let halfKeep = min(targetPauseDuration / 2.0, gap.durationSeconds / 2.0)
        return gap.endSeconds - halfKeep
    }

    /// Total time being cut (accounting for kept pauses)
    private var totalCutTime: TimeInterval {
        cutsToApply.reduce(0) { $0 + actualCutAmount(for: $1) }
    }

    /// Duration after cuts applied
    private var previewDuration: TimeInterval {
        duration - totalCutTime
    }

    /// Convert original time to preview time (with cuts collapsed, accounting for kept pauses)
    private func originalToPreviewTime(_ time: TimeInterval) -> TimeInterval {
        var adjustedTime = time
        for cut in cutsToApply {
            let cutStart = actualCutStart(for: cut)
            let cutEnd = actualCutEnd(for: cut)
            let cutAmount = actualCutAmount(for: cut)

            if cutAmount <= 0 { continue } // Gap too short to cut

            if time >= cutEnd {
                // Time is after this cut (in kept pause at end or beyond), subtract cut amount
                adjustedTime -= cutAmount
            } else if time > cutStart {
                // Time is inside the actual cut portion, snap to cut start
                adjustedTime -= (time - cutStart)
            }
            // If time is in the kept pause at start (gap.startTime to cutStart), no adjustment
        }
        return adjustedTime
    }

    /// Convert preview time back to original time
    private func previewToOriginalTime(_ previewTime: TimeInterval) -> TimeInterval {
        var originalTime = previewTime
        for cut in cutsToApply {
            let cutStart = actualCutStart(for: cut)
            let cutAmount = actualCutAmount(for: cut)

            if cutAmount <= 0 { continue }

            let cutStartInPreview = originalToPreviewTime(cutStart)
            if previewTime >= cutStartInPreview {
                originalTime += cutAmount
            }
        }
        return min(originalTime, duration)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Zoom controls
            zoomControls

            // Timeline content
            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            // Background with time markers
                            timeMarkersLayer

                            // Waveform layer (dB visualization)
                            waveformLayer
                                .offset(y: 20)

                            // Speech segments layer (on top of waveform)
                            segmentsLayer
                                .offset(y: waveformHeight + 25)

                            // In preview mode: show cut markers as thin red lines
                            // In edit mode: show full gap sections
                            if previewMode {
                                cutMarkersLayer
                                    .offset(y: waveformHeight + 25)
                            } else {
                                gapsLayer
                                    .offset(y: waveformHeight + 25)
                            }

                            // Words layer (visible when zoomed in)
                            if zoomLevel > 50 {
                                wordsLayer
                                    .offset(y: waveformHeight + segmentHeight + 35)
                            }

                            // Playhead
                            playheadLayer
                        }
                        .frame(width: effectiveTimelineWidth, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .coordinateSpace(name: "timeline")
                        .onTapGesture { location in
                            // Pixel position to time - direct mapping, no conversion
                            // In preview mode: seeking composition player with composition time
                            // In edit mode: seeking original player with original time
                            let tappedTime = Double(location.x) / zoomLevel
                            let effectiveDuration = previewMode ? previewDuration : duration
                            let clampedTime = max(0, min(effectiveDuration, tappedTime))
                            onSeek(clampedTime)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var timelineWidth: CGFloat {
        CGFloat(duration * zoomLevel)
    }

    private var effectiveTimelineWidth: CGFloat {
        if previewMode {
            return CGFloat(previewDuration * zoomLevel)
        } else {
            return CGFloat(duration * zoomLevel)
        }
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        HStack {
            // Preview mode toggle
            Button {
                withAnimation {
                    previewMode.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: previewMode ? "eye.fill" : "eye.slash")
                    Text(previewMode ? "Preview" : "Edit")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(previewMode ? Color.green.opacity(0.2) : Color.secondary.opacity(0.2))
                .foregroundColor(previewMode ? .green : .secondary)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())

            // Time saved indicator
            if !cutsToApply.isEmpty {
                Text("-\(formatTimeDuration(totalCutTime))")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }

            Spacer()

            // Zoom controls
            Button {
                withAnimation {
                    zoomLevel = max(minZoom, zoomLevel / 1.5)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomLevel <= minZoom)

            Slider(value: $zoomLevel, in: minZoom...maxZoom)
                .frame(width: 100)

            Button {
                withAnimation {
                    zoomLevel = min(maxZoom, zoomLevel * 1.5)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomLevel >= maxZoom)

            Spacer()

            Text(zoomLevelText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
    }

    private var zoomLevelText: String {
        if zoomLevel < 20 {
            return "Overview"
        } else if zoomLevel < 50 {
            return "Segments"
        } else if zoomLevel < 100 {
            return "Words"
        } else {
            return "Detail"
        }
    }

    // MARK: - Time Markers Layer

    private var timeMarkersLayer: some View {
        Canvas { context, size in
            // Determine marker interval based on zoom
            let interval: TimeInterval
            if zoomLevel < 20 {
                interval = 30 // 30 second marks
            } else if zoomLevel < 50 {
                interval = 10 // 10 second marks
            } else if zoomLevel < 100 {
                interval = 5  // 5 second marks
            } else {
                interval = 1  // 1 second marks
            }

            // In preview mode, show markers for the collapsed duration
            let effectiveDuration = previewMode ? previewDuration : duration

            var time: TimeInterval = 0
            while time <= effectiveDuration {
                let x = time * zoomLevel

                // Draw marker line
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: 1)

                // Draw time label
                let timeText = formatTime(time)
                let textPoint = CGPoint(x: x + 4, y: 2)
                context.draw(Text(timeText).font(.caption2).foregroundColor(.secondary), at: textPoint, anchor: .topLeading)

                time += interval
            }
        }
    }

    // MARK: - Waveform Layer

    private var waveformLayer: some View {
        Canvas { context, size in
            guard let waveform = waveformData, !waveform.samples.isEmpty else { return }

            let width = effectiveTimelineWidth
            let height = waveformHeight

            // Draw waveform as filled path
            var path = Path()
            path.move(to: CGPoint(x: 0, y: height))

            // Draw waveform - in preview mode, skip cut sections
            let sampleCount = Int(width)
            for i in 0..<sampleCount {
                let x = CGFloat(i)

                // Convert x position to time
                let time: TimeInterval
                if previewMode {
                    // In preview mode: x maps to preview time, convert to original time for amplitude lookup
                    let previewTime = Double(i) / zoomLevel
                    time = previewToOriginalTimeForWaveform(previewTime)
                } else {
                    // In edit mode: direct mapping
                    time = (Double(i) / Double(sampleCount)) * duration
                }

                let amplitude = CGFloat(waveform.amplitude(at: time))
                let y = height - (amplitude * height * 0.9)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            // Close path at bottom right
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()

            // Fill with gradient
            let gradient = Gradient(colors: [
                Color.blue.opacity(0.4),
                Color.blue.opacity(0.2)
            ])
            context.fill(path, with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: height)
            ))

            // Draw outline
            var outlinePath = Path()
            outlinePath.move(to: CGPoint(x: 0, y: height))
            for i in 0..<sampleCount {
                let x = CGFloat(i)

                let time: TimeInterval
                if previewMode {
                    let previewTime = Double(i) / zoomLevel
                    time = previewToOriginalTimeForWaveform(previewTime)
                } else {
                    time = (Double(i) / Double(sampleCount)) * duration
                }

                let amplitude = CGFloat(waveform.amplitude(at: time))
                let y = height - (amplitude * height * 0.9)
                outlinePath.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(outlinePath, with: .color(.blue.opacity(0.6)), lineWidth: 1)

            // Draw gap boundary lines directly on waveform (edit mode only)
            // REFACTOR NOTE: Using startSeconds/endSeconds for pixel calculations
            if !previewMode {
                for gap in gaps {
                    // Draw vertical line at gap start
                    let startX = gap.startSeconds * zoomLevel
                    let startPath = Path { p in
                        p.move(to: CGPoint(x: startX, y: 0))
                        p.addLine(to: CGPoint(x: startX, y: height))
                    }
                    let gapLineColor: Color = (gap.removalStatus == .remove || gap.removalStatus == .autoRemoved)
                        ? .red : .orange
                    context.stroke(startPath, with: .color(gapLineColor.opacity(0.8)), lineWidth: 1)

                    // Draw vertical line at gap end
                    let endX = gap.endSeconds * zoomLevel
                    let endPath = Path { p in
                        p.move(to: CGPoint(x: endX, y: 0))
                        p.addLine(to: CGPoint(x: endX, y: height))
                    }
                    context.stroke(endPath, with: .color(gapLineColor.opacity(0.8)), lineWidth: 1)

                    // Shade the gap region on waveform
                    let gapRect = CGRect(x: startX, y: 0, width: endX - startX, height: height)
                    context.fill(Path(gapRect), with: .color(gapLineColor.opacity(0.15)))
                }
            }

        }
        .frame(width: effectiveTimelineWidth, height: waveformHeight, alignment: .topLeading)
    }

    /// Convert preview time to original time for waveform lookup
    /// This maps continuously through the kept segments (accounting for centered pause removal)
    private func previewToOriginalTimeForWaveform(_ previewTime: TimeInterval) -> TimeInterval {
        // Build list of kept segments
        // With centered pause: we keep half at start, cut middle, keep half at end
        var keptSegments: [(previewStart: TimeInterval, originalStart: TimeInterval, duration: TimeInterval)] = []
        var currentOriginalTime: TimeInterval = 0
        var currentPreviewTime: TimeInterval = 0

        for cut in cutsToApply {
            let cutStart = actualCutStart(for: cut)
            let cutEnd = actualCutEnd(for: cut)
            let cutAmount = actualCutAmount(for: cut)

            // Segment before this cut (includes the kept pause at start)
            let segmentDuration = cutStart - currentOriginalTime
            if segmentDuration > 0 {
                keptSegments.append((
                    previewStart: currentPreviewTime,
                    originalStart: currentOriginalTime,
                    duration: segmentDuration
                ))
                currentPreviewTime += segmentDuration
            }

            // Skip to after the cut (which starts at cutEnd, including kept pause at end)
            if cutAmount > 0 {
                currentOriginalTime = cutEnd
            } else {
                currentOriginalTime = cutStart
            }
        }

        // Final segment after last cut
        let finalDuration = duration - currentOriginalTime
        if finalDuration > 0 {
            keptSegments.append((
                previewStart: currentPreviewTime,
                originalStart: currentOriginalTime,
                duration: finalDuration
            ))
        }

        // Find which segment this preview time falls into
        for segment in keptSegments {
            let segmentEnd = segment.previewStart + segment.duration
            if previewTime < segmentEnd {
                // This preview time is in this segment
                let offsetInSegment = previewTime - segment.previewStart
                return segment.originalStart + offsetInSegment
            }
        }

        // Past the end, return last valid time
        return duration
    }

    // MARK: - Segments Layer

    private var segmentsLayer: some View {
        ForEach(segments) { segment in
            segmentView(for: segment)
        }
    }

    @ViewBuilder
    // REFACTOR NOTE: Using startSeconds/endSeconds/durationSeconds for pixel calculations
    private func segmentView(for segment: SpeechSegment) -> some View {
        if previewMode {
            // Check if segment is entirely inside a cut (shouldn't show)
            // Note: CodableCMTime comparison works directly
            let isInsideCut = cutsToApply.contains { cut in
                segment.startTime >= cut.startTime && segment.endTime <= cut.endTime
            }

            if !isInsideCut {
                let previewStart = originalToPreviewTime(segment.startSeconds)
                let previewEnd = originalToPreviewTime(segment.endSeconds)
                let x = previewStart * zoomLevel
                let width = max(2, (previewEnd - previewStart) * zoomLevel)

                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: CGFloat(width), height: segmentHeight)
                    .position(x: CGFloat(x) + CGFloat(width) / 2, y: segmentHeight / 2)
            }
        } else {
            let x = segment.startSeconds * zoomLevel
            let width = max(2, segment.durationSeconds * zoomLevel)

            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: CGFloat(width), height: segmentHeight)
                .position(x: CGFloat(x) + CGFloat(width) / 2, y: segmentHeight / 2)
        }
    }

    // MARK: - Gaps Layer

    // REFACTOR NOTE: Using startSeconds/durationSeconds for pixel calculations
    private var gapsLayer: some View {
        ForEach(gaps) { gap in
            let x = gap.startSeconds * zoomLevel
            let width = max(2, gap.durationSeconds * zoomLevel)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(gapColor(for: gap))
                    .frame(width: CGFloat(width), height: segmentHeight)

                // Show gap duration if wide enough
                if width > 30 {
                    Text(String(format: "%.1fs", gap.durationSeconds))
                        .font(.caption2)
                        .foregroundColor(.white)
                        .frame(width: CGFloat(width))
                }
            }
            .frame(width: CGFloat(width), height: segmentHeight, alignment: .leading)
            .position(x: CGFloat(x) + CGFloat(width) / 2, y: segmentHeight / 2)
        }
    }

    private func gapColor(for gap: DetectedGap) -> Color {
        switch gap.removalStatus {
        case .pending:
            return Color.orange.opacity(0.5)
        case .remove, .autoRemoved:
            return Color.red.opacity(0.5)
        case .keep, .autoKept:
            return Color.green.opacity(0.3)
        }
    }

    // MARK: - Cut Markers Layer (Preview Mode)

    /// In preview mode, shows thin red markers where cuts will be applied
    private var cutMarkersLayer: some View {
        ForEach(cutsToApply) { cut in
            // Calculate position in preview timeline (at end of kept pause)
            let previewX = originalToPreviewTime(actualCutStart(for: cut)) * zoomLevel
            let markerHeight = segmentHeight + 10
            let cutAmount = actualCutAmount(for: cut)

            // Only show marker if there's actually something being cut
            if cutAmount > 0 {
                VStack(spacing: 0) {
                    // Scissors icon on top
                    Image(systemName: "scissors")
                        .font(.system(size: 10))
                        .foregroundColor(.red)

                    // Red cut marker line
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 3, height: markerHeight)

                    // Duration label - show actual cut amount, not full gap
                    Text(String(format: "-%.1fs", cutAmount))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.red)
                }
                .position(x: CGFloat(previewX), y: markerHeight / 2)
            }
        }
    }

    // MARK: - Words Layer

    private var wordsLayer: some View {
        ForEach(words) { word in
            wordView(for: word)
        }
    }

    @ViewBuilder
    // REFACTOR NOTE: Using startSeconds/endSeconds/durationSeconds for pixel calculations
    private func wordView(for word: TranscribedWord) -> some View {
        if previewMode {
            // Check if word is inside a cut (shouldn't show)
            // Note: CodableCMTime comparison works directly
            let isInsideCut = cutsToApply.contains { cut in
                word.startTime >= cut.startTime && word.endTime <= cut.endTime
            }

            if !isInsideCut {
                let previewStart = originalToPreviewTime(word.startSeconds)
                let previewEnd = originalToPreviewTime(word.endSeconds)
                let x = previewStart * zoomLevel
                let width = max(4, (previewEnd - previewStart) * zoomLevel)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: CGFloat(width), height: wordHeight)
                    .overlay(
                        Text(word.text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 2)
                    )
                    .position(x: CGFloat(x) + CGFloat(width) / 2, y: wordHeight / 2)
            }
        } else {
            let x = word.startSeconds * zoomLevel
            let width = max(4, word.durationSeconds * zoomLevel)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.blue.opacity(0.7))
                .frame(width: CGFloat(width), height: wordHeight)
                .overlay(
                    Text(word.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 2)
                )
                .position(x: CGFloat(x) + CGFloat(width) / 2, y: wordHeight / 2)
        }
    }

    // MARK: - Playhead Layer

    private var playheadLayer: some View {
        // currentTime is:
        // - In preview mode: composition time (already "preview time") from the cut composition player
        // - In edit mode: original time from the original video player
        // NO CONVERSION NEEDED - just use directly
        let x = currentTime * zoomLevel
        let totalHeight: CGFloat = waveformHeight + segmentHeight + wordHeight + 60

        // Use a Canvas for the playhead so it aligns exactly with waveform coordinate system
        return Canvas { context, size in
            // Draw playhead line
            let linePath = Path { p in
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: totalHeight))
            }
            context.stroke(linePath, with: .color(.red), lineWidth: 2)

            // Draw playhead handle (circle at top)
            let handleRect = CGRect(x: x - 7, y: 0, width: 14, height: 14)
            context.fill(Path(ellipseIn: handleRect), with: .color(.red))
        }
        .frame(width: effectiveTimelineWidth, height: totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                .onChanged { value in
                    // Pixel position to time - direct mapping, no conversion
                    // In preview mode: seeking composition player with composition time
                    // In edit mode: seeking original player with original time
                    let newTime = Double(value.location.x) / zoomLevel
                    let effectiveDuration = previewMode ? previewDuration : duration
                    let clampedTime = max(0, min(effectiveDuration, newTime))
                    onSeek(clampedTime)
                }
        )
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)

        if zoomLevel > 80 {
            return String(format: "%d:%02d.%d", minutes, seconds, fraction)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func formatTimeDuration(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)

        if minutes > 0 {
            return String(format: "%d:%02d.%d", minutes, seconds, fraction)
        } else {
            return String(format: "%d.%ds", seconds, fraction)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView(
            duration: 60,
            words: [],
            segments: [],
            gaps: [],
            waveformData: nil,
            targetPauseDuration: 0.3,
            currentTime: .constant(10),
            zoomLevel: .constant(30),
            previewMode: .constant(false),
            onSeek: { _ in }
        )
        .frame(height: 200)
    }
}
#endif
