//
//  YouTubeFirebaseService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//


import Foundation
import FirebaseFirestore

class YouTubeFirebaseService {
    // Singleton
    static let shared = YouTubeFirebaseService()
    
    private let db = Firestore.firestore()
    
    // Collection names - CONSISTENT throughout
    private let channelsCollection = "youtube_channels"
    private let videosCollection = "youtube_videos"
    
    // Cache properties
    private static var cachedVideos: [YouTubeVideo]?
    private static var cachedChannels: [YouTubeChannel]?
    private static var videosCacheDate: Date?
    private static var channelsCacheDate: Date?
    private static let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Channel Operations
    
    /// Get all channels (used by channel list view)
    func getAllChannels() async throws -> [YouTubeChannel] {
        let snapshot = try await db.collection(channelsCollection)
            .order(by: "lastSynced", descending: true)
            .getDocuments()
        
        // OLD (silently fails):
        // return snapshot.documents.compactMap { try? $0.data(as: YouTubeChannel.self) }
        
        // NEW (throws errors so you can see what's wrong):
        var channels: [YouTubeChannel] = []
        for doc in snapshot.documents {
            do {
                let channel = try doc.data(as: YouTubeChannel.self)
                channels.append(channel)
            } catch {
                print("⚠️ Failed to decode channel \(doc.documentID): \(error)")
                // Still try to continue with other channels
            }
        }
        return channels
    }
    
    /// Fetch all channels with caching (used by search view)
    func fetchAllChannels(forceRefresh: Bool = false) async throws -> [YouTubeChannel] {
        if !forceRefresh,
           let cached = Self.cachedChannels,
           let cacheDate = Self.channelsCacheDate,
           Date().timeIntervalSince(cacheDate) < Self.cacheValidityDuration {
            print("📦 Returning cached channels (\(cached.count) channels)")
            return cached
        }
        
        print("🔄 Fetching fresh channels from Firebase...")
        let snapshot = try await db.collection(channelsCollection).getDocuments()
        
        let channels = try snapshot.documents.compactMap { doc in
            try doc.data(as: YouTubeChannel.self)
        }
        
        Self.cachedChannels = channels
        Self.channelsCacheDate = Date()
        
        print("✅ Fetched and cached \(channels.count) channels")
        return channels
    }
    
    /// Get a single channel by ID
    func getChannel(channelId: String) async throws -> YouTubeChannel? {
        let docRef = db.collection(channelsCollection).document(channelId)
        let document = try await docRef.getDocument()
        return try? document.data(as: YouTubeChannel.self)
    }
    
    /// Fetch a single channel (same as getChannel but with different name for consistency)
    func fetchChannel(channelId: String) async throws -> YouTubeChannel? {
        return try await getChannel(channelId: channelId)
    }
    
    /// Save a single channel with verification
    func saveChannel(_ channel: YouTubeChannel) async throws {
        let docRef = db.collection(channelsCollection).document(channel.channelId)
        
        print("💾 Saving channel: \(channel.name)")
        print("📝 Channel ID: \(channel.channelId)")
        print("📍 Collection: \(channelsCollection)")
        
        do {
            try docRef.setData(from: channel)
            print("✅ Saved channel: \(channel.name)")
            
            // Verify it was saved
            let savedDoc = try await docRef.getDocument()
            if savedDoc.exists {
                print("✅ Verified: Channel exists in Firestore")
            } else {
                print("❌ ERROR: Channel not found after save!")
            }
            
            invalidateChannelsCache()
            
        } catch {
            print("❌ Failed to save channel: \(error)")
            throw error
        }
    }
    
    // MARK: - Video Operations
    
    /// Fetch all videos with caching
    func fetchAllVideos(forceRefresh: Bool = false) async throws -> [YouTubeVideo] {
        if !forceRefresh,
           let cached = Self.cachedVideos,
           let cacheDate = Self.videosCacheDate,
           Date().timeIntervalSince(cacheDate) < Self.cacheValidityDuration {
            print("📦 Returning cached videos (\(cached.count) videos)")
            return cached
        }
        
        print("🔄 Fetching fresh videos from Firebase...")
        let snapshot = try await db.collection(videosCollection).getDocuments()
        
        let videos = try snapshot.documents.compactMap { doc in
            try doc.data(as: YouTubeVideo.self)
        }
        
        Self.cachedVideos = videos
        Self.videosCacheDate = Date()
        
        print("✅ Fetched and cached \(videos.count) videos")
        return videos
    }
    func saveVideoFacts(videoId: String, facts: String) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)
        try await docRef.updateData(["factsText": facts])
        print("✅ Saved facts for video: \(videoId)")
    }
    
    /// Fetch a single video by ID
    func fetchVideo(videoId: String) async throws -> YouTubeVideo? {
        let docRef = db.collection(videosCollection).document(videoId)
        
        do {
            let document = try await docRef.getDocument()
            
            if document.exists {
                return try document.data(as: YouTubeVideo.self)
            } else {
                return nil
            }
        } catch {
            if (error as NSError).code == FirestoreErrorCode.notFound.rawValue {
                return nil
            }
            throw error
        }
    }
    
    /// Get videos for a specific channel
    func getVideos(forChannel channelId: String) async throws -> [YouTubeVideo] {
        let snapshot = try await db.collection(videosCollection)
            .whereField("channelId", isEqualTo: channelId)
            .order(by: "publishedAt", descending: true)
            .getDocuments()
        
        print("📄 Found \(snapshot.documents.count) documents in query")
        
        var videos: [YouTubeVideo] = []
        for doc in snapshot.documents {
            do {
                let video = try doc.data(as: YouTubeVideo.self)
                videos.append(video)
            } catch {
                print("❌ Failed to decode video \(doc.documentID): \(error)")
            }
        }
        return videos
    }
    func saveScriptSummary(videoId: String, summary: ScriptSummary) async throws {
        let data = try Firestore.Encoder().encode(summary)
        try await db.collection(videosCollection).document(videoId).setData([
            "scriptSummary": data
        ], merge: true)
    }
    
    /// Save a single video
    func saveVideo(_ video: YouTubeVideo) async throws {
        let docRef = db.collection(videosCollection).document(video.videoId)
        
        print("💾 Saving video: \(video.title)")
        print("📝 Video ID: \(video.videoId)")
        print("📍 Collection: \(videosCollection)")
        
        do {
            try docRef.setData(from: video)
            print("✅ Saved video: \(video.title)")
            
            invalidateVideosCache()
            try await syncChannelFromVideo(channelId: video.channelId, videoNotHunting: video.notHunting)

            
        } catch {
            print("❌ Failed to save video: \(error)")
            throw error
        }
    }
    
    /// Save multiple videos (batch operation)
    func saveVideos(_ videos: [YouTubeVideo]) async throws {
        let batch = db.batch()
        
        for video in videos {
            let docRef = db.collection(videosCollection).document(video.videoId)
            try batch.setData(from: video, forDocument: docRef)
        }
        
        try await batch.commit()
        print("✅ Saved \(videos.count) videos to Firebase")
        
        invalidateVideosCache()
    }
    
    /// Update video transcript
    func updateVideoTranscript(videoId: String, transcript: String) async throws {
        let docRef = db.collection(videosCollection).document(videoId)
        try await docRef.updateData([
            "transcript": transcript
        ])
        print("✅ Updated transcript for video: \(videoId)")
        
        invalidateVideosCache()
    }
    /// Update video summary
    func updateVideoSummary(videoId: String, summary: String) async throws {
        let docRef = db.collection(videosCollection).document(videoId)
        try await docRef.updateData([
            "summaryText": summary
        ])
        print("✅ Updated summary for video: \(videoId)")
        
        invalidateVideosCache()
    }

    
    // MARK: - Cache Management
    
    func clearCache() {
        Self.cachedVideos = nil
        Self.cachedChannels = nil
        Self.videosCacheDate = nil
        Self.channelsCacheDate = nil
        print("🗑️ Cache cleared")
    }
    
    func invalidateVideosCache() {
        Self.cachedVideos = nil
        Self.videosCacheDate = nil
        print("🗑️ Videos cache invalidated")
    }
    
    func invalidateChannelsCache() {
        Self.cachedChannels = nil
        Self.channelsCacheDate = nil
        print("🗑️ Channels cache invalidated")
    }
    //MARK: - Update Pin Status
    
    /// Update channel pin status
    func updateChannelPinStatus(channelId: String, isPinned: Bool) async throws {
        try await db.collection(channelsCollection).document(channelId).updateData([
            "isPinned": isPinned
        ])
        invalidateChannelsCache()
    }

    /// Update channel hunting status directly
    func updateChannelHuntingStatus(channelId: String, notHunting: Bool) async throws {
        try await db.collection(channelsCollection).document(channelId).updateData([
            "notHunting": notHunting
        ])
        invalidateChannelsCache()
    }

    /// Update channel sentence analysis status
    func updateChannelSentenceAnalysisStatus(channelId: String, hasSentenceAnalysis: Bool) async throws {
        try await db.collection(channelsCollection).document(channelId).updateData([
            "hasSentenceAnalysis": hasSentenceAnalysis
        ])
        invalidateChannelsCache()
        print("✅ Updated channel \(channelId) hasSentenceAnalysis = \(hasSentenceAnalysis)")
    }

    /// IMPORTANT: Call this after saving a video to sync channel hunting status
    /// This updates the channel based on the video you just saved
    func syncChannelFromVideo(channelId: String, videoNotHunting: Bool) async throws {
        // Get current channel
        guard let channel = try await getChannel(channelId: channelId) else {
            print("⚠️ Channel \(channelId) not found, cannot sync")
            return
        }
        
        // If video is hunting (notHunting = false), channel must be hunting
        if !videoNotHunting {
            if channel.notHunting {
                try await updateChannelHuntingStatus(channelId: channelId, notHunting: false)
                print("🔄 Updated channel \(channelId) to hunting (has hunting video)")
            }
        }
        // If video is notHunting, we don't change channel status
        // (channel could still have other hunting videos)
    }
    
    // MARK: - New Field Updates

    /// Update a single field on a video document
    func updateVideoField(videoId: String, field: String, value: Any?) async throws {
        let docRef = db.collection(videosCollection).document(videoId)
        
        if let value = value {
            try await docRef.updateData([field: value])
        } else {
            // If value is nil, delete the field
            try await docRef.updateData([field: FieldValue.delete()])
        }
        
        invalidateVideosCache()
    }

    /// Update hook
    func updateVideoHook(videoId: String, hook: String?) async throws {
        try await updateVideoField(videoId: videoId, field: "hook", value: hook)
    }

    /// Update hook type
    func updateVideoHookType(videoId: String, hookType: String?) async throws {
        try await updateVideoField(videoId: videoId, field: "hookType", value: hookType)
    }

    /// Update intro
    func updateVideoIntro(videoId: String, intro: String?) async throws {
        try await updateVideoField(videoId: videoId, field: "intro", value: intro)
    }

    /// Update notes
    func updateVideoNotes(videoId: String, notes: String?) async throws {
        try await updateVideoField(videoId: videoId, field: "notes", value: notes)
    }

    /// Update video type
    func updateVideoType(videoId: String, videoType: String?) async throws {
        try await updateVideoField(videoId: videoId, field: "videoType", value: videoType)
    }

    /// Update notHunting flag
    func updateNotHunting(videoId: String, notHunting: Bool) async throws {
        try await updateVideoField(videoId: videoId, field: "notHunting", value: notHunting)
        
        // Get the video to find its channelId
        if let video = try await fetchVideo(videoId: videoId) {
            try await syncChannelFromVideo(channelId: video.channelId, videoNotHunting: notHunting)
        }
    }

    /// Update facts
    func updateVideoFacts(videoId: String, facts: String?) async throws {
        try await updateVideoField(videoId: videoId, field: "factsText", value: facts)
    }

    /// Save rhetorical sequence for a video
    func saveRhetoricalSequence(videoId: String, sequence: RhetoricalSequence) async throws {
        let docRef = db.collection(videosCollection).document(videoId)

        // Encode sequence to dictionary
        let encoder = Firestore.Encoder()
        let sequenceData = try encoder.encode(sequence)

        try await docRef.updateData(["rhetoricalSequence": sequenceData])
        invalidateVideosCache()
    }

    /// Batch save rhetorical sequences for multiple videos
    func saveRhetoricalSequencesBatch(sequences: [String: RhetoricalSequence]) async throws {
        let encoder = Firestore.Encoder()

        // Process in batches of 500 (Firestore limit)
        let sequenceArray = Array(sequences)
        for chunk in stride(from: 0, to: sequenceArray.count, by: 500) {
            let batch = db.batch()
            let end = min(chunk + 500, sequenceArray.count)

            for i in chunk..<end {
                let (videoId, sequence) = sequenceArray[i]
                let docRef = db.collection(videosCollection).document(videoId)
                let sequenceData = try encoder.encode(sequence)
                batch.updateData(["rhetoricalSequence": sequenceData], forDocument: docRef)
            }

            try await batch.commit()
        }

        invalidateVideosCache()
    }

    /// Clear rhetoricalSequence field from a single video
    func clearRhetoricalSequence(forVideoId videoId: String) async throws {
        let docRef = db.collection(videosCollection).document(videoId)
        try await docRef.updateData(["rhetoricalSequence": FieldValue.delete()])
        invalidateVideosCache()
        print("🗑️ Cleared rhetoricalSequence for video: \(videoId)")
    }

    /// Clear rhetoricalSequence field from all videos in the database
    func clearAllRhetoricalSequences() async throws -> Int {
        let snapshot = try await db.collection(videosCollection).getDocuments()

        var clearedCount = 0

        // Process in batches of 500 (Firestore limit)
        let docs = snapshot.documents.filter { doc in
            doc.data()["rhetoricalSequence"] != nil
        }

        for chunk in stride(from: 0, to: docs.count, by: 500) {
            let batch = db.batch()
            let end = min(chunk + 500, docs.count)

            for i in chunk..<end {
                let docRef = docs[i].reference
                batch.updateData(["rhetoricalSequence": FieldValue.delete()], forDocument: docRef)
                clearedCount += 1
            }

            try await batch.commit()
        }

        invalidateVideosCache()
        print("🗑️ Cleared rhetoricalSequence from \(clearedCount) videos")
        return clearedCount
    }

    /// Verify channels using already-loaded data (no Firebase queries)
    /// Pass in channels and videos you already have in memory
    func verifyChannelsHuntingStatus(channels: [YouTubeChannel], videos: [YouTubeVideo]) async {
        Task.detached(priority: .background) {
            var updatedCount = 0
            
            for channel in channels {
                // Skip if already notHunting
                if channel.notHunting {
                    continue
                }
                
                // Get this channel's videos from the loaded videos
                let channelVideos = videos.filter { $0.channelId == channel.channelId }
                
                // Check if ALL videos are notHunting
                let allVideosNotHunting = !channelVideos.isEmpty && channelVideos.allSatisfy { $0.notHunting }
                
                if allVideosNotHunting {
                    // Update Firebase only
                    try? await self.updateChannelHuntingStatus(channelId: channel.channelId, notHunting: true)
                    print("✅ Fixed channel \(channel.name) -> notHunting = true")
                    updatedCount += 1
                }
            }
            
            print("🎉 Background verification complete. Updated \(updatedCount) channels.")
        }
    }
    

    // MARK: - Stats Update Methods

    /// Update stats for a single video from YouTube API
    func updateVideoStats(videoId: String) async throws -> YouTubeVideo {
        print("🔄 Updating stats for video: \(videoId)")
        
        // 1. Get existing video from Firebase
        guard var existingVideo = try await fetchVideo(videoId: videoId) else {
            throw NSError(domain: "Firebase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Video not found"])
        }
        
        // 2. Fetch fresh stats from YouTube API
        let apiService = YouTubeAPIService(apiKey: YouTubeAPIKeyManager.shared.apiKey)
        let freshVideo = try await apiService.fetchVideoDetails(videoId: videoId)
        
        // 3. Create snapshot of current stats
        let snapshot = ViewSnapshot(
            date: Date(),
            viewCount: freshVideo.stats.viewCount,
            likeCount: freshVideo.stats.likeCount
        )
        
        // 4. Update view history
        var history = existingVideo.stats.viewHistory ?? []
        history.append(snapshot)
        
        // Keep only last 30 snapshots to avoid bloat
        if history.count > 30 {
            history = Array(history.suffix(30))
        }
        
        // 5. Create updated video with new stats
        let updatedVideo = YouTubeVideo(
            videoId: existingVideo.videoId,
            channelId: existingVideo.channelId,
            title: freshVideo.title, // Update title in case it changed
            description: freshVideo.description,
            publishedAt: existingVideo.publishedAt,
            duration: existingVideo.duration,
            thumbnailUrl: freshVideo.thumbnailUrl,
            stats: VideoStats(
                viewCount: freshVideo.stats.viewCount,
                likeCount: freshVideo.stats.likeCount,
                commentCount: freshVideo.stats.commentCount,
                viewHistory: history
            ),
            createdAt: existingVideo.createdAt,
            transcript: existingVideo.transcript,
            factsText: existingVideo.factsText,
            summaryText: existingVideo.summaryText,
            notHunting: existingVideo.notHunting,
            notes: existingVideo.notes,
            videoType: existingVideo.videoType,
            hook: existingVideo.hook,
            hookType: existingVideo.hookType,
            intro: existingVideo.intro
        )
        
        // 6. Save back to Firebase
        try await updateVideoField(videoId: videoId, field: "stats", value: [
            "viewCount": updatedVideo.stats.viewCount,
            "likeCount": updatedVideo.stats.likeCount,
            "commentCount": updatedVideo.stats.commentCount,
            "viewHistory": updatedVideo.stats.viewHistory?.map { snapshot in
                [
                    "date": Timestamp(date: snapshot.date),
                    "viewCount": snapshot.viewCount,
                    "likeCount": snapshot.likeCount
                
                ]
            } ?? []
        ])
        
        print("✅ Updated video stats: \(updatedVideo.title)")
        print("   Views: \(updatedVideo.stats.viewCount) (history: \(history.count) snapshots)")
        
        return updatedVideo
    }
    
    // ADD THIS TO YouTubeFirebaseService

    /// Refresh a channel's metadata from YouTube API
    func refreshChannel(channelId: String) async throws -> YouTubeChannel {
        print("🔄 Refreshing channel: \(channelId)")
        
        // 1. Fetch fresh data from YouTube API
        let apiService = YouTubeAPIService(apiKey: YouTubeAPIKeyManager.shared.apiKey)
        let freshChannel = try await apiService.fetchChannelById(channelId: channelId)
        
        // 2. Get existing channel to preserve isPinned and notHunting
        if let existingChannel = try await getChannel(channelId: channelId) {
            // Create updated channel with preserved flags
            let updatedChannel = YouTubeChannel(
                channelId: freshChannel.channelId,
                name: freshChannel.name,
                handle: freshChannel.handle,
                thumbnailUrl: freshChannel.thumbnailUrl,
                videoCount: freshChannel.videoCount,
                lastSynced: Date(), // ✅ Fresh timestamp
                metadata: freshChannel.metadata,
                isPinned: existingChannel.isPinned,     // ✅ Preserve pin status
                notHunting: existingChannel.notHunting  // ✅ Preserve hunting status
            )
            
            // 3. Save to Firebase
            try await saveChannel(updatedChannel)
            
            print("✅ Refreshed channel: \(updatedChannel.name)")
            return updatedChannel
        } else {
            // New channel, save as-is
            try await saveChannel(freshChannel)
            print("✅ Added new channel: \(freshChannel.name)")
            return freshChannel
        }
    }

    /// Update all videos for a channel
    func updateChannelVideos(channelId: String) async throws -> (updated: [YouTubeVideo], new: [YouTubeVideo]) {
        print("🔄 Updating channel: \(channelId)")
        
        let apiService = YouTubeAPIService(apiKey: YouTubeAPIKeyManager.shared.apiKey)
        
        // ✅ 1. Update channel metadata first
        let freshChannelData = try await apiService.fetchChannelById(channelId: channelId)
        
        // Get existing channel to preserve flags
        if let existingChannel = try await getChannel(channelId: channelId) {
            let updatedChannel = YouTubeChannel(
                channelId: freshChannelData.channelId,
                name: freshChannelData.name,
                handle: freshChannelData.handle,
                thumbnailUrl: freshChannelData.thumbnailUrl,
                videoCount: freshChannelData.videoCount,
                lastSynced: Date(),
                metadata: freshChannelData.metadata,  // ✅ Fresh subscriber count
                isPinned: existingChannel.isPinned,
                notHunting: existingChannel.notHunting
            )
            
            try await saveChannel(updatedChannel)
            print("✅ Updated channel metadata: \(updatedChannel.name)")
            print("   Subscribers: \(updatedChannel.metadata?.subscriberCount ?? 0)")
        }
        
        // 1. Fetch all videos from YouTube API
        let freshVideos = try await apiService.fetchVideos(channelId: channelId, maxVideos: nil)
        print("📹 Fetched \(freshVideos.count) videos from YouTube")
        
        // 2. Get existing videos from Firebase
        let existingVideos = try await getVideos(forChannel: channelId)
        let existingVideoIds = Set(existingVideos.map { $0.videoId })
        print("💾 Found \(existingVideos.count) existing videos in Firebase")
        
        var updatedVideos: [YouTubeVideo] = []
        var newVideos: [YouTubeVideo] = []
        
        // 3. Process each video
        for freshVideo in freshVideos {
            if existingVideoIds.contains(freshVideo.videoId) {
                // Update existing video
                do {
                    let updated = try await updateVideoStats(videoId: freshVideo.videoId)
                    updatedVideos.append(updated)
                } catch {
                    print("⚠️ Failed to update \(freshVideo.videoId): \(error)")
                }
            } else {
                // New video - save it
                try await saveVideo(freshVideo)
                newVideos.append(freshVideo)
                print("✅ Added new video: \(freshVideo.title)")
            }
        }
        
        // 4. Update channel's lastSynced and videoCount
        try await db.collection(channelsCollection).document(channelId).updateData([
            "lastSynced": Timestamp(date: Date()),
            "videoCount": freshVideos.count
        ])
        
        invalidateChannelsCache()
        
        print("✅ Channel update complete:")
        print("   Updated: \(updatedVideos.count) videos")
        print("   New: \(newVideos.count) videos")
        
        return (updated: updatedVideos, new: newVideos)
    }

    /// Batch update stats for multiple videos
    func batchUpdateVideoStats(videoIds: [String]) async throws -> [YouTubeVideo] {
        var updatedVideos: [YouTubeVideo] = []
        
        for videoId in videoIds {
            do {
                let updated = try await updateVideoStats(videoId: videoId)
                updatedVideos.append(updated)
            } catch {
                print("⚠️ Failed to update \(videoId): \(error)")
            }
        }
        
        return updatedVideos
    }
    
    
    // MARK: - Script Breakdown Operations

    /// Save script breakdown
    func saveScriptBreakdown(videoId: String, breakdown: ScriptBreakdown) async throws {
        let docRef = db.collection(videosCollection).document(videoId)
        let dictionary = scriptBreakdownToFirebase(breakdown)
        print(#function,dictionary)
        try await docRef.updateData([
            "scriptBreakdown": dictionary
        ])
        print("✅ Saved script breakdown for video: \(videoId)")
        invalidateVideosCache()
    }

    /// Load script breakdown
    func loadScriptBreakdown(videoId: String) async throws -> ScriptBreakdown? {
        let docRef = db.collection(videosCollection).document(videoId)
        let document = try await docRef.getDocument()
        
        guard let data = document.data(),
              let breakdownData = data["scriptBreakdown"] as? [String: Any] else {
            return nil
        }
        
        return firebaseToScriptBreakdown(breakdownData)
    }
    
    // Add to YouTubeFirebaseService

    func loadPinnedChannels() async throws -> [YouTubeChannel] {
        let snapshot = try await db.collection("channels")
            .whereField("isPinned", isEqualTo: true)
            .order(by: "name")
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: YouTubeChannel.self)
        }
    }

    func loadVideosForPinnedChannels() async throws -> [YouTubeVideo] {
        // Get pinned channels
        let pinnedChannels = try await loadPinnedChannels()
        let pinnedChannelIds = pinnedChannels.map { $0.channelId }
        
        guard !pinnedChannelIds.isEmpty else {
            return []
        }
        
        // Firebase 'in' queries are limited to 10 items, so batch
        let channelIdBatches = pinnedChannelIds.chunked(into: 10)
        var allVideos: [YouTubeVideo] = []
        
        for batch in channelIdBatches {
            let snapshot = try await db.collection("videos")
                .whereField("channelId", in: batch)
                .order(by: "publishedAt", descending: true)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { doc in
                try? doc.data(as: YouTubeVideo.self)
            }
            allVideos.append(contentsOf: videos)
        }
        
        return allVideos
    }

  
    func loadAllChannels() async throws -> [YouTubeChannel] {
        let snapshot = try await db.collection("channels")
            .order(by: "name")
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: YouTubeChannel.self)
        }
    }
    
    // MARK: - A1a Analysis Operations

    /// Save A1a analysis results to video doc
    func saveVideoAnalysis(videoId: String, videoSummary: String, logicSpine: LogicSpineData, bridgePoints: [BridgePoint], validationStatus: ValidationStatus, validationIssues: [ValidationIssue]?, extractionDate: Date) async throws {
        let docRef = db.collection(videosCollection).document(videoId)
        
        var dict: [String: Any] = [
            "videoSummary": videoSummary,
            "logicSpine": [
                "chain": logicSpine.chain,
                "causalLinks": logicSpine.causalLinks.map { link in
                    [
                        "from": link.from,
                        "to": link.to,
                        "connection": link.connection
                    ]
                }
            ],
            "bridgePoints": bridgePoints.map { point in
                [
                    "text": point.text,
                    "belongsTo": point.belongsTo,
                    "timestamp": point.timestamp
                ]
            },
            "validationStatus": validationStatus.rawValue,
            "extractionDate": Timestamp(date: extractionDate)
        ]
        
        if let issues = validationIssues {
            dict["validationIssues"] = issues.map { issue in
                [
                    "severity": issue.severity.rawValue,
                    "type": issue.type.rawValue,
                    "message": issue.message
                ]
            }
        }
        
        try await docRef.setData(dict, merge: true)
        print("✅ Saved A1a analysis for video: \(videoId)")
        invalidateVideosCache()
    }

    private func parseLogicSpine(_ data: [String: Any]) -> LogicSpineData? {
        guard let chain = data["chain"] as? [String] else { return nil }
        
        let linksArray = data["causalLinks"] as? [[String: Any]] ?? []
        let causalLinks = linksArray.compactMap { linkDict -> CausalLink? in
            guard let from = linkDict["from"] as? String,
                  let to = linkDict["to"] as? String,
                  let connection = linkDict["connection"] as? String else {
                return nil
            }
            return CausalLink(from: from, to: to, connection: connection)
        }
        
        return LogicSpineData(chain: chain, causalLinks: causalLinks)
    }

    private func parseBridgePoints(_ data: [[String: Any]]) -> [BridgePoint] {
        return data.compactMap { pointDict -> BridgePoint? in
            guard let text = pointDict["text"] as? String,
                  let belongsTo = pointDict["belongsTo"] as? [String],
                  let timestamp = pointDict["timestamp"] as? Int else {
                return nil
            }
            return BridgePoint(text: text, belongsTo: belongsTo, timestamp: timestamp)
        }
    }

    // MARK: - Script Breakdown Conversio
    
//    private func scriptBreakdownToFirebase(_ breakdown: ScriptBreakdown) -> [String: Any] {
//        var data: [String: Any] = [
//            "lastEditedDate": Timestamp(date: breakdown.lastEditedDate)
//        ]
//        
//        data["sentences"] = breakdown.sentences.map { sentence in
//            [
//                "id": sentence.id.uuidString,
//                "text": sentence.text,
//                "isSelected": sentence.isSelected,
//                "isTyped": sentence.isTyped
//            ]
//        }
//        
//        data["sections"] = breakdown.sections.map { section in
//            var sectionDict: [String: Any] = [
//                "id": section.id.uuidString,
//                "name": section.name,
//                "startSentenceId": section.startSentenceId.uuidString,
//                "endSentenceId": section.endSentenceId?.uuidString as Any,
//                "patternIds": section.patternIds.map { $0.uuidString }
//            ]
//            
//            // Byron's fields
//            if let rawNotes = section.rawNotes {
//                sectionDict["rawNotes"] = rawNotes
//            }
//            if let beliefInstalled = section.beliefInstalled {
//                sectionDict["beliefInstalled"] = beliefInstalled
//            }
//            
//            // AI fields
//            if let aiTitle = section.aiTitle {
//                sectionDict["aiTitle"] = aiTitle
//            }
//            if let aiSummary = section.aiSummary {
//                sectionDict["aiSummary"] = aiSummary
//            }
//            if let aiStrategicPurpose = section.aiStrategicPurpose {
//                sectionDict["aiStrategicPurpose"] = aiStrategicPurpose
//            }
//            if let aiMechanism = section.aiMechanism {
//                sectionDict["aiMechanism"] = aiMechanism
//            }
//            if let aiInputsRecipe = section.aiInputsRecipe {
//                sectionDict["aiInputsRecipe"] = aiInputsRecipe
//            }
//            if let aiBSFlags = section.aiBSFlags {
//                sectionDict["aiBSFlags"] = aiBSFlags
//            }
//            if let aiArchetype = section.aiArchetype {
//                sectionDict["aiArchetype"] = aiArchetype
//            }
//            
//            return sectionDict
//        }
//        
//        data["allMarkedPatterns"] = breakdown.allMarkedPatterns.map { pattern in
//            [
//                "id": pattern.id.uuidString,
//                "type": pattern.type.rawValue,
//                "sentenceIds": pattern.sentenceIds.map { $0.uuidString },
//                "note": pattern.note as Any,
//                "sectionId": pattern.sectionId?.uuidString as Any,
//                "extractedToPlaybook": pattern.extractedToPlaybook
//            ]
//        }
//        
//        return data
//    }
//
//    private func firebaseToScriptBreakdown(_ data: [String: Any]) -> ScriptBreakdown? {
//        var breakdown = ScriptBreakdown()
//        
//        if let timestamp = data["lastEditedDate"] as? Timestamp {
//            breakdown.lastEditedDate = timestamp.dateValue()
//        }
//        
//        if let sentencesArray = data["sentences"] as? [[String: Any]] {
//            breakdown.sentences = sentencesArray.compactMap { sentenceData -> ScriptSentence? in
//                guard let idString = sentenceData["id"] as? String,
//                      let id = UUID(uuidString: idString),
//                      let text = sentenceData["text"] as? String else {
//                    return nil
//                }
//                
//                return ScriptSentence(
//                    id: id,
//                    text: text,
//                    isSelected: sentenceData["isSelected"] as? Bool ?? false,
//                    isTyped: sentenceData["isTyped"] as? Bool ?? false
//                )
//            }
//        }
//        
//        if let sectionsArray = data["sections"] as? [[String: Any]] {
//            breakdown.sections = sectionsArray.compactMap { sectionData -> OutlineSection? in
//                guard let idString = sectionData["id"] as? String,
//                      let id = UUID(uuidString: idString),
//                      let name = sectionData["name"] as? String,
//                      let startIdString = sectionData["startSentenceId"] as? String,
//                      let startId = UUID(uuidString: startIdString) else {
//                    return nil
//                }
//                
//                let endId = (sectionData["endSentenceId"] as? String).flatMap { UUID(uuidString: $0) }
//                let patternIds = (sectionData["patternIds"] as? [String] ?? []).compactMap { UUID(uuidString: $0) }
//                
//                let section = OutlineSection(
//                    id: id,
//                    startSentenceId: startId,
//                    endSentenceId: endId,
//                    patternIds: patternIds,
//                    name: name,
//                    rawNotes: sectionData["rawNotes"] as? String,
//                    beliefInstalled: sectionData["beliefInstalled"] as? String,
//                    aiTitle: sectionData["aiTitle"] as? String,
//                    aiSummary: sectionData["aiSummary"] as? String,
//                    aiStrategicPurpose: sectionData["aiStrategicPurpose"] as? String,
//                    aiMechanism: sectionData["aiMechanism"] as? String,
//                    aiInputsRecipe: sectionData["aiInputsRecipe"] as? String,
//                    aiBSFlags: sectionData["aiBSFlags"] as? String,
//                    aiArchetype: sectionData["aiArchetype"] as? String
//                )
//                
//                return section
//            }
//        }
//        
//        if let patternsArray = data["allMarkedPatterns"] as? [[String: Any]] {
//            breakdown.allMarkedPatterns = patternsArray.compactMap { patternData -> MarkedPattern? in
//                guard let idString = patternData["id"] as? String,
//                      let id = UUID(uuidString: idString),
//                      let typeString = patternData["type"] as? String,
//                      let type = PatternType(rawValue: typeString),
//                      let sentenceIdsArray = patternData["sentenceIds"] as? [String] else {
//                    return nil
//                }
//                
//                let sentenceIds = sentenceIdsArray.compactMap { UUID(uuidString: $0) }
//                let sectionId = (patternData["sectionId"] as? String).flatMap { UUID(uuidString: $0) }
//                
//                var pattern = MarkedPattern(
//                    id: id,
//                    type: type,
//                    sentenceIds: sentenceIds,
//                    note: patternData["note"] as? String,
//                    sectionId: sectionId
//                )
//                pattern.extractedToPlaybook = patternData["extractedToPlaybook"] as? Bool ?? false
//                return pattern
//            }
//        }
//        
//        return breakdown
//    }
    
    private func scriptBreakdownToFirebase(_ breakdown: ScriptBreakdown) -> [String: Any] {
        var data: [String: Any] = [
            "lastEditedDate": Timestamp(date: breakdown.lastEditedDate)
        ]

        data["sentences"] = breakdown.sentences.map { sentence in
            [
                "id": sentence.id.uuidString,
                "text": sentence.text,
                "isSelected": sentence.isSelected,
                "isTyped": sentence.isTyped
            ] as [String: Any]
        }

        data["sections"] = breakdown.sections.map { section in
            var sectionDict: [String: Any] = [
                "id": section.id.uuidString,
                "name": section.name,
                "startSentenceId": section.startSentenceId.uuidString,
                "patternIds": section.patternIds.map { $0.uuidString }
            ]

            // ✅ Firestore cannot accept Optional<T> as Any. Use NSNull() or omit.
            sectionDict["endSentenceId"] = section.endSentenceId?.uuidString ?? NSNull()

            // Byron's fields
            if let rawNotes = section.rawNotes { sectionDict["rawNotes"] = rawNotes }
            if let beliefInstalled = section.beliefInstalled { sectionDict["beliefInstalled"] = beliefInstalled }

            // AI fields
            if let aiTitle = section.aiTitle { sectionDict["aiTitle"] = aiTitle }
            if let aiSummary = section.aiSummary { sectionDict["aiSummary"] = aiSummary }
            if let aiStrategicPurpose = section.aiStrategicPurpose { sectionDict["aiStrategicPurpose"] = aiStrategicPurpose }
            if let aiMechanism = section.aiMechanism { sectionDict["aiMechanism"] = aiMechanism }
            if let aiInputsRecipe = section.aiInputsRecipe { sectionDict["aiInputsRecipe"] = aiInputsRecipe }
            if let aiBSFlags = section.aiBSFlags { sectionDict["aiBSFlags"] = aiBSFlags }
            if let aiArchetype = section.aiArchetype { sectionDict["aiArchetype"] = aiArchetype }

            return sectionDict
        }

        data["allMarkedPatterns"] = breakdown.allMarkedPatterns.map { pattern in
            var dict: [String: Any] = [
                "id": pattern.id.uuidString,
                "type": pattern.type.rawValue,
                "sentenceIds": pattern.sentenceIds.map { $0.uuidString },
                "extractedToPlaybook": pattern.extractedToPlaybook
            ]

            // ✅ No Optionals in Firestore dictionaries
            dict["note"] = pattern.note ?? NSNull()
            dict["sectionId"] = pattern.sectionId?.uuidString ?? NSNull()

            return dict
        }

        return data
    }

    private func firebaseToScriptBreakdown(_ data: [String: Any]) -> ScriptBreakdown? {
        var breakdown = ScriptBreakdown()

        if let timestamp = data["lastEditedDate"] as? Timestamp {
            breakdown.lastEditedDate = timestamp.dateValue()
        }

        if let sentencesArray = data["sentences"] as? [[String: Any]] {
            breakdown.sentences = sentencesArray.compactMap { sentenceData -> ScriptSentence? in
                guard let idString = sentenceData["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let text = sentenceData["text"] as? String else { return nil }

                return ScriptSentence(
                    id: id,
                    text: text,
                    isSelected: sentenceData["isSelected"] as? Bool ?? false,
                    isTyped: sentenceData["isTyped"] as? Bool ?? false
                )
            }
        }

        if let sectionsArray = data["sections"] as? [[String: Any]] {
            breakdown.sections = sectionsArray.compactMap { sectionData -> OutlineSection? in
                guard let idString = sectionData["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let name = sectionData["name"] as? String,
                      let startIdString = sectionData["startSentenceId"] as? String,
                      let startId = UUID(uuidString: startIdString) else { return nil }

                // ✅ Handle NSNull safely
                let endIdString = sectionData["endSentenceId"] as? String
                let endId = endIdString.flatMap { UUID(uuidString: $0) }

                let patternIds = (sectionData["patternIds"] as? [String] ?? []).compactMap { UUID(uuidString: $0) }

                return OutlineSection(
                    id: id,
                    startSentenceId: startId,
                    endSentenceId: endId,
                    patternIds: patternIds,
                    name: name,
                    rawNotes: sectionData["rawNotes"] as? String,
                    beliefInstalled: sectionData["beliefInstalled"] as? String,
                    aiTitle: sectionData["aiTitle"] as? String,
                    aiSummary: sectionData["aiSummary"] as? String,
                    aiStrategicPurpose: sectionData["aiStrategicPurpose"] as? String,
                    aiMechanism: sectionData["aiMechanism"] as? String,
                    aiInputsRecipe: sectionData["aiInputsRecipe"] as? String,
                    aiBSFlags: sectionData["aiBSFlags"] as? String,
                    aiArchetype: sectionData["aiArchetype"] as? String
                )
            }
        }

        if let patternsArray = data["allMarkedPatterns"] as? [[String: Any]] {
            breakdown.allMarkedPatterns = patternsArray.compactMap { patternData -> MarkedPattern? in
                guard let idString = patternData["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let typeString = patternData["type"] as? String,
                      let type = PatternType(rawValue: typeString),
                      let sentenceIdsArray = patternData["sentenceIds"] as? [String] else { return nil }

                let sentenceIds = sentenceIdsArray.compactMap { UUID(uuidString: $0) }

                let sectionIdString = patternData["sectionId"] as? String
                let sectionId = sectionIdString.flatMap { UUID(uuidString: $0) }

                let note = patternData["note"] as? String

                var pattern = MarkedPattern(
                    id: id,
                    type: type,
                    sentenceIds: sentenceIds,
                    note: note,
                    sectionId: sectionId
                )
                pattern.extractedToPlaybook = patternData["extractedToPlaybook"] as? Bool ?? false
                return pattern
            }
        }

        return breakdown
    }

   
}


import Foundation
import FirebaseFirestore

extension YouTubeFirebaseService {
    
    // MARK: - Channel A3 Updates
    
    /// Update channel's profileIds array after A3 clustering
    func updateChannelProfileIds(channelId: String, profileIds: [String]) async throws {
        let docRef = db.collection(channelsCollection).document(channelId)
        try await docRef.updateData([
            "profileIds": profileIds,
            "lastFullClusterAt": Timestamp(date: Date()),
            "pendingRecluster": false
        ])
        invalidateChannelsCache()
        print("✅ Updated channel profileIds: \(profileIds.count) profiles")
    }
    
    /// Update scriptsAnalyzed count
    func updateChannelScriptsAnalyzed(channelId: String, count: Int) async throws {
        let docRef = db.collection(channelsCollection).document(channelId)
        try await docRef.updateData([
            "scriptsAnalyzed": count
        ])
        invalidateChannelsCache()
    }
    
    /// Mark channel as needing recluster (when new videos are analyzed)
    func markChannelPendingRecluster(channelId: String) async throws {
        let docRef = db.collection(channelsCollection).document(channelId)
        try await docRef.updateData([
            "pendingRecluster": true
        ])
        invalidateChannelsCache()
    }
    
    // MARK: - Videos with ScriptSummary
    
    /// Load videos that have scriptSummary (ready for A3 clustering)
    func loadVideosWithScriptSummary(channelId: String) async throws -> [YouTubeVideo] {
        let allVideos = try await getVideos(forChannel: channelId)
        return allVideos.filter { $0.scriptSummary != nil }
    }
    
    /// Count videos with scriptSummary
    func countVideosWithScriptSummary(channelId: String) async throws -> Int {
        let videos = try await loadVideosWithScriptSummary(channelId: channelId)
        return videos.count
    }
}

// MARK: - Purpose-Filtered Video Queries (Pre-A0)

extension YouTubeFirebaseService {

    /// Get videos for a channel filtered by purpose
    func getVideos(forChannel channelId: String, purpose: VideoPurpose) async throws -> [YouTubeVideo] {
        let fieldName: String
        switch purpose {
        case .taxonomyBuilding: fieldName = "forTaxonomyBuilding"
        case .scriptAnalysis: fieldName = "forScriptAnalysis"
        case .researchData: fieldName = "forResearchData"
        case .ideaGeneration: fieldName = "forIdeaGeneration"
        case .thumbnailStudy: fieldName = "forThumbnailStudy"
        }

        let snapshot = try await db.collection(videosCollection)
            .whereField("channelId", isEqualTo: channelId)
            .whereField(fieldName, isEqualTo: true)
            .order(by: "publishedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: YouTubeVideo.self)
        }
    }

    /// Get pinned videos for a channel
    func getPinnedVideos(forChannel channelId: String) async throws -> [YouTubeVideo] {
        let snapshot = try await db.collection(videosCollection)
            .whereField("channelId", isEqualTo: channelId)
            .whereField("isPinned", isEqualTo: true)
            .order(by: "publishedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: YouTubeVideo.self)
        }
    }

    /// Get video IDs already in our database for a channel
    func getExistingVideoIds(forChannel channelId: String) async throws -> Set<String> {
        let videos = try await getVideos(forChannel: channelId)
        return Set(videos.map { $0.videoId })
    }

    /// Update purpose flags for a video
    func updateVideoPurposeFlags(
        videoId: String,
        forTaxonomyBuilding: Bool? = nil,
        forScriptAnalysis: Bool? = nil,
        forResearchData: Bool? = nil,
        forIdeaGeneration: Bool? = nil,
        forThumbnailStudy: Bool? = nil,
        isPinned: Bool? = nil
    ) async throws {
        var updates: [String: Any] = [:]

        if let value = forTaxonomyBuilding { updates["forTaxonomyBuilding"] = value }
        if let value = forScriptAnalysis { updates["forScriptAnalysis"] = value }
        if let value = forResearchData { updates["forResearchData"] = value }
        if let value = forIdeaGeneration { updates["forIdeaGeneration"] = value }
        if let value = forThumbnailStudy { updates["forThumbnailStudy"] = value }
        if let value = isPinned { updates["isPinned"] = value }

        guard !updates.isEmpty else { return }

        let docRef = db.collection(videosCollection).document(videoId)
        try await docRef.updateData(updates)
        invalidateVideosCache()
        print("✅ Updated purpose flags for video: \(videoId)")
    }

    /// Batch update purpose flags for multiple videos (used when importing from Pre-A0)
    func batchUpdateVideoPurposeFlags(
        videoIds: [String],
        forTaxonomyBuilding: Bool? = nil,
        forScriptAnalysis: Bool? = nil,
        forResearchData: Bool? = nil,
        forIdeaGeneration: Bool? = nil,
        forThumbnailStudy: Bool? = nil
    ) async throws {
        var updates: [String: Any] = [:]

        if let value = forTaxonomyBuilding { updates["forTaxonomyBuilding"] = value }
        if let value = forScriptAnalysis { updates["forScriptAnalysis"] = value }
        if let value = forResearchData { updates["forResearchData"] = value }
        if let value = forIdeaGeneration { updates["forIdeaGeneration"] = value }
        if let value = forThumbnailStudy { updates["forThumbnailStudy"] = value }

        guard !updates.isEmpty else { return }

        // Firestore batch limit is 500 writes
        let batches = videoIds.chunked(into: 400)

        for batch in batches {
            let writeBatch = db.batch()
            for videoId in batch {
                let docRef = db.collection(videosCollection).document(videoId)
                writeBatch.updateData(updates, forDocument: docRef)
            }
            try await writeBatch.commit()
        }

        invalidateVideosCache()
        print("✅ Batch updated purpose flags for \(videoIds.count) videos")
    }

    /// Save Phase0Result to a video
    func savePhase0Result(videoId: String, result: Phase0Result) async throws {
        let docRef = db.collection(videosCollection).document(videoId)
        let data = try Firestore.Encoder().encode(result)
        try await docRef.setData([
            "phase0Result": data
        ], merge: true)
        invalidateVideosCache()
        print("✅ Saved Phase0Result for video: \(videoId)")
    }

    /// Save assigned template ID to a video
    func saveAssignedTemplateId(videoId: String, templateId: String) async throws {
        let docRef = db.collection(videosCollection).document(videoId)
        try await docRef.updateData([
            "assignedTemplateId": templateId
        ])
        invalidateVideosCache()
        print("✅ Assigned template '\(templateId)' to video: \(videoId)")
    }
}

// MARK: - Taxonomy Operations

extension YouTubeFirebaseService {

    private var taxonomyCollection: String { "youtube_video_taxonomy" }

    /// Save a taxonomy for a channel
    func saveTaxonomy(_ taxonomy: StyleTaxonomy) async throws {
        let docRef = db.collection(taxonomyCollection).document(taxonomy.channelId)
        try docRef.setData(from: taxonomy)
        print("✅ Saved taxonomy for channel: \(taxonomy.channelId)")
        print("   Templates: \(taxonomy.templates.map { $0.name }.joined(separator: ", "))")
    }

    /// Load taxonomy for a channel
    func loadTaxonomy(channelId: String) async throws -> StyleTaxonomy? {
        let docRef = db.collection(taxonomyCollection).document(channelId)
        let document = try await docRef.getDocument()

        if document.exists {
            return try document.data(as: StyleTaxonomy.self)
        }
        return nil
    }

    /// Check if a channel has a taxonomy
    func hasTaxonomy(channelId: String) async throws -> Bool {
        let docRef = db.collection(taxonomyCollection).document(channelId)
        let document = try await docRef.getDocument()
        return document.exists
    }

    /// Update a specific template within a taxonomy
    func updateTemplate(channelId: String, template: StyleTemplate) async throws {
        guard var taxonomy = try await loadTaxonomy(channelId: channelId) else {
            throw NSError(domain: "Firebase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Taxonomy not found for channel"])
        }

        // Find and update the template
        if let index = taxonomy.templates.firstIndex(where: { $0.id == template.id }) {
            taxonomy.templates[index] = template
            taxonomy.updatedAt = Date()
            try await saveTaxonomy(taxonomy)
            print("✅ Updated template: \(template.name)")
        } else {
            throw NSError(domain: "Firebase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Template not found in taxonomy"])
        }
    }

    /// Update just the A1a prompt for a template
    func updateTemplateA1aPrompt(
        channelId: String,
        templateId: String,
        prompt: String
    ) async throws {
        guard var taxonomy = try await loadTaxonomy(channelId: channelId) else {
            throw NSError(domain: "Firebase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Taxonomy not found"])
        }

        if let index = taxonomy.templates.firstIndex(where: { $0.id == templateId }) {
            taxonomy.templates[index].a1aSystemPrompt = prompt
            taxonomy.updatedAt = Date()
            try await saveTaxonomy(taxonomy)
            print("✅ Updated A1a prompt for template: \(templateId)")
        }
    }

    /// Update template stability score after fidelity testing
    func updateTemplateStability(
        channelId: String,
        templateId: String,
        stabilityScore: Double,
        testedAt: Date
    ) async throws {
        guard var taxonomy = try await loadTaxonomy(channelId: channelId) else {
            throw NSError(domain: "Firebase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Taxonomy not found"])
        }

        if let index = taxonomy.templates.firstIndex(where: { $0.id == templateId }) {
            taxonomy.templates[index].a1aStabilityScore = stabilityScore
            taxonomy.templates[index].a1aLastTestedAt = testedAt
            taxonomy.updatedAt = Date()
            try await saveTaxonomy(taxonomy)
            print("✅ Updated stability for template: \(templateId) (score: \(stabilityScore))")
        }
    }

    /// Get all taxonomies (for overview/dashboard)
    func getAllTaxonomies() async throws -> [StyleTaxonomy] {
        let snapshot = try await db.collection(taxonomyCollection).getDocuments()
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: StyleTaxonomy.self)
        }
    }

    /// Delete a taxonomy
    func deleteTaxonomy(channelId: String) async throws {
        let docRef = db.collection(taxonomyCollection).document(channelId)
        try await docRef.delete()
        print("🗑️ Deleted taxonomy for channel: \(channelId)")
    }

    // MARK: - Locked Taxonomy Operations

    private var lockedTaxonomyCollection: String { "youtube_locked_taxonomy" }

    /// Save a locked taxonomy (user-created, template-focused)
    func saveLockedTaxonomy(_ taxonomy: LockedTaxonomy, forChannel channelId: String) async throws {
        let docRef = db.collection(lockedTaxonomyCollection).document(channelId)
        try docRef.setData(from: taxonomy)
        print("✅ Saved locked taxonomy for channel: \(channelId)")
        print("   Templates: \(taxonomy.templates.map { $0.name }.joined(separator: ", "))")
        print("   Locked: \(taxonomy.isLocked ? "Yes" : "No")")
    }

    /// Get locked taxonomy for a channel
    func getLockedTaxonomy(forChannel channelId: String) async throws -> LockedTaxonomy? {
        let docRef = db.collection(lockedTaxonomyCollection).document(channelId)
        let document = try await docRef.getDocument()

        if document.exists {
            return try document.data(as: LockedTaxonomy.self)
        }
        return nil
    }

    /// Check if a channel has a locked taxonomy
    func hasLockedTaxonomy(channelId: String) async throws -> Bool {
        let docRef = db.collection(lockedTaxonomyCollection).document(channelId)
        let document = try await docRef.getDocument()
        return document.exists
    }

    /// Delete a locked taxonomy
    func deleteLockedTaxonomy(channelId: String) async throws {
        let docRef = db.collection(lockedTaxonomyCollection).document(channelId)
        try await docRef.delete()
        print("🗑️ Deleted locked taxonomy for channel: \(channelId)")
    }
}
