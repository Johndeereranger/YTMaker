//
//  YouTubeAPIService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//
import Foundation

class YouTubeAPIService {
    private let apiKey: String
    private let baseURL = "https://www.googleapis.com/youtube/v3"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Public Methods
    
    /// Extract channel ID from various input formats
    func extractChannelId(from input: String) -> String {
        // Remove whitespace
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle @username
        if trimmed.hasPrefix("@") {
            return String(trimmed.dropFirst())
        }
        
        // Handle full URL
        if let url = URL(string: trimmed), let host = url.host, host.contains("youtube.com") {
            // youtube.com/channel/UCxxxx
            if let channelId = url.pathComponents.first(where: { $0.hasPrefix("UC") && $0.count == 24 }) {
                return channelId
            }
            // youtube.com/@username
            if let handle = url.pathComponents.first(where: { $0.hasPrefix("@") }) {
                return String(handle.dropFirst())
            }
        }
        
        // Assume it's already a channel ID
        return trimmed
    }
    
    /// Fetch channel information
    func fetchChannel(input: String) async throws -> YouTubeChannel {
        let channelId = extractChannelId(from: input)
        
        // If it starts with UC, it's already a channel ID
        let actualChannelId: String
        if channelId.hasPrefix("UC") && channelId.count == 24 {
            actualChannelId = channelId
        } else {
            // It's a handle, need to search for it
            actualChannelId = try await searchForChannel(handle: channelId)
        }
        
        let encodedId = actualChannelId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? actualChannelId
        let urlString = "\(baseURL)/channels?part=snippet,statistics,contentDetails&id=\(encodedId)&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Debug: Print raw response for diagnosis
        if let rawJSON = String(data: data, encoding: .utf8) {
            print("DEBUG: Raw /channels response: \(rawJSON)")
        } else {
            print("DEBUG: Raw data not UTF-8 decodable")
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "YouTubeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        do {
            let apiResponse = try JSONDecoder().decode(YouTubeChannelResponse.self, from: data)
            
            guard let item = apiResponse.items.first else {
                throw NSError(domain: "YouTubeAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Channel not found"])
            }
            
            return YouTubeChannel(
                channelId: item.id,
                name: item.snippet.title,
                handle: item.snippet.customUrl ?? "",
                thumbnailUrl: item.snippet.thumbnails.high.url,
                videoCount: Int(item.statistics.videoCount ?? "0") ?? 0,
                lastSynced: Date(),
                metadata: ChannelMetadata(
                    subscriberCount: Int(item.statistics.subscriberCount ?? "0"),
                    description: item.snippet.description
                )
            )
        } catch {
            print("DEBUG: Decoding error: \(error)")
            throw error
        }
    }
    
    /// Search for channel by handle
    private func searchForChannel(handle: String) async throws -> String {
        let encodedHandle = handle.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? handle
        let urlString = "\(baseURL)/search?part=snippet&type=channel&q=\(encodedHandle)&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Debug: Print raw response
        if let rawJSON = String(data: data, encoding: .utf8) {
            print("DEBUG: Raw /search response: \(rawJSON)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "YouTubeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        struct SearchResponse: Codable {
            let items: [SearchItem]
            struct SearchItem: Codable {
                let id: SearchId
                struct SearchId: Codable {
                    let channelId: String
                }
            }
        }
        
        let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let channelId = searchResponse.items.first?.id.channelId else {
            throw NSError(domain: "YouTubeAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Channel not found"])
        }
        
        return channelId
    }
    /// Fetch all videos from a channel (with pagination)
    func fetchVideos(channelId: String, maxVideos: Int? = nil, onProgress: ((Int) -> Void)? = nil) async throws -> [YouTubeVideo] {
        print("THIS IS FETCHING")
        // Get uploads playlist ID - REQUEST ALL PARTS
        let channelURL = "\(baseURL)/channels?part=snippet,statistics,contentDetails&id=\(channelId)&key=\(apiKey)"
        guard let url = URL(string: channelURL) else { throw URLError(.badURL) }
        
        let (channelData, _) = try await URLSession.shared.data(from: url)
        let channelResponse = try JSONDecoder().decode(YouTubeChannelResponse.self, from: channelData)
        
        guard let uploadsPlaylistId = channelResponse.items.first?.contentDetails.relatedPlaylists.uploads else {
            throw NSError(domain: "YouTubeAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Uploads playlist not found"])
        }
        
        print("📋 Uploads playlist ID: \(uploadsPlaylistId)")
        
        var allVideos: [YouTubeVideo] = []
        var nextPageToken: String? = nil
        var pageCount = 0
        
        repeat {
            pageCount += 1
            var playlistURL = "\(baseURL)/playlistItems?part=contentDetails&maxResults=50&playlistId=\(uploadsPlaylistId)&key=\(apiKey)"
            if let pageToken = nextPageToken {
                playlistURL += "&pageToken=\(pageToken)"
            }
            
            print("📡 Fetching page \(pageCount)...")
            print("DEBUG: Playlist URL: \(playlistURL)")
            
            guard let url = URL(string: playlistURL) else { throw URLError(.badURL) }
            let (playlistData, playlistResponse) = try await URLSession.shared.data(from: url)
            
            // DEBUG: Print raw response
            if let jsonString = String(data: playlistData, encoding: .utf8) {
                print("DEBUG: Raw playlist response (first 1000 chars): \(String(jsonString.prefix(1000)))")
            }
            
            // Check HTTP status
            if let httpResponse = playlistResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorText = String(data: playlistData, encoding: .utf8) ?? "Unknown error"
                print("❌ Playlist API Error: \(errorText)")
                throw NSError(domain: "YouTubeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
            }
            
            let playlistResponseDecoded = try JSONDecoder().decode(YouTubePlaylistResponse.self, from: playlistData)
            let videoIds = playlistResponseDecoded.items.map { $0.contentDetails.videoId }.joined(separator: ",")
            
            print("🎬 Found \(playlistResponseDecoded.items.count) video IDs")
            
            // Get detailed video info
            let videosURL = "\(baseURL)/videos?part=snippet,contentDetails,statistics&id=\(videoIds)&key=\(apiKey)"
            guard let videosURLObj = URL(string: videosURL) else { throw URLError(.badURL) }
            
            print("📡 Fetching video details...")
            let (videosData, videosResponse) = try await URLSession.shared.data(from: videosURLObj)
            
            // Check HTTP status
            if let httpResponse = videosResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorText = String(data: videosData, encoding: .utf8) ?? "Unknown error"
                print("❌ Videos API Error: \(errorText)")
                throw NSError(domain: "YouTubeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
            }
            
            // DEBUG: Print raw response
            if let jsonString = String(data: videosData, encoding: .utf8) {
                print("DEBUG: Raw videos response (first 1000 chars): \(String(jsonString.prefix(1000)))")
            }
            
            let videosResponseDecoded = try JSONDecoder().decode(YouTubeVideosResponse.self, from: videosData)

            print("✅ Decoded \(videosResponseDecoded.items.count) videos")

            let videos = videosResponseDecoded.items.compactMap { item -> YouTubeVideo? in
                // Skip videos without duration
                guard let duration = item.contentDetails.duration else {
                    print("⏭️ Skipping video \(item.id) - no duration yet")
                    return nil
                }
                
                return YouTubeVideo(
                    videoId: item.id,
                    channelId: channelId,
                    title: item.snippet.title,
                    description: item.snippet.description,
                    publishedAt: ISO8601DateFormatter().date(from: item.snippet.publishedAt) ?? Date(),
                    duration: duration,
                    thumbnailUrl: item.snippet.thumbnails.high.url,
                    stats: VideoStats(
                        viewCount: Int(item.statistics.viewCount ?? "0") ?? 0,
                        likeCount: Int(item.statistics.likeCount ?? "0") ?? 0,
                        commentCount: Int(item.statistics.commentCount ?? "0") ?? 0
                    ),
                    createdAt: Date()
                )
            }

            print("✅ Processed \(videos.count) videos with duration")
            
            allVideos.append(contentsOf: videos)
            nextPageToken = playlistResponseDecoded.nextPageToken
            
            print("📊 Total videos fetched so far: \(allVideos.count)")
            
            // Call progress callback
            onProgress?(allVideos.count)
            
            // Check if we've hit the max limit (if specified)
            if let max = maxVideos, allVideos.count >= max {
                print("⚠️ Hit max limit of \(max) videos")
                break
            }
            
        } while nextPageToken != nil
        
        print("✅ Finished fetching \(allVideos.count) videos across \(pageCount) pages")
        return allVideos
    }
    /// Fetch all videos from a channel (up to maxVideos)
    /// Fetch all videos from a channel (with pagination)

}


// Add these methods to your YouTubeAPIService class

extension YouTubeAPIService {
    
    /// Fetch a single video's details by video ID
    func fetchVideoDetails(videoId: String) async throws -> YouTubeVideo {
        let urlString = "\(baseURL)/videos?part=snippet,contentDetails,statistics&id=\(videoId)&key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "YouTubeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        let apiResponse = try JSONDecoder().decode(YouTubeVideosResponse.self, from: data)
        
        guard let item = apiResponse.items.first else {
            throw NSError(domain: "YouTubeAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Video not found"])
        }
        
        guard let duration = item.contentDetails.duration else {
            throw NSError(domain: "YouTubeAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Video is still processing or has no duration"])
        }
        
        return YouTubeVideo(
            videoId: item.id,
            channelId: item.snippet.channelId,
            title: item.snippet.title,
            description: item.snippet.description,
            publishedAt: ISO8601DateFormatter().date(from: item.snippet.publishedAt) ?? Date(),
            duration: duration,
            thumbnailUrl: item.snippet.thumbnails.high.url,
            stats: VideoStats(
                viewCount: Int(item.statistics.viewCount ?? "0") ?? 0,
                likeCount: Int(item.statistics.likeCount ?? "0") ?? 0,
                commentCount: Int(item.statistics.commentCount ?? "0") ?? 0
            ),
            createdAt: Date()
        )
    }
    
    /// Fetch channel by channel ID (not handle)
    func fetchChannelById(channelId: String) async throws -> YouTubeChannel {
        let urlString = "\(baseURL)/channels?part=snippet,statistics,contentDetails&id=\(channelId)&key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "YouTubeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        let apiResponse = try JSONDecoder().decode(YouTubeChannelResponse.self, from: data)
        
        guard let item = apiResponse.items.first else {
            throw NSError(domain: "YouTubeAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Channel not found"])
        }
        
        return YouTubeChannel(
            channelId: item.id,
            name: item.snippet.title,
            handle: item.snippet.customUrl ?? "",
            thumbnailUrl: item.snippet.thumbnails.high.url,
            videoCount: Int(item.statistics.videoCount ?? "0") ?? 0,
            lastSynced: Date(),
            metadata: ChannelMetadata(
                subscriberCount: Int(item.statistics.subscriberCount ?? "0"),
                description: item.snippet.description
            )
        )
    }
}
