//
//  SimplifiedTimelineView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Complete rewrite for proper timeline functionality.
//

import SwiftUI
import CoreMedia

// MARK: - Simplified Timeline View

struct SimplifiedTimelineView: View {
    @ObservedObject var viewModel: MoveEditorViewModel

    // Layout constants
    private let rulerHeight: CGFloat = 28
    private let trackHeight: CGFloat = 60
    private let markerLaneHeight: CGFloat = 50
    private let playheadWidth: CGFloat = 2

    // Drag states
    @State private var isDraggingPlayhead = false
    @State private var draggingMoveId: UUID? = nil
    @State private var dragMoveOffset: CGFloat = 0

    // Scroll tracking
    @State private var scrollOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 500

    // Computed
    private var totalHeight: CGFloat {
        rulerHeight + trackHeight + markerLaneHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main timeline area
            GeometryReader { geometry in
                let geoWidth = geometry.size.width

                ZStack(alignment: .topLeading) {
                    // Scrollable content
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: true) {
                            ZStack(alignment: .topLeading) {
                                // Content width anchor
                                Color.clear
                                    .frame(width: contentWidth(for: geoWidth), height: totalHeight)

                                // Layers
                                VStack(spacing: 0) {
                                    // Time ruler
                                    timeRuler(width: contentWidth(for: geoWidth))

                                    // Track background + speech segments
                                    trackLayer(width: contentWidth(for: geoWidth))

                                    // Marker lane for applied moves
                                    markerLane(width: contentWidth(for: geoWidth))
                                }

                                // Playhead (spans full height, on top)
                                playhead(height: totalHeight)
                                    .id("playhead")
                            }
                            .background(
                                GeometryReader { inner in
                                    Color.clear.preference(
                                        key: ScrollOffsetKey.self,
                                        value: inner.frame(in: .named("scroll")).minX
                                    )
                                }
                            )
                            // Tap anywhere to seek
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if !isDraggingPlayhead && draggingMoveId == nil {
                                            // Scrub while dragging on empty area
                                            seekTo(x: value.location.x)
                                        }
                                    }
                                    .onEnded { value in
                                        if !isDraggingPlayhead && draggingMoveId == nil {
                                            seekTo(x: value.location.x)
                                        }
                                    }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(ScrollOffsetKey.self) { value in
                            scrollOffset = -value
                        }
                        .onChange(of: viewModel.currentTime) { _, _ in
                            // Auto-scroll to keep playhead visible when playing
                            if viewModel.isPlaying {
                                autoScrollIfNeeded(proxy: scrollProxy, containerWidth: geoWidth)
                            }
                        }
                    }
                }
                .onAppear {
                    containerWidth = geoWidth
                    // Auto-fit on first load
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewModel.fitToWidth(geoWidth)
                    }
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    containerWidth = newWidth
                }
            }
            .frame(height: totalHeight)
            .background(Color.platformTextBackground)
            .clipped()

            // Zoom controls bar
            zoomControlsBar
        }
    }

    // MARK: - Content Width

    private func contentWidth(for containerWidth: CGFloat) -> CGFloat {
        let computed = CGFloat(viewModel.simplifiedDurationSeconds * viewModel.pixelsPerSecond)
        // Always at least fill the container
        return max(containerWidth, computed)
    }

    // MARK: - Time Ruler

    private func timeRuler(width: CGFloat) -> some View {
        Canvas { context, size in
            let duration = viewModel.simplifiedDurationSeconds
            guard duration > 0 else { return }

            let pps = viewModel.pixelsPerSecond
            let tickInterval = calculateTickInterval(pps: pps)
            let majorInterval = calculateMajorInterval(pps: pps)

            var time = 0.0
            while time <= duration {
                let x = time * pps
                let isMajor = time.truncatingRemainder(dividingBy: majorInterval) < 0.001

                // Tick line
                let tickHeight: CGFloat = isMajor ? 12 : 6
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height - tickHeight))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)

                // Label for major ticks
                if isMajor && x > 5 {
                    let label = formatTimeRuler(time)
                    let text = Text(label).font(.system(size: 10)).foregroundColor(.secondary)
                    context.draw(text, at: CGPoint(x: x, y: 10))
                }

                time += tickInterval
            }
        }
        .frame(width: width, height: rulerHeight)
        .background(Color.platformControlBackground)
    }

    // MARK: - Track Layer

    private func trackLayer(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Background
            Rectangle()
                .fill(Color.platformControlBackground.opacity(0.3))

            // Speech segments visualization
            ForEach(viewModel.project.speechSegments) { segment in
                let startX = viewModel.xPosition(for: segment.startTime)
                let endX = viewModel.xPosition(for: segment.endTime)
                let segWidth = max(2, endX - startX)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue.opacity(0.4))
                    .frame(width: segWidth, height: trackHeight - 8)
                    .offset(x: startX, y: 4)
            }
        }
        .frame(width: width, height: trackHeight)
    }

    // MARK: - Marker Lane (Applied Moves)

    private func markerLane(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Background
            Rectangle()
                .fill(Color.platformControlBackground.opacity(0.5))

            // Divider line at top
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)

            // Move markers
            ForEach(viewModel.sortedMoves) { move in
                moveMarker(for: move)
            }
        }
        .frame(width: width, height: markerLaneHeight)
    }

    private func moveMarker(for move: AppliedMove) -> some View {
        let isSelected = viewModel.selectedAppliedMove?.id == move.id
        let isDragging = draggingMoveId == move.id

        let baseX = viewModel.xPosition(for: move.startTime)
        let xPos = isDragging ? baseX + dragMoveOffset : baseX
        let markerWidth = max(24, CGFloat(move.durationSeconds * viewModel.pixelsPerSecond))

        return VStack(spacing: 2) {
            // Marker head
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor : markerColor(for: move))
                .frame(width: markerWidth, height: 28)
                .overlay(
                    Image(systemName: markerIcon(for: move))
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // Stem
            Rectangle()
                .fill(isSelected ? Color.accentColor : markerColor(for: move))
                .frame(width: 2, height: markerLaneHeight - 34)
        }
        .offset(x: xPos - markerWidth / 2, y: 4)
        .gesture(
            DragGesture()
                .onChanged { value in
                    draggingMoveId = move.id
                    dragMoveOffset = value.translation.width
                }
                .onEnded { value in
                    let newX = baseX + value.translation.width
                    let newTime = viewModel.time(for: newX)
                    viewModel.updateMovePosition(move, to: newTime)
                    draggingMoveId = nil
                    dragMoveOffset = 0
                }
        )
        .onTapGesture {
            viewModel.selectMove(move)
        }
    }

    /// Get the appropriate icon for a move type
    private func markerIcon(for move: AppliedMove) -> String {
        switch move.moveType {
        case .zoomIn:
            return "plus.magnifyingglass"
        case .zoomOut:
            return "minus.magnifyingglass"
        case .positionLeft:
            return "arrow.left"
        case .positionRight:
            return "arrow.right"
        case .positionUp:
            return "arrow.up"
        case .positionDown:
            return "arrow.down"
        case .positionCenter:
            return "circle.circle"
        }
    }

    /// Get the appropriate color for a move type
    private func markerColor(for move: AppliedMove) -> Color {
        switch move.moveType {
        case .zoomIn, .zoomOut:
            return .orange
        case .positionLeft, .positionRight, .positionUp, .positionDown:
            return .blue
        case .positionCenter:
            return .green
        }
    }

    // MARK: - Playhead

    private func playhead(height: CGFloat) -> some View {
        let xPos = viewModel.xPosition(for: viewModel.currentTime)

        return ZStack(alignment: .top) {
            // Main line
            Rectangle()
                .fill(Color.red)
                .frame(width: playheadWidth, height: height)

            // Draggable head
            PlayheadHandle()
                .fill(Color.red)
                .frame(width: 16, height: 20)
                .offset(y: -2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDraggingPlayhead = true
                            let newX = xPos + value.translation.width
                            seekTo(x: newX)
                        }
                        .onEnded { _ in
                            isDraggingPlayhead = false
                        }
                )
        }
        .offset(x: xPos - playheadWidth / 2)
        .allowsHitTesting(true)
    }

    // MARK: - Zoom Controls Bar

    private var zoomControlsBar: some View {
        HStack(spacing: 12) {
            // Zoom out
            Button(action: { zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            // Zoom level indicator
            Text(zoomLevelText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70)

            // Zoom in
            Button(action: { zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            // Fit button
            Button(action: { fitToView() }) {
                Text("Fit")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.platformControl)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Spacer()

            // Current time display
            Text(formatTime(viewModel.currentTime.seconds))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)

            Text("/")
                .foregroundColor(.secondary)

            Text(formatTime(viewModel.simplifiedDurationSeconds))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.platformControlBackground)
    }

    private var zoomLevelText: String {
        let pps = viewModel.pixelsPerSecond
        if pps >= 100 {
            return "\(Int(pps))px/s"
        } else if pps >= 10 {
            return String(format: "%.1fpx/s", pps)
        } else {
            return String(format: "%.2fpx/s", pps)
        }
    }

    // MARK: - Actions

    private func seekTo(x: CGFloat) {
        let newTime = viewModel.time(for: x)
        viewModel.seek(to: newTime)
    }

    private func zoomIn() {
        // Zoom anchored on playhead
        let playheadX = viewModel.xPosition(for: viewModel.currentTime)
        let playheadRatio = playheadX / contentWidth(for: containerWidth)

        viewModel.zoomIn()

        // Adjust scroll to keep playhead at same relative position
        // This would need ScrollViewReader to work properly
    }

    private func zoomOut() {
        viewModel.zoomOut()
    }

    private func fitToView() {
        viewModel.fitToWidth(containerWidth)
    }

    private func autoScrollIfNeeded(proxy: ScrollViewProxy, containerWidth: CGFloat) {
        let playheadX = viewModel.xPosition(for: viewModel.currentTime)
        let visibleStart = scrollOffset
        let visibleEnd = scrollOffset + containerWidth

        // If playhead is outside visible area, scroll to it
        if playheadX < visibleStart + 50 || playheadX > visibleEnd - 50 {
            // Scroll to put playhead at 1/3 from left
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("playhead", anchor: .leading)
            }
        }
    }

    // MARK: - Helpers

    private func calculateTickInterval(pps: Double) -> Double {
        // Adjust tick spacing based on zoom level
        if pps >= 100 { return 0.5 }
        if pps >= 50 { return 1.0 }
        if pps >= 20 { return 2.0 }
        if pps >= 10 { return 5.0 }
        return 10.0
    }

    private func calculateMajorInterval(pps: Double) -> Double {
        if pps >= 100 { return 5.0 }
        if pps >= 50 { return 10.0 }
        if pps >= 20 { return 30.0 }
        if pps >= 10 { return 60.0 }
        return 60.0
    }

    private func formatTimeRuler(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "\(secs)s"
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }
}

// MARK: - Playhead Handle Shape

struct PlayheadHandle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Pentagon shape pointing down
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

#if DEBUG
struct SimplifiedTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        SimplifiedTimelineView(viewModel: MoveEditorViewModel.preview)
            .frame(height: 200)
    }
}
#endif
