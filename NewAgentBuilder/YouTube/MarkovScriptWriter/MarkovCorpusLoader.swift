//
//  MarkovCorpusLoader.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/17/26.
//
//  Thin async wrapper for loading corpus data needed by the Markov Script Writer.
//  Sequences for the transition matrix, JohnnyGists for matching, channels for UI.
//

import Foundation

struct MarkovCorpusLoader {

    // MARK: - Load Rhetorical Sequences (for Markov matrix)

    /// Result from loading corpus data — sequences, titles, and full video objects for provenance lookups.
    struct CorpusLoadResult {
        let sequences: [String: RhetoricalSequence]
        let videoTitles: [String: String]
        let corpusVideos: [String: YouTubeVideo]
    }

    /// Load all rhetorical sequences from analyzed videos, keyed by videoId.
    /// Also captures video titles for pattern provenance lookups.
    static func loadSequences(channelIds: [String]? = nil) async throws -> CorpusLoadResult {
        let service = YouTubeFirebaseService.shared
        var sequences: [String: RhetoricalSequence] = [:]
        var videoTitles: [String: String] = [:]
        var corpusVideos: [String: YouTubeVideo] = [:]

        let channels: [YouTubeChannel]
        if let ids = channelIds, !ids.isEmpty {
            channels = try await withThrowingTaskGroup(of: YouTubeChannel?.self) { group in
                for id in ids {
                    group.addTask { try? await service.getChannel(channelId: id) }
                }
                var result: [YouTubeChannel] = []
                for try await channel in group {
                    if let ch = channel { result.append(ch) }
                }
                return result
            }
        } else {
            channels = try await service.getAllChannels()
        }

        for channel in channels {
            let videos = try await service.getVideos(forChannel: channel.channelId)
            for video in videos {
                if let seq = video.rhetoricalSequence {
                    sequences[video.videoId] = seq
                    videoTitles[video.videoId] = video.title
                    corpusVideos[video.videoId] = video
                }
            }
        }

        return CorpusLoadResult(sequences: sequences, videoTitles: videoTitles, corpusVideos: corpusVideos)
    }

    // MARK: - Load Johnny Gists (for matching, Phase 4)

    /// Delegates to existing GistMatchingService for corpus gist loading.
    static func loadJohnnyGists(channelIds: [String]? = nil) async throws -> [JohnnyGist] {
        try await GistMatchingService().loadJohnnyGists(channelIds: channelIds)
    }

    // MARK: - Available Channels

    /// Load all available YouTube channels for the channel selector UI.
    static func availableChannels() async throws -> [YouTubeChannel] {
        try await YouTubeFirebaseService.shared.getAllChannels()
    }
}
