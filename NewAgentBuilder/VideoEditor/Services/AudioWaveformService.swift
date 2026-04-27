//
//  AudioWaveformService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//
//  REFACTORED 2026-02-03: Added CMTime-based public API.
//  Internal calculations remain sample-based for efficiency.
//  WaveformData stores duration as TimeInterval (seconds) because it's sample-based.
//

import Foundation
import AVFoundation
import Accelerate
import CoreMedia

// MARK: - Waveform Data

struct WaveformData: Codable, Hashable {
    let samples: [Float]  // Normalized dB values (0.0 to 1.0)
    let sampleRate: Double  // Samples per second
    // NOTE: duration is kept as TimeInterval because waveform is sample-based internally
    let duration: TimeInterval
    let audioStartOffset: TimeInterval  // Offset from video start (usually 0, but can vary)

    init(samples: [Float], sampleRate: Double, duration: TimeInterval, audioStartOffset: TimeInterval = 0) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.duration = duration
        self.audioStartOffset = audioStartOffset
    }

    // Custom decoding to handle existing data without audioStartOffset
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        samples = try container.decode([Float].self, forKey: .samples)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        // Default to 0 if not present (backward compatibility)
        audioStartOffset = try container.decodeIfPresent(TimeInterval.self, forKey: .audioStartOffset) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case samples, sampleRate, duration, audioStartOffset
    }

    // MARK: - CMTime API (for timeline integration)

    /// Duration as CMTime
    var durationCMTime: CodableCMTime {
        CodableCMTime(seconds: duration)
    }

    /// Get the amplitude at a specific video time (CMTime version)
    func amplitude(at videoTime: CodableCMTime) -> Float {
        return amplitude(at: videoTime.seconds)
    }

    /// Get samples for a time range (CMTime version)
    func samples(from startTime: CodableCMTime, to endTime: CodableCMTime, count: Int) -> [Float] {
        return samples(from: startTime.seconds, to: endTime.seconds, count: count)
    }

    // MARK: - TimeInterval API (internal/sample-based)

    /// Get the amplitude at a specific video time (accounting for audio offset)
    func amplitude(at videoTime: TimeInterval) -> Float {
        guard duration > 0, !samples.isEmpty else { return 0 }

        // Convert video time to audio time
        let audioTime = videoTime - audioStartOffset

        // If before audio starts, return silence
        if audioTime < 0 { return 0 }

        // If after audio ends, return silence
        if audioTime >= duration { return 0 }

        let index = Int((audioTime / duration) * Double(samples.count))
        let clampedIndex = max(0, min(samples.count - 1, index))
        return samples[clampedIndex]
    }

    /// Get samples for a time range (TimeInterval version for internal use)
    func samples(from startTime: TimeInterval, to endTime: TimeInterval, count: Int) -> [Float] {
        guard duration > 0, !samples.isEmpty, count > 0 else { return [] }

        var result: [Float] = []
        let timeStep = (endTime - startTime) / Double(count)

        for i in 0..<count {
            let time = startTime + (Double(i) * timeStep)
            result.append(amplitude(at: time))
        }

        return result
    }
}

// MARK: - Waveform Service

class AudioWaveformService {
    static let shared = AudioWaveformService()

    private init() {}

    /// Extract waveform data from a video file
    /// - Parameters:
    ///   - videoURL: URL to the video file
    ///   - samplesPerSecond: How many samples per second (higher = more detail, more memory)
    ///   - onProgress: Progress callback (0.0 to 1.0)
    /// - Returns: WaveformData containing normalized amplitude samples
    func extractWaveform(
        from videoURL: URL,
        samplesPerSecond: Double = 30,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> WaveformData {

        let asset = AVAsset(url: videoURL)

        // Get video duration (this is what the timeline uses)
        let videoDuration = try await asset.load(.duration).seconds
        guard videoDuration > 0 else {
            throw WaveformError.invalidDuration
        }

        // Get audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw WaveformError.noAudioTrack
        }

        // Get audio track's time range to detect offset from video start
        let audioTimeRange = try await audioTrack.load(.timeRange)
        let audioStartOffset = audioTimeRange.start.seconds
        let audioDuration = audioTimeRange.duration.seconds

        print("📊 Audio track timing:")
        print("   Video duration: \(String(format: "%.3f", videoDuration))s")
        print("   Audio starts at: \(String(format: "%.3f", audioStartOffset))s")
        print("   Audio duration: \(String(format: "%.3f", audioDuration))s")

        // Use video duration for timeline, but account for audio offset
        let duration = videoDuration

        onProgress?(0.1)

        // Set up asset reader
        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw WaveformError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        onProgress?(0.2)

        // Read all audio samples
        var allSamples: [Int16] = []
        let sourceSampleRate: Double = 44100

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)

                data.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                }

                // Convert to Int16 samples
                let samples = data.withUnsafeBytes { ptr in
                    Array(ptr.bindMemory(to: Int16.self))
                }
                allSamples.append(contentsOf: samples)
            }
            CMSampleBufferInvalidate(sampleBuffer)
        }

        onProgress?(0.6)

        guard !allSamples.isEmpty else {
            throw WaveformError.noSamples
        }

        // Downsample to target samples per second
        let totalTargetSamples = Int(duration * samplesPerSecond)
        let samplesPerBucket = max(1, allSamples.count / totalTargetSamples)

        var downsampledAmplitudes: [Float] = []
        downsampledAmplitudes.reserveCapacity(totalTargetSamples)

        for i in stride(from: 0, to: allSamples.count, by: samplesPerBucket) {
            let end = min(i + samplesPerBucket, allSamples.count)
            let bucket = allSamples[i..<end]

            // Get RMS (root mean square) for this bucket
            var sum: Float = 0
            for sample in bucket {
                let normalized = Float(sample) / Float(Int16.max)
                sum += normalized * normalized
            }
            let rms = sqrt(sum / Float(bucket.count))

            // Convert to dB and normalize to 0-1 range
            // dB range roughly -60 to 0, we normalize this
            let db = 20 * log10(max(rms, 0.0001))
            let normalizedDb = (db + 60) / 60  // -60dB = 0, 0dB = 1
            let clampedDb = max(0, min(1, normalizedDb))

            downsampledAmplitudes.append(clampedDb)

            // Progress update
            if i % 10000 == 0 {
                let progress = 0.6 + (Double(i) / Double(allSamples.count)) * 0.35
                onProgress?(progress)
            }
        }

        onProgress?(1.0)

        print("✅ Waveform extracted: \(downsampledAmplitudes.count) samples for \(String(format: "%.1f", duration))s (audio offset: \(String(format: "%.3f", audioStartOffset))s)")

        return WaveformData(
            samples: downsampledAmplitudes,
            sampleRate: samplesPerSecond,
            duration: duration,
            audioStartOffset: audioStartOffset
        )
    }
}

// MARK: - Errors

enum WaveformError: LocalizedError {
    case invalidDuration
    case noAudioTrack
    case readerFailed(String)
    case noSamples

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Video has invalid duration"
        case .noAudioTrack:
            return "Video has no audio track"
        case .readerFailed(let message):
            return "Failed to read audio: \(message)"
        case .noSamples:
            return "No audio samples found"
        }
    }
}
