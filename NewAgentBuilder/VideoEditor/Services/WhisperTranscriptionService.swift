//
//  WhisperTranscriptionService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//
//  REFACTORED 2026-02-03: Updated to create TranscribedWord with CodableCMTime.
//  Uses convenience initializer that takes seconds for Whisper output.
//

import Foundation
import CoreMedia
import AVFoundation
import WhisperKit

// MARK: - Transcription Service

@MainActor
class WhisperTranscriptionService: ObservableObject {
    static let shared = WhisperTranscriptionService()

    @Published var isModelLoaded = false
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0.0
    @Published var modelLoadError: String?

    private var whisperKit: WhisperKit?

    // Available models (smaller = faster, larger = more accurate)
    enum WhisperModel: String, CaseIterable {
        case tiny = "tiny"
        case base = "base"
        case small = "small"
        case medium = "medium"

        var displayName: String {
            switch self {
            case .tiny: return "Tiny (fastest, least accurate)"
            case .base: return "Base (fast, good accuracy)"
            case .small: return "Small (balanced)"
            case .medium: return "Medium (slow, best accuracy)"
            }
        }
    }

    private init() {}

    // MARK: - Load Model

    func loadModel(_ model: WhisperModel = .base) async throws {
        guard !isModelLoaded else { return }

        isDownloadingModel = true
        downloadProgress = 0.0
        modelLoadError = nil

        do {
            print("🎤 Loading WhisperKit model: \(model.rawValue)")

            whisperKit = try await WhisperKit(
                model: model.rawValue,
                downloadBase: nil,
                modelRepo: nil,
                modelFolder: nil,
                tokenizerFolder: nil,
                computeOptions: nil,
                audioProcessor: nil,
                featureExtractor: nil,
                audioEncoder: nil,
                textDecoder: nil,
                logitsFilters: nil,
                segmentSeeker: nil,
                verbose: true,
                logLevel: .debug,
                prewarm: true,
                load: true,
                useBackgroundDownloadSession: false
            )

            isModelLoaded = true
            isDownloadingModel = false
            downloadProgress = 1.0
            print("✅ WhisperKit model loaded successfully")

        } catch {
            isDownloadingModel = false
            modelLoadError = error.localizedDescription
            print("❌ Failed to load WhisperKit model: \(error)")
            throw error
        }
    }

    // MARK: - Transcribe Video

    func transcribe(
        videoURL: URL,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> [TranscribedWord] {

        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        // Extract audio from video
        onProgress(0.05, "Extracting audio...")
        let audioURL = try await extractAudio(from: videoURL)

        defer {
            // Clean up temporary audio file
            try? FileManager.default.removeItem(at: audioURL)
        }

        // Transcribe
        onProgress(0.1, "Starting transcription...")

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: DecodingOptions(
                verbose: true,
                task: .transcribe,
                language: "en",
                temperatureFallbackCount: 3,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: true,
                clipTimestamps: [],
                concurrentWorkerCount: 0,
                chunkingStrategy: .vad
            ),
            callback: { progress in
                // Simple progress update - WhisperKit doesn't give easy percentage
                Task { @MainActor in
                    onProgress(0.5, "Transcribing...")
                }
                return true // continue
            }
        )

        onProgress(0.95, "Processing results...")

        // Convert to our TranscribedWord format
        var words: [TranscribedWord] = []

        for result in results {
            // TranscriptionResult has segments, each segment has words
            for segment in result.segments {
                if let segmentWords = segment.words {
                    for wordTiming in segmentWords {
                        // REFACTOR NOTE: Using convenience initializer with seconds
                        // OLD CODE:
                        // let word = TranscribedWord(
                        //     text: wordTiming.word.trimmingCharacters(in: CharacterSet.whitespaces),
                        //     startTime: TimeInterval(wordTiming.start),
                        //     endTime: TimeInterval(wordTiming.end),
                        //     confidence: wordTiming.probability
                        // )
                        let word = TranscribedWord(
                            text: wordTiming.word.trimmingCharacters(in: CharacterSet.whitespaces),
                            startSeconds: Double(wordTiming.start),
                            endSeconds: Double(wordTiming.end),
                            confidence: wordTiming.probability
                        )
                        words.append(word)
                    }
                }
            }
        }

        onProgress(1.0, "Complete")
        print("✅ Transcribed \(words.count) words")

        return words
    }

    // MARK: - Extract Audio

    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVAsset(url: videoURL)

        // Create output URL for audio
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        // Check for audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw TranscriptionError.noAudioTrack
        }

        // Export audio
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status == .completed {
            return outputURL
        } else {
            throw exportSession.error ?? TranscriptionError.exportFailed
        }
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case noAudioTrack
    case exportFailed
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model not loaded. Please load the model first."
        case .noAudioTrack:
            return "Video file has no audio track."
        case .exportFailed:
            return "Failed to extract audio from video."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}
