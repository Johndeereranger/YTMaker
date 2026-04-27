//
//  YouTubeVideoListView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//


import SwiftUI

import SwiftUI

enum VideoSortOrder {
    case newestFirst
    case oldestFirst
    case mostViewed
}

enum VideoFilter {
    case all
    case longs
    case shorts
}

struct YouTubeVideoListView: View {
    let channelId: String
    let channelName: String
    
    @State private var allVideos: [YouTubeVideo] = []
    @State private var displayedVideos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var sortOrder: VideoSortOrder = .newestFirst
    @State private var filter: VideoFilter = .all
    @State private var showFilters = false
    
    // Channel stats
    @State private var totalVideos = 0
    @State private var totalLongs = 0
    @State private var totalShorts = 0
    @State private var hoursOfLongs: Double = 0
    @State private var longViewCount = 0
    @State private var shortViewCount = 0
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading videos...")
            } else if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if displayedVideos.isEmpty {
                Text("No videos found")
                    .foregroundColor(.secondary)
            } else {
                List {
                    // Channel Stats Section
                    Section {
                        VStack(spacing: 8) {
                            HStack {
                                StatPill(icon: "play.rectangle", value: "\(totalVideos)", label: "Total")
                                StatPill(icon: "film", value: "\(totalLongs)", label: "Longs")
                                StatPill(icon: "bolt", value: "\(totalShorts)", label: "Shorts")
                            }
                            
                            HStack {
                                StatPill(icon: "clock", value: String(format: "%.1fh", hoursOfLongs), label: "Hours")
                                StatPill(icon: "eye", value: formatViewCount(longViewCount), label: "Long Views")
                                StatPill(icon: "eye", value: formatViewCount(shortViewCount), label: "Short Views")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Videos Section
                    Section {
                        ForEach(displayedVideos) { video in
                            NavigationLink(destination: YouTubeVideoDetailView(video: video)) {
                                EnhancedVideoRowView(video: video) {
                                    applyFiltersAndSort()
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(channelName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showFilters.toggle() }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(sortOrder: $sortOrder, filter: $filter) {
                applyFiltersAndSort()
            }
        }
        .task {
            await loadVideos()
        }
        .refreshable {
            await loadVideos()
        }
    }
    
    func loadVideos() async {
        isLoading = true
        errorMessage = ""
        
        do {
            let firebaseService = YouTubeFirebaseService()
            allVideos = try await firebaseService.getVideos(forChannel: channelId)
            calculateStats()
            applyFiltersAndSort()
            print("✅ Loaded \(allVideos.count) videos")
        } catch {
            errorMessage = "Failed to load videos: \(error.localizedDescription)"
            print("❌ Error loading videos: \(error)")
        }
        
        isLoading = false
    }
    
    func calculateStats() {
        totalVideos = allVideos.count
        
        let longs = allVideos.filter { !isShort($0) }
        let shorts = allVideos.filter { isShort($0) }
        
        totalLongs = longs.count
        totalShorts = shorts.count
        
        hoursOfLongs = longs.reduce(0.0) { total, video in
            total + (parseDuration(video.duration) / 3600.0)
        }
        
        longViewCount = longs.reduce(0) { $0 + $1.stats.viewCount }
        shortViewCount = shorts.reduce(0) { $0 + $1.stats.viewCount }
    }
    
    func applyFiltersAndSort() {
        // Apply filter
        var filtered = allVideos
        switch filter {
        case .all:
            break
        case .longs:
            filtered = allVideos.filter { !isShort($0) }
        case .shorts:
            filtered = allVideos.filter { isShort($0) }
        }
        
        // Apply sort
        switch sortOrder {
        case .newestFirst:
            filtered.sort { $0.publishedAt > $1.publishedAt }
        case .oldestFirst:
            filtered.sort { $0.publishedAt < $1.publishedAt }
        case .mostViewed:
            filtered.sort { $0.stats.viewCount > $1.stats.viewCount }
        }
        
        displayedVideos = filtered
    }
    
    func isShort(_ video: YouTubeVideo) -> Bool {
        return parseDuration(video.duration) < 60
    }
    
    func parseDuration(_ duration: String) -> Double {
        // Parse ISO 8601 duration (PT10M30S) to seconds
        var result: Double = 0
        var current = ""
        
        for char in duration {
            if char.isNumber {
                current += String(char)
            } else if char == "H" {
                result += Double(current) ?? 0 * 3600
                current = ""
            } else if char == "M" {
                result += (Double(current) ?? 0) * 60
                current = ""
            } else if char == "S" {
                result += Double(current) ?? 0
                current = ""
            }
        }
        
        return result
    }
    
    func formatViewCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Stat Pill
struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}


// MARK: - Filter Sheet
struct FilterSheet: View {
    @Binding var sortOrder: VideoSortOrder
    @Binding var filter: VideoFilter
    let onApply: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Sort Order") {
                    Button(action: { sortOrder = .newestFirst }) {
                        HStack {
                            Text("Newest First")
                            Spacer()
                            if sortOrder == .newestFirst {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: { sortOrder = .oldestFirst }) {
                        HStack {
                            Text("Oldest First")
                            Spacer()
                            if sortOrder == .oldestFirst {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: { sortOrder = .mostViewed }) {
                        HStack {
                            Text("Most Viewed")
                            Spacer()
                            if sortOrder == .mostViewed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Section("Filter") {
                    Button(action: { filter = .all }) {
                        HStack {
                            Text("All Videos")
                            Spacer()
                            if filter == .all {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: { filter = .longs }) {
                        HStack {
                            Text("Longs Only (>60s)")
                            Spacer()
                            if filter == .longs {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: { filter = .shorts }) {
                        HStack {
                            Text("Shorts Only (<60s)")
                            Spacer()
                            if filter == .shorts {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sort & Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }
}
