//
//  StrategicOutlineView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/5/26.
//


import SwiftUI

struct StrategicOutlineView: View {
    let video: YouTubeVideo
    @State private var scriptBreakdown: ScriptBreakdown?
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading outline...")
                    .padding()
            } else if let breakdown = scriptBreakdown {
                VStack(alignment: .leading, spacing: 20) {
                    // Video header
                    videoHeader
                    
                    Divider()
                    
                    // Sections
                    ForEach(Array(breakdown.sections.enumerated()), id: \.element.id) { index, section in
                        sectionCard(section: section, index: index, breakdown: breakdown)
                    }
                    
                    // Export buttons
                    exportButtons
                }
                .padding()
            } else {
                Text("No outline available")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .navigationTitle("Strategic Outline")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadOutline()
        }
    }
    
    private var videoHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
            
//            Text(video.channelTitle)
//                .font(.subheadline)
//                .foregroundColor(.secondary)
            
            Link("Open in YouTube", destination: URL(string: "https://youtube.com/watch?v=\(video.videoId)")!)
                .font(.caption)
        }
    }
    
    private func sectionCard(section: OutlineSection, index: Int, breakdown: ScriptBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("SECTION \(index + 1): \(section.name)")
                .font(.headline)
                .foregroundColor(.blue)
            
            // Belief
            if let belief = section.beliefInstalled, !belief.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Belief Installed:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(belief)
                        .font(.body)
                }
            }
            
            // Notes
            if let notes = section.rawNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(notes)
                        .font(.body)
                }
            }
            
            // Patterns
            let patternsInSection = breakdown.allMarkedPatterns.filter { $0.sectionId == section.id }
            if !patternsInSection.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patterns Used:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(Array(Set(patternsInSection.map { $0.type })), id: \.self) { type in
                            HStack(spacing: 4) {
                                Image(systemName: type.icon)
                                Text(type.rawValue)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(type.color.opacity(0.15))
                            .foregroundColor(type.color)
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            // Archetype (if set)
            if let archetype = section.aiArchetype, !archetype.isEmpty {
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                    Text("Archetype: \(archetype)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.purple)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var exportButtons: some View {
        VStack(spacing: 12) {
            Button(action: { copyOutline() }) {
                Label("Copy Outline", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
            
            Button(action: { copyFullVersion() }) {
                Label("Copy Full Version", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(8)
            }
            
            Button(action: { copyWithPrompt() }) {
                Label("Copy with AI Prompt", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .foregroundColor(.purple)
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadOutline() async {
        isLoading = true
        do {
            let firebaseService = YouTubeFirebaseService()
            scriptBreakdown = try await firebaseService.loadScriptBreakdown(videoId: video.videoId)
        } catch {
            print("❌ Error loading outline: \(error)")
        }
        isLoading = false
    }
    
    // Export functions (same as in ScriptBreakdownEditorView but using local scriptBreakdown)
    private func copyOutline() {
        guard let breakdown = scriptBreakdown else { return }
        // ... same implementation ...
    }
    
    private func copyFullVersion() {
        guard let breakdown = scriptBreakdown else { return }
        // ... same implementation ...
    }
    
    private func copyWithPrompt() {
        guard let breakdown = scriptBreakdown else { return }
        // ... same implementation ...
    }
}
