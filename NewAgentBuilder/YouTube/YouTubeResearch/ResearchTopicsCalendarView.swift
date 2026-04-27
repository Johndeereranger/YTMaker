//
//  ResearchTopicsCalendarView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/13/26.
//
import SwiftUI

//// MARK: - Research Topics Calendar View
//struct ResearchTopicsCalendarView: View {
//    @StateObject private var manager = ResearchTopicManager()
//    
//    // Group topics by target month
//    var topicsByMonth: [(month: String, topics: [ResearchTopic])] {
//        let grouped = Dictionary(grouping: manager.topics) { $0.targetPublishedMonth }
//        
//        return TopicMonth.allMonths.compactMap { month in
//            if let topics = grouped[month], !topics.isEmpty {
//                // Sort by build order within each month
//                let sorted = topics.sorted { $0.buildOrder < $1.buildOrder }
//                return (month: month, topics: sorted)
//            }
//            return nil
//        }
//    }
//    
//    var body: some View {
//        NavigationView {
//            List {
//                ForEach(topicsByMonth, id: \.month) { monthGroup in
//                    Section {
//                        ForEach(monthGroup.topics) { topic in
//                            NavigationLink(destination: ResearchTopicDetailView(topic: topic, manager: manager)) {
//                                CalendarTopicRow(topic: topic)
//                            }
//                        }
//                    } header: {
//                        HStack {
//                            Text(monthGroup.month)
//                                .font(.headline)
//                            Spacer()
//                            Text("\(monthGroup.topics.count) topics")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                }
//            }
//            .navigationTitle("Content Calendar")
//            .toolbar {
//                ToolbarItem(placement: .navigationBarLeading) {
//                    Button(action: { refreshTopics() }) {
//                        Image(systemName: "arrow.clockwise")
//                    }
//                    .disabled(manager.isLoading)
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
//}

// MARK: - Calendar View (No need to pass manager)
struct ResearchTopicsCalendarView: View {
    @StateObject private var manager = ResearchTopicManager.shared  // ✅ Use shared instance
    
    // Group topics by target month
    var topicsByMonth: [(month: String, topics: [ResearchTopic])] {
        let grouped = Dictionary(grouping: manager.topics) { $0.targetPublishedMonth }
        
        return TopicMonth.allMonths.compactMap { month in
            if let topics = grouped[month], !topics.isEmpty {
                let sorted = topics.sorted { $0.buildOrder < $1.buildOrder }
                return (month: month, topics: sorted)
            }
            return nil
        }
    }
    
    var body: some View {
        List {
            ForEach(topicsByMonth, id: \.month) { monthGroup in
                Section {
                    ForEach(monthGroup.topics) { topic in
                        NavigationLink(destination: ResearchTopicDetailView(topic: topic)) {
                            CalendarTopicRow(topic: topic)
                        }
                    }
                } header: {
                    HStack {
                        Text(monthGroup.month)
                            .font(.headline)
                        Spacer()
                        Text("\(monthGroup.topics.count) topics")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Content Calendar")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { refreshTopics() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(manager.isLoading)
            }
        }
        .overlay {
            if manager.isLoading {
                ProgressView()
            }
        }
    }
    
    private func refreshTopics() {
        Task {
            await manager.refresh()
        }
    }
}

// MARK: - Calendar Topic Row
struct CalendarTopicRow: View {
    let topic: ResearchTopic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title and build order
            HStack {
                Text("#\(topic.buildOrder)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                
                Text(topic.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // Category and Status
            HStack(spacing: 8) {
                // Category badge
                Text(topic.category)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor(topic.category).opacity(0.2))
                    .foregroundColor(categoryColor(topic.category))
                    .cornerRadius(4)
                
                // Status badge
                Text(topic.status.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(topic.status).opacity(0.2))
                    .foregroundColor(statusColor(topic.status))
                    .cornerRadius(4)
                
                // Remake indicator
                if topic.isRemake {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                // Video count
                if !topic.videoIds.isEmpty {
                    Label("\(topic.videoIds.count)", systemImage: "video")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Corn": return .yellow
        case "Thermal Drone": return .purple
        case "Hunting Tactics": return .green
        case "Deer Related (Non-Tactics)": return .blue
        case "Gear & Equipment": return .orange
        case "Deer Behavior": return .cyan
        default: return .gray
        }
    }
    
    private func statusColor(_ status: TopicStatus) -> Color {
        switch status {
        case .idea: return .gray
        case .selected: return .green
        case .published: return .blue
        }
    }
}

#Preview {
    ResearchTopicsCalendarView()
}
