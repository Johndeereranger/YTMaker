//
//  YouTubeChannelListView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//


import SwiftUI
//
//struct YouTubeChannelListView: View {
//    @State private var channels: [YouTubeChannel] = []
//    @State private var isLoading = true
//    @State private var errorMessage = ""
//    
//    var body: some View {
//        Group {
//            if isLoading {
//                ProgressView("Loading channels...")
//            } else if !errorMessage.isEmpty {
//                VStack(spacing: 16) {
//                    Text(errorMessage)
//                        .foregroundColor(.red)
//                        .padding()
//                    
//                    Button("Retry") {
//                        Task { await loadChannels() }
//                    }
//                }
//            } else if channels.isEmpty {
//                VStack(spacing: 16) {
//                    Image(systemName: "video.slash")
//                        .font(.system(size: 60))
//                        .foregroundColor(.gray)
//                    Text("No channels imported yet")
//                        .foregroundColor(.secondary)
//                }
//            } else {
//                List(channels) { channel in
//                    NavigationLink(destination: VideoSearchView(channelId: channel.channelId)) {
//                        ChannelRowView(channel: channel)
//                    }
//                }
////                List(channels) { channel in
////                    NavigationLink(destination: YouTubeVideoListView(
////                        channelId: channel.channelId,
////                        channelName: channel.name
////                    )) {
////                        ChannelRowView(channel: channel)
////                    }
////                }
//            }
//        }
//        .navigationTitle("YouTube Channels")
//        .task {
//            await loadChannels()
//        }
//        .refreshable {
//            await loadChannels()
//        }
//    }
//    
//    func loadChannels() async {
//        isLoading = true
//        errorMessage = ""
//        
//        do {
//            let firebaseService = YouTubeFirebaseService()
//            channels = try await firebaseService.getAllChannels()
//            print("✅ Loaded \(channels.count) channels")
//        } catch {
//            errorMessage = "Failed to load channels: \(error.localizedDescription)"
//            print("❌ Error loading channels: \(error)")
//        }
//        
//        isLoading = false
//    }
//}
//
//struct ChannelRowView: View {
//    let channel: YouTubeChannel
//    
//    var body: some View {
//        HStack(spacing: 12) {
//            // Channel thumbnail
//            AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
//                image
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//            } placeholder: {
//                Circle()
//                    .fill(Color.gray.opacity(0.3))
//            }
//            .frame(width: 60, height: 60)
//            .clipShape(Circle())
//            
//            // Channel info
//            VStack(alignment: .leading, spacing: 4) {
//                Text(channel.name)
//                    .font(.headline)
//                
//                HStack(spacing: 12) {
//                    Label("\(channel.videoCount)", systemImage: "play.rectangle")
//                        .font(.caption)
//                    
//                    if let subscribers = channel.metadata?.subscriberCount {
//                        Label("\(subscribers.formatted())", systemImage: "person.2")
//                            .font(.caption)
//                    }
//                }
//                .foregroundColor(.secondary)
//                
//                Text("Last synced: \(channel.lastSynced.formatted(date: .abbreviated, time: .shortened))")
//                    .font(.caption2)
//                    .foregroundColor(.secondary)
//            }
//        }
//        .padding(.vertical, 4)
//    }
//}
//



import SwiftUI

enum ChannelFilter: String, CaseIterable {
    case all = "All"
    case hunting = "Hunting"
    case notHunting = "Not Hunting"
}

enum ChannelSort: String, CaseIterable {
    case alphabetical = "Alphabetical"
    case lastSynced = "Last Synced"
    case videoCount = "Video Count"
}

struct YouTubeChannelListView: View {
    @State private var channels: [YouTubeChannel] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var selectedFilter: ChannelFilter = .all
    @State private var selectedSort: ChannelSort = .alphabetical
    @EnvironmentObject var nav: NavigationViewModel
    @EnvironmentObject var viewModel: VideoSearchViewModel
    
    var importedCounts: [String: Int] {
        Dictionary(grouping: viewModel.allVideos, by: { $0.channelId })
            .mapValues { $0.count }
    }
    
    var filteredAndSortedChannels: [YouTubeChannel] {
        var filtered = channels
        
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
            // Pinned channels always come first
            if channel1.isPinned != channel2.isPinned {
                return channel1.isPinned
            }
            
            // Then sort by selected method
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
                    ProgressView("Loading channels...")
                } else if !errorMessage.isEmpty {
                    VStack(spacing: 16) {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                        
                        Button("Retry") {
                            Task { await loadChannels() }
                        }
                    }
                } else if filteredAndSortedChannels.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        if channels.isEmpty {
                            Text("No channels imported yet")
                                .foregroundColor(.secondary)
                        } else {
                            Text("No channels match filter")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    List {
//                        ForEach(filteredAndSortedChannels) { channel in
//                            NavigationLink(destination: VideoSearchView(channelId: channel.channelId)) {
//                                ChannelRowView(
//                                    channel: channel,
//                                    onTogglePin: {
//                                        Task { await togglePin(channel: channel) }
//                                    }
//                                )
//                            }
//                        }
                        ForEach(filteredAndSortedChannels) { channel in
                            Button {
                                nav.push(.youtubeChannelVideos(channel.channelId))  // ✅ Pass channelId
                            } label: {
                                ChannelRowView(
                                    channel: channel, importedCount: importedCounts[channel.channelId] ?? 0,
                                    
                                    onTogglePin: {
                                        Task { await togglePin(channel: channel) }
                                    },
                                    onRefresh: { completion in
                                        Task {
                                            await refreshChannel(channel: channel)
                                            completion()
                                        }
                                    },
                                    onUpdateStats: { completion in
                                        Task {
                                            await updateChannelStats(channel: channel)
                                            completion()
                                        }
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
        .navigationTitle("YouTube Channels")
        .task {
            await loadChannels()
        }
        .refreshable {
            await loadChannels()
        }
    }
    
    func loadChannels() async {
        isLoading = true
        errorMessage = ""
        
        do {
            let firebaseService = YouTubeFirebaseService()
            channels = try await firebaseService.getAllChannels()
            print("✅ Loaded \(channels.count) channels")
        } catch {
            errorMessage = "Failed to load channels: \(error.localizedDescription)"
            print("❌ Error loading channels: \(error)")
        }
        
        isLoading = false
    }
    
    func togglePin(channel: YouTubeChannel) async {
        // Update local state immediately for responsive UI
        if let index = channels.firstIndex(where: { $0.channelId == channel.channelId }) {
            channels[index].isPinned.toggle()
            
            // Update Firebase
            do {
                let firebaseService = YouTubeFirebaseService()
                try await firebaseService.updateChannelPinStatus(
                    channelId: channel.channelId,
                    isPinned: channels[index].isPinned
                )
                print("✅ Updated pin status for \(channel.name)")
            } catch {
                // Revert on error
                channels[index].isPinned.toggle()
                print("❌ Failed to update pin status: \(error)")
            }
        }
    }
    // Add this new method to YouTubeChannelListView:
    func updateChannelStats(channel: YouTubeChannel) async {
        do {
            let firebaseService = YouTubeFirebaseService()
            let (updated, new) = try await firebaseService.updateChannelVideos(
                channelId: channel.channelId
            )
            
            print("✅ Updated \(updated.count) videos, found \(new.count) new videos")
            
            // Fetch fresh channel from Firebase (has updated lastSynced)
            if let freshChannel = try await firebaseService.getChannel(channelId: channel.channelId) {
                if let index = channels.firstIndex(where: { $0.channelId == channel.channelId }) {
                    channels[index] = freshChannel
                }
            }
            
        } catch {
            print("❌ Failed to update channel stats: \(error)")
            errorMessage = "Failed to update stats: \(error.localizedDescription)"
        }
    }
    func refreshChannel(channel: YouTubeChannel) async {
        do {
            let firebaseService = YouTubeFirebaseService()
            let updatedChannel = try await firebaseService.refreshChannel(
                channelId: channel.channelId
            )
            
            // Update local array
            if let index = channels.firstIndex(where: { $0.channelId == channel.channelId }) {
                channels[index] = updatedChannel
            }
            
            print("✅ Refreshed \(updatedChannel.name)")
        } catch {
            print("❌ Failed to refresh channel: \(error)")
            errorMessage = "Failed to refresh: \(error.localizedDescription)"
        }
    }
}
//
//struct ChannelRowView: View {
//    let channel: YouTubeChannel
//    let onTogglePin: () -> Void
//    
//    var body: some View {
//        HStack(spacing: 12) {
//            // Pin flag button
//            Button(action: onTogglePin) {
//                Image(systemName: channel.isPinned ? "flag.fill" : "flag")
//                    .foregroundColor(channel.isPinned ? .orange : .gray)
//                    .font(.system(size: 20))
//            }
//            .buttonStyle(.plain)
//            
//            // Channel thumbnail
//            AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
//                image
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//            } placeholder: {
//                Circle()
//                    .fill(Color.gray.opacity(0.3))
//            }
//            .frame(width: 60, height: 60)
//            .clipShape(Circle())
//            
//            // Channel info
//            VStack(alignment: .leading, spacing: 4) {
//                HStack {
//                    Text(channel.name)
//                        .font(.headline)
//                    
//                    // Hunting badge
//                    if !channel.notHunting {
//                        Image(systemName: "scope")
//                            .font(.caption2)
//                            .foregroundColor(.green)
//                    }
//                }
//                
//                HStack(spacing: 12) {
//                    Label("\(channel.videoCount)", systemImage: "play.rectangle")
//                        .font(.caption)
//                    
//                    if let subscribers = channel.metadata?.subscriberCount {
//                        Label("\(subscribers.formatted())", systemImage: "person.2")
//                            .font(.caption)
//                    }
//                }
//                .foregroundColor(.secondary)
//                
//                Text("Last synced: \(channel.lastSynced.formatted(date: .abbreviated, time: .shortened))")
//                    .font(.caption2)
//                    .foregroundColor(.secondary)
//            }
//            
//            Spacer()
//        }
//        .padding(.vertical, 4)
//    }
//}
////
////// Placeholder for VideoSearchView
////struct VideoSearchView: View {
////    let channelId: String
////    
////    var body: some View {
////        Text("Video Search for channel: \(channelId)")
////            .navigationTitle("Videos")
////    }
////}
////
////#Preview {
////    NavigationView {
////        YouTubeChannelListView()
////    }
////}
// UPDATE YOUR ChannelRowView to add stats update button
// UPDATE YOUR ChannelRowView to add stats update button

struct ChannelRowViewOld: View {
    let channel: YouTubeChannel
    let onTogglePin: () -> Void
    let onRefresh: (@escaping () -> Void) -> Void  // ✅ NOW takes completion
      let onUpdateStats: (@escaping () -> Void) -> Void
    
    @State private var isRefreshing = false
    @State private var isUpdatingStats = false  // ✅ NEW
    
    var body: some View {
        HStack(spacing: 12) {
            // Pin flag button
            Button(action: onTogglePin) {
                Image(systemName: channel.isPinned ? "flag.fill" : "flag")
                    .foregroundColor(channel.isPinned ? .orange : .gray)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            
            // Channel thumbnail
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
            
            // Channel info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name)
                        .font(.headline)
                    
                    // Hunting badge
                    if !channel.notHunting {
                        Image(systemName: "scope")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                
                HStack(spacing: 12) {
                    Label("\(channel.videoCount)", systemImage: "play.rectangle")
                        .font(.caption)
                    
                    if let subscribers = channel.metadata?.subscriberCount {
                        Label("\(subscribers.formatted())", systemImage: "person.2")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
                
                Text("Last synced: \(channel.lastSynced.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // ✅ NEW: Update Stats button
            Button(action: {
                isUpdatingStats = true
                onUpdateStats {  // ✅ Pass completion closure
                    isUpdatingStats = false
                }
            }) {
                if isUpdatingStats {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.green)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingStats)
            
            // Refresh metadata button
            Button(action: {
                isRefreshing = true
                onRefresh {  // ✅ Pass completion closure
                    isRefreshing = false
                }
            }) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.vertical, 4)
    }
}


struct ChannelRowView: View {
    let channel: YouTubeChannel
    let importedCount: Int  // ✅ NEW parameter
    let onTogglePin: () -> Void
    let onRefresh: (@escaping () -> Void) -> Void
    let onUpdateStats: (@escaping () -> Void) -> Void
    
    @State private var isRefreshing = false
    @State private var isUpdatingStats = false
    
    // Calculate import percentage
    var importPercentage: Double {
        guard channel.videoCount > 0 else { return 0 }
        return Double(importedCount) / Double(channel.videoCount)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Pin flag button
            Button(action: onTogglePin) {
                Image(systemName: channel.isPinned ? "flag.fill" : "flag")
                    .foregroundColor(channel.isPinned ? .orange : .gray)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            
            // Channel thumbnail
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
            
            // Channel info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name)
                        .font(.headline)
                    
                    // Hunting badge
                    if !channel.notHunting {
                        Image(systemName: "scope")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                
                // Video counts with progress
                HStack(spacing: 8) {
                    // Imported / Total count
                    HStack(spacing: 4) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.caption2)
                        Text("\(importedCount)")
                            .fontWeight(.semibold)
                        Text("/")
                        Text("\(channel.videoCount)")
                    }
                    .font(.caption)
                    .foregroundColor(importPercentage >= 1.0 ? .green : .primary)
                    
//                    // Progress bar
//                    GeometryReader { geometry in
//                        ZStack(alignment: .leading) {
//                            // Background
//                            RoundedRectangle(cornerRadius: 2)
//                                .fill(Color.gray.opacity(0.2))
//                                .frame(height: 4)
//                            
//                            // Progress
//                            RoundedRectangle(cornerRadius: 2)
//                                .fill(importPercentage >= 1.0 ? Color.green : Color.blue)
//                                .frame(width: geometry.size.width * importPercentage, height: 4)
//                        }
//                    }
//                    .frame(width: 40, height: 4)
                    
//                    // Percentage
//                    Text("\(Int(importPercentage * 100))%")
//                        .font(.caption2)
//                        .foregroundColor(.secondary)
                    
//                    if let subscribers = channel.metadata?.subscriberCount {
//                        Label("\(subscribers.formatted())", systemImage: "person.2")
//                            .font(.caption)
//                    }
                    
                    if let formattedSubs = channel.formattedSubscriberCount {
                        Label(formattedSubs, systemImage: "person.2")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
                
                Text("Last synced: \(channel.lastSynced.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Update Stats button
            Button(action: {
                isUpdatingStats = true
                onUpdateStats {
                    isUpdatingStats = false
                }
            }) {
                if isUpdatingStats {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.green)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingStats)
            
            // Refresh metadata button
            Button(action: {
                isRefreshing = true
                onRefresh {
                    isRefreshing = false
                }
            }) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.vertical, 4)
    }
}
