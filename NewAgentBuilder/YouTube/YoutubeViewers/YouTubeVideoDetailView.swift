//
//  YouTubeVideoDetailView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/16/25.
//


import SwiftUI

struct YouTubeVideoDetailView: View {
    let video: YouTubeVideo
    @EnvironmentObject var viewModel: VideoSearchViewModel
    @EnvironmentObject var nav: NavigationViewModel
    
    // Local state for editing
    @State private var localVideo: YouTubeVideo
    @State private var transcript: String?
    @State private var summary: String?
    @State private var isLoadingTranscript = false
    @State private var transcriptError: String?
    
    // Collapsible section states
    @State private var isDescriptionExpanded = false
    @State private var isTranscriptExpanded = false
    @State private var isFactsExpanded = false
    @State private var isSummaryExpanded = false
    @State private var isHookExpanded = false
    @State private var isIntroExpanded = false
    @State private var isNotesExpanded = false
    @State private var isUpdatingStats = false
    // Add this state variable with the others at the top
    @State private var isTranscriptRewriterExpanded = false
    @State private var isStrategicOutlineExpanded = false
    @State private var isPatternExportExpanded = false
    @State private var hasAnalysis = false
    
    
    @State private var outlineBreakdown: ScriptBreakdown?

    // Script Breakdown
    // MARK: - Script Breakdown State

    @State private var isScriptBreakdownExpanded = false
    @State private var isGeneratedOutlineExpanded = false
    @State private var selectedPatternType: PatternType = .tease
    @State private var typingText = ""

    
    // Research topics
    @StateObject private var topicManager = ResearchTopicManager.shared
    @State private var showTopicPicker = false
    
    @State private var showingDiagnostic = false
    
    init(video: YouTubeVideo) {
        self.video = video
        _localVideo = State(initialValue: video)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Thumbnail
                thumbnailSection
                
                // Title
                Text(localVideo.title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Stats
                statsSection
                
                // Date and Duration
                metadataRow
                
                Divider()
                
                // Research Metadata Section (notHunting, videoType, notes)
                researchMetadataSection
                
                Divider()
                
                // Hook Section (hook + hookType)
                hookSection
                
                Divider()
                
                // Intro Section
                introSection
                
                Divider()
                
                // Description (collapsible)
                descriptionSection
                
                Divider()
                
                // Transcript Section (collapsible + editable)
                transcriptSection
                Divider()
                transcriptRewriterSection
                Divider()
                scriptBreakdownSection
                Divider()
                generatedOutlineSection
                Divider()
              
                strategicOutlineSection
                Divider()

                patternExportSection
                Divider()
                // Facts Section (collapsible + editable)
                factsSection
                
                Divider()
                
                // Summary Section (collapsible + editable)
                summarySection
                
                Divider()
                
                // Research Topics Section
                researchTopicsSection
                
                Divider()
                analyzeStructureButton
                Divider()
                
                // Video ID
                videoIdSection
                
                // Open in YouTube
                youtubeButton
            }
            .padding()
        }
        .navigationTitle("Video Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadResearchTopics()
            await loadOutlineData()
            await checkForAnalysis()
            //await loadScriptBreakdown()
            //await loadScriptBreakdown()
        }
        .sheet(isPresented: $showTopicPicker) {
            ResearchTopicPickerSheet(
                video: localVideo
            )
        }
        .sheet(isPresented: $showingDiagnostic) {
            ScriptBreakdownDiagnosticView(videoId: localVideo.videoId)
        }
    }
    
    // MARK: - Thumbnail Section
    private var thumbnailSection: some View {
        AsyncImage(url: URL(string: localVideo.thumbnailUrl)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fit)
        }
        .frame(maxWidth: 250, maxHeight: 250)
        .cornerRadius(12)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        HStack(spacing: 20) {
            StatBadge(icon: "eye.fill", value: localVideo.stats.viewCount, label: "views")
            StatBadge(icon: "hand.thumbsup.fill", value: localVideo.stats.likeCount, label: "likes")
            StatBadge(icon: "bubble.left.fill", value: localVideo.stats.commentCount, label: "comments")
        }
    }
    
    // MARK: - Metadata Row
    private var metadataRow: some View {
        HStack {
            Label(localVideo.publishedAt.formatted(date: .long, time: .omitted), systemImage: "calendar")
            
            Label(formatDuration(localVideo.duration), systemImage: "clock")
            Spacer()
           
                   Button(action: { showingDiagnostic = true }) {
                       Label("Diagnostic", systemImage: "stethoscope")
                   }
               
            Button(action: {
                  nav.push(.scriptBreakdownFullscreen(localVideo))
              }) {
                  Label("Script Breakdown", systemImage: "doc.text.magnifyingglass")
                      .font(.caption)
              }
              .buttonStyle(.bordered)
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    // MARK: - Research Metadata Section
    private var researchMetadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Research Metadata")
                .font(.headline)
            
            // Not Hunting Toggle
            Toggle(isOn: Binding(
                get: { localVideo.notHunting },
                set: { newValue in
                    localVideo.notHunting = newValue
                    Task { await saveField("notHunting", value: newValue) }
                }
            )) {
                Label("Not Hunting Content", systemImage: localVideo.notHunting ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(localVideo.notHunting ? .red : .green)
            }
            
            // Video Type
            EditableTextFieldSection(
                title: "Video Type",
                icon: "tag",
                placeholder: "e.g., Tutorial, List, Review",
                text: Binding(
                    get: { localVideo.videoType ?? "" },
                    set: { newValue in
                        localVideo.videoType = newValue.isEmpty ? nil : newValue
                    }
                ),
                onSave: { await saveField("videoType", value: localVideo.videoType) }
            )
            
            // Notes (collapsible)
            CollapsibleEditableSection(
                title: "Notes",
                icon: "note.text",
                isExpanded: $isNotesExpanded,
                text: Binding(
                    get: { localVideo.notes ?? "" },
                    set: { newValue in
                        localVideo.notes = newValue.isEmpty ? nil : newValue
                    }
                ),
                placeholder: "Add your research notes here...",
                onSave: { await saveField("notes", value: localVideo.notes) },
                additionalButtons: {EmptyView()}
            )
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Transcript Rewriter Section
    private var transcriptRewriterSection: some View {
        CollapsibleSection(
            title: "Transcript Rewriter",
            icon: "pencil.line",
            isExpanded: $isTranscriptRewriterExpanded,
            count: nil
        ) {
            if let transcriptText = localVideo.transcript ?? transcript, !transcriptText.isEmpty {
                TranscriptRewriterView(transcript: transcriptText)
            } else {
                Text("No transcript available. Fetch transcript first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            }
        }
    }
    // MARK: - Stratigic Outline Section
    private var strategicOutlineSection: some View {
        CollapsibleSection(
            title: "Strategic Outline",
            icon: "list.bullet.rectangle.portrait",
            isExpanded: $isStrategicOutlineExpanded,
            count: outlineBreakdown?.sections.isEmpty == false ? "\(outlineBreakdown?.sections.count ?? 0) sections" : nil
        ) {
            if let breakdown = outlineBreakdown {
                StrategicOutlineView2(
                    video: localVideo,
                    breakdown: Binding(
                        get: { breakdown },
                        set: { outlineBreakdown = $0 }
                    )
                )
                .padding()
            } else {
                Text("Loading outline...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }


    
    // MARK: - Script Breakdown Section
    private var scriptBreakdownSection: some View {
        CollapsibleSection(
            title: "Script Breakdown",
            icon: "doc.text.magnifyingglass",
            isExpanded: $isScriptBreakdownExpanded,
            count: nil
        ) {
            if let transcriptText = localVideo.transcript ?? transcript, !transcriptText.isEmpty {
                ScriptBreakdownEditorView(video: localVideo, transcript: transcriptText, isFullscreen: false)
            } else {
                Text("No transcript available. Fetch transcript first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            }
        }
    }
    

   
    
    // MARK: - Generated Outline Section
    private var generatedOutlineSection: some View {
        CollapsibleSection(
            title: "Generated Outline",
            icon: "list.bullet.rectangle",
            isExpanded: $isGeneratedOutlineExpanded,
            count: outlineBreakdown?.sections.isEmpty == false ? "\(outlineBreakdown?.sections.count ?? 0) sections" : nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let breakdown = outlineBreakdown, !breakdown.sections.isEmpty {
                    outlineContent(breakdown: breakdown)
                    
                    CopyButton(
                        label: "Copy Outline",
                        valueToCopy: generateOutlineText(breakdown: breakdown),
                        font: .subheadline
                    )
                    .padding(.top, 8)
                } else {
                    Text("No outline yet. Use Script Breakdown above to create sections.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                }
            }
            .padding()
        }
        .task {
            await loadOutlineData()
        }
        .refreshable {
            await loadOutlineData()
        }
    }
    
    private func outlineContent(breakdown: ScriptBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(breakdown.sections.enumerated()), id: \.element.id) { index, section in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(index + 1). \(section.name)")
                            .font(.headline)
                        Spacer()
                        Button(action: { editSectionName(section) }) {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    

                    
                    let patternsInSection = breakdown.allMarkedPatterns.filter { $0.sectionId == section.id }
                    if !patternsInSection.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Patterns:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(patternsInSection) { pattern in
                                HStack(spacing: 8) {
                                    Image(systemName: pattern.type.icon)
                                        .foregroundColor(pattern.type.color)
                                        .font(.caption)
                                    
                                    Text(pattern.type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(pattern.type.color)
                                    
                                    Text(getSentenceTextForPattern(pattern, breakdown: breakdown).prefix(60) + "...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(pattern.type.color.opacity(0.05))
                                .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    private func getSentenceTextForPattern(_ pattern: MarkedPattern, breakdown: ScriptBreakdown) -> String {
        let sentences = breakdown.sentences.filter { pattern.sentenceIds.contains($0.id) }
        return sentences.map { $0.text }.joined(separator: " ")
    }

    private func generateOutlineText(breakdown: ScriptBreakdown) -> String {
        var text = "VIDEO OUTLINE\n\n"
        
        for (index, section) in breakdown.sections.enumerated() {
            text += "\(index + 1). \(section.name)\n"
            
//            if let purpose = section.purpose, !purpose.isEmpty {
//                text += "   Purpose: \(purpose)\n"
//            }
            
            let patternsInSection = breakdown.allMarkedPatterns.filter { $0.sectionId == section.id }
            if !patternsInSection.isEmpty {
                text += "   Patterns:\n"
                for pattern in patternsInSection {
                    let sentenceText = getSentenceTextForPattern(pattern, breakdown: breakdown)
                    text += "   - [\(pattern.type.rawValue)] \(sentenceText)\n"
                }
            }
            
            text += "\n"
        }
        
        return text
    }

    private func loadOutlineData() async {
        do {
            let firebaseService = YouTubeFirebaseService()
            if let breakdown = try await firebaseService.loadScriptBreakdown(videoId: localVideo.videoId) {
                outlineBreakdown = breakdown
                print("Load VideoID: \(localVideo.videoId) Outline Success")
                for (index, section) in breakdown.sections.enumerated() {
                    print("Section \(index + 1): \(section.name)")
                    print("AITITLE: \(section.aiTitle ?? "N/A ")")
                    
                }
            } else {
                print("no breakdown got")
            }
        } catch {
            print("❌ Error loading outline: \(error)")
        }
    }
   


    private func editSectionName(_ section: OutlineSection) {
        // TODO: Show alert or inline editor to change section name and purpose
        // For now, this is a placeholder
        print("Edit section: \(section.name)")
    }

   

    private func typingModeView(transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type the transcript as practice (not saved):")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .top, spacing: 12) {
                // Original transcript (reference)
                VStack(alignment: .leading) {
                    Text("Original:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ScrollView {
                        Text(transcript)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .frame(maxHeight: 200)
                }
                .frame(maxWidth: .infinity)
                
                // Your typing
                VStack(alignment: .leading) {
                    Text("Your typing:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $typingText)
                        .font(.body)
                        .frame(maxHeight: 200)
                        .border(Color.gray.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
            }
            
        }
    }

    

   



   





    // MARK: - Script Breakdown Actions

   

    

 
    
    // MARK: - Hook Section
    private var hookSection: some View {
        CollapsibleSection(
            title: "Hook",
            icon: "hook",
            isExpanded: $isHookExpanded,
            count: localVideo.hook != nil ? "Set" : "Not set"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Hook Text
                EditableTextFieldSection(
                    title: "Hook Text",
                    icon: "text.quote",
                    placeholder: "Enter the video hook...",
                    text: Binding(
                        get: { localVideo.hook ?? "" },
                        set: { newValue in
                            localVideo.hook = newValue.isEmpty ? nil : newValue
                        }
                    ),
                    onSave: { await saveField("hook", value: localVideo.hook) },
                    multiline: true
                )
                
                // Hook Type Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hook Type")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("Hook Type", selection: Binding(
                        get: { localVideo.hookType ?? .none },
                        set: { newValue in
                            localVideo.hookType = newValue == .none ? nil : newValue
                            Task { await saveField("hookType", value: localVideo.hookType?.rawValue) }
                        }
                    )) {
                        ForEach(HookType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Copy Hook Button
                if let hook = localVideo.hook, !hook.isEmpty {
                    CopyButton(label: "Copy Hook", valueToCopy: hook, font: .caption)
                }
            }
        }
    }
    
    // MARK: - Intro Section
    private var introSection: some View {
        CollapsibleEditableSection(
            title: "Intro",
            icon: "play.circle",
            isExpanded: $isIntroExpanded,
            text: Binding(
                get: { localVideo.intro ?? "" },
                set: { newValue in
                    localVideo.intro = newValue.isEmpty ? nil : newValue
                }
            ),
            placeholder: "Enter the video intro...",
            onSave: { await saveField("intro", value: localVideo.intro) },
            additionalButtons: { EmptyView() }
        )
    }
    
    // MARK: - Description Section
    private var descriptionSection: some View {
        CollapsibleSection(
            title: "Description",
            icon: "text.alignleft",
            isExpanded: $isDescriptionExpanded,
            count: nil
        ) {
            Text(localVideo.description.isEmpty ? "No description" : localVideo.description)
                .font(.body)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }
    
    // MARK: - Transcript Section
    private var transcriptSection: some View {
        CollapsibleEditableSection(
            title: "Transcript",
            icon: "doc.text",
            isExpanded: $isTranscriptExpanded,
            text: Binding(
                get: { localVideo.transcript ?? transcript ?? "" },
                set: { newValue in
                    if localVideo.transcript != nil {
                        localVideo.transcript = newValue.isEmpty ? nil : newValue
                    } else {
                        transcript = newValue.isEmpty ? nil : newValue
                    }
                }
            ),
            placeholder: "No transcript available",
            onSave: { await saveTranscript() },
            additionalButtons: {transcriptButtons}
        )
    }

    
    private var evergreenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Growth Analysis")
                .font(.headline)
            
            if let history = localVideo.stats.viewHistory, !history.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Evergreen status
                    HStack {
                        Image(systemName: localVideo.isEvergreen ? "leaf.fill" : "chart.line.flattrend.xyaxis")
                            .foregroundColor(localVideo.isEvergreen ? .green : .orange)
                        
                        Text(localVideo.isEvergreen ? "Evergreen Video" : "Peaked Video")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(localVideo.isEvergreen ? .green : .orange)
                    }
                    
                    // Growth rate
                    if let growthRate = localVideo.growthRate {
                        Text("Growth: \(String(format: "%.1f", growthRate))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // View history summary
                    Text("\(history.count) data points collected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastUpdate = localVideo.daysSinceLastUpdate {
                        Text("Last updated: \(lastUpdate) days ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Simple growth chart visualization
                    if history.count >= 2 {
                        ViewHistoryChart(history: history)
                            .frame(height: 100)
                    }
                }
            } else {
                Text("No growth data available yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                
                Text("Update stats to start tracking growth")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Update stats button
            Button(action: { Task { await updateVideoStats() } }) {
                HStack {
                    if isUpdatingStats {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Updating...")
                    } else {
                        Image(systemName: "chart.xyaxis.line")
                        Text("Update Stats Now")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .foregroundColor(.purple)
                .cornerRadius(8)
            }
            .disabled(isUpdatingStats)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var transcriptButtons: some View {
        Group {
            if localVideo.transcript == nil && transcript == nil {
                Button(action: { Task { await fetchTranscript() } }) {
                    if isLoadingTranscript {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading...")
                                .font(.caption)
                        }
                    } else {
                        Label("Fetch", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingTranscript)
            }
            
            // ✅ ADD THIS - Copy with Title button
            if let transcriptText = localVideo.transcript ?? transcript, !transcriptText.isEmpty {
                CopyButton(
                    label: "Copy w/ Title",
                    valueToCopy: "Title:\(localVideo.title)\n\nScript:\(transcriptText)",
                    font: .caption
                )
            }
            
            if let error = transcriptError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private func updateVideoStats() async {
        isUpdatingStats = true
        
        do {
            let firebaseService = YouTubeFirebaseService()
            let apiKey = "YOUR_API_KEY" // TODO: Get from secure storage
            
            let updatedVideo = try await firebaseService.updateVideoStats(
                videoId: localVideo.videoId
            )
            
            localVideo = updatedVideo
            viewModel.updateVideo(updatedVideo)
            
            print("✅ Updated stats")
        } catch {
            print("❌ Failed to update stats: \(error)")
        }
        
        isUpdatingStats = false
    }
    
    private var patternExportSection: some View {
        CollapsibleSection(
            title: "Pattern Export",
            icon: "square.and.arrow.up",
            isExpanded: $isPatternExportExpanded,
            count: outlineBreakdown?.allMarkedPatterns.isEmpty == false ? "\(outlineBreakdown?.allMarkedPatterns.count ?? 0) patterns" : nil
        ) {
            if let breakdown = outlineBreakdown {
                PatternExportView(video: localVideo, breakdown: breakdown)
            } else {
                Text("Loading patterns...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
    
    // MARK: - Facts Section
    private var factsSection: some View {
        CollapsibleEditableSection(
            title: "Facts",
            icon: "list.bullet.clipboard",
            isExpanded: $isFactsExpanded,
            text: Binding(
                get: { localVideo.factsText ?? "" },
                set: { newValue in
                    localVideo.factsText = newValue.isEmpty ? nil : newValue
                }
            ),
            placeholder: "No facts available",
            onSave: { await saveField("factsText", value: localVideo.factsText) },
            backgroundColor: Color.blue.opacity(0.05),
            additionalButtons: {EmptyView()}
        )
    }
    
    // MARK: - Summary Section
    private var summarySection: some View {
        CollapsibleEditableSection(
            title: "Summary",
            icon: "doc.plaintext",
            isExpanded: $isSummaryExpanded,
            text: Binding(
                get: { localVideo.summaryText ?? summary ?? "" },
                set: { newValue in
                    if localVideo.summaryText != nil {
                        localVideo.summaryText = newValue.isEmpty ? nil : newValue
                    } else {
                        summary = newValue.isEmpty ? nil : newValue
                    }
                }
            ),
            placeholder: "No summary available",
            onSave: { await saveSummary() },
            backgroundColor: Color.purple.opacity(0.05),
            additionalButtons: {EmptyView()}
        )
    }
    
    // MARK: - Research Topics Section
    private var researchTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Research Topics")
                    .font(.headline)
                Spacer()
                Button(action: { showTopicPicker = true }) {
                    Label("Manage", systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            
            let assignedTopics = topicManager.topics.filter { $0.videoIds.contains(localVideo.videoId) }
            
            if assignedTopics.isEmpty {
                Text("Not assigned to any research topics")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(assignedTopics) { topic in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.blue)
                            Text(topic.title)
                                .font(.subheadline)
                            Spacer()
                            Button(action: {
                                Task {
                                    try await topicManager.removeVideoFromTopic(
                                        topicId: topic.id,
                                        videoId: localVideo.videoId
                                    )
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Video ID Section
    private var videoIdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Video ID")
                .font(.headline)
            HStack {
                
                Text(localVideo.videoId)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                
                CopyButton(label: "Video ID", valueToCopy: localVideo.videoId,font: .caption)
                
                Spacer()
            }
        }
    }
    
    // MARK: - YouTube Button
    private var youtubeButton: some View {
        Link(destination: URL(string: "https://youtube.com/watch?v=\(localVideo.videoId)")!) {
            Label("Open in YouTube", systemImage: "play.rectangle.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadResearchTopics() async {
        do {
            try await topicManager.fetchAllTopics()
        } catch {
            print("❌ Error loading topics: \(error)")
        }
    }
    
    private func saveField(_ field: String, value: Any?) async {
        let firebaseService = YouTubeFirebaseService()
        do {
            try await firebaseService.updateVideoField(videoId: localVideo.videoId, field: field, value: value)
            print("✅ Saved \(field)")
            
            // ✅ ADD THIS - Update the ViewModel
            viewModel.updateVideo(localVideo)
            
        } catch {
            print("❌ Error saving \(field): \(error)")
        }
    }
    
    private func fetchTranscript() async {
        isLoadingTranscript = true
        transcriptError = nil
        
        do {
            let service = YouTubeTranscriptService()
            let fetchedTranscript = try await service.fetchTranscript(videoId: localVideo.videoId)
            transcript = fetchedTranscript
            localVideo.transcript = fetchedTranscript
            
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.updateVideoTranscript(videoId: localVideo.videoId, transcript: fetchedTranscript)
            
            print("✅ Fetched and saved transcript")
        } catch {
            transcriptError = "Failed to fetch transcript: \(error.localizedDescription)"
            print("❌ Transcript error: \(error)")
        }
        
        isLoadingTranscript = false
    }
    
    private func saveTranscript() async {
        let textToSave = localVideo.transcript ?? transcript ?? ""
        guard !textToSave.isEmpty else { return }
        
        do {
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.updateVideoTranscript(videoId: localVideo.videoId, transcript: textToSave)
            localVideo.transcript = textToSave
            viewModel.updateTranscript(videoId: localVideo.videoId, transcript: textToSave)
            print("✅ Saved transcript")
        } catch {
            print("❌ Error saving transcript: \(error)")
        }
    }
    
    private func saveSummary() async {
        let textToSave = localVideo.summaryText ?? summary ?? ""
        guard !textToSave.isEmpty else { return }
        
        do {
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.updateVideoSummary(videoId: localVideo.videoId, summary: textToSave)
            localVideo.summaryText = textToSave
            print("✅ Saved summary")
            viewModel.updateSummary(videoId: localVideo.videoId, summary: textToSave)
        } catch {
            print("❌ Error saving summary: \(error)")
        }
    }
    
    private func formatDuration(_ duration: String) -> String {
        var result = duration
        result = result.replacingOccurrences(of: "PT", with: "")
        result = result.replacingOccurrences(of: "H", with: ":")
        result = result.replacingOccurrences(of: "M", with: ":")
        result = result.replacingOccurrences(of: "S", with: "")
        return result
    }
    
    private func checkForAnalysis() async {
        do {
            let alignment = try await CreatorAnalysisFirebase.shared.loadAlignmentDoc(
                videoId: video.videoId,
                channelId: video.channelId
            )
            hasAnalysis = alignment != nil
        } catch {
            hasAnalysis = false
        }
    }
}


struct ViewHistoryChart: View {
    let history: [ViewSnapshot]
    
    var body: some View {
        GeometryReader { geometry in
            let sorted = history.sorted { $0.date < $1.date }
            let maxViews = Double(sorted.map { $0.viewCount }.max() ?? 1)
            let minViews = Double(sorted.map { $0.viewCount }.min() ?? 0)
            let range = maxViews - minViews
            
            Path { path in
                for (index, snapshot) in sorted.enumerated() {
                    let x = CGFloat(index) / CGFloat(sorted.count - 1) * geometry.size.width
                    let normalizedY = range > 0 ? (Double(snapshot.viewCount) - minViews) / range : 0.5
                    let y = geometry.size.height - (CGFloat(normalizedY) * geometry.size.height)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.green, lineWidth: 2)
        }
    }
    
}


extension YouTubeVideoDetailView {
    var analyzeStructureButton: some View {
        Section {
            Button {
                nav.push(.manualIngestion(video))
            } label: {
                Label("Analyze Script Structure (A1a)", systemImage: "brain")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            if hasAnalysis {
                Button {
                    nav.push(.alignmentViewer(video))
                } label: {
                    Label("View Structure Analysis", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
