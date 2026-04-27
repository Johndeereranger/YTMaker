//
//  DuplicateDetectionService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/31/26.
//
//  REFACTORED 2026-02-03: Updated to work with CodableCMTime-based models.
//  Internal calculations use seconds; creates CodableCMTime for model objects.
//

import Foundation
import CoreMedia

/// Service for detecting repeated phrases (duplicate takes) in transcriptions
class DuplicateDetectionService {
    static let shared = DuplicateDetectionService()

    private init() {}

    // MARK: - Noise Token Detection

    /// Tokens to filter out from duplicate detection
    private let noisePatterns: [String] = [
        "[blank", "_audio]", "[music", "[applause", "[laughter",
        "[inaudible", "[crosstalk", "[silence", "blank_audio"
    ]

    /// Check if a word is a noise token (transcription artifact)
    private func isNoiseToken(_ word: String) -> Bool {
        let lower = word.lowercased()
        return noisePatterns.contains { lower.contains($0) }
    }

    // MARK: - Main Detection

    /// Detect repeated phrases in the transcription
    /// - Parameters:
    ///   - words: All transcribed words with timing
    ///   - settings: Project settings (minPhraseLength, similarityThreshold)
    /// - Returns: Array of RepeatedPhrase objects for review
    func detectDuplicates(
        words: [TranscribedWord],
        settings: ProjectSettings
    ) -> [RepeatedPhrase] {
        print("═══════════════════════════════════════════════════════════════")
        print("🔍 DUPLICATE DETECTION STARTING")
        print("═══════════════════════════════════════════════════════════════")
        print("📊 Input: \(words.count) words")
        print("⚙️ Settings:")
        print("   • Min phrase length: \(settings.minPhraseLength) words")
        print("   • Similarity threshold: \(settings.duplicateSimilarityThreshold)")

        guard words.count >= settings.minPhraseLength * 2 else {
            print("❌ Not enough words for duplicate detection")
            return []
        }

        // Sort words by time (using CodableCMTime comparison)
        let sortedWords = words.sorted { $0.startTime < $1.startTime }

        // Create index mapping: filtered index -> original index
        // Filter out noise tokens but keep track of original positions
        var filteredIndices: [Int] = []
        var filteredWords: [TranscribedWord] = []
        var normalizedWords: [String] = []

        for (originalIndex, word) in sortedWords.enumerated() {
            if !isNoiseToken(word.text) {
                filteredIndices.append(originalIndex)
                filteredWords.append(word)
                normalizedWords.append(normalizeWord(word.text))
            } else {
                print("   🚫 Filtered noise token [\(originalIndex)]: '\(word.text)'")
            }
        }

        print("📊 After filtering: \(filteredWords.count) words (removed \(sortedWords.count - filteredWords.count) noise tokens)")

        // Debug: Print first 50 filtered words
        // REFACTOR NOTE: Using startSeconds/endSeconds for display
        print("\n📝 FIRST 50 WORDS (filtered & normalized):")
        for i in 0..<min(50, normalizedWords.count) {
            let word = filteredWords[i]
            let origIdx = filteredIndices[i]
            print("   [\(i)→\(origIdx)] \(formatTime(word.startSeconds))-\(formatTime(word.endSeconds)): '\(word.text)' → '\(normalizedWords[i])'")
        }

        // Find all matching phrase pairs
        var matches = findMatchingPhrases(
            words: filteredWords,
            normalizedWords: normalizedWords,
            minLength: settings.minPhraseLength,
            similarityThreshold: settings.duplicateSimilarityThreshold
        )

        print("\n📋 RAW MATCHES FOUND: \(matches.count)")
        for (i, match) in matches.prefix(20).enumerated() {
            print("   Match \(i + 1) (\(match.range1.count) words):")
            print("      Take 1: \(formatTime(match.startTime1))-\(formatTime(match.endTime1))")
            print("      Take 2: \(formatTime(match.startTime2))-\(formatTime(match.endTime2))")
            print("      Text: '\(match.text1.prefix(60))...'")
        }

        // Deduplicate: keep only the longest match when ranges overlap
        matches = deduplicateMatches(matches)

        print("\n📋 AFTER DEDUPLICATION: \(matches.count) matches")
        for (i, match) in matches.enumerated() {
            print("   Match \(i + 1) (\(match.range1.count) words):")
            print("      Take 1: indices \(match.range1.lowerBound)-\(match.range1.upperBound - 1), \(formatTime(match.startTime1))-\(formatTime(match.endTime1))")
            print("      Take 2: indices \(match.range2.lowerBound)-\(match.range2.upperBound - 1), \(formatTime(match.startTime2))-\(formatTime(match.endTime2))")
        }

        // Convert matches to RepeatedPhrase objects (using filtered word indices)
        let phrases = convertToRepeatedPhrases(matches, filteredWords: filteredWords, originalIndices: filteredIndices)

        print("\n═══════════════════════════════════════════════════════════════")
        print("✅ DUPLICATE DETECTION COMPLETE")
        print("   Found \(phrases.count) repeated phrases")
        print("═══════════════════════════════════════════════════════════════")
        for phrase in phrases {
            print("\n   📌 PHRASE (\(phrase.occurrences.first?.wordRange.count ?? 0) words): \"\(phrase.normalizedPhrase.prefix(50))...\"")
            for (i, occ) in phrase.occurrences.enumerated() {
                // REFACTOR NOTE: Using durationSeconds for display
                print("      Take \(i + 1): \(formatTime(occ.startTime))-\(formatTime(occ.endTime)) (\(String(format: "%.1f", occ.durationSeconds))s)")
            }
        }
        print("═══════════════════════════════════════════════════════════════\n")

        return phrases
    }

    // MARK: - Phrase Matching

    /// Find all pairs of matching phrases
    private func findMatchingPhrases(
        words: [TranscribedWord],
        normalizedWords: [String],
        minLength: Int,
        similarityThreshold: Double
    ) -> [PhraseMatch] {
        var matches: [PhraseMatch] = []
        let wordCount = words.count

        // Build n-gram index for efficient lookup
        // Key: first N words joined, Value: starting indices
        var ngramIndex: [String: [Int]] = [:]
        let indexLength = min(minLength, 3) // Use first 3 words as index key

        print("\n🔧 Building n-gram index (key length: \(indexLength) words)...")

        for i in 0...(wordCount - indexLength) {
            let key = normalizedWords[i..<(i + indexLength)].joined(separator: " ")
            ngramIndex[key, default: []].append(i)
        }

        // Debug: Show n-grams with multiple occurrences
        let duplicateNgrams = ngramIndex.filter { $0.value.count > 1 }
        print("📊 N-gram index stats:")
        print("   • Total unique n-grams: \(ngramIndex.count)")
        print("   • N-grams with duplicates: \(duplicateNgrams.count)")

        if duplicateNgrams.isEmpty {
            print("   ⚠️ NO DUPLICATE N-GRAMS FOUND - nothing to match")
            print("   First 20 n-grams:")
            for (key, indices) in ngramIndex.prefix(20) {
                print("      '\(key)' at indices: \(indices)")
            }
        } else {
            print("\n   📋 All duplicate n-grams:")
            for (key, indices) in duplicateNgrams.sorted(by: { $0.value.count > $1.value.count }) {
                let times = indices.map { formatTime(words[$0].startTime) }
                print("      '\(key)' (\(indices.count)x) at times: \(times.joined(separator: ", "))")
            }
        }

        // Find matches using the index
        var skippedTooClose = 0
        var expandFailed = 0

        for (key, indices) in ngramIndex where indices.count > 1 {
            // For each pair of matching n-grams
            for i in 0..<indices.count {
                for j in (i+1)..<indices.count {
                    let idx1 = indices[i]
                    let idx2 = indices[j]

                    // Skip if too close together (likely same utterance)
                    // REFACTOR NOTE: Using startSeconds for comparison
                    let timeDiff = abs(words[idx1].startSeconds - words[idx2].startSeconds)
                    if timeDiff < 2.0 {
                        skippedTooClose += 1
                        continue
                    }

                    // Expand match to find full phrase extent
                    if let match = expandMatch(
                        idx1: idx1,
                        idx2: idx2,
                        words: words,
                        normalizedWords: normalizedWords,
                        minLength: minLength,
                        similarityThreshold: similarityThreshold
                    ) {
                        // Add all matches; we'll deduplicate later to keep longest
                        matches.append(match)
                        print("   ✓ Match found: '\(key)' expanded to \(match.range1.count) words")
                    } else {
                        expandFailed += 1
                    }
                }
            }
        }

        print("\n📈 Matching stats:")
        print("   • Pairs skipped (too close in time): \(skippedTooClose)")
        print("   • Pairs failed expansion: \(expandFailed)")
        print("   • Raw matches before dedup: \(matches.count)")

        return matches
    }

    /// Expand a match to find the full extent of the repeated phrase
    private func expandMatch(
        idx1: Int,
        idx2: Int,
        words: [TranscribedWord],
        normalizedWords: [String],
        minLength: Int,
        similarityThreshold: Double
    ) -> PhraseMatch? {
        let wordCount = words.count

        // Expand forward
        var matchLength = 0
        var mismatchCount = 0
        let maxMismatches = 2 // Allow some flexibility

        while idx1 + matchLength < wordCount &&
              idx2 + matchLength < wordCount &&
              mismatchCount <= maxMismatches {

            let word1 = normalizedWords[idx1 + matchLength]
            let word2 = normalizedWords[idx2 + matchLength]

            if word1 == word2 || similarity(word1, word2) >= similarityThreshold {
                matchLength += 1
            } else {
                mismatchCount += 1
                if mismatchCount <= maxMismatches {
                    matchLength += 1 // Include mismatched word but count it
                }
            }
        }

        // Remove trailing mismatches
        while matchLength > 0 && mismatchCount > 0 {
            let word1 = normalizedWords[idx1 + matchLength - 1]
            let word2 = normalizedWords[idx2 + matchLength - 1]
            if word1 != word2 && similarity(word1, word2) < similarityThreshold {
                matchLength -= 1
                mismatchCount -= 1
            } else {
                break
            }
        }

        // Check minimum length
        if matchLength < minLength { return nil }

        // Create the match
        let range1 = idx1..<(idx1 + matchLength)
        let range2 = idx2..<(idx2 + matchLength)

        let text1 = words[range1].map(\.text).joined(separator: " ")
        let text2 = words[range2].map(\.text).joined(separator: " ")
        let normalizedPhrase = normalizedWords[range1].joined(separator: " ")

        return PhraseMatch(
            range1: range1,
            range2: range2,
            text1: text1,
            text2: text2,
            normalizedPhrase: normalizedPhrase,
            startTime1: words[idx1].startTime,
            endTime1: words[idx1 + matchLength - 1].endTime,
            startTime2: words[idx2].startTime,
            endTime2: words[idx2 + matchLength - 1].endTime
        )
    }

    // MARK: - Deduplication

    /// Remove overlapping matches, keeping only the longest one
    private func deduplicateMatches(_ matches: [PhraseMatch]) -> [PhraseMatch] {
        guard !matches.isEmpty else { return [] }

        // Sort by length (longest first)
        let sortedByLength = matches.sorted { $0.range1.count > $1.range1.count }

        var kept: [PhraseMatch] = []

        for match in sortedByLength {
            // Check if this match overlaps with any already-kept match
            let overlapsWithKept = kept.contains { existing in
                rangesOverlap(match.range1, existing.range1) ||
                rangesOverlap(match.range1, existing.range2) ||
                rangesOverlap(match.range2, existing.range1) ||
                rangesOverlap(match.range2, existing.range2)
            }

            if !overlapsWithKept {
                kept.append(match)
                print("   ✓ Keeping match: \(match.range1.count) words at \(formatTime(match.startTime1)) & \(formatTime(match.startTime2))")
            } else {
                print("   ✗ Discarding overlapping match: \(match.range1.count) words")
            }
        }

        return kept
    }

    /// Check if two ranges overlap
    private func rangesOverlap(_ r1: Range<Int>, _ r2: Range<Int>) -> Bool {
        return r1.lowerBound < r2.upperBound && r2.lowerBound < r1.upperBound
    }

    // MARK: - Convert to RepeatedPhrases

    /// Convert matches to RepeatedPhrase objects
    private func convertToRepeatedPhrases(
        _ matches: [PhraseMatch],
        filteredWords: [TranscribedWord],
        originalIndices: [Int]
    ) -> [RepeatedPhrase] {
        var phrases: [RepeatedPhrase] = []

        for match in matches {
            // Create occurrences for both instances
            // Map filtered indices back to original indices for the word range
            let origRange1Start = originalIndices[match.range1.lowerBound]
            let origRange1End = originalIndices[match.range1.upperBound - 1] + 1
            let origRange2Start = originalIndices[match.range2.lowerBound]
            let origRange2End = originalIndices[match.range2.upperBound - 1] + 1

            let occurrence1 = PhraseOccurrence(
                id: UUID(),
                segmentId: UUID(),
                wordRange: origRange1Start..<origRange1End,
                startTime: match.startTime1,
                endTime: match.endTime1,
                originalText: match.text1
            )

            let occurrence2 = PhraseOccurrence(
                id: UUID(),
                segmentId: UUID(),
                wordRange: origRange2Start..<origRange2End,
                startTime: match.startTime2,
                endTime: match.endTime2,
                originalText: match.text2
            )

            // Create a truncated phrase for display (first 10 words)
            let displayPhrase: String
            if match.normalizedPhrase.split(separator: " ").count > 10 {
                displayPhrase = match.normalizedPhrase.split(separator: " ").prefix(10).joined(separator: " ") + "..."
            } else {
                displayPhrase = match.normalizedPhrase
            }

            phrases.append(RepeatedPhrase(
                normalizedPhrase: displayPhrase,
                occurrences: [occurrence1, occurrence2]
            ))
        }

        // Sort occurrences within each phrase by time
        for i in 0..<phrases.count {
            phrases[i].occurrences.sort { $0.startTime < $1.startTime }
        }

        return phrases
    }

    // MARK: - Text Utilities

    /// Normalize a word for comparison (lowercase, remove punctuation)
    private func normalizeWord(_ word: String) -> String {
        let lowercased = word.lowercased()
        let cleaned = lowercased.filter { $0.isLetter || $0.isNumber || $0 == "'" }
        return cleaned.isEmpty ? lowercased : cleaned
    }

    /// Calculate similarity between two strings (Levenshtein-based)
    private func similarity(_ s1: String, _ s2: String) -> Double {
        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        let distance = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    /// Levenshtein edit distance
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }

        return matrix[m][n]
    }

    // MARK: - Gap Creation

    /// Create gaps for rejected duplicate occurrences
    /// Call this after user selects which take to keep
    func createGapsForRejectedDuplicates(
        phrase: RepeatedPhrase,
        selectedId: UUID,
        existingGaps: [DetectedGap],
        waveformData: WaveformData? = nil
    ) -> [DetectedGap] {
        var newGaps: [DetectedGap] = []
        let refiner = CutBoundaryRefiner.shared

        for occurrence in phrase.occurrences {
            // Skip the selected occurrence
            if occurrence.id == selectedId { continue }

            // Check if this region already has a gap
            let hasExistingGap = existingGaps.contains { gap in
                gap.startTime <= occurrence.startTime && gap.endTime >= occurrence.endTime
            }

            if !hasExistingGap {
                var refinedStart = occurrence.startTime
                var refinedEnd = occurrence.endTime

                // Refine boundaries using waveform if available
                if let waveform = waveformData {
                    // Search BACKWARD from start to find where silence ends (speech begins)
                    let startResult = refiner.refineCutPoint(
                        whisperTime: occurrence.startTime,
                        waveform: waveform,
                        direction: .backward
                    )
                    if startResult.foundSilence {
                        refinedStart = startResult.refinedTime
                        // REFACTOR NOTE: Using adjustment.seconds for multiplication
                        print("  📍 Refined start: \(formatTimeMs(occurrence.startTime)) → \(formatTimeMs(refinedStart)) (\(String(format: "%+.0f", startResult.adjustment.seconds * 1000))ms)")
                    }

                    // Search FORWARD from end to find where silence begins (speech ends)
                    let endResult = refiner.refineCutPoint(
                        whisperTime: occurrence.endTime,
                        waveform: waveform,
                        direction: .forward
                    )
                    if endResult.foundSilence {
                        refinedEnd = endResult.refinedTime
                        // REFACTOR NOTE: Using adjustment.seconds for multiplication
                        print("  📍 Refined end: \(formatTimeMs(occurrence.endTime)) → \(formatTimeMs(refinedEnd)) (\(String(format: "%+.0f", endResult.adjustment.seconds * 1000))ms)")
                    }
                }

                // Create a gap with refined boundaries
                let gap = DetectedGap(
                    startTime: refinedStart,
                    endTime: refinedEnd,
                    removalStatus: .autoRemoved // Auto-remove rejected duplicates
                )
                newGaps.append(gap)
                print("✂️ Created gap for rejected duplicate: \(formatTimeMs(refinedStart)) - \(formatTimeMs(refinedEnd))")
            }
        }

        return newGaps
    }

    // MARK: - Time Formatting

    // REFACTOR NOTE: Added CodableCMTime overloads for frame-accurate timing

    private func formatTimeMs(_ time: CodableCMTime) -> String {
        formatTimeMs(time.seconds)
    }

    private func formatTimeMs(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, ms)
    }

    private func formatTime(_ time: CodableCMTime) -> String {
        formatTime(time.seconds)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Internal Types

/// A match between two phrase instances
// REFACTOR NOTE: Changed from TimeInterval to CodableCMTime for frame-accurate timing
// OLD CODE (commented for debug reference):
// private struct PhraseMatch {
//     let range1: Range<Int>
//     let range2: Range<Int>
//     let text1: String
//     let text2: String
//     let normalizedPhrase: String
//     let startTime1: TimeInterval
//     let endTime1: TimeInterval
//     let startTime2: TimeInterval
//     let endTime2: TimeInterval
// }
private struct PhraseMatch {
    let range1: Range<Int>  // Word indices for first occurrence
    let range2: Range<Int>  // Word indices for second occurrence
    let text1: String       // Original text of first occurrence
    let text2: String       // Original text of second occurrence
    let normalizedPhrase: String
    let startTime1: CodableCMTime
    let endTime1: CodableCMTime
    let startTime2: CodableCMTime
    let endTime2: CodableCMTime
}
