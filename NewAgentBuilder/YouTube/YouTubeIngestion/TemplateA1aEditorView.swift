//
//  TemplateA1aEditorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import SwiftUI

struct TemplateA1aEditorView: View {
    let channel: YouTubeChannel
    let template: StyleTemplate
    let onSave: (StyleTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var promptText: String = ""
    @State private var sampleVideos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showCopyConfirmation = false

    // For fidelity testing
    @State private var selectedTestVideo: YouTubeVideo?
    @State private var showFidelityTester = false
    @State private var lastStabilityScore: Double?
    @State private var lastTestedAt: Date?

    // For version history
    @State private var showIterationComparison = false

    var body: some View {
        List {
            // Template Info Section
            Section("Template Info") {
                templateInfoView
            }

            // Prompt Editor Section
            Section("A1a System Prompt") {
                promptEditorView
            }

            // Sample Videos Section
            Section("Sample Videos (\(sampleVideos.count))") {
                if isLoading {
                    ProgressView("Loading videos...")
                } else if sampleVideos.isEmpty {
                    Text("No videos in this template")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sampleVideos.prefix(5)) { video in
                        SampleVideoRow(video: video, isSelected: selectedTestVideo?.videoId == video.videoId) {
                            selectedTestVideo = video
                        }
                    }
                    if sampleVideos.count > 5 {
                        Text("+ \(sampleVideos.count - 5) more videos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Fidelity Test Results Section
            if lastStabilityScore != nil || template.a1aStabilityScore != nil {
                Section("Fidelity Testing") {
                    fidelityStatusView
                }
            }

            // Actions Section
            Section {
                actionsView
            }
        }
        .navigationTitle("Edit A1a - \(template.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await savePrompt() }
                }
                .disabled(promptText.isEmpty || isSaving)
            }
        }
        .task {
            await loadSampleVideos()
            loadExistingPrompt()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showFidelityTester) {
            if let video = selectedTestVideo {
                TemplateFidelityTesterView(
                    channel: channel,
                    template: template,
                    video: video,
                    prompt: promptText,
                    onComplete: { score, testedAt in
                        lastStabilityScore = score
                        lastTestedAt = testedAt
                    }
                )
            }
        }
        .sheet(isPresented: $showIterationComparison) {
            TemplateIterationComparisonView(
                channel: channel,
                template: template
            )
        }
    }

    // MARK: - Template Info

    private var templateInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name)
                .font(.headline)

            if let coreQuestion = template.coreQuestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Core Question")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(coreQuestion)
                        .font(.caption)
                        .italic()
                }
            }

            if let narrativeArc = template.narrativeArc {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Narrative Arc")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(narrativeArc)
                        .font(.caption)
                }
            }

            HStack(spacing: 16) {
                Label("\(template.videoCount) videos", systemImage: "video")
                Label("Pivots: \(template.expectedPivotMin)-\(template.expectedPivotMax)", systemImage: "arrow.triangle.branch")
                Label(template.retentionStrategy, systemImage: "chart.line.uptrend.xyaxis")
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            if template.hasA1aPrompt {
                Label("Has custom A1a prompt", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Prompt Editor

    private var promptEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Customize the A1a prompt for this template")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    loadBaselinePrompt()
                } label: {
                    Text("Load Baseline")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            TextEditor(text: $promptText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 300)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Text("\(promptText.count) characters")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    copyPromptToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Actions

    private var actionsView: some View {
        VStack(spacing: 12) {
            // Test Button
            Button {
                showFidelityTester = true
            } label: {
                HStack {
                    Image(systemName: "testtube.2")
                    Text(selectedTestVideo != nil ? "Run Fidelity Test" : "Select a Video to Test")
                }
            }
            .disabled(selectedTestVideo == nil || promptText.isEmpty)
            .buttonStyle(.bordered)

            // Version History Button (disabled - no version tracking)
            Button {
                showIterationComparison = true
            } label: {
                Label("View Version History", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            .disabled(true)

            // Copy Prompt + Template Context
            Button {
                copyPromptWithContext()
            } label: {
                Label("Copy Prompt + Template Context", systemImage: "doc.on.doc.fill")
            }
            .buttonStyle(.bordered)
        }
    }

    private var fidelityStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show the most recent score (either from this session or saved)
            let score = lastStabilityScore ?? template.a1aStabilityScore ?? 0
            let testedAt = lastTestedAt ?? template.a1aLastTestedAt

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stability Score")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Text("\(Int(score * 100))%")
                        .font(.title.bold())
                        .foregroundColor(stabilityColor(score))
                }

                Spacer()

                if let date = testedAt {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last Tested")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Score interpretation
            HStack {
                Image(systemName: score >= 0.8 ? "checkmark.circle.fill" : score >= 0.6 ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                    .foregroundColor(stabilityColor(score))
                Text(score >= 0.8 ? "Prompt is stable" : score >= 0.6 ? "Some inconsistency detected" : "Prompt needs refinement")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if lastStabilityScore != nil {
                Label("New test result - save to update template", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private func stabilityColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .yellow }
        return .red
    }

    // MARK: - Data Loading

    private func loadSampleVideos() async {
        isLoading = true
        do {
            let allVideos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channel.channelId)
            sampleVideos = allVideos.filter { template.videoIds.contains($0.videoId) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadExistingPrompt() {
        if let existingPrompt = template.a1aSystemPrompt, !existingPrompt.isEmpty {
            promptText = existingPrompt
        } else {
            loadBaselinePrompt()
        }
    }

    private func loadBaselinePrompt() {
        // Generate a template-specific baseline prompt
        promptText = generateBaselinePrompt()
    }

    private func generateBaselinePrompt() -> String {
        """
        You are analyzing a YouTube video transcript to identify its structural sections.

        TEMPLATE CONTEXT:
        - Content Type: \(template.name)
        - Core Question: \(template.coreQuestion ?? "N/A")
        - Narrative Arc: \(template.narrativeArc ?? "N/A")
        - Expected Pivots: \(template.expectedPivotMin)-\(template.expectedPivotMax)
        - Retention Strategy: \(template.retentionStrategy)
        - Argument Type: \(template.argumentType)
        - Section Density: \(template.sectionDensity)
        - Common Evidence Types: \(template.commonEvidenceTypes.joined(separator: ", "))

        YOUR TASK:
        Identify the major structural sections of this video. For each section, provide:
        1. The section role (HOOK, SETUP, EVIDENCE, TURN, PAYOFF, etc.)
        2. Start and end sentence numbers
        3. A brief title and summary
        4. The strategic purpose of this section

        For this "\(template.name)" style video, pay special attention to:
        - \(template.retentionStrategy) retention patterns
        - \(template.argumentType) argument structure
        - Evidence types like: \(template.commonEvidenceTypes.joined(separator: ", "))

        OUTPUT FORMAT: Return valid JSON only.
        """
    }

    // MARK: - Actions

    private func savePrompt() async {
        isSaving = true

        do {
            try await YouTubeFirebaseService.shared.updateTemplateA1aPrompt(
                channelId: channel.channelId,
                templateId: template.id,
                prompt: promptText
            )

            // If we have a new stability score from testing, save it too
            if let score = lastStabilityScore, let testedAt = lastTestedAt {
                try await YouTubeFirebaseService.shared.updateTemplateStability(
                    channelId: channel.channelId,
                    templateId: template.id,
                    stabilityScore: score,
                    testedAt: testedAt
                )
            }

            // Update local template and call callback
            var updatedTemplate = template
            updatedTemplate.a1aSystemPrompt = promptText
            if let score = lastStabilityScore {
                updatedTemplate.a1aStabilityScore = score
            }
            if let testedAt = lastTestedAt {
                updatedTemplate.a1aLastTestedAt = testedAt
            }
            onSave(updatedTemplate)

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func copyPromptToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = promptText
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(promptText, forType: .string)
        #endif
    }

    private func copyPromptWithContext() {
        let contextualPrompt = """
        ==================== TEMPLATE CONTEXT ====================

        Template Name: \(template.name)
        Core Question: \(template.coreQuestion ?? "N/A")
        Narrative Arc: \(template.narrativeArc ?? "N/A")
        Description: \(template.description)

        Characteristics:
        - Expected Pivots: \(template.expectedPivotMin)-\(template.expectedPivotMax)
        - Retention Strategy: \(template.retentionStrategy)
        - Argument Type: \(template.argumentType)
        - Section Density: \(template.sectionDensity)
        - Evidence Types: \(template.commonEvidenceTypes.joined(separator: ", "))

        Videos in this template: \(template.videoCount)

        ==================== A1A SYSTEM PROMPT ====================

        \(promptText)
        """

        #if os(iOS)
        UIPasteboard.general.string = contextualPrompt
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextualPrompt, forType: .string)
        #endif
    }
}

// MARK: - Sample Video Row

private struct SampleVideoRow: View {
    let video: YouTubeVideo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)

                // Thumbnail
                AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 28)
                .cornerRadius(4)

                // Title
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        if video.hasTranscript {
                            Label("Transcript", systemImage: "doc.text")
                        }
                        if video.phase0Result != nil {
                            Label("Phase 0", systemImage: "sparkles")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        TemplateA1aEditorView(
            channel: YouTubeChannel(
                channelId: "test",
                name: "Johnny Harris",
                handle: "johnnyharris",
                thumbnailUrl: "",
                videoCount: 100,
                lastSynced: Date()
            ),
            template: StyleTemplate(
                id: "test_historical",
                name: "Historical Investigation",
                description: "Videos that trace the origins of institutions or events",
                videoIds: ["video1", "video2"],
                expectedPivotMin: 4,
                expectedPivotMax: 6,
                retentionStrategy: "mystery-reveal",
                argumentType: "investigative",
                sectionDensity: "dense",
                commonTransitionMarkers: [],
                commonEvidenceTypes: ["historical-data", "document-reveal"],
                expectedSectionsMin: 5,
                expectedSectionsMax: 8,
                turnSignals: []
            ),
            onSave: { _ in }
        )
    }
}
