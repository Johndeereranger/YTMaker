//
//  YouTubeImporterView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//

import SwiftUI
//
//struct YouTubeImporterView: View {
//    enum ImportMode {
//        case channel
//        case video
//    }
//    
//    @EnvironmentObject var viewModel: VideoSearchViewModel
//    @State private var importMode: ImportMode = .channel
//    @State private var channelInput = ""
//    @State private var videoInput = ""
//    @State private var youtubeAPIKey = "AIzaSyA5tkpCH8MLfDmdVBFDnGSj-1IL34-91KE"
//    @State private var isLoading = false
//    @State private var statusMessage = ""
//    @State private var importedChannel: YouTubeChannel?
//    @State private var importedVideo: YouTubeVideo?
//    @State private var videoCount = 0
//    
//    // ✅ NEW: Research metadata
//    @State private var notHunting = false
//    @State private var selectedTopicId: String? = nil
//    @StateObject private var topicManager = ResearchTopicManager()
//    
//    var body: some View {
//        Form {
//            Section("API Configuration") {
//                SecureField("YouTube API Key", text: $youtubeAPIKey)
//                    .textInputAutocapitalization(.never)
//                Text("Get your key from: console.cloud.google.com")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//            }
//            
//            Section {
//                Picker("Import Type", selection: $importMode) {
//                    Text("Channel").tag(ImportMode.channel)
//                    Text("Single Video").tag(ImportMode.video)
//                }
//                .pickerStyle(.segmented)
//            }
//            
//            // ✅ NEW: Research Metadata Section
//            Section("Research Settings") {
//                Toggle(isOn: $notHunting) {
//                    Label("Not Hunting Content", systemImage: notHunting ? "xmark.circle.fill" : "checkmark.circle.fill")
//                        .foregroundColor(notHunting ? .red : .green)
//                }
//                
//                Picker("Assign to Research Topic", selection: $selectedTopicId) {
//                    Text("None").tag(nil as String?)
//                    ForEach(topicManager.topics) { topic in
//                        Text(topic.title).tag(topic.id as String?)
//                    }
//                }
//                
//                if topicManager.topics.isEmpty {
//                    Text("No research topics available")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                }
//            }
//            
//            if importMode == .channel {
//                channelImportSection
//            } else {
//                videoImportSection
//            }
//            
//            if !statusMessage.isEmpty {
//                Section("Status") {
//                    Text(statusMessage)
//                        .font(.caption)
//                        .foregroundColor(statusMessage.contains("✅") ? .green : .red)
//                }
//            }
//            
//            if let channel = importedChannel {
//                Section("Imported Channel") {
//                    HStack {
//                        AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
//                            image.resizable()
//                        } placeholder: {
//                            Rectangle().fill(Color.gray.opacity(0.3))
//                        }
//                        .frame(width: 60, height: 60)
//                        .cornerRadius(8)
//                        
//                        VStack(alignment: .leading) {
//                            Text(channel.name)
//                                .font(.headline)
//                            Text("\(videoCount) videos imported")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                            if notHunting {
//                                Text("Marked as: Not Hunting")
//                                    .font(.caption)
//                                    .foregroundColor(.red)
//                            }
//                            if let topicId = selectedTopicId,
//                               let topic = topicManager.topics.first(where: { $0.id == topicId }) {
//                                Text("Topic: \(topic.title)")
//                                    .font(.caption)
//                                    .foregroundColor(.blue)
//                            }
//                        }
//                    }
//                }
//            }
//            
//            if let video = importedVideo {
//                Section("Imported Video") {
//                    VStack(alignment: .leading, spacing: 8) {
//                        AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
//                            image.resizable()
//                                .aspectRatio(contentMode: .fill)
//                        } placeholder: {
//                            Rectangle().fill(Color.gray.opacity(0.3))
//                        }
//                        .frame(height: 120)
//                        .cornerRadius(8)
//                        
//                        Text(video.title)
//                            .font(.headline)
//                        
//                        if notHunting {
//                            Text("Marked as: Not Hunting")
//                                .font(.caption)
//                                .foregroundColor(.red)
//                        }
//                        
//                        if let topicId = selectedTopicId,
//                           let topic = topicManager.topics.first(where: { $0.id == topicId }) {
//                            Text("Assigned to: \(topic.title)")
//                                .font(.caption)
//                                .foregroundColor(.blue)
//                        }
//                        
//                        Text("Channel will be auto-created if it doesn't exist")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                }
//            }
//        }
//        .navigationTitle("YouTube Importer")
//        .task {
//            await loadTopics()
//        }
//    }
//    
//    private var channelImportSection: some View {
//        Section("Channel Information") {
//            TextField("YouTube Channel (@handle or URL)", text: $channelInput)
//                .textInputAutocapitalization(.never)
//            
//            Button(action: {
//                Task { await importChannel() }
//            }) {
//                if isLoading {
//                    HStack {
//                        ProgressView()
//                        Text("Importing...")
//                    }
//                } else {
//                    Text("Import Channel")
//                }
//            }
//            .disabled(channelInput.isEmpty || youtubeAPIKey.isEmpty || isLoading)
//        }
//    }
//    
//    private var videoImportSection: some View {
//        Section("Video Information") {
//            TextField("YouTube Video URL or ID", text: $videoInput)
//                .textInputAutocapitalization(.never)
//            
//            Text("Examples:")
//                .font(.caption)
//                .foregroundStyle(.secondary)
//            Text("https://youtube.com/watch?v=VIDEO_ID")
//                .font(.caption)
//                .foregroundStyle(.secondary)
//            Text("https://youtu.be/VIDEO_ID")
//                .font(.caption)
//                .foregroundStyle(.secondary)
//            
//            Button(action: {
//                Task { await importVideo() }
//            }) {
//                if isLoading {
//                    HStack {
//                        ProgressView()
//                        Text("Importing...")
//                    }
//                } else {
//                    Text("Import Video")
//                }
//            }
//            .disabled(videoInput.isEmpty || youtubeAPIKey.isEmpty || isLoading)
//        }
//    }
//    
//    // MARK: - Load Topics
//    private func loadTopics() async {
//        do {
//            try await topicManager.fetchAllTopics()
//        } catch {
//            print("❌ Error loading topics: \(error)")
//        }
//    }
//    
//    // MARK: - Channel Import
//    func importChannel() async {
//        isLoading = true
//        statusMessage = "Fetching channel information..."
//        importedChannel = nil
//        importedVideo = nil
//        videoCount = 0
//        
//        do {
//            let youtubeService = YouTubeAPIService(apiKey: youtubeAPIKey)
//            let firebaseService = YouTubeFirebaseService()
//            
//            statusMessage = "📡 Fetching channel..."
//            let channel = try await youtubeService.fetchChannel(input: channelInput)
//            
//            statusMessage = "💾 Saving channel to Firebase..."
//            try await firebaseService.saveChannel(channel)
//            
//            statusMessage = "📹 Fetching videos..."
//            var videos = try await youtubeService.fetchVideos(
//                channelId: channel.channelId,
//                maxVideos: nil
//            ) { count in
//                Task { @MainActor in
//                    statusMessage = "📹 Fetched \(count) videos so far..."
//                }
//            }
//            
//            // ✅ Apply notHunting flag to all videos
//            if notHunting {
//                statusMessage = "🏷️ Marking videos as not hunting..."
//                videos = videos.map { video in
//                    var updatedVideo = video
//                    updatedVideo.notHunting = true
//                    return updatedVideo
//                }
//            }
//            
//            statusMessage = "💾 Saving \(videos.count) videos to Firebase..."
//            try await firebaseService.saveVideos(videos)
//            
//            // ✅ Assign to research topic if selected
//            if let topicId = selectedTopicId {
//                statusMessage = "📁 Assigning videos to research topic..."
//                let videoIds = videos.map { $0.videoId }
//                
//                for videoId in videoIds {
//                    try await topicManager.addVideoToTopic(topicId: topicId, videoId: videoId)
//                }
//            }
//            
//            importedChannel = channel
//            videoCount = videos.count
//            
//            var successMessage = "✅ Successfully imported \(channel.name) with \(videos.count) videos!"
//            if notHunting {
//                successMessage += " (Marked as not hunting)"
//            }
//            if let topicId = selectedTopicId,
//               let topic = topicManager.topics.first(where: { $0.id == topicId }) {
//                successMessage += " → \(topic.title)"
//            }
//            
//            await MainActor.run {
//                for video in videos {
//                    viewModel.addVideo(video)
//                }
//                viewModel.addChannel(channel)
//            }
//            statusMessage = successMessage
//            
//        } catch {
//            statusMessage = "❌ Error: \(error.localizedDescription)"
//            print("Import error: \(error)")
//        }
//        
//        isLoading = false
//    }
//    
//    // MARK: - Video Import
//    func importVideo() async {
//        isLoading = true
//        statusMessage = "Extracting video ID..."
//        importedChannel = nil
//        importedVideo = nil
//        videoCount = 0
//        
//        do {
//            guard let videoId = extractVideoId(from: videoInput) else {
//                statusMessage = "❌ Invalid YouTube URL or video ID"
//                isLoading = false
//                return
//            }
//            
//            print("📹 Importing video ID: \(videoId)")
//            
//            let youtubeService = YouTubeAPIService(apiKey: youtubeAPIKey)
//            let firebaseService = YouTubeFirebaseService.shared
//            
//            // Check if video already exists
//            statusMessage = "Checking if video exists..."
//            let existingVideo = try await firebaseService.fetchVideo(videoId: videoId)
//            
//            if existingVideo != nil {
//                print("⚠️ Video already exists: \(videoId)")
//                statusMessage = "⚠️ Video already imported!"
//                isLoading = false
//                return
//            }
//            
//            // Fetch video details
//            statusMessage = "📡 Fetching video details..."
//            print("📡 Fetching video details from YouTube API...")
//            var video = try await youtubeService.fetchVideoDetails(videoId: videoId)
//            
//            print("✅ Got video: \(video.title)")
//            print("📺 Video's channel ID: \(video.channelId)")
//            
//            // ✅ Apply notHunting flag
//            video.notHunting = notHunting
//            
//            // Check if channel exists
//            statusMessage = "Checking channel..."
//            print("🔍 Checking if channel exists: \(video.channelId)")
//            let existingChannel = try await firebaseService.fetchChannel(channelId: video.channelId)
//            
//            if let channel = existingChannel {
//                print("✅ Channel already exists: \(channel.name)")
//                statusMessage = "Channel already exists: \(channel.name)"
//            } else {
//                print("⚠️ Channel not found, fetching from YouTube...")
//                statusMessage = "📡 Fetching channel details..."
//                
//                do {
//                    let channelDetails = try await youtubeService.fetchChannelById(channelId: video.channelId)
//                    
//                    print("✅ Got channel: \(channelDetails.name)")
//                    statusMessage = "💾 Creating channel: \(channelDetails.name)..."
//                    
//                    try await firebaseService.saveChannel(channelDetails)
//                    print("✅ Channel saved successfully")
//                } catch {
//                    print("❌ Failed to fetch/save channel: \(error)")
//                    print("❌ Error details: \(error.localizedDescription)")
//                    statusMessage = "⚠️ Channel fetch failed, but continuing..."
//                }
//            }
//            
//            // Save video
//            statusMessage = "💾 Saving video..."
//            print("💾 Saving video to Firebase...")
//            try await firebaseService.saveVideo(video)
//            print("✅ Video saved successfully")
//            
//            // ✅ Assign to research topic if selected
//            if let topicId = selectedTopicId {
//                statusMessage = "📁 Assigning to research topic..."
//                try await topicManager.addVideoToTopic(topicId: topicId, videoId: video.videoId)
//            }
//            
//            importedVideo = video
//            
//            var successMessage = "✅ Successfully imported video!"
//            if notHunting {
//                successMessage += " (Not hunting)"
//            }
//            if let topicId = selectedTopicId,
//               let topic = topicManager.topics.first(where: { $0.id == topicId }) {
//                successMessage += " → \(topic.title)"
//            }
//            
//            await MainActor.run {
//                viewModel.addVideo(video)
//            }
//            statusMessage = successMessage
//            
//        } catch {
//            print("❌ Import failed: \(error)")
//            print("❌ Error type: \(type(of: error))")
//            statusMessage = "❌ Error: \(error.localizedDescription)"
//        }
//        
//        isLoading = false
//    }
//    
//    // MARK: - Helper Methods
//    private func extractVideoId(from input: String) -> String? {
//        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        // Direct video ID (11 characters)
//        if trimmed.count == 11 && !trimmed.contains("/") && !trimmed.contains("=") {
//            return trimmed
//        }
//        
//        guard let url = URL(string: trimmed) else {
//            return nil
//        }
//        
//        // youtube.com/watch?v=VIDEO_ID
//        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
//           let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value {
//            return videoId
//        }
//        
//        // youtube.com/shorts/VIDEO_ID
//        if url.pathComponents.contains("shorts") {
//            let pathComponents = url.pathComponents
//            if let shortsIndex = pathComponents.firstIndex(of: "shorts"),
//               shortsIndex + 1 < pathComponents.count {
//                let videoId = pathComponents[shortsIndex + 1]
//                if let cleanId = videoId.split(separator: "?").first {
//                    return String(cleanId)
//                }
//                return videoId
//            }
//        }
//        
//        // youtu.be/VIDEO_ID
//        if url.host?.contains("youtu.be") == true {
//            let videoId = url.lastPathComponent
//            if videoId.count == 11 {
//                return videoId
//            }
//        }
//        
//        return nil
//    }
//}
//MARK: - Was working changed on 1/22/25
//
//struct YouTubeImporterView: View {
//    enum ImportMode {
//        case channel
//        case video
//    }
//    
//    @EnvironmentObject var viewModel: VideoSearchViewModel
//    @State private var importMode: ImportMode = .channel
//    @State private var channelInput = ""
//    @State private var videoInput = ""
//    @State private var youtubeAPIKey = "AIzaSyA5tkpCH8MLfDmdVBFDnGSj-1IL34-91KE"
//    @State private var isLoading = false
//    @State private var statusMessage = ""
//    @State private var importedChannel: YouTubeChannel?
//    @State private var importedVideo: YouTubeVideo?
//    @State private var videoCount = 0
//    
//    // Research metadata
//    @State private var notHunting = false
//    @State private var selectedTopicId: String? = nil
//    @StateObject private var topicManager = ResearchTopicManager.shared
//    
//    // ⭐ NEW: Create topic fields
//    @State private var showCreateTopic = false
//    @State private var newTopicTitle = ""
//    @State private var newTopicDescription = ""
//    @State private var newTopicNotes = ""
//    
//    var body: some View {
//        Form {
//            Section("API Configuration") {
//                SecureField("YouTube API Key", text: $youtubeAPIKey)
//                    .textInputAutocapitalization(.never)
//                Text("Get your key from: console.cloud.google.com")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//            }
//            
//            Section {
//                Picker("Import Type", selection: $importMode) {
//                    Text("Channel").tag(ImportMode.channel)
//                    Text("Single Video").tag(ImportMode.video)
//                }
//                .pickerStyle(.segmented)
//            }
//            
//            // Research Metadata Section
//            Section("Research Settings") {
//                Toggle(isOn: $notHunting) {
//                    Label("Not Hunting Content", systemImage: notHunting ? "xmark.circle.fill" : "checkmark.circle.fill")
//                        .foregroundColor(notHunting ? .red : .green)
//                }
//                
//                // ⭐ Only show topic assignment for single video import
//                if importMode == .video {
//                    VStack(alignment: .leading, spacing: 8) {
//                        Picker("Assign to Research Topic", selection: $selectedTopicId) {
//                            Text("None").tag(nil as String?)
//                            ForEach(topicManager.topics) { topic in
//                                Text(topic.title).tag(topic.id as String?)
//                            }
//                        }
//                        
//                        // ⭐ NEW: Create topic button
//                        Button {
//                            showCreateTopic.toggle()
//                        } label: {
//                            Label(showCreateTopic ? "Cancel New Topic" : "Create New Topic",
//                                  systemImage: showCreateTopic ? "xmark.circle" : "plus.circle")
//                                .font(.caption)
//                        }
//                        .buttonStyle(.bordered)
//                        .controlSize(.small)
//                    }
//                    
//                    // ⭐ NEW: Create topic fields
//                    if showCreateTopic {
//                        VStack(alignment: .leading, spacing: 12) {
//                            TextField("Topic Title", text: $newTopicTitle)
//                                .textFieldStyle(.roundedBorder)
//                            
//                            TextField("Description (optional)", text: $newTopicDescription)
//                                .textFieldStyle(.roundedBorder)
//                            
//                            TextField("Notes (optional)", text: $newTopicNotes)
//                                .textFieldStyle(.roundedBorder)
//                        }
//                        .padding(.vertical, 8)
//                        .padding(.horizontal, 12)
//                        .background(Color(.secondarySystemBackground))
//                        .cornerRadius(8)
//                    }
//                    
//                    if topicManager.topics.isEmpty && !showCreateTopic {
//                        Text("No research topics available. Create one above.")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                }
//            }
//            
//            if importMode == .channel {
//                channelImportSection
//            } else {
//                videoImportSection
//            }
//            
//            if !statusMessage.isEmpty {
//                Section("Status") {
//                    Text(statusMessage)
//                        .font(.caption)
//                        .foregroundColor(statusMessage.contains("✅") ? .green : .red)
//                }
//            }
//            
//            if let channel = importedChannel {
//                Section("Imported Channel") {
//                    HStack {
//                        AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
//                            image.resizable()
//                        } placeholder: {
//                            Rectangle().fill(Color.gray.opacity(0.3))
//                        }
//                        .frame(width: 60, height: 60)
//                        .cornerRadius(8)
//                        
//                        VStack(alignment: .leading) {
//                            Text(channel.name)
//                                .font(.headline)
//                            Text("\(videoCount) videos imported")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                            if notHunting {
//                                Text("Marked as: Not Hunting")
//                                    .font(.caption)
//                                    .foregroundColor(.red)
//                            }
//                        }
//                    }
//                }
//            }
//            
//            if let video = importedVideo {
//                Section("Imported Video") {
//                    VStack(alignment: .leading, spacing: 8) {
//                        AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
//                            image.resizable()
//                                .aspectRatio(contentMode: .fill)
//                        } placeholder: {
//                            Rectangle().fill(Color.gray.opacity(0.3))
//                        }
//                        .frame(height: 120)
//                        .cornerRadius(8)
//                        
//                        Text(video.title)
//                            .font(.headline)
//                        
//                        if notHunting {
//                            Text("Marked as: Not Hunting")
//                                .font(.caption)
//                                .foregroundColor(.red)
//                        }
//                        
//                        if let topicId = selectedTopicId,
//                           let topic = topicManager.topics.first(where: { $0.id == topicId }) {
//                            Text("Assigned to: \(topic.title)")
//                                .font(.caption)
//                                .foregroundColor(.blue)
//                        }
//                        
//                        Text("Channel will be auto-created if it doesn't exist")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                }
//            }
//        }
//        .navigationTitle("YouTube Importer")
//        .task {
//            await loadTopics()
//        }
//    }
//    
//    private var channelImportSection: some View {
//        Section("Channel Information") {
//            TextField("YouTube Channel (@handle or URL)", text: $channelInput)
//                .textInputAutocapitalization(.never)
//            
//            Button(action: {
//                Task { await importChannel() }
//            }) {
//                if isLoading {
//                    HStack {
//                        ProgressView()
//                        Text("Importing...")
//                    }
//                } else {
//                    Text("Import Channel")
//                }
//            }
//            .disabled(channelInput.isEmpty || youtubeAPIKey.isEmpty || isLoading)
//        }
//    }
//    
//    private var videoImportSection: some View {
//        Section("Video Information") {
//            TextField("YouTube Video URL or ID", text: $videoInput)
//                .textInputAutocapitalization(.never)
//            
//            Text("Examples:")
//                .font(.caption)
//                .foregroundStyle(.secondary)
//            Text("https://youtube.com/watch?v=VIDEO_ID")
//                .font(.caption)
//                .foregroundStyle(.secondary)
//            Text("https://youtu.be/VIDEO_ID")
//                .font(.caption)
//                .foregroundStyle(.secondary)
//            
//            Button(action: {
//                Task { await importVideo() }
//            }) {
//                if isLoading {
//                    HStack {
//                        ProgressView()
//                        Text("Importing...")
//                    }
//                } else {
//                    Text("Import Video")
//                }
//            }
//            .disabled(videoInput.isEmpty || youtubeAPIKey.isEmpty || isLoading)
//        }
//    }
//    
//    // MARK: - Load Topics
//    private func loadTopics() async {
//        do {
//            try await topicManager.fetchAllTopics()
//        } catch {
//            print("❌ Error loading topics: \(error)")
//        }
//    }
//    
//    // MARK: - Channel Import
//    func importChannel() async {
//        isLoading = true
//        statusMessage = "Fetching channel information..."
//        importedChannel = nil
//        importedVideo = nil
//        videoCount = 0
//        
//        do {
//            let youtubeService = YouTubeAPIService(apiKey: youtubeAPIKey)
//            let firebaseService = YouTubeFirebaseService()
//            
//            statusMessage = "📡 Fetching channel..."
//            let channel = try await youtubeService.fetchChannel(input: channelInput)
//            
//            statusMessage = "💾 Saving channel to Firebase..."
//            try await firebaseService.saveChannel(channel)
//            
//            statusMessage = "📹 Fetching videos..."
//            var videos = try await youtubeService.fetchVideos(
//                channelId: channel.channelId,
//                maxVideos: nil
//            ) { count in
//                Task { @MainActor in
//                    statusMessage = "📹 Fetched \(count) videos so far..."
//                }
//            }
//            
//            if notHunting {
//                statusMessage = "🏷️ Marking videos as not hunting..."
//                videos = videos.map { video in
//                    var updatedVideo = video
//                    updatedVideo.notHunting = true
//                    return updatedVideo
//                }
//            }
//            
//            statusMessage = "💾 Saving \(videos.count) videos to Firebase..."
//            try await firebaseService.saveVideos(videos)
//            
//            importedChannel = channel
//            videoCount = videos.count
//            
//            var successMessage = "✅ Successfully imported \(channel.name) with \(videos.count) videos!"
//            if notHunting {
//                successMessage += " (Marked as not hunting)"
//            }
//            
//            await MainActor.run {
//                for video in videos {
//                    viewModel.addVideo(video)
//                }
//                viewModel.addChannel(channel)
//            }
//            statusMessage = successMessage
//            
//        } catch {
//            statusMessage = "❌ Error: \(error.localizedDescription)"
//            print("Import error: \(error)")
//        }
//        
//        isLoading = false
//    }
//    
//    // MARK: - Video Import
//    func importVideo() async {
//        isLoading = true
//        statusMessage = "Extracting video ID..."
//        importedChannel = nil
//        importedVideo = nil
//        videoCount = 0
//        
//        do {
//            // ⭐ NEW: Create topic first if needed
//            var topicIdToUse: String? = selectedTopicId
//            
//            if showCreateTopic && !newTopicTitle.isEmpty {
//                statusMessage = "📁 Creating research topic..."
//                
//                let newTopic = ResearchTopic(
//                    title: newTopicTitle,
//                    description: newTopicDescription.isEmpty ? nil : newTopicDescription,
//                    videoIds: [],
//                    topicNotes: newTopicNotes.isEmpty ? nil : newTopicNotes
//                )
//                
//                try await topicManager.createTopic(newTopic)
//                topicIdToUse = newTopic.id
//                
//                print("✅ Created new topic: \(newTopic.title) with ID: \(newTopic.id)")
//                
//                // Clear create topic fields
//                await MainActor.run {
//                    newTopicTitle = ""
//                    newTopicDescription = ""
//                    newTopicNotes = ""
//                    showCreateTopic = false
//                    selectedTopicId = topicIdToUse
//                }
//            }
//            
//            guard let videoId = extractVideoId(from: videoInput) else {
//                statusMessage = "❌ Invalid YouTube URL or video ID"
//                isLoading = false
//                return
//            }
//            
//            print("📹 Importing video ID: \(videoId)")
//            
//            let youtubeService = YouTubeAPIService(apiKey: youtubeAPIKey)
//            let firebaseService = YouTubeFirebaseService.shared
//            
//            statusMessage = "Checking if video exists..."
//            let existingVideo = try await firebaseService.fetchVideo(videoId: videoId)
//            
//            if existingVideo != nil {
//                print("⚠️ Video already exists: \(videoId)")
//                statusMessage = "⚠️ Video already imported!"
//                isLoading = false
//                return
//            }
//            
//            statusMessage = "📡 Fetching video details..."
//            print("📡 Fetching video details from YouTube API...")
//            var video = try await youtubeService.fetchVideoDetails(videoId: videoId)
//            
//            print("✅ Got video: \(video.title)")
//            print("📺 Video's channel ID: \(video.channelId)")
//            
//            video.notHunting = notHunting
//            
//            statusMessage = "Checking channel..."
//            print("🔍 Checking if channel exists: \(video.channelId)")
//            let existingChannel = try await firebaseService.fetchChannel(channelId: video.channelId)
//            
//            if let channel = existingChannel {
//                print("✅ Channel already exists: \(channel.name)")
//                statusMessage = "Channel already exists: \(channel.name)"
//            } else {
//                print("⚠️ Channel not found, fetching from YouTube...")
//                statusMessage = "📡 Fetching channel details..."
//                
//                do {
//                    let channelDetails = try await youtubeService.fetchChannelById(channelId: video.channelId)
//                    
//                    print("✅ Got channel: \(channelDetails.name)")
//                    statusMessage = "💾 Creating channel: \(channelDetails.name)..."
//                    
//                    try await firebaseService.saveChannel(channelDetails)
//                    print("✅ Channel saved successfully")
//                } catch {
//                    print("❌ Failed to fetch/save channel: \(error)")
//                    print("❌ Error details: \(error.localizedDescription)")
//                    statusMessage = "⚠️ Channel fetch failed, but continuing..."
//                }
//            }
//            
//            statusMessage = "💾 Saving video..."
//            print("💾 Saving video to Firebase...")
//            try await firebaseService.saveVideo(video)
//            print("✅ Video saved successfully")
//            
//            // ⭐ Assign to research topic (using newly created topic if applicable)
//            if let topicId = topicIdToUse {
//                statusMessage = "📁 Assigning to research topic..."
//                try await topicManager.addVideoToTopic(topicId: topicId, videoId: video.videoId)
//            }
//            
//            importedVideo = video
//            
//            var successMessage = "✅ Successfully imported video!"
//            if notHunting {
//                successMessage += " (Not hunting)"
//            }
//            if let topicId = topicIdToUse,
//               let topic = topicManager.topics.first(where: { $0.id == topicId }) {
//                successMessage += " → \(topic.title)"
//            }
//            
//            await MainActor.run {
//                viewModel.addVideo(video)
//            }
//            statusMessage = successMessage
//            
//        } catch {
//            print("❌ Import failed: \(error)")
//            print("❌ Error type: \(type(of: error))")
//            statusMessage = "❌ Error: \(error.localizedDescription)"
//        }
//        
//        isLoading = false
//    }
//    
//    // MARK: - Helper Methods
//    private func extractVideoId(from input: String) -> String? {
//        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        if trimmed.count == 11 && !trimmed.contains("/") && !trimmed.contains("=") {
//            return trimmed
//        }
//        
//        guard let url = URL(string: trimmed) else {
//            return nil
//        }
//        
//        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
//           let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value {
//            return videoId
//        }
//        
//        if url.pathComponents.contains("shorts") {
//            let pathComponents = url.pathComponents
//            if let shortsIndex = pathComponents.firstIndex(of: "shorts"),
//               shortsIndex + 1 < pathComponents.count {
//                let videoId = pathComponents[shortsIndex + 1]
//                if let cleanId = videoId.split(separator: "?").first {
//                    return String(cleanId)
//                }
//                return videoId
//            }
//        }
//        
//        if url.host?.contains("youtu.be") == true {
//            let videoId = url.lastPathComponent
//            if videoId.count == 11 {
//                return videoId
//            }
//        }
//        
//        return nil
//    }
//}


struct YouTubeImporterView: View {
    enum ImportMode {
        case channel
        case video
    }
    
    @EnvironmentObject var viewModel: VideoSearchViewModel
    @State private var importMode: ImportMode = .video  // ⭐ Changed default to video
    @State private var channelInput = ""
    @State private var videoInput = ""
    @State private var youtubeAPIKey = "AIzaSyA5tkpCH8MLfDmdVBFDnGSj-1IL34-91KE"
    @State private var isLoading = false
    @State private var statusMessage = ""
    @State private var importedChannel: YouTubeChannel?
    @State private var importedVideo: YouTubeVideo?
    @State private var videoCount = 0
    
    // Research metadata
    @State private var notHunting = false
    @State private var selectedTopicId: String? = nil
    @StateObject private var topicManager = ResearchTopicManager.shared
    
    // ⭐ NEW: Create topic fields
    @State private var showCreateTopic = false
    @State private var newTopicTitle = ""
    @State private var newTopicDescription = ""
    @State private var newTopicNotes = ""
    @State private var videoAlreadyExists = false
    
    // ⭐ Computed property to check if we have a successful import
    private var hasSuccessfulImport: Bool {
        importedChannel != nil || importedVideo != nil || videoAlreadyExists
    }
    
    var body: some View {
        Form {
            Section("API Configuration") {
                SecureField("YouTube API Key", text: $youtubeAPIKey)
                    .textInputAutocapitalization(.never)
                Text("Get your key from: console.cloud.google.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Picker("Import Type", selection: $importMode) {
                    Text("Channel").tag(ImportMode.channel)
                    Text("Single Video").tag(ImportMode.video)
                }
                .pickerStyle(.segmented)
            }
            if !statusMessage.isEmpty {
                Section("Status") {
                    HStack {
                        if hasSuccessfulImport {
                            Button("Import Another") {
                                resetForNextImport()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(statusMessage.contains("✅") ? .green :
                                            statusMessage.contains("⚠️") ? .orange : .red)
                        
                        Spacer()
                        
                       
                    }
                }
            }
            
            // Research Metadata Section
            Section("Research Settings") {
                Toggle(isOn: $notHunting) {
                    Label("Not Hunting Content", systemImage: notHunting ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(notHunting ? .red : .green)
                }
                
                // ⭐ Only show topic assignment for single video import
                if importMode == .video {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Assign to Research Topic", selection: $selectedTopicId) {
                            Text("None").tag(nil as String?)
                            ForEach(topicManager.topics) { topic in
                                Text(topic.title).tag(topic.id as String?)
                            }
                        }
                        
                        // ⭐ NEW: Create topic button
                        Button {
                            showCreateTopic.toggle()
                        } label: {
                            Label(showCreateTopic ? "Cancel New Topic" : "Create New Topic",
                                  systemImage: showCreateTopic ? "xmark.circle" : "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    // ⭐ NEW: Create topic fields
                    if showCreateTopic {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Topic Title", text: $newTopicTitle)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("Description (optional)", text: $newTopicDescription)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("Notes (optional)", text: $newTopicNotes)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    
                    if topicManager.topics.isEmpty && !showCreateTopic {
                        Text("No research topics available. Create one above.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if importMode == .channel {
                channelImportSection
            } else {
                videoImportSection
            }
            
         
            
            if let channel = importedChannel {
                Section("Imported Channel") {
                    HStack {
                        AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
                            image.resizable()
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading) {
                            Text(channel.name)
                                .font(.headline)
                            Text("\(videoCount) videos imported")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if notHunting {
                                Text("Marked as: Not Hunting")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            
            if let video = importedVideo {
                Section("Imported Video") {
                    VStack(alignment: .leading, spacing: 8) {
                        AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(height: 120)
                        .cornerRadius(8)
                        
                        Text(video.title)
                            .font(.headline)
                        
                        if notHunting {
                            Text("Marked as: Not Hunting")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        if let topicId = selectedTopicId,
                           let topic = topicManager.topics.first(where: { $0.id == topicId }) {
                            Text("Assigned to: \(topic.title)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        Text("Channel will be auto-created if it doesn't exist")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
     
        }
        .navigationTitle("YouTube Importer")
        .task {
            await loadTopics()
        }
    }
    
    private var channelImportSection: some View {
        Section("Channel Information") {
            TextField("YouTube Channel (@handle or URL)", text: $channelInput)
                .textInputAutocapitalization(.never)
            
            Button(action: {
                Task { await importChannel() }
            }) {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Importing...")
                    }
                } else {
                    Text("Import Channel")
                }
            }
            .disabled(channelInput.isEmpty || youtubeAPIKey.isEmpty || isLoading)
        }
    }
    private var videoImportSection: some View {
        Section("Video Information") {
            HStack {
                // ⭐ Paste & Import button
                Button {
                    Task {
                        if let clipboardString = UIPasteboard.general.string {
                            videoInput = clipboardString
                            // Small delay to let the state update
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            await importVideo()
                        }
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                
                TextField("YouTube Video URL or ID", text: $videoInput)
                    .textInputAutocapitalization(.never)
            }
            
            Text("Examples:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("https://youtube.com/watch?v=VIDEO_ID")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("https://youtu.be/VIDEO_ID")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button(action: {
                Task { await importVideo() }
            }) {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Importing...")
                    }
                } else {
                    Text("Import Video")
                }
            }
            .disabled(videoInput.isEmpty || youtubeAPIKey.isEmpty || isLoading)
        }
    }
    private var videoImportSectionOld: some View {
        Section("Video Information") {
            TextField("YouTube Video URL or ID", text: $videoInput)
                .textInputAutocapitalization(.never)
            
            Text("Examples:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("https://youtube.com/watch?v=VIDEO_ID")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("https://youtu.be/VIDEO_ID")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button(action: {
                Task { await importVideo() }
            }) {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Importing...")
                    }
                } else {
                    Text("Import Video")
                }
            }
            .disabled(videoInput.isEmpty || youtubeAPIKey.isEmpty || isLoading)
        }
    }
    
    // MARK: - Reset for Next Import
    private func resetForNextImport() {
        // Clear results
        importedChannel = nil
        importedVideo = nil
        videoAlreadyExists = false
        videoCount = 0
        statusMessage = ""
        
        // Clear input fields
        channelInput = ""
        videoInput = ""
        
        // Keep: importMode, notHunting, selectedTopicId (user preferences)
    }
    
    // MARK: - Load Topics
    private func loadTopics() async {
        do {
            try await topicManager.fetchAllTopics()
        } catch {
            print("❌ Error loading topics: \(error)")
        }
    }
    
    // MARK: - Channel Import
    func importChannel() async {
        isLoading = true
        statusMessage = "Fetching channel information..."
        importedChannel = nil
        importedVideo = nil
        videoCount = 0
        
        do {
            let youtubeService = YouTubeAPIService(apiKey: youtubeAPIKey)
            let firebaseService = YouTubeFirebaseService()
            
            statusMessage = "📡 Fetching channel..."
            let channel = try await youtubeService.fetchChannel(input: channelInput)
            
            statusMessage = "💾 Saving channel to Firebase..."
            try await firebaseService.saveChannel(channel)
            
            statusMessage = "📹 Fetching videos..."
            var videos = try await youtubeService.fetchVideos(
                channelId: channel.channelId,
                maxVideos: nil
            ) { count in
                Task { @MainActor in
                    statusMessage = "📹 Fetched \(count) videos so far..."
                }
            }
            
            if notHunting {
                statusMessage = "🏷️ Marking videos as not hunting..."
                videos = videos.map { video in
                    var updatedVideo = video
                    updatedVideo.notHunting = true
                    return updatedVideo
                }
            }
            
            statusMessage = "💾 Saving \(videos.count) videos to Firebase..."
            try await firebaseService.saveVideos(videos)
            
            importedChannel = channel
            videoCount = videos.count
            
            var successMessage = "✅ Successfully imported \(channel.name) with \(videos.count) videos!"
            if notHunting {
                successMessage += " (Marked as not hunting)"
            }
            
            await MainActor.run {
                for video in videos {
                    viewModel.addVideo(video)
                }
                viewModel.addChannel(channel)
            }
            statusMessage = successMessage
            
        } catch {
            statusMessage = "❌ Error: \(error.localizedDescription)"
            print("Import error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Video Import
    func importVideo() async {
        isLoading = true
        statusMessage = "Extracting video ID..."
        importedChannel = nil
        importedVideo = nil
        videoCount = 0
        
        do {
            // ⭐ NEW: Create topic first if needed
            var topicIdToUse: String? = selectedTopicId
            
            if showCreateTopic && !newTopicTitle.isEmpty {
                statusMessage = "📁 Creating research topic..."
                
                let newTopic = ResearchTopic(
                    title: newTopicTitle,
                    description: newTopicDescription.isEmpty ? nil : newTopicDescription,
                    videoIds: [],
                    topicNotes: newTopicNotes.isEmpty ? nil : newTopicNotes
                )
                
                try await topicManager.createTopic(newTopic)
                topicIdToUse = newTopic.id
                
                print("✅ Created new topic: \(newTopic.title) with ID: \(newTopic.id)")
                
                // Clear create topic fields
                await MainActor.run {
                    newTopicTitle = ""
                    newTopicDescription = ""
                    newTopicNotes = ""
                    showCreateTopic = false
                    selectedTopicId = topicIdToUse
                }
            }
            
            guard let videoId = extractVideoId(from: videoInput) else {
                statusMessage = "❌ Invalid YouTube URL or video ID"
                isLoading = false
                return
            }
            
            print("📹 Importing video ID: \(videoId)")
            
            let youtubeService = YouTubeAPIService(apiKey: youtubeAPIKey)
            let firebaseService = YouTubeFirebaseService.shared
            
            statusMessage = "Checking if video exists..."
            let existingVideo = try await firebaseService.fetchVideo(videoId: videoId)
            
            if existingVideo != nil {
                print("⚠️ Video already exists: \(videoId)")
                statusMessage = "⚠️ Video already imported!"
                videoAlreadyExists = true
                isLoading = false
                return
            }
            
            statusMessage = "📡 Fetching video details..."
            print("📡 Fetching video details from YouTube API...")
            var video = try await youtubeService.fetchVideoDetails(videoId: videoId)
            
            print("✅ Got video: \(video.title)")
            print("📺 Video's channel ID: \(video.channelId)")
            
            video.notHunting = notHunting
            
            statusMessage = "Checking channel..."
            print("🔍 Checking if channel exists: \(video.channelId)")
            let existingChannel = try await firebaseService.fetchChannel(channelId: video.channelId)
            
            if let channel = existingChannel {
                print("✅ Channel already exists: \(channel.name)")
                statusMessage = "Channel already exists: \(channel.name)"
            } else {
                print("⚠️ Channel not found, fetching from YouTube...")
                statusMessage = "📡 Fetching channel details..."
                
                do {
                    let channelDetails = try await youtubeService.fetchChannelById(channelId: video.channelId)
                    
                    print("✅ Got channel: \(channelDetails.name)")
                    statusMessage = "💾 Creating channel: \(channelDetails.name)..."
                    
                    try await firebaseService.saveChannel(channelDetails)
                    print("✅ Channel saved successfully")
                } catch {
                    print("❌ Failed to fetch/save channel: \(error)")
                    print("❌ Error details: \(error.localizedDescription)")
                    statusMessage = "⚠️ Channel fetch failed, but continuing..."
                }
            }
            
            statusMessage = "💾 Saving video..."
            print("💾 Saving video to Firebase...")
            try await firebaseService.saveVideo(video)
            print("✅ Video saved successfully")
            
            // ⭐ Assign to research topic (using newly created topic if applicable)
            if let topicId = topicIdToUse {
                statusMessage = "📁 Assigning to research topic..."
                try await topicManager.addVideoToTopic(topicId: topicId, videoId: video.videoId)
            }
            
            importedVideo = video
            
            var successMessage = "✅ Successfully imported video!"
            if notHunting {
                successMessage += " (Not hunting)"
            }
            if let topicId = topicIdToUse,
               let topic = topicManager.topics.first(where: { $0.id == topicId }) {
                successMessage += " → \(topic.title)"
            }
            
            await MainActor.run {
                viewModel.addVideo(video)
            }
            statusMessage = successMessage
            
        } catch {
            print("❌ Import failed: \(error)")
            print("❌ Error type: \(type(of: error))")
            statusMessage = "❌ Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Helper Methods
    private func extractVideoId(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count == 11 && !trimmed.contains("/") && !trimmed.contains("=") {
            return trimmed
        }
        
        guard let url = URL(string: trimmed) else {
            return nil
        }
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return videoId
        }
        
        if url.pathComponents.contains("shorts") {
            let pathComponents = url.pathComponents
            if let shortsIndex = pathComponents.firstIndex(of: "shorts"),
               shortsIndex + 1 < pathComponents.count {
                let videoId = pathComponents[shortsIndex + 1]
                if let cleanId = videoId.split(separator: "?").first {
                    return String(cleanId)
                }
                return videoId
            }
        }
        
        if url.host?.contains("youtu.be") == true {
            let videoId = url.lastPathComponent
            if videoId.count == 11 {
                return videoId
            }
        }
        
        return nil
    }
}
