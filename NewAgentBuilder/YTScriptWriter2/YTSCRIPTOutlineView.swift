//
//  YTSCRIPTOutlineView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/6/25.
//



import SwiftUI

struct YTSCRIPTOutlineView: View {
    @Bindable var script: YTSCRIPT
    @EnvironmentObject var nav: NavigationViewModel
    @State private var showingPasteSheet = false
    @State private var jsonInput = ""
    @State private var parseError: String?
    @State private var showingCopiedAlert = false
    
    var totalTargetWords: Int {
        script.outlineSections
            .filter { !$0.isArchived }
            .reduce(0) { $0 + $1.effectiveWordCount }
    }

    var totalCurrentWords: Int {
        script.outlineSections
            .filter { !$0.isArchived }
            .reduce(0) { $0 + $1.currentWordCount }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                copyPromptSection
                pasteJSONSection
                if !script.outlineSections.isEmpty {
                    statsSection
                    sectionsListSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Outline")
        .sheet(isPresented: $showingPasteSheet) {
            PasteOutlineJSONSheet(
                jsonInput: $jsonInput,
                onParse: parseJSON,
                onDismiss: { showingPasteSheet = false }
            )
        }
        .alert("Prompt Copied", isPresented: $showingCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The prompt has been copied to your clipboard.")
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outline")
                .font(.title2)
                .bold()
            
            HStack {
                
                Text("Generate outline structure from AI, then adjust word counts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    addNewSection()
                } label: {
                    Label("Add Section", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
    }
    private func addNewSection() {
        let newSection = YTSCRIPTOutlineSection2(
            name: "New Section",
            orderIndex: script.outlineSections.count,
            bulletPoints: []
        )
        
        script.outlineSections.append(newSection)
        autoSave()
    }
    
//    private var copyPromptSection: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Label("Step 1: Copy Prompt", systemImage: "1.circle.fill")
//                .font(.headline)
//            
//            Text("Copy and paste into Claude/ChatGPT/Grok to generate outline")
//                .font(.subheadline)
//                .foregroundStyle(.secondary)
//            
//            Button(action: copyPromptToClipboard) {
//                HStack {
//                    Image(systemName: "doc.on.doc")
//                    Text("Copy Outline Prompt")
//                }
//                .frame(maxWidth: .infinity)
//                .padding()
//                .background(Color.accentColor)
//                .foregroundColor(.white)
//                .cornerRadius(8)
//            }
//            .buttonStyle(.plain)
//        }
//        .padding()
//        .background(Color(.tertiarySystemBackground))
//        .cornerRadius(12)
//        .padding(.horizontal)
//    }
    
    private var copyPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Step 1: Copy Prompt", systemImage: "1.circle.fill")
                .font(.headline)
            
            Text("Choose your outline style:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                // Kallaway outline button
                Button {
                    copyPromptToClipboard(style: .kallaway)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "list.number")
                        Text("Kallaway Outline")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(script.writingStyle == .kallaway ? Color.blue : Color(.tertiarySystemBackground))
                    .foregroundColor(script.writingStyle == .kallaway ? .white : .primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Derrick outline button
                Button {
                    copyPromptToClipboard(style: .derrick)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "person.fill")
                        Text("Derrick Outline")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(script.writingStyle == .derrick ? Color.green : Color(.tertiarySystemBackground))
                    .foregroundColor(script.writingStyle == .derrick ? .white : .primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func copyPromptToClipboard(style: WritingStyle) {
        //let prompt = generatePrompt(for: style)
        let prompt = YTSCRIPTOutlinePrompts.generatePrompt(for: style, script: script)
        #if os(iOS)
        UIPasteboard.general.string = prompt
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
        
        showingCopiedAlert = true
    }
    
    private var pasteJSONSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Step 2: Paste AI Response", systemImage: "2.circle.fill")
                .font(.headline)
            
            Text("Paste the JSON outline back here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: { showingPasteSheet = true }) {
                HStack {
                    Image(systemName: "arrow.down.doc")
                    Text(script.outlineSections.isEmpty ? "Paste JSON Outline" : "Replace Outline")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            if let error = parseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var statsSection: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(totalTargetWords) words")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Est. Tgt Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f min", Double(totalTargetWords) / script.wordsPerMinute))
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Current")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(totalCurrentWords) words")
                    .font(.headline)
                    .foregroundColor(totalCurrentWords > 0 ? .green : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Est. Curtent Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f min", Double(totalCurrentWords) / script.wordsPerMinute))
                    .font(.headline)
            }
            
     
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    private var sectionsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Outline Sections")
                    .font(.headline)
                
                Spacer()
                
                CopyButtonAction(label: "Script Text") {
                    copyFullScript()
                    
                }
                
                CopyButtonAction(label: "Script Text With Lines") {
                    copyFullScriptWithLines()
                }
                
                CopyButtonAction(label: "Outline") {
                    copyFullOutline()
                }
                
                
                
//                Button(role: .destructive) {
//                    script.outlineSections = []
//                    autoSave()
//                } label: {
//                    Label("Clear All", systemImage: "trash")
//                        .font(.caption)
//                }
            }
            .padding(.horizontal)
            
            // Active sections
            ForEach(script.outlineSections.filter { !$0.isArchived }.sorted(by: { $0.orderIndex < $1.orderIndex })) { section in
                VStack(spacing: 0) {
                    OutlineSectionCard(
                        script: script,
                        section: section,
                        onTap: {
                            nav.push(.newSectionEditor(script, section.id))
                        },
                        onMoveUp: canMoveUp(section) ? {
                            moveSection(section, direction: -1)
                        } : nil,
                        onMoveDown: canMoveDown(section) ? {
                            moveSection(section, direction: 1)
                        } : nil,
                        onDelete: {
                            deleteSection(section)
                        }
                    )
                    
                    // Archive button below card
                    Button {
                        if let index = script.outlineSections.firstIndex(where: { $0.id == section.id }) {
                            script.outlineSections[index].isArchived = true
                            autoSave()
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal)

            // Archived sections
            if !script.outlineSections.filter({ $0.isArchived }).isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Archived Sections")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 12)
                    
                    ForEach(script.outlineSections.filter { $0.isArchived }) { section in
                        HStack {
                            Text(section.name)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if let index = script.outlineSections.firstIndex(where: { $0.id == section.id }) {
                                    script.outlineSections[index].isArchived = false
                                    autoSave()
                                }
                            } label: {
                                Label("Unarchive", systemImage: "arrow.uturn.backward")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    

  
    private var sectionsListSection2: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Outline Sections")
                    .font(.headline)
                
                Spacer()
                
                Button {
                         copyFullOutline()
                     } label: {
                         Label("Copy Outline", systemImage: "doc.on.doc")
                             .font(.caption)
                     }
                     .buttonStyle(.bordered)
                     .controlSize(.small)
                
                Button(role: .destructive) {
                    script.outlineSections = []
                    autoSave()
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            
            ForEach(script.outlineSections) { section in
                OutlineSectionCard(
                    script: script,
                    section: section,
                    onTap: {
                        nav.push(.newSectionEditor(script, section.id))
                        // TODO: Navigate to section editor
                        print("📝 Navigate to section editor for: \(section.name)")
                    },
                    onMoveUp: canMoveUp(section) ? {
                        moveSection(section, direction: -1)
                    } : nil,
                    onMoveDown: canMoveDown(section) ? {
                        moveSection(section, direction: 1)
                    } : nil,
                    onDelete: {
                        deleteSection(section)
                    }
                )
            }
            .padding(.horizontal)
            ForEach(script.outlineSections.filter { !$0.isArchived }.sorted(by: { $0.orderIndex < $1.orderIndex })) { section in
                HStack {
                    Text(section.name)
                    Spacer()
                    Button {
                        if let index = script.outlineSections.firstIndex(where: { $0.id == section.id }) {
                            script.outlineSections[index].isArchived = true
                            autoSave()
                        }
                    } label: {
                        Image(systemName: "archivebox")
                    }
                }
            }

            // Show archived sections separately
            if !script.outlineSections.filter({ $0.isArchived }).isEmpty {
                Section("Archived Sections") {
                    ForEach(script.outlineSections.filter { $0.isArchived }) { section in
                        HStack {
                            Text(section.name)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if let index = script.outlineSections.firstIndex(where: { $0.id == section.id }) {
                                    script.outlineSections[index].isArchived = false
                                    autoSave()
                                }
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    private func copyFullScript() {
        let activeSections = script.outlineSections
            .filter { !$0.isArchived }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
        
        var fullScript = ""
        
        for section in activeSections {
            // Add section name as header
            fullScript += "\(section.name)\n\n"
            
            // Get current version sentences
            if section.currentVersionIndex >= 0,
               section.currentVersionIndex < section.sectionVersions.count {
                let currentVersion = section.sectionVersions[section.currentVersionIndex]
                
                if !currentVersion.sentences.isEmpty {
                    // Use parsed sentences
                    let sentences = currentVersion.sentences
                        .sorted(by: { $0.orderIndex < $1.orderIndex })
                        .map { $0.text }
                    fullScript += sentences.joined(separator: "\n")
                } else if let polishedText = currentVersion.polishedText, !polishedText.isEmpty {
                    // Fallback to polished text if no sentences
                    fullScript += polishedText
                }
            } else if !section.polishedText.isEmpty {
                // Fallback to section's polished text
                fullScript += section.polishedText
            }
            
            fullScript += "\n\n"
        }
        
        #if os(iOS)
        UIPasteboard.general.string = fullScript
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullScript, forType: .string)
        #endif
    }

    private func copyFullScriptWithLines() {
        let activeSections = script.outlineSections
            .filter { !$0.isArchived }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
        
        var fullScript = ""
        var globalSentenceNumber = 1
        
        for section in activeSections {
            // Add section name as header
            fullScript += "\(section.name)\n\n"
            
            // Get current version sentences
            if section.currentVersionIndex >= 0,
               section.currentVersionIndex < section.sectionVersions.count {
                let currentVersion = section.sectionVersions[section.currentVersionIndex]
                
                if !currentVersion.sentences.isEmpty {
                    // Use parsed sentences with line numbers
                    let sentences = currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex })
                    for sentence in sentences {
                        fullScript += "S\(globalSentenceNumber): \(sentence.text)\n"
                        globalSentenceNumber += 1
                    }
                } else if let polishedText = currentVersion.polishedText, !polishedText.isEmpty {
                    // Fallback: split polished text by newlines and number
                    let lines = polishedText.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    
                    for line in lines {
                        fullScript += "S\(globalSentenceNumber): \(line)\n"
                        globalSentenceNumber += 1
                    }
                }
            } else if !section.polishedText.isEmpty {
                // Fallback: split section polished text
                let lines = section.polishedText.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                for line in lines {
                    fullScript += "S\(globalSentenceNumber): \(line)\n"
                    globalSentenceNumber += 1
                }
            }
            
            fullScript += "\n"
        }
        
        #if os(iOS)
        UIPasteboard.general.string = fullScript
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullScript, forType: .string)
        #endif
    }
    private func copyFullOutline() {
        let outlineText = script.outlineSections.map { section in
            var sectionText = "\(section.name)\n"
            if !section.bulletPoints.isEmpty {
                sectionText += section.bulletPoints.map { "  • \($0)" }.joined(separator: "\n")
            }
            return sectionText
        }.joined(separator: "\n\n")
        
        #if os(iOS)
        UIPasteboard.general.string = outlineText
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outlineText, forType: .string)
        #endif
    }
    
//    private func copyPromptToClipboard() {
//        let prompt = generatePrompt()
//        
//        #if os(iOS)
//        UIPasteboard.general.string = prompt
//        #else
//        NSPasteboard.general.clearContents()
//        NSPasteboard.general.setString(prompt, forType: .string)
//        #endif
//        
//        showingCopiedAlert = true
//    }
    private func generatePrompt(for style: WritingStyle) -> String {
        switch style {
        case .kallaway:
            return generateKallawayOutlinePrompt()
        case .derrick:
            return generateDerrickOutlinePrompt()
        default:
            return generateKallawayOutlinePrompt() // fallback
        }
    }
    
    private func generateDerrickOutlinePrompt() -> String {
        let pointsText = script.researchPoints.enumerated().map { index, point in
            """
            ### Point \(index + 1): \(point.title)
            \(point.rawNotes)
            """
        }.joined(separator: "\n\n")
        
        let angleText: String
        if !script.manualAngle.isEmpty {
            angleText = "SELECTED ANGLE:\n\(script.manualAngle)\n\n"
        } else if let selectedAngle = script.generatedAngles.first(where: { $0.id == script.selectedAngleId }) {
            angleText = """
            SELECTED ANGLE:
            - Statement: \(selectedAngle.angleStatement)
            - Nuke Point: \(selectedAngle.nukePoint)
            
            """
        } else {
            angleText = ""
        }
        
        return """
        You are creating a YouTube outline in DERRICK'S OWNERSHIP-DENSE STYLE.
        
        CONTEXT:
        - Mission: \(script.objective)
        - Target Emotion: \(script.targetEmotion)
        - Audience: \(script.audienceNotes)
        - Target Duration: \(String(format: "%.1f", script.targetMinutes)) minutes
        
        \(angleText)RESEARCH POINTS (YOUR unique observations):
        \(pointsText)
        
        DERRICK STYLE REQUIREMENTS:
        🎯 HIGH OWNERSHIP DENSITY - This must be YOUR specific story:
        - Use named elements (e.g., "DD stand", "South Georgia property", specific buck names)
        - Show time investment ("20 years managing", "this season")
        - Include YOUR specific data ("20 deer on 200 acres", "500-yard commute")
        - Build personal journey ("I discovered", "I was wrong about", "Here's what surprised me")
        - Make it UNCOPYABLE - requires YOUR footage and property access
        
        OUTLINE STRUCTURE:
        1. Hook with YOUR specific mystery/problem on YOUR property
        2. Investigation of what YOU found with YOUR thermal drone
        3. Discovery/reveal moment (what YOUR data showed)
        4. Diagnosis (what it means for YOUR property)
        5. Resolution or next steps (what YOU will do)
        
        SECTION NAMING STYLE:
        - "The DD Stand Mystery" (not "Understanding Stand Location")
        - "The 500-Yard Commute I Discovered" (not "Deer Travel Patterns")
        - "Why My 20-Year Strategy Failed" (not "Food Plot Principles")
        - Always use "I", "My", specific names/numbers
        
        OWNERSHIP CHECKLIST for each section:
        ✓ Named specific (stand, property, buck, or measurement)
        ✓ Personal investment visible (years, attempts, failures)
        ✓ YOUR unique footage/data mentioned
        ✓ Could NOT be made by another creator without YOUR access
        
        OUTPUT FORMAT:
        Return ONLY valid JSON:
        
        {
          "outline": [
            {
              "id": 1,
              "section_name": "YOUR specific section name with named elements",
              "key_points": [
                "Bullet with YOUR specific detail",
                "Another point showing YOUR investment",
                "Point that requires YOUR footage"
              ]
            }
          ]
        }
        
        Generate 5-7 sections with HIGH ownership density.
        Every section name must include YOUR specific context.
        """
    }
    
    private func generateKallawayOutlinePrompt() -> String {
        // Format research points
        let pointsText = script.researchPoints.enumerated().map { index, point in
            """
            ### Point \(index + 1): \(point.title)
            \(point.rawNotes)
            """
        }.joined(separator: "\n\n")
        
        // Get selected angle if exists
        let angleText: String
        if !script.manualAngle.isEmpty {
            angleText = "SELECTED ANGLE:\n\(script.manualAngle)\n\n"
        } else if let selectedAngle = script.generatedAngles.first(where: { $0.id == script.selectedAngleId }) {
            angleText = """
            SELECTED ANGLE:
            - Statement: \(selectedAngle.angleStatement)
            - Nuke Point: \(selectedAngle.nukePoint)
            - Hook Type: \(selectedAngle.hookType)
            - Supporting Points: \(selectedAngle.supportingPoints.joined(separator: ", "))
            
            """
        } else {
            angleText = ""
        }
        
        return """
        You are creating a YouTube video outline based on thermal drone research findings.
        
        CONTEXT:
        - Mission: \(script.objective)
        - Target Emotion: \(script.targetEmotion)
        - Audience: \(script.audienceNotes)
        - Target Duration: \(String(format: "%.1f", script.targetMinutes)) minutes
        
        \(angleText)RESEARCH POINTS:
        \(pointsText)
        
        YOUR TASK:
        Create a video outline with 5-8 sections that tells a compelling story.
        
        REQUIREMENTS:
        1. Start with Hook/Intro section
        2. Arrange middle sections using strong storytelling (consider 2-1-3-4 if applicable)
        3. End with Outro section
        4. Each section needs:
           - Clear section name
           - 3-5 key bullet points of what to cover
        5. DO NOT include word counts or time estimates (I'll set those)
        6. Merge related research points if it makes sense
        7. Use the selected angle to guide the story structure
        
        OUTPUT FORMAT:
        Return ONLY valid JSON in this exact structure:
        
        {
          "outline": [
            {
              "id": 1,
              "section_name": "Hook/Intro",
              "key_points": [
                "Context & click confirmation",
                "State common belief",
                "Contrast with contrarian take from data",
                "Show credibility (thermal drone study)",
                "Lay out plan for video"
              ]
            },
            {
              "id": 2,
              "section_name": "Section title here",
              "key_points": [
                "Bullet point 1",
                "Bullet point 2",
                "Bullet point 3"
              ]
            }
          ]
        }
        
        Generate the complete outline and return as JSON.
        """
    }
    
    private func parseJSON() {
        parseError = nil
        
        guard !jsonInput.isEmpty else {
            parseError = "Please paste the JSON response"
            return
        }
        
        // Clean input
        var cleanedInput = jsonInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedInput.hasPrefix("```json") {
            cleanedInput = cleanedInput.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedInput.hasPrefix("```") {
            cleanedInput = cleanedInput.replacingOccurrences(of: "```", with: "")
        }
        cleanedInput = cleanedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedInput.data(using: .utf8) else {
            parseError = "Could not convert input to data"
            return
        }
        
        do {
            let response = try JSONDecoder().decode(OutlineResponse.self, from: data)
            
            // Convert to YTSCRIPTOutlineSection2
            script.outlineSections = response.outline.map { outlineItem in
                YTSCRIPTOutlineSection2(
                    id: UUID(),
                    name: outlineItem.section_name,
                    orderIndex: outlineItem.id - 1,
                    targetWordCount: nil,
                    bulletPoints: outlineItem.key_points
                )
            }
            
            showingPasteSheet = false
            jsonInput = ""
            autoSave()
            
            print("✅ Parsed \(response.outline.count) outline sections")
        } catch {
            parseError = "JSON parsing failed: \(error.localizedDescription)"
            print("❌ Parse error: \(error)")
        }
    }
    
    // FIXED: All these now use YTSCRIPTOutlineSection2
    private func canMoveUp(_ section: YTSCRIPTOutlineSection2) -> Bool {
        section.orderIndex > 0
    }
    
    private func canMoveDown(_ section: YTSCRIPTOutlineSection2) -> Bool {
        section.orderIndex < script.outlineSections.count - 1
    }
    
    private func moveSection(_ section: YTSCRIPTOutlineSection2, direction: Int) {
        guard let index = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < script.outlineSections.count else { return }
        
        script.outlineSections.move(fromOffsets: IndexSet(integer: index), toOffset: newIndex > index ? newIndex + 1 : newIndex)
        reindexSections()
        autoSave()
    }
    
    private func deleteSection(_ section: YTSCRIPTOutlineSection2) {
        script.outlineSections.removeAll { $0.id == section.id }
        reindexSections()
        autoSave()
    }
    
    private func reindexSections() {
        for (index, section) in script.outlineSections.enumerated() {
            script.outlineSections[index].orderIndex = index
        }
    }
    
    private func autoSave() {
        Task {
            do {
                try await YTSCRIPTManager.shared.updateScript(script)
            } catch {
                print("❌ Auto-save failed: \(error)")
            }
        }
    }
}

// MARK: - Outline Section Card


// MARK: - Outline Section Card

struct OutlineSectionCard: View {
    @Bindable var script: YTSCRIPT
    var section: YTSCRIPTOutlineSection2
    let onTap: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    let onDelete: () -> Void
    
    @State private var showingWordCountEdit = false
    @State private var customWordCount: String = ""
    @State private var showingBulletEdit = false
    @State private var editingBulletIndex: Int?
    @State private var bulletText: String = ""
    @State private var showingNameEdit = false
    @State private var sectionName: String = ""
    @State private var showingAddBullet = false
    @State private var newBulletText: String = ""
    
    var sectionIndex: Int {
        script.outlineSections.firstIndex(where: { $0.id == section.id }) ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            bulletPointsList
            addBulletButton
            actionButtons
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .alert("Edit Section Name", isPresented: $showingNameEdit) {
            nameEditAlert
        }
        .alert("Set Target Word Count", isPresented: $showingWordCountEdit) {
            wordCountAlert
        } message: {
            Text("Current: \(section.effectiveWordCount) words")
        }
        .alert("Edit Bullet Point", isPresented: $showingBulletEdit) {
            bulletEditAlert
        }
        .alert("Add Bullet Point", isPresented: $showingAddBullet) {
            addBulletAlert
        }
    }
    
    private var headerRow: some View {
        HStack {
            Text("\(section.orderIndex + 1).")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                // Editable section name
                Button {
                    sectionName = section.name
                    showingNameEdit = true
                } label: {
                    HStack(spacing: 4) {
                        Text(section.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "pencil.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Target:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            customWordCount = String(section.effectiveWordCount)
                            showingWordCountEdit = true
                        } label: {
                            Text("\(section.effectiveWordCount)w")
                                .font(.caption)
                                .fontWeight(.medium)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if section.currentWordCount > 0 {
                        HStack(spacing: 4) {
                            Text("Current:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(section.currentWordCount)w")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            
            Spacer()
            
            moveButtons
        }
    }
    
    private var moveButtons: some View {
        VStack(spacing: 4) {
            if let onMoveUp {
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            if let onMoveDown {
                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var bulletPointsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(section.bulletPoints.enumerated()), id: \.offset) { index, bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(bullet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Edit button
                    Button {
                        editingBulletIndex = index
                        bulletText = bullet
                        showingBulletEdit = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    // Delete button
                    Button {
                        deleteBullet(at: index)
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var addBulletButton: some View {
        Button {
            newBulletText = ""
            showingAddBullet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                Text("Add bullet point")
                    .font(.caption)
            }
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                Label("Edit Section", systemImage: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
            
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    // MARK: - Actions
    
    private func deleteBullet(at index: Int) {
        script.outlineSections[sectionIndex].bulletPoints.remove(at: index)
    }
    
    // MARK: - Alerts
    
    @ViewBuilder
    private var nameEditAlert: some View {
        TextField("Section name", text: $sectionName)
        
        Button("Save") {
            if !sectionName.isEmpty {
                script.outlineSections[sectionIndex].name = sectionName
            }
            showingNameEdit = false
        }
        
        Button("Cancel", role: .cancel) {
            showingNameEdit = false
        }
    }
    
    @ViewBuilder
    private var wordCountAlert: some View {
        TextField("Word count", text: $customWordCount)
            .keyboardType(.numberPad)
        
        Button("Use Default (\(YTSCRIPTOutlineSection2.defaultWordCount(for: section.name)))") {
            script.outlineSections[sectionIndex].targetWordCount = nil
            showingWordCountEdit = false
        }
        
        Button("Set") {
            if let count = Int(customWordCount), count > 0 {
                script.outlineSections[sectionIndex].targetWordCount = count
            }
            showingWordCountEdit = false
        }
        
        Button("Cancel", role: .cancel) {
            showingWordCountEdit = false
        }
    }
    
    @ViewBuilder
    private var bulletEditAlert: some View {
        TextField("Bullet point", text: $bulletText)
        
        Button("Save") {
            if let index = editingBulletIndex, !bulletText.isEmpty {
                script.outlineSections[sectionIndex].bulletPoints[index] = bulletText
            }
            showingBulletEdit = false
            editingBulletIndex = nil
        }
        
        Button("Cancel", role: .cancel) {
            showingBulletEdit = false
            editingBulletIndex = nil
        }
    }
    
    @ViewBuilder
    private var addBulletAlert: some View {
        TextField("New bullet point", text: $newBulletText)
        
        Button("Add") {
            if !newBulletText.isEmpty {
                script.outlineSections[sectionIndex].bulletPoints.append(newBulletText)
            }
            showingAddBullet = false
        }
        
        Button("Cancel", role: .cancel) {
            showingAddBullet = false
        }
    }
}
// MARK: - Paste Sheet

struct PasteOutlineJSONSheet: View {
    @Binding var jsonInput: String
    let onParse: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Paste the JSON outline from your AI assistant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $jsonInput)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .frame(minHeight: 300)
                
                HStack {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Parse JSON") {
                        onParse()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(jsonInput.isEmpty)
                }
            }
            .padding()
            .navigationTitle("Paste Outline JSON")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - JSON Decoding

struct OutlineResponse: Codable {
    let outline: [OutlineItem]
}

struct OutlineItem: Codable {
    let id: Int
    let section_name: String
    let key_points: [String]
}
