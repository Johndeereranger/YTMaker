//
//  FingerprintDataCollector.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/14/26.
//

import Foundation

/// Collects and buckets rhetorical move data from a creator's videos
/// into fingerprint slots (move label x position).
///
/// Extracts RAW TRANSCRIPT TEXT using sentence ranges — not AI summaries.
struct FingerprintDataCollector {

    /// Minimum number of examples required before a fingerprint can be generated.
    /// User will tune this later.
    var minimumSampleSize: Int = 3

    /// Analyze all videos with rhetorical sequences for a creator and return
    /// availability per slot (move label x position).
    ///
    /// Only includes moves where raw transcript text can be extracted
    /// (requires both `transcript` on the video and `startSentence`/`endSentence` on the move).
    func collectSlotAvailability(
        channelId: String,
        videos: [YouTubeVideo]
    ) -> [FingerprintSlotKey: FingerprintSlotAvailability] {
        var slots: [FingerprintSlotKey: FingerprintSlotAvailability] = [:]

        let videosWithSequences = videos.filter {
            $0.rhetoricalSequence != nil && $0.transcript != nil
        }

        for video in videosWithSequences {
            guard let sequence = video.rhetoricalSequence,
                  let transcript = video.transcript else { continue }
            let seqLength = sequence.moves.count
            guard seqLength >= 1 else { continue }

            // Parse transcript into sentences once per video
            let sentences = SentenceParser.parse(transcript)

            for move in sequence.moves {
                // Only include moves with valid sentence ranges
                guard let rawText = extractTranscriptText(
                    from: move, sentences: sentences
                ) else { continue }

                let slotKey = FingerprintSlotKey.from(
                    chunkIndex: move.chunkIndex,
                    moveType: move.moveType,
                    sequenceLength: seqLength
                )

                // Get or create slot availability
                var slot = slots[slotKey] ?? FingerprintSlotAvailability(
                    slotKey: slotKey,
                    exampleCount: 0,
                    sourceVideoIds: [],
                    sampleTexts: [],
                    sourceVideoTitles: [],
                    existingFingerprints: [:]
                )

                slot.exampleCount += 1
                slot.sampleTexts.append(rawText)
                slot.sourceVideoTitles.append(video.title)

                // Track which video this came from
                if !slot.sourceVideoIds.contains(video.videoId) {
                    slot.sourceVideoIds.append(video.videoId)
                }

                slots[slotKey] = slot
            }
        }

        return slots
    }

    /// Merge existing fingerprints into slot availability data for stale detection.
    /// Groups fingerprints by (slotKey, promptType) into each slot's dict.
    func mergeExistingFingerprints(
        _ fingerprints: [FingerprintDocument],
        into slots: inout [FingerprintSlotKey: FingerprintSlotAvailability]
    ) {
        for fp in fingerprints {
            guard let slotKey = fp.slotKey,
                  let promptType = fp.promptTypeEnum else { continue }
            if var slot = slots[slotKey] {
                slot.existingFingerprints[promptType] = fp
                slots[slotKey] = slot
            }
        }
    }

    /// Extract raw transcript text for a chunk using sentence range mapping.
    /// Returns nil if sentence ranges are missing or out of bounds.
    private func extractTranscriptText(
        from move: RhetoricalMove,
        sentences: [String]
    ) -> String? {
        guard let start = move.startSentence,
              let end = move.endSentence,
              start >= 0,
              end < sentences.count,
              start <= end else {
            return nil
        }

        let chunkSentences = Array(sentences[start...end])
        let text = chunkSentences.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// Summary statistics for a set of slot availabilities.
    static func summarize(_ slots: [FingerprintSlotKey: FingerprintSlotAvailability], minimum: Int) -> SlotSummary {
        let allSlots = Array(slots.values)
        let withData = allSlots.filter { $0.exampleCount > 0 }
        let sufficient = allSlots.filter { $0.hasSufficientData(minimum: minimum) }
        let generated = allSlots.filter { $0.generatedCount > 0 }
        let fullyGenerated = allSlots.filter { $0.isFullyGenerated }
        let stale = allSlots.filter { $0.isStale }
        let totalFingerprints = allSlots.reduce(0) { $0 + $1.generatedCount }

        return SlotSummary(
            totalSlots: RhetoricalMoveType.allCases.count * FingerprintPosition.allCases.count,
            slotsWithData: withData.count,
            slotsWithSufficientData: sufficient.count,
            slotsGenerated: generated.count,
            slotsFullyGenerated: fullyGenerated.count,
            slotsStale: stale.count,
            totalFingerprints: totalFingerprints
        )
    }
}
