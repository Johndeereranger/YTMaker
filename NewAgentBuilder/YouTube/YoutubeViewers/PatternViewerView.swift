//
//  PatternViewerView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/6/26.
//


import SwiftUI

struct PatternViewerView: View {
    @StateObject private var exportManager = PatternExportManager()
    @EnvironmentObject var viewModel: VideoSearchViewModel
    @EnvironmentObject var nav: NavigationViewModel
    
    @State private var searchText = ""
    @State private var selectedPatternType: PatternType? = nil
    @State private var selectedCreatorId: String? = nil
    @State private var showingFilters = false
    @State private var isLoading = false
    
    // Computed filtered patterns
    private var filteredPatterns: [ExportedPattern] {
        var patterns = exportManager.exportedPatterns
        
        // Filter by search text
        if !searchText.isEmpty {
            patterns = patterns.filter { pattern in
                pattern.sentenceText.localizedCaseInsensitiveContains(searchText) ||
                pattern.videoTitle.localizedCaseInsensitiveContains(searchText) ||
                pattern.sectionTitle.localizedCaseInsensitiveContains(searchText) ||
                (pattern.note?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Filter by pattern type
        if let type = selectedPatternType {
            patterns = patterns.filter { $0.patternType == type }
        }
        
        // Filter by creator
        if let creatorId = selectedCreatorId {
            patterns = patterns.filter { $0.creatorId == creatorId }
        }
        
        return patterns
    }
    
    // Get unique creators from patterns
    private var uniqueCreators: [(id: String, name: String)] {
        let creators = exportManager.exportedPatterns.map { pattern in
            (id: pattern.creatorId, name: pattern.creatorName ?? pattern.creatorId)
        }
        
        let uniqueDict = Dictionary(grouping: creators, by: { $0.id })
            .mapValues { $0.first! }
        
        return Array(uniqueDict.values).sorted { $0.name < $1.name }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar and filters
            searchAndFilterSection
            
            // Stats
            statsSection
            
            Divider()
            
            // Patterns list
            if isLoading {
                ProgressView("Loading patterns...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPatterns.isEmpty {
                emptyState
            } else {
                patternsList
            }
        }
        .navigationTitle("Exported Patterns")
        .task {
            await loadPatterns()
        }
        .refreshable {
            await loadPatterns()
        }
    }
    
    // MARK: - Search and Filter Section
    
    private var searchAndFilterSection: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search patterns...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Pattern type filter
                    Menu {
                        Button("All Types") {
                            selectedPatternType = nil
                        }
                        
                        Divider()
                        
                        ForEach(PatternType.allCases, id: \.self) { type in
                            Button(action: { selectedPatternType = type }) {
                                HStack {
                                    Image(systemName: type.icon)
                                    Text(type.rawValue)
                                    if selectedPatternType == type {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                            Text(selectedPatternType?.rawValue ?? "All Types")
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedPatternType != nil ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .foregroundColor(selectedPatternType != nil ? .blue : .primary)
                        .cornerRadius(8)
                    }
                    
                    // Creator filter
                    if !uniqueCreators.isEmpty {
                        Menu {
                            Button("All Creators") {
                                selectedCreatorId = nil
                            }
                            
                            Divider()
                            
                            ForEach(uniqueCreators, id: \.id) { creator in
                                Button(action: { selectedCreatorId = creator.id }) {
                                    HStack {
                                        Text(creator.name)
                                        if selectedCreatorId == creator.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person")
                                Text(selectedCreatorId != nil ? (uniqueCreators.first { $0.id == selectedCreatorId }?.name ?? "Creator") : "All Creators")
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCreatorId != nil ? Color.purple.opacity(0.2) : Color.gray.opacity(0.1))
                            .foregroundColor(selectedCreatorId != nil ? .purple : .primary)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Clear filters
                    if selectedPatternType != nil || selectedCreatorId != nil {
                        Button(action: clearFilters) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                Text("Clear")
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        HStack(spacing: 20) {
            StatBadge(
                icon: "square.and.arrow.up",
                value: exportManager.exportedPatterns.count,
                label: "patterns"
            )
            
            StatBadge(
                icon: "tag",
                value: Set(exportManager.exportedPatterns.map { $0.patternType }).count,
                label: "types"
            )
            
            StatBadge(
                icon: "person",
                value: uniqueCreators.count,
                label: "creators"
            )
            
            if !searchText.isEmpty || selectedPatternType != nil || selectedCreatorId != nil {
                StatBadge(
                    icon: "line.3.horizontal.decrease.circle",
                    value: filteredPatterns.count,
                    label: "filtered"
                )
            }
        }
        .padding()
    }
    
    // MARK: - Patterns List
    
    private var patternsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredPatterns) { pattern in
                    patternCard(pattern: pattern)
                }
            }
            .padding()
        }
    }
    
    private func patternCard(pattern: ExportedPattern) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Pattern type + Date
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: pattern.patternType.icon)
                    Text(pattern.patternType.rawValue)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(pattern.patternType.color.opacity(0.15))
                .foregroundColor(pattern.patternType.color)
                .cornerRadius(6)
                
                Spacer()
                
                Text(pattern.exportedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Delete button
                Button(action: { Task { await deletePattern(pattern) } }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            // Video context
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { navigateToVideo(pattern.videoId) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.rectangle")
                            .font(.caption2)
                        Text(pattern.videoTitle)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text("Section: \(pattern.sectionTitle)")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                if let creatorName = pattern.creatorName {
                    HStack(spacing: 4) {
                        Image(systemName: "person")
                            .font(.caption2)
                        Text(creatorName)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Pattern text
            Text(pattern.sentenceText)
                .font(.body)
                .textSelection(.enabled)
            
            // Note (if present)
            if let note = pattern.note, !note.isEmpty {
                Text("Note: \(note)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 4)
            }
            
            // Copy button
            HStack {
                Spacer()
                CopyButton(
                    label: "Copy Text",
                    valueToCopy: pattern.sentenceText,
                    font: .caption
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            if searchText.isEmpty && selectedPatternType == nil && selectedCreatorId == nil {
                Text("No Exported Patterns")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Export patterns from video script breakdowns to build your playbook.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("No Matching Patterns")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Try adjusting your search or filters.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Clear Filters") {
                    clearFilters()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadPatterns() async {
        isLoading = true
        do {
            try await exportManager.fetchAllPatterns()
        } catch {
            print("❌ Error loading patterns: \(error)")
        }
        isLoading = false
    }
    
    private func clearFilters() {
        searchText = ""
        selectedPatternType = nil
        selectedCreatorId = nil
    }
    
    private func deletePattern(_ pattern: ExportedPattern) async {
        do {
            try await exportManager.deletePattern(id: pattern.id)
            await loadPatterns()
        } catch {
            print("❌ Error deleting pattern: \(error)")
        }
    }
    
    private func navigateToVideo(_ videoId: String) {
        print(#function, "NOT SET UP YET ")
        // Find video in viewModel
//        if let video = viewModel.allVideos.first(where: { $0.videoId == videoId }) {
//            nav.push(.videoDetail(video))
//        }
    }
}

