//
//  CorpusRetriever.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  In-memory index over JohnnyGists for synthesis pipeline retrieval.
//  Built once from loaded JohnnyGists, then queried per-section during synthesis.
//

import Foundation

struct CorpusRetriever {

    // MARK: - Position Zones

    enum PositionZone: String, Codable {
        case start
        case middle
        case end

        /// Determine zone for a chain position
        static func fromChainPosition(index: Int, totalPositions: Int) -> PositionZone {
            if index < 3 { return .start }
            if index >= totalPositions - 3 { return .end }
            return .middle
        }

        /// Determine zone for a corpus gist by its positionPercent (0.0–1.0)
        static func fromPositionPercent(_ percent: Double) -> PositionZone {
            if percent < 0.25 { return .start }
            if percent > 0.75 { return .end }
            return .middle
        }

        /// Proximity score: 1.0 = same zone, 0.5 = adjacent, 0.0 = opposite
        func proximity(to other: PositionZone) -> Double {
            if self == other { return 1.0 }
            if self == .middle || other == .middle { return 0.5 }
            return 0.0 // start vs end
        }
    }

    // MARK: - Tunable Weights

    struct ExampleSelectionWeights: Codable {
        var confidence: Double = 0.4
        var positionProximity: Double = 0.3
        var videoDiversity: Double = 0.3
        static let `default` = ExampleSelectionWeights()
    }

    // MARK: - Transition Example Result

    struct TransitionExampleResult {
        let pairs: [(tail: JohnnyGist, head: JohnnyGist)]
        let isFallback: Bool
        let fallbackType: String? // "category_match", "single_side", or nil
    }

    // MARK: - Internal Indexes

    /// moveLabel (rawValue) → [JohnnyGist]
    private let moveIndex: [String: [JohnnyGist]]

    /// videoId → chunkIndex → JohnnyGist
    private let videoChunkIndex: [String: [Int: JohnnyGist]]

    /// All adjacent pairs from same videos, sorted by videoId + chunkIndex
    private let adjacencyPairs: [(tail: JohnnyGist, head: JohnnyGist)]

    /// moveCategory (rawValue) → [JohnnyGist]
    private let categoryIndex: [String: [JohnnyGist]]

    // MARK: - Init

    init(johnnyGists: [JohnnyGist]) {
        // Build moveIndex
        var mIdx: [String: [JohnnyGist]] = [:]
        for gist in johnnyGists {
            mIdx[gist.moveLabel, default: []].append(gist)
        }
        self.moveIndex = mIdx

        // Build categoryIndex
        var cIdx: [String: [JohnnyGist]] = [:]
        for gist in johnnyGists {
            cIdx[gist.moveCategory, default: []].append(gist)
        }
        self.categoryIndex = cIdx

        // Build videoChunkIndex
        var vcIdx: [String: [Int: JohnnyGist]] = [:]
        for gist in johnnyGists {
            vcIdx[gist.videoId, default: [:]][gist.chunkIndex] = gist
        }
        self.videoChunkIndex = vcIdx

        // Build adjacency pairs: group by videoId, sort by chunkIndex, create adjacent pairs
        var pairs: [(tail: JohnnyGist, head: JohnnyGist)] = []
        let grouped = Dictionary(grouping: johnnyGists, by: \.videoId)
        for (_, gists) in grouped {
            let sorted = gists.sorted { $0.chunkIndex < $1.chunkIndex }
            for i in 0..<(sorted.count - 1) {
                // Only pair genuinely adjacent chunks (chunkIndex differs by 1)
                if sorted[i + 1].chunkIndex == sorted[i].chunkIndex + 1 {
                    pairs.append((tail: sorted[i], head: sorted[i + 1]))
                }
            }
        }
        self.adjacencyPairs = pairs
    }

    // MARK: - Creator Sections for Move Type (Pass 1, Item #6)

    func creatorSections(
        for moveType: RhetoricalMoveType,
        positionZone: PositionZone,
        maxCount: Int = 15,
        weights: ExampleSelectionWeights = .default
    ) -> [JohnnyGist] {
        guard let candidates = moveIndex[moveType.rawValue], !candidates.isEmpty else {
            return []
        }

        // Score each candidate
        let scored: [(gist: JohnnyGist, score: Double)] = candidates.map { gist in
            let confScore = gist.confidence * weights.confidence

            let gistZone = PositionZone.fromPositionPercent(gist.positionPercent)
            let posScore = positionZone.proximity(to: gistZone) * weights.positionProximity

            // videoDiversity is applied post-scoring via deduplication
            let score = confScore + posScore
            return (gist, score)
        }

        // Sort by score descending
        let sorted = scored.sorted { $0.score > $1.score }

        // Deduplicate: max 2 examples from same video
        var videoCount: [String: Int] = [:]
        var result: [JohnnyGist] = []

        for item in sorted {
            let vid = item.gist.videoId
            let count = videoCount[vid, default: 0]
            if count < 2 {
                result.append(item.gist)
                videoCount[vid] = count + 1
            }
            if result.count >= maxCount { break }
        }

        return result
    }

    // MARK: - Preceding Chunk (Pass 1, Item #7)

    func precedingChunk(for gist: JohnnyGist) -> JohnnyGist? {
        guard gist.chunkIndex > 0 else { return nil }
        return videoChunkIndex[gist.videoId]?[gist.chunkIndex - 1]
    }

    // MARK: - Transition Examples (Pass 1, Item #8 & Pass 2)

    func transitionExamples(
        from moveA: RhetoricalMoveType,
        to moveB: RhetoricalMoveType,
        maxCount: Int = 5
    ) -> TransitionExampleResult {

        // 1. Exact match: tail.moveLabel == moveA AND head.moveLabel == moveB
        let exactPairs = adjacencyPairs.filter {
            $0.tail.moveLabel == moveA.rawValue && $0.head.moveLabel == moveB.rawValue
        }
        if !exactPairs.isEmpty {
            let selected = Array(exactPairs.prefix(maxCount))
            return TransitionExampleResult(pairs: selected, isFallback: false, fallbackType: nil)
        }

        // 2. Fallback: category-level match (any move in categoryA → any move in categoryB)
        let catA = moveA.category.rawValue
        let catB = moveB.category.rawValue
        let categoryPairs = adjacencyPairs.filter {
            $0.tail.moveCategory == catA && $0.head.moveCategory == catB
        }
        if !categoryPairs.isEmpty {
            let selected = Array(categoryPairs.prefix(maxCount))
            return TransitionExampleResult(pairs: selected, isFallback: true, fallbackType: "category_match")
        }

        // 3. Fallback: single-side examples (tail of moveA + head of moveB, unpaired)
        let tailExamples = moveIndex[moveA.rawValue]?.suffix(maxCount) ?? []
        let headExamples = moveIndex[moveB.rawValue]?.prefix(maxCount) ?? []

        // Pair them up as best we can (zip, may be uneven)
        var singleSidePairs: [(tail: JohnnyGist, head: JohnnyGist)] = []
        let pairCount = min(tailExamples.count, headExamples.count, maxCount)
        let tailArr = Array(tailExamples)
        let headArr = Array(headExamples)
        for i in 0..<pairCount {
            singleSidePairs.append((tail: tailArr[i], head: headArr[i]))
        }

        return TransitionExampleResult(
            pairs: singleSidePairs,
            isFallback: true,
            fallbackType: singleSidePairs.isEmpty ? nil : "single_side"
        )
    }

    // MARK: - Diagnostics

    var totalGists: Int { moveIndex.values.reduce(0) { $0 + $1.count } }
    var totalAdjacencyPairs: Int { adjacencyPairs.count }
    var moveTypeCoverage: [String: Int] { moveIndex.mapValues(\.count) }
}
