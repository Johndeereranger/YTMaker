//
//  StrategicOutlineView 2.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/5/26.
//
//

import SwiftUI

struct StrategicOutlineView2: View {
    let video: YouTubeVideo
    @Binding var breakdown: ScriptBreakdown
    
    @State private var showingImportSection = false
    @State private var importStatus: String = ""
    @State private var editingSection: OutlineSection?
    @State private var expandedSections: Set<UUID> = []
    @State private var showingAIForSection: Set<UUID> = []
    @State private var saveStatus: String = ""
    @State private var isSaving: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            exportButtons
            HStack {
                Text("Strategic Outline")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Save status indicator
                if isSaving {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Saving...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if !saveStatus.isEmpty {
                    Text(saveStatus)
                        .font(.caption2)
                        .foregroundColor(saveStatus.contains("✅") ? .green : .red)
                }
                
                // Toggle all AI sections
                if !breakdown.sections.isEmpty {
                    Button(action: toggleAllAISections) {
                        Label(showingAIForSection.count == breakdown.sections.count ? "Collapse All AI" : "Expand All AI",
                              systemImage: showingAIForSection.count == breakdown.sections.count ? "chevron.up.circle" : "chevron.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if breakdown.sections.isEmpty {
                Text("No strategic outline yet. Use Script Breakdown to create sections with notes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Section cards
                        sectionsList
                        
                        // Export buttons
                        exportButtons
                        
                        // AI Import Section
                        aiAnalysisImportSection()
                    }
                }
            }
        }
        .sheet(item: $editingSection) { section in
            SectionEditorSheet(
                section: section,
                breakdown: $breakdown,
                video: video,
                onSave: {
                    // Trigger save status update
                    saveStatus = "✅ Section saved"
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        saveStatus = ""
                    }
                }
            )
        }
    }
    
    private var sectionsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(breakdown.sections.enumerated()), id: \.element.id) { index, section in
                sectionCard(section: section, index: index)
            }
        }
    }
    
    private func sectionCard(section: OutlineSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with edit button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SECTION \(index + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(section.displayName)
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    // Show both titles if AI title exists
                    if let aiTitle = section.aiTitle, aiTitle != section.name {
                        HStack(spacing: 4) {
                            Text("Original:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(section.name)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { editingSection = section }) {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Byron's Input Section (Always visible)
            if section.beliefInstalled != nil || section.rawNotes != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Notes:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    if let belief = section.beliefInstalled, !belief.isEmpty {
                        fieldDisplay(.beliefInstalled, content: belief)
                    }
                    
                    if let notes = section.rawNotes, !notes.isEmpty {
                        fieldDisplay(.rawNotes, content: notes)
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.05))
                .cornerRadius(8)
            }
            
            // Patterns Used
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
                .padding(12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
            Text("AI Title, ")
            let hasAnyAI = (section.aiTitle?.isEmpty == false) ||
                           (section.aiSummary?.isEmpty == false) ||
                           (section.aiStrategicPurpose?.isEmpty == false) ||
                           (section.aiMechanism?.isEmpty == false) ||
                           (section.aiInputsRecipe?.isEmpty == false) ||
                           (section.aiBSFlags?.isEmpty == false) ||
                           (section.aiArchetype?.isEmpty == false)

            
            // AI Fields Section (Collapsible)
            if hasAnyAI {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: {
                        withAnimation {
                            if showingAIForSection.contains(section.id) {
                                showingAIForSection.remove(section.id)
                            } else {
                                showingAIForSection.insert(section.id)
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: showingAIForSection.contains(section.id) ? "chevron.down" : "chevron.right")
                            Text("AI Analysis")
                                .font(.caption)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            // Show archetype as preview when collapsed
                            if !showingAIForSection.contains(section.id), let archetype = section.aiArchetype {
                                HStack(spacing: 4) {
                                    Image(systemName: OutlineSection.FieldType.aiArchetype.icon)
                                        .font(.caption2)
                                    Text(archetype)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.purple)
                            }
                            
                            Button(action: { clearAIAnalysis(for: section) }) {
                                Image(systemName: "trash.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundColor(.purple)
                    }
                    .buttonStyle(.plain)
                    
                    if showingAIForSection.contains(section.id) {
                        VStack(alignment: .leading, spacing: 12) {
                            if let summary = section.aiSummary, !summary.isEmpty {
                                fieldDisplay(.aiSummary, content: summary)
                            }
                            
                            if let purpose = section.aiStrategicPurpose, !purpose.isEmpty {
                                fieldDisplay(.aiStrategicPurpose, content: purpose)
                            }
                            
                            if let mechanism = section.aiMechanism, !mechanism.isEmpty {
                                fieldDisplay(.aiMechanism, content: mechanism)
                            }
                            
                            if let inputs = section.aiInputsRecipe, !inputs.isEmpty {
                                fieldDisplay(.aiInputsRecipe, content: inputs)
                            }
                            
                            if let flags = section.aiBSFlags, !flags.isEmpty {
                                fieldDisplay(.aiBSFlags, content: flags)
                            }
                            
                            if let archetype = section.aiArchetype, !archetype.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: OutlineSection.FieldType.aiArchetype.icon)
                                        .foregroundColor(OutlineSection.FieldType.aiArchetype.color)
                                    Text("Archetype:")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    Text(archetype)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.purple.opacity(0.05))
                .cornerRadius(8)
            } else {
                // No AI analysis yet
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.secondary)
                        Text("No AI analysis yet - CHECK2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func fieldDisplay(_ fieldType: OutlineSection.FieldType, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: fieldType.icon)
                    .foregroundColor(fieldType.color)
                    .font(.caption)
                Text(fieldType.displayName + ":")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            Text(content)
                .font(.body)
                .textSelection(.enabled)
        }
    }
    
    private var exportButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export Options:")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                CopyButtonAction(label: "Full Version") {
                    copyFullVersion()
                }
                CopyButtonAction(label: "Human Prompt") {
                    copyWithPrompt()
                }
                CopyButtonAction(label: "JSON Prompt") {
                    copyWithPromptJSON()
                }
            }
            
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func toggleAllAISections() {
        if showingAIForSection.count == breakdown.sections.count {
            showingAIForSection.removeAll()
        } else {
            showingAIForSection = Set(breakdown.sections.map { $0.id })
        }
    }
    
    private func clearAIAnalysis(for section: OutlineSection) {
        guard let index = breakdown.sections.firstIndex(where: { $0.id == section.id }) else { return }
        
        breakdown.sections[index].aiTitle = nil
        breakdown.sections[index].aiSummary = nil
        breakdown.sections[index].aiStrategicPurpose = nil
        breakdown.sections[index].aiMechanism = nil
        breakdown.sections[index].aiInputsRecipe = nil
        breakdown.sections[index].aiBSFlags = nil
        breakdown.sections[index].aiArchetype = nil
        
        Task {
            await saveToFirebase(showStatus: true, statusMessage: "AI analysis cleared", updatedBreakdown: breakdown)
        }
    }
    
    private func saveToFirebase(showStatus: Bool = false, statusMessage: String = "Saved", updatedBreakdown: ScriptBreakdown) async {
        if showStatus {
            isSaving = true
            saveStatus = ""
        }
        
        do {
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.saveScriptBreakdown(videoId: video.videoId, breakdown: updatedBreakdown)
            print("✅ Saved script breakdown: \(breakdown.sections.count) sections, \(breakdown.allMarkedPatterns.count) patterns")
            
            if showStatus {
                isSaving = false
                saveStatus = "✅ \(statusMessage)"
                
                // Clear status after 2 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    saveStatus = ""
                }
            }
        } catch {
            print("❌ Error saving script breakdown: \(error)")
            
            if showStatus {
                isSaving = false
                saveStatus = "❌ Save failed"
                
                // Clear status after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    saveStatus = ""
                }
            }
        }
    }
    
    // MARK: - Export Functions
    
    private func copyFullVersion() {
        let fullVersion = generateFullVersion()
        #if os(iOS)
        UIPasteboard.general.string = fullVersion
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullVersion, forType: .string)
        #endif
        print("✅ Copied full version to clipboard")
        
        saveStatus = "✅ Copied to clipboard"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveStatus = ""
        }
    }
    
    private func copyWithPrompt() {
        let fullVersion = generateFullVersion()
        let promptService = YouTubeAIPrompts()
        let withPrompt = promptService.getAIPromptForOutlineSectionsHuman(fullVersion: fullVersion)

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(withPrompt, forType: .string)
        #else
        UIPasteboard.general.string = withPrompt
        #endif

        print("✅ Copied with human AI prompt to clipboard")
        
        saveStatus = "✅ Copied with prompt"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveStatus = ""
        }
    }

    private func copyWithPromptJSON() {
        let fullVersion = generateFullVersion()
        let promptService = YouTubeAIPrompts()
        let withPrompt = promptService.getAIPromptForOutlineSectionsJSON(fullVersion: fullVersion)

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(withPrompt, forType: .string)
        #else
        UIPasteboard.general.string = withPrompt
        #endif

        print("✅ Copied with JSON AI prompt to clipboard")
        
        saveStatus = "✅ Copied JSON prompt"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveStatus = ""
        }
    }
    
    private func generateFullVersion() -> String {
        var output = """
        VIDEO: \(video.title)
        URL: https://youtube.com/watch?v=\(video.videoId)
        
        """
        
        for (index, section) in breakdown.sections.enumerated() {
            output += "=== SECTION \(index + 1): \(section.displayName) ===\n\n"
            
            // Byron's Input
            if let belief = section.beliefInstalled, !belief.isEmpty {
                output += "Belief Installed: \(belief)\n\n"
            }
            
            if let notes = section.rawNotes, !notes.isEmpty {
                output += "Your Notes: \(notes)\n\n"
            }
            
            // AI Fields (if present)
            if section.hasAIAnalysis {
                output += "--- AI ANALYSIS ---\n\n"
                
                if let summary = section.aiSummary {
                    output += "Summary: \(summary)\n\n"
                }
                if let purpose = section.aiStrategicPurpose {
                    output += "Strategic Purpose: \(purpose)\n\n"
                }
                if let mechanism = section.aiMechanism {
                    output += "Mechanism: \(mechanism)\n\n"
                }
                if let inputs = section.aiInputsRecipe {
                    output += "Inputs Recipe: \(inputs)\n\n"
                }
                if let flags = section.aiBSFlags {
                    output += "BS Flags: \(flags)\n\n"
                }
                if let archetype = section.aiArchetype {
                    output += "Archetype: \(archetype)\n\n"
                }
            }
            
            // Patterns
            let patternsInSection = breakdown.allMarkedPatterns.filter { $0.sectionId == section.id }
            if !patternsInSection.isEmpty {
                let uniqueTypes = Array(Set(patternsInSection.map { $0.type.rawValue })).sorted()
                output += "Patterns Used: \(uniqueTypes.joined(separator: ", "))\n\n"
            }
            
            // Transcript
            output += "TRANSCRIPT:\n"
            let sentencesInSection = getSentencesForSection(section)
            for sentence in sentencesInSection {
                let patterns = breakdown.allMarkedPatterns.filter { $0.sentenceIds.contains(sentence.id) }
                if !patterns.isEmpty {
                    let patternTags = patterns.map { "[\($0.type.rawValue)]" }.joined(separator: " ")
                    output += "\(patternTags) \(sentence.text)\n"
                } else {
                    output += "\(sentence.text)\n"
                }
            }
            
            output += "\n"
        }
        
        return output
    }
    
    private func getSentencesForSection(_ section: OutlineSection) -> [ScriptSentence] {
        guard let startIndex = breakdown.sentences.firstIndex(where: { $0.id == section.startSentenceId }) else {
            return []
        }
        
        if let endSentenceId = section.endSentenceId,
           let endIndex = breakdown.sentences.firstIndex(where: { $0.id == endSentenceId }) {
            return Array(breakdown.sentences[startIndex...endIndex])
        } else {
            // Find next section
            if let currentIdx = breakdown.sections.firstIndex(where: { $0.id == section.id }),
               currentIdx + 1 < breakdown.sections.count {
                let nextSection = breakdown.sections[currentIdx + 1]
                if let nextStartIndex = breakdown.sentences.firstIndex(where: { $0.id == nextSection.startSentenceId }) {
                    return Array(breakdown.sentences[startIndex..<nextStartIndex])
                }
            }
            // Last section - go to end
            return Array(breakdown.sentences[startIndex...])
        }
    }
    
    // MARK: - AI Analysis Import
    
    private func aiAnalysisImportSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { importAIAnalysisFromPasteboard() }) {
                HStack {
                    Image(systemName: "arrow.down.doc")
                    Text("Import AI Analysis from Clipboard")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(6)
            }
            
            if !importStatus.isEmpty {
                Text(importStatus)
                    .font(.caption)
                    .foregroundColor(importStatus.contains("✅") ? .green : .red)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func importAIAnalysisFromPasteboard() {
        let pastedText: String
        
        #if os(macOS)
        pastedText = NSPasteboard.general.string(forType: .string) ?? ""
        #else
        pastedText = UIPasteboard.general.string ?? ""
        #endif
        
        guard !pastedText.isEmpty else {
            importStatus = "❌ Clipboard is empty"
            return
        }
        
        print("📋 Attempting to parse AI analysis JSON...")
        print("📋 First 100 chars: \(String(pastedText.prefix(100)))")
        
        do {
            let decoder = JSONDecoder()
            let jsonData = pastedText.data(using: .utf8)!
            let analysis = try decoder.decode(AIAnalysisJSON.self, from: jsonData)
            
            print("✅ Parsed JSON: \(analysis.sections.count) sections")
            var updatedBreakdown = breakdown
            var updatedCount = 0
            for sectionAnalysis in analysis.sections {
                let index = sectionAnalysis.sectionNumber - 1
                guard index >= 0 && index < updatedBreakdown.sections.count else {
                    print("⚠️ Section number \(sectionAnalysis.sectionNumber) out of range (have \(updatedBreakdown.sections.count) sections)")
                    continue
                }
                
                print("📝 Updating section \(sectionAnalysis.sectionNumber):")
                print("   - Title: \(sectionAnalysis.aiTitle ?? "nil")")
                print("   - Archetype: \(sectionAnalysis.aiArchetype ?? "nil")")
                
                updatedBreakdown.sections[index].aiTitle = sectionAnalysis.aiTitle
                updatedBreakdown.sections[index].aiSummary = sectionAnalysis.aiSummary
                updatedBreakdown.sections[index].aiStrategicPurpose = sectionAnalysis.aiStrategicPurpose
                updatedBreakdown.sections[index].aiMechanism = sectionAnalysis.aiMechanism
                updatedBreakdown.sections[index].aiInputsRecipe = sectionAnalysis.aiInputsRecipe
                updatedBreakdown.sections[index].aiBSFlags = sectionAnalysis.aiBSFlags
                updatedBreakdown.sections[index].aiArchetype = sectionAnalysis.aiArchetype
                
                
                print("🔍 VERIFY: breakdown.sections[\(index)].aiTitle = \(updatedBreakdown.sections[index].aiTitle ?? "NIL")")
                print("🔍 VERIFY: breakdown.sections[\(index)].aiArchetype = \(updatedBreakdown.sections[index].aiArchetype ?? "NIL")")
                // Expand AI section for newly imported sections
                showingAIForSection.insert(updatedBreakdown.sections[index].id)
                
                updatedCount += 1
            }
            
            importStatus = "✅ Imported AI analysis for \(updatedCount) section(s)"
            breakdown = updatedBreakdown

            // Save to Firebase
            Task {
                await saveToFirebase(showStatus: true, statusMessage: "Imported \(updatedCount) sections", updatedBreakdown: updatedBreakdown)
            }
                        print("✅ Imported AI analysis for \(updatedCount) sections")
            
        } catch let decodingError as DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
                importStatus = "❌ Missing field: \(key.stringValue)"
                print("❌ Missing key: \(key.stringValue) at path: \(context.codingPath)")
            case .typeMismatch(let type, let context):
                importStatus = "❌ Type mismatch: expected \(type)"
                print("❌ Type mismatch: \(type) at path: \(context.codingPath)")
            case .valueNotFound(let type, let context):
                importStatus = "❌ Value not found: \(type)"
                print("❌ Value not found: \(type) at path: \(context.codingPath)")
            case .dataCorrupted(let context):
                importStatus = "❌ Data corrupted: \(context.debugDescription)"
                print("❌ Data corrupted: \(context)")
            @unknown default:
                importStatus = "❌ Unknown decoding error"
                print("❌ Unknown decoding error: \(decodingError)")
            }
        } catch {
            importStatus = "❌ Failed to parse JSON: \(error.localizedDescription)"
            print("❌ Error parsing AI analysis JSON: \(error)")
        }
    }
}

// MARK: - Section Editor Sheet

struct SectionEditorSheet: View {
    let section: OutlineSection
    @Binding var breakdown: ScriptBreakdown
    let video: YouTubeVideo
    let onSave: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var editedName: String
    @State private var editedRawNotes: String
    @State private var editedBeliefInstalled: String
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    
    init(section: OutlineSection, breakdown: Binding<ScriptBreakdown>, video: YouTubeVideo, onSave: @escaping () -> Void) {
        self.section = section
        self._breakdown = breakdown
        self.video = video
        self.onSave = onSave
        self._editedName = State(initialValue: section.name)
        self._editedRawNotes = State(initialValue: section.rawNotes ?? "")
        self._editedBeliefInstalled = State(initialValue: section.beliefInstalled ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Section Title") {
                    TextField("Section name", text: $editedName)
                }
                
                Section("Belief Installed") {
                    Text("By the end of this section, viewer believes/feels:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $editedBeliefInstalled)
                        .frame(minHeight: 60)
                }
                
                Section("Your Raw Notes") {
                    Text("Include skepticism, BS flags, manipulation observations:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $editedRawNotes)
                        .frame(minHeight: 120)
                }
                
                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Section")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveChanges() }
                    }
                    .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.3)
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Saving...")
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.9))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
    
    private func saveChanges() async {
        guard let index = breakdown.sections.firstIndex(where: { $0.id == section.id }) else {
            saveError = "Section not found"
            return
        }
        
        isSaving = true
        saveError = nil
        
        print("💾 Saving section changes:")
        print("   - Name: '\(editedName)'")
        print("   - Belief: '\(editedBeliefInstalled.isEmpty ? "(empty)" : editedBeliefInstalled)'")
        print("   - Notes: '\(editedRawNotes.isEmpty ? "(empty)" : String(editedRawNotes.prefix(50)))'")
        
        // Update the breakdown
        breakdown.sections[index].name = editedName
        breakdown.sections[index].rawNotes = editedRawNotes.isEmpty ? nil : editedRawNotes
        breakdown.sections[index].beliefInstalled = editedBeliefInstalled.isEmpty ? nil : editedBeliefInstalled
        
        do {
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.saveScriptBreakdown(videoId: video.videoId, breakdown: breakdown)
            print("✅ Saved section edits to Firebase")
            
            // Verify it was saved by loading it back
            if let loadedBreakdown = try await firebaseService.loadScriptBreakdown(videoId: video.videoId) {
                if let loadedSection = loadedBreakdown.sections.first(where: { $0.id == section.id }) {
                    print("✅ Verified saved data:")
                    print("   - Name: '\(loadedSection.name)'")
                    print("   - Belief: '\(loadedSection.beliefInstalled ?? "(nil)")'")
                    print("   - Notes: '\(loadedSection.rawNotes ?? "(nil)")'")
                }
            }
            
            isSaving = false
            onSave()
            dismiss()
        } catch {
            print("❌ Error saving section edits: \(error)")
            saveError = "Failed to save: \(error.localizedDescription)"
            isSaving = false
        }
    }
}

