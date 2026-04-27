//
//  LLMBoundaryModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/4/26.
//

import Foundation

// MARK: - LLM Boundary Video Result

/// Persisted result of running the LLM splitter on a single video.
/// Stores the boundary positions, section text, and splitter metadata so that
/// the moves step can pick them up later without re-running the splitter.
///
/// Firebase collection: "llmBoundaryResults"
/// Doc ID: "{channelId}_{videoId}"
struct LLMBoundaryVideoResult: Codable, Identifiable {
    let id: String                          // "{channelId}_{videoId}"
    let channelId: String
    let videoId: String
    let videoTitle: String
    let boundaries: [SectionBoundary]       // Consensus boundaries from splitter (confidence, reasons, sentenceText)
    let chunks: [LLMChunkRecord]            // Self-contained section records with full text
    let totalSentences: Int                 // Original sentence count before exclusion
    let cleanSentenceCount: Int             // After digression exclusion
    let excludedSentenceIndices: [Int]      // Provenance: which sentences were digressions (for auditing, not reconstruction)
    let splitterConfig: LLMSplitterConfig
    let completedAt: Date

    static func docId(channelId: String, videoId: String) -> String {
        "\(channelId)_\(videoId)"
    }

    init(
        channelId: String,
        videoId: String,
        videoTitle: String,
        boundaries: [SectionBoundary],
        chunks: [LLMChunkRecord],
        totalSentences: Int,
        cleanSentenceCount: Int,
        excludedSentenceIndices: [Int],
        splitterConfig: LLMSplitterConfig,
        completedAt: Date = Date()
    ) {
        self.id = Self.docId(channelId: channelId, videoId: videoId)
        self.channelId = channelId
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.boundaries = boundaries
        self.chunks = chunks
        self.totalSentences = totalSentences
        self.cleanSentenceCount = cleanSentenceCount
        self.excludedSentenceIndices = excludedSentenceIndices
        self.splitterConfig = splitterConfig
        self.completedAt = completedAt
    }
}

// MARK: - LLM Chunk Record

/// A lightweight section record storing the chunk's position and full text.
/// Self-contained: the moves step can build Chunk objects from these
/// without re-parsing the transcript.
struct LLMChunkRecord: Codable, Identifiable {
    var id: Int { chunkIndex }

    let chunkIndex: Int
    let startSentence: Int       // 0-indexed into original (pre-exclusion) sentence array
    let endSentence: Int         // 0-indexed, inclusive
    let sentenceCount: Int
    let positionInVideo: Double  // 0.0-1.0
    let text: String             // Full section text
}

// MARK: - LLM Splitter Config

/// Records the parameters used for a splitter run (provenance, not configuration).
struct LLMSplitterConfig: Codable {
    let windowSize: Int          // 10
    let stepSize: Int            // 3
    let temperature: Double      // 0.3
    let promptVariant: String    // "legacy"
    let boundaryCount: Int       // Number of boundaries found
}
