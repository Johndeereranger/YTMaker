//
//  CreatorStudyListView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/16/26.
//


import SwiftUI

// MARK: - Creator Study List View
struct CreatorStudyListView: View {
    @StateObject private var viewModel = VideoSearchViewModel.instance
    @EnvironmentObject var nav: NavigationViewModel
    
    @State private var studyChannels: [YouTubeChannel] = []
    @State private var isLoading = true
    @State private var selectedFilter: ChannelFilter = .all
    @State private var selectedSort: ChannelSort = .alphabetical
    
    var filteredAndSortedChannels: [YouTubeChannel] {
        var filtered = studyChannels
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .hunting:
            filtered = filtered.filter { !$0.notHunting }
        case .notHunting:
            filtered = filtered.filter { $0.notHunting }
        }
        
        // Sort: pinned always first
        return filtered.sorted { channel1, channel2 in
            if channel1.isPinned != channel2.isPinned {
                return channel1.isPinned
            }
            
            switch selectedSort {
            case .alphabetical:
                return channel1.name.localizedCaseInsensitiveCompare(channel2.name) == .orderedAscending
            case .lastSynced:
                return channel1.lastSynced > channel2.lastSynced
            case .videoCount:
                return channel1.videoCount > channel2.videoCount
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter segment control
            Picker("Filter", selection: $selectedFilter) {
                ForEach(ChannelFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Sort picker
            HStack {
                Text("Sort by:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Sort", selection: $selectedSort) {
                    ForEach(ChannelSort.allCases, id: \.self) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            // Content
            Group {
                if isLoading {
                    ProgressView("Loading study creators...")
                } else if filteredAndSortedChannels.isEmpty {
                    if studyChannels.isEmpty {
                        ContentUnavailableView(
                            "No Study Creators",
                            systemImage: "person.2.slash",
                            description: Text("Mark channels as study creators in the channel list")
                        )
                    } else {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("No channels match current filter")
                        )
                    }
                } else {
                    List {
                        ForEach(filteredAndSortedChannels) { channel in
                            Button {
                                nav.push(.creatorDetail(channel))
                            } label: {
                                StudyCreatorRow(
                                    channel: channel,
                                    onTogglePin: {
                                        Task { await togglePin(channel: channel) }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Study Creators")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        nav.push(.youtubeChannelList)
                    } label: {
                        Label("Manage Study Creators", systemImage: "list.bullet")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadStudyCreators()
        }
        .refreshable {
            await loadStudyCreators()
        }
    }
    
    private func loadStudyCreators() async {
        isLoading = true
        
        do {
            let firebase = YouTubeFirebaseService.shared
            let allChannels = try await firebase.fetchAllChannels()
            studyChannels = allChannels
        } catch {
            print("❌ Failed to load study creators: \(error)")
        }
        
        isLoading = false
    }
    
    private func togglePin(channel: YouTubeChannel) async {
        if let index = studyChannels.firstIndex(where: { $0.channelId == channel.channelId }) {
            studyChannels[index].isPinned.toggle()
            
            do {
                let firebaseService = YouTubeFirebaseService.shared
                try await firebaseService.updateChannelPinStatus(
                    channelId: channel.channelId,
                    isPinned: studyChannels[index].isPinned
                )
                print("✅ Updated pin status for \(channel.name)")
            } catch {
                // Revert on error
                studyChannels[index].isPinned.toggle()
                print("❌ Failed to update pin status: \(error)")
            }
        }
    }
}

// MARK: - Study Creator Row

struct StudyCreatorRow: View {
    let channel: YouTubeChannel
    let onTogglePin: () -> Void

    @State private var isLoadingTemplate = false
    @State private var templateCopied = false
    @State private var templateError: String?

    var body: some View {
        HStack(spacing: 12) {
            // Pin flag button
            Button(action: onTogglePin) {
                Image(systemName: channel.isPinned ? "flag.fill" : "flag")
                    .foregroundColor(channel.isPinned ? .orange : .gray)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)

            AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name)
                        .font(.headline)

                    if !channel.notHunting {
                        Image(systemName: "scope")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                HStack(spacing: 12) {
                    Label("\(channel.videoCount)", systemImage: "play.rectangle")
                        .font(.caption)

                    if let formattedSubs = channel.formattedSubscriberCount {
                        Label(formattedSubs, systemImage: "person.2")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // Copy Template button
            Button {
                Task { await copyTemplate() }
            } label: {
                if isLoadingTemplate {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 24, height: 24)
                } else if templateCopied {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                } else {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.purple)
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoadingTemplate)

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }

    private func copyTemplate() async {
        isLoadingTemplate = true
        templateError = nil

        do {
            // Load videos for this channel
            let videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channel.channelId)

            // Load sentence data for all videos
            var sentenceData: [String: [SentenceFidelityTest]] = [:]
            for video in videos {
                let runs = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
                if !runs.isEmpty {
                    sentenceData[video.videoId] = runs
                }
            }

            // Check if we have enough data
            let videosWithData = videos.filter { sentenceData[$0.videoId] != nil }
            guard videosWithData.count >= 3 else {
                templateError = "Need at least 3 videos with sentence analysis"
                isLoadingTemplate = false
                return
            }

            // Extract template
            let service = TemplateExtractionService.shared
            if let template = await service.extractTemplate(
                channel: channel,
                videos: videos,
                sentenceData: sentenceData
            ) {
                // Copy to clipboard
                let text = service.exportTemplateAsText(template, videos: videos)
                #if canImport(UIKit)
                UIPasteboard.general.string = text
                #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #endif

                // Show success
                templateCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    templateCopied = false
                }
            } else {
                templateError = "Failed to extract template"
            }
        } catch {
            templateError = error.localizedDescription
            print("❌ Failed to copy template: \(error)")
        }

        isLoadingTemplate = false
    }
}
struct StudyCreatorRowOld: View {
    let channel: YouTubeChannel
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label("\(channel.videoCount)", systemImage: "play.rectangle")
                        .font(.caption)
                    
                    if let subscribers = channel.metadata?.subscriberCount {
                        Label("\(subscribers.formatted())", systemImage: "person.2")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}
//
//// MARK: - Creator Detail View
//struct CreatorDetailView: View {
//    let channel: YouTubeChannel
//    @EnvironmentObject var nav: NavigationViewModel
//    
//    @State private var videos: [YouTubeVideo] = []
//    @State private var analyzedVideos: [String: AlignmentData] = [:]
//    @State private var aggregation: AggregationData?
//    @State private var isLoading = true
//    @State private var selectedVideo: YouTubeVideo?
//    @State private var showManualIngestion = false
//    
//    var analyzedCount: Int {
//        analyzedVideos.count
//    }
//    
//    var canRunAggregation: Bool {
//        analyzedCount >= 10
//    }
//    
//    var body: some View {
//        List {
//            // Channel Overview
//            Section {
//                HStack(spacing: 12) {
//                    AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
//                        image
//                            .resizable()
//                            .aspectRatio(contentMode: .fill)
//                    } placeholder: {
//                        Circle()
//                            .fill(Color.gray.opacity(0.3))
//                    }
//                    .frame(width: 80, height: 80)
//                    .clipShape(Circle())
//                    
//                    VStack(alignment: .leading, spacing: 8) {
//                        Text(channel.name)
//                            .font(.title3)
//                            .fontWeight(.bold)
//                        
//                        if let subscribers = channel.metadata?.subscriberCount {
//                            Label("\(subscribers.formatted()) subscribers", systemImage: "person.2")
//                                .font(.caption)
//                        }
//                        
//                        Label("\(channel.videoCount) videos", systemImage: "play.rectangle")
//                            .font(.caption)
//                    }
//                }
//                .padding(.vertical, 8)
//            }
//            
//            // Analysis Progress
//            Section("Analysis Progress") {
//                HStack {
//                    VStack(alignment: .leading) {
//                        Text("\(analyzedCount) / \(videos.count)")
//                            .font(.title2)
//                            .fontWeight(.bold)
//                        Text("Videos Analyzed")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                    
//                    Spacer()
//                    
//                    if analyzedCount > 0 && videos.count > 0  {
//                        CircularProgressView(
//                            progress: Double(analyzedCount) / Double(videos.count),
//                            lineWidth: 8
//                        )
//                        .frame(width: 60, height: 60)
//                    }
//                }
//                .padding(.vertical, 8)
//                
//                if canRunAggregation && aggregation == nil {
//                    Button {
//                        // TODO: Run aggregation
//                    } label: {
//                        Label("Run Pattern Analysis", systemImage: "chart.bar.xaxis")
//                            .frame(maxWidth: .infinity)
//                    }
//                    .buttonStyle(.borderedProminent)
//                } else if let agg = aggregation {
//                    HStack {
//                        Image(systemName: "checkmark.circle.fill")
//                            .foregroundColor(.green)
//                        Text("Pattern analysis complete")
//                        Spacer()
//                        Text(agg.aggregationDate.formatted(date: .abbreviated, time: .omitted))
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                }
//            }
//            
//            // Videos
//            Section("Videos") {
//                ForEach(videos) { video in
//                    Button {
//                        nav.push(.manualIngestion(video))
////                        if analyzedVideos[video.videoId] != nil {
////                            // View analysis
////                            nav.push(.videoAnalysisDetail(video))
////                        } else {
////                            // Start analysis
////                            nav.push(.manualIngestion(video))
//////                            selectedVideo = video
//////                            showManualIngestion = true
////                        }
//                    } label: {
//                        VideoAnalysisRow(
//                            video: video,
//                            hasAnalysis: analyzedVideos[video.videoId] != nil
//                        )
//                    }
//                    .buttonStyle(.plain)
//                }
//            }
//        }
//        .navigationTitle("Creator Analysis")
//        .navigationBarTitleDisplayMode(.inline)
//        .task {
//            await loadData()
//        }
//        .refreshable {
//            await loadData()
//        }
//        .sheet(isPresented: $showManualIngestion) {
//            if let video = selectedVideo {
//                ManualIngestionView(video: video)
//            }
//        }
//    }
//    
//    private func loadData() async {
//        isLoading = true
//        
//        do {
//            let firebase = YouTubeFirebaseService.shared
//            let analysisFirebase = CreatorAnalysisFirebase.shared
//            
//            print("🔍 Loading videos for channel: \(channel.channelId)")
//            
//            // Load videos
//            videos = try await firebase.getVideos(forChannel: channel.channelId)
//            print("📹 Loaded \(videos.count) videos")
//            
//            // Load alignment docs
//            let alignments = try await analysisFirebase.loadAllAlignmentDocs(channelId: channel.channelId)
//            print("📊 Loaded \(alignments.count) alignments")
//            analyzedVideos = Dictionary(uniqueKeysWithValues: alignments.map { ($0.videoId, $0) })
//            
//            // Load aggregation if it exists
//            aggregation = try await analysisFirebase.loadAggregation(channelId: channel.channelId)
//            
//        } catch {
//            print("❌ Failed to load data: \(error)")
//        }
//        
//        isLoading = false
//    }
//}
//
//// MARK: - Video Analysis Row
//struct VideoAnalysisRow: View {
//    let video: YouTubeVideo
//    let hasAnalysis: Bool
//    
//    var body: some View {
//        HStack(spacing: 12) {
//            AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
//                image
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//            } placeholder: {
//                Rectangle()
//                    .fill(Color.gray.opacity(0.3))
//            }
//            .frame(width: 120, height: 68)
//            .cornerRadius(8)
//            
//            VStack(alignment: .leading, spacing: 4) {
//                Text(video.title)
//                    .font(.subheadline)
//                    .lineLimit(2)
//                
//                HStack {
//                    Label(formatDuration(video.duration), systemImage: "clock")
//                    Spacer()
//                    if hasAnalysis {
//                        Image(systemName: "checkmark.circle.fill")
//                            .foregroundColor(.green)
//                    } else {
//                        Image(systemName: "plus.circle")
//                            .foregroundColor(.blue)
//                    }
//                }
//                .font(.caption)
//                .foregroundColor(.secondary)
//            }
//        }
//        .padding(.vertical, 4)
//    }
//    
//    private func formatDuration(_ seconds: String) -> String {
//        guard let totalSeconds = Int(seconds) else { return seconds }
//        let minutes = totalSeconds / 60
//        let secs = totalSeconds % 60
//        return String(format: "%d:%02d", minutes, secs)
//    }
//}
//
//// MARK: - Circular Progress View
//struct CircularProgressView: View {
//    let progress: Double
//    let lineWidth: CGFloat
//    
//    private var safeProgress: Double {
//        guard progress.isFinite else { return 0 }
//        return min(max(progress, 0), 1)
//    }
//    
//    var body: some View {
//        ZStack {
//            Circle()
//                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
//            
//            Circle()
//                .trim(from: 0, to: safeProgress)
//                .stroke(Color.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
//                .rotationEffect(.degrees(-90))
//                .animation(.easeInOut, value: safeProgress)
//            
//            Text("\(Int(safeProgress * 100))%")
//                .font(.caption)
//                .fontWeight(.bold)
//        }
//    }
//}

//// MARK: - Creator Detail View
//struct CreatorDetailView: View {
//    let channel: YouTubeChannel
//    @EnvironmentObject var nav: NavigationViewModel
//    
//    @State private var videos: [YouTubeVideo] = []
//    @State private var analyzedVideos: [String: AlignmentData] = [:]
//    @State private var aggregation: AggregationData?
//    @State private var isLoading = true
//    @State private var selectedVideo: YouTubeVideo?
//    @State private var showManualIngestion = false
//    
//    // A3 State
//    @State private var styleProfiles: [StyleProfile] = []
//    @State private var isRunningA3 = false
//    @State private var a3Progress = ""
//    @State private var a3Error: String?
//    
//    var analyzedCount: Int {
//        analyzedVideos.count
//    }
//    
//    var videosWithSummaryCount: Int {
//        videos.filter { $0.scriptSummary != nil }.count
//    }
//    
//    var canRunA3: Bool {
//        videosWithSummaryCount >= 5
//    }
//    
//    var body: some View {
//        List {
//            // Channel Overview
//            Section {
//                HStack(spacing: 12) {
//                    AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
//                        image
//                            .resizable()
//                            .aspectRatio(contentMode: .fill)
//                    } placeholder: {
//                        Circle()
//                            .fill(Color.gray.opacity(0.3))
//                    }
//                    .frame(width: 80, height: 80)
//                    .clipShape(Circle())
//                    
//                    VStack(alignment: .leading, spacing: 8) {
//                        Text(channel.name)
//                            .font(.title3)
//                            .fontWeight(.bold)
//                        
//                        if let subscribers = channel.metadata?.subscriberCount {
//                            Label("\(subscribers.formatted()) subscribers", systemImage: "person.2")
//                                .font(.caption)
//                        }
//                        
//                        Label("\(channel.videoCount) videos", systemImage: "play.rectangle")
//                            .font(.caption)
//                    }
//                }
//                .padding(.vertical, 8)
//            }
//            
//            // Analysis Progress
//            Section("Analysis Progress") {
//                HStack {
//                    VStack(alignment: .leading) {
//                        Text("\(analyzedCount) / \(videos.count)")
//                            .font(.title2)
//                            .fontWeight(.bold)
//                        Text("Videos Analyzed")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                    
//                    Spacer()
//                    
//                    if analyzedCount > 0 && videos.count > 0 {
//                        CircularProgressView(
//                            progress: Double(analyzedCount) / Double(videos.count),
//                            lineWidth: 8
//                        )
//                        .frame(width: 60, height: 60)
//                    }
//                }
//                .padding(.vertical, 8)
//                
//                // Show summary count if different from analyzed count
//                if videosWithSummaryCount != analyzedCount {
//                    HStack {
//                        Image(systemName: "doc.text")
//                            .foregroundColor(.orange)
//                        Text("\(videosWithSummaryCount) videos have scriptSummary")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                    }
//                }
//            }
//            
//            // Style Profiles Section (A3)
//            Section("Style Profiles") {
//                if isRunningA3 {
//                    VStack(spacing: 12) {
//                        ProgressView()
//                        Text(a3Progress)
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                            .multilineTextAlignment(.center)
//                    }
//                    .frame(maxWidth: .infinity)
//                    .padding(.vertical, 12)
//                    
//                } else if styleProfiles.isEmpty {
//                    VStack(alignment: .leading, spacing: 12) {
//                        Button {
//                            Task { await runA3Analysis() }
//                        } label: {
//                            Label("Analyze Writing Styles", systemImage: "sparkles")
//                                .frame(maxWidth: .infinity)
//                        }
//                        .buttonStyle(.borderedProminent)
//                        .disabled(!canRunA3)
//                        
//                        if !canRunA3 {
//                            HStack {
//                                Image(systemName: "info.circle")
//                                    .foregroundColor(.orange)
//                                Text("Need at least 5 videos with scriptSummary. Current: \(videosWithSummaryCount)")
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                        }
//                    }
//                    
//                } else {
//                    ForEach(styleProfiles) { profile in
//                        StyleProfileCard(profile: profile)
//                    }
//                    
//                    Button {
//                        Task { await runA3Analysis() }
//                    } label: {
//                        Label("Re-analyze Styles", systemImage: "arrow.clockwise")
//                    }
//                    .buttonStyle(.bordered)
//                }
//                
//                if let error = a3Error {
//                    HStack {
//                        Image(systemName: "exclamationmark.triangle")
//                            .foregroundColor(.red)
//                        Text(error)
//                            .font(.caption)
//                            .foregroundColor(.red)
//                    }
//                }
//            }
//            
//            // Videos
//            Section("Videos (\(videos.count))") {
//                ForEach(videos) { video in
//                    Button {
//                        nav.push(.manualIngestion(video))
//                    } label: {
//                        VideoAnalysisRow(
//                            video: video,
//                            hasAnalysis: analyzedVideos[video.videoId] != nil,
//                            hasSummary: video.scriptSummary != nil
//                        )
//                    }
//                    .buttonStyle(.plain)
//                }
//            }
//        }
//        .navigationTitle("Creator Analysis")
//        .navigationBarTitleDisplayMode(.inline)
//        .task {
//            await loadData()
//        }
//        .refreshable {
//            await loadData()
//        }
//        .sheet(isPresented: $showManualIngestion) {
//            if let video = selectedVideo {
//                ManualIngestionView(video: video)
//            }
//        }
//    }
//    
//    // MARK: - Load Data
//    
//    private func loadData() async {
//        isLoading = true
//        
//        do {
//            let firebase = YouTubeFirebaseService.shared
//            let analysisFirebase = CreatorAnalysisFirebase.shared
//            
//            print("🔍 Loading videos for channel: \(channel.channelId)")
//            
//            // Load videos
//            videos = try await firebase.getVideos(forChannel: channel.channelId)
//            print("📹 Loaded \(videos.count) videos")
//            print("📊 Videos with scriptSummary: \(videosWithSummaryCount)")
//            
//            // Load alignment docs
//            let alignments = try await analysisFirebase.loadAllAlignmentDocs(channelId: channel.channelId)
//            print("📊 Loaded \(alignments.count) alignments")
//            analyzedVideos = Dictionary(uniqueKeysWithValues: alignments.map { ($0.videoId, $0) })
//            
//            // Load aggregation if it exists
//            aggregation = try await analysisFirebase.loadAggregation(channelId: channel.channelId)
//            
//            // Load style profiles
//            await loadStyleProfiles()
//            
//        } catch {
//            print("❌ Failed to load data: \(error)")
//        }
//        
//        isLoading = false
//    }
//    
//    // MARK: - A3 Methods
//    
//    private func loadStyleProfiles() async {
//        guard let styleIds = channel.styleIds, !styleIds.isEmpty else {  // ← Changed
//            print("📊 No style profiles found for channel")
//            return
//        }
//        
//        do {
//            let profiles = try await A3ClusteringService.shared.loadStyleProfiles(profileIds: styleIds)  // ← parameter name stays same in function
//            await MainActor.run {
//                styleProfiles = profiles
//            }
//            print("✅ Loaded \(profiles.count) style profiles")
//        } catch {
//            print("❌ Failed to load style profiles: \(error)")
//        }
//    }
//    
//    private func runA3Analysis() async {
//        await MainActor.run {
//            isRunningA3 = true
//            a3Error = nil
//            a3Progress = "Starting analysis..."
//        }
//        
//        do {
//            let result = try await A3ClusteringService.shared.runStyleAnalysis(
//                channelId: channel.channelId
//            ) { progress in
//                Task { @MainActor in
//                    a3Progress = progress
//                }
//            }
//            
//            await MainActor.run {
//                styleProfiles = result.profiles
//                isRunningA3 = false
//                a3Progress = ""
//            }
//            
//            print("✅ A3 complete: \(result.profiles.count) profiles from \(result.videosAnalyzed) videos")
//            
//        } catch {
//            await MainActor.run {
//                a3Error = error.localizedDescription
//                isRunningA3 = false
//                a3Progress = ""
//            }
//            print("❌ A3 failed: \(error)")
//        }
//    }
//}


import SwiftUI

struct CreatorDetailView: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel
    @ObservedObject private var viewModel = CreatorDetailViewModel.shared

    // Rhetorical Fidelity Test state
    @State private var showRhetoricalFidelitySheet = false
    @State private var selectedVideoForFidelity: YouTubeVideo? = nil
    @State private var showIconLegend = false

    // Sentence count state
    @State private var totalSentenceCount: Int?
    @State private var totalWordCount: Int?
    @State private var sentenceCountByVideo: [(videoId: String, title: String, sentences: Int, words: Int)]?
    @State private var isRefetching = false
    @State private var refetchProgress: (completed: Int, total: Int) = (0, 0)
    @State private var isTestingOne = false
    @State private var testResult: String?

    /// Shows the most recent delete result, or the active operation
    private var deleteStatusText: String {
        if let op = viewModel.activeDeleteOp {
            switch op {
            case "sentenceFidelity": return "Deleting sentences..."
            case "digressions": return "Deleting digressions..."
            case "batchDigressions": return "Deleting batch..."
            case "rhetorical": return "Clearing rhetorical..."
            default: return "Deleting..."
            }
        }
        let results = viewModel.deleteResults
        if results.isEmpty { return "Pick one" }
        return results.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Channel Header
                channelHeaderSection

                // Analysis Summary
                analysisSummarySection

                // LLM Pipeline (pure LLM-based digestion)
                LLMPipelineSection(channel: channel)

                // Donor Library Pipeline (sentence-level slot annotation → bigrams → templates)
                DonorLibraryPipelineSection(channel: channel)

                // Narrative Spine Pipeline (structural pattern extraction)
                NarrativeSpinePipelineSection(channel: channel)

                // Spine-Rhetorical Alignment Pipeline
                SpineAlignmentPipelineSection(channel: channel)

                // Sequence Bookends (opening/closing pattern explorer)
                if viewModel.videosWithRhetoricalSequence > 0 {
                    sequenceBookendsSection
                }

                // Sentence-Tag Pipeline (deterministic, legacy)
                DigestionPipelineSection(channel: channel)

                // Batch Actions
                batchActionsSection

                // Style Taxonomy / Pre-A0
                taxonomySection

                // Template Extractor
                templateExtractorSection

                // Chunk Browser
                chunkBrowserSection

                // Creator Profile (for Shape Script Writer)
                creatorProfileSection

                // Rhetorical Fidelity Test
                rhetoricalFidelitySection

                // Video List
                videoListSection
            }
            .padding()
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingVideos)
            }
        }
        .overlay {
            if viewModel.batchService.isRunning {
                batchProgressOverlay
            }
            if viewModel.showA3Progress {
                a3ProgressOverlay
            }
            if viewModel.sentenceBatchService.isRunning {
                sentenceBatchProgressOverlay
            }
            if viewModel.isRunningEfficientTest {
                efficientTestProgressOverlay
            }
        }
        .alert("A3 Error", isPresented: .constant(viewModel.a3Error != nil)) {
            Button("OK") { viewModel.a3Error = nil }
        } message: {
            if let error = viewModel.a3Error {
                Text(error)
            }
        }
        .task(id: channel.channelId) {
            await viewModel.setChannel(channel)
        }
        .sheet(isPresented: $showRhetoricalFidelitySheet) {
            if let video = selectedVideoForFidelity {
                RhetoricalFidelityTestSheet(video: video, channel: channel)
            }
        }
    }
    
    // MARK: - Channel Header
    
    private var channelHeaderSection: some View {
        HStack(spacing: 16) {
            if let url = URL(string: channel.thumbnailUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.title2.bold())
                
                // Use metadata?.subscriberCount if available
                if let subs = channel.metadata?.subscriberCount {
                    Text("\(subs.formatted()) subscribers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("\(viewModel.videos.count) videos loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Analysis Summary
    
    private var analysisSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis Status")
                .font(.headline)

            HStack(spacing: 16) {
                StatusCard(
                    title: "Not Analyzed",
                    count: viewModel.batchService.unanalyzedCount,
                    color: .secondary
                )

                StatusCard(
                    title: "Ready for A3",
                    count: viewModel.batchService.readyForA3Count,
                    color: .green
                )

                StatusCard(
                    title: "Total",
                    count: viewModel.batchService.videoStatuses.count,
                    color: .blue
                )
            }

            // Sentence count button + result
            HStack(spacing: 12) {
                Button {
                    countSentences()
                } label: {
                    Label("Get Sentence Count", systemImage: "text.line.first.and.arrowtriangle.forward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                if let breakdown = sentenceCountByVideo, breakdown.contains(where: { $0.sentences <= 1 }) {
                    Button {
                        Task { await testFixOneTranscript() }
                    } label: {
                        if isTestingOne {
                            Label("Testing...", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption)
                        } else {
                            Label("Test 1", systemImage: "ant")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(isTestingOne)

                    Button {
                        Task { await fixLowSentenceTranscripts() }
                    } label: {
                        if isRefetching {
                            Label("\(refetchProgress.completed)/\(refetchProgress.total)", systemImage: "text.badge.checkmark")
                                .font(.caption)
                        } else {
                            let count = breakdown.filter { $0.sentences <= 1 }.count
                            Label("Fix \(count) bad", systemImage: "text.badge.checkmark")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isRefetching)
                }

                if let total = totalSentenceCount, let words = totalWordCount {
                    Text("\(total) sentences, \(words) words across \(sentenceCountByVideo?.count ?? 0) videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Test result display
            if let result = testResult {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Test Fetch Result")
                            .font(.caption)
                            .fontWeight(.bold)
                        Spacer()
                        Button("Dismiss") { testResult = nil }
                            .font(.caption2)
                    }
                    Text(result)
                        .font(.caption2)
                        .monospaced()
                        .lineLimit(20)
                        .textSelection(.enabled)
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }

            if let breakdown = sentenceCountByVideo, !breakdown.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(breakdown, id: \.title) { entry in
                        HStack {
                            Text(entry.title)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.sentences)s / \(entry.words)w")
                                .font(.caption2)
                                .monospaced()
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
        }
    }
    
    private func countSentences() {
        var results: [(videoId: String, title: String, sentences: Int, words: Int)] = []
        var totalSentences = 0
        var totalWords = 0

        for status in viewModel.batchService.videoStatuses {
            guard let transcript = status.video.transcript, !transcript.isEmpty else { continue }
            let sentences = SentenceParser.parse(transcript)
            let wordCount = transcript.split(whereSeparator: \.isWhitespace).count
            results.append((videoId: status.video.videoId, title: status.video.title, sentences: sentences.count, words: wordCount))
            totalSentences += sentences.count
            totalWords += wordCount
        }

        results.sort(by: { $0.sentences > $1.sentences })
        sentenceCountByVideo = results
        totalSentenceCount = totalSentences
        totalWordCount = totalWords
    }

    private func fixLowSentenceTranscripts() async {
        guard let breakdown = sentenceCountByVideo else { return }

        // Collect videos that need fixing with their transcripts
        let badVideos: [(videoId: String, transcript: String)] = breakdown
            .filter { $0.sentences <= 1 }
            .compactMap { entry in
                guard let idx = viewModel.batchService.videoStatuses.firstIndex(where: { $0.video.videoId == entry.videoId }),
                      let transcript = viewModel.batchService.videoStatuses[idx].video.transcript,
                      !transcript.isEmpty else { return nil }
                return (videoId: entry.videoId, transcript: transcript)
            }

        guard !badVideos.isEmpty else { return }

        isRefetching = true
        refetchProgress = (0, badVideos.count)

        let firebaseService = YouTubeFirebaseService()
        let systemPrompt = "You add punctuation to unpunctuated transcripts. Return ONLY the transcript with proper punctuation (periods, commas, question marks, exclamation marks) added. Do not change, add, or remove any words. Do not add formatting or commentary."

        // Process 10 at a time in parallel
        await withTaskGroup(of: (String, String?).self) { group in
            var inFlight = 0

            for video in badVideos {
                // Limit to 10 concurrent
                if inFlight >= 10 {
                    if let (videoId, punctuated) = await group.next() {
                        await handleFixResult(videoId: videoId, punctuated: punctuated, firebaseService: firebaseService)
                        inFlight -= 1
                    }
                }

                group.addTask {
                    let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
                    let result = await adapter.generate_response(
                        prompt: video.transcript,
                        promptBackgroundInfo: systemPrompt,
                        params: ["temperature": 0.1, "max_tokens": 16000]
                    )
                    return (video.videoId, result.isEmpty ? nil : result)
                }
                inFlight += 1
            }

            // Collect remaining results
            for await (videoId, punctuated) in group {
                await handleFixResult(videoId: videoId, punctuated: punctuated, firebaseService: firebaseService)
            }
        }

        // Refresh counts with punctuated transcripts
        countSentences()
        isRefetching = false
    }

    private func handleFixResult(videoId: String, punctuated: String?, firebaseService: YouTubeFirebaseService) async {
        guard let punctuated = punctuated else {
            refetchProgress.completed += 1
            print("❌ Empty response for \(videoId)")
            return
        }

        do {
            try await firebaseService.updateVideoTranscript(videoId: videoId, transcript: punctuated)

            // Update the local video
            if let idx = viewModel.batchService.videoStatuses.firstIndex(where: { $0.video.videoId == videoId }) {
                let old = viewModel.batchService.videoStatuses[idx]
                var updatedVideo = old.video
                updatedVideo.transcript = punctuated
                viewModel.batchService.videoStatuses[idx] = VideoAnalysisStatus(
                    id: old.id, video: updatedVideo, state: old.state,
                    sectionCount: old.sectionCount, beatCount: old.beatCount,
                    hasScriptSummary: old.hasScriptSummary
                )
            }

            let newSentenceCount = SentenceParser.parse(punctuated).count
            refetchProgress.completed += 1
            print("✅ Fixed \(videoId): \(newSentenceCount) sentences (\(refetchProgress.completed)/\(refetchProgress.total))")
        } catch {
            refetchProgress.completed += 1
            print("❌ Failed to save \(videoId): \(error)")
        }
    }

    private func testFixOneTranscript() async {
        guard let breakdown = sentenceCountByVideo,
              let firstBad = breakdown.first(where: { $0.sentences <= 1 }) else { return }

        isTestingOne = true
        testResult = nil

        // Get existing transcript
        guard let idx = viewModel.batchService.videoStatuses.firstIndex(where: { $0.video.videoId == firstBad.videoId }),
              let transcript = viewModel.batchService.videoStatuses[idx].video.transcript,
              !transcript.isEmpty else {
            testResult = "VIDEO: \(firstBad.title)\nSTATUS: No transcript found"
            isTestingOne = false
            return
        }

        let beforeSentences = SentenceParser.parse(transcript).count

        // Send to Claude for punctuation
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let systemPrompt = "You add punctuation to unpunctuated transcripts. Return ONLY the transcript with proper punctuation (periods, commas, question marks, exclamation marks) added. Do not change, add, or remove any words. Do not add formatting or commentary."

        let punctuated = await adapter.generate_response(
            prompt: transcript,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.1, "max_tokens": 16000]
        )

        let afterSentences = SentenceParser.parse(punctuated).count
        let preview = String(punctuated.prefix(500))

        testResult = """
        VIDEO: \(firstBad.title)
        ID: \(firstBad.videoId)
        BEFORE: \(beforeSentences) sentences
        AFTER: \(afterSentences) sentences
        NOT SAVED — test only

        FIRST 500 CHARS (punctuated):
        \(preview)
        """

        isTestingOne = false
    }

    // MARK: - Sequence Bookends

    private var sequenceBookendsSection: some View {
        Button {
            nav.push(.sequenceBookends(channel))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.and.right.text.vertical")
                    .font(.subheadline)
                    .foregroundColor(.teal)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sequence Bookends")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("Opening & closing patterns across \(viewModel.videosWithRhetoricalSequence) scripts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Batch Actions

    private var batchActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Actions")
                .font(.headline)

            HStack(spacing: 12) {
                // Process All Unanalyzed
                Button {
                    Task { await viewModel.batchService.processAllUnanalyzed() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.title2)
                        Text("Analyze All")
                            .font(.caption.bold())
                        Text("Fast Path")
                            .font(.caption)
                        Text("\(viewModel.batchService.unanalyzedCount) videos")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.batchService.unanalyzedCount == 0 || viewModel.batchService.isRunning)

                // Run A3 Clustering
                Button {
                    Task { await viewModel.runA3Analysis() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.title2)
                        Text("Run A3")
                            .font(.caption.bold())
                        Text("\(viewModel.batchService.readyForA3Count) ready")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.batchService.readyForA3Count >= 5 ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.batchService.readyForA3Count >= 5 ? Color.purple : Color.gray, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.batchService.readyForA3Count < 5 || viewModel.batchService.isRunning)
                Button {
                    Task { await viewModel.fetchAllMissingTranscripts() }
                } label: {
                    VStack(spacing: 6) {
                        if viewModel.isFetchingTranscripts {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "text.alignleft")
                                .font(.title2)
                        }
                        Text(viewModel.isFetchingTranscripts ? "Fetching..." : "Get Transcripts")
                            .font(.caption.bold())
                        Text(viewModel.isFetchingTranscripts ? viewModel.transcriptFetchProgress : "\(viewModel.missingTranscriptCount) missing")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.missingTranscriptCount > 0 ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.missingTranscriptCount > 0 ? Color.red : Color.gray, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.missingTranscriptCount == 0 || viewModel.batchService.isRunning || viewModel.isFetchingTranscripts)
                // Refresh Status
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                        Text("Refresh")
                            .font(.caption.bold())
                        Text("Status")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.batchService.isRunning)
            }

            // Sentence Analysis Row
            HStack(spacing: 12) {
                // Batch Sentence Analysis button
                Button {
                    Task { await viewModel.runBatchSentenceAnalysis() }
                } label: {
                    VStack(spacing: 6) {
                        if viewModel.sentenceBatchService.isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                .font(.title2)
                        }
                        Text(viewModel.sentenceBatchService.isRunning ? "Analyzing..." : "Sentence Tags")
                            .font(.caption.bold())
                        Text("\(viewModel.videosWithTranscripts - viewModel.videosWithSentenceAnalysis) to analyze")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosWithTranscripts == 0 || viewModel.sentenceBatchService.isRunning || viewModel.isRunningEfficientTest)

                // Efficient (Cached) Sentence Analysis button - processes up to 10 videos
                Button {
                    Task { await viewModel.runEfficientSentenceTest() }
                } label: {
                    VStack(spacing: 6) {
                        if viewModel.isRunningEfficientTest {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "bolt.badge.clock")
                                .font(.title2)
                        }
                        Text(viewModel.isRunningEfficientTest ? "Running..." : "Efficient")
                            .font(.caption.bold())
                        Text("\(min(10, viewModel.videosWithTranscripts - viewModel.videosWithSentenceAnalysis)) videos")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.yellow, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosWithTranscripts - viewModel.videosWithSentenceAnalysis == 0 || viewModel.sentenceBatchService.isRunning || viewModel.isRunningEfficientTest)

                // Copy All Sentence Data button
                Button {
                    viewModel.copyAllSentenceData()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                        Text("Copy All")
                            .font(.caption.bold())
                        Text("\(viewModel.videosWithSentenceAnalysis) analyzed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.videosWithSentenceAnalysis > 0 ? Color.indigo.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.videosWithSentenceAnalysis > 0 ? Color.indigo : Color.gray, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosWithSentenceAnalysis == 0)

                // Granular Delete Buttons
                Menu {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteSentenceFidelity() }
                    } label: {
                        Label("Delete Sentence Fidelity", systemImage: "testtube.2")
                    }

                    Button(role: .destructive) {
                        Task { await viewModel.deleteDigressionResults() }
                    } label: {
                        Label("Delete Digressions", systemImage: "arrow.trianglehead.branch")
                    }

                    Button(role: .destructive) {
                        Task { await viewModel.deleteBatchDigressions(channelId: channel.id) }
                    } label: {
                        Label("Delete Batch Digressions (this channel)", systemImage: "rectangle.stack.badge.minus")
                    }

                    Button(role: .destructive) {
                        Task { await viewModel.deleteAllBatchDigressions() }
                    } label: {
                        Label("Delete ALL Batch Digressions", systemImage: "rectangle.stack.badge.minus")
                    }

                    Button(role: .destructive) {
                        Task { await viewModel.deleteRhetoricalSequences() }
                    } label: {
                        Label("Delete Rhetorical Sequences", systemImage: "waveform.path.ecg")
                    }

                    Divider()

                    Button(role: .destructive) {
                        Task { await viewModel.wipeAllSentenceData() }
                    } label: {
                        Label("Wipe All (except batch digressions)", systemImage: "trash")
                    }
                } label: {
                    VStack(spacing: 6) {
                        if viewModel.activeDeleteOp != nil {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash.circle")
                                .font(.title2)
                        }
                        Text(viewModel.activeDeleteOp != nil ? "Deleting..." : "Delete")
                            .font(.caption.bold())
                        Text(deleteStatusText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red, lineWidth: 1)
                    )
                }
                .disabled(viewModel.activeDeleteOp != nil)

                // Sentence Analysis Status
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.title2)
                        .foregroundColor(viewModel.videosWithSentenceAnalysis > 0 ? .green : .gray)
                    Text("Sentences")
                        .font(.caption.bold())
                    Text("\(viewModel.videosWithSentenceAnalysis)/\(viewModel.videosWithTranscripts)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }

            if viewModel.batchService.readyForA3Count < 5 {
                Text("Need at least 5 videos with scriptSummary to run A3 clustering")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Rhetorical Style Analysis Row
            HStack(spacing: 12) {
                // Queue videos needing enhanced analysis button
                Button {
                    viewModel.queueAllVideosNeedingEnhancedRhetorical()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(viewModel.videosNeedingEnhancedRhetorical > 0 ? .orange : .gray)
                        Text("Queue Needed")
                            .font(.caption.bold())
                        Text("\(viewModel.videosNeedingEnhancedRhetorical) need update")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.videosNeedingEnhancedRhetorical > 0 ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.videosNeedingEnhancedRhetorical > 0 ? Color.orange : Color.gray, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosNeedingEnhancedRhetorical == 0 || viewModel.isRunningRhetoricalAnalysis)

                // Batch Extract button (all ready)
                Button {
                    Task { await viewModel.runBatchRhetoricalAnalysis() }
                } label: {
                    VStack(spacing: 6) {
                        if viewModel.isRunningRhetoricalAnalysis {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                                .font(.title2)
                        }
                        Text(viewModel.isRunningRhetoricalAnalysis ? "Extracting..." : "Extract All")
                            .font(.caption.bold())
                        Text("\(viewModel.videosReadyForRhetoricalAnalysis) ready")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.videosReadyForRhetoricalAnalysis > 0 ? Color.pink.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.videosReadyForRhetoricalAnalysis > 0 ? Color.pink : Color.gray, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosReadyForRhetoricalAnalysis == 0 || viewModel.isRunningRhetoricalAnalysis)

                // View Analysis button
                Button {
                    nav.push(.creatorRhetoricalStyle(channel))
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title2)
                        Text("View Style")
                            .font(.caption.bold())
                        Text("\(viewModel.videosWithRhetoricalSequence) analyzed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.videosWithRhetoricalSequence > 0 ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.videosWithRhetoricalSequence > 0 ? Color.purple : Color.gray, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Status indicator
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.title2)
                        .foregroundColor(viewModel.videosWithRhetoricalSequence > 0 ? .green : .gray)
                    Text("Rhetorical")
                        .font(.caption.bold())
                    Text("\(viewModel.videosWithRhetoricalSequence)/\(viewModel.videosWithSentenceAnalysis)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }

            // Progress indicator for rhetorical analysis
            if viewModel.isRunningRhetoricalAnalysis {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Rhetorical Analysis Running")
                            .font(.caption.bold())
                            .foregroundColor(.pink)
                    }

                    // Show overall progress
                    if !viewModel.rhetoricalAnalysisProgress.isEmpty {
                        Text(viewModel.rhetoricalAnalysisProgress)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Show per-video progress
                    if !viewModel.rhetoricalQueueProgress.isEmpty {
                        ForEach(Array(viewModel.rhetoricalQueueProgress.keys), id: \.self) { videoId in
                            if let progress = viewModel.rhetoricalQueueProgress[videoId],
                               let video = viewModel.videos.first(where: { $0.videoId == videoId }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.caption2)
                                    Text(video.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                    Text("- \(progress)")
                                        .font(.caption2)
                                        .foregroundColor(.pink)
                                }
                            }
                        }
                    }

                    // Show queue count
                    if !viewModel.videosQueuedForRhetorical.isEmpty {
                        Text("\(viewModel.videosQueuedForRhetorical.count) more in queue")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.pink.opacity(0.1))
                .cornerRadius(8)
            }

            // Digression Analysis Row
            HStack(spacing: 12) {
                Button {
                    nav.push(.batchDigressionDashboard(channel))
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.title2)
                        Text("Digression")
                            .font(.caption.bold())
                        Text("Batch Analysis")
                            .font(.caption)
                        Text("\(viewModel.videosWithSentenceAnalysis) with data")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.videosWithSentenceAnalysis > 0 ? Color.indigo.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.videosWithSentenceAnalysis > 0 ? Color.indigo : Color.gray, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosWithSentenceAnalysis == 0)

                Button {
                    nav.push(.digressionChunkComparison(channel))
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.title2)
                        Text("Chunk")
                            .font(.caption.bold())
                        Text("Comparison")
                            .font(.caption)
                        Text("Before vs After")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.videosWithSentenceAnalysis > 0 ? Color.teal.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.videosWithSentenceAnalysis > 0 ? Color.teal : Color.gray, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosWithSentenceAnalysis == 0)
            }

            // Creator Fingerprint + Section Questions Row
            HStack(spacing: 12) {
                Button {
                    nav.push(.creatorFingerprint(channel))
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "person.text.rectangle")
                            .font(.title2)
                        Text("Fingerprint")
                            .font(.caption.bold())
                        Text("Style DNA")
                            .font(.caption)
                        Text("\(viewModel.videosWithRhetoricalSequence) analyzed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.videosWithRhetoricalSequence > 0 ? Color.cyan.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.videosWithRhetoricalSequence > 0 ? Color.cyan : Color.gray, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosWithRhetoricalSequence == 0)

                Button {
                    nav.push(.sectionQuestions(channel))
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "questionmark.text.page")
                            .font(.title2)
                        Text("Questions")
                            .font(.caption.bold())
                        Text("Section Q&A")
                            .font(.caption)
                        Text("\(viewModel.videosWithRhetoricalSequence) analyzed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.videosWithRhetoricalSequence > 0 ? Color.indigo.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.videosWithRhetoricalSequence > 0 ? Color.indigo : Color.gray, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.videosWithRhetoricalSequence == 0)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    // MARK: - Style Taxonomy Section

    private var taxonomySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style Taxonomy")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Status message
                HStack {
                    Image(systemName: "rectangle.3.group")
                        .font(.title2)
                        .foregroundColor(.purple)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No taxonomy built yet")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Browse all \(channel.videoCount) videos and select representative samples for style analysis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Browse button
                Button {
                    nav.push(.preA0Browse(channel))
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Browse All Videos")
                        Spacer()
                        Text("\(channel.videoCount) on YouTube")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Run Phase 0 button
                Button {
                    nav.push(.taxonomyBatchRunner(channel))
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Run Phase 0 Analysis")
                        Spacer()
                        Text("Structural DNA")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Build A1a Prompts button
                Button {
                    nav.push(.a1aPromptBuilder(channel))
                } label: {
                    HStack {
                        Image(systemName: "hammer.fill")
                        Text("Build A1a Prompts")
                        Spacer()
                        Text("Per-template extraction")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Info about what this does
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Smart video selection: Cluster videos by content theme, then pick representative samples from each cluster for taxonomy building.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Template Extractor Section

    private var templateExtractorSection: some View {
        TemplateExtractorSection(
            channel: channel,
            videos: viewModel.videos,
            sentenceData: viewModel.videoSentenceData
        )
    }

    // MARK: - Chunk Browser Section

    private var chunkBrowserSection: some View {
        let videosWithRhetorical = viewModel.videos.filter { $0.hasRhetoricalSequence }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Chunk Browser")
                .font(.headline)

            Text("Browse and search all rhetorical chunks across videos")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("\(videosWithRhetorical.count) videos with rhetorical data")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                let totalChunks = videosWithRhetorical.compactMap { $0.rhetoricalSequence?.moves.count }.reduce(0, +)
                Text("\(totalChunks) total chunks")
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            Button {
                nav.push(.creatorChunkBrowser(channel, viewModel.videos))
            } label: {
                Label("Browse Chunks", systemImage: "square.grid.3x3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(videosWithRhetorical.isEmpty)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Creator Profile Section

    private var creatorProfileSection: some View {
        CreatorProfileSection(
            channel: channel,
            videos: viewModel.videos,
            sentenceData: viewModel.videoSentenceData
        )
    }

    // MARK: - Rhetorical Fidelity Test Section

    private var rhetoricalFidelitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rhetorical Fidelity Test")
                .font(.headline)

            Text("Test extraction stability by running multiple times on the same video")
                .font(.caption)
                .foregroundColor(.secondary)

            // Video picker - only videos with sentence fidelity data
            let videosWithSentenceData = viewModel.videos.filter { viewModel.videoSentenceData[$0.videoId] != nil }

            if videosWithSentenceData.isEmpty {
                Text("No videos with sentence analysis. Run sentence fidelity test on videos first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Picker("Select Video", selection: $selectedVideoForFidelity) {
                    Text("Choose a video...").tag(nil as YouTubeVideo?)
                    ForEach(videosWithSentenceData) { video in
                        Text(video.title).tag(video as YouTubeVideo?)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    if selectedVideoForFidelity != nil {
                        showRhetoricalFidelitySheet = true
                    }
                } label: {
                    Label("Run Fidelity Test", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedVideoForFidelity == nil)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Video List

    private func iconLegendRow(_ systemName: String, color: Color, name: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.bold())
                Text(desc)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var videoListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Videos")
                    .font(.headline)
                Spacer()

                Menu {
                    Section("Title") {
                        Button("A → Z") { viewModel.sortVideos(by: .titleAZ) }
                        Button("Z → A") { viewModel.sortVideos(by: .titleZA) }
                    }
                    Section("Duration") {
                        Button("Longest First") { viewModel.sortVideos(by: .longestFirst) }
                        Button("Shortest First") { viewModel.sortVideos(by: .shortestFirst) }
                    }
                    Section("Rhetorical") {
                        Button("Has Rhetorical") { viewModel.sortVideos(by: .hasRhetorical) }
                        Button("No Rhetorical") { viewModel.sortVideos(by: .noRhetorical) }
                    }
                    Section("Other") {
                        Button("By Status") { viewModel.sortVideos(by: .status) }
                        Button("By Date") { viewModel.sortVideos(by: .date) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }

            // Icon Legend
            DisclosureGroup(isExpanded: $showIconLegend) {
                VStack(alignment: .leading, spacing: 16) {
                    // Action Buttons
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Action Buttons")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        iconLegendRow("bolt.fill", color: .orange, name: "Quick Analyze",
                            desc: "Runs the fast-path analysis pipeline on this video. Only appears for videos not yet analyzed.")
                        iconLegendRow("testtube.2", color: .purple, name: "Sentence Fidelity",
                            desc: "Runs multiple LLM tagging passes on the transcript to measure tag stability across runs. Requires a transcript.")
                        iconLegendRow("rectangle.split.3x1", color: .blue, name: "Boundary Detection",
                            desc: "Detects section boundaries using sentence telemetry data. Requires sentence analysis to be complete.")
                        iconLegendRow("scissors", color: .teal, name: "Section Splitter",
                            desc: "LLM-based section splitting fidelity test. Slides a window across the transcript and uses consensus to find rhetorical boundaries.")
                        iconLegendRow("text.redaction", color: .indigo, name: "Digression Detection",
                            desc: "Identifies sponsor reads, asides, tangents, and other digressions. Requires sentence analysis.")
                        iconLegendRow("waveform.path.ecg", color: .pink, name: "Rhetorical Sequence",
                            desc: "View the rhetorical move sequence for this video. Only appears when a sequence has been extracted.")
                        iconLegendRow("plus.circle.fill", color: .pink, name: "Queue Rhetorical",
                            desc: "Queue this video for rhetorical sequence extraction. Orange version means the existing sequence is outdated and needs re-analysis.")
                        iconLegendRow("target", color: .mint, name: "Ground Truth",
                            desc: "Run 4 independent boundary detection methods and build consensus. Requires sentence analysis + transcript.")
                        iconLegendRow("flask", color: .indigo, name: "Experiment Lab",
                            desc: "Run and compare different prompt configurations for section splitting. Stores full history with A/B/C comparison.")
                        iconLegendRow("chevron.right", color: .secondary, name: "Detail View",
                            desc: "Navigate to the full manual ingestion detail view for this video.")
                    }

                    Divider()

                    // Inline Indicators
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inline Indicators")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        iconLegendRow("text.alignleft", color: .green, name: "Transcript",
                            desc: "Tap to copy transcript to clipboard. Green means transcript exists. Red means missing — tap to fetch it.")
                        iconLegendRow("doc.on.doc", color: .cyan, name: "Sentence Tags",
                            desc: "Shows sentence count and run count from fidelity testing (e.g. 142s 3r). Tap copy icon to copy all tagged data.")
                        iconLegendRow("rectangle.split.3x1", color: .blue, name: "Copy Chunks",
                            desc: "Copy boundary-detected chunk data to clipboard. Blue background indicator.")
                        iconLegendRow("list.number", color: .orange, name: "Copy Raw Sentences",
                            desc: "Copy just the raw numbered sentences to clipboard. Uses saved Firebase data from when fidelity test was run.")
                        iconLegendRow("arrow.counterclockwise", color: .teal, name: "Live Parse",
                            desc: "Copy sentences using the CURRENT SentenceParser on the raw transcript. Unlike Raw Sentences (which copies saved data), this always reflects the latest parser logic.")
                        iconLegendRow("exclamationmark.triangle.fill", color: .orange, name: "Outdated Rhetorical",
                            desc: "Rhetorical sequence is outdated — chunk count has changed since it was last extracted.")
                    }

                    Divider()

                    // Status Badges
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status Badges")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        iconLegendRow("circle", color: .secondary, name: "Not Analyzed",
                            desc: "No analysis has been run on this video yet.")
                        iconLegendRow("arrow.trianglehead.2.clockwise.rotate.90", color: .orange, name: "In Progress",
                            desc: "Analysis is currently running on this video.")
                        iconLegendRow("checkmark.circle", color: .blue, name: "A1a Complete",
                            desc: "First-pass analysis is done.")
                        iconLegendRow("checkmark.circle.fill", color: .green, name: "Ready for A3",
                            desc: "Analysis complete and ready for clustering.")
                        iconLegendRow("star.fill", color: .purple, name: "Full Analysis",
                            desc: "All analysis stages complete.")
                        iconLegendRow("exclamationmark.circle", color: .red, name: "Failed",
                            desc: "Analysis failed with an error.")
                    }
                }
                .padding(.vertical, 8)
            } label: {
                Label("Icon Guide", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

            // Search bar
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search videos...", text: $viewModel.videoSearchText)
                        .autocorrectionDisabled()
                        .onSubmit { viewModel.executeSearch() }
                    if !viewModel.videoSearchText.isEmpty {
                        Button {
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)

                Button {
                    viewModel.executeSearch()
                } label: {
                    Text("Search")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            // Transcript toggle + result count
            HStack {
                Toggle("Search transcripts", isOn: $viewModel.searchTranscripts)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .tint(.blue)

                Spacer()

                if viewModel.isSearchActive {
                    Text("\(viewModel.filteredVideoStatuses.count) of \(viewModel.batchService.videoStatuses.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.isLoadingVideos {
                ProgressView("Loading videos...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.batchService.videoStatuses.isEmpty {
                Text("No videos found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.isSearchActive && viewModel.filteredVideoStatuses.isEmpty {
                Text("No videos match \"\(viewModel.videoSearchText)\"")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.displayedVideoStatuses) { status in
                        videoStatusRow(for: status)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func videoStatusRow(for status: VideoAnalysisStatus) -> some View {
        let video = status.video
        let videoId = video.videoId
        let sentenceRuns = viewModel.videoSentenceData[videoId]
        let hasSentenceRuns = sentenceRuns != nil
        let hasTranscript = video.hasTranscript
        let needsRhetorical = viewModel.videoNeedsRhetoricalAnalysis(video)
        let rhetoricalMismatch = viewModel.rhetoricalMismatchInfo(video)

        VideoStatusRow(
            status: status,
            onTap: {
                nav.push(.manualIngestion(video))
            },
            onQuickAnalyze: {
                Task { await viewModel.batchService.processVideos([video]) }
            },
            onFetchTranscript: {
                Task { await viewModel.fetchTranscript(for: video) }
            },
            onFidelityTest: {
                nav.push(.sentenceFidelityTest(video, channel))
            },
            sentenceRuns: sentenceRuns,
            onCopySentences: hasSentenceRuns ? {
                viewModel.copySentenceDataForVideo(video)
            } : nil,
            onBoundaryDetection: {
                if let latestRun = sentenceRuns?.first {
                    nav.push(.boundaryDetection(video, latestRun))
                }
            },
            onCopyChunks: hasSentenceRuns ? {
                viewModel.copyChunksDataForVideo(video)
            } : nil,
            onCopyRawSentences: hasSentenceRuns ? {
                viewModel.copyRawSentencesForVideo(video)
            } : nil,
            onCopyLiveParse: hasTranscript ? {
                viewModel.copyLiveParseSentencesForVideo(video)
            } : nil,
            onGroundTruth: (hasSentenceRuns && hasTranscript) ? {
                nav.push(.groundTruth(video))
            } : nil,
            onExperimentLab: hasTranscript ? {
                nav.push(.promptExperimentLab(video))
            } : nil,
            onSectionSplitter: hasTranscript ? {
                nav.push(.sectionSplitterFidelity(video))
            } : nil,
            onDigressionDetection: hasSentenceRuns ? {
                nav.push(.digressionDetection(video))
            } : nil,
            onRhetoricalSequence: video.hasRhetoricalSequence ? {
                nav.push(.videoRhetoricalSequence(video))
            } : nil,
            onQueueRhetorical: needsRhetorical ? {
                viewModel.queueVideoForRhetorical(video)
            } : nil,
            isQueuedForRhetorical: viewModel.isVideoInRhetoricalQueue(videoId),
            rhetoricalQueueProgress: viewModel.rhetoricalQueueProgress[videoId],
            needsRhetoricalAnalysis: needsRhetorical,
            rhetoricalMismatchInfo: rhetoricalMismatch
        )
    }
    
    
    // MARK: - Overlays
    private var batchProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)

                Text("Batch Analysis Running")
                    .font(.headline)

                // Show current video's phase
                if let inProgressVideo = viewModel.batchService.videoStatuses.first(where: {
                    if case .inProgress = $0.state { return true }
                    return false
                }) {
                    Text(inProgressVideo.video.title)
                        .font(.subheadline)
                        .lineLimit(1)

                    if case .inProgress(let phase, _) = inProgressVideo.state {
                        Text(phase)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Text(viewModel.batchService.overallProgress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // ... rest of overlay
            }
        }
    }
    private var batchProgressOverlayOLD: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)

                Text("Batch Analysis Running")
                    .font(.headline)

                Text(viewModel.batchService.overallProgress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 20) {
                    VStack {
                        Text("\(viewModel.batchService.completedCount)")
                            .font(.title2.bold())
                            .foregroundColor(.green)
                        Text("Done")
                            .font(.caption)
                    }

                    VStack {
                        Text("\(viewModel.batchService.failedCount)")
                            .font(.title2.bold())
                            .foregroundColor(.red)
                        Text("Failed")
                            .font(.caption)
                    }

                    VStack {
                        Text("\(viewModel.batchService.totalCount - viewModel.batchService.completedCount - viewModel.batchService.failedCount)")
                            .font(.title2.bold())
                            .foregroundColor(.blue)
                        Text("Remaining")
                            .font(.caption)
                    }
                }

                Button("Cancel") {
                    // TODO: Implement cancellation
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 20)
            )
        }
    }

    private var a3ProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)

                Text("Running A3 Clustering")
                    .font(.headline)

                Text(viewModel.a3Progress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 20)
            )
        }
    }

    private var efficientTestProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)

                Text("Efficient Sentence Analysis")
                    .font(.headline)

                Text(viewModel.efficientTestProgress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 20)
            )
        }
    }

    private var sentenceBatchProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)

                Text("Sentence Tagging")
                    .font(.headline)

                if !viewModel.sentenceBatchService.currentVideoTitle.isEmpty {
                    Text(viewModel.sentenceBatchService.currentVideoTitle)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                Text(viewModel.sentenceBatchService.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 20) {
                    VStack {
                        Text("\(viewModel.sentenceBatchService.completedVideos.count)")
                            .font(.title2.bold())
                            .foregroundColor(.green)
                        Text("Done")
                            .font(.caption)
                    }

                    VStack {
                        Text("\(viewModel.sentenceBatchService.failedVideos.count)")
                            .font(.title2.bold())
                            .foregroundColor(.red)
                        Text("Failed")
                            .font(.caption)
                    }

                    VStack {
                        Text("\(viewModel.sentenceBatchService.totalVideos - viewModel.sentenceBatchService.currentVideoIndex)")
                            .font(.title2.bold())
                            .foregroundColor(.cyan)
                        Text("Remaining")
                            .font(.caption)
                    }
                }

                // Progress bar
                ProgressView(value: Double(viewModel.sentenceBatchService.currentVideoIndex), total: Double(max(1, viewModel.sentenceBatchService.totalVideos)))
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 20)
            )
        }
    }
    
}
struct VideoStatusRow: View {
    let status: VideoAnalysisStatus
    let onTap: () -> Void
    let onQuickAnalyze: () -> Void
    let onFetchTranscript: () -> Void
    let onFidelityTest: () -> Void
    var sentenceRuns: [SentenceFidelityTest]? = nil
    var onCopySentences: (() -> Void)? = nil
    var onBoundaryDetection: (() -> Void)? = nil
    var onCopyChunks: (() -> Void)? = nil
    var onCopyRawSentences: (() -> Void)? = nil
    var onCopyLiveParse: (() -> Void)? = nil
    var onGroundTruth: (() -> Void)? = nil
    var onExperimentLab: (() -> Void)? = nil
    var onSectionSplitter: (() -> Void)? = nil
    var onDigressionDetection: (() -> Void)? = nil
    var onRhetoricalSequence: (() -> Void)? = nil
    var onQueueRhetorical: (() -> Void)? = nil
    var isQueuedForRhetorical: Bool = false
    var rhetoricalQueueProgress: String? = nil
    var needsRhetoricalAnalysis: Bool = false  // True if no sequence OR outdated sequence
    var rhetoricalMismatchInfo: (current: Int, existing: Int)? = nil  // Shows chunk count mismatch

    #if os(macOS)
    private let useHorizontalActions = true
    #else
    private let useHorizontalActions = false
    #endif

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let url = URL(string: status.video.thumbnailUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 80, height: 45)
                .cornerRadius(4)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(status.video.title)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Status badge
                    statusBadge

                    // Duration
                    Text(formattedDuration)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Transcript copy button
                    if let transcript = status.video.transcript, !transcript.isEmpty {
                        TranscriptCopyButton(transcript: transcript)
                    } else {
                        Button {
                            onFetchTranscript()
                        } label: {
                            Image(systemName: "text.alignleft")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    // Section/beat counts if available
                    if let sectionCount = status.sectionCount, sectionCount > 0 {
                        Text("\(sectionCount)s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let beatCount = status.beatCount, beatCount > 0 {
                        Text("\(beatCount)b")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Sentence analysis indicator with copy
                    if let runs = sentenceRuns, !runs.isEmpty {
                        SentenceAnalysisIndicator(
                            runs: runs,
                            onCopy: onCopySentences
                        )

                        // Chunks copy button (only if has sentence analysis)
                        if let copyChunks = onCopyChunks {
                            ChunksCopyButton(onCopy: copyChunks)
                        }

                        // Raw sentences copy button
                        if let copyRaw = onCopyRawSentences {
                            RawSentencesCopyButton(onCopy: copyRaw)
                        }
                    }

                    // Live parse copy button
                    if let copyLive = onCopyLiveParse {
                        LiveSentencesCopyButton(onCopy: copyLive)
                    }

                    // Rhetorical sequence indicator
                    if let sequence = status.video.rhetoricalSequence {
                        HStack(spacing: 2) {
                            Image(systemName: rhetoricalMismatchInfo != nil ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                                .font(.caption2)
                                .foregroundColor(rhetoricalMismatchInfo != nil ? .orange : .pink)
                            Text("\(sequence.moves.count)m")
                                .font(.caption2)
                                .foregroundColor(rhetoricalMismatchInfo != nil ? .orange : .pink)
                        }
                        .help(rhetoricalMismatchInfo != nil ? "Outdated: \(rhetoricalMismatchInfo!.existing) moves vs \(rhetoricalMismatchInfo!.current) chunks" : "Rhetorical sequence")
                    }
                }
            }

            Spacer()

            // Actions - HStack on Mac, VStack on iOS
            actionButtons
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        let buttons = actionButtonsContent
        #if os(macOS)
        HStack(spacing: 4) {
            buttons
        }
        #else
        VStack(spacing: 4) {
            buttons
        }
        #endif
    }

    @ViewBuilder
    private var actionButtonsContent: some View {
        if status.state == .notStarted {
            Button {
                onQuickAnalyze()
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }

        // Fidelity test button
        if status.video.hasTranscript {
            Button {
                onFidelityTest()
            } label: {
                Image(systemName: "testtube.2")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
            .controlSize(.small)
        }

        // Boundary detection button (only if has sentence analysis)
        if let onBoundary = onBoundaryDetection, sentenceRuns != nil {
            Button {
                onBoundary()
            } label: {
                Image(systemName: "rectangle.split.3x1")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.small)
        }

        // Section splitter fidelity test button (only if has transcript)
        if let onSplitter = onSectionSplitter {
            Button {
                onSplitter()
            } label: {
                Image(systemName: "scissors")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.teal)
            .controlSize(.small)
        }

        // Digression detection button
        if let onDigression = onDigressionDetection {
            Button {
                onDigression()
            } label: {
                Image(systemName: "text.redaction")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.indigo)
            .controlSize(.small)
        }

        // Ground truth button (only if has sentence analysis + transcript)
        if let onGT = onGroundTruth {
            Button {
                onGT()
            } label: {
                Image(systemName: "target")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.mint)
            .controlSize(.small)
        }

        // Experiment Lab button (same requirements as ground truth)
        if let onExpLab = onExperimentLab {
            Button {
                onExpLab()
            } label: {
                Image(systemName: "flask")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.indigo)
            .controlSize(.small)
        }

        // Rhetorical sequence button (show if video has rhetorical sequence)
        if let onRhetorical = onRhetoricalSequence, status.video.hasRhetoricalSequence {
            Button {
                onRhetorical()
            } label: {
                Label("Rhetorical", systemImage: "waveform.path.ecg")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.pink)
            .controlSize(.small)
        }

        // Queue for rhetorical analysis button (show if needs analysis - no sequence OR outdated)
        if let onQueue = onQueueRhetorical, needsRhetoricalAnalysis {
            if isQueuedForRhetorical {
                // Show queued/processing state
                if let progress = rhetoricalQueueProgress {
                    Text(progress)
                        .font(.caption2)
                        .foregroundColor(.pink)
                        .frame(minWidth: 60)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text("Queued")
                            .font(.caption2)
                    }
                    .foregroundColor(.pink.opacity(0.7))
                }
            } else {
                Button {
                    onQueue()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: rhetoricalMismatchInfo != nil ? "arrow.clockwise.circle.fill" : "plus.circle.fill")
                            .font(.caption)
                        if let mismatch = rhetoricalMismatchInfo {
                            // Show update button with mismatch info
                            Text("\(mismatch.existing)→\(mismatch.current)")
                                .font(.caption2)
                        } else {
                            Text("Analyze")
                                .font(.caption2)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(rhetoricalMismatchInfo != nil ? .orange : .pink)
                .controlSize(.small)
                .help(rhetoricalMismatchInfo != nil ? "Rhetorical sequence outdated: \(rhetoricalMismatchInfo!.existing) moves vs \(rhetoricalMismatchInfo!.current) chunks" : "Queue for rhetorical analysis")
            }
        }

        Button {
            onTap()
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch status.state {
        case .notStarted:
            Label("Not Analyzed", systemImage: "circle")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .inProgress:
            Label("In Progress", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption2)
                .foregroundColor(.orange)
        case .a1aComplete:
            Label("A1a Done", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundColor(.blue)
        case .a1bComplete:
            Label("Ready for A3", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.green)
        case .fullComplete:
            Label("Full Analysis", systemImage: "star.fill")
                .font(.caption2)
                .foregroundColor(.purple)
        case .failed(let error):
            Label("Failed", systemImage: "exclamationmark.circle")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }

    private var formattedDuration: String {
        let totalSeconds = TimestampCalculator.parseDuration(status.video.duration)
        guard totalSeconds > 0 else { return "--:--" }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Supporting Views

struct StatusCard: View {
    let title: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Video Analysis Row
struct VideoAnalysisRow: View {
    let video: YouTubeVideo
    let hasAnalysis: Bool
    let hasSummary: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 120, height: 68)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .lineLimit(2)
                
                HStack {
                    Label(formatDuration(video.duration), systemImage: "clock")
                    
                    Spacer()
                    
                    // Status indicators
                    if hasSummary {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if hasAnalysis {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ seconds: String) -> String {
        guard let totalSeconds = Int(seconds) else { return seconds }
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Style Profile Card
struct StyleProfileCard: View {
    let profile: StyleProfile
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name.replacingOccurrences(of: "_", with: " "))
                        .font(.headline)
                    
                    Text("\(profile.videoCount) videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            // Description
            Text(profile.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Topics
            if !profile.triggerTopics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(profile.triggerTopics, id: \.self) { topic in
                            Text(topic)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            // Expanded details
            if isExpanded {
                Divider()
                
                // Stats
                VStack(alignment: .leading, spacing: 6) {
                    SimpleStatRow(label: "Turn Position", value: "\(Int(profile.turnPositionMean * 100))%")
                    SimpleStatRow(label: "Avg Formality", value: String(format: "%.1f/10", profile.voiceAvgFormality))
                    SimpleStatRow(label: "Sections", value: profile.typicalSectionSequence.joined(separator: " → "))
                }
                .font(.caption)
                
                // Discriminators
                if !profile.discriminators.isEmpty {
                    Divider()
                    Text("What makes this unique:")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    ForEach(profile.discriminators, id: \.self) { d in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(d)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct SimpleStatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Circular Progress View
struct CircularProgressView: View {
    let progress: Double
    let lineWidth: CGFloat

    private var safeProgress: Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: safeProgress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: safeProgress)

            Text("\(Int(safeProgress * 100))%")
                .font(.caption)
                .fontWeight(.bold)
        }
    }
}

// MARK: - Transcript Copy Button
struct TranscriptCopyButton: View {
    let transcript: String
    @State private var isCopied = false

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIPasteboard.general.string = transcript
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            #endif

            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = true
            }

            // Fade back after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isCopied = false
                }
            }
        } label: {
            Image(systemName: isCopied ? "checkmark" : "text.alignleft")
                .font(.caption2)
                .foregroundColor(isCopied ? .blue : .green)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sentence Analysis Indicator
struct SentenceAnalysisIndicator: View {
    let runs: [SentenceFidelityTest]
    var onCopy: (() -> Void)?
    @State private var isCopied = false

    private var latestRun: SentenceFidelityTest? {
        runs.first
    }

    private var sentenceCount: Int {
        latestRun?.totalSentences ?? 0
    }

    private var runCount: Int {
        runs.count
    }

    var body: some View {
        HStack(spacing: 4) {
            // Indicator showing sentence count and runs
            Text("\(sentenceCount)s")
                .font(.caption2)
                .foregroundColor(.cyan)

            Text("\(runCount)r")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Copy button
            if let onCopy = onCopy {
                Button {
                    onCopy()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isCopied = false
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundColor(isCopied ? .green : .cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.cyan.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Chunks Copy Button
struct ChunksCopyButton: View {
    let onCopy: () -> Void
    @State private var isCopied = false

    var body: some View {
        Button {
            onCopy()
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isCopied = false
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: isCopied ? "checkmark" : "rectangle.split.3x1")
                    .font(.caption2)
            }
            .foregroundColor(isCopied ? .green : .blue)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(4)
    }
}

struct RawSentencesCopyButton: View {
    let onCopy: () -> Void
    @State private var isCopied = false

    var body: some View {
        Button {
            onCopy()
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isCopied = false
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: isCopied ? "checkmark" : "list.number")
                    .font(.caption2)
            }
            .foregroundColor(isCopied ? .green : .orange)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(4)
    }
}

struct LiveSentencesCopyButton: View {
    let onCopy: () -> Void
    @State private var isCopied = false

    var body: some View {
        Button {
            onCopy()
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isCopied = false
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: isCopied ? "checkmark" : "arrow.counterclockwise")
                    .font(.caption2)
            }
            .foregroundColor(isCopied ? .green : .teal)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.teal.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Rhetorical Fidelity Test Sheet

struct RhetoricalFidelityTestSheet: View {
    let video: YouTubeVideo
    let channel: YouTubeChannel
    @Environment(\.dismiss) private var dismiss

    // Test configuration
    @State private var runCount: Int = 3
    @State private var temperature: Double = 0.1

    // Test state
    @State private var isRunning = false
    @State private var progress: (completed: Int, total: Int) = (0, 0)
    @State private var currentRunNumber: Int = 0
    @State private var chunkProgress: (completed: Int, total: Int) = (0, 0)
    @State private var testRuns: [(run: Int, temperature: Double, sequence: RhetoricalSequence)] = []
    @State private var errorMessage: String?
    @State private var copyConfirmation = false

    private let service = RhetoricalMoveService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Video info
                    videoInfoSection

                    Divider()

                    if isRunning {
                        runningView
                    } else if !testRuns.isEmpty {
                        resultsView
                    } else {
                        configurationView
                    }
                }
                .padding()
            }
            .navigationTitle("Rhetorical Fidelity Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !testRuns.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            copyReport()
                            copyConfirmation = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copyConfirmation = false
                            }
                        }) {
                            Label(copyConfirmation ? "Copied!" : "Copy Report", systemImage: copyConfirmation ? "checkmark" : "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Label(video.durationFormatted, systemImage: "clock")
                Spacer()
                if video.wordCount > 0 {
                    Label("\(video.wordCount) words", systemImage: "text.alignleft")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var configurationView: some View {
        VStack(spacing: 20) {
            // Run count picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Number of Runs")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Runs", selection: $runCount) {
                    Text("1").tag(1)
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("10").tag(10)
                }
                .pickerStyle(.segmented)
            }

            // Temperature slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.2f", temperature))
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }

                Slider(value: $temperature, in: 0...1, step: 0.05)

                HStack {
                    Text("Deterministic")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Creative")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Run button
            Button(action: runTest) {
                Label("Run \(runCount)x Fidelity Test", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var runningView: some View {
        VStack(spacing: 16) {
            Spacer()

            // Overall run progress
            ProgressView(value: Double(progress.completed), total: Double(progress.total))
                .progressViewStyle(.linear)
                .frame(maxWidth: 250)

            Text("Run \(currentRunNumber) of \(progress.total)")
                .font(.headline)

            // Chunk progress within current run
            if chunkProgress.total > 0 {
                ProgressView(value: Double(chunkProgress.completed), total: Double(chunkProgress.total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                    .tint(.green)

                Text("Chunk \(chunkProgress.completed)/\(chunkProgress.total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Processing chunks in parallel (10 concurrent)...")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(minHeight: 200)
    }

    private var resultsView: some View {
        VStack(spacing: 16) {
            // Action buttons row
            HStack {
                Button(action: { runCount = 1; runTest() }) {
                    Label("+1 Run", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)

                Button(action: { runCount = 3; runTest() }) {
                    Label("+3 Runs", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    copyReport()
                    copyConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copyConfirmation = false
                    }
                }) {
                    Label(copyConfirmation ? "Copied!" : "Copy", systemImage: copyConfirmation ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }

            // Stability summary
            if testRuns.count > 1 {
                stabilityCard
            }

            // Run summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Runs Completed: \(testRuns.count)")
                    .font(.headline)

                ForEach(testRuns, id: \.run) { runData in
                    HStack {
                        Text("Run #\(runData.run)")
                        Spacer()
                        Text("T=\(String(format: "%.2f", runData.temperature))")
                            .foregroundColor(.secondary)
                        Text("\(runData.sequence.moves.count) moves")
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.0f%%", runData.sequence.averageConfidence * 100)) conf")
                            .foregroundColor(.blue)
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)

            // Disagreements
            if !disagreements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Disagreements (\(disagreements.count) chunks)")
                        .font(.headline)
                        .foregroundColor(.orange)

                    ForEach(disagreements, id: \.chunkIndex) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chunk \(item.chunkIndex)")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(item.labels.map { $0.displayName }.joined(separator: " vs "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var stabilityCard: some View {
        HStack(spacing: 20) {
            VStack {
                Text("\(String(format: "%.0f", stabilityScore * 100))%")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(stabilityScore >= 0.9 ? .green : stabilityScore >= 0.7 ? .orange : .red)
                Text("Stability")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack {
                Text("\(testRuns.count)")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Runs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack {
                Text("\(disagreements.count)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(disagreements.isEmpty ? .green : .orange)
                Text("Conflicts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Computed Properties

    private var stabilityScore: Double {
        guard testRuns.count > 1 else { return 1.0 }
        let chunkCount = testRuns.first?.sequence.moves.count ?? 0
        guard chunkCount > 0 else { return 1.0 }

        var agreements = 0
        for chunkIndex in 0..<chunkCount {
            let labels = testRuns.compactMap { runData -> RhetoricalMoveType? in
                runData.sequence.moves.first { $0.chunkIndex == chunkIndex }?.moveType
            }
            if Set(labels).count == 1 {
                agreements += 1
            }
        }
        return Double(agreements) / Double(chunkCount)
    }

    private var disagreements: [(chunkIndex: Int, labels: [RhetoricalMoveType])] {
        guard testRuns.count > 1 else { return [] }
        let chunkCount = testRuns.first?.sequence.moves.count ?? 0

        var results: [(Int, [RhetoricalMoveType])] = []
        for chunkIndex in 0..<chunkCount {
            let labels = testRuns.compactMap { runData -> RhetoricalMoveType? in
                runData.sequence.moves.first { $0.chunkIndex == chunkIndex }?.moveType
            }
            if Set(labels).count > 1 {
                results.append((chunkIndex, labels))
            }
        }
        return results
    }

    // MARK: - Actions

    private func runTest() {
        // Get sentence fidelity data for this video
        let viewModel = CreatorDetailViewModel.shared
        guard let sentenceRuns = viewModel.videoSentenceData[video.videoId],
              let latestRun = sentenceRuns.first else {
            errorMessage = "No sentence analysis data. Run sentence fidelity test first."
            return
        }

        // Get chunks from boundary detection
        let boundaryService = BoundaryDetectionService.shared
        let boundaryResult = boundaryService.detectBoundaries(from: latestRun)
        let chunks = boundaryResult.chunks

        guard !chunks.isEmpty else {
            errorMessage = "No chunks detected from sentence data"
            return
        }

        isRunning = true
        let startingRunNumber = testRuns.count
        let runsToExecute = runCount
        let temp = temperature

        progress = (0, runsToExecute)
        chunkProgress = (0, chunks.count)

        Task {
            // Run each fidelity test sequentially, but chunks within each run are parallel
            for runNum in 0..<runsToExecute {
                let runNumber = startingRunNumber + runNum + 1

                await MainActor.run {
                    currentRunNumber = runNumber
                    chunkProgress = (0, chunks.count)
                }

                do {
                    // Use incremental extraction - processes chunks in parallel (10 concurrent)
                    let sequence = try await service.extractRhetoricalSequenceIncremental(
                        videoId: video.videoId,
                        chunks: chunks,
                        existingMoves: [],
                        temperature: temp,
                        concurrency: 10,
                        onMoveExtracted: { move, current, total in
                            await MainActor.run {
                                chunkProgress = (current, total)
                            }
                        },
                        onProgress: nil
                    )

                    await MainActor.run {
                        testRuns.append((run: runNumber, temperature: temp, sequence: sequence))
                        testRuns.sort { $0.run < $1.run }
                        progress.completed += 1
                    }
                } catch {
                    print("Fidelity run \(runNumber) failed: \(error)")
                    await MainActor.run {
                        progress.completed += 1
                        errorMessage = "Run \(runNumber) failed: \(error.localizedDescription)"
                    }
                }
            }

            await MainActor.run {
                isRunning = false
                chunkProgress = (0, 0)
            }
        }
    }

    private func copyReport() {
        var report = """
        RHETORICAL FIDELITY TEST REPORT
        ═══════════════════════════════════════
        Video: \(video.title)
        Video ID: \(video.videoId)
        Total Runs: \(testRuns.count)
        Stability Score: \(String(format: "%.0f%%", stabilityScore * 100))
        Disagreements: \(disagreements.count)

        RUNS:
        """

        for runData in testRuns {
            report += "\nRun #\(runData.run) | T=\(String(format: "%.2f", runData.temperature)) | \(runData.sequence.moves.count) moves | \(String(format: "%.0f%%", runData.sequence.averageConfidence * 100)) avg conf"
        }

        if !disagreements.isEmpty {
            report += "\n\nDISAGREEMENTS:"
            for item in disagreements {
                report += "\nChunk \(item.chunkIndex): \(item.labels.map { $0.displayName }.joined(separator: " vs "))"
            }
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }
}

// MARK: - Creator Chunk Browser View

struct CreatorChunkBrowserView: View {
    let channel: YouTubeChannel
    let videos: [YouTubeVideo]

    // Sorting
    enum SortMode: String, CaseIterable {
        case parentCategory = "Parent Category"
        case moveLabel = "Move Label"
        case videoTitle = "Video"
    }
    @State private var sortMode: SortMode = .parentCategory

    // Filtering
    @State private var selectedParentCategory: RhetoricalCategory? = nil
    @State private var selectedMoveType: RhetoricalMoveType? = nil

    // Search
    @State private var searchText = ""
    @State private var searchCategory: RhetoricalCategory? = nil
    @State private var searchMoveType: RhetoricalMoveType? = nil
    @State private var isSearching = false
    @State private var searchResults: [ChunkSearchResult] = []

    // Expanded chunks
    @State private var expandedChunkIds: Set<String> = []

    // Raw text cache - stores chunk text by videoId_chunkIndex
    @State private var chunkTextCache: [String: String] = [:]
    @State private var loadingChunkIds: Set<String> = []

    private let fidelityService = SentenceFidelityFirebaseService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Search Section
            searchSection

            Divider()

            // Filter/Sort Bar
            filterSortBar

            Divider()

            // Content
            if isSearching {
                searchingView
            } else if !searchResults.isEmpty {
                searchResultsView
            } else {
                chunkListView
            }
        }
        .navigationTitle("Chunk Browser")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text("\(allChunks.count) chunks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(spacing: 12) {
            // Text input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Enter a sentence to find matching chunks...", text: $searchText, axis: .vertical)
                    .lineLimit(1...3)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)

            // Category filter for search
            HStack {
                Text("Search in:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Category", selection: $searchCategory) {
                    Text("All Categories").tag(nil as RhetoricalCategory?)
                    ForEach(RhetoricalCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat as RhetoricalCategory?)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: searchCategory) { _, _ in
                    // Clear move type when category changes
                    searchMoveType = nil
                }

                // Move type picker (child category)
                Picker("Move", selection: $searchMoveType) {
                    Text("All Moves").tag(nil as RhetoricalMoveType?)
                    ForEach(moveTypesForCategory(searchCategory), id: \.self) { moveType in
                        Text(moveType.displayName).tag(moveType as RhetoricalMoveType?)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                // AI Search button
                Button(action: performAISearch) {
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Find Matches", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
        }
        .padding()
    }

    // MARK: - Filter/Sort Bar

    private var filterSortBar: some View {
        VStack(spacing: 0) {
            // Row 1: Sort and Parent Categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Sort picker
                    Menu {
                        ForEach(SortMode.allCases, id: \.self) { mode in
                            Button(action: { sortMode = mode }) {
                                if sortMode == mode {
                                    Label(mode.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(mode.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label("Sort: \(sortMode.rawValue)", systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Divider()
                        .frame(height: 20)

                    // Parent category filter chips
                    ForEach(RhetoricalCategory.allCases, id: \.self) { category in
                        Button(action: {
                            if selectedParentCategory == category {
                                selectedParentCategory = nil
                                selectedMoveType = nil
                            } else {
                                selectedParentCategory = category
                                selectedMoveType = nil
                            }
                        }) {
                            Text(category.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedParentCategory == category ? categoryColor(category) : Color.secondary.opacity(0.2))
                                .foregroundColor(selectedParentCategory == category ? .white : .primary)
                                .cornerRadius(16)
                        }
                    }

                    if selectedParentCategory != nil || selectedMoveType != nil {
                        Button(action: {
                            selectedParentCategory = nil
                            selectedMoveType = nil
                        }) {
                            Label("Clear", systemImage: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Row 2: Move Type chips (shown when a parent category is selected)
            if let category = selectedParentCategory {
                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Move:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        ForEach(moveTypesForCategory(category), id: \.self) { moveType in
                            Button(action: {
                                if selectedMoveType == moveType {
                                    selectedMoveType = nil
                                } else {
                                    selectedMoveType = moveType
                                }
                            }) {
                                Text(moveType.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedMoveType == moveType ? categoryColor(category) : Color.secondary.opacity(0.15))
                                    .foregroundColor(selectedMoveType == moveType ? .white : .primary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(categoryColor(category).opacity(0.05))
            }
        }
    }

    // MARK: - Chunk List View

    private var chunkListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(groupedChunks.keys.sorted(by: groupSortOrder), id: \.self) { groupKey in
                    if let chunks = groupedChunks[groupKey] {
                        chunkGroupSection(title: groupKey, chunks: chunks)
                    }
                }
            }
            .padding()
        }
    }

    private func chunkGroupSection(title: String, chunks: [ChunkWithContext]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group header
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(chunks.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.bottom, 4)

            // Chunks in this group
            ForEach(chunks, id: \.id) { chunk in
                chunkCard(chunk)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private func chunkCard(_ chunk: ChunkWithContext) -> some View {
        let isExpanded = expandedChunkIds.contains(chunk.id)

        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                // Move type badge
                Text(chunk.move.moveType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor(chunk.move.moveType.category))
                    .foregroundColor(.white)
                    .cornerRadius(8)

                Text("•")
                    .foregroundColor(.secondary)

                Text(chunk.videoTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(chunk.move.confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button(action: {
                    withAnimation {
                        if isExpanded {
                            expandedChunkIds.remove(chunk.id)
                        } else {
                            expandedChunkIds.insert(chunk.id)
                            loadChunkText(for: chunk)
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }

            // Brief description (always visible)
            Text(chunk.move.briefDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 2)

            // Expanded content
            if isExpanded {
                Divider()

                // Gists
                if let gistA = chunk.move.gistA {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gist A (Deterministic)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)

                        Text("Subject: \(gistA.subject.joined(separator: ", "))")
                            .font(.caption2)

                        Text("Premise: \(gistA.premise)")
                            .font(.caption2)

                        Text("Frame: \(gistA.frame.displayName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }

                if let gistB = chunk.move.gistB {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gist B (Flexible)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)

                        Text("Subject: \(gistB.subject.joined(separator: ", "))")
                            .font(.caption2)

                        Text("Premise: \(gistB.premise)")
                            .font(.caption2)

                        Text("Frame: \(gistB.frame.displayName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }

                // Expanded description
                if let expanded = chunk.move.expandedDescription {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expanded")
                            .font(.caption2)
                            .fontWeight(.medium)

                        Text(expanded)
                            .font(.caption2)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }

                // Raw text section
                rawTextSection(for: chunk)
            }
        }
        .padding()
        .background(Color.white.opacity(0.5))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func rawTextSection(for chunk: ChunkWithContext) -> some View {
        if let cachedText = chunkTextCache[chunk.id] {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Raw Text")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)

                    Spacer()

                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = cachedText
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cachedText, forType: .string)
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                }

                Text(cachedText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        } else if loadingChunkIds.contains(chunk.id) {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading raw text...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        } else {
            Button {
                loadChunkText(for: chunk)
            } label: {
                Label("Load Raw Text", systemImage: "arrow.down.circle")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
    }

    private func loadChunkText(for chunk: ChunkWithContext) {
        guard chunkTextCache[chunk.id] == nil, !loadingChunkIds.contains(chunk.id) else { return }

        loadingChunkIds.insert(chunk.id)

        Task {
            do {
                // Fetch fidelity tests for this video
                let tests = try await fidelityService.getTestRuns(forVideoId: chunk.videoId)

                // Get the latest test with sentences
                guard let latestTest = tests.sorted(by: { $0.createdAt > $1.createdAt }).first,
                      !latestTest.sentences.isEmpty else {
                    await MainActor.run {
                        loadingChunkIds.remove(chunk.id)
                        chunkTextCache[chunk.id] = "[No sentence data available]"
                    }
                    return
                }

                // Use BoundaryDetectionService to get chunks
                let boundaryResult = BoundaryDetectionService.shared.detectBoundaries(from: latestTest)

                // Find the matching chunk by index
                if let matchingChunk = boundaryResult.chunks.first(where: { $0.chunkIndex == chunk.move.chunkIndex }) {
                    await MainActor.run {
                        chunkTextCache[chunk.id] = matchingChunk.fullText
                        loadingChunkIds.remove(chunk.id)
                    }
                } else {
                    await MainActor.run {
                        chunkTextCache[chunk.id] = "[Chunk \(chunk.move.chunkIndex) not found in boundary data]"
                        loadingChunkIds.remove(chunk.id)
                    }
                }
            } catch {
                await MainActor.run {
                    loadingChunkIds.remove(chunk.id)
                    chunkTextCache[chunk.id] = "[Error: \(error.localizedDescription)]"
                }
            }
        }
    }

    // MARK: - Search Views

    private var searchingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Finding matching chunks...")
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var searchResultsView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Results header
                HStack {
                    Text("Found \(searchResults.count) matches")
                        .font(.headline)

                    Spacer()

                    Button(action: { searchResults = [] }) {
                        Label("Clear Results", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.top)

                // Result cards
                ForEach(searchResults) { result in
                    searchResultCard(result)
                }
            }
            .padding()
        }
    }

    private func searchResultCard(_ result: ChunkSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Match score header
            HStack {
                // Score badge
                Text("\(Int(result.matchScore * 100))% match")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(matchScoreColor(result.matchScore))
                    .foregroundColor(.white)
                    .cornerRadius(8)

                // Move type
                Text(result.chunk.move.moveType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor(result.chunk.move.moveType.category))
                    .foregroundColor(.white)
                    .cornerRadius(8)

                Spacer()

                Text(result.chunk.videoTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Match reason
            VStack(alignment: .leading, spacing: 4) {
                Text("Why it matched:")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)

                Text(result.matchReason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            // Gist comparison
            if let gistB = result.chunk.move.gistB {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gist:")
                        .font(.caption2)
                        .fontWeight(.medium)

                    Text(gistB.premise)
                        .font(.caption)
                }
            }

            // Brief description
            Text(result.chunk.move.briefDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            // Raw text
            if let rawText = result.chunk.rawText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Raw Text:")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)

                    Text(rawText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(5)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Data

    private var allChunks: [ChunkWithContext] {
        var chunks: [ChunkWithContext] = []

        for video in videos {
            guard let sequence = video.rhetoricalSequence else { continue }

            for move in sequence.moves {
                let chunk = ChunkWithContext(
                    id: "\(video.videoId)_\(move.chunkIndex)",
                    videoId: video.videoId,
                    videoTitle: video.title,
                    move: move,
                    rawText: nil // Would need to fetch from boundary detection
                )
                chunks.append(chunk)
            }
        }

        return chunks
    }

    private var filteredChunks: [ChunkWithContext] {
        var chunks = allChunks

        // Filter by parent category
        if let category = selectedParentCategory {
            chunks = chunks.filter { $0.move.moveType.category == category }
        }

        // Filter by specific move type
        if let moveType = selectedMoveType {
            chunks = chunks.filter { $0.move.moveType == moveType }
        }

        return chunks
    }

    private var groupedChunks: [String: [ChunkWithContext]] {
        var groups: [String: [ChunkWithContext]] = [:]

        for chunk in filteredChunks {
            let key: String
            switch sortMode {
            case .parentCategory:
                key = chunk.move.moveType.category.rawValue
            case .moveLabel:
                key = chunk.move.moveType.displayName
            case .videoTitle:
                key = chunk.videoTitle
            }

            if groups[key] == nil {
                groups[key] = []
            }
            groups[key]?.append(chunk)
        }

        return groups
    }

    private func groupSortOrder(_ a: String, _ b: String) -> Bool {
        switch sortMode {
        case .parentCategory:
            let catA = RhetoricalCategory.allCases.first { $0.rawValue == a }
            let catB = RhetoricalCategory.allCases.first { $0.rawValue == b }
            let orderA = catA.map { RhetoricalCategory.allCases.firstIndex(of: $0) ?? 0 } ?? 0
            let orderB = catB.map { RhetoricalCategory.allCases.firstIndex(of: $0) ?? 0 } ?? 0
            return orderA < orderB
        case .moveLabel, .videoTitle:
            return a < b
        }
    }

    // MARK: - AI Search

    private func performAISearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        searchResults = []

        Task {
            do {
                let results = try await findMatchingChunks(query: query, category: searchCategory)

                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    print("Search error: \(error)")
                    isSearching = false
                }
            }
        }
    }

    private func findMatchingChunks(query: String, category: RhetoricalCategory?) async throws -> [ChunkSearchResult] {
        // Filter chunks to search
        var chunksToSearch = allChunks
        if let category = category {
            chunksToSearch = chunksToSearch.filter { $0.move.moveType.category == category }
        }

        // Limit to reasonable number for AI
        let maxChunks = min(100, chunksToSearch.count)
        let sampledChunks = Array(chunksToSearch.prefix(maxChunks))

        // Build gist summaries for AI comparison
        var gistDescriptions: [(index: Int, chunk: ChunkWithContext, gistText: String)] = []
        for (index, chunk) in sampledChunks.enumerated() {
            var gistText = "[\(index)] \(chunk.move.moveType.displayName): "
            if let gistB = chunk.move.gistB {
                gistText += gistB.premise
            } else {
                gistText += chunk.move.briefDescription
            }
            gistDescriptions.append((index, chunk, gistText))
        }

        // Call AI to find matches
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let gistList = gistDescriptions.map { $0.gistText }.joined(separator: "\n")

        let prompt = """
        I have a sentence/idea that I want to find matching rhetorical chunks for:

        QUERY: "\(query)"

        Here are the available chunks with their gists:

        \(gistList)

        Find the TOP 10 chunks that best match the query semantically. Consider:
        - Similar rhetorical function
        - Similar structural purpose
        - Similar topic or approach

        Return a JSON array with your rankings:
        {
          "matches": [
            {
              "index": 0,
              "score": 0.95,
              "reason": "Why this chunk matches the query"
            }
          ]
        }

        Score from 0.0 to 1.0. Only include chunks with score >= 0.5.
        Output ONLY valid JSON.
        """

        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: "You are a rhetorical analysis assistant helping find similar chunks.",
            params: ["temperature": 0.1, "max_tokens": 2000]
        )

        // Parse response
        return parseSearchResults(response, chunks: sampledChunks)
    }

    private func parseSearchResults(_ response: String, chunks: [ChunkWithContext]) -> [ChunkSearchResult] {
        // Extract JSON
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.range(of: "{") {
            text = String(text[start.lowerBound...])
        }
        if let end = text.range(of: "}", options: .backwards) {
            text = String(text[...end.lowerBound])
        }

        guard let data = text.data(using: .utf8) else { return [] }

        struct AIMatch: Codable {
            let index: Int
            let score: Double
            let reason: String
        }

        struct AIResponse: Codable {
            let matches: [AIMatch]
        }

        do {
            let parsed = try JSONDecoder().decode(AIResponse.self, from: data)

            var results: [ChunkSearchResult] = []
            for match in parsed.matches {
                guard match.index >= 0 && match.index < chunks.count else { continue }

                let chunk = chunks[match.index]
                results.append(ChunkSearchResult(
                    id: UUID().uuidString,
                    chunk: chunk,
                    matchScore: match.score,
                    matchReason: match.reason
                ))
            }

            return results.sorted { $0.matchScore > $1.matchScore }
        } catch {
            print("Failed to parse search results: \(error)")
            return []
        }
    }

    // MARK: - Helpers

    private func categoryColor(_ category: RhetoricalCategory) -> Color {
        switch category {
        case .hook: return .red
        case .setup: return .blue
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .green
        case .closing: return .gray
        }
    }

    private func moveTypesForCategory(_ category: RhetoricalCategory?) -> [RhetoricalMoveType] {
        guard let category = category else {
            return RhetoricalMoveType.allCases
        }
        return RhetoricalMoveType.allCases.filter { $0.category == category }
    }

    private func matchScoreColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .orange }
        return .red
    }
}

// MARK: - Supporting Types for Chunk Browser

struct ChunkWithContext: Identifiable {
    let id: String
    let videoId: String
    let videoTitle: String
    let move: RhetoricalMove
    let rawText: String?
}

struct ChunkSearchResult: Identifiable {
    let id: String
    let chunk: ChunkWithContext
    let matchScore: Double
    let matchReason: String
}
