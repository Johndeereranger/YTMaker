//
//  OpeningPatternService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//
//  Computes opening patterns from rhetorical sequences.
//  Groups videos by their first N move types (e.g., "Shocking Fact → Stakes Establishment")
//  and returns patterns sorted by frequency.
//
//  Extracted from SequenceBookendsView.computePatterns() for reuse
//  in the opener matcher pipeline.
//

import Foundation

/// A group of videos sharing the same opening move pattern.
struct OpeningPattern {
    let label: String                    // "Shocking Fact → Stakes Establishment"
    let moveTypes: [RhetoricalMoveType]
    let videos: [(videoId: String, title: String)]
    var frequency: Int { videos.count }
}

struct OpeningPatternService {

    /// Compute opening patterns by grouping videos with identical first `depth` move types.
    /// - Parameters:
    ///   - sequences: Video ID → RhetoricalSequence mapping
    ///   - titles: Video ID → title mapping
    ///   - depth: Number of opening moves to match (default 2)
    ///   - minFrequency: Minimum number of videos in a group to include (default 3)
    /// - Returns: Patterns sorted by frequency (most common first), filtered to minFrequency
    static func computeOpeningPatterns(
        sequences: [String: RhetoricalSequence],
        titles: [String: String],
        depth: Int = 2,
        minFrequency: Int = 3
    ) -> [OpeningPattern] {
        var grouping: [String: (moves: [RhetoricalMoveType], videos: [(videoId: String, title: String)])] = [:]

        for (videoId, seq) in sequences {
            let sortedMoves = seq.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            guard sortedMoves.count >= depth else { continue }

            let slice = Array(sortedMoves.prefix(depth))
            let moveTypes = slice.map(\.moveType)
            let key = moveTypes.map(\.displayName).joined(separator: " \u{2192} ")

            if grouping[key] == nil {
                grouping[key] = (moves: moveTypes, videos: [])
            }

            let title = titles[videoId] ?? videoId
            grouping[key]?.videos.append((videoId: videoId, title: title))
        }

        return grouping
            .compactMap { key, value -> OpeningPattern? in
                guard value.videos.count >= minFrequency else { return nil }
                return OpeningPattern(label: key, moveTypes: value.moves, videos: value.videos)
            }
            .sorted { $0.frequency > $1.frequency }
    }
}
