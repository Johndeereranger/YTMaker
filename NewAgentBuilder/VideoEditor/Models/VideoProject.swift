//
//  VideoProject.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//
//  REFACTORED 2026-02-03: Changed from TimeInterval to CMTime for frame-accurate timing.
//

import Foundation
import CoreMedia

// MARK: - Video Project

/// Represents a single video editing project
/// One video = one project for Phase 1
struct VideoProject: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // Video file reference (stored as bookmark data for sandbox-safe access)
    var videoBookmarkData: Data?
    var videoFileName: String?

    // REFACTOR NOTE: Changed from TimeInterval to CodableCMTime for frame-accurate timing
    // OLD CODE (commented for debug reference):
    // var videoDuration: TimeInterval?
    var videoDuration: CodableCMTime?

    // Convenience accessor for seconds
    var videoDurationSeconds: Double? { videoDuration?.seconds }

    // Processing status
    var status: ProjectStatus

    // Transcription results
    var transcribedWords: [TranscribedWord]
    var speechSegments: [SpeechSegment]
    var detectedGaps: [DetectedGap]

    // Audio waveform for visualization
    var waveformData: WaveformData?

    // Duplicate detection
    var repeatedPhrases: [RepeatedPhrase]

    // Applied moves (Stage 2 - zoom/pan/position transforms)
    var appliedMoves: [AppliedMove]

    // Project style - defines zoom percentages for this video
    // e.g., Base=115%, Medium=127%, Full=140%
    var projectStyle: ProjectStyle

    // Settings
    var settings: ProjectSettings

    // REFACTOR NOTE: Changed videoDuration from TimeInterval? to CodableCMTime?
    // OLD CODE (commented for debug reference):
    // init(..., videoDuration: TimeInterval? = nil, ...)
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        videoBookmarkData: Data? = nil,
        videoFileName: String? = nil,
        videoDuration: CodableCMTime? = nil,
        status: ProjectStatus = .created,
        transcribedWords: [TranscribedWord] = [],
        speechSegments: [SpeechSegment] = [],
        detectedGaps: [DetectedGap] = [],
        waveformData: WaveformData? = nil,
        repeatedPhrases: [RepeatedPhrase] = [],
        appliedMoves: [AppliedMove] = [],
        projectStyle: ProjectStyle = .default,
        settings: ProjectSettings = ProjectSettings()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.videoBookmarkData = videoBookmarkData
        self.videoFileName = videoFileName
        self.videoDuration = videoDuration
        self.status = status
        self.transcribedWords = transcribedWords
        self.speechSegments = speechSegments
        self.detectedGaps = detectedGaps
        self.waveformData = waveformData
        self.repeatedPhrases = repeatedPhrases
        self.appliedMoves = appliedMoves
        self.projectStyle = projectStyle
        self.settings = settings
    }

    // MARK: - Backward Compatible Decoding

    /// Custom decoder to handle projects saved before appliedMoves was added
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        videoBookmarkData = try container.decodeIfPresent(Data.self, forKey: .videoBookmarkData)
        videoFileName = try container.decodeIfPresent(String.self, forKey: .videoFileName)
        videoDuration = try container.decodeIfPresent(CodableCMTime.self, forKey: .videoDuration)
        status = try container.decode(ProjectStatus.self, forKey: .status)
        transcribedWords = try container.decode([TranscribedWord].self, forKey: .transcribedWords)
        speechSegments = try container.decode([SpeechSegment].self, forKey: .speechSegments)
        detectedGaps = try container.decode([DetectedGap].self, forKey: .detectedGaps)
        waveformData = try container.decodeIfPresent(WaveformData.self, forKey: .waveformData)
        repeatedPhrases = try container.decode([RepeatedPhrase].self, forKey: .repeatedPhrases)
        // Backward compatibility: default to empty array if not present
        appliedMoves = try container.decodeIfPresent([AppliedMove].self, forKey: .appliedMoves) ?? []
        // Backward compatibility: default to .default style if not present
        projectStyle = try container.decodeIfPresent(ProjectStyle.self, forKey: .projectStyle) ?? .default
        settings = try container.decode(ProjectSettings.self, forKey: .settings)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt
        case videoBookmarkData, videoFileName, videoDuration
        case status, transcribedWords, speechSegments, detectedGaps
        case waveformData, repeatedPhrases, appliedMoves, projectStyle, settings
    }

    // MARK: - Video File Access

    /// Resolve the video URL from stored bookmark data
    func resolveVideoURL() -> URL? {
        guard let bookmarkData = videoBookmarkData else { return nil }

        var isStale = false
        do {
            #if os(macOS)
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            #else
            // iOS / Mac Catalyst
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            #endif

            if isStale {
                print("⚠️ Bookmark is stale for video: \(videoFileName ?? "unknown")")
            }

            return url
        } catch {
            print("❌ Failed to resolve video bookmark: \(error)")
            return nil
        }
    }

    /// Create bookmark data from a video URL
    static func createBookmark(from url: URL) -> Data? {
        do {
            #if os(macOS)
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #else
            // iOS / Mac Catalyst - security-scoped URLs from document picker
            // cannot use .minimalBookmark, use empty options instead
            let bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #endif
            return bookmarkData
        } catch {
            print("❌ Failed to create bookmark: \(error)")
            return nil
        }
    }

    // MARK: - Computed Properties

    /// Whether the project has been transcribed
    var isTranscribed: Bool {
        !transcribedWords.isEmpty
    }

    /// Whether gaps have been detected
    var hasGapDetection: Bool {
        !detectedGaps.isEmpty
    }

    /// Number of gaps pending review
    var pendingGapsCount: Int {
        detectedGaps.filter { $0.removalStatus == .pending }.count
    }

    /// Number of duplicate phrases needing review
    var pendingDuplicatesCount: Int {
        repeatedPhrases.filter { $0.needsReview }.count
    }
}

// MARK: - Project Status

enum ProjectStatus: String, Codable, CaseIterable {
    case created            // Just created, no video yet
    case videoImported      // Video file attached
    case transcribing       // Whisper running
    case transcribed        // Transcription complete
    case gapsDetected       // Gap detection complete
    case reviewing          // User is reviewing gaps/duplicates
    case readyToExport      // All reviews complete
    case exported           // FCPXML exported

    var displayName: String {
        switch self {
        case .created: return "Created"
        case .videoImported: return "Video Imported"
        case .transcribing: return "Transcribing..."
        case .transcribed: return "Transcribed"
        case .gapsDetected: return "Gaps Detected"
        case .reviewing: return "In Review"
        case .readyToExport: return "Ready to Export"
        case .exported: return "Exported"
        }
    }

    var icon: String {
        switch self {
        case .created: return "doc"
        case .videoImported: return "film"
        case .transcribing: return "waveform"
        case .transcribed: return "text.alignleft"
        case .gapsDetected: return "scissors"
        case .reviewing: return "eye"
        case .readyToExport: return "checkmark.circle"
        case .exported: return "square.and.arrow.up"
        }
    }
}

// MARK: - Project Settings

struct ProjectSettings: Codable, Hashable {
    // NOTE: Settings are kept as TimeInterval (Double seconds) because they're user-facing.
    // Users configure these in seconds via UI. Convert to CodableCMTime for calculations.

    /// Gaps shorter than this are ignored entirely (in seconds)
    /// At 30fps, one frame ≈ 0.033s. Minimum allows frame-level precision.
    var minimumGapDuration: TimeInterval = 0.1

    /// When cutting a gap, keep this much pause for natural breathing room (in seconds)
    /// Example: A 2s gap becomes 0.3s instead of 0s
    /// Set to 0 to remove gaps completely
    var targetPauseDuration: TimeInterval = 0.3

    /// Gaps longer than this are flagged for review (in seconds)
    var autoReviewThreshold: TimeInterval = 2.0

    /// Silence detection threshold (0.0 - 1.0, relative to max amplitude)
    var silenceThreshold: Double = 0.05

    /// Minimum phrase length for duplicate detection (in words)
    var minPhraseLength: Int = 4

    /// Similarity threshold for duplicate matching (0.0 - 1.0)
    var duplicateSimilarityThreshold: Double = 0.85

    // MARK: - CMTime Conversions

    /// Get minimumGapDuration as CMTime for calculations
    var minimumGapDurationCMTime: CodableCMTime {
        CodableCMTime(seconds: minimumGapDuration)
    }

    /// Get targetPauseDuration as CMTime for calculations
    var targetPauseDurationCMTime: CodableCMTime {
        CodableCMTime(seconds: targetPauseDuration)
    }

    /// Get autoReviewThreshold as CMTime for calculations
    var autoReviewThresholdCMTime: CodableCMTime {
        CodableCMTime(seconds: autoReviewThreshold)
    }

    // MARK: - Computed (CMTime versions)

    // REFACTOR NOTE: Added CMTime versions of these methods
    // OLD CODE (commented for debug reference):
    // func amountToCut(from gapDuration: TimeInterval) -> TimeInterval { ... }
    // func shouldCut(gapDuration: TimeInterval) -> Bool { ... }

    /// The actual amount to cut from a gap (gap duration - target pause)
    func amountToCut(from gapDuration: CodableCMTime) -> CodableCMTime {
        let cutAmount = gapDuration - targetPauseDurationCMTime
        if cutAmount < .zero {
            return .zero
        }
        return cutAmount
    }

    /// Whether a gap should be cut at all (only if it's longer than target pause)
    func shouldCut(gapDuration: CodableCMTime) -> Bool {
        return gapDuration > targetPauseDurationCMTime
    }

    // Legacy TimeInterval versions for backward compatibility during migration
    func amountToCut(fromSeconds gapDuration: TimeInterval) -> TimeInterval {
        let cutAmount = gapDuration - targetPauseDuration
        return max(0, cutAmount)
    }

    func shouldCut(gapDurationSeconds: TimeInterval) -> Bool {
        return gapDurationSeconds > targetPauseDuration
    }
}
