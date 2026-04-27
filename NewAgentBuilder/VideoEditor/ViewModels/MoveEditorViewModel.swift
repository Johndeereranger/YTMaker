//
//  MoveEditorViewModel.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  ViewModel for Stage 2 Move Editor - applying zoom/pan moves to the simplified timeline.
//

import Foundation
import CoreMedia
import AVFoundation
import Combine

// MARK: - Move Editor ViewModel

@MainActor
class MoveEditorViewModel: ObservableObject {
    // MARK: - Published State

    /// The video project being edited
    @Published var project: VideoProject

    /// Current playhead position
    @Published var currentTime: CodableCMTime = .zero

    /// Whether video is playing
    @Published var isPlaying: Bool = false

    /// Currently selected applied move (for editing/deletion)
    @Published var selectedAppliedMove: AppliedMove?

    /// Currently selected move preset (from button grid)
    @Published var selectedMovePreset: MovePreset?

    /// Move being dragged (for repositioning)
    @Published var draggingMove: AppliedMove?

    /// Timeline zoom level (pixels per second) - start zoomed out to see full timeline
    @Published var pixelsPerSecond: Double = 15.0

    // MARK: - Computed Properties

    /// Project style for zoom level percentages - uses the project's style
    var projectStyle: ProjectStyle {
        get { project.projectStyle }
        set {
            project.projectStyle = newValue
            saveProject()
        }
    }

    /// All applied moves sorted by time
    var sortedMoves: [AppliedMove] {
        project.appliedMoves.sortedByTime
    }

    /// Video duration in seconds
    var videoDurationSeconds: Double {
        project.videoDuration?.seconds ?? 0
    }

    /// The "simplified" duration after cuts are applied
    /// This calculates the final timeline duration with gaps removed
    var simplifiedDurationSeconds: Double {
        guard let totalDuration = project.videoDuration?.seconds else { return 0 }

        // Sum up all the cuts that will be removed
        let totalCutDuration = project.detectedGaps
            .filter { shouldCut($0) }
            .reduce(0.0) { sum, gap in
                sum + project.settings.amountToCut(fromSeconds: gap.durationSeconds)
            }

        return max(0, totalDuration - totalCutDuration)
    }

    /// Timeline width in points based on duration and zoom
    var timelineWidth: CGFloat {
        CGFloat(simplifiedDurationSeconds * pixelsPerSecond)
    }

    // MARK: - Player

    /// The AVPlayer instance - exposed for the view to display
    @Published private(set) var player: AVPlayer?
    private var playerObserver: Any?
    /// Non-isolated reference for cleanup in deinit
    private var playerForCleanup: AVPlayer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(project: VideoProject) {
        self.project = project
        setupPlayer()
    }

    deinit {
        if let observer = playerObserver {
            playerForCleanup?.removeTimeObserver(observer)
        }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        guard let url = project.resolveVideoURL() else { return }

        // Start security-scoped access
        _ = url.startAccessingSecurityScopedResource()

        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        playerForCleanup = newPlayer  // Keep non-isolated reference for deinit

        // Observe playback time
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        playerObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CodableCMTime(time)
            }
        }
    }

    // MARK: - Playback Controls

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: CodableCMTime) {
        player?.seek(to: time.time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func seekToSeconds(_ seconds: Double) {
        seek(to: CodableCMTime(seconds: seconds))
    }

    // MARK: - Move Management

    /// Apply a move at the current playhead position
    func applyMove(_ preset: MovePreset) {
        let appliedMove = AppliedMove.from(preset, at: currentTime)
        project.appliedMoves.append(appliedMove)
        selectedAppliedMove = appliedMove
        saveProject()
    }

    /// Remove an applied move
    func removeMove(_ move: AppliedMove) {
        project.appliedMoves.removeAll { $0.id == move.id }
        if selectedAppliedMove?.id == move.id {
            selectedAppliedMove = nil
        }
        saveProject()
    }

    /// Update an applied move's position
    func updateMovePosition(_ move: AppliedMove, to newTime: CodableCMTime) {
        guard let index = project.appliedMoves.firstIndex(where: { $0.id == move.id }) else {
            return
        }

        // Clamp to valid range
        let clampedSeconds = max(0, min(simplifiedDurationSeconds, newTime.seconds))
        project.appliedMoves[index].startTime = CodableCMTime(seconds: clampedSeconds)

        // Update selected move reference if this is the selected one
        if selectedAppliedMove?.id == move.id {
            selectedAppliedMove = project.appliedMoves[index]
        }
        saveProject()
    }

    /// Update an applied move's duration
    func updateMoveDuration(_ move: AppliedMove, to newDuration: Double) {
        guard let index = project.appliedMoves.firstIndex(where: { $0.id == move.id }) else {
            return
        }

        // Clamp duration to reasonable range
        let clampedDuration = max(0.03, min(10.0, newDuration))
        project.appliedMoves[index].durationOverride = CodableCMTime(seconds: clampedDuration)

        // Update selected move reference if this is the selected one
        if selectedAppliedMove?.id == move.id {
            selectedAppliedMove = project.appliedMoves[index]
        }
        saveProject()
    }

    /// Select a move
    func selectMove(_ move: AppliedMove?) {
        selectedAppliedMove = move
        if let move = move {
            // Seek to the move's start time
            seek(to: move.startTime)
        }
    }

    /// Delete selected move
    func deleteSelectedMove() {
        if let move = selectedAppliedMove {
            removeMove(move)
        }
    }

    // MARK: - Timeline Helpers

    /// Convert time to X position on timeline
    func xPosition(for time: CodableCMTime) -> CGFloat {
        // For now, use simplified time directly
        // TODO: Account for collapsed cuts when calculating position
        return CGFloat(time.seconds * pixelsPerSecond)
    }

    /// Convert X position to time
    func time(for xPosition: CGFloat) -> CodableCMTime {
        let seconds = Double(xPosition) / pixelsPerSecond
        let clampedSeconds = max(0, min(simplifiedDurationSeconds, seconds))
        return CodableCMTime(seconds: clampedSeconds)
    }

    /// Get the preset for an applied move
    func preset(for move: AppliedMove) -> MovePreset? {
        // In a real implementation, this would look up from a preset library
        // For now, we create a placeholder
        nil
    }

    // MARK: - Gap Helpers

    /// Whether a gap should be cut (based on removal status)
    private func shouldCut(_ gap: DetectedGap) -> Bool {
        switch gap.removalStatus {
        case .remove, .autoRemoved:
            return true
        case .keep, .autoKept, .pending:
            return false
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        pixelsPerSecond = min(200, pixelsPerSecond * 1.5)
    }

    func zoomOut() {
        pixelsPerSecond = max(5, pixelsPerSecond / 1.5)
    }

    /// Fit the entire timeline to a given width
    func fitToWidth(_ availableWidth: CGFloat) {
        guard simplifiedDurationSeconds > 0 else { return }
        // Leave some padding
        let targetWidth = availableWidth - 40
        pixelsPerSecond = max(5, Double(targetWidth) / simplifiedDurationSeconds)
    }

    // MARK: - Persistence

    private func saveProject() {
        project.updatedAt = Date()

        // Save directly to UserDefaults (matching VideoEditorProjectView pattern)
        if let data = UserDefaults.standard.data(forKey: "VideoEditorProjects"),
           var projects = try? JSONDecoder().decode([VideoProject].self, from: data) {
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
                if let encoded = try? JSONEncoder().encode(projects) {
                    UserDefaults.standard.set(encoded, forKey: "VideoEditorProjects")
                    print("Saved project with \(project.appliedMoves.count) moves")
                }
            }
        }
    }
}

// MARK: - Preview Helper

extension MoveEditorViewModel {
    static var preview: MoveEditorViewModel {
        let project = VideoProject(name: "Preview Project")
        return MoveEditorViewModel(project: project)
    }
}
