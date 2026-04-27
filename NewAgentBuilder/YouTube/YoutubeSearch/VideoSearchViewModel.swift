//
//  VideoSearchViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/17/25.
//

import Foundation
import Combine

@MainActor
class VideoSearchViewModel: ObservableObject {
    static let instance = VideoSearchViewModel()
    
    enum SearchMode {
        case title
        case transcript
        case both
    }
    
    enum LoadMode {
        case all
        case pinnedChannels
        
        var title: String {
            switch self {
            case .all: return "All Videos"
            case .pinnedChannels: return "Pinned Channels"
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .pinnedChannels: return "pin.fill"
            }
        }
    }
    
    enum SortOption: String, CaseIterable {
        case dateNewest = "Newest First"
        case dateOldest = "Oldest First"
        case viewsHighest = "Most Views"
        case viewsLowest = "Least Views"
        case titleAZ = "Title A-Z"
        case titleZA = "Title Z-A"
        case durationLongest = "Longest"
        case durationShortest = "Shortest"
    }
    
    // MARK: - Published Properties
    @Published var searchText = ""
    @Published var excludeText = ""
    @Published var searchMode: SearchMode = .both
    @Published var sortOption: SortOption = .dateNewest
    @Published var showOnlyWithTranscripts = false
    @Published var showOnlyWithoutTranscripts = false
    @Published var selectedChannels: Set<String> = []
    @Published var filteredVideos: [YouTubeVideo] = []
    @Published var availableChannels: [YouTubeChannel] = []
    @Published var loadMode: LoadMode = .pinnedChannels
    @Published var isLoading = false
    @Published private(set) var allVideos: [YouTubeVideo] = []
    @Published var selectedTopics: [String] = []  // ✅ NEW: Selected research topic IDs
    @Published var topicsMap: [String: [String]] = [:]  // ✅ NEW: topicId -> [videoIds]
    @Published var hasLoadedInitialData = false
    @Published var loadStatusMessage = ""
    
    // MARK: - New Filter Properties
    @Published var transcriptFilter: Int = 0 // 0 = All, 1 = Has, 2 = None
    @Published var factsFilter: Int = 0      // 0 = All, 1 = Has, 2 = None
    @Published var summaryFilter: Int = 0    // 0 = All, 1 = Has, 2 = None
    
    private let firebaseService: YouTubeFirebaseService
    private var cancellables = Set<AnyCancellable>()
    
    private init(firebaseService: YouTubeFirebaseService = YouTubeFirebaseService.shared) {
        self.firebaseService = firebaseService
        setupBindings()
    }
    
    private func setupBindings() {
        // Auto-filter when search/sort/mode changes
        Publishers.CombineLatest4(
            $searchText,
            $excludeText,
            $searchMode,
            $sortOption
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.filterVideos()
        }
        .store(in: &cancellables)
        
        // Auto-filter when transcript toggles or channels change
        Publishers.CombineLatest3(
            $showOnlyWithTranscripts,
            $showOnlyWithoutTranscripts,
            $selectedChannels
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.filterVideos()
        }
        .store(in: &cancellables)
        
        // Auto-filter when segmented filter pickers change
        Publishers.CombineLatest3(
            $transcriptFilter,
            $factsFilter,
            $summaryFilter
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.filterVideos()
        }
        .store(in: &cancellables)
        
//        $loadMode
//                .dropFirst() // Don't trigger on initial value
//                .sink { [weak self] _ in
//                    Task {
//                        await self?.loadData()
//                    }
//                }
//                .store(in: &cancellables)
    }
    func loadData() async {
        isLoading = true
        
        do {
            availableChannels = try await firebaseService.fetchAllChannels()
            allVideos = try await firebaseService.fetchAllVideos()  // ✅ Back to loading all
            await loadTopicMappings()
            
            await firebaseService.verifyChannelsHuntingStatus(channels: availableChannels, videos: allVideos)
            filterVideos()
            hasLoadedInitialData = true
        } catch {
            print("Error loading data: \(error)")
        }
        
        isLoading = false
    }
    func loadData1() async {
            isLoading = true
            loadStatusMessage = "Loading..."
            
            do {
                // Always load all channels for the filter
                availableChannels = try await firebaseService.fetchAllChannels()
                
                // Load videos based on mode
                switch loadMode {
                case .all:
                    allVideos = try await firebaseService.fetchAllVideos()
                    loadStatusMessage = "✅ Loaded \(allVideos.count) videos"
                    
                case .pinnedChannels:
                    allVideos = try await firebaseService.loadVideosForPinnedChannels()
                    let pinnedCount = availableChannels.filter { $0.isPinned }.count
                    loadStatusMessage = "✅ Loaded \(allVideos.count) videos from \(pinnedCount) pinned channels"
                }
                
                await loadTopicMappings()
                await firebaseService.verifyChannelsHuntingStatus(channels: availableChannels, videos: allVideos)
                filterVideos()
                hasLoadedInitialData = true
                
                // Clear status after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    loadStatusMessage = ""
                }
                
            } catch {
                print("❌ Error loading data: \(error)")
                loadStatusMessage = "❌ Load failed: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
//    func loadTopicMappings() async {
//        let topicManager = ResearchTopicManager()
//        
//        do {
//            try await topicManager.fetchAllTopics()
//            
//            // Build a map of topicId -> [videoIds]
//            var mapping: [String: [String]] = [:]
//            for topic in topicManager.topics {
//                mapping[topic.id] = topic.videoIds
//            }
//            
//            await MainActor.run {
//                self.topicsMap = mapping
//            }
//            
//            print("✅ Loaded \(topicManager.topics.count) topic mappings")
//        } catch {
//            print("❌ Error loading topics: \(error)")
//        }
//    }
    
    func loadTopicMappings() async {
        let topicManager = ResearchTopicManager.shared  // ✅ Use shared instance
        
        // Load data if not already loaded (will skip if already cached)
        await topicManager.loadDataIfNeeded()
        
        // Build a map of topicId -> [videoIds]
        var mapping: [String: [String]] = [:]
        for topic in topicManager.topics {
            mapping[topic.id] = topic.videoIds
        }
        
        await MainActor.run {
            self.topicsMap = mapping
        }
        
        print("✅ Loaded \(topicManager.topics.count) topic mappings")
    }
    func filterVideos() {
        var results = allVideos
        
        // Search text filter
        if !searchText.isEmpty {
            results = results.filter { video in
                let searchLower = searchText.lowercased()
                
                switch searchMode {
                case .both:
                    return video.title.lowercased().contains(searchLower) ||
                           (video.transcript?.lowercased().contains(searchLower) ?? false)
                case .title:
                    return video.title.lowercased().contains(searchLower)
                case .transcript:
                    return video.transcript?.lowercased().contains(searchLower) ?? false
                }
            }
        }
        
        // Exclude words filter
        if !excludeText.isEmpty {
            let excludeWords = excludeText.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
            
            results = results.filter { video in
                let titleLower = video.title.lowercased()
                let transcriptLower = video.transcript?.lowercased() ?? ""
                
                return !excludeWords.contains { word in
                    titleLower.contains(word) || transcriptLower.contains(word)
                }
            }
        }
        
        // Channel filter
        if !selectedChannels.isEmpty {
            results = results.filter { selectedChannels.contains($0.channelId) }
        }
        
        // ✅ NEW: Research Topic filter
        if !selectedTopics.isEmpty {
            // Get all video IDs from selected topics
            var videoIdsInTopics: Set<String> = []
            for topicId in selectedTopics {
                if let videoIds = topicsMap[topicId] {
                    videoIdsInTopics.formUnion(videoIds)
                }
            }
            
            // Filter to only videos in selected topics
            results = results.filter { videoIdsInTopics.contains($0.videoId) }
        }
        
        // Transcript filter
        switch transcriptFilter {
        case 1: // Has transcript
            results = results.filter { $0.hasTranscript }
        case 2: // No transcript
            results = results.filter { !$0.hasTranscript }
        default:
            break
        }
        
        // Facts filter
        switch factsFilter {
        case 1: // Has facts
            results = results.filter { $0.hasFacts }
        case 2: // No facts
            results = results.filter { !$0.hasFacts }
        default:
            break
        }
        
        // Summary filter
        switch summaryFilter {
        case 1: // Has summary
            results = results.filter { $0.hasSummary }
        case 2: // No summary
            results = results.filter { !$0.hasSummary }
        default:
            break
        }
        
        // Apply sorting
        // Apply sorting
        results.sort { video1, video2 in
            switch sortOption {
            case .dateNewest:
                return video1.publishedAt > video2.publishedAt
            case .dateOldest:
                return video1.publishedAt < video2.publishedAt
            case .viewsHighest:
                return video1.stats.viewCount > video2.stats.viewCount
            case .viewsLowest:
                return video1.stats.viewCount < video2.stats.viewCount
            case .titleAZ:
                return video1.title < video2.title
            case .titleZA:
                return video1.title > video2.title
            case .durationLongest:
                return parseDuration(video1.duration) > parseDuration(video2.duration)
            case .durationShortest:
                return parseDuration(video1.duration) < parseDuration(video2.duration)
            }
        }

        filteredVideos = results
        
        filteredVideos = results
    }

    func filterVideos1() {
        var results = allVideos
        
        // Filter by channel
        if !selectedChannels.isEmpty {
            results = results.filter { selectedChannels.contains($0.channelId) }
        }
        
        // Filter by old transcript toggles (kept for backwards compatibility)
        if showOnlyWithTranscripts {
            results = results.filter { $0.transcript != nil && !($0.transcript?.isEmpty ?? true) }
        } else if showOnlyWithoutTranscripts {
            results = results.filter { $0.transcript == nil || $0.transcript?.isEmpty == true }
        }
        
        // NEW: Filter by segmented transcript picker
        switch transcriptFilter {
        case 1: // Has Transcript
            results = results.filter { !($0.transcript?.isEmpty ?? true) }
        case 2: // No Transcript
            results = results.filter { $0.transcript?.isEmpty ?? true }
        default: // All
            break
        }
        
        // NEW: Filter by facts
        switch factsFilter {
        case 1: // Has Facts
            results = results.filter { !($0.factsText?.isEmpty ?? true) }
        case 2: // No Facts
            results = results.filter { $0.factsText?.isEmpty ?? true }
        default: // All
            break
        }
        
        // NEW: Filter by summary
        switch summaryFilter {
        case 1: // Has Summary
            results = results.filter { !($0.summaryText?.isEmpty ?? true) }
        case 2: // No Summary
            results = results.filter { $0.summaryText?.isEmpty ?? true }
        default: // All
            break
        }
        
        // Parse exclude words (comma-separated)
        let excludeWords = excludeText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        
        // Search filter
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            
            results = results.filter { video in
                let matchesSearch: Bool
                switch searchMode {
                case .title:
                    matchesSearch = video.title.lowercased().contains(lowercasedSearch)
                    
                case .transcript:
                    guard let transcript = video.transcript else { return false }
                    matchesSearch = transcript.lowercased().contains(lowercasedSearch)
                    
                case .both:
                    let titleMatch = video.title.lowercased().contains(lowercasedSearch)
                    let transcriptMatch = video.transcript?.lowercased().contains(lowercasedSearch) ?? false
                    matchesSearch = titleMatch || transcriptMatch
                }
                
                // If it matches search, now check exclude words
                if matchesSearch && !excludeWords.isEmpty {
                    let titleLower = video.title.lowercased()
                    let transcriptLower = video.transcript?.lowercased() ?? ""
                    
                    // Exclude if ANY exclude word is found in title or transcript
                    let shouldExclude = excludeWords.contains { excludeWord in
                        titleLower.contains(excludeWord) || transcriptLower.contains(excludeWord)
                    }
                    
                    return !shouldExclude
                }
                
                return matchesSearch
            }
        }
        
        // Sort results
        results.sort { video1, video2 in
            switch sortOption {
            case .dateNewest:
                return video1.publishedAt > video2.publishedAt
            case .dateOldest:
                return video1.publishedAt < video2.publishedAt
            case .viewsHighest:
                return video1.stats.viewCount > video2.stats.viewCount
            case .viewsLowest:
                return video1.stats.viewCount < video2.stats.viewCount
            case .titleAZ:
                return video1.title < video2.title
            case .titleZA:
                return video1.title > video2.title
            case .durationLongest:
                return parseDuration(video1.duration) > parseDuration(video2.duration)
            case .durationShortest:
                return parseDuration(video1.duration) < parseDuration(video2.duration)
            }
        }
        
        filteredVideos = results
    }
    
    // MARK: - Channel Functions
    func toggleChannel(_ channelId: String) {
        if selectedChannels.contains(channelId) {
            selectedChannels.remove(channelId)
        } else {
            selectedChannels.insert(channelId)
        }
    }
    
    func selectAllChannels() {
        selectedChannels = Set(availableChannels.map { $0.channelId })
    }
    
    func deselectAllChannels() {
        selectedChannels.removeAll()
    }
    
    // MARK: - Video Update Functions
    func updateVideo(_ updatedVideo: YouTubeVideo) {
        guard let index = allVideos.firstIndex(where: { $0.videoId == updatedVideo.videoId }) else { return }
        var updated = allVideos
        updated[index] = updatedVideo
        allVideos = updated
        filterVideos()
    }
    
    func updateFacts(videoId: String, facts: String) {
        print("🔄 Updating facts for \(videoId)")
        guard let index = allVideos.firstIndex(where: { $0.videoId == videoId }) else {
            print("❌ Video not found in allVideos!")
            return
        }
        var updated = allVideos
        updated[index].factsText = facts
        allVideos = updated
        print("✅ Updated allVideos, now filtering...")
        filterVideos()
        print("✅ Filtered videos count: \(filteredVideos.count)")
    }
    
    func updateSummary(videoId: String, summary: String) {
        guard let index = allVideos.firstIndex(where: { $0.videoId == videoId }) else { return }
        var updated = allVideos
        updated[index].summaryText = summary
        allVideos = updated
        filterVideos()
    }
    
    func updateTranscript(videoId: String, transcript: String) {
        guard let index = allVideos.firstIndex(where: { $0.videoId == videoId }) else { return }
        var updated = allVideos
        updated[index].transcript = transcript
        allVideos = updated
        filterVideos()
    }
    
    // MARK: - Helper Functions
    private func parseDuration(_ duration: String) -> Int {
        var seconds = 0
        let scanner = Scanner(string: duration)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "PTS")
        
        var value: Int = 0
        while !scanner.isAtEnd {
            if scanner.scanInt(&value) {
                if scanner.scanString("H") != nil {
                    seconds += value * 3600
                } else if scanner.scanString("M") != nil {
                    seconds += value * 60
                } else if scanner.scanString("S") != nil {
                    seconds += value
                }
            }
        }
        return seconds
    }
    
    // MARK: - Add New Content
    func addVideo(_ video: YouTubeVideo) {
        // Check if video already exists
        guard !allVideos.contains(where: { $0.videoId == video.videoId }) else {
            print("⚠️ Video already exists in allVideos, skipping add")
            return
        }
        
        allVideos.append(video)
        filterVideos()
        print("✅ Added video to ViewModel: \(video.title)")
    }

    func addChannel(_ channel: YouTubeChannel) {
        // Check if channel already exists
        guard !availableChannels.contains(where: { $0.channelId == channel.channelId }) else {
            print("⚠️ Channel already exists in availableChannels, skipping add")
            return
        }
        
        availableChannels.append(channel)
        print("✅ Added channel to ViewModel: \(channel.name)")
    }
}
