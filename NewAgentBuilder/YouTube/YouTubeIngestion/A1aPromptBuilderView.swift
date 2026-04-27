//
//  A1aPromptBuilderView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/25/26.
//

import SwiftUI

/// Entry point for A1a prompt development workflow
/// Shows all locked templates and their A1a prompt status
/// Navigate here from CreatorDetailView's "Build A1a Prompts" button
struct A1aPromptBuilderView: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel

    @State private var lockedTaxonomy: LockedTaxonomy?
    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading templates...")
            } else if let taxonomy = lockedTaxonomy, taxonomy.isLocked {
                templateListView(taxonomy: taxonomy)
            } else {
                noTaxonomyView
            }
        }
        .navigationTitle("A1a Prompts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
    }

    // MARK: - Template List View

    private func templateListView(taxonomy: LockedTaxonomy) -> some View {
        List {
            // Summary section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .foregroundColor(.blue)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("A1a Prompt Development")
                                .font(.headline)
                            Text("Build template-specific extraction prompts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    HStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text("\(taxonomy.templateCount)")
                                .font(.title2.bold())
                            Text("Templates")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading) {
                            Text("\(templatesWithPrompt(taxonomy).count)")
                                .font(.title2.bold())
                                .foregroundColor(.green)
                            Text("Have Prompts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading) {
                            Text("\(templatesNeedingPrompt(taxonomy).count)")
                                .font(.title2.bold())
                                .foregroundColor(templatesNeedingPrompt(taxonomy).isEmpty ? .secondary : .orange)
                            Text("Need Work")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Templates needing prompts (prioritized)
            if !templatesNeedingPrompt(taxonomy).isEmpty {
                Section("Needs A1a Prompt") {
                    ForEach(templatesNeedingPrompt(taxonomy)) { template in
                        templateRow(template: template, status: .needsPrompt)
                    }
                }
            }

            // Templates with prompts
            if !templatesWithPrompt(taxonomy).isEmpty {
                Section("Has A1a Prompt") {
                    ForEach(templatesWithPrompt(taxonomy)) { template in
                        let status: TemplatePromptStatus = {
                            if let stability = template.a1aStabilityScore, stability >= 0.8 {
                                return .stable
                            } else if template.hasBeenTested {
                                return .needsWork
                            } else {
                                return .untested
                            }
                        }()
                        templateRow(template: template, status: status)
                    }
                }
            }

            // Help section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workflow")
                        .font(.caption.bold())

                    workflowStep(number: 1, text: "Select a template below")
                    workflowStep(number: 2, text: "Copy context (Phase 0 + transcripts)")
                    workflowStep(number: 3, text: "Develop prompt externally")
                    workflowStep(number: 4, text: "Paste & run fidelity tests")
                    workflowStep(number: 5, text: "Save when stable (80%+)")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func workflowStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.blue))

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Template Row

    private func templateRow(template: LockedTemplate, status: TemplatePromptStatus) -> some View {
        Button {
            nav.push(.a1aPromptWorkbench(channel, template))
        } label: {
            HStack(spacing: 12) {
                // Status indicator
                statusIcon(status)

                // Template info
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Text(template.id)
                            .font(.caption2)
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.indigo.opacity(0.1))
                            .cornerRadius(2)

                        Text("\(template.exemplarCount) exemplars")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Exemplars with data
                        let exemplarsReady = exemplarsWithData(for: template)
                        if exemplarsReady < template.exemplarCount {
                            Text("\(exemplarsReady) ready")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }

                    // Status text
                    statusText(template: template, status: status)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusIcon(_ status: TemplatePromptStatus) -> some View {
        switch status {
        case .needsPrompt:
            Image(systemName: "circle")
                .font(.title3)
                .foregroundColor(.secondary)
        case .untested:
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundColor(.blue)
        case .needsWork:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.orange)
        case .stable:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)
        }
    }

    @ViewBuilder
    private func statusText(template: LockedTemplate, status: TemplatePromptStatus) -> some View {
        switch status {
        case .needsPrompt:
            Text("No A1a prompt - tap to start building")
                .font(.caption)
                .foregroundColor(.secondary)
        case .untested:
            Text("Has prompt - not yet tested")
                .font(.caption)
                .foregroundColor(.blue)
        case .needsWork:
            if let stability = template.a1aStabilityScore {
                Text("\(String(format: "%.0f%%", stability * 100)) stability (needs work)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        case .stable:
            if let stability = template.a1aStabilityScore {
                Text("\(String(format: "%.0f%%", stability * 100)) stable")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    // MARK: - No Taxonomy View

    private var noTaxonomyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Locked Taxonomy")
                .font(.title2.bold())

            Text("You need to create and lock a taxonomy before building A1a prompts.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                nav.push(.taxonomyBatchRunner(channel))
            } label: {
                Label("Create Taxonomy", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Helpers

    private func templatesWithPrompt(_ taxonomy: LockedTaxonomy) -> [LockedTemplate] {
        taxonomy.templates.filter { $0.hasA1aPrompt }
    }

    private func templatesNeedingPrompt(_ taxonomy: LockedTaxonomy) -> [LockedTemplate] {
        taxonomy.templates.filter { !$0.hasA1aPrompt }
    }

    private func exemplarsWithData(for template: LockedTemplate) -> Int {
        template.exemplarVideoIds.filter { videoId in
            videos.first { $0.videoId == videoId }?.hasTranscript == true
        }.count
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true

        do {
            // Load videos
            videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channel.channelId)

            // Load locked taxonomy
            lockedTaxonomy = try await YouTubeFirebaseService.shared.getLockedTaxonomy(forChannel: channel.channelId)

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Supporting Types

private enum TemplatePromptStatus {
    case needsPrompt    // No A1a prompt yet
    case untested       // Has prompt but not tested
    case needsWork      // Tested but stability < 80%
    case stable         // Tested and stability >= 80%
}
