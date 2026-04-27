//
//  CorpusWordCountService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  Computes per-move and per-category word count statistics from the corpus.
//  Derives word counts by extracting sentence slices from video transcripts
//  using each RhetoricalMove's startSentence/endSentence boundaries.
//

import Foundation

// MARK: - Word Count Stats

struct WordCountStats {
    let min: Int
    let max: Int
    let avg: Double
    let sampleCount: Int

    static func from(_ counts: [Int]) -> WordCountStats? {
        guard !counts.isEmpty else { return nil }
        let sorted = counts.sorted()
        let sum = counts.reduce(0, +)
        return WordCountStats(
            min: sorted.first!,
            max: sorted.last!,
            avg: Double(sum) / Double(counts.count),
            sampleCount: counts.count
        )
    }
}

// MARK: - Corpus Word Count Service

enum CorpusWordCountService {

    struct CorpusWordCountResult {
        let perMove: [RhetoricalMoveType: WordCountStats]
        let perCategory: [RhetoricalCategory: WordCountStats]
    }

    /// Compute word count statistics grouped by move type and category.
    /// Iterates corpus sequences once — O(total moves across all videos).
    static func computeStats(
        sequences: [String: RhetoricalSequence],
        corpusVideos: [String: YouTubeVideo]
    ) -> CorpusWordCountResult {

        // Accumulate raw word counts per move type
        var moveWordCounts: [RhetoricalMoveType: [Int]] = [:]

        for (videoId, sequence) in sequences {
            guard let transcript = corpusVideos[videoId]?.transcript,
                  !transcript.isEmpty else { continue }

            let sentences = SentenceParser.parse(transcript)
            guard !sentences.isEmpty else { continue }

            for move in sequence.moves {
                guard let start = move.startSentence,
                      let end = move.endSentence,
                      start >= 0,
                      end < sentences.count,
                      start <= end else { continue }

                let slice = sentences[start...end].joined(separator: " ")
                let wordCount = slice
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .count

                guard wordCount > 0 else { continue }
                moveWordCounts[move.moveType, default: []].append(wordCount)
            }
        }

        // Compute per-move stats
        var perMove: [RhetoricalMoveType: WordCountStats] = [:]
        for (moveType, counts) in moveWordCounts {
            if let stats = WordCountStats.from(counts) {
                perMove[moveType] = stats
            }
        }

        // Compute per-category stats by grouping raw counts
        var categoryWordCounts: [RhetoricalCategory: [Int]] = [:]
        for (moveType, counts) in moveWordCounts {
            categoryWordCounts[moveType.category, default: []].append(contentsOf: counts)
        }

        var perCategory: [RhetoricalCategory: WordCountStats] = [:]
        for (category, counts) in categoryWordCounts {
            if let stats = WordCountStats.from(counts) {
                perCategory[category] = stats
            }
        }

        return CorpusWordCountResult(perMove: perMove, perCategory: perCategory)
    }
}
