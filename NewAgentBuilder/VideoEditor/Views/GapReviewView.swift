//
//  GapReviewView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//
//  REFACTORED 2026-02-03: Updated to use seconds accessors for CodableCMTime models.
//

import SwiftUI
import AVKit
import CoreMedia

// MARK: - Gap Review View

struct GapReviewView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var viewModel: GapReviewViewModel

    init(project: VideoProject) {
        _viewModel = StateObject(wrappedValue: GapReviewViewModel(project: project))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Video preview with waveform context
                if viewModel.showVideoPreview {
                    videoAndWaveformSection
                        .frame(height: geometry.size.height * 0.45)
                }

                Divider()

                // Stats header with clear counts
                statsHeader

                Divider()

                // Filter tabs - now shows "Needs Review" instead of just "Pending"
                filterTabs

                Divider()

                // Gap list or empty state
                if viewModel.filteredGaps.isEmpty {
                    emptyState
                } else {
                    gapList
                }

                Divider()

                // Bottom action bar
                actionBar
            }
        }
        .navigationTitle("Review Gaps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.copyGapReviewDebugReport()
                } label: {
                    Label("Debug", systemImage: "doc.on.clipboard")
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

    // MARK: - Video and Waveform Section

    private var videoAndWaveformSection: some View {
        VStack(spacing: 0) {
            // Video player (smaller)
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.top, 8)
            } else {
                ProgressView("Loading video...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Waveform section
            if let waveform = viewModel.project.waveformData {
                VStack(spacing: 4) {
                    // Overview waveform - shows entire video with view region highlighted
                    overviewWaveform(waveform: waveform)
                        .frame(height: 40)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Detail waveform - zoomed to current gap context
                    if let selectedGap = viewModel.selectedGap {
                        gapContextWaveform(waveform: waveform, gap: selectedGap)
                            .frame(height: 70)
                            .padding(.horizontal)
                    } else {
                        Text("Select a gap to see detail view")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(height: 70)
                    }
                }
                .padding(.bottom, 4)
            }

            // Playback controls
            playbackControls
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .background(Color.black.opacity(0.05))
    }

    // MARK: - Overview Waveform (Full Video)

    private func overviewWaveform(waveform: WaveformData) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let totalDuration = waveform.duration

            // Calculate view region for detail waveform (if gap selected)
            // REFACTOR NOTE: Using startSeconds/durationSeconds for TimeInterval calculations
            let viewRegion: (start: TimeInterval, end: TimeInterval)? = {
                guard let gap = viewModel.selectedGap else { return nil }
                let contextDuration: TimeInterval = 5.0
                let gapCenter = gap.startSeconds + (gap.durationSeconds / 2)
                let viewStart = max(0, gapCenter - contextDuration / 2)
                let viewEnd = min(waveform.duration, gapCenter + contextDuration / 2)
                return (viewStart, viewEnd)
            }()

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    // Draw waveform
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

                    // Fill waveform
                    context.fill(path, with: .color(.blue.opacity(0.2)))

                    // Draw ALL gaps on overview
                    // REFACTOR NOTE: Using startSeconds/endSeconds for pixel calculations
                    for gap in viewModel.project.detectedGaps {
                        let gapStartX = (gap.startSeconds / totalDuration) * Double(width)
                        let gapEndX = (gap.endSeconds / totalDuration) * Double(width)
                        let gapWidth = max(2, gapEndX - gapStartX)

                        let isSelected = gap.id == viewModel.selectedGapId
                        let willCut = gap.removalStatus == .remove || gap.removalStatus == .autoRemoved

                        // Gap marker
                        let gapRect = CGRect(x: gapStartX, y: 0, width: gapWidth, height: height)
                        let gapColor: Color = willCut ? .red : .orange
                        context.fill(Path(gapRect), with: .color(gapColor.opacity(isSelected ? 0.8 : 0.4)))

                        // Selected gap border
                        if isSelected {
                            let borderPath = Path(gapRect)
                            context.stroke(borderPath, with: .color(.yellow), lineWidth: 2)
                        }
                    }

                    // Draw view region highlight (what's shown in detail view)
                    if let region = viewRegion {
                        let regionStartX = (region.start / totalDuration) * Double(width)
                        let regionEndX = (region.end / totalDuration) * Double(width)
                        let regionRect = CGRect(x: regionStartX, y: 0, width: regionEndX - regionStartX, height: height)

                        // Semi-transparent highlight
                        context.stroke(Path(regionRect), with: .color(.white), lineWidth: 2)

                        // Dim areas outside view region
                        let leftDim = CGRect(x: 0, y: 0, width: regionStartX, height: height)
                        let rightDim = CGRect(x: regionEndX, y: 0, width: width - regionEndX, height: height)
                        context.fill(Path(leftDim), with: .color(.black.opacity(0.3)))
                        context.fill(Path(rightDim), with: .color(.black.opacity(0.3)))
                    }

                    // Draw playhead
                    let playheadX = (viewModel.currentTime / totalDuration) * Double(width)
                    let playheadPath = Path { p in
                        p.move(to: CGPoint(x: playheadX, y: 0))
                        p.addLine(to: CGPoint(x: playheadX, y: height))
                    }
                    context.stroke(playheadPath, with: .color(.red), lineWidth: 1.5)
                }

                // Time labels at edges
                HStack {
                    Text("0:00")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(totalDuration))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 2)
            }
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture { location in
                // Tap to seek
                let tappedTime = (Double(location.x) / Double(width)) * totalDuration
                viewModel.seekTo(time: tappedTime)
            }
        }
    }

    // MARK: - Gap Context Waveform

    private func gapContextWaveform(waveform: WaveformData, gap: DetectedGap) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            // Show 5 seconds of context around the gap
            // REFACTOR NOTE: Using startSeconds/durationSeconds for TimeInterval calculations
            let contextDuration: TimeInterval = 5.0
            let gapCenter = gap.startSeconds + (gap.durationSeconds / 2)
            let viewStart = max(0, gapCenter - contextDuration / 2)
            let viewEnd = min(waveform.duration, gapCenter + contextDuration / 2)
            let viewDuration = viewEnd - viewStart

            ZStack(alignment: .topLeading) {
                // Waveform background
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

                    // Fill waveform
                    context.fill(path, with: .color(.blue.opacity(0.3)))

                    // Draw waveform outline
                    var outlinePath = Path()
                    outlinePath.move(to: CGPoint(x: 0, y: height))
                    for i in 0..<sampleCount {
                        let time = viewStart + (Double(i) / Double(sampleCount)) * viewDuration
                        let amplitude = CGFloat(waveform.amplitude(at: time))
                        let x = CGFloat(i)
                        let y = height - (amplitude * height * 0.85)
                        outlinePath.addLine(to: CGPoint(x: x, y: y))
                    }
                    context.stroke(outlinePath, with: .color(.blue.opacity(0.6)), lineWidth: 1)

                    // Draw ALL gaps in view range (faded)
                    // REFACTOR NOTE: Using startSeconds/endSeconds for pixel calculations
                    for otherGap in viewModel.project.detectedGaps {
                        if otherGap.endSeconds > viewStart && otherGap.startSeconds < viewEnd {
                            let gapStartX = ((otherGap.startSeconds - viewStart) / viewDuration) * Double(width)
                            let gapEndX = ((otherGap.endSeconds - viewStart) / viewDuration) * Double(width)
                            let gapWidth = gapEndX - gapStartX

                            let isCurrentGap = otherGap.id == gap.id
                            let gapColor: Color = isCurrentGap
                                ? (otherGap.removalStatus == .remove || otherGap.removalStatus == .autoRemoved ? .red : .orange)
                                : .gray.opacity(0.3)

                            // Gap rectangle
                            let gapRect = CGRect(x: gapStartX, y: 0, width: max(2, gapWidth), height: height)
                            context.fill(Path(gapRect), with: .color(gapColor.opacity(isCurrentGap ? 0.4 : 0.2)))

                            // Gap borders (only for current gap)
                            if isCurrentGap {
                                let leftLine = Path { p in
                                    p.move(to: CGPoint(x: gapStartX, y: 0))
                                    p.addLine(to: CGPoint(x: gapStartX, y: height))
                                }
                                context.stroke(leftLine, with: .color(gapColor), lineWidth: 2)

                                let rightLine = Path { p in
                                    p.move(to: CGPoint(x: gapEndX, y: 0))
                                    p.addLine(to: CGPoint(x: gapEndX, y: height))
                                }
                                context.stroke(rightLine, with: .color(gapColor), lineWidth: 2)
                            }
                        }
                    }

                    // Draw playhead
                    if viewModel.currentTime >= viewStart && viewModel.currentTime <= viewEnd {
                        let playheadX = ((viewModel.currentTime - viewStart) / viewDuration) * Double(width)
                        let playheadPath = Path { p in
                            p.move(to: CGPoint(x: playheadX, y: 0))
                            p.addLine(to: CGPoint(x: playheadX, y: height))
                        }
                        context.stroke(playheadPath, with: .color(.red), lineWidth: 2)

                        // Playhead circle
                        let circle = CGRect(x: playheadX - 5, y: 0, width: 10, height: 10)
                        context.fill(Path(ellipseIn: circle), with: .color(.red))
                    }
                }

                // Gap label overlay
                VStack {
                    Spacer()
                    HStack {
                        // Gap info
                        // REFACTOR NOTE: Using durationSeconds/startSeconds for display
                        HStack(spacing: 4) {
                            Image(systemName: gap.removalStatus == .remove || gap.removalStatus == .autoRemoved ? "scissors" : "pause.fill")
                                .font(.caption2)
                            Text(String(format: "%.2fs gap", gap.durationSeconds))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(gap.removalStatus == .remove || gap.removalStatus == .autoRemoved ? Color.red : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(6)

                        Spacer()

                        // Time position
                        Text("@ \(formatTime(gap.startSeconds))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    .padding(4)
                }
            }
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 16) {
            // Play/Pause
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            // Current time
            Text(formatTime(viewModel.currentTime))
                .font(.caption)
                .monospacedDigit()

            Spacer()

            // Skip cuts toggle
            Toggle(isOn: $viewModel.skipCutsEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "scissors")
                    Text("Skip Cuts")
                }
                .font(.caption)
            }
            .toggleStyle(.button)
            .tint(viewModel.skipCutsEnabled ? .red : .secondary)

            // Time saved indicator
            if viewModel.skipCutsEnabled {
                Text("-\(formatTime(viewModel.statistics.savedDuration))")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        let stats = viewModel.statistics

        return HStack(spacing: 16) {
            statItem(
                value: "\(stats.totalGaps)",
                label: "Total",
                color: .primary
            )

            statItem(
                value: "\(stats.remainingToReview)",
                label: "To Review",
                color: stats.remainingToReview > 0 ? .orange : .green
            )

            statItem(
                value: String(format: "%.1fs", stats.savedDuration),
                label: "Will Cut",
                color: .red
            )

            Spacer()

            // Batch actions
            Menu {
                Section("Mark All Visible") {
                    Button {
                        viewModel.markAllFiltered(.remove)
                    } label: {
                        Label("Cut All", systemImage: "scissors")
                    }

                    Button {
                        viewModel.markAllFiltered(.keep)
                    } label: {
                        Label("Keep All", systemImage: "checkmark")
                    }
                }

                Divider()

                Button {
                    viewModel.resetToAuto()
                } label: {
                    Label("Reset to Auto", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", filter: .all)
                filterChip("To Review", filter: .needsReview)  // Changed from "Pending"
                filterChip("Will Cut", filter: .willCut)
                filterChip("Will Keep", filter: .willKeep)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(_ title: String, filter: GapFilter) -> some View {
        let isSelected = viewModel.currentFilter == filter
        let count = viewModel.countForFilter(filter)

        return Button {
            viewModel.currentFilter = filter
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text("(\(count))")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color.secondary.opacity(0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("No Gaps to Review")
                .font(.headline)

            Text("All gaps have been reviewed")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                viewModel.currentFilter = .all
            } label: {
                Text("Show All Gaps")
            }
            .buttonStyle(BorderedButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gap List

    private var gapList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.filteredGaps) { gap in
                    GapRowView(
                        gap: gap,
                        actualCutAmount: viewModel.actualCutAmount(for: gap),
                        context: viewModel.getContext(for: gap),
                        isSelected: viewModel.selectedGapId == gap.id,
                        onSelect: {
                            viewModel.selectGap(gap)
                        },
                        onPreview: {
                            viewModel.previewGap(gap)
                        },
                        onStatusChange: { status in
                            viewModel.updateGapStatus(gap, status: status)
                        }
                    )
                    .id(gap.id)
                    .listRowBackground(
                        viewModel.selectedGapId == gap.id
                            ? Color.blue.opacity(0.15)
                            : Color.clear
                    )
                }
            }
            .listStyle(.plain)
            .onChange(of: viewModel.selectedGapId) { _, newId in
                if let id = newId {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            // Video preview toggle
            Button {
                withAnimation {
                    viewModel.showVideoPreview.toggle()
                }
            } label: {
                Label(
                    viewModel.showVideoPreview ? "Hide Preview" : "Show Preview",
                    systemImage: viewModel.showVideoPreview ? "eye.slash" : "eye"
                )
            }
            .buttonStyle(BorderedButtonStyle())

            Spacer()

            // Navigation between gaps
            HStack(spacing: 12) {
                Button {
                    viewModel.selectPreviousGap()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!viewModel.canSelectPrevious)

                Text("\(viewModel.currentGapIndex + 1) of \(viewModel.filteredGaps.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    viewModel.selectNextGap()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!viewModel.canSelectNext)
            }

            Spacer()

            if viewModel.statistics.remainingToReview > 0 {
                Text("\(viewModel.statistics.remainingToReview) to review")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Label("All reviewed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }
}

// MARK: - Gap Row View

struct GapRowView: View {
    let gap: DetectedGap
    let actualCutAmount: TimeInterval  // How much will actually be cut (gap - kept pause)
    let context: (before: String, after: String)
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onStatusChange: (GapRemovalStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: gap duration, actual cut amount, time, status
            // REFACTOR NOTE: Using durationSeconds/startSeconds for display
            HStack {
                // Gap duration badge
                Text(String(format: "%.2fs gap", gap.durationSeconds))
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(durationColor.opacity(0.15))
                    .foregroundColor(durationColor)
                    .cornerRadius(6)

                // Actual cut amount (if different from gap duration)
                if isWillCut && actualCutAmount < gap.durationSeconds {
                    Text(String(format: "→ cut %.2fs", actualCutAmount))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red)
                }

                // Time position
                Text("@ \(formatTime(gap.startSeconds))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Status badge - now shows if it's auto or manual
                statusBadge
            }

            // Context: "...words before" [GAP] "words after..."
            HStack(spacing: 0) {
                if !context.before.isEmpty {
                    Text("...\(context.before)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Gap indicator - show actual cut amount when cutting
                HStack(spacing: 4) {
                    if isWillCut {
                        Image(systemName: "scissors")
                            .font(.caption2)
                        // Show actual cut, not full gap
                        Text(String(format: "-%.1fs", actualCutAmount))
                            .font(.caption2)
                    } else {
                        // Show full gap duration when keeping
                        Text(String(format: "%.1fs", gap.durationSeconds))
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isWillCut ? Color.red.opacity(0.2) : Color.orange.opacity(0.2))
                .foregroundColor(isWillCut ? .red : .orange)
                .cornerRadius(4)

                if !context.after.isEmpty {
                    Text("\(context.after)...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                // Preview button
                Button {
                    onPreview()
                } label: {
                    Label("Preview", systemImage: "play.circle")
                        .font(.subheadline)
                }
                .buttonStyle(BorderedButtonStyle())
                .tint(.blue)

                Spacer()

                // Keep button - emphasize if currently set to cut
                Button {
                    onStatusChange(.keep)
                } label: {
                    Label("Keep", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isKeep ? Color.green : Color.green.opacity(0.2))
                        .foregroundColor(isKeep ? .white : .green)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                // Cut button - emphasize if currently set to keep
                Button {
                    onStatusChange(.remove)
                } label: {
                    Label("Cut", systemImage: "scissors")
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isWillCut ? Color.red : Color.red.opacity(0.2))
                        .foregroundColor(isWillCut ? .white : .red)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var isWillCut: Bool {
        gap.removalStatus == .remove || gap.removalStatus == .autoRemoved
    }

    private var isKeep: Bool {
        gap.removalStatus == .keep || gap.removalStatus == .autoKept
    }

    // REFACTOR NOTE: Using durationSeconds for color calculation
    private var durationColor: Color {
        if gap.durationSeconds < 0.8 {
            return .green
        } else if gap.durationSeconds < 1.5 {
            return .orange
        } else {
            return .red
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            // Show if it's auto-decided
            if gap.removalStatus == .autoRemoved || gap.removalStatus == .autoKept {
                Image(systemName: "sparkles")
                    .font(.caption2)
            }
            Image(systemName: statusIcon)
                .font(.caption2)
            Text(statusText)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .cornerRadius(6)
    }

    private var statusIcon: String {
        switch gap.removalStatus {
        case .pending:
            return "questionmark.circle"
        case .remove, .autoRemoved:
            return "scissors"
        case .keep, .autoKept:
            return "checkmark.circle"
        }
    }

    private var statusText: String {
        switch gap.removalStatus {
        case .pending:
            return "Pending"
        case .autoRemoved:
            return "Auto Cut"
        case .remove:
            return "Cut"
        case .autoKept:
            return "Auto Keep"
        case .keep:
            return "Keep"
        }
    }

    private var statusColor: Color {
        switch gap.removalStatus {
        case .pending:
            return .orange
        case .remove, .autoRemoved:
            return .red
        case .keep, .autoKept:
            return .green
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }
}

// MARK: - Gap Filter

enum GapFilter: CaseIterable {
    case all
    case needsReview  // Changed from "pending" - includes auto-decisions that user might want to override
    case willCut
    case willKeep
}

// MARK: - Gap Review ViewModel

@MainActor
class GapReviewViewModel: ObservableObject {
    @Published var project: VideoProject
    @Published var currentFilter: GapFilter = .all  // Default to ALL so user sees everything
    @Published var showVideoPreview = true
    @Published var selectedGapId: UUID?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var skipCutsEnabled = false  // Default OFF so user can hear gaps

    var player: AVPlayer?
    private var videoURL: URL?
    private var timeObserver: Any?
    private let gapService = GapDetectionService.shared

    var filteredGaps: [DetectedGap] {
        let sorted = project.detectedGaps.sorted { $0.startTime < $1.startTime }
        switch currentFilter {
        case .all:
            return sorted
        case .needsReview:
            // Show pending gaps that need decision
            return sorted.filter { $0.removalStatus == .pending }
        case .willCut:
            return sorted.filter { $0.removalStatus == .remove || $0.removalStatus == .autoRemoved }
        case .willKeep:
            return sorted.filter { $0.removalStatus == .keep || $0.removalStatus == .autoKept }
        }
    }

    var selectedGap: DetectedGap? {
        guard let id = selectedGapId else { return nil }
        return project.detectedGaps.first { $0.id == id }
    }

    var currentGapIndex: Int {
        guard let id = selectedGapId else { return 0 }
        return filteredGaps.firstIndex { $0.id == id } ?? 0
    }

    var canSelectPrevious: Bool {
        currentGapIndex > 0
    }

    var canSelectNext: Bool {
        currentGapIndex < filteredGaps.count - 1
    }

    var statistics: GapStatistics {
        GapStatistics(gaps: project.detectedGaps, targetPauseDuration: project.settings.targetPauseDuration)
    }

    /// Calculate actual cut amount for a gap (accounting for kept pause)
    // REFACTOR NOTE: Using durationSeconds for TimeInterval calculations
    func actualCutAmount(for gap: DetectedGap) -> TimeInterval {
        let targetPause = project.settings.targetPauseDuration
        let keptPause = min(targetPause, gap.durationSeconds)
        return max(0, gap.durationSeconds - keptPause)
    }

    /// Gaps that will be cut (for skip-cuts playback)
    private var cutsToSkip: [DetectedGap] {
        project.detectedGaps.filter {
            $0.removalStatus == .remove || $0.removalStatus == .autoRemoved
        }.sorted { $0.startTime < $1.startTime }
    }

    init(project: VideoProject) {
        self.project = project

        // Auto-select first gap if any
        if let firstGap = project.detectedGaps.sorted(by: { $0.startTime < $1.startTime }).first {
            self.selectedGapId = firstGap.id
        }
    }

    func loadVideo() {
        guard let url = project.resolveVideoURL() else { return }
        _ = url.startAccessingSecurityScopedResource()
        videoURL = url
        player = AVPlayer(url: url)

        // Set up time observer for skip-cuts
        setupTimeObserver()

        // Seek to first gap
        if let firstGap = selectedGap {
            selectGap(firstGap)
        }
    }

    private func setupTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            Task { @MainActor in
                self.currentTime = time.seconds

                // Skip cuts if enabled
                if self.skipCutsEnabled && self.isPlaying {
                    self.checkAndSkipCut(at: time.seconds)
                }
            }
        }
    }

    // REFACTOR NOTE: Using startSeconds/endSeconds for TimeInterval comparisons
    private func checkAndSkipCut(at time: TimeInterval) {
        // Find if we're inside a cut gap
        for gap in cutsToSkip {
            // If we're at the start of a gap, skip to the end
            if time >= gap.startSeconds && time < gap.startSeconds + 0.15 {
                let skipTo = CMTime(seconds: gap.endSeconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                player?.seek(to: skipTo, toleranceBefore: .zero, toleranceAfter: .zero)
                print("Skipped gap: \(formatTime(gap.startSeconds)) -> \(formatTime(gap.endSeconds))")
                break
            }
        }
    }

    func cleanup() {
        player?.pause()
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        player = nil
        videoURL?.stopAccessingSecurityScopedResource()
    }

    func togglePlayback() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func countForFilter(_ filter: GapFilter) -> Int {
        switch filter {
        case .all:
            return project.detectedGaps.count
        case .needsReview:
            return project.detectedGaps.filter { $0.removalStatus == .pending }.count
        case .willCut:
            return project.detectedGaps.filter { $0.removalStatus == .remove || $0.removalStatus == .autoRemoved }.count
        case .willKeep:
            return project.detectedGaps.filter { $0.removalStatus == .keep || $0.removalStatus == .autoKept }.count
        }
    }

    func getContext(for gap: DetectedGap) -> (before: String, after: String) {
        let context = gapService.getGapContext(
            gap: gap,
            words: project.transcribedWords,
            segments: project.speechSegments,
            contextWordCount: 4
        )
        return (
            before: context.before.map(\.text).joined(separator: " "),
            after: context.after.map(\.text).joined(separator: " ")
        )
    }

    // REFACTOR NOTE: Using startSeconds for TimeInterval calculation
    func selectGap(_ gap: DetectedGap) {
        selectedGapId = gap.id

        // Seek to just before the gap
        let seekTime = max(0, gap.startSeconds - 1.0)
        let cmTime = CMTime(seconds: seekTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekTo(time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func selectPreviousGap() {
        guard canSelectPrevious else { return }
        let newIndex = currentGapIndex - 1
        let gap = filteredGaps[newIndex]
        selectGap(gap)
    }

    func selectNextGap() {
        guard canSelectNext else { return }
        let newIndex = currentGapIndex + 1
        let gap = filteredGaps[newIndex]
        selectGap(gap)
    }

    // REFACTOR NOTE: Using startSeconds/durationSeconds for TimeInterval calculations
    func previewGap(_ gap: DetectedGap) {
        guard let player = player else { return }

        selectedGapId = gap.id

        // Temporarily disable skip-cuts for preview
        let wasSkipEnabled = skipCutsEnabled
        skipCutsEnabled = false

        // Seek to 1 second before gap
        let startTime = max(0, gap.startSeconds - 1.0)
        let cmTime = CMTime(seconds: startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        isPlaying = true

        // Stop after gap ends + 1 second
        let previewDuration = (gap.startSeconds - startTime) + gap.durationSeconds + 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + previewDuration) { [weak self] in
            self?.player?.pause()
            self?.isPlaying = false
            self?.skipCutsEnabled = wasSkipEnabled
        }
    }

    func updateGapStatus(_ gap: DetectedGap, status: GapRemovalStatus) {
        if let index = project.detectedGaps.firstIndex(where: { $0.id == gap.id }) {
            // When user manually changes, always use the manual status (not auto)
            project.detectedGaps[index].removalStatus = status
        }
    }

    func markAllFiltered(_ status: GapRemovalStatus) {
        // Mark all currently filtered gaps with the given status
        for gap in filteredGaps {
            if let index = project.detectedGaps.firstIndex(where: { $0.id == gap.id }) {
                project.detectedGaps[index].removalStatus = status
            }
        }
    }

    func markAllPending(_ status: GapRemovalStatus) {
        for i in 0..<project.detectedGaps.count {
            if project.detectedGaps[i].removalStatus == .pending {
                project.detectedGaps[i].removalStatus = status
            }
        }
    }

    // REFACTOR NOTE: Using CodableCMTime.zero as default
    func resetToAuto() {
        let newGaps = gapService.detectGaps(
            in: project.speechSegments,
            settings: project.settings,
            videoDuration: project.videoDuration ?? .zero
        )
        project.detectedGaps = newGaps
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }

    func saveAndExit() {
        // Update status based on review progress
        let pending = statistics.pendingCount
        if pending == 0 {
            project.status = .reviewing
        }

        // Save to storage
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

    // MARK: - Debug

    func copyGapReviewDebugReport() {
        let targetPause = project.settings.targetPauseDuration

        var report = """
        ════════════════════════════════════════════════════════════════
        GAP REVIEW DEBUG REPORT
        Generated: \(Date())
        ════════════════════════════════════════════════════════════════

        PROJECT: \(project.name)
        VIDEO DURATION: \(formatTimeMs(project.videoDurationSeconds ?? 0))
        CURRENT GAP INDEX: \(currentGapIndex + 1) of \(filteredGaps.count)

        ════════════════════════════════════════════════════════════════
        SETTINGS
        ════════════════════════════════════════════════════════════════
        Target pause duration: \(String(format: "%.3f", targetPause))s
        Filter mode: \(filterDescription(currentFilter))

        ════════════════════════════════════════════════════════════════
        CURRENT GAP DETAILS
        ════════════════════════════════════════════════════════════════

        """

        if let gap = selectedGap {
            let cut = calculateActualCutDebug(gap: gap, targetPause: targetPause)
            let willCut = gap.removalStatus == .remove || gap.removalStatus == .autoRemoved

            // REFACTOR NOTE: Using startSeconds/endSeconds/durationSeconds for debug output
            report += """
            Gap: \(formatTimeMs(gap.startSeconds)) - \(formatTimeMs(gap.endSeconds))
            Duration: \(String(format: "%.3f", gap.durationSeconds))s
            Status: \(gap.removalStatus.displayName)
            Will be cut: \(willCut ? "YES" : "NO")

            CUT CALCULATION (centered pause):
              Gap start: \(formatTimeMs(gap.startSeconds))
              Gap end: \(formatTimeMs(gap.endSeconds))
              Gap duration: \(String(format: "%.3f", gap.durationSeconds))s
              Target pause: \(String(format: "%.3f", targetPause))s
              Half keep (each side): \(String(format: "%.3f", cut.halfKeep))s
              Actual cut start: \(formatTimeMs(cut.cutStart))
              Actual cut end: \(formatTimeMs(cut.cutEnd))
              Time to remove: \(String(format: "%.3f", cut.cutEnd - cut.cutStart))s

            WHAT SHOULD BE SHOWN IN WAVEFORM:
              View range should be: ~\(formatTimeMs(gap.startSeconds - 2.0)) to ~\(formatTimeMs(gap.endSeconds + 2.0))
              Gap highlight: \(formatTimeMs(gap.startSeconds)) - \(formatTimeMs(gap.endSeconds))
              Cut region (if removing): \(formatTimeMs(cut.cutStart)) - \(formatTimeMs(cut.cutEnd))

            """
        } else {
            report += "No current gap selected.\n"
        }

        report += """

        ════════════════════════════════════════════════════════════════
        ALL GAPS IN PROJECT (\(project.detectedGaps.count) total)
        ════════════════════════════════════════════════════════════════

        """

        // Note: CodableCMTime comparison works for sorting
        let sortedGaps = project.detectedGaps.sorted { $0.startTime < $1.startTime }
        for (index, gap) in sortedGaps.enumerated() {
            let isCurrent = gap.id == selectedGap?.id
            let marker = isCurrent ? ">>> " : "    "
            report += "\(marker)[\(index + 1)] \(formatTimeMs(gap.startSeconds)) - \(formatTimeMs(gap.endSeconds)) (\(String(format: "%.2f", gap.durationSeconds))s) - \(gap.removalStatus.displayName)\n"
        }

        report += """

        ════════════════════════════════════════════════════════════════
        FILTERED GAPS (current view: \(filteredGaps.count) gaps)
        ════════════════════════════════════════════════════════════════

        """

        for (index, gap) in filteredGaps.enumerated() {
            let isCurrent = index == currentGapIndex
            let marker = isCurrent ? ">>> " : "    "
            report += "\(marker)[\(index + 1)] \(formatTimeMs(gap.startSeconds)) - \(formatTimeMs(gap.endSeconds)) (\(String(format: "%.2f", gap.durationSeconds))s) - \(gap.removalStatus.displayName)\n"
        }

        report += """

        ════════════════════════════════════════════════════════════════
        STATISTICS
        ════════════════════════════════════════════════════════════════
        Total gaps: \(statistics.totalGaps)
        Pending: \(statistics.pendingCount)
        Manual removed: \(statistics.manualRemovedCount)
        Manual kept: \(statistics.manualKeptCount)
        Auto-removed: \(statistics.autoRemovedCount)
        Auto-kept: \(statistics.autoKeptCount)
        Saved duration: \(String(format: "%.3f", statistics.savedDuration))s

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

        print("📋 Gap review debug report copied to clipboard (\(report.count) characters)")
    }

    // REFACTOR NOTE: Using startSeconds/endSeconds/durationSeconds for TimeInterval calculations
    private func calculateActualCutDebug(gap: DetectedGap, targetPause: TimeInterval) -> (halfKeep: TimeInterval, cutStart: TimeInterval, cutEnd: TimeInterval) {
        let halfKeep = min(targetPause / 2.0, gap.durationSeconds / 2.0)
        let cutStart = gap.startSeconds + halfKeep
        let cutEnd = gap.endSeconds - halfKeep
        return (halfKeep, cutStart, cutEnd)
    }

    private func formatTimeMs(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, ms)
    }

    private func filterDescription(_ filter: GapFilter) -> String {
        switch filter {
        case .all: return "ALL"
        case .needsReview: return "NEEDS_REVIEW"
        case .willCut: return "WILL_CUT"
        case .willKeep: return "WILL_KEEP"
        }
    }
}
