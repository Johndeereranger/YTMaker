//
//  TemplateExtractorView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import SwiftUI

// MARK: - Template Extractor Section (for CreatorDetailView)

struct TemplateExtractorSection: View {
    let channel: YouTubeChannel
    let videos: [YouTubeVideo]
    let sentenceData: [String: [SentenceFidelityTest]]

    @ObservedObject private var service = TemplateExtractionService.shared
    @State private var showFullView = false

    private var videosWithAnalysis: Int {
        videos.filter { sentenceData[$0.videoId] != nil }.count
    }

    private var canExtract: Bool {
        videosWithAnalysis >= 3
    }

    var body: some View {
        content
            .onAppear {
                // Reset template state when viewing a different channel
                service.resetIfNeeded(for: channel.channelId)
            }
            .onChange(of: channel.channelId) { _, newChannelId in
                service.resetIfNeeded(for: newChannelId)
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Template Extractor")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Status
                HStack {
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundColor(statusColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(statusSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Action buttons
                HStack(spacing: 12) {
                    // Extract button
                    Button {
                        Task { await extractTemplate() }
                    } label: {
                        HStack {
                            if case .analyzing = service.state {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(extractButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canExtract ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canExtract || isExtracting)

                    // View template button (if available)
                    if service.currentTemplate != nil {
                        Button {
                            showFullView = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("View")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Progress or result preview
                if case .analyzing(let progress) = service.state {
                    Text(progress)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if let template = service.currentTemplate {
                    templatePreview(template)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .sheet(isPresented: $showFullView) {
            if let template = service.currentTemplate {
                NavigationStack {
                    TemplateDetailView(template: template, videos: videos)
                }
            }
        }
    }

    private var isExtracting: Bool {
        if case .analyzing = service.state { return true }
        return false
    }

    private var statusIcon: String {
        switch service.state {
        case .idle:
            return service.currentTemplate != nil ? "checkmark.seal.fill" : "doc.badge.gearshape"
        case .analyzing:
            return "gearshape.2"
        case .complete:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch service.state {
        case .idle:
            return service.currentTemplate != nil ? .green : .purple
        case .analyzing:
            return .orange
        case .complete:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusTitle: String {
        switch service.state {
        case .idle:
            return service.currentTemplate != nil ? "Template Ready" : "Extract Template"
        case .analyzing:
            return "Extracting..."
        case .complete:
            return "Template Extracted"
        case .failed(let error):
            return "Extraction Failed"
        }
    }

    private var statusSubtitle: String {
        switch service.state {
        case .idle:
            if let template = service.currentTemplate {
                return "Based on \(template.videosAnalyzed) videos"
            }
            return "\(videosWithAnalysis) videos with sentence analysis available"
        case .analyzing(let progress):
            return progress
        case .complete(let template):
            return "Analyzed \(template.videosAnalyzed) videos"
        case .failed(let error):
            return error
        }
    }

    private var extractButtonTitle: String {
        if case .analyzing = service.state {
            return "Extracting..."
        }
        return service.currentTemplate != nil ? "Re-extract" : "Extract Template"
    }

    @ViewBuilder
    private func templatePreview(_ template: CreatorTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Quick Stats")
                .font(.caption.bold())

            HStack(spacing: 16) {
                // Structural templates count (primary!)
                if let clustering = service.currentClusteringResult {
                    VStack {
                        Text("\(clustering.templates.count)")
                            .font(.title3.bold())
                            .foregroundColor(.purple)
                        Text("Templates")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                VStack {
                    Text(String(format: "%.0f", template.styleMetrics.averageChunksPerVideo))
                        .font(.title3.bold())
                    Text("Chunks/Vid")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(Int(template.styleMetrics.firstPersonUsage * 100))%")
                        .font(.title3.bold())
                    Text("1st Person")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("\(Int(template.styleMetrics.assertingUsage * 100))%")
                        .font(.title3.bold())
                    Text("Asserting")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Show structural template names if available
            if let clustering = service.currentClusteringResult, !clustering.templates.isEmpty {
                HStack(spacing: 6) {
                    ForEach(clustering.templates.sorted(by: { $0.videoCount > $1.videoCount }).prefix(3)) { t in
                        Text(t.templateName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
        }
    }

    private func extractTemplate() async {
        _ = await service.extractTemplate(
            channel: channel,
            videos: videos,
            sentenceData: sentenceData
        )
    }
}

// MARK: - Template Detail View

struct TemplateDetailView: View {
    let template: CreatorTemplate
    let videos: [YouTubeVideo]
    @ObservedObject private var service = TemplateExtractionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var isCopied = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Structures Tab (NEW - most important)
            structuresTab
                .tabItem {
                    Label("Structures", systemImage: "rectangle.stack")
                }
                .tag(0)

            // Overview Tab
            overviewTab
                .tabItem {
                    Label("Style", systemImage: "chart.bar")
                }
                .tag(1)

            // Patterns Tab
            patternsTab
                .tabItem {
                    Label("Patterns", systemImage: "rectangle.3.group")
                }
                .tag(2)

            // Opening/Closing Tab
            sectionsTab
                .tabItem {
                    Label("Sections", systemImage: "arrow.left.arrow.right")
                }
                .tag(3)
        }
        .navigationTitle(template.channelName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    copyReport()
                    withAnimation {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            isCopied = false
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Structures Tab

    private var structuresTab: some View {
        List {
            if let clustering = service.currentClusteringResult {
                Section("Summary") {
                    LabeledContent("Videos Analyzed", value: "\(clustering.videoStructures.count)")
                    LabeledContent("Structural Templates", value: "\(clustering.templates.count)")
                    LabeledContent("Coverage", value: "\(Int(clustering.coveragePercent * 100))%")
                    if !clustering.outlierVideoIds.isEmpty {
                        LabeledContent("Unique/Outlier Videos", value: "\(clustering.outlierVideoIds.count)")
                    }
                }

                if clustering.templates.isEmpty {
                    Section {
                        Text("No distinct structural patterns found. Videos may have too varied structures, or need more data.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } else {
                    ForEach(clustering.templates.sorted(by: { $0.videoCount > $1.videoCount })) { structTemplate in
                        Section {
                            StructuralTemplateView(template: structTemplate)
                        } header: {
                            HStack {
                                Text(structTemplate.templateName)
                                Spacer()
                                Text("\(structTemplate.videoCount) videos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("Structural analysis not available. Re-extract template to generate.")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        List {
            Section("Generation Info") {
                LabeledContent("Videos Analyzed", value: "\(template.videosAnalyzed)")
                LabeledContent("Generated", value: template.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Version", value: template.extractorVersion)
            }

            Section("Perspective Usage") {
                MetricRow(label: "First Person", value: template.styleMetrics.firstPersonUsage, color: .blue)
                MetricRow(label: "Second Person", value: template.styleMetrics.secondPersonUsage, color: .green)
                MetricRow(label: "Third Person", value: template.styleMetrics.thirdPersonUsage, color: .purple)
            }

            Section("Stance Distribution") {
                MetricRow(label: "Asserting", value: template.styleMetrics.assertingUsage, color: .orange)
                MetricRow(label: "Questioning", value: template.styleMetrics.questioningUsage, color: .cyan)
                MetricRow(label: "Challenging", value: template.styleMetrics.challengingUsage, color: .red)
            }

            Section("Content Density") {
                MetricRow(label: "Statistics", value: template.styleMetrics.statisticDensity, color: .indigo)
                MetricRow(label: "Named Entities", value: template.styleMetrics.entityDensity, color: .mint)
                MetricRow(label: "Quotes", value: template.styleMetrics.quoteDensity, color: .pink)
            }

            Section("Engagement Features") {
                MetricRow(label: "Contrast Markers", value: template.styleMetrics.contrastMarkerFrequency, color: .orange)
                MetricRow(label: "Reveal Language", value: template.styleMetrics.revealLanguageFrequency, color: .purple)
                MetricRow(label: "Challenge Language", value: template.styleMetrics.challengeLanguageFrequency, color: .red)
            }

            Section("Structure") {
                LabeledContent("Avg Chunks/Video", value: String(format: "%.1f", template.styleMetrics.averageChunksPerVideo))
                LabeledContent("Avg Sentences/Chunk", value: String(format: "%.1f", template.styleMetrics.averageSentencesPerChunk))
            }
        }
    }

    // MARK: - Patterns Tab

    private var patternsTab: some View {
        List {
            if template.contentPatterns.isEmpty {
                Text("No content patterns detected")
                    .foregroundColor(.secondary)
            } else {
                ForEach(template.contentPatterns) { pattern in
                    ContentPatternRow(pattern: pattern)
                }
            }
        }
    }

    // MARK: - Sections Tab

    private var sectionsTab: some View {
        List {
            Section("Opening Pattern") {
                SectionPatternView(pattern: template.openingPattern)
            }

            Section("Closing Pattern") {
                SectionPatternView(pattern: template.closingPattern)
            }
        }
    }

    private func copyReport() {
        let text = TemplateExtractionService.shared.exportTemplateAsText(template, videos: videos)
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Supporting Views

struct MetricRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack {
            Text(label)

            Spacer()

            HStack(spacing: 8) {
                ProgressView(value: value, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                    .tint(color)

                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 35, alignment: .trailing)
            }
        }
    }
}

struct ContentPatternRow: View {
    let pattern: ContentPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pattern.patternName)
                    .font(.headline)

                Spacer()

                Text("\(Int(pattern.frequency * 100))%")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)
            }

            HStack(spacing: 12) {
                Label(pattern.typicalPosition.label, systemImage: "mappin")
                Label("\(Int(pattern.averageSentenceCount)) sentences", systemImage: "text.alignleft")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text(pattern.dominantPerspective.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)

                Text(pattern.dominantStance.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }

            if !pattern.typicalTagDensity.topTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(pattern.typicalTagDensity.topTags, id: \.name) { tag in
                        Text("\(tag.name) \(Int(tag.value * 100))%")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SectionPatternView: View {
    let pattern: SectionPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Avg Chunks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", pattern.averageChunkCount))
                        .font(.title3.bold())
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Avg Sentences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", pattern.averageSentenceCount))
                        .font(.title3.bold())
                }
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Perspective")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pattern.dominantPerspective.rawValue)
                        .font(.subheadline)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Stance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pattern.dominantStance.rawValue)
                        .font(.subheadline)
                }
            }

            if !pattern.typicalTagDensity.topTags.isEmpty {
                Divider()

                Text("Top Tags")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(pattern.typicalTagDensity.topTags, id: \.name) { tag in
                        HStack(spacing: 4) {
                            Text(tag.name)
                            Text("\(Int(tag.value * 100))%")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }

            if !pattern.exampleSentences.isEmpty {
                Divider()

                Text("Example Openings")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(pattern.exampleSentences.prefix(3)) { example in
                    Text("\"\(example.text)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Structural Template View

struct StructuralTemplateView: View {
    let template: StructuralTemplate

    @EnvironmentObject private var nav: NavigationViewModel
    @ObservedObject private var extractionService = TemplateExtractionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Characteristics
            if !template.dominantCharacteristics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(template.dominantCharacteristics, id: \.self) { char in
                        Text(char)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }

            // Chunk sequence
            Text("Typical Chunk Sequence:")
                .font(.caption.bold())
                .padding(.top, 4)

            ForEach(template.typicalSequence) { chunk in
                TemplateChunkRow(chunk: chunk)
            }

            // Key pivots
            if !template.keyPivots.isEmpty {
                Divider()

                Text("Key Pivots:")
                    .font(.caption.bold())

                ForEach(template.keyPivots, id: \.position) { pivot in
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(pivot.label)
                            .font(.caption)
                    }
                }
            }

            // All videos in this template
            if !template.exampleVideoTitles.isEmpty {
                Divider()

                Text("Videos in Template (\(template.exampleVideoTitles.count)):")
                    .font(.caption.bold())

                ForEach(template.exampleVideoTitles, id: \.self) { title in
                    Text("• \(title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Find Twins button
            if template.videoCount >= 2, let channelId = extractionService.currentChannel?.channelId {
                Divider()

                Button {
                    nav.push(.rhetoricalTwinFinder(
                        channelId,
                        template.id
                    ))
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("Find Rhetorical Twins")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct TemplateChunkRow: View {
    let chunk: TemplateChunk

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Position label
            Text(chunk.positionLabel)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .leading)

            // Role and tags
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chunk.typicalRole)
                        .font(.caption)
                        .fontWeight(.medium)

                    if chunk.isPivotPoint {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("PIVOT")
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                    }
                }

                if !chunk.highTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chunk.highTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(tagColor(for: tag).opacity(0.2))
                                .cornerRadius(3)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func tagColor(for tag: String) -> Color {
        switch tag {
        case "1P": return .blue
        case "2P": return .green
        case "STAT", "ENT": return .indigo
        case "QUOTE": return .pink
        case "CONTRAST": return .orange
        case "REVEAL": return .purple
        case "CHALLENGE": return .red
        default: return .gray
        }
    }
}
