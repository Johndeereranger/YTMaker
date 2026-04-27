//
//  CreatorProfileSection.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/27/26.
//

import SwiftUI

// MARK: - Creator Profile Section

/// Section view for generating and viewing Creator Profiles
/// Used in CreatorDetailView alongside TemplateExtractorSection
struct CreatorProfileSection: View {
    let channel: YouTubeChannel
    let videos: [YouTubeVideo]
    let sentenceData: [String: [SentenceFidelityTest]]

    @StateObject private var profileService = CreatorProfileService.shared
    @State private var existingProfile: CreatorProfile?
    @State private var isLoadingProfile = false
    @State private var isGenerating = false
    @State private var showProfileDetail = false
    @State private var generationProgress = ""
    @State private var errorMessage: String?

    private var videosWithAnalysis: Int {
        videos.filter { sentenceData[$0.videoId] != nil }.count
    }

    private var canGenerate: Bool {
        videosWithAnalysis >= 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "person.crop.rectangle.stack")
                    .foregroundColor(.purple)
                Text("Creator Profile")
                    .font(.headline)
                Spacer()

                if existingProfile != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            // Status
            HStack {
                Text("Videos with analysis:")
                Text("\(videosWithAnalysis)")
                    .fontWeight(.semibold)
                    .foregroundColor(canGenerate ? .green : .orange)
                Text("(need 3+)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            // Existing profile info
            if let profile = existingProfile {
                existingProfileView(profile)
            } else if isLoadingProfile {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking for existing profile...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No profile generated yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }

            // Generate button
            if isGenerating {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(generationProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                Button {
                    Task { await generateProfile() }
                } label: {
                    HStack {
                        Image(systemName: existingProfile == nil ? "plus.circle.fill" : "arrow.clockwise")
                        Text(existingProfile == nil ? "Generate Creator Profile" : "Regenerate Profile")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!canGenerate)
            }

            if !canGenerate {
                Text("Run sentence analysis on at least 3 videos to generate a profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .task {
            await loadExistingProfile()
        }
        .sheet(isPresented: $showProfileDetail) {
            if let profile = existingProfile {
                CreatorProfileDetailSheet(profile: profile)
            }
        }
    }

    // MARK: - Existing Profile View

    private func existingProfileView(_ profile: CreatorProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile v\(profile.profileVersion)")
                        .font(.caption.bold())

                    Text("Generated: \(profile.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(profile.videosAnalyzed) videos analyzed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showProfileDetail = true
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.bordered)
            }

            // Quick summary
            VStack(alignment: .leading, spacing: 4) {
                Label("Shape: \(profile.shape.middle.name)", systemImage: "rectangle.3.group")
                    .font(.caption)

                Label("Required: \(profile.ingredientList.required.count) ingredients", systemImage: "checkmark.circle")
                    .font(.caption)

                Label("Style: \(profile.styleFingerprint.summary)", systemImage: "paintbrush")
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func loadExistingProfile() async {
        isLoadingProfile = true
        do {
            existingProfile = try await CreatorProfileFirebaseService.shared.getProfile(forChannelId: channel.channelId)
        } catch {
            print("Failed to load profile: \(error)")
        }
        isLoadingProfile = false
    }

    private func generateProfile() async {
        isGenerating = true
        errorMessage = nil
        generationProgress = "Starting..."

        do {
            // First, we need the clustering result from TemplateExtractionService
            generationProgress = "Extracting templates..."

            // Run template extraction first if needed
            let templateService = TemplateExtractionService.shared
            let creatorTemplate = await templateService.extractTemplate(
                channel: channel,
                videos: videos,
                sentenceData: sentenceData,
                onProgress: { progress in
                    Task { @MainActor in
                        generationProgress = progress
                    }
                }
            )

            guard let template = creatorTemplate,
                  let clusteringResult = templateService.currentClusteringResult else {
                errorMessage = "Failed to extract templates"
                isGenerating = false
                return
            }

            // Now generate the creator profile
            generationProgress = "Generating profile..."

            let profile = await profileService.generateProfile(
                channel: channel,
                clusteringResult: clusteringResult,
                creatorTemplate: template,
                onProgress: { progress in
                    Task { @MainActor in
                        generationProgress = progress
                    }
                }
            )

            guard let generatedProfile = profile else {
                errorMessage = "Failed to generate profile"
                isGenerating = false
                return
            }

            // Save to Firebase
            generationProgress = "Saving profile..."
            try await CreatorProfileFirebaseService.shared.saveProfile(generatedProfile)

            existingProfile = generatedProfile
            generationProgress = "Complete!"

        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        isGenerating = false
    }
}

// MARK: - Profile Detail Sheet

struct CreatorProfileDetailSheet: View {
    let profile: CreatorProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.channelName)
                            .font(.title.bold())
                        Text("Creator Profile v\(profile.profileVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(profile.videosAnalyzed) videos analyzed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Style Fingerprint
                    sectionHeader("Style Fingerprint", icon: "paintbrush")
                    styleSection

                    Divider()

                    // Shape
                    sectionHeader("Content Shape", icon: "rectangle.3.group")
                    shapeSection

                    Divider()

                    // Ingredients
                    sectionHeader("Ingredient List", icon: "checklist")
                    ingredientsSection

                    Divider()

                    // Export
                    Button {
                        copyToClipboard(profile.exportText)
                    } label: {
                        Label("Copy Full Profile", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Profile Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile.styleFingerprint.summary)
                .font(.subheadline)
                .foregroundColor(.blue)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Perspective:")
                        .foregroundStyle(.secondary)
                    Text("1P \(pct(profile.styleFingerprint.firstPersonUsage)) | 2P \(pct(profile.styleFingerprint.secondPersonUsage)) | 3P \(pct(profile.styleFingerprint.thirdPersonUsage))")
                }
                GridRow {
                    Text("Stance:")
                        .foregroundStyle(.secondary)
                    Text("Assert \(pct(profile.styleFingerprint.assertingUsage)) | Question \(pct(profile.styleFingerprint.questioningUsage))")
                }
                GridRow {
                    Text("Content:")
                        .foregroundStyle(.secondary)
                    Text("ENT \(pct(profile.styleFingerprint.entityDensity)) | STAT \(pct(profile.styleFingerprint.statisticDensity))")
                }
                GridRow {
                    Text("Engagement:")
                        .foregroundStyle(.secondary)
                    Text("CONTRAST \(pct(profile.styleFingerprint.contrastFrequency)) | REVEAL \(pct(profile.styleFingerprint.revealFrequency))")
                }
            }
            .font(.caption)
        }
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(profile.shape.overallDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Intro
            shapePartRow("INTRO", profile.shape.intro.name, profile.shape.intro.typicalPositionRange, profile.shape.intro.highTags)

            // Middle
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("MIDDLE")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    Text(profile.shape.middle.name)
                        .font(.caption.bold())
                    Spacer()
                    Text(profile.shape.middle.typicalPositionRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(profile.shape.middle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Pivots: \(profile.shape.middle.pivotCountRange)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !profile.shape.middle.commonBlockTypes.isEmpty {
                    Text("Blocks: \(profile.shape.middle.commonBlockTypes.map { $0.name }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)

            // Close
            shapePartRow("CLOSE", profile.shape.close.name, profile.shape.close.typicalPositionRange, profile.shape.close.highTags)

            // Consistent/Flexible
            if !profile.shape.consistentElements.isEmpty {
                Text("Consistent: \(profile.shape.consistentElements.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            if !profile.shape.flexibleElements.isEmpty {
                Text("Flexible: \(profile.shape.flexibleElements.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func shapePartRow(_ label: String, _ name: String, _ range: String, _ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.bold())
                    .foregroundColor(label == "INTRO" ? .green : .blue)
                Text(name)
                    .font(.caption.bold())
                Spacer()
                Text(range)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !tags.isEmpty {
                Text("Tags: \(tags.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Required
            if !profile.ingredientList.required.isEmpty {
                Text("REQUIRED (must appear)")
                    .font(.caption.bold())
                    .foregroundColor(.red)

                ForEach(profile.ingredientList.required) { ingredient in
                    ingredientRow(ingredient)
                }
            }

            // Common
            if !profile.ingredientList.common.isEmpty {
                Text("COMMON (often appears)")
                    .font(.caption.bold())
                    .foregroundColor(.orange)
                    .padding(.top, 4)

                ForEach(profile.ingredientList.common) { ingredient in
                    ingredientRow(ingredient)
                }
            }

            // Optional
            if !profile.ingredientList.optional.isEmpty {
                Text("OPTIONAL (sometimes appears)")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
                    .padding(.top, 4)

                ForEach(profile.ingredientList.optional) { ingredient in
                    ingredientRow(ingredient)
                }
            }
        }
    }

    private func ingredientRow(_ ingredient: Ingredient) -> some View {
        HStack(alignment: .top) {
            Text("•")
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.type)
                    .font(.caption.bold())
                Text(ingredient.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(pct(ingredient.frequency))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pct(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
