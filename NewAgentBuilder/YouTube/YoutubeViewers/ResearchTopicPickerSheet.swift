//
//  ResearchTopicPickerSheet.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/3/25.
//


import SwiftUI

//struct ResearchTopicPickerSheet: View {
//    let video: YouTubeVideo
//    @ObservedObject var manager: ResearchTopicManager
//    @Environment(\.dismiss) var dismiss
//    
//    @State private var selectedTopicIds: Set<String> = []
//    @State private var isSaving = false
//    
//    var body: some View {
//        NavigationView {
//            VStack {
//                if manager.topics.isEmpty {
//                    emptyStateView
//                } else {
//                    topicList
//                }
//            }
//            .navigationTitle("Assign to Topics")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") { dismiss() }
//                }
//                
//                ToolbarItem(placement: .confirmationAction) {
//                    Button("Save") {
//                        saveChanges()
//                    }
//                    .disabled(isSaving)
//                }
//            }
//            .onAppear {
//                loadCurrentAssignments()
//            }
//        }
//    }
//    
//    private var emptyStateView: some View {
//        VStack(spacing: 16) {
//            Image(systemName: "folder.badge.questionmark")
//                .font(.system(size: 60))
//                .foregroundColor(.gray)
//            
//            Text("No Research Topics")
//                .font(.headline)
//            
//            Text("Create research topics first to assign videos")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//                .multilineTextAlignment(.center)
//        }
//        .padding()
//    }
//    
//    private var topicList: some View {
//        List {
//            Section {
//                Text("Select the research topics this video belongs to")
//                    .font(.subheadline)
//                    .foregroundColor(.secondary)
//            }
//            
//            Section {
//                ForEach(manager.topics) { topic in
//                    TopicRowCheckbox(
//                        topic: topic,
//                        isSelected: selectedTopicIds.contains(topic.id),
//                        onToggle: { toggleTopic(topic.id) }
//                    )
//                }
//            }
//        }
//    }
//    
//    private func loadCurrentAssignments() {
//        selectedTopicIds = Set(
//            manager.topics
//                .filter { $0.videoIds.contains(video.videoId) }
//                .map { $0.id }
//        )
//    }
//    
//    private func toggleTopic(_ topicId: String) {
//        if selectedTopicIds.contains(topicId) {
//            selectedTopicIds.remove(topicId)
//        } else {
//            selectedTopicIds.insert(topicId)
//        }
//    }
//    
//    private func saveChanges() {
//        isSaving = true
//        
//        Task {
//            // Get currently assigned topics
//            let currentTopics = Set(
//                manager.topics
//                    .filter { $0.videoIds.contains(video.videoId) }
//                    .map { $0.id }
//            )
//            
//            // Topics to add (in selectedTopicIds but not in currentTopics)
//            let topicsToAdd = selectedTopicIds.subtracting(currentTopics)
//            
//            // Topics to remove (in currentTopics but not in selectedTopicIds)
//            let topicsToRemove = currentTopics.subtracting(selectedTopicIds)
//            
//            // Add video to new topics
//            for topicId in topicsToAdd {
//                do {
//                    try await manager.addVideoToTopic(topicId: topicId, videoId: video.videoId)
//                    print("✅ Added video to topic: \(topicId)")
//                } catch {
//                    print("❌ Error adding video to topic: \(error)")
//                }
//            }
//            
//            // Remove video from deselected topics
//            for topicId in topicsToRemove {
//                do {
//                    try await manager.removeVideoFromTopic(topicId: topicId, videoId: video.videoId)
//                    print("✅ Removed video from topic: \(topicId)")
//                } catch {
//                    print("❌ Error removing video from topic: \(error)")
//                }
//            }
//            
//            isSaving = false
//            dismiss()
//        }
//    }
//}
//
//struct TopicRowCheckbox: View {
//    let topic: ResearchTopic
//    let isSelected: Bool
//    let onToggle: () -> Void
//    
//    var body: some View {
//        Button(action: onToggle) {
//            HStack {
//                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
//                    .foregroundColor(isSelected ? .blue : .gray)
//                    .imageScale(.large)
//                
//                VStack(alignment: .leading, spacing: 4) {
//                    Text(topic.title)
//                        .font(.body)
//                        .foregroundColor(.primary)
//                    
//                    if let description = topic.description {
//                        Text(description)
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                            .lineLimit(2)
//                    }
//                    
//                    Text("\(topic.videoIds.count) videos")
//                        .font(.caption2)
//                        .foregroundColor(.secondary)
//                }
//                
//                Spacer()
//            }
//            .contentShape(Rectangle())
//        }
//        .buttonStyle(.plain)
//    }
//}


struct ResearchTopicPickerSheet: View {
    let video: YouTubeVideo
    @StateObject private var manager = ResearchTopicManager.shared  // ✅ Use shared instance
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTopicIds: Set<String> = []
    @State private var isSaving = false
    @State private var selectedCategoryFilter: String = "All"  // ✅ Filter state
    @State private var showFilterMenu = false
    
    // ✅ Filtered topics based on category
    var filteredTopics: [ResearchTopic] {
        if selectedCategoryFilter == "All" {
            return manager.topics
        } else {
            return manager.topics.filter { $0.category == selectedCategoryFilter }
        }
    }
    
    // ✅ Get unique categories from topics
    var availableCategories: [String] {
        var categories = Set(manager.topics.map { $0.category })
        return ["All"] + categories.sorted()
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if manager.topics.isEmpty {
                    emptyStateView
                } else {
                    topicList
                }
            }
            .navigationTitle("Assign to Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .principal) {
                    // ✅ Filter button
                    Menu {
                        ForEach(availableCategories, id: \.self) { category in
                            Button(action: { selectedCategoryFilter = category }) {
                                HStack {
                                    Text(category)
                                    if selectedCategoryFilter == category {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedCategoryFilter)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .imageScale(.small)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                loadCurrentAssignments()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Research Topics")
                .font(.headline)
            
            Text("Create research topics first to assign videos")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var topicList: some View {
        List {
            Section {
                HStack {
                    Text("Select the research topics this video belongs to")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // ✅ Show count
                    Text("\(filteredTopics.count) of \(manager.topics.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                if filteredTopics.isEmpty {
                    Text("No topics in this category")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(filteredTopics) { topic in
                        TopicRowCheckbox(
                            topic: topic,
                            isSelected: selectedTopicIds.contains(topic.id),
                            onToggle: { toggleTopic(topic.id) }
                        )
                    }
                }
            }
        }
    }
    
    private func loadCurrentAssignments() {
        selectedTopicIds = Set(
            manager.topics
                .filter { $0.videoIds.contains(video.videoId) }
                .map { $0.id }
        )
    }
    
    private func toggleTopic(_ topicId: String) {
        if selectedTopicIds.contains(topicId) {
            selectedTopicIds.remove(topicId)
        } else {
            selectedTopicIds.insert(topicId)
        }
    }
    
    private func saveChanges() {
        isSaving = true
        
        Task {
            // Get currently assigned topics
            let currentTopics = Set(
                manager.topics
                    .filter { $0.videoIds.contains(video.videoId) }
                    .map { $0.id }
            )
            
            // Topics to add (in selectedTopicIds but not in currentTopics)
            let topicsToAdd = selectedTopicIds.subtracting(currentTopics)
            
            // Topics to remove (in currentTopics but not in selectedTopicIds)
            let topicsToRemove = currentTopics.subtracting(selectedTopicIds)
            
            // Add video to new topics
            for topicId in topicsToAdd {
                do {
                    try await manager.addVideoToTopic(topicId: topicId, videoId: video.videoId)
                    print("✅ Added video to topic: \(topicId)")
                } catch {
                    print("❌ Error adding video to topic: \(error)")
                }
            }
            
            // Remove video from deselected topics
            for topicId in topicsToRemove {
                do {
                    try await manager.removeVideoFromTopic(topicId: topicId, videoId: video.videoId)
                    print("✅ Removed video from topic: \(topicId)")
                } catch {
                    print("❌ Error removing video from topic: \(error)")
                }
            }
            
            isSaving = false
            dismiss()
        }
    }
}

struct TopicRowCheckbox: View {
    let topic: ResearchTopic
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .imageScale(.large)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.title)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    // ✅ Show category badge
                    HStack(spacing: 8) {
                        Text(topic.category)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        Text("\(topic.videoIds.count) videos")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let description = topic.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
