//
//  VideoSearchRow.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/17/25.
//


import SwiftUI

// MARK: - Video Row

struct VideoSearchRow: View {
    let video: YouTubeVideo
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VideoThumbnail(video: video)
            VideoInfo(video: video)
        }
        .padding(.vertical, 4)
    }
}

struct VideoThumbnail: View {
    let video: YouTubeVideo
    
    var body: some View {
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
        .overlay(
            DurationBadge(duration: video.duration),
            alignment: .bottomTrailing
        )
    }
}

struct DurationBadge: View {
    let duration: String
    
    var body: some View {
        Text(formatDuration(duration))
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(4)
            .padding(4)
    }
    
    private func formatDuration(_ duration: String) -> String {
        var hours = 0
        var minutes = 0
        var secs = 0
        var value: Int = 0
        
        let scanner = Scanner(string: duration)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "PTS")
        
        while !scanner.isAtEnd {
            if scanner.scanInt(&value) {
                if scanner.scanString("H") != nil {
                    hours = value
                } else if scanner.scanString("M") != nil {
                    minutes = value
                } else if scanner.scanString("S") != nil {
                    secs = value
                }
            }
        }
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

struct VideoInfo: View {
    let video: YouTubeVideo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            
            VideoMetadata(video: video)
            
            Text(video.publishedAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct VideoMetadata: View {
    let video: YouTubeVideo
    
    var body: some View {
        HStack(spacing: 8) {
            Label(formatNumber(video.stats.viewCount), systemImage: "eye")
            
            if video.transcript != nil && !(video.transcript?.isEmpty ?? true) {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.green)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Channel Filter Sheet

struct ChannelFilterSheet: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                SelectAllSection(viewModel: viewModel)
                ChannelsSection(viewModel: viewModel)
            }
            .navigationTitle("Filter by Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SelectAllSection: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    
    var body: some View {
        Section {
            Button(action: {
                if viewModel.selectedChannels.count == viewModel.availableChannels.count {
                    viewModel.deselectAllChannels()
                } else {
                    viewModel.selectAllChannels()
                }
            }) {
                HStack {
                    Text(viewModel.selectedChannels.count == viewModel.availableChannels.count ? "Deselect All" : "Select All")
                    Spacer()
                    Text("\(viewModel.selectedChannels.count)/\(viewModel.availableChannels.count)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

//struct ChannelsSection: View {
//    @ObservedObject var viewModel: VideoSearchViewModel
//    
//    var body: some View {
//        Section("Channels") {
//            ForEach(viewModel.availableChannels) { channel in
//                ChannelRow(
//                    channel: channel,
//                    isSelected: viewModel.selectedChannels.contains(channel.channelId),
//                    onTap: { viewModel.toggleChannel(channel.channelId) }
//                )
//            }
//        }
//    }
//}

struct ChannelsSection: View {
    @ObservedObject var viewModel: VideoSearchViewModel
    
    var sortedChannels: [YouTubeChannel] {
        viewModel.availableChannels.sorted { channel1, channel2 in
            // Pinned channels always come first
            if channel1.isPinned != channel2.isPinned {
                return channel1.isPinned
            }
            
            // Then sort alphabetically by name
            return channel1.name.localizedCaseInsensitiveCompare(channel2.name) == .orderedAscending
        }
    }
    
    var body: some View {
        Section("Channels") {
            ForEach(sortedChannels) { channel in
                ChannelRow(
                    channel: channel,
                    isSelected: viewModel.selectedChannels.contains(channel.channelId),
                    onTap: { viewModel.toggleChannel(channel.channelId) }
                )
            }
        }
    }
}

struct ChannelRow: View {
    let channel: YouTubeChannel
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
                    image.resizable()
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
                .cornerRadius(20)
                
                VStack(alignment: .leading) {
                    Text(channel.name)
                        .foregroundColor(.primary)
                    Text("\(channel.videoCount) videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
