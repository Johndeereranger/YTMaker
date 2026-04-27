//
//  PatternExportView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/6/26.
//


import SwiftUI

struct PatternExportView: View {
    let video: YouTubeVideo
    let breakdown: ScriptBreakdown
    
    @StateObject private var exportManager = PatternExportManager()
    @State private var selectedPatterns: Set<UUID> = []
    @State private var exportedPatternIds: Set<UUID> = []
    @State private var isExporting = false
    @State private var exportStatus = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Pattern Export")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if !selectedPatterns.isEmpty {
                    Button(action: { Task { await exportSelected() } }) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text("Export \(selectedPatterns.count)")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }
            }
            
            if !exportStatus.isEmpty {
                Text(exportStatus)
                    .font(.caption)
                    .foregroundColor(exportStatus.contains("✅") ? .green : .red)
            }
            
            // Patterns list
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(breakdown.allMarkedPatterns) { pattern in
                        patternRow(pattern: pattern)
                    }
                }
            }
        }
        .padding()
        .task {
            await loadExportedStatus()
        }
    }
    
    private func patternRow(pattern: MarkedPattern) -> some View {
        let isExported = exportedPatternIds.contains(pattern.id)
        let isSelected = selectedPatterns.contains(pattern.id)
        let sentences = getSentencesForPattern(pattern)
        let sectionTitle = getSectionTitle(for: pattern)
        
        return HStack(alignment: .top, spacing: 12) {
            // Checkbox (disabled if already exported)
            Button(action: {
                if !isExported {
                    toggleSelection(pattern.id)
                }
            }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isExported ? .gray : (isSelected ? .blue : .primary))
            }
            .buttonStyle(.plain)
            .disabled(isExported)
            
            VStack(alignment: .leading, spacing: 8) {
                // Pattern type badge
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: pattern.type.icon)
                        Text(pattern.type.rawValue)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(pattern.type.color.opacity(0.15))
                    .foregroundColor(pattern.type.color)
                    .cornerRadius(6)
                    
                    if isExported {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Exported")
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                    }
                }
                
                // Section context
                Text("Section: \(sectionTitle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Sentence text
                Text(sentences)
                    .font(.body)
                    .lineLimit(3)
                
                // Note (if present)
                if let note = pattern.note, !note.isEmpty {
                    Text("Note: \(note)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.05) : Color.gray.opacity(0.05))
        .cornerRadius(8)
        .opacity(isExported ? 0.6 : 1.0)
    }
    
    private func toggleSelection(_ patternId: UUID) {
        if selectedPatterns.contains(patternId) {
            selectedPatterns.remove(patternId)
        } else {
            selectedPatterns.insert(patternId)
        }
    }
    
    private func getSentencesForPattern(_ pattern: MarkedPattern) -> String {
        let sentences = breakdown.sentences.filter { pattern.sentenceIds.contains($0.id) }
        return sentences.map { $0.text }.joined(separator: " ")
    }
    
    private func getSectionTitle(for pattern: MarkedPattern) -> String {
        guard let sectionId = pattern.sectionId,
              let section = breakdown.sections.first(where: { $0.id == sectionId }) else {
            return "Unknown Section"
        }
        return section.name
    }
    
    private func loadExportedStatus() async {
        do {
            let patternIds = breakdown.allMarkedPatterns.map { $0.id }
            exportedPatternIds = try await exportManager.getExportedStatus(for: patternIds)
        } catch {
            print("❌ Error loading exported status: \(error)")
        }
    }
    
    private func exportSelected() async {
        isExporting = true
        exportStatus = ""
        
        do {
            // ✅ Fetch channel info ONCE upfront
            let firebaseService = YouTubeFirebaseService()
            let channel = try? await firebaseService.getChannel(channelId: video.channelId)
            let channelName = channel?.name ?? video.channelId
            
            var patternsToExport: [ExportedPattern] = []
            
            for patternId in selectedPatterns {
                guard let pattern = breakdown.allMarkedPatterns.first(where: { $0.id == patternId }),
                      let sectionId = pattern.sectionId,
                      let section = breakdown.sections.first(where: { $0.id == sectionId }) else {
                    continue
                }
                
                let sentenceText = getSentencesForPattern(pattern)
                
                let exportedPattern = ExportedPattern(
                    videoId: video.videoId,
                    videoTitle: video.title,
                    channelId: video.channelId,
                    channelName: channelName,  // ✅ Real channel name
                    sectionTitle: section.name,
                    patternType: pattern.type,
                    sentenceText: sentenceText,
                    note: pattern.note,
                    creatorId: video.channelId,
                    creatorName: channelName,  // ✅ Real channel name
                    originalPatternId: pattern.id
                )
                
                patternsToExport.append(exportedPattern)
            }
            
            try await exportManager.exportPatterns(patternsToExport)
            
            // Update exported status
            await loadExportedStatus()
            
            // Clear selection
            selectedPatterns.removeAll()
            
            exportStatus = "✅ Exported \(patternsToExport.count) pattern(s)"
            
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                exportStatus = ""
            }
            
        } catch {
            exportStatus = "❌ Export failed: \(error.localizedDescription)"
        }
        
        isExporting = false
    }
}
