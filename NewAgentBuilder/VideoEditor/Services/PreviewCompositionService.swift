//
//  PreviewCompositionService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/31/26.
//
//  REFACTORED 2026-02-03: Updated to use CMTime throughout.
//  Already used CMTime internally for AVFoundation; now input types also use CMTime.
//

import Foundation
import AVFoundation
import CoreMedia

/// Service that creates an AVComposition for previewing video with cuts applied
/// This doesn't render to disk - it's an in-memory edit that plays in real-time
class PreviewCompositionService {
    static let shared = PreviewCompositionService()

    private init() {}

    /// Create a composition that excludes the marked cuts
    /// - Parameters:
    ///   - sourceURL: Original video URL
    ///   - cuts: Gaps marked for removal (sorted by startTime)
    ///   - targetPauseDuration: How much pause to keep from each gap (default 0 = remove entirely)
    ///   - waveformData: Audio waveform for refining cut boundaries to actual silence
    /// - Returns: AVPlayerItem ready for playback, or nil if failed
    // REFACTOR NOTE: targetPauseDuration kept as TimeInterval for settings compatibility
    func createPreviewComposition(
        sourceURL: URL,
        cuts: [DetectedGap],
        targetPauseDuration: TimeInterval = 0,
        waveformData: WaveformData? = nil
    ) async throws -> AVPlayerItem {

        let asset = AVURLAsset(url: sourceURL)

        // Load duration and tracks
        let duration = try await asset.load(.duration)
        let totalDuration = duration.seconds

        // Get the video track's natural timescale for precision
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw PreviewError.noVideoTrack
        }
        let naturalTimescale = try await videoTrack.load(.naturalTimeScale)

        // Sort cuts by start time and filter to only those being removed
        let filteredCuts = cuts
            .filter { $0.removalStatus == .remove || $0.removalStatus == .autoRemoved }
            .sorted { $0.startTime < $1.startTime }

        // CRITICAL: Merge overlapping gaps before processing
        // This handles cases where duplicate rejection gaps overlap with silence gaps
        let sortedCuts = mergeOverlappingGaps(filteredCuts)

        print("🔧 Gaps before merge: \(filteredCuts.count), after merge: \(sortedCuts.count)")

        // If no cuts, just return the original
        if sortedCuts.isEmpty {
            return AVPlayerItem(asset: asset)
        }

        // Create composition with natural timescale
        let composition = AVMutableComposition()
        composition.naturalSize = try await videoTrack.load(.naturalSize)

        // Add video track
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw PreviewError.compositionFailed
        }

        // Copy video track settings
        compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

        // Add audio track
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        // Build segments (the parts we KEEP)
        // targetPauseDuration determines how much of each gap to preserve
        // waveformData is used to refine cut points to actual silence
        let keepSegments = calculateKeepSegments(
            totalDuration: totalDuration,
            cuts: sortedCuts,
            targetPauseDuration: targetPauseDuration,
            waveformData: waveformData
        )

        print("📽️ Building preview composition:")
        print("   Total duration: \(String(format: "%.1f", totalDuration))s")
        print("   Cuts: \(sortedCuts.count)")
        print("   Keep segments: \(keepSegments.count)")
        print("   Timescale: \(naturalTimescale)")

        // Insert each keep segment into composition
        var insertTime = CMTime.zero

        for segment in keepSegments {
            // Use natural timescale for frame-accurate editing
            let startTime = CMTime(seconds: segment.start, preferredTimescale: naturalTimescale)
            let endTime = CMTime(seconds: segment.end, preferredTimescale: naturalTimescale)
            let segmentDuration = endTime - startTime
            let timeRange = CMTimeRange(start: startTime, duration: segmentDuration)

            // Insert video
            try compositionVideoTrack.insertTimeRange(
                timeRange,
                of: videoTrack,
                at: insertTime
            )

            // Insert audio if available
            if let audioTrack = audioTrack, let compositionAudioTrack = compositionAudioTrack {
                try compositionAudioTrack.insertTimeRange(
                    timeRange,
                    of: audioTrack,
                    at: insertTime
                )
            }

            print("   ✓ Segment \(String(format: "%.2f", segment.start))s - \(String(format: "%.2f", segment.end))s")

            insertTime = insertTime + segmentDuration
        }

        let finalDuration = insertTime.seconds
        let cutTime = totalDuration - finalDuration
        print("   📊 Final duration: \(String(format: "%.1f", finalDuration))s (cut \(String(format: "%.1f", cutTime))s)")

        // Create audio mix with short crossfades at edit points for smoother transitions
        let audioMix = createAudioMix(
            for: compositionAudioTrack,
            segments: keepSegments,
            timescale: naturalTimescale
        )

        // Create player item with better buffering
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.preferredForwardBufferDuration = 2.0 // Buffer 2 seconds ahead

        if let audioMix = audioMix {
            playerItem.audioMix = audioMix
        }

        return playerItem
    }

    /// Create audio mix with short fades at segment boundaries
    private func createAudioMix(
        for audioTrack: AVMutableCompositionTrack?,
        segments: [(start: TimeInterval, end: TimeInterval)],
        timescale: CMTimeScale
    ) -> AVMutableAudioMix? {
        guard let audioTrack = audioTrack, segments.count > 1 else { return nil }

        let audioMix = AVMutableAudioMix()
        let parameters = AVMutableAudioMixInputParameters(track: audioTrack)

        let fadeDuration = CMTime(seconds: 0.02, preferredTimescale: timescale) // 20ms fade

        var compositionTime = CMTime.zero

        for (index, segment) in segments.enumerated() {
            let segmentDuration = CMTime(seconds: segment.end - segment.start, preferredTimescale: timescale)

            // Fade in at start of segment (except first)
            if index > 0 {
                let fadeInStart = compositionTime
                let fadeInEnd = compositionTime + fadeDuration
                parameters.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0,
                                         timeRange: CMTimeRange(start: fadeInStart, end: fadeInEnd))
            }

            // Fade out at end of segment (except last)
            if index < segments.count - 1 {
                let fadeOutStart = compositionTime + segmentDuration - fadeDuration
                let fadeOutEnd = compositionTime + segmentDuration
                parameters.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0,
                                         timeRange: CMTimeRange(start: fadeOutStart, end: fadeOutEnd))
            }

            compositionTime = compositionTime + segmentDuration
        }

        audioMix.inputParameters = [parameters]
        return audioMix
    }

    /// Merge overlapping or adjacent gaps into single contiguous gaps
    /// This is critical when duplicate rejection gaps overlap with silence gaps
    // REFACTOR NOTE: Updated to work with CodableCMTime-based DetectedGap
    private func mergeOverlappingGaps(_ gaps: [DetectedGap]) -> [DetectedGap] {
        guard !gaps.isEmpty else { return [] }

        var merged: [DetectedGap] = []
        var current = gaps[0]

        for i in 1..<gaps.count {
            let next = gaps[i]

            // Check if next gap overlaps with or is adjacent to current
            // (Using small epsilon for floating point comparison on seconds)
            if next.startSeconds <= current.endSeconds + 0.001 {
                // Merge: extend current gap to include next
                let newEndSeconds = max(current.endSeconds, next.endSeconds)
                // REFACTOR NOTE: Using convenience initializer with seconds for consistency
                current = DetectedGap(
                    id: current.id,
                    startSeconds: current.startSeconds,
                    endSeconds: newEndSeconds,
                    precedingSegmentId: current.precedingSegmentId,
                    followingSegmentId: next.followingSegmentId,
                    removalStatus: current.removalStatus
                )
                print("   🔗 Merged gap: \(String(format: "%.3f", current.startSeconds))-\(String(format: "%.3f", current.endSeconds)) (absorbed \(String(format: "%.3f", next.startSeconds))-\(String(format: "%.3f", next.endSeconds)))")
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

    /// Calculate the segments to keep (inverse of cuts, respecting targetPauseDuration)
    /// - Parameters:
    ///   - totalDuration: Total video duration
    ///   - cuts: Gaps to be cut
    ///   - targetPauseDuration: How much pause to keep from each gap (0 = remove entirely)
    ///
    /// The kept pause is SPLIT between start and end of the gap for natural speech flow:
    /// - Half the pause is kept at the end of the preceding speech
    /// - Half the pause is kept at the start of the following speech
    ///
    /// Example: 10s gap with 0.5s targetPauseDuration
    /// - Keep 0.25s at start (breath after speech)
    /// - Cut 9.5s in the middle
    /// - Keep 0.25s at end (breath before next speech)
    // REFACTOR NOTE: Uses seconds internally for calculations, works with CodableCMTime-based DetectedGap
    private func calculateKeepSegments(
        totalDuration: TimeInterval,
        cuts: [DetectedGap],
        targetPauseDuration: TimeInterval = 0,
        waveformData: WaveformData? = nil
    ) -> [(start: TimeInterval, end: TimeInterval)] {

        var segments: [(start: TimeInterval, end: TimeInterval)] = []
        var currentStart: TimeInterval = 0
        let refiner = CutBoundaryRefiner.shared

        for cut in cuts {
            // Split the kept pause between start and end
            // halfKeep = half the target pause, but never more than half the gap
            // Use seconds for calculations
            let halfKeep = min(targetPauseDuration / 2.0, cut.durationSeconds / 2.0)

            // Calculate initial cut points from Whisper timestamps (in seconds, then convert to CMTime)
            var actualCutStartSeconds = cut.startSeconds + halfKeep
            var actualCutEndSeconds = cut.endSeconds - halfKeep

            // REFINE cut points using waveform to find actual silence
            if let waveform = waveformData {
                // Buffer to move cut points INTO the silence (not right at the edge)
                // The boundary detection finds where silence begins/ends, but we want to
                // cut deeper into the silence to avoid any trailing audio or reverb
                let silenceBuffer: TimeInterval = 0.08  // 80ms into the silence

                // Refine start: search BACKWARD to find where preceding silence ENDS (speech begins)
                // Then move EARLIER (into the silence) by the buffer amount
                let startResult = refiner.refineCutPoint(
                    whisperTime: CodableCMTime(seconds: actualCutStartSeconds),
                    waveform: waveform,
                    direction: .backward
                )
                if startResult.foundSilence {
                    let oldStart = actualCutStartSeconds
                    // Move earlier into the silence (subtract buffer)
                    actualCutStartSeconds = max(0, startResult.refinedTime.seconds - silenceBuffer)
                    print("   📍 Cut start refined: \(formatTimeMs(oldStart)) → \(formatTimeMs(actualCutStartSeconds)) (with \(Int(silenceBuffer * 1000))ms buffer)")
                }

                // Refine end: search FORWARD to find where following silence BEGINS (speech ends)
                // Then move LATER (into the silence) by the buffer amount
                let endResult = refiner.refineCutPoint(
                    whisperTime: CodableCMTime(seconds: actualCutEndSeconds),
                    waveform: waveform,
                    direction: .forward
                )
                if endResult.foundSilence {
                    let oldEnd = actualCutEndSeconds
                    // Move later into the silence (add buffer)
                    actualCutEndSeconds = min(waveform.duration, endResult.refinedTime.seconds + silenceBuffer)
                    print("   📍 Cut end refined: \(formatTimeMs(oldEnd)) → \(formatTimeMs(actualCutEndSeconds)) (with \(Int(silenceBuffer * 1000))ms buffer)")
                }
            }

            // Only cut if there's something left to cut after refinement
            if actualCutStartSeconds < actualCutEndSeconds {
                // Keep segment from currentStart to actualCutStart
                if actualCutStartSeconds > currentStart {
                    segments.append((start: currentStart, end: actualCutStartSeconds))
                }
                // Next segment starts at actualCutEnd
                currentStart = actualCutEndSeconds
            } else {
                // Gap is shorter than targetPauseDuration or refinement eliminated it
                // Just continue - it will be included in the next segment
            }
        }

        // Keep final segment after last cut
        if currentStart < totalDuration {
            segments.append((start: currentStart, end: totalDuration))
        }

        return segments
    }

    private func formatTimeMs(_ timeSeconds: TimeInterval) -> String {
        let minutes = Int(timeSeconds) / 60
        let seconds = Int(timeSeconds) % 60
        let ms = Int((timeSeconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, ms)
    }
}

// MARK: - Errors

enum PreviewError: LocalizedError {
    case noVideoTrack
    case compositionFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in source file"
        case .compositionFailed:
            return "Failed to build preview composition"
        }
    }
}
