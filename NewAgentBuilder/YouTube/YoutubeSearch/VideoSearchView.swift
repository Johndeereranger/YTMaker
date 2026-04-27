//
//  VideoSearchView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/17/25.
//
//

import SwiftUI
struct VideoSearchView: View {
    @EnvironmentObject var viewModel: VideoSearchViewModel  // ✅ Use environment object
    @State private var showChannelFilter = false
    
    let preSelectedChannelId: String?
    
    init(channelId: String? = nil) {
        self.preSelectedChannelId = channelId
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SearchControlsView(
                viewModel: viewModel,
                showChannelFilter: $showChannelFilter
            )
            
            Divider()
            
            GridResultsView(viewModel: viewModel)
        }
        .navigationTitle(preSelectedChannelId != nil ? "Channel Videos" : "Search Videos")
        .task {
            if !viewModel.hasLoadedInitialData{
                await viewModel.loadData()
            }
            
            // ✅ Auto-select channel if provided
            if let channelId = preSelectedChannelId {
                viewModel.selectedChannels = [channelId]
                viewModel.filterVideos()
            }
        }
        .sheet(isPresented: $showChannelFilter) {
            ChannelFilterSheet(viewModel: viewModel)
        }
    }
}



// MARK: - Search Controls
import SwiftUI

import SwiftUI

import SwiftUI

// MARK: - Search Controls (with Research Topic Filter)
struct SearchControlsView: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @Binding var showChannelFilter: Bool
    @State private var isExpanded = false
    @State private var showTopicFilter = false
    @State private var showBatchAnalysis = false  // Batch analysis sheet
    @StateObject private var batchAnalysisService = BatchVideoAnalysisService()

    // Sentence analysis tracking
    @State private var analyzedVideoIds: Set<String> = []
    @State private var sentenceDataByVideo: [String: SentenceFidelityTest] = [:]
    @State private var isLoadingSentenceStatus = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Always visible: Search bar + Toggle button
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search videos...", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
 
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.blue)
                        .imageScale(.large)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            
            
            // Show active filters count when collapsed
            if !isExpanded {
                HStack {
                    Text(filterSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if hasActiveFilters {
                        Button(action: { withAnimation { isExpanded = true } }) {
                            Text("Edit Filters")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // ALWAYS VISIBLE: Sentence Analysis Actions Row
            sentenceActionsRow
 
            // Collapsible section
            if isExpanded {
                VStack(spacing: 12) {
                    
                    HStack(spacing: 12) {
                        Picker("Load Mode", selection: $viewModel.loadMode) {
                            ForEach([VideoSearchViewModel.LoadMode.pinnedChannels, .all], id: \.self) { mode in
                                HStack(spacing: 4) {
                                    Image(systemName: mode.icon)
                                    Text(mode.title)
                                }
                                .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        // Refresh button
                        Button(action: { Task { await viewModel.loadData() } }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isLoading)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // ✅ NEW: Status message
                    if !viewModel.loadStatusMessage.isEmpty {
                        HStack(spacing: 4) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(viewModel.loadStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    // Exclude words bar
                    HStack {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.red)
                        TextField("Exclude words (comma-separated)", text: $viewModel.excludeText)
                            .textInputAutocapitalization(.never)
         
                        if !viewModel.excludeText.isEmpty {
                            Button(action: { viewModel.excludeText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
         
                    // Search mode picker
                    Picker("Search in", selection: $viewModel.searchMode) {
                        Text("Both").tag(VideoSearchViewModel.SearchMode.both)
                        Text("Title Only").tag(VideoSearchViewModel.SearchMode.title)
                        Text("Transcript Only").tag(VideoSearchViewModel.SearchMode.transcript)
                    }
                    .pickerStyle(.segmented)
         
                    // Sort and filter row
                    HStack {
                        SortMenuButton(viewModel: viewModel)
                        ChannelFilterButton(viewModel: viewModel, showChannelFilter: $showChannelFilter)

                        // Research Topic Filter Button
                        ResearchTopicFilterButton(viewModel: viewModel, showTopicFilter: $showTopicFilter)

                        // Batch Analysis Button
                        let videosWithTranscripts = viewModel.filteredVideos.filter { !($0.transcript?.isEmpty ?? true) }
                        if !videosWithTranscripts.isEmpty {
                            Button(action: { showBatchAnalysis = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "waveform.badge.magnifyingglass")
                                    Text("\(videosWithTranscripts.count)")
                                        .font(.caption)
                                }
                                .font(.subheadline)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                        }

                        if viewModel.filteredVideos.contains(where: { !($0.factsText?.isEmpty ?? true) }) {
                            Button(action: {
                                copyAllFacts(viewModel: viewModel)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }

                        if viewModel.filteredVideos.contains(where: { !($0.summaryText?.isEmpty ?? true) }) {
                            Button(action: {
                                copyAllSummaries(viewModel: viewModel)
                            }) {
                                Image(systemName: "doc.text")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.1))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        Spacer()
                    }
         
                    // Transcript filter (segmented)
                    Picker("Transcripts", selection: $viewModel.transcriptFilter) {
                        Text("All Transcripts").tag(0)
                        Text("Has Transcripts").tag(1)
                        Text("No Transcripts").tag(2)
                    }
                    .pickerStyle(.segmented)
         
                    // Facts filter (segmented)
                    Picker("Facts", selection: $viewModel.factsFilter) {
                        Text("All Facts").tag(0)
                        Text("Has Facts").tag(1)
                        Text("No Facts").tag(2)
                    }
                    .pickerStyle(.segmented)
         
                    // Summary filter (segmented)
                    Picker("Summary", selection: $viewModel.summaryFilter) {
                        Text("All Summary").tag(0)
                        Text("Has Summary").tag(1)
                        Text("No Summary").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .onAppear {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                isExpanded = true
            }
            #elseif os(macOS)
            isExpanded = true
            #endif
        }
        .sheet(isPresented: $showTopicFilter) {
            ResearchTopicFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showBatchAnalysis) {
            BatchVideoAnalysisSheet(
                videos: viewModel.filteredVideos.filter { !($0.transcript?.isEmpty ?? true) },
                service: batchAnalysisService
            )
        }
    }
    
    // MARK: - Sentence Actions Row (Always Visible)

    private var sentenceActionsRow: some View {
        let videosWithTranscripts = viewModel.filteredVideos.filter { !($0.transcript?.isEmpty ?? true) }
        let analyzedCount = viewModel.filteredVideos.filter { analyzedVideoIds.contains($0.videoId) }.count

        return HStack(spacing: 8) {
            // Video count info
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.caption2)
                Text("\(viewModel.filteredVideos.count)")
                    .font(.caption.bold())
            }
            .foregroundColor(.secondary)

            Divider()
                .frame(height: 16)

            // Transcripts count
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .font(.caption2)
                Text("\(videosWithTranscripts.count)")
                    .font(.caption.bold())
            }
            .foregroundColor(videosWithTranscripts.isEmpty ? .secondary : .blue)

            Divider()
                .frame(height: 16)

            // Analyzed count
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.caption2)
                if isLoadingSentenceStatus {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Text("\(analyzedCount)")
                        .font(.caption.bold())
                }
            }
            .foregroundColor(analyzedCount > 0 ? .green : .secondary)

            Spacer()

            // Copy All Sentences Button (if any analyzed)
            if analyzedCount > 0 {
                Button(action: { copyAllSentenceAnalyses() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy \(analyzedCount)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(6)
                }
            }

            // Batch Analyze Button
            if !videosWithTranscripts.isEmpty {
                Button(action: { showBatchAnalysis = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                        Text("Analyze \(videosWithTranscripts.count)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(6)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .task {
            await loadSentenceAnalysisStatus()
        }
    }

    private func loadSentenceAnalysisStatus() async {
        isLoadingSentenceStatus = true

        var analyzed: Set<String> = []
        var dataByVideo: [String: SentenceFidelityTest] = [:]

        for video in viewModel.filteredVideos {
            do {
                let runs = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
                if let latestRun = runs.sorted(by: { $0.createdAt > $1.createdAt }).first {
                    analyzed.insert(video.videoId)
                    dataByVideo[video.videoId] = latestRun
                }
            } catch {
                // Skip errors
            }
        }

        await MainActor.run {
            analyzedVideoIds = analyzed
            sentenceDataByVideo = dataByVideo
            isLoadingSentenceStatus = false
        }
    }

    private func copyAllSentenceAnalyses() {
        var output = """
        ════════════════════════════════════════════════════════════════
        BULK SENTENCE TELEMETRY EXPORT
        ════════════════════════════════════════════════════════════════

        Total Videos: \(sentenceDataByVideo.count)
        Export Date: \(Date().formatted())

        """

        for video in viewModel.filteredVideos {
            guard let test = sentenceDataByVideo[video.videoId] else { continue }

            output += "\n════════════════════════════════════════════════════════════════\n"
            output += "VIDEO: \(video.title)\n"
            output += "════════════════════════════════════════════════════════════════\n"
            output += "Sentences: \(test.totalSentences) | Mode: \(test.taggingMode ?? "?") | Temp: \(String(format: "%.1f", test.temperature ?? 0))\n"
            output += "────────────────────────────────────────────────────────────────\n"

            for sentence in test.sentences {
                output += "\n[\(sentence.sentenceIndex)] \(sentence.text)\n"
                output += "   stance=\(sentence.stance) perspective=\(sentence.perspective)"

                var flags: [String] = []
                if sentence.hasNumber { flags.append("num") }
                if sentence.hasStatistic { flags.append("stat") }
                if sentence.hasQuote { flags.append("quote") }
                if sentence.hasNamedEntity { flags.append("entity") }
                if sentence.hasRevealLanguage { flags.append("reveal") }
                if sentence.hasPromiseLanguage { flags.append("promise") }
                if sentence.hasChallengeLanguage { flags.append("challenge") }
                if sentence.isTransition { flags.append("trans") }
                if sentence.isCallToAction { flags.append("CTA") }

                if !flags.isEmpty {
                    output += " [\(flags.joined(separator: ","))]"
                }
                output += "\n"
            }
        }

        output += "\n════════════════════════════════════════════════════════════════\n"
        output += "END OF EXPORT\n"

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif

        print("✅ Copied sentence analyses for \(sentenceDataByVideo.count) videos")
    }

    // Computed properties for filter summary
    private var hasActiveFilters: Bool {
        !viewModel.excludeText.isEmpty ||
        viewModel.searchMode != .both ||
        viewModel.transcriptFilter != 0 ||
        viewModel.factsFilter != 0 ||
        viewModel.summaryFilter != 0 ||
        !viewModel.selectedChannels.isEmpty ||
        !viewModel.selectedTopics.isEmpty  // ✅ NEW
    }
    
    private var filterSummary: String {
        var filters: [String] = []
        
        if !viewModel.selectedChannels.isEmpty {
            filters.append("\(viewModel.selectedChannels.count) channel(s)")
        }
        if !viewModel.selectedTopics.isEmpty {  // ✅ NEW
            filters.append("\(viewModel.selectedTopics.count) topic(s)")
        }
        if viewModel.transcriptFilter != 0 {
            filters.append(viewModel.transcriptFilter == 1 ? "Has transcripts" : "No transcripts")
        }
        if viewModel.factsFilter != 0 {
            filters.append(viewModel.factsFilter == 1 ? "Has facts" : "No facts")
        }
        if viewModel.summaryFilter != 0 {
            filters.append(viewModel.summaryFilter == 1 ? "Has summary" : "No summary")
        }
//        if viewModel.searchMode != .both {
//            filters.append("Search: \(viewModel.searchMode.rawValue)")
//        }
        
        return filters.isEmpty ? "No filters active" : filters.joined(separator: " • ")
    }
    
    // Helper Functions
    private func copyAllFacts(viewModel: VideoSearchViewModel) {
        let allFacts = viewModel.filteredVideos
            .compactMap { video -> String? in
                guard let facts = video.factsText, !facts.isEmpty else { return nil }
                return "[\(video.title)]\n\(facts)\n"
            }
            .joined(separator: "\n")
        
        #if os(iOS)
        UIPasteboard.general.string = allFacts
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allFacts, forType: .string)
        #endif
        
        print("✅ Copied \(viewModel.filteredVideos.filter { !($0.factsText?.isEmpty ?? true) }.count) facts")
    }
    
    private func copyAllSummaries(viewModel: VideoSearchViewModel) {
        let allSummaries = viewModel.filteredVideos
            .compactMap { video -> String? in
                guard let summary = video.summaryText, !summary.isEmpty else { return nil }
                return "[\(video.title)]\n\(summary)\n"
            }
            .joined(separator: "\n")
        
        #if os(iOS)
        UIPasteboard.general.string = allSummaries
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allSummaries, forType: .string)
        #endif
        
        print("✅ Copied \(viewModel.filteredVideos.filter { !($0.summaryText?.isEmpty ?? true) }.count) summaries")
    }
}

// ✅ NEW: Research Topic Filter Button
struct ResearchTopicFilterButton: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @Binding var showTopicFilter: Bool
    
    var body: some View {
        Button(action: { showTopicFilter.toggle() }) {
            HStack {
                Image(systemName: "folder.circle")
                Text("Topics")
                if !viewModel.selectedTopics.isEmpty {
                    Text("(\(viewModel.selectedTopics.count))")
                        .font(.caption)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(viewModel.selectedTopics.isEmpty ? Color(.systemGray6) : Color.green.opacity(0.2))
            .cornerRadius(8)
        }
    }
}

// ✅ NEW: Research Topic Filter Sheet
struct ResearchTopicFilterSheet: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var topicManager = ResearchTopicManager.shared
    @State private var selectedTopics: Set<String> = []
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Filter videos by research topic")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if topicManager.topics.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("No research topics yet")
                                .font(.headline)
                            Text("Create topics to organize your videos")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                } else {
                    Section("Select Topics") {
                        ForEach(topicManager.topics) { topic in
                            Button(action: { toggleTopic(topic.id) }) {
                                HStack {
                                    Image(systemName: selectedTopics.contains(topic.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedTopics.contains(topic.id) ? .green : .gray)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(topic.title)
                                            .foregroundColor(.primary)
                                        if let description = topic.description {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text("\(topic.videoIds.count) videos")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Filter by Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyFilter()
                    }
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear All") {
                        selectedTopics.removeAll()
                    }
                    .disabled(selectedTopics.isEmpty)
                }
            }
            .task {
                await loadTopics()
                selectedTopics = Set(viewModel.selectedTopics)
            }
        }
    }
    
    private func loadTopics() async {
        do {
            try await topicManager.fetchAllTopics()
        } catch {
            print("❌ Error loading topics: \(error)")
        }
    }
    
    private func toggleTopic(_ topicId: String) {
        if selectedTopics.contains(topicId) {
            selectedTopics.remove(topicId)
        } else {
            selectedTopics.insert(topicId)
        }
    }
    
    private func applyFilter() {
        viewModel.selectedTopics = Array(selectedTopics)
        viewModel.filterVideos()
        dismiss()
    }
}
// MARK: - Search Controls (Collapsible)
struct SearchControlsView2: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @Binding var showChannelFilter: Bool
    @State private var isExpanded = false  // ✅ Toggle for showing/hiding filters
    
    var body: some View {
        VStack(spacing: 12) {
            // Always visible: Search bar + Toggle button
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search videos...", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
 
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                
                // ✅ Toggle button for filters
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.blue)
                        .imageScale(.large)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // ✅ Show active filters count when collapsed
            if !isExpanded {
                HStack {
                    Text(filterSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if hasActiveFilters {
                        Button(action: { withAnimation { isExpanded = true } }) {
                            Text("Edit Filters")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
 
            // ✅ Collapsible section
            if isExpanded {
                VStack(spacing: 12) {
                    // Exclude words bar
                    HStack {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.red)
                        TextField("Exclude words (comma-separated)", text: $viewModel.excludeText)
                            .textInputAutocapitalization(.never)
         
                        if !viewModel.excludeText.isEmpty {
                            Button(action: { viewModel.excludeText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
         
                    // Search mode picker
                    Picker("Search in", selection: $viewModel.searchMode) {
                        Text("Both").tag(VideoSearchViewModel.SearchMode.both)
                        Text("Title Only").tag(VideoSearchViewModel.SearchMode.title)
                        Text("Transcript Only").tag(VideoSearchViewModel.SearchMode.transcript)
                    }
                    .pickerStyle(.segmented)
         
                    // Sort and filter row
                    HStack {
                        SortMenuButton(viewModel: viewModel)
                        ChannelFilterButton(viewModel: viewModel, showChannelFilter: $showChannelFilter)
                        
                        if viewModel.filteredVideos.contains(where: { !($0.factsText?.isEmpty ?? true) }) {
                            Button(action: {
                                copyAllFacts(viewModel: viewModel)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                        
                        // Copy All Summaries
                        if viewModel.filteredVideos.contains(where: { !($0.summaryText?.isEmpty ?? true) }) {
                            Button(action: {
                                copyAllSummaries(viewModel: viewModel)
                            }) {
                                Image(systemName: "doc.text")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.1))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        Spacer()
                    }
         
                    // Transcript filter (segmented)
                    Picker("Transcripts", selection: $viewModel.transcriptFilter) {
                        Text("All Transcripts").tag(0)
                        Text("Has Transcripts").tag(1)
                        Text("No Transcripts").tag(2)
                    }
                    .pickerStyle(.segmented)
         
                    // Facts filter (segmented)
                    Picker("Facts", selection: $viewModel.factsFilter) {
                        Text("All Facts").tag(0)
                        Text("Has Facts").tag(1)
                        Text("No Facts").tag(2)
                    }
                    .pickerStyle(.segmented)
         
                    // Summary filter (segmented)
                    Picker("Summary", selection: $viewModel.summaryFilter) {
                        Text("All Summary").tag(0)
                        Text("Has Summary").tag(1)
                        Text("No Summary").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .onAppear {
            // ✅ Auto-expand on iPad/Mac, collapsed on iPhone
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                isExpanded = true
            }
            #elseif os(macOS)
            isExpanded = true
            #endif
        }
    }
    
    // ✅ Computed properties for filter summary
    private var hasActiveFilters: Bool {
        !viewModel.excludeText.isEmpty ||
        viewModel.searchMode != .both ||
        viewModel.transcriptFilter != 0 ||
        viewModel.factsFilter != 0 ||
        viewModel.summaryFilter != 0 ||
        !viewModel.selectedChannels.isEmpty
    }
    
    private var filterSummary: String {
        var filters: [String] = []
        
        if !viewModel.selectedChannels.isEmpty {
            filters.append("\(viewModel.selectedChannels.count) channel(s)")
        }
        if viewModel.transcriptFilter != 0 {
            filters.append(viewModel.transcriptFilter == 1 ? "Has transcripts" : "No transcripts")
        }
        if viewModel.factsFilter != 0 {
            filters.append(viewModel.factsFilter == 1 ? "Has facts" : "No facts")
        }
        if viewModel.summaryFilter != 0 {
            filters.append(viewModel.summaryFilter == 1 ? "Has summary" : "No summary")
        }
//        if viewModel.searchMode != .both {
//            filters.append("Search: \(viewModel.searchMode.rawValue)")
//        }
        
        return filters.isEmpty ? "No filters active" : filters.joined(separator: " • ")
    }
    
    // MARK: - Helper Functions
    private func copyAllFacts(viewModel: VideoSearchViewModel) {
        let allFacts = viewModel.filteredVideos
            .compactMap { video -> String? in
                guard let facts = video.factsText, !facts.isEmpty else { return nil }
                return "[\(video.title)]\n\(facts)\n"
            }
            .joined(separator: "\n")
        
        #if os(iOS)
        UIPasteboard.general.string = allFacts
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allFacts, forType: .string)
        #endif
        
        print("✅ Copied \(viewModel.filteredVideos.filter { !($0.factsText?.isEmpty ?? true) }.count) facts")
    }
    
    private func copyAllSummaries(viewModel: VideoSearchViewModel) {
        let allSummaries = viewModel.filteredVideos
            .compactMap { video -> String? in
                guard let summary = video.summaryText, !summary.isEmpty else { return nil }
                return "[\(video.title)]\n\(summary)\n"
            }
            .joined(separator: "\n")
        
        #if os(iOS)
        UIPasteboard.general.string = allSummaries
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allSummaries, forType: .string)
        #endif
        
        print("✅ Copied \(viewModel.filteredVideos.filter { !($0.summaryText?.isEmpty ?? true) }.count) summaries")
    }
}

// Keep all your other views as they are (SortMenuButton, ChannelFilterButton, etc.)
// MARK: - Collapsible Search Controls (iPhone-friendly)
struct SearchControlsViewGrok: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @Binding var showChannelFilter: Bool
    @State private var expanded = false   // ← THE MAGIC

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Toggle Bar (always visible)
            HStack {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                Text(expanded ? "Hide Filters" : "Show Filters")
                    .font(.subheadline).bold()
                Spacer()
                Text("\(viewModel.filteredVideos.count) videos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(Color(.systemGroupedBackground))
            .onTapGesture { withAnimation { expanded.toggle() } }

            // MARK: Collapsible Panel
            if expanded {
                innerControls
                    .padding()
                    .background(Color(.systemBackground))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGroupedBackground))
            .shadow(radius: expanded ? 4 : 0))
    }

    // MARK: All your original controls (unchanged)
    private var innerControls: some View {
        VStack(spacing: 12) {
            // Search bar
            searchBar
            excludeBar
            searchModePicker
            actionRow
            transcriptPicker
            factsPicker
            summaryPicker
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Search videos...", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var excludeBar: some View {
        HStack {
            Image(systemName: "minus.circle").foregroundColor(.red)
            TextField("Exclude words (comma-separated)", text: $viewModel.excludeText)
                .textInputAutocapitalization(.never)
            if !viewModel.excludeText.isEmpty {
                Button { viewModel.excludeText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var searchModePicker: some View {
        Picker("Search in", selection: $viewModel.searchMode) {
            Text("Both").tag(VideoSearchViewModel.SearchMode.both)
            Text("Title Only").tag(VideoSearchViewModel.SearchMode.title)
            Text("Transcript Only").tag(VideoSearchViewModel.SearchMode.transcript)
        }
        .pickerStyle(.segmented)
    }

    private var actionRow: some View {
        HStack {
            SortMenuButton(viewModel: viewModel)
            ChannelFilterButton(viewModel: viewModel, showChannelFilter: $showChannelFilter)

//            // Copy All Facts
//            if viewModel.filteredVideos.contains(where: { !($0.factsText?.isEmpty ?? true) }) {
//                Button { copyAllFacts(viewModel: viewModel) } label: {
//                    Image(systemName: "doc.on.doc")
//                }
//                .buttonStyle(.borderedProminent)
//                .buttonBorderShape(.capsule)
//                .controlSize(.small)
//            }
//
//            // Copy All Summaries
//            if viewModel.filteredVideos.contains(where: { !($0.summaryText?.isEmpty ?? true) }) {
//                Button { copyAllSummaries(viewModel: viewModel) } label: {
//                    Image(systemName: "doc.text")
//                }
//                .buttonStyle(.bordered)
//                .tint(.purple)
//                .controlSize(.small)
//            }

            Spacer()
        }
    }

    private var transcriptPicker: some View {
        Picker("Transcripts", selection: $viewModel.transcriptFilter) {
            Text("All").tag(0)
            Text("Has").tag(1)
            Text("None").tag(2)
        }
        .pickerStyle(.segmented)
    }

    private var factsPicker: some View {
        Picker("Facts", selection: $viewModel.factsFilter) {
            Text("All").tag(0)
            Text("Has").tag(1)
            Text("None").tag(2)
        }
        .pickerStyle(.segmented)
    }

    private var summaryPicker: some View {
        Picker("Summary", selection: $viewModel.summaryFilter) {
            Text("All").tag(0)
            Text("Has").tag(1)
            Text("None").tag(2)
        }
        .pickerStyle(.segmented)
    }
}
struct SearchControlsViewOld: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @Binding var showChannelFilter: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search videos...", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            // Exclude words bar
            HStack {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red)
                TextField("Exclude words (comma-separated)", text: $viewModel.excludeText)
                    .textInputAutocapitalization(.never)

                if !viewModel.excludeText.isEmpty {
                    Button(action: { viewModel.excludeText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            // Search mode picker
            Picker("Search in", selection: $viewModel.searchMode) {
                Text("Both").tag(VideoSearchViewModel.SearchMode.both)
                Text("Title Only").tag(VideoSearchViewModel.SearchMode.title)
                Text("Transcript Only").tag(VideoSearchViewModel.SearchMode.transcript)
            }
            .pickerStyle(.segmented)

            // Sort and filter row
            HStack {
                SortMenuButton(viewModel: viewModel)
                ChannelFilterButton(viewModel: viewModel, showChannelFilter: $showChannelFilter)
                
                if viewModel.filteredVideos.contains(where: { !($0.factsText?.isEmpty ?? true) }) {
                            Button(action: {
                                copyAllFacts(viewModel: viewModel)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                        
                        // Copy All Summaries
                        if viewModel.filteredVideos.contains(where: { !($0.summaryText?.isEmpty ?? true) }) {
                            Button(action: {
                                copyAllSummaries(viewModel: viewModel)
                            }) {
                                Image(systemName: "doc.text")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.1))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                Spacer()
            }

            // Transcript filter (segmented)
            Picker("Transcripts", selection: $viewModel.transcriptFilter) {
                Text("All Transcripts").tag(0)
                Text("Has Transcripts").tag(1)
                Text("No Transcripts").tag(2)
            }
            .pickerStyle(.segmented)

            // Facts filter (segmented)
            Picker("Facts", selection: $viewModel.factsFilter) {
                Text("All Facts").tag(0)
                Text("Has Facts").tag(1)
                Text("No Facts").tag(2)
            }
            .pickerStyle(.segmented)

            // Summary filter (segmented)
            Picker("Summary", selection: $viewModel.summaryFilter) {
                Text("All Summary").tag(0)
                Text("Has Summary").tag(1)
                Text("No Summary").tag(2)
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private func copyAllFacts(viewModel: VideoSearchViewModel) {
         let allFacts = viewModel.filteredVideos
             .compactMap { video -> String? in
                 guard let facts = video.factsText, !facts.isEmpty else { return nil }
                 return "[\(video.title)]\n\(facts)\n"
             }
             .joined(separator: "\n")
         
         #if os(iOS)
         UIPasteboard.general.string = allFacts
         #elseif os(macOS)
         NSPasteboard.general.clearContents()
         NSPasteboard.general.setString(allFacts, forType: .string)
         #endif
         
         print("✅ Copied \(viewModel.filteredVideos.filter { !($0.factsText?.isEmpty ?? true) }.count) facts")
     }
     
     private func copyAllSummaries(viewModel: VideoSearchViewModel) {
         let allSummaries = viewModel.filteredVideos
             .compactMap { video -> String? in
                 guard let summary = video.summaryText, !summary.isEmpty else { return nil }
                 return "[\(video.title)]\n\(summary)\n"
             }
             .joined(separator: "\n")
         
         #if os(iOS)
         UIPasteboard.general.string = allSummaries
         #elseif os(macOS)
         NSPasteboard.general.clearContents()
         NSPasteboard.general.setString(allSummaries, forType: .string)
         #endif
         
         print("✅ Copied \(viewModel.filteredVideos.filter { !($0.summaryText?.isEmpty ?? true) }.count) summaries")
     }
    
}


struct SortMenuButton: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    
    var body: some View {
        Menu {
            Picker("Sort By", selection: $viewModel.sortOption) {
                ForEach(VideoSearchViewModel.SortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                Text(viewModel.sortOption.rawValue)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct ChannelFilterButton: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @Binding var showChannelFilter: Bool
    
    var body: some View {
        Button(action: { showChannelFilter.toggle() }) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text("Channels")
                if !viewModel.selectedChannels.isEmpty {
                    Text("(\(viewModel.selectedChannels.count))")
                        .font(.caption)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(viewModel.selectedChannels.isEmpty ? Color(.systemGray6) : Color.blue.opacity(0.2))
            .cornerRadius(8)
        }
    }
}

struct TranscriptFilterButton: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
    }
}

// MARK: - Search Results

struct SearchResultsView: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    
    var body: some View {
        if viewModel.isLoading {
            LoadingView()
        } else if viewModel.filteredVideos.isEmpty && !viewModel.searchText.isEmpty {
            EmptyResultsView()
        } else {
            GridResultsView(viewModel: viewModel)
            //ResultsList(viewModel: viewModel)
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView("Loading videos...")
            Spacer()
        }
    }
}

struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No videos found")
                .font(.headline)
            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
struct GridResultsView: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @EnvironmentObject var nav: NavigationViewModel  // ✅ ADD THIS
    // @State private var selectedVideo: YouTubeVideo? = nil  // ❌ REMOVE THIS
    
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("\(viewModel.filteredVideos.count) videos")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.filteredVideos) { video in
                        Button {
                            nav.push(.youtubeVideoDetail(video))  // ✅ USE CUSTOM NAV
                        } label: {
                            YouTubeVideoCard(
                                video: video,
                                onTranscriptUpdated: {
                                    viewModel.filterVideos()
                                },
                                onTapped: { nav.push(.youtubeVideoDetail(video)) }  // ✅ USE CUSTOM NAV
                            )
                            .environmentObject(viewModel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        // ❌ REMOVE: .navigationDestination(item: $selectedVideo)
    }
}



struct ResultsList: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @State private var copySuccess = false  // ✅ for feedback

    var body: some View {
        List {
            // ✅ Summary Section
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary")
                        .font(.headline)

                    // Stats
                    Text("• Total Videos: \(viewModel.filteredVideos.count)")
                    Text("• With Transcripts: \(viewModel.filteredVideos.filter { !($0.transcript?.isEmpty ?? true) }.count)")
                    Text("• With Facts: \(viewModel.filteredVideos.filter { !($0.factsText?.isEmpty ?? true) }.count)")
                    Text("• With Summaries: \(viewModel.filteredVideos.filter { !($0.summaryText?.isEmpty ?? true) }.count)")

                    // ✅ Copy All Facts Button
                    if viewModel.filteredVideos.contains(where: { !($0.factsText?.isEmpty ?? true) }) {
                        Button(action: copyAllFacts) {
                            Label("Copy All Facts", systemImage: "doc.on.doc.fill")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.blue)
                    }

                    if copySuccess {
                        Text("Copied all facts!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
            }

            // ✅ Video Rows
//            ForEach(viewModel.filteredVideos) { video in
//                EnhancedVideoRowView(video: video) {
//                    viewModel.filterVideos()
//                }
//            }
            // ✅ Video Rows with Navigation
            ForEach(viewModel.filteredVideos) { video in
                NavigationLink(destination: YouTubeVideoDetailView(video: video)) {
                    EnhancedVideoRowView(video: video) {
                        viewModel.filterVideos()
                    }
                }
            }

        }
        .listStyle(.plain)
    }

    // MARK: - Helper
    private func copyAllFacts() {
        let allFacts = viewModel.filteredVideos
            .compactMap { $0.factsText?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n— — — — — — — — — —\n\n")

        UIPasteboard.general.string = allFacts
        withAnimation { copySuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copySuccess = false }
        }
    }
}

// MARK: - Batch Video Analysis Sheet

struct BatchVideoAnalysisSheet: View {
    let videos: [YouTubeVideo]
    @ObservedObject var service: BatchVideoAnalysisService
    @Environment(\.dismiss) var dismiss

    @State private var temperature: Double = 0.3
    @State private var hasStarted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !hasStarted {
                    // Configuration view
                    configurationView
                } else {
                    // Progress view
                    progressView
                }
            }
            .padding()
            .navigationTitle("Batch Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(service.isRunning)
                }
            }
        }
    }

    private var configurationView: some View {
        VStack(spacing: 24) {
            // Summary
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Batch Sentence Analysis")
                    .font(.title2.bold())

                Text("\(videos.count) videos with transcripts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Settings
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.headline)

                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", temperature))
                        .foregroundColor(.secondary)
                }
                Slider(value: $temperature, in: 0...1, step: 0.1)

                Text("Lower = more deterministic, Higher = more creative")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Label("Processing Mode", systemImage: "info.circle")
                    .font(.subheadline.bold())

                Text("Each video will be analyzed using batched tagging:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    VStack {
                        Text("10")
                            .font(.title.bold())
                            .foregroundColor(.purple)
                        Text("concurrent\nbatches")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("×")
                        .foregroundColor(.secondary)

                    VStack {
                        Text("10")
                            .font(.title.bold())
                            .foregroundColor(.purple)
                        Text("sentences\nper batch")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("=")
                        .foregroundColor(.secondary)

                    VStack {
                        Text("100")
                            .font(.title.bold())
                            .foregroundColor(.green)
                        Text("sentences\nat once")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }

            Spacer()

            // Start button
            Button {
                hasStarted = true
                Task {
                    await service.analyzeVideos(videos, temperature: temperature)
                }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Analysis")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    private var progressView: some View {
        VStack(spacing: 24) {
            if service.isRunning {
                // Active progress
                VStack(spacing: 16) {
                    ProgressView(value: Double(service.currentVideoIndex), total: Double(service.totalVideos))
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 2)

                    Text("\(service.currentVideoIndex) / \(service.totalVideos)")
                        .font(.title.bold())

                    Text(service.currentVideoTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(service.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                // Completed
                VStack(spacing: 16) {
                    Image(systemName: service.failedVideos.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(service.failedVideos.isEmpty ? .green : .orange)

                    Text("Analysis Complete")
                        .font(.title2.bold())

                    HStack(spacing: 24) {
                        VStack {
                            Text("\(service.completedVideos.count)")
                                .font(.title.bold())
                                .foregroundColor(.green)
                            Text("Completed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack {
                            Text("\(service.failedVideos.count)")
                                .font(.title.bold())
                                .foregroundColor(service.failedVideos.isEmpty ? .secondary : .red)
                            Text("Failed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Failed videos list
                if !service.failedVideos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Failed Videos")
                            .font(.headline)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(service.failedVideos, id: \.videoId) { failed in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(failed.title)
                                            .font(.caption.bold())
                                        Text(failed.error)
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }

                // Copy report button
                Button {
                    UIPasteboard.general.string = service.generateReport()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Report")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)

                // Done button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

