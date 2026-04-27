//
//  DebugDataView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/17/25.
//


import SwiftUI
import FirebaseFirestore

struct DebugDataView: View {
    @State private var channels: [YouTubeChannel] = []
    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = false
    @State private var debugInfo = ""
    
    var body: some View {
        List {
            Section("Debug Info") {
                Text(debugInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Channels (\(channels.count))") {
                ForEach(channels) { channel in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name)
                            .font(.headline)
                        Text("Channel ID: \(channel.channelId)")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        let videosForChannel = videos.filter { $0.channelId == channel.channelId }
                        Text("Videos in DB: \(videosForChannel.count)")
                            .font(.caption)
                            .foregroundColor(videosForChannel.isEmpty ? .red : .green)
                        
                        if !videosForChannel.isEmpty {
                            ForEach(videosForChannel) { video in
                                Text("  • \(video.title)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section("All Videos (\(videos.count))") {
                ForEach(videos) { video in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .font(.subheadline)
                        Text("Video ID: \(video.videoId)")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Channel ID: \(video.channelId)")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        let matchingChannel = channels.first { $0.channelId == video.channelId }
                        if let channel = matchingChannel {
                            Text("✅ Channel found: \(channel.name)")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("❌ Channel NOT found!")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Debug Data")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    Task { await loadData() }
                }
            }
        }
        .task {
            await loadData()
        }
    }
    
    func loadData() async {
        isLoading = true
        debugInfo = "Loading..."
        
        do {
            let db = Firestore.firestore()
            
            // Fetch channels
            let channelsSnapshot = try await db.collection("channels").getDocuments()
            channels = try channelsSnapshot.documents.compactMap { doc in
                try doc.data(as: YouTubeChannel.self)
            }
            
            // Fetch videos
            let videosSnapshot = try await db.collection("videos").getDocuments()
            videos = try videosSnapshot.documents.compactMap { doc in
                try doc.data(as: YouTubeVideo.self)
            }
            
            // Build debug info
            var info = "Channels: \(channels.count)\n"
            info += "Videos: \(videos.count)\n\n"
            
            for channel in channels {
                let videosForChannel = videos.filter { $0.channelId == channel.channelId }
                info += "[\(channel.name)]\n"
                info += "  ID: \(channel.channelId)\n"
                info += "  Videos: \(videosForChannel.count)\n\n"
            }
            
            // Check for orphaned videos
            let orphanedVideos = videos.filter { video in
                !channels.contains { $0.channelId == video.channelId }
            }
            if !orphanedVideos.isEmpty {
                info += "⚠️ ORPHANED VIDEOS: \(orphanedVideos.count)\n"
                for video in orphanedVideos {
                    info += "  • \(video.title) (channelId: \(video.channelId))\n"
                }
            }
            
            debugInfo = info
            
        } catch {
            debugInfo = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

#Preview {
    DebugDataView()
}

import SwiftUI

// Test 1: Absolutely minimal view
struct MinimalTest1: View {
    var body: some View {
        Text("Test 1: Basic View")
            .onAppear {
                print("✅ MinimalTest1 appeared")
            }
            .onDisappear {
                print("❌ MinimalTest1 disappeared")
            }
    }
}

// Test 2: With ViewModel but no Firebase
class TestViewModel: ObservableObject {
    @Published var message = "Hello"
    
    init() {
        print("✅ TestViewModel initialized")
    }
    
    deinit {
        print("❌ TestViewModel deinitialized")
    }
}

struct MinimalTest2: View {
    @StateObject private var viewModel = TestViewModel()
    
    var body: some View {
        Text(viewModel.message)
            .onAppear {
                print("✅ MinimalTest2 appeared")
            }
            .onDisappear {
                print("❌ MinimalTest2 disappeared")
            }
    }
}

// Test 3: With async task (no Firebase)
struct MinimalTest3: View {
    @State private var data = "Loading..."
    
    var body: some View {
        Text(data)
            .onAppear {
                print("✅ MinimalTest3 appeared")
            }
            .onDisappear {
                print("❌ MinimalTest3 disappeared")
            }
            .task {
                print("✅ MinimalTest3 task started")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                data = "Loaded!"
                print("✅ MinimalTest3 task completed")
            }
    }
}

// Test 4: Actual VideoSearchView but simplified
struct MinimalTest4: View {
    @StateObject private var viewModel = TestViewModel()
    
    var body: some View {
        Text(viewModel.message)
            .onAppear {
                print("✅ MinimalTest2 appeared")
            }
            .onDisappear {
                print("❌ MinimalTest2 disappeared")
            }
    }
}

// Test 5: With Firebase call
struct MinimalTest5: View {
    @State private var status = "Not loaded"
    
    var body: some View {
        Text(status)
            .onAppear {
                print("✅ MinimalTest5 appeared")
            }
            .onDisappear {
                print("❌ MinimalTest5 disappeared")
            }
            .task {
                print("✅ MinimalTest5 task started")
                do {
                    let videos = try await YouTubeFirebaseService.shared.fetchAllVideos()
                    status = "Loaded \(videos.count) videos"
                    print("✅ MinimalTest5 loaded successfully")
                } catch {
                    status = "Error: \(error.localizedDescription)"
                    print("❌ MinimalTest5 error: \(error)")
                }
            }
    }
}
