//
//  CutBoundaryRefiner.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/1/26.
//
//  REFACTORED 2026-02-03: Changed from TimeInterval to CMTime for frame-accurate timing.
//  Internal sample-based calculations remain the same; CMTime is used for input/output.
//

import Foundation
import CoreMedia

/// Service that refines cut boundaries using actual waveform data
/// Whisper timestamps are approximate - this finds the true silence boundaries
class CutBoundaryRefiner {
    static let shared = CutBoundaryRefiner()

    private init() {}

    // MARK: - Configuration

    /// Minimum amplitude to consider as "silence" on the dB-normalized scale (0.0 = -60dB, 1.0 = 0dB)
    /// True silence ([BLANK_AUDIO]) is 0.0-0.02, so threshold must be below that
    /// 0.02 = actual silence, anything higher catches speech tail
    var silenceThreshold: Float = 0.02

    /// Minimum duration of silence to be valid (in seconds)
    /// NOTE: Kept as TimeInterval for internal sample calculations
    var minimumSilenceDuration: TimeInterval = 0.1

    /// How far to search before/after the whisper timestamp (in seconds)
    /// NOTE: Kept as TimeInterval for internal sample calculations
    var searchWindow: TimeInterval = 0.5

    // MARK: - Boundary Refinement

    /// Refine a cut point by finding the nearest true silence boundary
    /// - Parameters:
    ///   - whisperTime: The timestamp from Whisper transcription (CMTime)
    ///   - waveform: The audio waveform data
    ///   - direction: Which direction to search (forward = find start of silence, backward = find end of silence)
    /// - Returns: Refined timestamp at the true silence boundary
    // REFACTOR NOTE: Changed whisperTime from TimeInterval to CodableCMTime
    // OLD CODE (commented for debug reference):
    // func refineCutPoint(whisperTime: TimeInterval, waveform: WaveformData, direction: SearchDirection) -> RefinedCutResult
    func refineCutPoint(
        whisperTime: CodableCMTime,
        waveform: WaveformData,
        direction: SearchDirection
    ) -> RefinedCutResult {

        // Convert CMTime to seconds for sample-based calculations
        let whisperSeconds = whisperTime.seconds

        let sampleRate = waveform.sampleRate
        let samplesPerMs = sampleRate / 1000.0

        // Search window in samples
        let windowSamples = Int(searchWindow * sampleRate)
        let silenceSamples = Int(minimumSilenceDuration * sampleRate)

        // Get waveform samples around the whisper time
        let startTimeSeconds = max(0, whisperSeconds - searchWindow)
        let endTimeSeconds = min(waveform.duration, whisperSeconds + searchWindow)
        let sampleCount = Int((endTimeSeconds - startTimeSeconds) * sampleRate)

        let samples = waveform.samples(from: startTimeSeconds, to: endTimeSeconds, count: sampleCount)

        // Find the whisper time's position in our sample window
        let whisperOffset = whisperSeconds - startTimeSeconds
        let whisperSampleIndex = Int(whisperOffset * sampleRate)

        // Get amplitude at whisper's timestamp
        let amplitudeAtWhisper = whisperSampleIndex < samples.count ? samples[whisperSampleIndex] : 0

        var refinedSeconds = whisperSeconds
        var foundSilence = false
        var silenceStartSeconds: TimeInterval = whisperSeconds
        var silenceEndSeconds: TimeInterval = whisperSeconds

        switch direction {
        case .forward:
            // Looking for the start of silence AFTER whisper time
            // (used when cutting at end of a word - want to find where speech truly ends)
            if let result = findSilenceForward(
                samples: samples,
                startIndex: whisperSampleIndex,
                silenceThreshold: silenceThreshold,
                minSilenceSamples: silenceSamples
            ) {
                refinedSeconds = startTimeSeconds + (Double(result.silenceStartIndex) / sampleRate)
                silenceStartSeconds = refinedSeconds
                silenceEndSeconds = startTimeSeconds + (Double(result.silenceEndIndex) / sampleRate)
                foundSilence = true
            }

        case .backward:
            // Looking for the end of silence BEFORE whisper time
            // (used when cutting at start of a word - want to find where speech truly begins)
            if let result = findSilenceBackward(
                samples: samples,
                startIndex: whisperSampleIndex,
                silenceThreshold: silenceThreshold,
                minSilenceSamples: silenceSamples
            ) {
                refinedSeconds = startTimeSeconds + (Double(result.silenceEndIndex) / sampleRate)
                silenceStartSeconds = startTimeSeconds + (Double(result.silenceStartIndex) / sampleRate)
                silenceEndSeconds = refinedSeconds
                foundSilence = true
            }
        }

        let adjustmentSeconds = refinedSeconds - whisperSeconds

        // Convert results back to CodableCMTime
        return RefinedCutResult(
            originalTime: whisperTime,
            refinedTime: CodableCMTime(seconds: refinedSeconds),
            adjustment: CodableCMTime(seconds: adjustmentSeconds),
            foundSilence: foundSilence,
            silenceStart: CodableCMTime(seconds: silenceStartSeconds),
            silenceEnd: CodableCMTime(seconds: silenceEndSeconds),
            amplitudeAtOriginal: amplitudeAtWhisper,
            direction: direction
        )
    }

    /// Find silence boundary searching forward from start index
    private func findSilenceForward(
        samples: [Float],
        startIndex: Int,
        silenceThreshold: Float,
        minSilenceSamples: Int
    ) -> (silenceStartIndex: Int, silenceEndIndex: Int)? {

        var consecutiveSilent = 0
        var silenceStartIndex: Int?

        for i in startIndex..<samples.count {
            if samples[i] < silenceThreshold {
                if silenceStartIndex == nil {
                    silenceStartIndex = i
                }
                consecutiveSilent += 1

                if consecutiveSilent >= minSilenceSamples {
                    return (silenceStartIndex!, i)
                }
            } else {
                // Reset - not silent
                consecutiveSilent = 0
                silenceStartIndex = nil
            }
        }

        return nil
    }

    /// Find silence boundary searching backward from start index
    private func findSilenceBackward(
        samples: [Float],
        startIndex: Int,
        silenceThreshold: Float,
        minSilenceSamples: Int
    ) -> (silenceStartIndex: Int, silenceEndIndex: Int)? {

        var consecutiveSilent = 0
        var silenceEndIndex: Int?

        for i in stride(from: min(startIndex, samples.count - 1), through: 0, by: -1) {
            if samples[i] < silenceThreshold {
                if silenceEndIndex == nil {
                    silenceEndIndex = i
                }
                consecutiveSilent += 1

                if consecutiveSilent >= minSilenceSamples {
                    return (i, silenceEndIndex!)
                }
            } else {
                // Reset - not silent
                consecutiveSilent = 0
                silenceEndIndex = nil
            }
        }

        return nil
    }

    // MARK: - Debug Analysis

    /// Generate a detailed debug report comparing Whisper timestamps to waveform
    // REFACTOR NOTE: Changed targetPauseDuration to use seconds directly for display
    func generateDebugReport(
        gaps: [DetectedGap],
        waveform: WaveformData,
        targetPauseDuration: TimeInterval
    ) -> String {

        var report = """
        ════════════════════════════════════════════════════════════════
        CUT BOUNDARY REFINEMENT DEBUG REPORT
        Generated: \(Date())
        ════════════════════════════════════════════════════════════════

        SETTINGS
        ════════════════════════════════════════════════════════════════
        Silence threshold: \(String(format: "%.2f", silenceThreshold)) (0=silent, 1=loud)
        Minimum silence duration: \(String(format: "%.3f", minimumSilenceDuration))s
        Search window: ±\(String(format: "%.3f", searchWindow))s

        WAVEFORM INFO
        ════════════════════════════════════════════════════════════════
        Sample rate: \(String(format: "%.1f", waveform.sampleRate)) samples/sec
        Duration: \(String(format: "%.3f", waveform.duration))s
        Total samples: \(waveform.samples.count)

        ════════════════════════════════════════════════════════════════
        CUT POINT ANALYSIS
        ════════════════════════════════════════════════════════════════

        """

        let cutsToAnalyze = gaps.filter {
            $0.removalStatus == .remove || $0.removalStatus == .autoRemoved
        }.sorted { $0.startTime < $1.startTime }

        for (index, gap) in cutsToAnalyze.enumerated() {
            // Calculate cut points using centered pause logic (using seconds for display)
            let halfKeep = min(targetPauseDuration / 2.0, gap.durationSeconds / 2.0)
            let cutStartSeconds = gap.startSeconds + halfKeep
            let cutEndSeconds = gap.endSeconds - halfKeep

            // Convert to CodableCMTime for refineCutPoint calls
            let cutStart = CodableCMTime(seconds: cutStartSeconds)
            let cutEnd = CodableCMTime(seconds: cutEndSeconds)

            report += """

            ────────────────────────────────────────────────────────────────
            CUT \(index + 1): Gap \(formatTime(gap.startSeconds)) - \(formatTime(gap.endSeconds))
            ────────────────────────────────────────────────────────────────
            Gap duration: \(String(format: "%.3f", gap.durationSeconds))s
            Target pause: \(String(format: "%.3f", targetPauseDuration))s

            CUT START ANALYSIS (finding where to begin cutting):
            """

            // Analyze cut start - search BACKWARD to find where preceding silence ends
            let startResult = refineCutPoint(
                whisperTime: cutStart,
                waveform: waveform,
                direction: .backward
            )

            report += """

              Whisper says cut at: \(formatTime(startResult.originalTime.seconds))
              Amplitude at Whisper time: \(String(format: "%.3f", startResult.amplitudeAtOriginal))
              Found true silence: \(startResult.foundSilence ? "YES" : "NO")
            """

            if startResult.foundSilence {
                report += """

                  True silence at: \(formatTime(startResult.silenceStart.seconds)) - \(formatTime(startResult.silenceEnd.seconds))
                  RECOMMENDED cut start: \(formatTime(startResult.refinedTime.seconds))
                  Adjustment: \(startResult.adjustment.seconds >= 0 ? "+" : "")\(String(format: "%.3f", startResult.adjustment.seconds * 1000))ms
                """
            } else {
                report += """

                  ⚠️ No clear silence found within \(String(format: "%.0f", searchWindow * 1000))ms
                """
            }

            report += """


            CUT END ANALYSIS (finding where to stop cutting):
            """

            // Analyze cut end - search FORWARD to find where following silence begins
            let endResult = refineCutPoint(
                whisperTime: cutEnd,
                waveform: waveform,
                direction: .forward
            )

            report += """

              Whisper says cut at: \(formatTime(endResult.originalTime.seconds))
              Amplitude at Whisper time: \(String(format: "%.3f", endResult.amplitudeAtOriginal))
              Found true silence: \(endResult.foundSilence ? "YES" : "NO")
            """

            if endResult.foundSilence {
                report += """

                  True silence at: \(formatTime(endResult.silenceStart.seconds)) - \(formatTime(endResult.silenceEnd.seconds))
                  RECOMMENDED cut end: \(formatTime(endResult.refinedTime.seconds))
                  Adjustment: \(endResult.adjustment.seconds >= 0 ? "+" : "")\(String(format: "%.3f", endResult.adjustment.seconds * 1000))ms
                """
            } else {
                report += """

                  ⚠️ No clear silence found within \(String(format: "%.0f", searchWindow * 1000))ms
                """
            }

            // Waveform visualization around cut points (using seconds)
            report += """


            WAVEFORM AROUND CUT START (\(formatTime(cutStartSeconds))):
            """
            report += generateWaveformVisualization(
                around: cutStartSeconds,
                waveform: waveform,
                windowSize: 0.2
            )

            report += """


            WAVEFORM AROUND CUT END (\(formatTime(cutEndSeconds))):
            """
            report += generateWaveformVisualization(
                around: cutEndSeconds,
                waveform: waveform,
                windowSize: 0.2
            )
        }

        report += """


        ════════════════════════════════════════════════════════════════
        END OF REPORT
        ════════════════════════════════════════════════════════════════
        """

        return report
    }

    /// Generate ASCII visualization of waveform around a time point
    /// NOTE: Uses TimeInterval (seconds) internally for waveform sample access
    private func generateWaveformVisualization(
        around time: TimeInterval,
        waveform: WaveformData,
        windowSize: TimeInterval
    ) -> String {

        let startTime = max(0, time - windowSize / 2)
        let endTime = min(waveform.duration, time + windowSize / 2)

        // Get 40 samples for the visualization
        let sampleCount = 40
        let samples = waveform.samples(from: startTime, to: endTime, count: sampleCount)

        var viz = "\n    "

        // Time markers
        for i in 0..<sampleCount {
            let t = startTime + (Double(i) / Double(sampleCount)) * (endTime - startTime)
            if abs(t - time) < (endTime - startTime) / Double(sampleCount) {
                viz += "▼"  // Mark the cut point
            } else if i % 10 == 0 {
                viz += "|"
            } else {
                viz += " "
            }
        }

        viz += "\n    "

        // Amplitude bars (using block characters)
        for amplitude in samples {
            if amplitude < 0.1 {
                viz += "▁"  // Very quiet
            } else if amplitude < 0.2 {
                viz += "▂"
            } else if amplitude < 0.3 {
                viz += "▃"
            } else if amplitude < 0.4 {
                viz += "▄"
            } else if amplitude < 0.5 {
                viz += "▅"
            } else if amplitude < 0.6 {
                viz += "▆"
            } else if amplitude < 0.8 {
                viz += "▇"
            } else {
                viz += "█"  // Loud
            }
        }

        viz += "\n    "
        viz += String(format: "%.2f", startTime)
        viz += String(repeating: " ", count: sampleCount - 10)
        viz += String(format: "%.2f", endTime)
        viz += "s"

        // Silence threshold line
        viz += "\n    Threshold (──): \(String(format: "%.2f", silenceThreshold))"

        return viz
    }

    /// Format time in seconds as mm:ss.mmm
    private func formatTime(_ timeSeconds: TimeInterval) -> String {
        let minutes = Int(timeSeconds) / 60
        let seconds = Int(timeSeconds) % 60
        let ms = Int((timeSeconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, ms)
    }
}

// MARK: - Supporting Types

enum SearchDirection {
    case forward   // Search for silence after the timestamp
    case backward  // Search for silence before the timestamp
}

// REFACTOR NOTE: Changed from TimeInterval to CodableCMTime
// OLD CODE (commented for debug reference):
// struct RefinedCutResult {
//     let originalTime: TimeInterval
//     let refinedTime: TimeInterval
//     let adjustment: TimeInterval
//     let foundSilence: Bool
//     let silenceStart: TimeInterval
//     let silenceEnd: TimeInterval
//     let amplitudeAtOriginal: Float
//     let direction: SearchDirection
// }
struct RefinedCutResult {
    let originalTime: CodableCMTime
    let refinedTime: CodableCMTime
    let adjustment: CodableCMTime  // Positive = moved later, negative = moved earlier
    let foundSilence: Bool
    let silenceStart: CodableCMTime
    let silenceEnd: CodableCMTime
    let amplitudeAtOriginal: Float
    let direction: SearchDirection
}
