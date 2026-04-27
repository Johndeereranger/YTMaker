//
//  MoveEditorView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Stage 2 Move Editor - Apply zoom/pan moves to the simplified timeline.
//
//  Layout (4 panels):
//  ┌────────────────────────────────────────────────────────────────────────────┐
//  │ [Moves List] │ [Video Preview with Effects] │ [Move Buttons] │ [Detail]   │
//  │              │                              │                │            │
//  │ - Move 1     │  ┌────────────────────────┐  │ ZOOM IN        │ Start:     │
//  │ - Move 2     │  │   Video + Transform    │  │ [Inst][Med]    │ [slider]   │
//  │ - Move 3     │  │   Overlay showing      │  │                │            │
//  │              │  │   current zoom/pan     │  │ ZOOM OUT       │ Duration:  │
//  │              │  └────────────────────────┘  │ [Inst][Med]    │ [slider]   │
//  │              │  [Timeline with playhead]    │                │            │
//  └────────────────────────────────────────────────────────────────────────────┘
//

import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Move Editor View

struct MoveEditorView: View {
    @StateObject private var viewModel: MoveEditorViewModel
    @State private var showingStyleEditor = false

    init(project: VideoProject) {
        _viewModel = StateObject(wrappedValue: MoveEditorViewModel(project: project))
    }

    var body: some View {
        #if os(macOS)
        HSplitView {
            // Left: Applied moves list
            appliedMovesList
                .frame(minWidth: 160, maxWidth: 220)

            // Center: Video + Timeline
            centerContent

            // Right side: Move buttons + Detail editor
            rightPanel
        }
        .navigationTitle("Move Editor - \(viewModel.project.name)")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingStyleEditor) {
            styleEditorSheet
        }
        #else
        // iOS: Simplified layout
        HStack(spacing: 0) {
            appliedMovesList
                .frame(width: 180)
            centerContent
            rightPanel
        }
        .navigationTitle("Move Editor")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingStyleEditor) {
            styleEditorSheet
        }
        #endif
    }

    // MARK: - Right Panel (Buttons + Detail)

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Move buttons (top)
            MoveButtonGrid(
                selectedMovePreset: $viewModel.selectedMovePreset,
                projectStyle: viewModel.projectStyle,
                onMoveSelected: { preset in
                    viewModel.applyMove(preset)
                }
            )
            .frame(maxHeight: 350)

            Divider()

            // Detail editor (bottom) - shows when move selected
            if let selectedMove = viewModel.selectedAppliedMove {
                MoveDetailEditor(viewModel: viewModel, move: selectedMove)
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("Select a move to edit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.platformControlBackground)
            }
        }
        .frame(minWidth: 250, maxWidth: 300)
    }

    // MARK: - Applied Moves List (Left Sidebar)

    private var appliedMovesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Moves")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.sortedMoves.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Moves list
            if viewModel.sortedMoves.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No moves yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Position playhead and click a move button")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.sortedMoves) { move in
                            AppliedMoveRow(
                                move: move,
                                isSelected: viewModel.selectedAppliedMove?.id == move.id,
                                onSelect: { viewModel.selectMove(move) },
                                onDelete: { viewModel.removeMove(move) }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color.platformControlBackground)
    }

    // MARK: - Center Content (Video + Controls + Timeline)

    private var centerContent: some View {
        VStack(spacing: 0) {
            // Video preview with transform overlay
            videoPreviewWithEffects
                .frame(minHeight: 200)

            Divider()

            // Playback controls
            playbackControls

            Divider()

            // Timeline
            SimplifiedTimelineView(viewModel: viewModel)
        }
        .frame(minWidth: 500)
    }

    // MARK: - Video Preview with Effects

    private var videoPreviewWithEffects: some View {
        GeometryReader { geometry in
            let state = currentTransformState
            let frameWidth = geometry.size.width
            let frameHeight = geometry.size.height

            ZStack {
                // Base video with transforms applied
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .disabled(true) // Disable built-in controls
                        // Apply scale (zoom)
                        .scaleEffect(state.zoomScale)
                        // Apply position offset (convert percentage to points)
                        .offset(
                            x: frameWidth * state.positionX / 100,
                            y: frameHeight * state.positionY / 100
                        )
                } else {
                    Color.black
                    VStack(spacing: 8) {
                        Image(systemName: "film")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                        Text("No video loaded")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                // Transform indicator overlay (always show current state)
                VStack {
                    HStack {
                        Spacer()
                        transformIndicator(state: state)
                            .padding(8)
                    }
                    Spacer()
                }
            }
            .clipped()
        }
        .background(Color.black)
    }

    /// Get the current transform state based on all moves and current time
    private var currentTransformState: VideoTransformState {
        VideoTransformState.at(
            time: viewModel.currentTime.seconds,
            moves: viewModel.project.appliedMoves,
            projectStyle: viewModel.projectStyle
        )
    }

    /// Transform indicator showing current zoom and position
    private func transformIndicator(state: VideoTransformState) -> some View {
        HStack(spacing: 8) {
            // Zoom indicator
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                Text(String(format: "%.0f%%", state.zoomScale * 100))
                    .font(.system(size: 11, design: .monospaced))
            }

            // Position indicator (only show if not centered)
            if abs(state.positionX) > 0.1 || abs(state.positionY) > 0.1 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                    Text(String(format: "%.1f, %.1f", state.positionX, state.positionY))
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.7))
        .cornerRadius(4)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 16) {
            // Current time
            Text(formatTime(viewModel.currentTime.seconds))
                .font(.system(.body, design: .monospaced))
                .frame(width: 80)

            Spacer()

            // Step backward
            Button(action: { viewModel.seekToSeconds(viewModel.currentTime.seconds - 1.0/30.0) }) {
                Image(systemName: "backward.frame")
            }
            .buttonStyle(.plain)
            .help("Previous frame")

            // Play/Pause
            Button(action: viewModel.togglePlayPause) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .keyboardShortcut(.space, modifiers: [])
            #endif

            // Step forward
            Button(action: { viewModel.seekToSeconds(viewModel.currentTime.seconds + 1.0/30.0) }) {
                Image(systemName: "forward.frame")
            }
            .buttonStyle(.plain)
            .help("Next frame")

            Spacer()

            // Total duration
            Text(formatTime(viewModel.simplifiedDurationSeconds))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.platformControlBackground)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button(action: {
                showingStyleEditor = true
            }) {
                Label("Zoom Levels", systemImage: "slider.horizontal.3")
            }
            .help("Configure zoom percentages for this project")
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                // TODO: Export FCPXML with moves
            }) {
                Label("Export FCPXML", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Style Editor Sheet

    private var styleEditorSheet: some View {
        ProjectStyleEditor(projectStyle: projectStyleBinding)
    }

    /// Binding for projectStyle (since it's a computed property on the ViewModel)
    private var projectStyleBinding: Binding<ProjectStyle> {
        Binding(
            get: { viewModel.projectStyle },
            set: { viewModel.projectStyle = $0 }
        )
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }
}

// MARK: - Applied Move Row

struct AppliedMoveRow: View {
    let move: AppliedMove
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Icon for move type
                Image(systemName: iconForMove)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : colorForMove)
                    .frame(width: 20)

                // Time info
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTime(move.startSeconds))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .primary)
                    Text(String(format: "%.2fs", move.durationSeconds))
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                }

                Spacer()

                // Delete button (visible on hover or selection)
                if isHovering || isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : (isHovering ? Color.secondary.opacity(0.1) : Color.clear))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var iconForMove: String {
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

    private var colorForMove: Color {
        switch move.moveType {
        case .zoomIn, .zoomOut:
            return .orange
        case .positionLeft, .positionRight, .positionUp, .positionDown:
            return .blue
        case .positionCenter:
            return .green
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }
}

// MARK: - Preview

#if DEBUG
struct MoveEditorView_Previews: PreviewProvider {
    static var previews: some View {
        MoveEditorView(project: VideoProject(name: "Preview Project"))
            .frame(width: 1200, height: 700)
    }
}
#endif
