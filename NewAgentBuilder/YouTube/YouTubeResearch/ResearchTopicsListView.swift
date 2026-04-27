//
//  ResearchTopicsListView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/3/25.
//


import SwiftUI
//
//// MARK: - Research Topics List View
//struct ResearchTopicsListView: View {
//    @StateObject private var manager = ResearchTopicManager()
//    @State private var showCreateSheet = false
//    
//    var body: some View {
//        NavigationView {
//            List {
//                ForEach(manager.topics) { topic in
//                    NavigationLink(destination: ResearchTopicDetailView(topic: topic, manager: manager)) {
//                        TopicRowView(topic: topic)
//                    }
//                }
//                .onDelete { indexSet in
//                    deleteTopics(at: indexSet)
//                }
//            }
//            .navigationTitle("Research Topics")
//            .toolbar {
//                ToolbarItem(placement: .navigationBarLeading) {
//                    Button(action: { refreshTopics() }) {
//                        Image(systemName: "arrow.clockwise")
//                    }
//                    .disabled(manager.isLoading)
//                }
//                
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    NavigationLink(destination: ResearchTopicsCalendarView()) {
//                        Image(systemName: "calendar")
//                    }
//                }
//                
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button(action: { showCreateSheet = true }) {
//                        Image(systemName: "plus")
//                    }
//                }
//            }
//            .overlay {
//                if manager.isLoading {
//                    ProgressView()
//                }
//            }
//            .task {
//                await loadTopics()
//            }
//            .sheet(isPresented: $showCreateSheet) {
//                CreateTopicSheet(manager: manager)
//            }
//        }
//    }
//    
//    private func loadTopics() async {
//        do {
//            try await manager.fetchAllTopics()
//        } catch {
//            print("❌ Error loading topics: \(error)")
//        }
//    }
//    
//    private func refreshTopics() {
//        Task {
//            await manager.refresh()
//        }
//    }
//    
//    private func deleteTopics(at offsets: IndexSet) {
//        for index in offsets {
//            let topic = manager.topics[index]
//            Task {
//                try await manager.deleteTopic(id: topic.id)
//            }
//        }
//    }
//}

// MARK: - Research Topics List View
struct ResearchTopicsListView: View {
    @StateObject private var manager = ResearchTopicManager.shared  // ✅ Use shared instance
    @State private var showCreateSheet = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(manager.topics) { topic in
                    NavigationLink(destination: ResearchTopicDetailView(topic: topic)) {
                        TopicRowView(topic: topic)
                    }
                }
                .onDelete { indexSet in
                    deleteTopics(at: indexSet)
                }
            }
            .navigationTitle("Research Topics")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { refreshTopics() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(manager.isLoading)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ResearchTopicsCalendarView()) {
                        Image(systemName: "calendar")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCreateSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if manager.isLoading {
                    ProgressView()
                }
            }
            .task {
                await manager.loadDataIfNeeded()  // ✅ Only loads once
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateTopicSheet()
            }
        }
    }
    
    private func refreshTopics() {
        Task {
            await manager.refresh()
        }
    }
    
    private func deleteTopics(at offsets: IndexSet) {
        for index in offsets {
            let topic = manager.topics[index]
            Task {
                try await manager.deleteTopic(id: topic.id)
            }
        }
    }
}

// MARK: - Topic Row
struct TopicRowView: View {
    let topic: ResearchTopic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.title)
                .font(.headline)
            
            if let description = topic.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
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
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Topic Sheet
struct CreateTopicSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var manager = ResearchTopicManager.shared
    
    @State private var title = ""
    @State private var description = ""
    @State private var topicNotes = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Topic Info") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Notes") {
                    TextField("Research notes (optional)", text: $topicNotes, axis: .vertical)
                        .lineLimit(5...10)
                }
            }
            .navigationTitle("New Research Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTopic()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func createTopic() {
        let newTopic = ResearchTopic(
            title: title,
            description: description.isEmpty ? nil : description,
            topicNotes: topicNotes.isEmpty ? nil : topicNotes
        )
        
        Task {
            try await manager.createTopic(newTopic)
            dismiss()
        }
    }
}


#Preview {
    ResearchTopicsListView()
}
