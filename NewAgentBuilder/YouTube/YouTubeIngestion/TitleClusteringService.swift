//
//  TitleClusteringService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import Foundation

/// Service for clustering video titles by content theme using LLM
class TitleClusteringService {

    static let shared = TitleClusteringService()

    private let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

    // MARK: - Main Clustering Function

    /// Cluster video titles into content themes
    /// - Parameters:
    ///   - videos: Array of BrowseVideoMetadata (title + description)
    ///   - existingVideoIds: Video IDs already in our database
    ///   - targetClusters: Suggested number of clusters (5-7)
    /// - Returns: Array of TitleClusters
    func clusterTitles(
        videos: [BrowseVideoMetadata],
        existingVideoIds: Set<String>,
        targetClusters: Int = 6
    ) async throws -> [TitleCluster] {

        // Build the prompt with titles AND descriptions (truncated)
        let videosText = videos.enumerated().map { index, video in
            let truncatedDesc = String(video.description.prefix(200))
            let descSuffix = video.description.count > 200 ? "..." : ""
            return "\(index + 1). \(video.title)\n   Description: \(truncatedDesc)\(descSuffix)"
        }.joined(separator: "\n\n")

        let prompt = """
        Analyze these \(videos.count) YouTube videos and group them by NARRATIVE FORMAT and STRUCTURAL ARCHETYPE, NOT by surface topic.

        VIDEOS:
        \(videosText)

        CRITICAL: We are building a STYLE TAXONOMY for script writing. We need to group videos by HOW they tell stories, not WHAT they're about. Two videos about completely different topics should be in the same cluster if they use the same narrative approach.

        ARCHETYPE EXAMPLES (use these or similar structural categories):
        - "Biographical Investigation" - Deep dive into a PERSON's story, rise/fall, motivations (e.g., Trump biography, cult leader profile, CEO exposé)
        - "Historical Origin Story" - How something BEGAN, tracing roots of an event/movement/place (e.g., why borders exist, how a war started, origin of a religion)
        - "Corporate/Entity Exposé" - Revealing hidden truths about a COMPANY or INSTITUTION (e.g., company scandals, industry manipulation)
        - "Geopolitical Explainer" - Current conflicts, borders, international relations analysis
        - "Consumer/Product Investigation" - Why products are designed a certain way, hidden manipulation
        - "Personal Journey/Travel" - First-person exploration, on-location storytelling
        - "Cultural Phenomenon Analysis" - Explaining trends, movements, social dynamics
        - "Myth-Busting/Misconception" - Correcting common beliefs, revealing hidden truth

        INSTRUCTIONS:
        1. Group by NARRATIVE STRUCTURE and STORYTELLING FORMAT, not topic
        2. A video about Trump AND a video about Mormonism's founder = SAME cluster if both are biographical investigations
        3. Aim for \(targetClusters)-8 clusters based on distinct storytelling approaches
        4. Every video must belong to exactly one cluster
        5. Name clusters by their STRUCTURAL archetype, not topic

        OUTPUT FORMAT (JSON only, no other text):
        {
          "clusters": [
            {
              "theme": "Biographical Investigation",
              "description": "Deep-dive profiles examining a person's story, rise, motivations, and impact",
              "videoNumbers": [1, 5, 12, 23, 45]
            },
            {
              "theme": "Corporate Exposé",
              "description": "Investigative pieces revealing hidden truths about companies and institutions",
              "videoNumbers": [2, 8, 15, 33]
            }
          ]
        }

        Return ONLY the JSON, no explanation.
        """

        let systemPrompt = """
        You are a script structure analyst building a style taxonomy for a YouTube creator.
        Your goal is to identify distinct NARRATIVE FORMATS and STORYTELLING ARCHETYPES.
        Group videos by HOW they tell stories (structure, approach, format) NOT by what topics they cover.
        Two videos about different topics but same narrative style = same cluster.
        Return only valid JSON.
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 4000]
        )

        // Parse the response
        return try parseClusterResponse(
            response: response,
            videos: videos,
            existingVideoIds: existingVideoIds
        )
    }

    // MARK: - Response Parsing

    private func parseClusterResponse(
        response: String,
        videos: [BrowseVideoMetadata],
        existingVideoIds: Set<String>
    ) throws -> [TitleCluster] {

        // Extract JSON from response
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw ClusteringError.invalidResponse("Could not find JSON in response")
        }

        let decoded = try JSONDecoder().decode(ClusterResponse.self, from: data)

        // Convert to TitleCluster objects
        var clusters: [TitleCluster] = []

        for clusterData in decoded.clusters {
            // Map video numbers back to BrowseVideoMetadata
            let clusterVideos = clusterData.videoNumbers.compactMap { number -> BrowseVideoMetadata? in
                let index = number - 1  // Convert from 1-indexed to 0-indexed
                guard index >= 0, index < videos.count else { return nil }
                return videos[index]
            }

            // Determine which videos are already imported
            let existingInCluster = Set(clusterVideos.filter { existingVideoIds.contains($0.videoId) }.map { $0.videoId })

            // Calculate suggested count based on cluster size
            let suggestedCount = max(3, min(15, clusterVideos.count / 5))

            let cluster = TitleCluster(
                theme: clusterData.theme,
                description: clusterData.description,
                videos: clusterVideos,
                existingVideoIds: existingInCluster,
                selectedVideoIds: [],  // User will select
                suggestedCount: suggestedCount
            )

            clusters.append(cluster)
        }

        return clusters.sorted { $0.videos.count > $1.videos.count }
    }

    // MARK: - JSON Extraction

    private func extractJSON(from response: String) -> String? {
        // Try to find JSON in ```json block
        if let jsonBlockRange = response.range(of: "```json"),
           let endBlockRange = response.range(of: "```", range: jsonBlockRange.upperBound..<response.endIndex) {
            let jsonContent = String(response[jsonBlockRange.upperBound..<endBlockRange.lowerBound])
            return jsonContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON in generic ``` block
        if let startRange = response.range(of: "```"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            let content = String(response[startRange.upperBound..<endRange.lowerBound])
            if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Try to find JSON by locating first { and last }
        if let firstBrace = response.firstIndex(of: "{"),
           let lastBrace = response.lastIndex(of: "}") {
            let jsonContent = String(response[firstBrace...lastBrace])
            return jsonContent
        }

        // If already clean JSON
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }

        return nil
    }

    // MARK: - Helper Types

    private struct ClusterResponse: Codable {
        let clusters: [ClusterData]
    }

    private struct ClusterData: Codable {
        let theme: String
        let description: String
        let videoNumbers: [Int]
    }

    enum ClusteringError: Error, LocalizedError {
        case invalidResponse(String)
        case noVideos

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let message): return "Invalid clustering response: \(message)"
            case .noVideos: return "No videos to cluster"
            }
        }
    }
}

