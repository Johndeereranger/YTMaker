//
//  GistMatchingService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/29/26.
//

import Foundation

/// Service for matching rambling gists against Johnny's gists
/// Supports multiple matching strategies: GistA→GistA, GistB→GistB, Combined
class GistMatchingService {

    // MARK: - Load Johnny Gists

    /// Load Johnny gists from analyzed videos
    /// Converts RhetoricalMove data into JohnnyGist format
    func loadJohnnyGists(channelIds: [String]? = nil) async throws -> [JohnnyGist] {
        // Load from Firebase - get videos with rhetorical sequences
        let videosWithChannels = try await loadAnalyzedVideos(channelIds: channelIds)

        var gists: [JohnnyGist] = []

        for (video, channelName) in videosWithChannels {
            guard let sequence = video.rhetoricalSequence else { continue }

            // Load chunks for this video to get full text
            let chunks = try await loadChunksForVideo(videoId: video.videoId)

            for move in sequence.moves {
                guard let chunk = chunks.first(where: { $0.chunkIndex == move.chunkIndex }) else { continue }

                // Only include moves that have enhanced gist data
                guard let gistA = move.gistA, let gistB = move.gistB else { continue }

                let johnnyGist = JohnnyGist(
                    videoId: video.videoId,
                    videoTitle: video.title,
                    channelId: video.channelId,
                    channelName: channelName,
                    chunkIndex: move.chunkIndex,
                    fullChunkText: chunk.fullText,
                    gistA: gistA,
                    gistB: gistB,
                    briefDescription: move.briefDescription,
                    expandedDescription: move.expandedDescription,
                    moveLabel: move.moveType.rawValue,
                    moveCategory: move.moveType.category.rawValue,
                    confidence: move.confidence,
                    telemetry: move.telemetry,
                    positionPercent: chunk.positionInVideo,
                    positionLabel: chunk.positionLabel
                )

                gists.append(johnnyGist)
            }
        }

        return gists
    }

    private func loadAnalyzedVideos(channelIds: [String]?) async throws -> [(video: YouTubeVideo, channelName: String)] {
        // Use YouTubeFirebaseService to load videos
        let service = YouTubeFirebaseService.shared

        if let ids = channelIds, !ids.isEmpty {
            var allVideos: [(YouTubeVideo, String)] = []
            for channelId in ids {
                let channel = try? await service.getChannel(channelId: channelId)
                let channelName = channel?.name ?? "Unknown"
                let videos = try await service.getVideos(forChannel: channelId)
                for video in videos where video.rhetoricalSequence != nil {
                    allVideos.append((video, channelName))
                }
            }
            return allVideos
        } else {
            // Load all channels, then get videos with sequences
            let channels = try await service.getAllChannels()
            var allVideos: [(YouTubeVideo, String)] = []
            for channel in channels {
                let videos = try await service.getVideos(forChannel: channel.channelId)
                for video in videos where video.rhetoricalSequence != nil {
                    allVideos.append((video, channel.name))
                }
            }
            return allVideos
        }
    }

    private func loadChunksForVideo(videoId: String) async throws -> [Chunk] {
        // Load sentence fidelity test and run boundary detection
        let tests = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: videoId)

        guard let latestTest = tests.first else { return [] }

        let boundaryResult = BoundaryDetectionService.shared.detectBoundaries(from: latestTest)
        return boundaryResult.chunks
    }

    // MARK: - Find Matches

    /// Find top K matches for a rambling gist
    func findMatches(
        for ramblingGist: RamblingGist,
        in johnnyGists: [JohnnyGist],
        matchType: GistMatchType,
        topK: Int = 5
    ) async -> [GistMatch] {

        var scoredMatches: [(JohnnyGist, Double)] = []

        for johnnyGist in johnnyGists {
            let score = calculateSimilarity(
                rambling: ramblingGist,
                johnny: johnnyGist,
                matchType: matchType
            )

            if score > 0 {
                scoredMatches.append((johnnyGist, score))
            }
        }

        // Sort by score descending
        scoredMatches.sort { $0.1 > $1.1 }

        // Take top K and convert to GistMatch
        return scoredMatches.prefix(topK).map { (johnny, score) in
            GistMatch(
                ramblingGist: ramblingGist,
                johnnyGist: johnny,
                similarityScore: score,
                matchType: matchType
            )
        }
    }

    /// Calculate similarity between a rambling gist and Johnny gist
    func calculateSimilarity(
        rambling: RamblingGist,
        johnny: JohnnyGist,
        matchType: GistMatchType
    ) -> Double {

        switch matchType {
        case .gistAToGistA:
            return calculateGistASimilarity(rambling.gistA, johnny.gistA)

        case .gistBToGistB:
            return calculateGistBSimilarity(rambling.gistB, johnny.gistB)

        case .combined:
            let aScore = calculateGistASimilarity(rambling.gistA, johnny.gistA)
            let bScore = calculateGistBSimilarity(rambling.gistB, johnny.gistB)
            // Weight B slightly higher as it's more semantic
            return (aScore * 0.4) + (bScore * 0.6)
        }
    }

    /// GistA similarity - stricter, structural
    private func calculateGistASimilarity(_ a: ChunkGistA, _ b: ChunkGistA) -> Double {
        var score = 0.0

        // Frame match (40% weight)
        if a.frame == b.frame {
            score += 0.4
        }

        // Subject overlap (30% weight) - Jaccard similarity
        let subjectScore = jaccardSimilarity(Set(a.subject.map { $0.lowercased() }),
                                              Set(b.subject.map { $0.lowercased() }))
        score += subjectScore * 0.3

        // Premise similarity (30% weight) - simple word overlap
        let premiseScore = wordOverlapSimilarity(a.premise, b.premise)
        score += premiseScore * 0.3

        return score
    }

    /// GistB similarity - more flexible, semantic
    private func calculateGistBSimilarity(_ a: ChunkGistB, _ b: ChunkGistB) -> Double {
        var score = 0.0

        // Frame match (30% weight)
        if a.frame == b.frame {
            score += 0.3
        }

        // Subject overlap (30% weight)
        let subjectScore = jaccardSimilarity(Set(a.subject.map { $0.lowercased() }),
                                              Set(b.subject.map { $0.lowercased() }))
        score += subjectScore * 0.3

        // Premise similarity (40% weight) - higher weight for semantic matching
        let premiseScore = wordOverlapSimilarity(a.premise, b.premise)
        score += premiseScore * 0.4

        return score
    }

    /// Jaccard similarity for sets
    private func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    /// Simple word overlap similarity
    private func wordOverlapSimilarity(_ a: String, _ b: String) -> Double {
        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "be", "been",
                                       "being", "have", "has", "had", "do", "does", "did", "will",
                                       "would", "could", "should", "may", "might", "must", "shall",
                                       "can", "to", "of", "in", "for", "on", "with", "at", "by",
                                       "from", "as", "into", "through", "during", "before", "after",
                                       "above", "below", "between", "under", "again", "further",
                                       "then", "once", "here", "there", "when", "where", "why",
                                       "how", "all", "each", "few", "more", "most", "other", "some",
                                       "such", "no", "nor", "not", "only", "own", "same", "so",
                                       "than", "too", "very", "just", "and", "but", "if", "or",
                                       "because", "until", "while", "this", "that", "these", "those"]

        let wordsA = Set(a.lowercased().components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) })
        let wordsB = Set(b.lowercased().components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) })

        return jaccardSimilarity(wordsA, wordsB)
    }

    // MARK: - Search & Filter

    /// Search Johnny gists with query and filters
    func searchGists(
        query: String,
        filters: GistSearchFilters,
        in gists: [JohnnyGist]
    ) -> [JohnnyGist] {

        var results = gists

        // Apply text search
        if !query.isEmpty {
            let queryLower = query.lowercased()
            results = results.filter { gist in
                gist.briefDescription.lowercased().contains(queryLower) ||
                gist.gistB.premise.lowercased().contains(queryLower) ||
                gist.gistB.subject.joined(separator: " ").lowercased().contains(queryLower) ||
                gist.fullChunkText.lowercased().contains(queryLower) ||
                gist.videoTitle.lowercased().contains(queryLower)
            }
        }

        // Apply filters
        if !filters.channelIds.isEmpty {
            results = results.filter { filters.channelIds.contains($0.channelId) }
        }

        if !filters.moveCategories.isEmpty {
            results = results.filter { filters.moveCategories.contains($0.moveCategory) }
        }

        if !filters.moveLabels.isEmpty {
            results = results.filter { filters.moveLabels.contains($0.moveLabel) }
        }

        if !filters.frames.isEmpty {
            results = results.filter { filters.frames.contains($0.gistA.frame) ||
                                        filters.frames.contains($0.gistB.frame) }
        }

        if filters.positionRange != 0.0...1.0 {
            results = results.filter { filters.positionRange.contains($0.positionPercent) }
        }

        return results
    }

    /// Sort gists by specified option
    func sortGists(_ gists: [JohnnyGist], by option: GistSortOption) -> [JohnnyGist] {
        switch option {
        case .similarityDesc, .similarityAsc:
            // These require a reference gist - return unsorted for now
            return gists

        case .positionAsc:
            return gists.sorted { $0.positionPercent < $1.positionPercent }

        case .positionDesc:
            return gists.sorted { $0.positionPercent > $1.positionPercent }

        case .channelName:
            return gists.sorted { $0.channelName < $1.channelName }

        case .moveCategory:
            return gists.sorted { $0.moveCategory < $1.moveCategory }
        }
    }

    /// Sort matches by similarity
    func sortMatches(_ matches: [GistMatch], ascending: Bool = false) -> [GistMatch] {
        if ascending {
            return matches.sorted { $0.similarityScore < $1.similarityScore }
        } else {
            return matches.sorted { $0.similarityScore > $1.similarityScore }
        }
    }

    // MARK: - Batch Operations

    /// Find matches for all rambling gists at once
    func findAllMatches(
        ramblingGists: [RamblingGist],
        johnnyGists: [JohnnyGist],
        matchType: GistMatchType,
        topK: Int = 5
    ) async -> [UUID: [GistMatch]] {

        var results: [UUID: [GistMatch]] = [:]

        for gist in ramblingGists {
            let matches = await findMatches(
                for: gist,
                in: johnnyGists,
                matchType: matchType,
                topK: topK
            )
            results[gist.id] = matches
        }

        return results
    }

    // MARK: - Statistics

    /// Calculate match statistics
    func calculateMatchStats(matches: [UUID: [GistMatch]]) -> MatchStatistics {
        var strong = 0, moderate = 0, weak = 0, none = 0

        for (_, gistMatches) in matches {
            if let best = gistMatches.first {
                if best.similarityScore >= 0.8 {
                    strong += 1
                } else if best.similarityScore >= 0.6 {
                    moderate += 1
                } else {
                    weak += 1
                }
            } else {
                none += 1
            }
        }

        return MatchStatistics(
            total: matches.count,
            strongMatches: strong,
            moderateMatches: moderate,
            weakMatches: weak,
            noMatches: none
        )
    }
}

// MARK: - Match Statistics

struct MatchStatistics {
    let total: Int
    let strongMatches: Int
    let moderateMatches: Int
    let weakMatches: Int
    let noMatches: Int

    var successRate: Double {
        guard total > 0 else { return 0 }
        return Double(strongMatches + moderateMatches) / Double(total)
    }

    var strongRate: Double {
        guard total > 0 else { return 0 }
        return Double(strongMatches) / Double(total)
    }
}
