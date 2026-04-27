//
//  GapDetectionService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//
//  REFACTORED 2026-02-03: Changed from TimeInterval to CMTime for frame-accurate timing.
//

import Foundation
import CoreMedia

// MARK: - Gap Detection Service

class GapDetectionService {
    static let shared = GapDetectionService()

    private init() {}

    /// Detect gaps between speech segments
    /// - Parameters:
    ///   - segments: Speech segments from transcription
    ///   - settings: Project settings for thresholds
    ///   - videoDuration: Total video duration
    /// - Returns: Array of detected gaps with auto-classification
    // REFACTOR NOTE: Changed videoDuration from TimeInterval to CodableCMTime
    // OLD CODE (commented for debug reference):
    // func detectGaps(in segments: [SpeechSegment], settings: ProjectSettings, videoDuration: TimeInterval) -> [DetectedGap]
    func detectGaps(
        in segments: [SpeechSegment],
        settings: ProjectSettings,
        videoDuration: CodableCMTime
    ) -> [DetectedGap] {

        guard !segments.isEmpty else { return [] }

        // Sort segments by start time
        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }

        var gaps: [DetectedGap] = []
        let minimumGap = settings.minimumGapDurationCMTime

        // Check for gap at the beginning (before first speech)
        if let firstSegment = sortedSegments.first, firstSegment.startTime > minimumGap {
            let gap = DetectedGap(
                startTime: .zero,
                endTime: firstSegment.startTime,
                precedingSegmentId: nil,
                followingSegmentId: firstSegment.id,
                removalStatus: classifyGap(
                    duration: firstSegment.startTime,
                    settings: settings,
                    isEdge: true
                )
            )
            gaps.append(gap)
        }

        // Find gaps between segments
        for i in 0..<(sortedSegments.count - 1) {
            let currentSegment = sortedSegments[i]
            let nextSegment = sortedSegments[i + 1]

            let gapStart = currentSegment.endTime
            let gapEnd = nextSegment.startTime
            let gapDuration = gapEnd - gapStart

            // Only create gap if it's significant
            if gapDuration >= minimumGap {
                let gap = DetectedGap(
                    startTime: gapStart,
                    endTime: gapEnd,
                    precedingSegmentId: currentSegment.id,
                    followingSegmentId: nextSegment.id,
                    removalStatus: classifyGap(
                        duration: gapDuration,
                        settings: settings,
                        isEdge: false
                    )
                )
                gaps.append(gap)
            }
        }

        // Check for gap at the end (after last speech)
        if let lastSegment = sortedSegments.last {
            let gapDuration = videoDuration - lastSegment.endTime
            if gapDuration > minimumGap {
                let gap = DetectedGap(
                    startTime: lastSegment.endTime,
                    endTime: videoDuration,
                    precedingSegmentId: lastSegment.id,
                    followingSegmentId: nil,
                    removalStatus: classifyGap(
                        duration: gapDuration,
                        settings: settings,
                        isEdge: true
                    )
                )
                gaps.append(gap)
            }
        }

        print("🔍 Detected \(gaps.count) gaps")
        printGapSummary(gaps)

        return gaps
    }

    /// Classify a gap based on its duration
    /// - Parameters:
    ///   - duration: Gap duration
    ///   - settings: Project settings for thresholds
    ///   - isEdge: Whether this is at the start/end of video
    /// - Returns: Appropriate removal status
    // REFACTOR NOTE: Changed duration from TimeInterval to CodableCMTime
    // OLD CODE (commented for debug reference):
    // private func classifyGap(duration: TimeInterval, settings: ProjectSettings, isEdge: Bool) -> GapRemovalStatus
    private func classifyGap(
        duration: CodableCMTime,
        settings: ProjectSettings,
        isEdge: Bool
    ) -> GapRemovalStatus {

        let durationSeconds = duration.seconds

        // Edge gaps (start/end of video) are usually auto-removed
        if isEdge {
            return .autoRemoved
        }

        // Very short gaps are natural speech pauses - keep them
        if durationSeconds < 0.5 {
            return .autoKept
        }

        // Short-medium gaps (0.5-1.5s) are likely unwanted - auto-remove
        if durationSeconds < 1.5 {
            return .autoRemoved
        }

        // Medium gaps (1.5-3s) need review
        if durationSeconds < settings.autoReviewThreshold {
            return .pending
        }

        // Long gaps (>3s) are definitely unwanted but flag for review
        // in case there's a reason (B-roll, transition, etc.)
        return .pending
    }

    /// Print summary of detected gaps
    private func printGapSummary(_ gaps: [DetectedGap]) {
        let autoKept = gaps.filter { $0.removalStatus == .autoKept }.count
        let autoRemoved = gaps.filter { $0.removalStatus == .autoRemoved }.count
        let pending = gaps.filter { $0.removalStatus == .pending }.count

        // REFACTOR NOTE: Now using durationSeconds for display
        let totalGapTime = gaps.reduce(0.0) { $0 + $1.durationSeconds }
        let removableTime = gaps.filter { $0.removalStatus == .autoRemoved || $0.removalStatus == .pending }
            .reduce(0.0) { $0 + $1.durationSeconds }

        print("   📊 Auto-kept (natural pauses): \(autoKept)")
        print("   ✂️  Auto-removed: \(autoRemoved)")
        print("   ❓ Pending review: \(pending)")
        print("   ⏱️  Total gap time: \(String(format: "%.1f", totalGapTime))s")
        print("   ✂️  Removable time: \(String(format: "%.1f", removableTime))s")
    }

    /// Get context words around a gap
    /// - Parameters:
    ///   - gap: The gap to get context for
    ///   - words: All transcribed words
    ///   - segments: All segments
    ///   - contextWordCount: How many words to include before/after
    /// - Returns: Tuple of (preceding words, following words)
    func getGapContext(
        gap: DetectedGap,
        words: [TranscribedWord],
        segments: [SpeechSegment],
        contextWordCount: Int = 5
    ) -> (before: [TranscribedWord], after: [TranscribedWord]) {

        var beforeWords: [TranscribedWord] = []
        var afterWords: [TranscribedWord] = []

        // Find preceding segment and get last N words
        if let precedingId = gap.precedingSegmentId,
           let precedingSegment = segments.first(where: { $0.id == precedingId }) {
            let segmentWords = words.filter { precedingSegment.wordIds.contains($0.id) }
                .sorted { $0.startTime < $1.startTime }
            beforeWords = Array(segmentWords.suffix(contextWordCount))
        }

        // Find following segment and get first N words
        if let followingId = gap.followingSegmentId,
           let followingSegment = segments.first(where: { $0.id == followingId }) {
            let segmentWords = words.filter { followingSegment.wordIds.contains($0.id) }
                .sorted { $0.startTime < $1.startTime }
            afterWords = Array(segmentWords.prefix(contextWordCount))
        }

        return (beforeWords, afterWords)
    }
}

// MARK: - Gap Statistics

struct GapStatistics {
    let totalGaps: Int
    let pendingCount: Int
    let autoRemovedCount: Int
    let autoKeptCount: Int
    let manualRemovedCount: Int
    let manualKeptCount: Int

    // REFACTOR NOTE: These remain as TimeInterval (seconds) for display purposes
    // Internal calculations use the seconds property from CodableCMTime
    let totalGapDuration: TimeInterval
    let removableDuration: TimeInterval  // Total duration of gaps marked for removal
    let savedDuration: TimeInterval      // Actual time saved (accounting for kept pause)

    var reviewedCount: Int {
        manualRemovedCount + manualKeptCount
    }

    var remainingToReview: Int {
        pendingCount
    }

    /// Initialize with gaps only (legacy, assumes no kept pause)
    init(gaps: [DetectedGap]) {
        self.init(gaps: gaps, targetPauseDuration: 0)
    }

    /// Initialize with gaps and target pause duration for accurate saved time calculation
    // REFACTOR NOTE: Uses durationSeconds from gaps now
    init(gaps: [DetectedGap], targetPauseDuration: TimeInterval) {
        self.totalGaps = gaps.count
        self.pendingCount = gaps.filter { $0.removalStatus == .pending }.count
        self.autoRemovedCount = gaps.filter { $0.removalStatus == .autoRemoved }.count
        self.autoKeptCount = gaps.filter { $0.removalStatus == .autoKept }.count
        self.manualRemovedCount = gaps.filter { $0.removalStatus == .remove }.count
        self.manualKeptCount = gaps.filter { $0.removalStatus == .keep }.count

        // Use durationSeconds for display calculations
        self.totalGapDuration = gaps.reduce(0.0) { $0 + $1.durationSeconds }

        let removableGaps = gaps.filter {
            $0.removalStatus == .remove || $0.removalStatus == .autoRemoved
        }
        self.removableDuration = removableGaps.reduce(0.0) { $0 + $1.durationSeconds }

        // Calculate actual saved duration accounting for kept pause
        // Each gap keeps min(targetPauseDuration, gap.duration) which is split between start and end
        self.savedDuration = removableGaps.reduce(0.0) { total, gap in
            let keptPause = min(targetPauseDuration, gap.durationSeconds)
            return total + max(0, gap.durationSeconds - keptPause)
        }
    }
}
