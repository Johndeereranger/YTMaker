//
//  SilenceDetectionService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//

import Foundation

// MARK: - Silence Region

/// A region of silence detected from waveform analysis
struct SilenceRegion: Identifiable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval { endTime - startTime }
}

// MARK: - Silence Detection Service

class SilenceDetectionService {
    static let shared = SilenceDetectionService()

    private init() {}

    /// Detect silence regions from waveform data
    /// - Parameters:
    ///   - waveform: The extracted waveform data
    ///   - silenceThreshold: Normalized amplitude below which is considered silence (0.0-1.0, default 0.1)
    ///   - minSilenceDuration: Minimum duration to count as a gap (seconds)
    /// - Returns: Array of silence regions
    func detectSilenceRegions(
        from waveform: WaveformData,
        silenceThreshold: Float = 0.1,
        minSilenceDuration: TimeInterval = 0.3
    ) -> [SilenceRegion] {

        guard !waveform.samples.isEmpty, waveform.duration > 0 else {
            return []
        }

        var silenceRegions: [SilenceRegion] = []
        var silenceStartTime: TimeInterval?

        let samplesPerSecond = Double(waveform.samples.count) / waveform.duration

        for (index, amplitude) in waveform.samples.enumerated() {
            let time = Double(index) / samplesPerSecond

            if amplitude < silenceThreshold {
                // We're in silence
                if silenceStartTime == nil {
                    silenceStartTime = time
                }
            } else {
                // We're in sound - check if we were in silence
                if let startTime = silenceStartTime {
                    let duration = time - startTime
                    if duration >= minSilenceDuration {
                        silenceRegions.append(SilenceRegion(
                            startTime: startTime,
                            endTime: time
                        ))
                    }
                    silenceStartTime = nil
                }
            }
        }

        // Don't forget trailing silence
        if let startTime = silenceStartTime {
            let duration = waveform.duration - startTime
            if duration >= minSilenceDuration {
                silenceRegions.append(SilenceRegion(
                    startTime: startTime,
                    endTime: waveform.duration
                ))
            }
        }

        print("🔇 Found \(silenceRegions.count) silence regions from waveform")
        return silenceRegions
    }

    /// Detect gaps using pure waveform analysis
    /// Waveform is ground truth - sample accurate, millisecond precision
    /// Word timestamps from Whisper are NOT reliable (50-100ms off, often fills gaps incorrectly)
    /// - Parameters:
    ///   - waveform: The extracted waveform data
    ///   - words: Ignored - kept for API compatibility but not used
    ///   - settings: Project settings
    /// - Returns: Array of detected gaps with proper classification
    func detectGapsFromWaveform(
        waveform: WaveformData,
        words: [TranscribedWord],
        settings: ProjectSettings
    ) -> [DetectedGap] {

        // Pure waveform detection - this is authoritative
        let silenceRegions = detectSilenceRegions(
            from: waveform,
            silenceThreshold: Float(settings.silenceThreshold),
            minSilenceDuration: settings.minimumGapDuration
        )

        // Convert silence regions directly to gaps
        // No word boundary correlation - waveform is more accurate than Whisper timestamps
        var gaps: [DetectedGap] = []

        for (index, region) in silenceRegions.enumerated() {
            let isEdge = index == 0 || index == silenceRegions.count - 1

            // REFACTOR NOTE: Using convenience initializer with seconds
            // SilenceRegion uses TimeInterval internally (sample-based)
            let gap = DetectedGap(
                startSeconds: region.startTime,
                endSeconds: region.endTime,
                precedingSegmentId: nil,
                followingSegmentId: nil,
                removalStatus: classifyGap(
                    duration: region.duration,
                    isEdge: isEdge,
                    settings: settings
                )
            )
            gaps.append(gap)
        }

        print("✅ Created \(gaps.count) gaps from waveform (sample-accurate)")
        printGapSummary(gaps)

        return gaps
    }

    /// Refine word boundaries based on waveform
    /// This adjusts Whisper's word timestamps to better match actual speech
    func refineWordBoundaries(
        words: [TranscribedWord],
        waveform: WaveformData,
        silenceThreshold: Float = 0.1
    ) -> [TranscribedWord] {

        guard !words.isEmpty, !waveform.samples.isEmpty else {
            return words
        }

        var refinedWords: [TranscribedWord] = []

        for word in words {
            // REFACTOR NOTE: Using seconds for waveform operations (sample-based)
            // Check the waveform at the start and end of this word
            let startAmplitude = waveform.amplitude(at: word.startSeconds)
            let endAmplitude = waveform.amplitude(at: word.endSeconds)

            var newStartSeconds = word.startSeconds
            var newEndSeconds = word.endSeconds

            // If the word starts in silence, find where sound actually begins
            if startAmplitude < silenceThreshold {
                newStartSeconds = findSoundStart(
                    after: word.startSeconds,
                    before: word.endSeconds,
                    waveform: waveform,
                    threshold: silenceThreshold
                ) ?? word.startSeconds
            }

            // If the word ends in silence, find where sound actually ends
            if endAmplitude < silenceThreshold {
                newEndSeconds = findSoundEnd(
                    after: word.startSeconds,
                    before: word.endSeconds,
                    waveform: waveform,
                    threshold: silenceThreshold
                ) ?? word.endSeconds
            }

            // Only adjust if the change is significant and word still has duration
            if newEndSeconds > newStartSeconds {
                // REFACTOR NOTE: Using convenience initializer with seconds
                let refined = TranscribedWord(
                    id: word.id,
                    text: word.text,
                    startSeconds: newStartSeconds,
                    endSeconds: newEndSeconds,
                    confidence: word.confidence
                )
                refinedWords.append(refined)
            } else {
                // Keep original if refinement failed
                refinedWords.append(word)
            }
        }

        // REFACTOR NOTE: Using seconds for comparison
        let adjustedCount = zip(words, refinedWords).filter { $0.0.startSeconds != $0.1.startSeconds || $0.0.endSeconds != $0.1.endSeconds }.count
        print("📝 Refined \(adjustedCount) word boundaries based on waveform")

        return refinedWords
    }

    // MARK: - Private Helpers

    private func findSoundStart(
        after startTime: TimeInterval,
        before endTime: TimeInterval,
        waveform: WaveformData,
        threshold: Float
    ) -> TimeInterval? {
        let step = 0.01 // 10ms steps
        var time = startTime

        while time < endTime {
            if waveform.amplitude(at: time) >= threshold {
                return time
            }
            time += step
        }

        return nil
    }

    private func findSoundEnd(
        after startTime: TimeInterval,
        before endTime: TimeInterval,
        waveform: WaveformData,
        threshold: Float
    ) -> TimeInterval? {
        let step = 0.01 // 10ms steps
        var time = endTime

        while time > startTime {
            if waveform.amplitude(at: time) >= threshold {
                return time
            }
            time -= step
        }

        return nil
    }

    private func classifyGap(
        duration: TimeInterval,
        isEdge: Bool,
        settings: ProjectSettings
    ) -> GapRemovalStatus {

        // Edge gaps (start/end of video) are usually auto-removed
        if isEdge {
            return .autoRemoved
        }

        // Very short gaps are natural speech pauses - auto-keep
        if duration < 0.5 {
            return .autoKept
        }

        // Medium gaps - auto-remove (likely unwanted pauses)
        if duration < 1.5 {
            return .autoRemoved
        }

        // Longer gaps need review
        if duration < settings.autoReviewThreshold {
            return .pending
        }

        // Very long gaps definitely need review
        return .pending
    }

    private func printGapSummary(_ gaps: [DetectedGap]) {
        let autoKept = gaps.filter { $0.removalStatus == .autoKept }.count
        let autoRemoved = gaps.filter { $0.removalStatus == .autoRemoved }.count
        let pending = gaps.filter { $0.removalStatus == .pending }.count

        // REFACTOR NOTE: Using durationSeconds for TimeInterval arithmetic
        let totalGapTime = gaps.reduce(0.0) { $0 + $1.durationSeconds }
        let removableTime = gaps.filter { $0.removalStatus == .autoRemoved || $0.removalStatus == .pending }
            .reduce(0.0) { $0 + $1.durationSeconds }

        print("   📊 Auto-kept (natural pauses): \(autoKept)")
        print("   ✂️  Auto-removed: \(autoRemoved)")
        print("   ❓ Pending review: \(pending)")
        print("   ⏱️  Total gap time: \(String(format: "%.1f", totalGapTime))s")
        print("   ✂️  Removable time: \(String(format: "%.1f", removableTime))s")
    }
}
