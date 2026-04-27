//
//  ResearchTopicDetailView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/3/25.
//


import SwiftUI
import SwiftUI

struct ResearchTopicDetailViewfirst: View {
    let topic: ResearchTopic
    @ObservedObject var manager: ResearchTopicManager
    @EnvironmentObject var viewModel: VideoSearchViewModel  // ✅ Use cached videos
    
    @State private var showEditSheet = false
    @State private var selectedVideo: YouTubeVideo?
    
    // ✅ Computed property - filters from already-loaded videos
    var videos: [YouTubeVideo] {
        viewModel.allVideos.filter { topic.videoIds.contains($0.videoId) }
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Topic Info Card
                topicInfoCard
                
                Divider()
                
                // Videos Header
                HStack {
                    Text("\(videos.count) Videos")
                        .font(.headline)
                    Spacer()
                    
                    // Refresh button (reloads all videos in search view)
                    Button(action: { refreshAllVideos() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding(.horizontal)
                
                // Videos Grid
                if viewModel.isLoading {
                    ProgressView("Loading videos...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if videos.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(videos) { video in
                            Button {
                                selectedVideo = video
                            } label: {
                                ResearchTopicVideoCard(
                                    video: video,
                                    onRemove: {
                                        Task { await removeVideo(video) }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showEditSheet = true }) {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .navigationDestination(item: $selectedVideo) { video in
            YouTubeVideoDetailView(video: video)
        }
        .sheet(isPresented: $showEditSheet) {
            EditTopicSheet(topic: topic)
        }
    }
    
    // MARK: - Topic Info Card
    private var topicInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let description = topic.description {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("\(topic.videoIds.count) videos assigned", systemImage: "video")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(topic.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let notes = topic.topicNotes, !notes.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Research Notes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No videos in this topic")
                .font(.headline)
            
            Text("Assign videos from the search view or video importer")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Refresh All Videos
    private func refreshAllVideos() {
        Task {
            await viewModel.loadData()
        }
    }
    
    // MARK: - Remove Video
    private func removeVideo(_ video: YouTubeVideo) async {
        do {
            try await manager.removeVideoFromTopic(topicId: topic.id, videoId: video.videoId)
            
            // Refresh topic list to update video counts
            try await manager.fetchAllTopics()
            
            print("✅ Removed video from topic")
        } catch {
            print("❌ Error removing video: \(error)")
        }
    }
}
import SwiftUI

// MARK: - Enhanced Research Topic Video Card
struct ResearchTopicVideoCard: View {
    let video: YouTubeVideo
    let onRemove: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Card Content
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail with remove button
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(12)
                    
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.red))
                    }
                    .padding(8)
                }
                
                // Title
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                // Stats Row
                HStack(spacing: 12) {
                    Label("\(video.stats.viewCount.formatted())", systemImage: "eye.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(video.stats.likeCount.formatted())", systemImage: "hand.thumbsup.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Hook Type (if exists)
                if let hookType = video.hookType, hookType != .none {
                    HStack {
                        Image(systemName: "hook")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        
                        Text(hookType.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        Spacer()
                        
                        if video.hook != nil && !(video.hook?.isEmpty ?? true) {
                            Button(action: { withAnimation { isExpanded.toggle() } }) {
                                HStack(spacing: 4) {
                                    Text(isExpanded ? "Hide" : "View")
                                        .font(.caption2)
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                }
                                .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
                
                // Metadata badges
                HStack(spacing: 8) {
                    if video.hasTranscript {
                        Badge(icon: "doc.text", color: .green, label: "Transcript")
                    }
                    if video.hasFacts {
                        Badge(icon: "list.bullet", color: .blue, label: "Facts")
                    }
                    if video.hasSummary {
                        Badge(icon: "doc.plaintext", color: .purple, label: "Summary")
                    }
                    if video.notHunting {
                        Badge(icon: "xmark.circle", color: .red, label: "Not Hunting")
                    }
                    Spacer()
                }
            }
            .padding()
            
            // Expandable Hook Section
            if isExpanded, let hook = video.hook, !hook.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    HStack {
                        Text("Hook Text")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: { copyToClipboard(hook) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption2)
                            .foregroundColor(.orange)
                        }
                    }
                    
                    Text(hook)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(6)
                }
                .padding(.horizontal)
                .padding(.bottom)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Enhanced Badge with Optional Label
struct Badge: View {
    let icon: String
    let color: Color
    var label: String? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            
            if let label = label {
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }
}


/*
// MARK: - Preview
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // Card with hook
            ResearchTopicVideoCard(
                video: YouTubeVideo(
                    videoId: "test1",
                    channelId: "channel1",
                    title: "5 Biggest Mistakes Deer Hunters Make",
                    description: "Learn the common mistakes",
                    publishedAt: Date(),
                    duration: "PT10M30S",
                    thumbnailUrl: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
                    stats: VideoStats(viewCount: 125000, likeCount: 3200, commentCount: 450),
                    createdAt: Date(),
                    transcript: "Full transcript here...",
                    factsText: "Key facts...",
                    summaryText: "Summary...",
                    notHunting: false,
                    notes: nil,
                    videoType: "List",
                    hook: "Are you making these deadly mistakes that cost you deer every single season? Today I'm revealing the 5 biggest errors even experienced hunters make.",
                    hookType: .numberList,
                    intro: nil
                ),
                onRemove: { print("Remove tapped") }
            )
            .padding()
            
            // Card without hook
            ResearchTopicVideoCard(
                video: YouTubeVideo(
                    videoId: "test2",
                    channelId: "channel1",
                    title: "Basic Deer Hunting Tips",
                    description: "Simple tips",
                    publishedAt: Date(),
                    duration: "PT8M15S",
                    thumbnailUrl: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
                    stats: VideoStats(viewCount: 45000, likeCount: 890, commentCount: 67),
                    createdAt: Date(),
                    transcript: nil,
                    factsText: nil,
                    summaryText: nil,
                    notHunting: false,
                    notes: nil,
                    videoType: nil,
                    hook: nil,
                    hookType: nil,
                    intro: nil
                ),
                onRemove: { print("Remove tapped") }
            )
            .padding()
        }
    }
}
// MARK: - Research Topic Video Card
struct ResearchTopicVideoCard1: View {
    let video: YouTubeVideo
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with remove button
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(height: 180)
                .clipped()
                .cornerRadius(12)
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.red))
                }
                .padding(8)
            }
            
            // Title
            Text(video.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundColor(.primary)
            
            // Stats
            HStack(spacing: 12) {
                Label("\(video.stats.viewCount.formatted())", systemImage: "eye.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label("\(video.stats.likeCount.formatted())", systemImage: "hand.thumbsup.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Metadata badges
            HStack(spacing: 8) {
                if video.hasTranscript {
                    Badge(icon: "doc.text", color: .green)
                }
                if video.hasFacts {
                    Badge(icon: "list.bullet", color: .blue)
                }
                if video.hasSummary {
                    Badge(icon: "doc.plaintext", color: .purple)
                }
                if video.notHunting {
                    Badge(icon: "xmark.circle", color: .red)
                }
                if let hookType = video.hookType {
                    Badge(icon: "hook", color: .orange)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Badge Helper
struct Badge3: View {
    let icon: String
    let color: Color
    
    var body: some View {
        Image(systemName: icon)
            .font(.caption2)
            .foregroundColor(color)
            .padding(4)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }
}

// MARK: - Edit Topic Sheet
// MARK: - Edit Topic Sheet
struct EditTopicSheet: View {
    let topic: ResearchTopic
    @ObservedObject var manager: ResearchTopicManager
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String
    @State private var description: String
    @State private var topicNotes: String
    @State private var isSaving = false
    
    @StateObject private var videoViewModel = VideoSearchViewModel.instance
    
    init(topic: ResearchTopic, manager: ResearchTopicManager) {
        self.topic = topic
        self.manager = manager
        _title = State(initialValue: topic.title)
        _description = State(initialValue: topic.description ?? "")
        _topicNotes = State(initialValue: topic.topicNotes ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Topic Info") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Research Notes") {
                    TextEditor(text: $topicNotes)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("Edit Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveTopic() }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button("Copy Video Titles") {
                        copyVideoTitles()
                    }
                }
            }
        }
    }
    
    private func saveTopic() async {
        isSaving = true
        
        var updatedTopic = topic
        updatedTopic.title = title
        updatedTopic.description = description.isEmpty ? nil : description
        updatedTopic.topicNotes = topicNotes.isEmpty ? nil : topicNotes
        
        do {
            try await manager.updateTopic(updatedTopic)
            dismiss()
        } catch {
            print("❌ Error saving topic: \(error)")
        }
        
        isSaving = false
    }
    
    private func copyVideoTitles() {
        // Use the already-cached videos from the ViewModel
        let topicVideos = videoViewModel.allVideos.filter { video in
            topic.videoIds.contains(video.videoId)
        }
        
        // Get titles and join with commas
        let titles = topicVideos.map { $0.title }.joined(separator: ", ")
        
        // Copy to clipboard
        UIPasteboard.general.string = titles
        print("📋 Copied \(topicVideos.count) video titles: \(titles)")
    }
}
struct EditTopicSheetOld: View {
    let topic: ResearchTopic
    @ObservedObject var manager: ResearchTopicManager
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String
    @State private var description: String
    @State private var topicNotes: String
    @State private var isSaving = false
    
    init(topic: ResearchTopic, manager: ResearchTopicManager) {
        self.topic = topic
        self.manager = manager
        _title = State(initialValue: topic.title)
        _description = State(initialValue: topic.description ?? "")
        _topicNotes = State(initialValue: topic.topicNotes ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Topic Info") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Research Notes") {
                    TextEditor(text: $topicNotes)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("Edit Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveTopic() }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }
    
    private func saveTopic() async {
        isSaving = true
        
        var updatedTopic = topic
        updatedTopic.title = title
        updatedTopic.description = description.isEmpty ? nil : description
        updatedTopic.topicNotes = topicNotes.isEmpty ? nil : topicNotes
        
        do {
            try await manager.updateTopic(updatedTopic)
            dismiss()
        } catch {
            print("❌ Error saving topic: \(error)")
        }
        
        isSaving = false
    }
}


struct ResearchTopicDetailView1: View {
    let topic: ResearchTopic
    @ObservedObject var manager: ResearchTopicManager
    
    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = false
    @State private var showEditSheet = false
    @State private var selectedVideo: YouTubeVideo?
    
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Topic Info Card
                topicInfoCard
                
                Divider()
                
                // Videos Header
                HStack {
                    Text("\(videos.count) Videos")
                        .font(.headline)
                    Spacer()
                    Button(action: { Task { await loadVideos() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding(.horizontal)
                
                // Videos Grid
                if isLoading {
                    ProgressView("Loading videos...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if videos.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(videos) { video in
                            Button {
                                selectedVideo = video
                            } label: {
                                ResearchTopicVideoCard(
                                    video: video,
                                    onRemove: {
                                        Task { await removeVideo(video) }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showEditSheet = true }) {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .task {
            await loadVideos()
        }
        .navigationDestination(item: $selectedVideo) { video in
            YouTubeVideoDetailView(video: video)
        }
        .sheet(isPresented: $showEditSheet) {
            EditTopicSheet(topic: topic, manager: manager)
        }
    }
    
    // MARK: - Topic Info Card
    private var topicInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let description = topic.description {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("\(topic.videoIds.count) videos", systemImage: "video")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(topic.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let notes = topic.topicNotes, !notes.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Research Notes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No videos in this topic")
                .font(.headline)
            
            Text("Assign videos from the search view or video importer")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Load Videos
    private func loadVideos() async {
        isLoading = true
        
        let firebaseService = YouTubeFirebaseService.shared
        var loadedVideos: [YouTubeVideo] = []
        
        for videoId in topic.videoIds {
            do {
                if let video = try await firebaseService.fetchVideo(videoId: videoId) {
                    loadedVideos.append(video)
                }
            } catch {
                print("❌ Error loading video \(videoId): \(error)")
            }
        }
        
        videos = loadedVideos
        isLoading = false
    }
    
    // MARK: - Remove Video
    private func removeVideo(_ video: YouTubeVideo) async {
        do {
            try await manager.removeVideoFromTopic(topicId: topic.id, videoId: video.videoId)
            videos.removeAll { $0.videoId == video.videoId }
            print("✅ Removed video from topic")
        } catch {
            print("❌ Error removing video: \(error)")
        }
    }
}

// MARK: - Research Topic Video Card
struct ResearchTopicVideoCard12: View {
    let video: YouTubeVideo
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with remove button
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(height: 180)
                .clipped()
                .cornerRadius(12)
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.red))
                }
                .padding(8)
            }
            
            // Title
            Text(video.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundColor(.primary)
            
            // Stats
            HStack(spacing: 12) {
                Label("\(video.stats.viewCount.formatted())", systemImage: "eye.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label("\(video.stats.likeCount.formatted())", systemImage: "hand.thumbsup.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Metadata badges
            HStack(spacing: 8) {
                if video.hasTranscript {
                    Badge(icon: "doc.text", color: .green)
                }
                if video.hasFacts {
                    Badge(icon: "list.bullet", color: .blue)
                }
                if video.hasSummary {
                    Badge(icon: "doc.plaintext", color: .purple)
                }
                if video.notHunting {
                    Badge(icon: "xmark.circle", color: .red)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Badge Helper
struct Badge1: View {
    let icon: String
    let color: Color
    
    var body: some View {
        Image(systemName: icon)
            .font(.caption2)
            .foregroundColor(color)
            .padding(4)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }
}

// MARK: - Edit Topic Sheet
struct EditTopicSheet1: View {
    let topic: ResearchTopic
    @ObservedObject var manager: ResearchTopicManager
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String
    @State private var description: String
    @State private var topicNotes: String
    @State private var isSaving = false
    
    init(topic: ResearchTopic, manager: ResearchTopicManager) {
        self.topic = topic
        self.manager = manager
        _title = State(initialValue: topic.title)
        _description = State(initialValue: topic.description ?? "")
        _topicNotes = State(initialValue: topic.topicNotes ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Topic Info") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Research Notes") {
                    TextEditor(text: $topicNotes)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("Edit Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveTopic() }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }
    
    private func saveTopic() async {
        isSaving = true
        
        var updatedTopic = topic
        updatedTopic.title = title
        updatedTopic.description = description.isEmpty ? nil : description
        updatedTopic.topicNotes = topicNotes.isEmpty ? nil : topicNotes
        
        do {
            try await manager.updateTopic(updatedTopic)
            dismiss()
        } catch {
            print("❌ Error saving topic: \(error)")
        }
        
        isSaving = false
    }
}




// MARK: - Research Topic Detail View
struct ResearchTopicDetailView: View {
    let topic: ResearchTopic
    @ObservedObject var manager: ResearchTopicManager
    
    @State private var editedTopic: ResearchTopic
    @State private var showEditSheet = false
    @State private var quickNote = ""
    @State private var showQuickNoteField = false
    
    init(topic: ResearchTopic, manager: ResearchTopicManager) {
        self.topic = topic
        self.manager = manager
        _editedTopic = State(initialValue: topic)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Quick Note Append Section - AT THE TOP
                quickNoteSection
                
                Divider()
                
                // Planning & Organization
                planningSection
                
                Divider()
                
                // Content Details
                contentSection
                
                Divider()
                
                // Creative Elements
                creativeSection
                
                Divider()
                
                // Videos
                videosSection
                
                Divider()
                
                // Full Notes
                notesSection
            }
            .padding()
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditTopicSheet(topic: editedTopic, manager: manager)
        }
    }
    
    // MARK: - Quick Note Section
    private var quickNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Append to Current Topic Notes")
                .font(.headline)
            
            if showQuickNoteField {
                VStack(spacing: 8) {
                    TextEditor(text: $quickNote)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    HStack {
                        Button("Cancel") {
                            quickNote = ""
                            showQuickNoteField = false
                        }
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Save & Close") {
                            saveQuickNote()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                Button(action: { showQuickNoteField = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Quick Note")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Planning Section
    private var planningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Planning & Organization")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Build Order")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(editedTopic.buildOrder)")
                        .font(.title3)
                }
                
                Spacer()
                
                VStack(alignment: .leading) {
                    Text("Target Month")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(editedTopic.targetPublishedMonth)
                        .font(.title3)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(editedTopic.category)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(editedTopic.status.rawValue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.1))
                    .foregroundColor(statusColor)
                    .cornerRadius(6)
            }
            
            if editedTopic.isRemake {
                Label("This is a remake/repurpose", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Content Section
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content Details")
                .font(.headline)
            
            if let description = editedTopic.description {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(description)
                        .font(.body)
                }
            }
            
            if let howHelpsBrain = editedTopic.howHelpsBrain {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How does this help someone get inside the brain of a deer?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(howHelpsBrain)
                        .font(.body)
                        .padding()
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Creative Section
    private var creativeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Creative Elements")
                .font(.headline)
            
            if let keyVisuals = editedTopic.keyVisuals {
                DetailBox(title: "Key Visuals", content: keyVisuals)
            }
            
            if let titleIdeas = editedTopic.titleIdeas {
                DetailBox(title: "Title Ideas", content: titleIdeas)
            }
            
            if let thumbnailIdeas = editedTopic.thumbnailIdeas {
                DetailBox(title: "Thumbnail Ideas", content: thumbnailIdeas)
            }
        }
    }
    
    // MARK: - Videos Section
    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Linked Videos")
                    .font(.headline)
                Spacer()
                Text("\(editedTopic.videoIds.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if editedTopic.videoIds.isEmpty {
                Text("No videos linked yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(editedTopic.videoIds, id: \.self) { videoId in
                    Text(videoId)
                        .font(.caption)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                }
            }
        }
    }
    
    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Research Notes")
                .font(.headline)
            
            if let notes = editedTopic.topicNotes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            } else {
                Text("No notes yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
    
    // MARK: - Helpers
    private var statusColor: Color {
        switch editedTopic.status {
        case .idea: return .gray
        case .selected: return .green
        case .published: return .primary
        }
    }
    
    private func saveQuickNote() {
        guard !quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var updatedTopic = editedTopic
        let timestamp = Date().formatted(date: .abbreviated, time: .shortened)
        let newNote = "\n\n--- \(timestamp) ---\n\(quickNote)"
        
        if let existingNotes = updatedTopic.topicNotes {
            updatedTopic.topicNotes = existingNotes + newNote
        } else {
            updatedTopic.topicNotes = quickNote
        }
        
        Task {
            try await manager.updateTopic(updatedTopic)
            editedTopic = updatedTopic
            quickNote = ""
            showQuickNoteField = false
        }
    }
}

// MARK: - Detail Box Helper
struct DetailBox: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(content)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }
}
 
 */
//// MARK: - Research Topic Detail View
//struct ResearchTopicDetailView: View {
//    let topic: ResearchTopic
//    @ObservedObject var manager: ResearchTopicManager
//    
//    @State private var editedTopic: ResearchTopic
//    @State private var showEditSheet = false
//    @State private var quickNote = ""
//    
//    init(topic: ResearchTopic, manager: ResearchTopicManager) {
//        self.topic = topic
//        self.manager = manager
//        _editedTopic = State(initialValue: topic)
//    }
//    
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 20) {
//                // Quick Note Append Section - AT THE TOP (Always Expanded)
//                quickNoteSection
//                
//                Divider()
//                
//                // Planning & Organization
//                planningSection
//                
//                Divider()
//                
//                // Content Details
//                contentSection
//                
//                Divider()
//                
//                // Creative Elements
//                creativeSection
//                
//                Divider()
//                
//                // Full Notes (moved above videos)
//                notesSection
//                
//                Divider()
//                
//                // Videos - NOW AT THE BOTTOM
//                videosSection
//            }
//            .padding()
//        }
//        .navigationTitle(topic.title)
//        .navigationBarTitleDisplayMode(.inline)
//        .toolbar {
//            ToolbarItem(placement: .navigationBarTrailing) {
//                Button("Edit") {
//                    showEditSheet = true
//                }
//            }
//        }
//        .sheet(isPresented: $showEditSheet) {
//            EditTopicSheet(topic: editedTopic, manager: manager)
//        }
//    }
//    
//    // MARK: - Quick Note Section (Always Expanded)
//    private var quickNoteSection: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            Text("Append to Current Topic Notes")
//                .font(.headline)
//            
//            TextEditor(text: $quickNote)
//                .frame(minHeight: 100)
//                .padding(8)
//                .background(Color(.systemGray6))
//                .cornerRadius(8)
//            
//            HStack {
//                Spacer()
//                
//                Button("Save & Close") {
//                    saveQuickNote()
//                }
//                .buttonStyle(.borderedProminent)
//                .disabled(quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
//            }
//        }
//    }
//    
//    // MARK: - Planning Section
//    private var planningSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Planning & Organization")
//                .font(.headline)
//            
//            HStack {
//                VStack(alignment: .leading) {
//                    Text("Build Order")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    Text("\(editedTopic.buildOrder)")
//                        .font(.title3)
//                }
//                
//                Spacer()
//                
//                VStack(alignment: .leading) {
//                    Text("Target Month")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    Text(editedTopic.targetPublishedMonth)
//                        .font(.title3)
//                }
//            }
//            
//            VStack(alignment: .leading, spacing: 4) {
//                Text("Category")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                Text(editedTopic.category)
//                    .padding(.horizontal, 12)
//                    .padding(.vertical, 6)
//                    .background(Color.blue.opacity(0.1))
//                    .foregroundColor(.blue)
//                    .cornerRadius(6)
//            }
//            
//            VStack(alignment: .leading, spacing: 4) {
//                Text("Status")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                Text(editedTopic.status.rawValue)
//                    .padding(.horizontal, 12)
//                    .padding(.vertical, 6)
//                    .background(statusColor.opacity(0.1))
//                    .foregroundColor(statusColor)
//                    .cornerRadius(6)
//            }
//            
//            if editedTopic.isRemake {
//                Label("This is a remake/repurpose", systemImage: "arrow.triangle.2.circlepath")
//                    .font(.caption)
//                    .foregroundColor(.orange)
//            }
//        }
//    }
//    
//    // MARK: - Content Section
//    private var contentSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Content Details")
//                .font(.headline)
//            
//            if let description = editedTopic.description {
//                VStack(alignment: .leading, spacing: 4) {
//                    Text("Description")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    Text(description)
//                        .font(.body)
//                }
//            }
//            
//            if let howHelpsBrain = editedTopic.howHelpsBrain {
//                VStack(alignment: .leading, spacing: 4) {
//                    Text("How does this help someone get inside the brain of a deer?")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    Text(howHelpsBrain)
//                        .font(.body)
//                        .padding()
//                        .background(Color.green.opacity(0.05))
//                        .cornerRadius(8)
//                }
//            }
//        }
//    }
//    
//    // MARK: - Creative Section
//    private var creativeSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Creative Elements")
//                .font(.headline)
//            
//            if let keyVisuals = editedTopic.keyVisuals {
//                DetailBox(title: "Key Visuals", content: keyVisuals)
//            }
//            
//            if let titleIdeas = editedTopic.titleIdeas {
//                DetailBox(title: "Title Ideas", content: titleIdeas)
//            }
//            
//            if let thumbnailIdeas = editedTopic.thumbnailIdeas {
//                DetailBox(title: "Thumbnail Ideas", content: thumbnailIdeas)
//            }
//        }
//    }
//    
//    // MARK: - Notes Section (Now above videos)
//    private var notesSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Research Notes")
//                .font(.headline)
//            
//            if let notes = editedTopic.topicNotes, !notes.isEmpty {
//                Text(notes)
//                    .font(.body)
//                    .padding()
//                    .background(Color(.systemGray6))
//                    .cornerRadius(8)
//            } else {
//                Text("No notes yet")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                    .frame(maxWidth: .infinity, alignment: .center)
//                    .padding()
//            }
//        }
//    }
//    
//    // MARK: - Videos Section (Now at the bottom with proper cards)
//    private var videosSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            HStack {
//                Text("Linked Videos")
//                    .font(.headline)
//                Spacer()
//                Text("\(editedTopic.videoIds.count)")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//            }
//            
//            if editedTopic.videoIds.isEmpty {
//                Text("No videos linked yet")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                    .frame(maxWidth: .infinity, alignment: .center)
//                    .padding()
//            } else {
//                ForEach(editedTopic.videoIds, id: \.self) { videoId in
//                    VideoCardView(videoId: videoId)
//                }
//            }
//        }
//    }
//    
//    // MARK: - Helpers
//    private var statusColor: Color {
//        switch editedTopic.status {
//        case .idea: return .gray
//        case .selected: return .green
//        case .published: return .primary
//        }
//    }
//    
//    private func saveQuickNote() {
//        guard !quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
//        
//        var updatedTopic = editedTopic
//        let timestamp = Date().formatted(date: .abbreviated, time: .shortened)
//        let newNote = "\n\n--- \(timestamp) ---\n\(quickNote)"
//        
//        if let existingNotes = updatedTopic.topicNotes {
//            updatedTopic.topicNotes = existingNotes + newNote
//        } else {
//            updatedTopic.topicNotes = quickNote
//        }
//        
//        Task {
//            try await manager.updateTopic(updatedTopic)
//            editedTopic = updatedTopic
//            quickNote = ""
//        }
//    }
//}
//
//// MARK: - Video Card View (Reusable Component)
//struct VideoCardView: View {
//    let videoId: String
//    @StateObject private var videoManager = VideoManager.shared
//    @State private var video: Video?
//    
//    var body: some View {
//        HStack(spacing: 12) {
//            // Thumbnail
//            if let thumbnailURL = video?.thumbnailURL {
//                AsyncImage(url: URL(string: thumbnailURL)) { image in
//                    image
//                        .resizable()
//                        .aspectRatio(contentMode: .fill)
//                } placeholder: {
//                    Rectangle()
//                        .fill(Color.gray.opacity(0.3))
//                        .overlay {
//                            ProgressView()
//                        }
//                }
//                .frame(width: 120, height: 68)
//                .cornerRadius(8)
//            } else {
//                Rectangle()
//                    .fill(Color.gray.opacity(0.3))
//                    .frame(width: 120, height: 68)
//                    .cornerRadius(8)
//                    .overlay {
//                        Image(systemName: "video")
//                            .foregroundColor(.gray)
//                    }
//            }
//            
//            // Video Info
//            VStack(alignment: .leading, spacing: 4) {
//                Text(video?.title ?? "Loading...")
//                    .font(.subheadline)
//                    .fontWeight(.medium)
//                    .lineLimit(2)
//                
//                if let video = video {
//                    HStack(spacing: 8) {
//                        Label(formatViews(video.viewCount), systemImage: "eye")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                        
//                        if let publishedAt = video.publishedAt {
//                            Label(publishedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                    
//                    if let duration = video.duration {
//                        Text(formatDuration(duration))
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                }
//            }
//            
//            Spacer()
//            
//            Image(systemName: "chevron.right")
//                .foregroundColor(.secondary)
//                .font(.caption)
//        }
//        .padding()
//        .background(Color(.systemGray6))
//        .cornerRadius(12)
//        .task {
//            await loadVideo()
//        }
//    }
//    
//    private func loadVideo() async {
//        do {
//            video = try await videoManager.fetchVideo(id: videoId)
//        } catch {
//            print("❌ Error loading video \(videoId): \(error)")
//        }
//    }
//    
//    private func formatViews(_ count: Int) -> String {
//        if count >= 1_000_000 {
//            return String(format: "%.1fM", Double(count) / 1_000_000)
//        } else if count >= 1_000 {
//            return String(format: "%.1fK", Double(count) / 1_000)
//        }
//        return "\(count)"
//    }
//    
//    private func formatDuration(_ seconds: Int) -> String {
//        let hours = seconds / 3600
//        let minutes = (seconds % 3600) / 60
//        let secs = seconds % 60
//        
//        if hours > 0 {
//            return String(format: "%d:%02d:%02d", hours, minutes, secs)
//        } else {
//            return String(format: "%d:%02d", minutes, secs)
//        }
//    }
//}
//
//// MARK: - Detail Box Helper
//struct DetailBox: View {
//    let title: String
//    let content: String
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            Text(title)
//                .font(.caption)
//                .foregroundColor(.secondary)
//            Text(content)
//                .font(.body)
//                .padding()
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .background(Color(.systemGray6))
//                .cornerRadius(8)
//        }
//    }
//}



// MARK: - Edit Topic Sheet
struct EditTopicSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var manager = ResearchTopicManager.shared  // ✅ Use shared instance
    
    @State private var topic: ResearchTopic
    
    init(topic: ResearchTopic) {  // ✅ No need to pass manager
        _topic = State(initialValue: topic)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Info") {
                    TextField("Title", text: $topic.title)
                    TextField("Description", text: Binding(
                        get: { topic.description ?? "" },
                        set: { topic.description = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
                
                Section("Planning") {
                    Stepper("Build Order: \(topic.buildOrder)", value: $topic.buildOrder, in: 1...9999, step: 10)
                    
                    TextField("Target Month", text: $topic.targetPublishedMonth)
                    
                    Picker("Category", selection: $topic.category) {
                        ForEach(TopicCategory.defaultCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    
                    Picker("Status", selection: $topic.status) {
                        ForEach(TopicStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    
                    Toggle("Is Remake/Repurpose", isOn: $topic.isRemake)
                }
                
                Section("Content Strategy") {
                    TextField("How does this help get inside the brain of a deer?", text: Binding(
                        get: { topic.howHelpsBrain ?? "" },
                        set: { topic.howHelpsBrain = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(4...8)
                }
                
                Section("Creative Elements") {
                    TextField("Key Visuals", text: Binding(
                        get: { topic.keyVisuals ?? "" },
                        set: { topic.keyVisuals = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                    
                    TextField("Title Ideas", text: Binding(
                        get: { topic.titleIdeas ?? "" },
                        set: { topic.titleIdeas = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                    
                    TextField("Thumbnail Ideas", text: Binding(
                        get: { topic.thumbnailIdeas ?? "" },
                        set: { topic.thumbnailIdeas = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
                
                Section("Research Notes") {
                    TextField("Notes", text: Binding(
                        get: { topic.topicNotes ?? "" },
                        set: { topic.topicNotes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(5...15)
                }
            }
            .navigationTitle("Edit Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTopic()
                    }
                    .disabled(topic.title.isEmpty)
                }
            }
        }
    }
    
    private func saveTopic() {
        Task {
            try await manager.updateTopic(topic)
            dismiss()
        }
    }
}

//
//// MARK: - Research Topic Detail View
//struct ResearchTopicDetailView: View {
//    let topic: ResearchTopic
//    @ObservedObject var manager: ResearchTopicManager
//    @EnvironmentObject var viewModel: VideoSearchViewModel  // ✅ Use cached videos
//    
//    @State private var editedTopic: ResearchTopic
//    @State private var showEditSheet = false
//    @State private var quickNote = ""
//    @State private var selectedVideo: YouTubeVideo?
//    
//    // ✅ Computed property - filters from already-loaded videos
//    var videos: [YouTubeVideo] {
//        viewModel.allVideos.filter { topic.videoIds.contains($0.videoId) }
//    }
//    
//    init(topic: ResearchTopic, manager: ResearchTopicManager) {
//        self.topic = topic
//        self.manager = manager
//        _editedTopic = State(initialValue: topic)
//    }
//    
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 20) {
//                // Quick Note Append Section - AT THE TOP (Always Expanded)
//                quickNoteSection
//                
//                Divider()
//                
//                // Planning & Organization
//                planningSection
//                
//                Divider()
//                
//                // Content Details
//                contentSection
//                
//                Divider()
//                
//                // Creative Elements
//                creativeSection
//                
//                Divider()
//                
//                // Full Notes (above videos)
//                notesSection
//                
//                Divider()
//                
//                // Videos - AT THE BOTTOM
//                videosSection
//            }
//            .padding()
//        }
//        .navigationTitle(topic.title)
//        .navigationBarTitleDisplayMode(.inline)
//        .toolbar {
//            ToolbarItem(placement: .navigationBarTrailing) {
//                Button("Edit") {
//                    showEditSheet = true
//                }
//            }
//        }
//        .navigationDestination(item: $selectedVideo) { video in
//            YouTubeVideoDetailView(video: video)
//        }
//        .sheet(isPresented: $showEditSheet) {
//            EditTopicSheet(topic: editedTopic, manager: manager)
//        }
//    }
//    
//    // MARK: - Quick Note Section (Always Expanded)
//    private var quickNoteSection: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            Text("Append to Current Topic Notes")
//                .font(.headline)
//            
//            TextEditor(text: $quickNote)
//                .frame(minHeight: 100)
//                .padding(8)
//                .background(Color(.systemGray6))
//                .cornerRadius(8)
//            
//            HStack {
//                Spacer()
//                
//                Button("Save & Close") {
//                    saveQuickNote()
//                }
//                .buttonStyle(.borderedProminent)
//                .disabled(quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
//            }
//        }
//    }
//    
//    // MARK: - Planning Section
//    private var planningSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Planning & Organization")
//                .font(.headline)
//            
//            HStack {
//                VStack(alignment: .leading) {
//                    Text("Build Order")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    Text("\(editedTopic.buildOrder)")
//                        .font(.title3)
//                }
//                
//                Spacer()
//                
//                VStack(alignment: .leading) {
//                    Text("Target Month")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    Text(editedTopic.targetPublishedMonth)
//                        .font(.title3)
//                }
//            }
//            
//            VStack(alignment: .leading, spacing: 4) {
//                Text("Category")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                Text(editedTopic.category)
//                    .padding(.horizontal, 12)
//                    .padding(.vertical, 6)
//                    .background(Color.blue.opacity(0.1))
//                    .foregroundColor(.blue)
//                    .cornerRadius(6)
//            }
//            
//            VStack(alignment: .leading, spacing: 4) {
//                Text("Status")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                Text(editedTopic.status.rawValue)
//                    .padding(.horizontal, 12)
//                    .padding(.vertical, 6)
//                    .background(statusColor.opacity(0.1))
//                    .foregroundColor(statusColor)
//                    .cornerRadius(6)
//            }
//            
//            if editedTopic.isRemake {
//                Label("This is a remake/repurpose", systemImage: "arrow.triangle.2.circlepath")
//                    .font(.caption)
//                    .foregroundColor(.orange)
//            }
//        }
//    }
//    
//    // MARK: - Content Section
//    private var contentSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Content Details")
//                .font(.headline)
//            
//            if let description = editedTopic.description {
//                VStack(alignment: .leading, spacing: 4) {
//                    Text("Description")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    Text(description)
//                        .font(.body)
//                }
//            }
//            
//            if let howHelpsBrain = editedTopic.howHelpsBrain {
//                VStack(alignment: .leading, spacing: 4) {
//                    Text("How does this help someone get inside the brain of a deer?")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    Text(howHelpsBrain)
//                        .font(.body)
//                        .padding()
//                        .background(Color.green.opacity(0.05))
//                        .cornerRadius(8)
//                }
//            }
//        }
//    }
//    
//    // MARK: - Creative Section
//    private var creativeSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Creative Elements")
//                .font(.headline)
//            
//            if let keyVisuals = editedTopic.keyVisuals {
//                DetailBox(title: "Key Visuals", content: keyVisuals)
//            }
//            
//            if let titleIdeas = editedTopic.titleIdeas {
//                DetailBox(title: "Title Ideas", content: titleIdeas)
//            }
//            
//            if let thumbnailIdeas = editedTopic.thumbnailIdeas {
//                DetailBox(title: "Thumbnail Ideas", content: thumbnailIdeas)
//            }
//        }
//    }
//    
//    // MARK: - Notes Section (Now above videos)
//    private var notesSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Research Notes")
//                .font(.headline)
//            
//            if let notes = editedTopic.topicNotes, !notes.isEmpty {
//                Text(notes)
//                    .font(.body)
//                    .padding()
//                    .background(Color(.systemGray6))
//                    .cornerRadius(8)
//            } else {
//                Text("No notes yet")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                    .frame(maxWidth: .infinity, alignment: .center)
//                    .padding()
//            }
//        }
//    }
//    
//    // MARK: - Videos Section (Now at the bottom with proper cards)
//    private var videosSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            HStack {
//                Text("Linked Videos")
//                    .font(.headline)
//                Spacer()
//                Text("\(videos.count)")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//            }
//            
//            if viewModel.isLoading {
//                ProgressView("Loading videos...")
//                    .frame(maxWidth: .infinity, alignment: .center)
//                    .padding()
//            } else if videos.isEmpty {
//                emptyStateView
//            } else {
//                ForEach(videos) { video in
//                    Button {
//                        selectedVideo = video
//                    } label: {
//                        ResearchTopicVideoCard(
//                            video: video,
//                            onRemove: {
//                                Task { await removeVideo(video) }
//                            }
//                        )
//                    }
//                    .buttonStyle(.plain)
//                }
//            }
//        }
//    }
//    
//    // MARK: - Empty State
//    private var emptyStateView: some View {
//        VStack(spacing: 16) {
//            Image(systemName: "video.slash")
//                .font(.system(size: 60))
//                .foregroundColor(.gray)
//            
//            Text("No videos in this topic")
//                .font(.headline)
//            
//            Text("Assign videos from the search view or video importer")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//                .multilineTextAlignment(.center)
//                .padding(.horizontal)
//        }
//        .frame(maxWidth: .infinity)
//        .padding(.vertical, 60)
//    }
//    
//    // MARK: - Helpers
//    private var statusColor: Color {
//        switch editedTopic.status {
//        case .idea: return .gray
//        case .selected: return .green
//        case .published: return .primary
//        }
//    }
//    
//    private func saveQuickNote() {
//        guard !quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
//        
//        var updatedTopic = editedTopic
//        let timestamp = Date().formatted(date: .abbreviated, time: .shortened)
//        let newNote = "\n\n--- \(timestamp) ---\n\(quickNote)"
//        
//        if let existingNotes = updatedTopic.topicNotes {
//            updatedTopic.topicNotes = existingNotes + newNote
//        } else {
//            updatedTopic.topicNotes = quickNote
//        }
//        
//        Task {
//            try await manager.updateTopic(updatedTopic)
//            editedTopic = updatedTopic
//            quickNote = ""
//        }
//    }
//    
//    // MARK: - Remove Video
//    private func removeVideo(_ video: YouTubeVideo) async {
//        do {
//            try await manager.removeVideoFromTopic(topicId: topic.id, videoId: video.videoId)
//            
//            // Refresh topic list to update video counts
//            try await manager.fetchAllTopics()
//            
//            print("✅ Removed video from topic")
//        } catch {
//            print("❌ Error removing video: \(error)")
//        }
//    }
//}
//
//// MARK: - Detail Box Helper
//struct DetailBox: View {
//    let title: String
//    let content: String
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            Text(title)
//                .font(.caption)
//                .foregroundColor(.secondary)
//            Text(content)
//                .font(.body)
//                .padding()
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .background(Color(.systemGray6))
//                .cornerRadius(8)
//        }
//    }
//}


// MARK: - Month Helper
enum TopicMonth {
    static let allMonths = [
        "no month",
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December","2027"
    ]
    
    // Helper for sorting in calendar view
       static func sortOrder(_ month: String) -> Int {
           allMonths.firstIndex(of: month) ?? 0
       }
}

// MARK: - Research Topic Detail View (Inline Editable)
//struct ResearchTopicDetailView: View {
//    let topic: ResearchTopic
//    @ObservedObject var manager: ResearchTopicManager
//    @EnvironmentObject var viewModel: VideoSearchViewModel
    
    struct ResearchTopicDetailView: View {
        @EnvironmentObject var nav: NavigationViewModel
        @State private var isCreatingScript = false
        let topic: ResearchTopic
        @StateObject private var manager = ResearchTopicManager.shared  // ✅ Use shared instance
        @EnvironmentObject var viewModel: VideoSearchViewModel
        
        @State private var editedTopic: ResearchTopic
    
   // @State private var editedTopic: ResearchTopic
    @State private var quickNote = ""
    @State private var selectedVideo: YouTubeVideo?
    @State private var hasUnsavedChanges = false
    @State private var isSaving = false
    @State private var buildOrderText: String
    
    // ✅ Computed property - filters from already-loaded videos
    var videos: [YouTubeVideo] {
        viewModel.allVideos.filter { topic.videoIds.contains($0.videoId) }
    }
    
    init(topic: ResearchTopic) {
        self.topic = topic
        _editedTopic = State(initialValue: topic)
        _buildOrderText = State(initialValue: String(topic.buildOrder))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Quick Note Append Section - AT THE TOP (Always Expanded)
                quickNoteSection
                
                Divider()
                
                // Planning & Organization (Inline Editable)
                planningSection
                
                Divider()
                
                // Content Details (Inline Editable)
                contentSection
                
                Divider()
                
                // Creative Elements (Inline Editable)
                creativeSection
                
                Divider()
                
                // Full Notes (Inline Editable)
                notesSection
                
                Divider()
                
                // Videos - AT THE BOTTOM
                videosSection
            }
            .padding()
        }
        .navigationTitle(editedTopic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                    if hasUnsavedChanges {
                        Button(action: { saveChanges() }) {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isSaving)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await startScript() }
                    } label: {
                        if isCreatingScript {
                            ProgressView()
                        } else {
                            Label("Start Script", systemImage: "doc.badge.plus")
                        }
                    }
                    .disabled(isCreatingScript)
                }
        }
        .navigationDestination(item: $selectedVideo) { video in
            YouTubeVideoDetailView(video: video)
        }
    }
    
    // MARK: - Quick Note Section (Always Expanded)
    private var quickNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Append to Current Topic Notes")
                .font(.headline)
            
            TextEditor(text: $quickNote)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            
            HStack {
                Spacer()
                
                Button("Save & Close") {
                    saveQuickNote()
                }
                .buttonStyle(.borderedProminent)
                .disabled(quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    // MARK: - Planning Section (Inline Editable)
    private var planningSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Planning & Organization")
                .font(.headline)
            
            // Title (Editable)
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Topic title", text: $editedTopic.title)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: editedTopic.title) { _, _ in hasUnsavedChanges = true }
            }
            
            // Build Order (Editable TextField)
            VStack(alignment: .leading, spacing: 4) {
                Text("Build Order")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Build order", text: $buildOrderText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .onChange(of: buildOrderText) { _, newValue in
                        if let number = Int(newValue) {
                            editedTopic.buildOrder = number
                            hasUnsavedChanges = true
                        }
                    }
            }
            
            // Target Month (Picker)
            VStack(alignment: .leading, spacing: 4) {
                Text("Target Month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Target Month", selection: $editedTopic.targetPublishedMonth) {
                    ForEach(TopicMonth.allMonths, id: \.self) { month in
                        Text(month).tag(month)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: editedTopic.targetPublishedMonth) { _, _ in hasUnsavedChanges = true }
            }
            
            // Category (Picker)
            VStack(alignment: .leading, spacing: 4) {
                Text("Category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Category", selection: $editedTopic.category) {
                    ForEach(TopicCategory.defaultCategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: editedTopic.category) { _, _ in hasUnsavedChanges = true }
            }
            
            // Status (Picker - Only 3 options)
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Status", selection: $editedTopic.status) {
                    ForEach(TopicStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: editedTopic.status) { _, _ in hasUnsavedChanges = true }
            }
            
            // Is Remake Toggle
            Toggle("Is Remake/Repurpose", isOn: $editedTopic.isRemake)
                .onChange(of: editedTopic.isRemake) { _, _ in hasUnsavedChanges = true }
        }
    }
    
    // MARK: - Content Section (Inline Editable)
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Content Details")
                .font(.headline)
            
            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { editedTopic.description ?? "" },
                    set: { editedTopic.description = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .onChange(of: editedTopic.description) { _, _ in hasUnsavedChanges = true }
            }
            
            // How helps brain
            VStack(alignment: .leading, spacing: 4) {
                Text("How does this help someone get inside the brain of a deer?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { editedTopic.howHelpsBrain ?? "" },
                    set: { editedTopic.howHelpsBrain = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color.green.opacity(0.05))
                .cornerRadius(8)
                .onChange(of: editedTopic.howHelpsBrain) { _, _ in hasUnsavedChanges = true }
            }
        }
    }
    
    // MARK: - Creative Section (Inline Editable)
    private var creativeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Creative Elements")
                .font(.headline)
            
            // Key Visuals
            VStack(alignment: .leading, spacing: 4) {
                Text("Key Visuals")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { editedTopic.keyVisuals ?? "" },
                    set: { editedTopic.keyVisuals = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .onChange(of: editedTopic.keyVisuals) { _, _ in hasUnsavedChanges = true }
            }
            
            // Title Ideas
            VStack(alignment: .leading, spacing: 4) {
                Text("Title Ideas")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { editedTopic.titleIdeas ?? "" },
                    set: { editedTopic.titleIdeas = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .onChange(of: editedTopic.titleIdeas) { _, _ in hasUnsavedChanges = true }
            }
            
            // Thumbnail Ideas
            VStack(alignment: .leading, spacing: 4) {
                Text("Thumbnail Ideas")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { editedTopic.thumbnailIdeas ?? "" },
                    set: { editedTopic.thumbnailIdeas = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .onChange(of: editedTopic.thumbnailIdeas) { _, _ in hasUnsavedChanges = true }
            }
        }
    }
    
    // MARK: - Notes Section (Inline Editable)
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Research Notes")
                .font(.headline)
            
            TextEditor(text: Binding(
                get: { editedTopic.topicNotes ?? "" },
                set: { editedTopic.topicNotes = $0.isEmpty ? nil : $0 }
            ))
            .frame(minHeight: 150)
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .onChange(of: editedTopic.topicNotes) { _, _ in hasUnsavedChanges = true }
        }
    }
    
    // MARK: - Videos Section
    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Linked Videos")
                    .font(.headline)
                Spacer()
                Text("\(videos.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if viewModel.isLoading {
                ProgressView("Loading videos...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if videos.isEmpty {
                emptyStateView
            } else {
                ForEach(videos) { video in
                    Button {
                        selectedVideo = video
                    } label: {
                        ResearchTopicVideoCard(
                            video: video,
                            onRemove: {
                                Task { await removeVideo(video) }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No videos in this topic")
                .font(.headline)
            
            Text("Assign videos from the search view or video importer")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Save Changes
    private func saveChanges() {
        isSaving = true
        
        Task {
            do {
                try await manager.updateTopic(editedTopic)
                hasUnsavedChanges = false
                isSaving = false
            } catch {
                print("❌ Error saving topic: \(error)")
                isSaving = false
            }
        }
    }
    
    // MARK: - Save Quick Note
    private func saveQuickNote() {
        guard !quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var updatedTopic = editedTopic
        let timestamp = Date().formatted(date: .abbreviated, time: .shortened)
        let newNote = "\n\n--- \(timestamp) ---\n\(quickNote)"
        
        if let existingNotes = updatedTopic.topicNotes {
            updatedTopic.topicNotes = existingNotes + newNote
        } else {
            updatedTopic.topicNotes = quickNote
        }
        
        Task {
            try await manager.updateTopic(updatedTopic)
            editedTopic = updatedTopic
            quickNote = ""
        }
    }
    
    // MARK: - Remove Video
    private func removeVideo(_ video: YouTubeVideo) async {
        do {
            try await manager.removeVideoFromTopic(topicId: topic.id, videoId: video.videoId)
            
            // Refresh topic list to update video counts
            try await manager.fetchAllTopics()
            
            print("✅ Removed video from topic")
        } catch {
            print("❌ Error removing video: \(error)")
        }
    }
        
        // MARK: - Start Script
        private func startScript() async {
            isCreatingScript = true
            
            let newScript = YTSCRIPT(
                title: editedTopic.title,
                sourceTopicId: editedTopic.id
            )
            
            do {
                try await YTSCRIPTManager.shared.createScript(newScript)
                await MainActor.run {
                    nav.push(.newScriptEditor(newScript))
                }
            } catch {
                print("❌ Failed to create script from topic: \(error)")
            }
            
            isCreatingScript = false
        }
}

// MARK: - Detail Box Helper (Not needed anymore, but keeping for reference)
struct DetailBox: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(content)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }
}
