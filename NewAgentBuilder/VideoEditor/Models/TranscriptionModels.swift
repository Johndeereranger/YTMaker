//
//  TranscriptionModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/30/26.
//
//  REFACTORED 2026-02-03: Changed from TimeInterval to CMTime for frame-accurate timing.
//  See FCP_EDIT_MODELS.md and FCPXML_KNOWLEDGE.md for rationale.
//

import Foundation
import CoreMedia

// MARK: - Transcribed Word

/// A single word from Whisper transcription with timing info
struct TranscribedWord: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let confidence: Float

    // REFACTOR NOTE: Changed from TimeInterval to CodableCMTime for frame-accurate timing
    // OLD CODE (commented for debug reference):
    // let startTime: TimeInterval
    // let endTime: TimeInterval
    // var duration: TimeInterval { endTime - startTime }
    let startTime: CodableCMTime
    let endTime: CodableCMTime

    var duration: CodableCMTime { endTime - startTime }

    // Convenience accessors for seconds (for display/formatting)
    var startSeconds: Double { startTime.seconds }
    var endSeconds: Double { endTime.seconds }
    var durationSeconds: Double { duration.seconds }

    init(
        id: UUID = UUID(),
        text: String,
        startTime: CodableCMTime,
        endTime: CodableCMTime,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }

    // Convenience initializer from TimeInterval (for migration/Whisper output)
    init(
        id: UUID = UUID(),
        text: String,
        startSeconds: Double,
        endSeconds: Double,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.text = text
        self.startTime = CodableCMTime(seconds: startSeconds)
        self.endTime = CodableCMTime(seconds: endSeconds)
        self.confidence = confidence
    }
}

// MARK: - Speech Segment

/// A continuous block of speech (sequence of words without significant gaps)
struct SpeechSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var wordIds: [UUID]  // References to TranscribedWord ids

    // REFACTOR NOTE: Changed from TimeInterval to CodableCMTime for frame-accurate timing
    // OLD CODE (commented for debug reference):
    // let startTime: TimeInterval
    // let endTime: TimeInterval
    // var duration: TimeInterval { endTime - startTime }
    let startTime: CodableCMTime
    let endTime: CodableCMTime

    var duration: CodableCMTime { endTime - startTime }

    // Convenience accessors for seconds
    var startSeconds: Double { startTime.seconds }
    var endSeconds: Double { endTime.seconds }
    var durationSeconds: Double { duration.seconds }

    /// Get the full transcript text (requires word lookup)
    func transcript(words: [TranscribedWord]) -> String {
        let segmentWords = words.filter { wordIds.contains($0.id) }
        return segmentWords.sorted { $0.startTime < $1.startTime }.map(\.text).joined(separator: " ")
    }

    init(
        id: UUID = UUID(),
        startTime: CodableCMTime,
        endTime: CodableCMTime,
        wordIds: [UUID]
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.wordIds = wordIds
    }

    // Convenience initializer from TimeInterval (for migration)
    init(
        id: UUID = UUID(),
        startSeconds: Double,
        endSeconds: Double,
        wordIds: [UUID]
    ) {
        self.id = id
        self.startTime = CodableCMTime(seconds: startSeconds)
        self.endTime = CodableCMTime(seconds: endSeconds)
        self.wordIds = wordIds
    }
}

// MARK: - Detected Gap

/// A silence/pause between speech segments
struct DetectedGap: Identifiable, Codable, Hashable {
    let id: UUID
    let precedingSegmentId: UUID?
    let followingSegmentId: UUID?

    // REFACTOR NOTE: Changed from TimeInterval to CodableCMTime for frame-accurate timing
    // OLD CODE (commented for debug reference):
    // let startTime: TimeInterval
    // let endTime: TimeInterval
    // var duration: TimeInterval { endTime - startTime }
    let startTime: CodableCMTime
    let endTime: CodableCMTime

    /// User's decision about this gap
    var removalStatus: GapRemovalStatus

    var duration: CodableCMTime { endTime - startTime }

    // Convenience accessors for seconds
    var startSeconds: Double { startTime.seconds }
    var endSeconds: Double { endTime.seconds }
    var durationSeconds: Double { duration.seconds }

    init(
        id: UUID = UUID(),
        startTime: CodableCMTime,
        endTime: CodableCMTime,
        precedingSegmentId: UUID? = nil,
        followingSegmentId: UUID? = nil,
        removalStatus: GapRemovalStatus = .pending
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.precedingSegmentId = precedingSegmentId
        self.followingSegmentId = followingSegmentId
        self.removalStatus = removalStatus
    }

    // Convenience initializer from TimeInterval (for migration)
    init(
        id: UUID = UUID(),
        startSeconds: Double,
        endSeconds: Double,
        precedingSegmentId: UUID? = nil,
        followingSegmentId: UUID? = nil,
        removalStatus: GapRemovalStatus = .pending
    ) {
        self.id = id
        self.startTime = CodableCMTime(seconds: startSeconds)
        self.endTime = CodableCMTime(seconds: endSeconds)
        self.precedingSegmentId = precedingSegmentId
        self.followingSegmentId = followingSegmentId
        self.removalStatus = removalStatus
    }
}

// MARK: - Gap Removal Status

enum GapRemovalStatus: String, Codable, CaseIterable {
    case pending        // Not yet reviewed
    case remove         // User wants this cut
    case keep           // Intentional pause, keep it
    case autoRemoved    // System removed (below threshold)
    case autoKept       // System kept (above threshold or too short)

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .remove: return "Cut"
        case .keep: return "Keep"
        case .autoRemoved: return "Auto-Cut"
        case .autoKept: return "Auto-Keep"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "questionmark.circle"
        case .remove: return "scissors"
        case .keep: return "checkmark.circle"
        case .autoRemoved: return "scissors"
        case .autoKept: return "checkmark.circle"
        }
    }

    var color: String {
        switch self {
        case .pending: return "orange"
        case .remove: return "red"
        case .keep: return "green"
        case .autoRemoved: return "red"
        case .autoKept: return "green"
        }
    }
}

// MARK: - Repeated Phrase (Duplicate Takes)

/// A phrase that appears multiple times in the video (multiple takes)
struct RepeatedPhrase: Identifiable, Codable, Hashable {
    let id: UUID
    let normalizedPhrase: String
    var occurrences: [PhraseOccurrence]
    var selectedOccurrenceId: UUID?  // Which take the user picked

    var needsReview: Bool {
        occurrences.count > 1 && selectedOccurrenceId == nil
    }

    init(
        id: UUID = UUID(),
        normalizedPhrase: String,
        occurrences: [PhraseOccurrence],
        selectedOccurrenceId: UUID? = nil
    ) {
        self.id = id
        self.normalizedPhrase = normalizedPhrase
        self.occurrences = occurrences
        self.selectedOccurrenceId = selectedOccurrenceId
    }
}

// MARK: - Phrase Occurrence

/// A single occurrence of a phrase in the video
struct PhraseOccurrence: Identifiable, Codable, Hashable {
    let id: UUID
    let segmentId: UUID
    let wordRange: Range<Int>  // Which words in the segment (by index)
    let originalText: String  // Original text with punctuation/capitalization

    // REFACTOR NOTE: Changed from TimeInterval to CodableCMTime for frame-accurate timing
    // OLD CODE (commented for debug reference):
    // let startTime: TimeInterval
    // let endTime: TimeInterval
    // var duration: TimeInterval { endTime - startTime }
    let startTime: CodableCMTime
    let endTime: CodableCMTime

    var duration: CodableCMTime { endTime - startTime }

    // Convenience accessors for seconds
    var startSeconds: Double { startTime.seconds }
    var endSeconds: Double { endTime.seconds }
    var durationSeconds: Double { duration.seconds }

    init(
        id: UUID = UUID(),
        segmentId: UUID,
        wordRange: Range<Int>,
        startTime: CodableCMTime,
        endTime: CodableCMTime,
        originalText: String
    ) {
        self.id = id
        self.segmentId = segmentId
        self.wordRange = wordRange
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
    }

    // Convenience initializer from TimeInterval (for migration)
    init(
        id: UUID = UUID(),
        segmentId: UUID,
        wordRange: Range<Int>,
        startSeconds: Double,
        endSeconds: Double,
        originalText: String
    ) {
        self.id = id
        self.segmentId = segmentId
        self.wordRange = wordRange
        self.startTime = CodableCMTime(seconds: startSeconds)
        self.endTime = CodableCMTime(seconds: endSeconds)
        self.originalText = originalText
    }
}

// MARK: - Timeline Item Protocol

/// Protocol for items that can appear on the timeline
/// REFACTOR NOTE: Changed from TimeInterval to CodableCMTime
/// OLD CODE (commented for debug reference):
// protocol TimelineItem {
//     var startTime: TimeInterval { get }
//     var endTime: TimeInterval { get }
//     var duration: TimeInterval { get }
// }
protocol TimelineItem {
    var startTime: CodableCMTime { get }
    var endTime: CodableCMTime { get }
    var duration: CodableCMTime { get }
}

extension TranscribedWord: TimelineItem {}
extension SpeechSegment: TimelineItem {}
extension DetectedGap: TimelineItem {}
