//
//  TemplateDashboardView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import SwiftUI

struct TemplateDashboardView: View {
    let channel: YouTubeChannel
    @State private var taxonomy: StyleTaxonomy?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTemplate: StyleTemplate?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading taxonomy...")
            } else if let taxonomy = taxonomy {
                taxonomyContent(taxonomy)
            } else {
                noTaxonomyView
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTaxonomy()
        }
        .refreshable {
            await loadTaxonomy()
        }
        .sheet(item: $selectedTemplate) { template in
            NavigationStack {
                TemplateA1aEditorView(
                    channel: channel,
                    template: template,
                    onSave: { updatedTemplate in
                        // Update local state
                        if let index = taxonomy?.templates.firstIndex(where: { $0.id == updatedTemplate.id }) {
                            taxonomy?.templates[index] = updatedTemplate
                        }
                    }
                )
            }
        }
    }

    // MARK: - Main Content

    private func taxonomyContent(_ taxonomy: StyleTaxonomy) -> some View {
        List {
            // Summary Section
            Section {
                summaryCard(taxonomy)
            }

            // Creator Signature
            if !taxonomy.creatorSignature.isEmpty {
                Section("Creator Signature") {
                    Text(taxonomy.creatorSignature)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Shared Patterns
            if !taxonomy.sharedPatterns.isEmpty {
                Section("Shared Patterns") {
                    ForEach(taxonomy.sharedPatterns, id: \.self) { pattern in
                        Label(pattern, systemImage: "checkmark.seal")
                            .font(.caption)
                    }
                }
            }

            // Templates Section
            Section("Content Types (\(taxonomy.templates.count))") {
                ForEach(taxonomy.templates) { template in
                    TemplateRowView(template: template) {
                        selectedTemplate = template
                    }
                }
            }
        }
    }

    private func summaryCard(_ taxonomy: StyleTaxonomy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(channel.name)
                .font(.headline)

            HStack(spacing: 20) {
                TemplateStatBox(label: "Templates", value: taxonomy.templates.count, color: .blue)
                TemplateStatBox(label: "With A1a", value: taxonomy.templates.filter { $0.hasA1aPrompt }.count, color: .green)
                TemplateStatBox(label: "Tested", value: taxonomy.templates.filter { $0.hasBeenTested }.count, color: .purple)
            }

            // Overall status
            let needsWork = taxonomy.templates.filter { !$0.hasA1aPrompt }.count
            if needsWork > 0 {
                Label("\(needsWork) templates need A1a prompts", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Label("All templates have A1a prompts", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Text("Built from \(taxonomy.videoCount) videos")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var noTaxonomyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Taxonomy Found")
                .font(.headline)

            Text("Run Phase 0 analysis on videos and cluster them to build a taxonomy for this channel.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadTaxonomy() async {
        isLoading = true
        do {
            taxonomy = try await YouTubeFirebaseService.shared.loadTaxonomy(channelId: channel.channelId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Template Row View

private struct TemplateRowView: View {
    let template: StyleTemplate
    let onBuildA1a: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(template.name)
                    .font(.headline)
                Spacer()
                Text("\(template.videoCount) videos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Core Question
            if let coreQuestion = template.coreQuestion {
                Text(coreQuestion)
                    .font(.caption)
                    .italic()
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Status Row
            HStack(spacing: 12) {
                // A1a Prompt Status
                StatusBadge(
                    icon: template.hasA1aPrompt ? "checkmark.circle.fill" : "circle",
                    label: template.hasA1aPrompt ? "Has A1a" : "No A1a",
                    color: template.hasA1aPrompt ? .green : .orange
                )

                // Fidelity Status
                StatusBadge(
                    icon: template.hasBeenTested ? "checkmark.circle.fill" : "circle",
                    label: template.hasBeenTested ? "Tested" : "Not Tested",
                    color: template.hasBeenTested ? .blue : .gray
                )

                // Stability Score
                if let score = template.a1aStabilityScore {
                    StatusBadge(
                        icon: "chart.bar.fill",
                        label: "\(Int(score * 100))%",
                        color: score > 0.8 ? .green : score > 0.6 ? .yellow : .red
                    )
                }

                Spacer()
            }

            // Action Button
            Button {
                onBuildA1a()
            } label: {
                HStack {
                    Image(systemName: template.hasA1aPrompt ? "pencil" : "plus.circle")
                    Text(template.hasA1aPrompt ? "Edit A1a Prompt" : "Build A1a Prompt")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Helper Views

private struct TemplateStatBox: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatusBadge: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(label)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }
}

// Make StyleTemplate conform to Identifiable for sheet presentation

#Preview {
    NavigationStack {
        TemplateDashboardView(channel: YouTubeChannel(
            channelId: "test",
            name: "Johnny Harris",
            handle: "johnnyharris",
            thumbnailUrl: "",
            videoCount: 100,
            lastSynced: Date()
        ))
    }
}
