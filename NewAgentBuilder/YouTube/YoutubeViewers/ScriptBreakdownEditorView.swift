//
//  ScriptBreakdownEditorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/4/26.
//
//
//import SwiftUI
//import FirebaseFirestore
//
//struct ScriptBreakdownEditorView: View {
//    let video: YouTubeVideo
//    let transcript: String
//    let isFullscreen: Bool
//    
//    @State private var scriptBreakdown: ScriptBreakdown = ScriptBreakdown()
//    @State private var selectedPatternType: PatternType = .tease
//    @State private var isTypingMode = false
//    @State private var isInitialized = false
//    @State private var showingPatternNote = false
//    @State private var showingPatternGuide = false
//    @State private var editingPattern: MarkedPattern?
//    @State private var showingSectionBreakWarning = false
//    @State private var pendingSectionBreakSentenceId: UUID?
//    @State private var typingText = ""
//    @State private var lastSelectedIndex: Int? = nil
//    @State private var showingClearAllConfirmation = false
//    @State private var patternToDelete: MarkedPattern?
//    @State private var sectionBreakToDelete: UUID?
//    
//    @State private var editingSectionId: UUID? = nil
//    @State private var showingImportSection = false
//    @State private var importStatus: String = ""
//    
//    var body: some View {
//        VStack(spacing: 0){
//            VStack(alignment: .leading, spacing: 16) {
//                // Mode selector (Mac/iPad only)
//#if os(macOS)
//                Picker("Mode", selection: $isTypingMode) {
//                    Text("Read").tag(false)
//                    Text("Type (Practice)").tag(true)
//                }
//                .pickerStyle(.segmented)
//                .padding(.bottom, 8)
//#endif
//                
//                // Pattern type selector
//                patternTypeSelector
//                
//                // Transcript reader/typer
//                if isTypingMode {
//                    typingModeView
//                } else {
//                    readingModeView
//                }
//                
//                // Action buttons
//                actionButtons
//                
//                // Current section preview
//                if !scriptBreakdown.sections.isEmpty {
//                    currentSectionPreview
//                }
//            }
//            .padding()
//            if let currentSection = getCurrentSection() {
//                sectionEditorPanel(section: currentSection)
//            }
//        }
//        
//        .task {
//            await loadScriptBreakdown()
//        }
//        .sheet(isPresented: $showingPatternGuide) {
//            PatternReferenceGuide()
//        }
//        .sheet(isPresented: $showingPatternNote) {
//            if let pattern = editingPattern {
//                PatternNoteEditor(pattern: pattern) { updatedPattern in
//                    if let index = scriptBreakdown.allMarkedPatterns.firstIndex(where: { $0.id == updatedPattern.id }) {
//                        scriptBreakdown.allMarkedPatterns[index] = updatedPattern
//                        Task { await saveScriptBreakdown() }
//                    }
//                }
//            }
//        }
//        .alert("Cannot Add Section Break", isPresented: $showingSectionBreakWarning) {
//            Button("Cancel", role: .cancel) {
//                pendingSectionBreakSentenceId = nil
//            }
//            Button("Delete Patterns & Continue", role: .destructive) {
//                if let sentenceId = pendingSectionBreakSentenceId {
//                    deletePatternsCrossingBoundary(at: sentenceId)
//                    pendingSectionBreakSentenceId = nil
//                }
//            }
//        } message: {
//            Text("One or more patterns cross this section boundary. Delete the patterns first, or choose a different location for the section break.")
//        }
//        .alert("Clear All Patterns & Sections?", isPresented: $showingClearAllConfirmation) {
//            Button("Cancel", role: .cancel) { }
//            Button("Clear All", role: .destructive) {
//                performClearAll()
//            }
//        } message: {
//            Text("This will delete all marked patterns and section breaks. The transcript will remain visible. This cannot be undone.")
//        }
//        .confirmationDialog("Delete Pattern?", isPresented: Binding(
//            get: { patternToDelete != nil },
//            set: { if !$0 { patternToDelete = nil } }
//        )) {
//            Button("Delete Pattern", role: .destructive) {
//                if let pattern = patternToDelete {
//                    deletePattern(pattern)
//                }
//            }
//            Button("Cancel", role: .cancel) {
//                patternToDelete = nil
//            }
//        }
//        .confirmationDialog("Delete Section Break?", isPresented: Binding(
//            get: { sectionBreakToDelete != nil },
//            set: { if !$0 { sectionBreakToDelete = nil } }
//        )) {
//            Button("Delete Section Break", role: .destructive) {
//                if let sentenceId = sectionBreakToDelete {
//                    deleteSectionBreak(at: sentenceId)
//                }
//            }
//            Button("Cancel", role: .cancel) {
//                sectionBreakToDelete = nil
//            }
//        } message: {
//            Text("This will merge this section with the previous one.")
//        }
//    }
//    
//    // MARK: - Subviews
//    
//    private var patternTypeSelector: some View {
//        VStack(spacing: 8) {
//            HStack {
//                Text("Select Pattern Type:")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                
//                Spacer()
//                
//                CopyButtonAction(label: "Text & Pattern Guide") {
//                    copyPatternGuidePrompt()
//                }
//                
//                Button(action: { showingPatternGuide = true }) {
//                    Label("Pattern Guide", systemImage: "info.circle")
//                        .font(.caption)
//                }
//                .buttonStyle(.bordered)
//            }
//            
//            ScrollView(.horizontal, showsIndicators: false) {
//                HStack(spacing: 8) {
//                    ForEach(PatternType.allCases, id: \.self) { type in
//                        Button(action: { selectedPatternType = type }) {
//                            HStack(spacing: 4) {
//                                Image(systemName: type.icon)
//                                Text(type.rawValue)
//                            }
//                            .font(.caption)
//                            .padding(.horizontal, 12)
//                            .padding(.vertical, 6)
//                            .background(selectedPatternType == type ? type.color.opacity(0.2) : Color.gray.opacity(0.1))
//                            .foregroundColor(selectedPatternType == type ? type.color : .primary)
//                            .cornerRadius(8)
//                        }
//                        .buttonStyle(.plain)
//                    }
//                }
//            }
//        }
//    }
//    
//    private var readingModeView: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 8) {
//                Text("Select sentences, then mark pattern:")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                
//                ForEach(Array(scriptBreakdown.sentences.enumerated()), id: \.element.id) { index, sentence in
//                    VStack(alignment: .leading, spacing: 4) {
//                        if isSectionBreakBefore(sentenceId: sentence.id) {
//                            sectionBreakDivider(at: sentence.id)
//                        }
//                        sentenceRow(sentence: sentence, index: index)
//                    }
//                }
//            }
//            .padding()
//        }
//        .frame(maxHeight: isFullscreen ? .infinity : 400)
//        .onAppear {
//            if !isInitialized {
//                initializeSentences(from: transcript)
//            }
//        }
//    }
//    
//    private var typingModeView: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Type the transcript as practice (not saved):")
//                .font(.caption)
//                .foregroundColor(.secondary)
//            
//            HStack(alignment: .top, spacing: 12) {
//                VStack(alignment: .leading) {
//                    Text("Original:")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    ScrollView {
//                        Text(transcript)
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                            .padding(8)
//                            .background(Color.gray.opacity(0.05))
//                            .cornerRadius(4)
//                    }
//                    .frame(maxHeight: 200)
//                }
//                .frame(maxWidth: .infinity)
//                
//                VStack(alignment: .leading) {
//                    Text("Your typing:")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    TextEditor(text: $typingText)
//                        .font(.body)
//                        .frame(maxHeight: 200)
//                        .border(Color.gray.opacity(0.3))
//                }
//                .frame(maxWidth: .infinity)
//            }
//            
//            Button(action: markPatternAtCurrentPosition) {
//                Label("Mark \(selectedPatternType.rawValue) Pattern", systemImage: "tag.fill")
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(selectedPatternType.color.opacity(0.2))
//                    .foregroundColor(selectedPatternType.color)
//                    .cornerRadius(8)
//            }
//        }
//    }
//    
//    private func sentenceRow(sentence: ScriptSentence, index: Int) -> some View {
//        HStack(alignment: .center, spacing: 8) {
//            Button(action: { toggleSentenceSelection(sentence.id) }) {
//                Image(systemName: sentence.isSelected ? "checkmark.square.fill" : "square")
//                    .foregroundColor(sentence.isSelected ? .blue : .gray)
//            }
//            .buttonStyle(.plain)
//            
//            let patternsForSentence = scriptBreakdown.allMarkedPatterns.filter { $0.sentenceIds.contains(sentence.id) }
//            if !patternsForSentence.isEmpty {
//                HStack(spacing: 4) {
//                    ForEach(patternsForSentence) { pattern in
//                        Button(action: {
//                            patternToDelete = pattern
//                        }) {
//                            HStack(spacing: 2) {
//                                Image(systemName: pattern.type.icon).font(.caption2)
//                                Text(pattern.type.rawValue).font(.caption2)
//                                Image(systemName: "xmark.circle.fill").font(.caption2)
//                            }
//                            .padding(.horizontal, 6).padding(.vertical, 2)
//                            .background(pattern.type.color.opacity(0.15))
//                            .foregroundColor(pattern.type.color)
//                            .cornerRadius(4)
//                        }
//                        .buttonStyle(.plain)
//                    }
//                }
//            }
//            
//            Text(sentence.text)
//                .font(.body)
//                .frame(maxWidth: .infinity, alignment: .leading)
//        }
//        .padding(.vertical, 4)
//        .padding(.horizontal, 8)
//        .background(sentence.isSelected ? Color.blue.opacity(0.05) : Color.clear)
//        .cornerRadius(4)
//    }
//    
//    private func sectionBreakDivider(at sentenceId: UUID) -> some View {
//        // Find which section starts at this sentence
//        let sectionNumber: Int? = {
//            if let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.startSentenceId == sentenceId }) {
//                return sectionIndex + 1
//            }
//            return nil
//        }()
//        
//        let labelText = sectionNumber.map { "SECTION \($0)" } ?? "SECTION BREAK"
//        
//        return HStack {
//            Rectangle().fill(Color.blue).frame(height: 2)
//            Text(labelText)
//                .font(.caption2)
//                .fontWeight(.bold)
//                .foregroundColor(.blue)
//            Rectangle().fill(Color.blue).frame(height: 2)
//            
//            // Only show delete button if not the first section
//            if let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.startSentenceId == sentenceId }),
//               sectionIndex > 0 {
//                Button(action: {
//                    sectionBreakToDelete = sentenceId
//                }) {
//                    Image(systemName: "trash.circle.fill")
//                        .foregroundColor(.red)
//                        .font(.body)
//                }
//                .buttonStyle(.plain)
//            }
//        }
//        .padding(.vertical, 8)
//    }
//    
//    private var actionButtons: some View {
//        let selectedCount = scriptBreakdown.sentences.filter { $0.isSelected }.count
//        
//        return HStack(spacing: 12) {
//            if selectedCount > 0 {
//                Button(action: markPatternAtCurrentPosition) {
//                    Label("Mark \(selectedCount) as \(selectedPatternType.rawValue)", systemImage: "tag.fill")
//                        .font(.caption)
//                }
//                .buttonStyle(.borderedProminent)
//                .tint(selectedPatternType.color)
//                
//                if selectedCount == 1 {
//                    Button(action: markSectionBreak) {
//                        Label("Section Break Above", systemImage: "scissors")
//                            .font(.caption)
//                    }
//                    .buttonStyle(.bordered)
//                }
//                
//                Button(action: deselectAll) {
//                    Label("Deselect All", systemImage: "xmark")
//                        .font(.caption)
//                }
//                .buttonStyle(.bordered)
//            } else {
//                Text("Select sentences to mark them")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//            }
//            
//            Button(action: { showingClearAllConfirmation = true }) {
//                Label("Clear All", systemImage: "trash")
//                    .font(.caption)
//            }
//            .buttonStyle(.bordered)
//            .tint(.red)
//            
//            Button(action: { Task { await saveScriptBreakdown() } }) {
//                Label("Save", systemImage: "square.and.arrow.down")
//                    .font(.caption)
//            }
//            .buttonStyle(.bordered)
//        }
//    }
//    
//    private var currentSectionPreview: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            Text("Current Section: \(scriptBreakdown.sections.last?.name ?? "Unknown")")
//                .font(.subheadline)
//                .fontWeight(.medium)
//            
//            if let lastSection = scriptBreakdown.sections.last {
//                let patternsInSection = scriptBreakdown.allMarkedPatterns.filter { $0.sectionId == lastSection.id }
//                if !patternsInSection.isEmpty {
//                    ScrollView(.horizontal, showsIndicators: false) {
//                        HStack(spacing: 8) {
//                            ForEach(patternsInSection) { pattern in
//                                Button(action: {
//                                    patternToDelete = pattern
//                                }) {
//                                    HStack(spacing: 4) {
//                                        Image(systemName: pattern.type.icon)
//                                            .foregroundColor(pattern.type.color)
//                                        Text(pattern.type.rawValue)
//                                            .font(.caption2)
//                                        Image(systemName: "xmark.circle.fill")
//                                            .font(.caption2)
//                                    }
//                                    .padding(.horizontal, 8)
//                                    .padding(.vertical, 4)
//                                    .background(pattern.type.color.opacity(0.1))
//                                    .cornerRadius(4)
//                                }
//                                .buttonStyle(.plain)
//                            }
//                        }
//                    }
//                }
//            }
//        }
//        .padding()
//        .background(Color.blue.opacity(0.05))
//        .cornerRadius(8)
//    }
//    
//    // MARK: - Actions
//    
//    private func loadScriptBreakdown() async {
//        do {
//            let firebaseService = YouTubeFirebaseService()
//            if let loadedBreakdown = try await firebaseService.loadScriptBreakdown(videoId: video.videoId) {
//                scriptBreakdown = loadedBreakdown
//                isInitialized = !loadedBreakdown.sentences.isEmpty
//                print("✅ Loaded script breakdown with \(loadedBreakdown.sentences.count) sentences")
//            }
//        } catch {
//            print("❌ Error loading script breakdown: \(error)")
//        }
//    }
//    
//    private func initializeSentences(from transcript: String) {
//        let sentences = SentenceParser.parse(transcript)
//        
//        scriptBreakdown.sentences = sentences.map { ScriptSentence(text: $0) }
//        
//        if let firstSentence = scriptBreakdown.sentences.first {
//            scriptBreakdown.sections.append(OutlineSection(
//                startSentenceId: firstSentence.id,
//                name: "Section 1"
//            ))
//        }
//        
//        isInitialized = true
//    }
//    
//    private func sectionEditorPanel(section: OutlineSection) -> some View {
//        // ✅ Always bind to the SOURCE OF TRUTH (scriptBreakdown.sections), not the passed-in copy
//        guard let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.id == section.id }) else {
//            return AnyView(EmptyView())
//        }
//
//        let nameBinding = Binding<String>(
//            get: { scriptBreakdown.sections[sectionIndex].name },
//            set: { scriptBreakdown.sections[sectionIndex].name = $0 }
//        )
//
//        let rawNotesBinding = Binding<String>(
//            get: { scriptBreakdown.sections[sectionIndex].rawNotes ?? "" },
//            set: { scriptBreakdown.sections[sectionIndex].rawNotes = $0.isEmpty ? nil : $0 }
//        )
//
//        let beliefBinding = Binding<String>(
//            get: { scriptBreakdown.sections[sectionIndex].beliefInstalled ?? "" },
//            set: { scriptBreakdown.sections[sectionIndex].beliefInstalled = $0.isEmpty ? nil : $0 }
//        )
//
//        return AnyView(
//            VStack(alignment: .leading, spacing: 12) {
////                HStack {
////                    CopyButtonAction(label: "Outline") {
////                        copyOutline()
////                    }
////                    CopyButtonAction(label: "Full Version") {
////                        copyFullVersion()
////                    }
////                    CopyButtonAction(label: "Human") {
////                        copyWithPrompt()
////                    }
////                    CopyButtonAction(label: "JSON") {
////                        copyWithPromptJSON()
////                    }
////                }
////                
////                aiAnalysisImportSection()
//                
//                Text("SECTION \(getSectionNumber(scriptBreakdown.sections[sectionIndex]))")
//                    .font(.caption)
//                    .fontWeight(.bold)
//                    .foregroundColor(.blue)
//              
//                TextField("Section Title", text: nameBinding)
//                    .textFieldStyle(.roundedBorder)
//                    .font(.subheadline)
//                    .onChange(of: nameBinding.wrappedValue) { _ in
//                        Task { await saveScriptBreakdown() }
//                    }
//
//                VStack(alignment: .leading, spacing: 4) {
//                    HStack(spacing: 4) {
//                        Image(systemName: OutlineSection.FieldType.rawNotes.icon)
//                            .foregroundColor(OutlineSection.FieldType.rawNotes.color)
//                        Text("Your Notes:")
//                    }
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//
//                    TextEditor(text: rawNotesBinding)
//                        .frame(height: 60)
//                        .font(.caption)
//                        .border(Color.gray.opacity(0.3))
//                        .onChange(of: rawNotesBinding.wrappedValue) { _ in
//                            Task { await saveScriptBreakdown() }
//                        }
//                }
//
//                VStack(alignment: .leading, spacing: 4) {
//                    HStack(spacing: 4) {
//                        Image(systemName: OutlineSection.FieldType.beliefInstalled.icon)
//                            .foregroundColor(OutlineSection.FieldType.beliefInstalled.color)
//                        Text("Belief Installed:")
//                    }
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//
//                    TextField("Viewer now believes/feels...", text: beliefBinding)
//                        .textFieldStyle(.roundedBorder)
//                        .font(.caption)
//                        .onChange(of: beliefBinding.wrappedValue) { _ in
//                            Task { await saveScriptBreakdown() }
//                        }
//                }
//
//                let patternsInSection = scriptBreakdown.allMarkedPatterns.filter { $0.sectionId == scriptBreakdown.sections[sectionIndex].id }
//                if !patternsInSection.isEmpty {
//                    HStack {
//                        Text("Patterns:")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//
//                        ForEach(Array(Set(patternsInSection.map { $0.type })), id: \.self) { type in
//                            Text(type.rawValue)
//                                .font(.caption2)
//                                .padding(.horizontal, 6)
//                                .padding(.vertical, 2)
//                                .background(type.color.opacity(0.15))
//                                .foregroundColor(type.color)
//                                .cornerRadius(4)
//                        }
//                    }
//                }
//            }
//            .padding()
//            .background(Color.gray.opacity(0.05))
//            .overlay(
//                Rectangle().frame(height: 1).foregroundColor(Color.blue),
//                alignment: .top
//            )
//        )
//    }
//    
//    private func toggleSentenceSelection(_ sentenceId: UUID) {
//        guard let currentIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == sentenceId }) else { return }
//        
//        let wasSelected = scriptBreakdown.sentences[currentIndex].isSelected
//        
//        // If selecting (not deselecting) and we have a previous selection, do range select
//        if !wasSelected, let lastIndex = lastSelectedIndex, lastIndex != currentIndex {
//            // Select everything between lastIndex and currentIndex (inclusive)
//            let start = min(lastIndex, currentIndex)
//            let end = max(lastIndex, currentIndex)
//            
//            for index in start...end {
//                scriptBreakdown.sentences[index].isSelected = true
//            }
//            
//            // Update last selected to current
//            lastSelectedIndex = currentIndex
//            
//        } else {
//            // Normal toggle (first selection or deselecting)
//            scriptBreakdown.sentences[currentIndex].isSelected.toggle()
//            
//            // Update last selected index
//            if scriptBreakdown.sentences[currentIndex].isSelected {
//                lastSelectedIndex = currentIndex
//            } else {
//                // If we deselected, find the last remaining selection or clear
//                if let lastRemaining = scriptBreakdown.sentences.indices.last(where: { scriptBreakdown.sentences[$0].isSelected }) {
//                    lastSelectedIndex = lastRemaining
//                } else {
//                    lastSelectedIndex = nil
//                }
//            }
//        }
//    }
//    
//    private func markPatternAtCurrentPosition() {
//        let selectedSentenceIds = scriptBreakdown.sentences.filter { $0.isSelected }.map { $0.id }
//        guard !selectedSentenceIds.isEmpty else { return }
//        
//        let currentSectionId = scriptBreakdown.sections.last?.id
//        
//        let pattern = MarkedPattern(
//            type: selectedPatternType,
//            sentenceIds: selectedSentenceIds,
//            sectionId: currentSectionId
//        )
//        
//        scriptBreakdown.allMarkedPatterns.append(pattern)
//        
//        if let lastSectionIndex = scriptBreakdown.sections.indices.last {
//            scriptBreakdown.sections[lastSectionIndex].patternIds.append(pattern.id)
//        }
//        
//        for index in scriptBreakdown.sentences.indices {
//            scriptBreakdown.sentences[index].isSelected = false
//        }
//        lastSelectedIndex = nil
//        Task { await saveScriptBreakdown() }
//    }
//    
//    private func deletePattern(_ pattern: MarkedPattern) {
//        // Remove from allMarkedPatterns
//        scriptBreakdown.allMarkedPatterns.removeAll { $0.id == pattern.id }
//        
//        // Remove from section's patternIds
//        if let sectionId = pattern.sectionId,
//           let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.id == sectionId }) {
//            scriptBreakdown.sections[sectionIndex].patternIds.removeAll { $0 == pattern.id }
//        }
//        
//        patternToDelete = nil
//        Task { await saveScriptBreakdown() }
//    }
//    
//    private func deleteSectionBreak(at sentenceId: UUID) {
//        guard let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.startSentenceId == sentenceId }),
//              sectionIndex > 0 else { return }
//        
//        // Get the patterns from the section being deleted
//        let deletedSection = scriptBreakdown.sections[sectionIndex]
//        let patternsToMove = scriptBreakdown.allMarkedPatterns.filter { $0.sectionId == deletedSection.id }
//        
//        // Move patterns to previous section
//        let previousSection = scriptBreakdown.sections[sectionIndex - 1]
//        for patternIndex in scriptBreakdown.allMarkedPatterns.indices {
//            if patternsToMove.contains(where: { $0.id == scriptBreakdown.allMarkedPatterns[patternIndex].id }) {
//                scriptBreakdown.allMarkedPatterns[patternIndex].sectionId = previousSection.id
//            }
//        }
//        
//        // Extend previous section's end to cover deleted section's range
//        if let endSentenceId = deletedSection.endSentenceId {
//            scriptBreakdown.sections[sectionIndex - 1].endSentenceId = endSentenceId
//        } else {
//            scriptBreakdown.sections[sectionIndex - 1].endSentenceId = nil
//        }
//        
//        // Remove the section
//        scriptBreakdown.sections.remove(at: sectionIndex)
//        
//        sectionBreakToDelete = nil
//        Task { await saveScriptBreakdown() }
//    }
//    
//    private func markSectionBreak() {
//        guard let firstSelectedId = scriptBreakdown.sentences.first(where: { $0.isSelected })?.id else {
//            print("⚠️ No sentence selected for section break")
//            return
//        }
//        
//        guard let sentenceIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == firstSelectedId }),
//              sentenceIndex > 0 else {
//            print("⚠️ Cannot add section break before first sentence")
//            return
//        }
//        
//        let previousSentenceId = scriptBreakdown.sentences[sentenceIndex - 1].id
//        let crossingPatterns = scriptBreakdown.allMarkedPatterns.filter { pattern in
//            pattern.sentenceIds.contains(previousSentenceId) && pattern.sentenceIds.contains(firstSelectedId)
//        }
//        
//        if !crossingPatterns.isEmpty {
//            pendingSectionBreakSentenceId = firstSelectedId
//            showingSectionBreakWarning = true
//            return
//        }
//        
//        if let lastSectionIndex = scriptBreakdown.sections.indices.last {
//            scriptBreakdown.sections[lastSectionIndex].endSentenceId = previousSentenceId
//        }
//        
//        let newSection = OutlineSection(
//            startSentenceId: firstSelectedId,
//            name: "Section \(scriptBreakdown.sections.count + 1)"
//        )
//        
//        scriptBreakdown.sections.append(newSection)
//        scriptBreakdown.lastEditedDate = Date()
//        
//        for index in scriptBreakdown.sentences.indices {
//            scriptBreakdown.sentences[index].isSelected = false
//        }
//        lastSelectedIndex = nil
//        Task { await saveScriptBreakdown() }
//    }
//    
//    private func deletePatternsCrossingBoundary(at sentenceId: UUID) {
//        guard let sentenceIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == sentenceId }),
//              sentenceIndex > 0 else { return }
//        
//        let previousSentenceId = scriptBreakdown.sentences[sentenceIndex - 1].id
//        
//        scriptBreakdown.allMarkedPatterns.removeAll { pattern in
//            pattern.sentenceIds.contains(previousSentenceId) && pattern.sentenceIds.contains(sentenceId)
//        }
//        
//        if let lastSectionIndex = scriptBreakdown.sections.indices.last {
//            scriptBreakdown.sections[lastSectionIndex].endSentenceId = previousSentenceId
//        }
//        
//        let newSection = OutlineSection(
//            startSentenceId: sentenceId,
//            name: "Section \(scriptBreakdown.sections.count + 1)"
//        )
//        
//        scriptBreakdown.sections.append(newSection)
//        scriptBreakdown.lastEditedDate = Date()
//        
//        Task { await saveScriptBreakdown() }
//    }
//    
//    private func deselectAll() {
//        for index in scriptBreakdown.sentences.indices {
//            scriptBreakdown.sentences[index].isSelected = false
//        }
//        lastSelectedIndex = nil
//    }
//    
//    private func performClearAll() {
//        // Clear patterns and sections, but keep sentences
//        scriptBreakdown.allMarkedPatterns.removeAll()
//        scriptBreakdown.sections.removeAll()
//        
//        // Re-add first section
//        if let firstSentence = scriptBreakdown.sentences.first {
//            scriptBreakdown.sections.append(OutlineSection(
//                startSentenceId: firstSentence.id,
//                name: "Section 1"
//            ))
//        }
//        
//        // Deselect all
//        for index in scriptBreakdown.sentences.indices {
//            scriptBreakdown.sentences[index].isSelected = false
//        }
//        lastSelectedIndex = nil
//        
//        Task { await saveScriptBreakdown() }
//    }
//    
//    private func isSectionBreakBefore(sentenceId: UUID) -> Bool {
//        return scriptBreakdown.sections.contains(where: { $0.startSentenceId == sentenceId })
//    }
//    
//    private func saveScriptBreakdown() async {
//        do {
//            let firebaseService = YouTubeFirebaseService()
//            try await firebaseService.saveScriptBreakdown(videoId: video.videoId, breakdown: scriptBreakdown)
//            print("✅ Saved script breakdown")
//        } catch {
//            print("❌ Error saving script breakdown: \(error)")
//        }
//    }
//    
//    private func getCurrentSection() -> OutlineSection? {
//        // 1) If user explicitly picked a section to edit, honor it
//        if let editingSectionId,
//           let section = scriptBreakdown.sections.first(where: { $0.id == editingSectionId }) {
//            return section
//        }
//
//        // 2) If user has sentence(s) selected, infer section from the first selected sentence
//        if let selectedSentence = scriptBreakdown.sentences.first(where: { $0.isSelected }),
//           let inferred = sectionContainingSentenceId(selectedSentence.id) {
//            return inferred
//        }
//
//        // 3) Fallback to last section
//        return scriptBreakdown.sections.last
//    }
//
//    private func sectionContainingSentenceId(_ sentenceId: UUID) -> OutlineSection? {
//        guard let sentenceIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == sentenceId }) else {
//            return nil
//        }
//
//        // Walk sections and find which one owns this sentence index
//        for (i, section) in scriptBreakdown.sections.enumerated() {
//            guard let startIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == section.startSentenceId }) else {
//                continue
//            }
//
//            // Determine end index for this section
//            let endIndex: Int = {
//                if let endId = section.endSentenceId,
//                   let end = scriptBreakdown.sentences.firstIndex(where: { $0.id == endId }) {
//                    return end
//                }
//                if i + 1 < scriptBreakdown.sections.count,
//                   let nextStart = scriptBreakdown.sentences.firstIndex(where: { $0.id == scriptBreakdown.sections[i + 1].startSentenceId }) {
//                    return max(startIndex, nextStart - 1)
//                }
//                return scriptBreakdown.sentences.count - 1
//            }()
//
//            if sentenceIndex >= startIndex && sentenceIndex <= endIndex {
//                return section
//            }
//        }
//
//        return nil
//    }
//
//    private func getSectionNumber(_ section: OutlineSection) -> Int {
//        return (scriptBreakdown.sections.firstIndex(where: { $0.id == section.id }) ?? 0) + 1
//    }
//
//    private func updateSectionName(_ sectionId: UUID, name: String) {
//        if let index = scriptBreakdown.sections.firstIndex(where: { $0.id == sectionId }) {
//            scriptBreakdown.sections[index].name = name
//            Task { await saveScriptBreakdown() }
//        }
//    }
//
//    private func updateSectionNotes(_ sectionId: UUID, notes: String) {
//        if let index = scriptBreakdown.sections.firstIndex(where: { $0.id == sectionId }) {
//            scriptBreakdown.sections[index].rawNotes = notes.isEmpty ? nil : notes
//            Task { await saveScriptBreakdown() }
//        }
//    }
//
//    private func updateSectionBelief(_ sectionId: UUID, belief: String) {
//        if let index = scriptBreakdown.sections.firstIndex(where: { $0.id == sectionId }) {
//            scriptBreakdown.sections[index].beliefInstalled = belief.isEmpty ? nil : belief
//            Task { await saveScriptBreakdown() }
//        }
//    }
//    
//    // MARK: - Export Functions
//
//    private func copyOutline() {
//        let outline = generateOutline()
//        
//        #if os(macOS)
//        let pasteboard = NSPasteboard.general
//        pasteboard.clearContents()
//        pasteboard.setString(outline, forType: .string)
//        #else
//        UIPasteboard.general.string = outline
//        #endif
//        
//        print("✅ Copied outline to clipboard")
//    }
//
//    private func copyFullVersion() {
//        let fullVersion = generateFullVersion()
//        
//        #if os(macOS)
//        let pasteboard = NSPasteboard.general
//        pasteboard.clearContents()
//        pasteboard.setString(fullVersion, forType: .string)
//        #else
//        UIPasteboard.general.string = fullVersion
//        #endif
//        
//        print("✅ Copied full version to clipboard")
//    }
//
//    private func copyWithPrompt() {
//        let fullVersion = generateFullVersion()
//        let promptService = YouTubeAIPrompts()
//        let withPrompt = promptService.getAIPromptForOutlineSectionsHuman(fullVersion: fullVersion)
//
//        #if os(macOS)
//        let pasteboard = NSPasteboard.general
//        pasteboard.clearContents()
//        pasteboard.setString(withPrompt, forType: .string)
//        #else
//        UIPasteboard.general.string = withPrompt
//        #endif
//
//        print("✅ Copied with human AI prompt to clipboard")
//    }
//
//    private func copyWithPromptJSON() {
//        let fullVersion = generateFullVersion()
//        let promptService = YouTubeAIPrompts()
//        let withPrompt = promptService.getAIPromptForOutlineSectionsJSON(fullVersion: fullVersion)
//
//        #if os(macOS)
//        let pasteboard = NSPasteboard.general
//        pasteboard.clearContents()
//        pasteboard.setString(withPrompt, forType: .string)
//        #else
//        UIPasteboard.general.string = withPrompt
//        #endif
//
//        print("✅ Copied with JSON AI prompt to clipboard")
//    }
//    
//    private func copyPatternGuidePrompt() {
//        // Get selected/marked text
//        let selectedText = getSelectedOrMarkedText()
//        
//        // Full script is the transcript
//        let fullScript = transcript
//        
//        // Generate prompt
//        let prompt = YouTubeAIPrompts().copyPatternGuideAnalysisPrompt(
//            selectedText: selectedText,
//            fullScript: fullScript
//        )
//        
//        // Copy to clipboard
//        #if os(macOS)
//        NSPasteboard.general.clearContents()
//        NSPasteboard.general.setString(prompt, forType: .string)
//        #else
//        UIPasteboard.general.string = prompt
//        #endif
//        
//        print("✅ Copied pattern guide analysis prompt to clipboard")
//    }
//
//    private func getSelectedOrMarkedText() -> String {
//        // 1) If user has actively selected sentences (checkboxes), use those
//        let selected = scriptBreakdown.sentences
//            .filter { $0.isSelected }
//            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
//            .filter { !$0.isEmpty }
//
//        if !selected.isEmpty {
//            return selected.joined(separator: " ")
//        }
//
//        // 2) If you’re editing a specific pattern in the sheet, use that pattern’s sentences
//        if let editingPattern {
//            let ids = Set(editingPattern.sentenceIds)
//            let text = scriptBreakdown.sentences
//                .filter { ids.contains($0.id) }
//                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
//                .filter { !$0.isEmpty }
//
//            if !text.isEmpty { return text.joined(separator: " ") }
//        }
//
//        // 3) Fallback: use the most recently created pattern (common “copy what I just marked” behavior)
//        if let lastPattern = scriptBreakdown.allMarkedPatterns.last {
//            let ids = Set(lastPattern.sentenceIds)
//            let text = scriptBreakdown.sentences
//                .filter { ids.contains($0.id) }
//                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
//                .filter { !$0.isEmpty }
//
//            if !text.isEmpty { return text.joined(separator: " ") }
//        }
//
//        return "No text selected or marked yet."
//    }
//
////    private func parseTranscriptIntoSentences(_ text: String) -> [String] {
////        // Split on sentence boundaries
////        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
////            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
////            .filter { !$0.isEmpty }
////        
////        return sentences
////    }
//
//    // MARK: - Outline Generators
//
//    private func generateOutline() -> String {
//        var output = """
//        VIDEO: \(video.title)
//        URL: https://youtube.com/watch?v=\(video.videoId)
//        
//        SECTIONS:
//        
//        """
//        
//        for (index, section) in scriptBreakdown.sections.enumerated() {
//            output += "\(index + 1). \(section.displayName)\n"
//            
//            if let belief = section.beliefInstalled, !belief.isEmpty {
//                output += "   Belief: \(belief)\n"
//            }
//            
//            if let notes = section.rawNotes, !notes.isEmpty {
//                output += "   Notes: \(notes)\n"
//            }
//            
//            let patternsInSection = scriptBreakdown.allMarkedPatterns.filter { $0.sectionId == section.id }
//            if !patternsInSection.isEmpty {
//                let uniqueTypes = Array(Set(patternsInSection.map { $0.type.rawValue })).sorted()
//                output += "   Patterns: \(uniqueTypes.joined(separator: ", "))\n"
//            }
//            
//            output += "\n"
//        }
//        
//        return output
//    }
//
//    private func generateFullVersion() -> String {
//        var output = """
//        VIDEO: \(video.title)
//        URL: https://youtube.com/watch?v=\(video.videoId)
//        
//        """
//        
//        for (index, section) in scriptBreakdown.sections.enumerated() {
//            output += "=== SECTION \(index + 1): \(section.displayName) ===\n\n"
//            
//            if let belief = section.beliefInstalled, !belief.isEmpty {
//                output += "Belief Installed: \(belief)\n\n"
//            }
//            
//            if let notes = section.rawNotes, !notes.isEmpty {
//                output += "Your Notes: \(notes)\n\n"
//            }
//            
//            let patternsInSection = scriptBreakdown.allMarkedPatterns.filter { $0.sectionId == section.id }
//            if !patternsInSection.isEmpty {
//                let uniqueTypes = Array(Set(patternsInSection.map { $0.type.rawValue })).sorted()
//                output += "Patterns Used: \(uniqueTypes.joined(separator: ", "))\n\n"
//            }
//            
//            output += "TRANSCRIPT:\n"
//            let sentencesInSection = getSentencesForSection(section)
//            for sentence in sentencesInSection {
//                let patterns = scriptBreakdown.allMarkedPatterns.filter { $0.sentenceIds.contains(sentence.id) }
//                if !patterns.isEmpty {
//                    let patternTags = patterns.map { "[\($0.type.rawValue)]" }.joined(separator: " ")
//                    output += "\(patternTags) \(sentence.text)\n"
//                } else {
//                    output += "\(sentence.text)\n"
//                }
//            }
//            
//            output += "\n"
//        }
//        
//        return output
//    }
//
//
//    
//    //MARK: - AI IMPORT
//    
//    private func aiAnalysisImportSection() -> some View {
//        VStack(alignment: .leading, spacing: 8) {
//            Button(action: { showingImportSection.toggle() }) {
//                HStack {
//                    Image(systemName: showingImportSection ? "chevron.down" : "chevron.right")
//                    Text("Paste AI Analysis")
//                        .font(.caption)
//                        .fontWeight(.semibold)
//                    Spacer()
//                }
//            }
//            .buttonStyle(.plain)
//            .foregroundColor(.blue)
//            
//            if showingImportSection {
//                VStack(alignment: .leading, spacing: 8) {
//                    Text("Copy JSON output from AI, then click below to import:")
//                        .font(.caption2)
//                        .foregroundColor(.secondary)
//                    
//                    Button(action: { importAIAnalysisFromPasteboard() }) {
//                        HStack {
//                            Image(systemName: "arrow.down.doc")
//                            Text("Import from Clipboard")
//                        }
//                        .frame(maxWidth: .infinity)
//                        .padding(.vertical, 8)
//                        .background(Color.blue.opacity(0.1))
//                        .foregroundColor(.blue)
//                        .cornerRadius(6)
//                    }
//                    
//                    if !importStatus.isEmpty {
//                        Text(importStatus)
//                            .font(.caption2)
//                            .foregroundColor(importStatus.contains("✅") ? .green : .red)
//                            .padding(.top, 4)
//                    }
//                }
//                .padding(12)
//                .background(Color.gray.opacity(0.05))
//                .cornerRadius(8)
//            }
//        }
//    }
//
//    private func importAIAnalysisFromPasteboard() {
//        // Get text from clipboard
//        let pastedText: String
//        
//        #if os(macOS)
//        pastedText = NSPasteboard.general.string(forType: .string) ?? ""
//        #else
//        pastedText = UIPasteboard.general.string ?? ""
//        #endif
//        
//        guard !pastedText.isEmpty else {
//            importStatus = "❌ Clipboard is empty"
//            return
//        }
//        
//        // Try to parse JSON
//        do {
//            let decoder = JSONDecoder()
//            let jsonData = pastedText.data(using: .utf8)!
//            let analysis = try decoder.decode(AIAnalysisJSON.self, from: jsonData)
//            
//            // Update sections with AI analysis
//            var updatedCount = 0
//            for sectionAnalysis in analysis.sections {
//                let index = sectionAnalysis.sectionNumber - 1
//                guard index >= 0 && index < scriptBreakdown.sections.count else {
//                    print("⚠️ Section number \(sectionAnalysis.sectionNumber) out of range")
//                    continue
//                }
//                
//                scriptBreakdown.sections[index].aiTitle = sectionAnalysis.aiTitle
//                scriptBreakdown.sections[index].aiSummary = sectionAnalysis.aiSummary
//                scriptBreakdown.sections[index].aiStrategicPurpose = sectionAnalysis.aiStrategicPurpose
//                scriptBreakdown.sections[index].aiMechanism = sectionAnalysis.aiMechanism
//                scriptBreakdown.sections[index].aiInputsRecipe = sectionAnalysis.aiInputsRecipe
//                scriptBreakdown.sections[index].aiBSFlags = sectionAnalysis.aiBSFlags
//                scriptBreakdown.sections[index].aiArchetype = sectionAnalysis.aiArchetype
//                
//                updatedCount += 1
//            }
//            
//            // Save to Firebase
//            Task {
//                await saveScriptBreakdown()
//                importStatus = "✅ Imported AI analysis for \(updatedCount) section(s)"
//            }
//            
//            print("✅ Imported AI analysis for \(updatedCount) sections")
//            
//        } catch {
//            importStatus = "❌ Failed to parse JSON: \(error.localizedDescription)"
//            print("❌ Error parsing AI analysis JSON: \(error)")
//        }
//    }
//
//    // MARK: - Helper for Transcript Extraction
//
//    private func getSentencesForSection(_ section: OutlineSection) -> [ScriptSentence] {
//        guard let startIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == section.startSentenceId }) else {
//            return []
//        }
//        
//        if let endSentenceId = section.endSentenceId,
//           let endIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == endSentenceId }) {
//            return Array(scriptBreakdown.sentences[startIndex...endIndex])
//        } else {
//            // Find next section
//            if let currentIdx = scriptBreakdown.sections.firstIndex(where: { $0.id == section.id }),
//               currentIdx + 1 < scriptBreakdown.sections.count {
//                let nextSection = scriptBreakdown.sections[currentIdx + 1]
//                if let nextStartIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == nextSection.startSentenceId }) {
//                    return Array(scriptBreakdown.sentences[startIndex..<nextStartIndex])
//                }
//            }
//            // Last section - go to end
//            return Array(scriptBreakdown.sentences[startIndex...])
//        }
//    }
//}
//

import SwiftUI
import FirebaseFirestore

struct ScriptBreakdownEditorView: View {
    let video: YouTubeVideo
    let transcript: String
    let isFullscreen: Bool
    
    @State private var scriptBreakdown: ScriptBreakdown = ScriptBreakdown()
    @State private var selectedPatternType: PatternType = .tease
    @State private var isTypingMode = false
    @State private var isInitialized = false
    @State private var showingPatternNote = false
    @State private var showingPatternGuide = false
    @State private var editingPattern: MarkedPattern?
    @State private var showingSectionBreakWarning = false
    @State private var pendingSectionBreakSentenceId: UUID?
    @State private var typingText = ""
    @State private var lastSelectedIndex: Int? = nil
    @State private var showingClearAllConfirmation = false
    @State private var patternToDelete: MarkedPattern?
    @State private var sectionBreakToDelete: UUID?
    
    @State private var editingSectionId: UUID? = nil
    @State private var showingImportSection = false
    @State private var importStatus: String = ""
    @State private var saveWorkItem: DispatchWorkItem?
    // Section editor height states - REDEFINED
    @State private var sectionEditorHeight: SectionEditorHeight = .collapsed
    
    @StateObject private var exportManager = PatternExportManager()
    @State private var autoExportStatus = ""
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    enum SectionEditorHeight {
        case collapsed  // Just section name bar
        case mid        // Name + all editing fields (notes, belief, patterns)
        case full       // Everything + AI analysis fields
        
        var height: CGFloat? {
            switch self {
            case .collapsed: return 44
            case .mid: return nil // Dynamic based on content
            case .full: return nil // Dynamic, but taller
            }
        }
        
        mutating func cycle() {
            switch self {
            case .collapsed: self = .mid
            case .mid: self = .full
            case .full: self = .collapsed
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0){
            VStack(alignment: .leading, spacing: 12) {
                // Mode selector (Mac only)
#if os(macOS)
                Picker("Mode", selection: $isTypingMode) {
                    Text("Read").tag(false)
                    Text("Type (Practice)").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)
#endif
                
                // Compact header with pattern selector, info, and copy buttons
                HStack(spacing: 12) {
                    Text("Pattern:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Copy selected/marked text button
                    Button(action: { copyPatternGuidePrompt() }) {
                        Image(systemName: "doc.on.doc")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .disabled(scriptBreakdown.sentences.filter { $0.isSelected }.isEmpty && scriptBreakdown.allMarkedPatterns.isEmpty)
                    .opacity(scriptBreakdown.sentences.filter { $0.isSelected }.isEmpty && scriptBreakdown.allMarkedPatterns.isEmpty ? 0.3 : 1.0)
                    
                    Button(action: { showingPatternGuide = true }) {
                        Image(systemName: "info.circle")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                }
                
                // Pattern type selector - horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PatternType.allCases, id: \.self) { type in
                            Button(action: { selectedPatternType = type }) {
                                HStack(spacing: 4) {
                                    Image(systemName: type.icon)
                                    Text(type.rawValue)
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedPatternType == type ? type.color.opacity(0.2) : Color.gray.opacity(0.1))
                                .foregroundColor(selectedPatternType == type ? type.color : .primary)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Transcript reader/typer - THIS IS THE KEY WORKSPACE
                if isTypingMode {
                    typingModeView
                } else {
                    readingModeView
                }
                
                // Action buttons - removed Save, kept Clear
                actionButtons
            }
            .padding()
            
            // Collapsible section editor at bottom
            if let currentSection = getCurrentSection() {
                collapsibleSectionEditor(section: currentSection)
            }
        }
        .navigationTitle(video.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadScriptBreakdown()
        }
        .onChange(of: scriptBreakdown) { _ in
            saveWorkItem?.cancel()
                        
                        // Schedule new work
                        let work = DispatchWorkItem {
                            Task {
                                await saveScriptBreakdown()
                            }
                        }
                        saveWorkItem = work
                        
                        // Execute after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        .sheet(isPresented: $showingPatternGuide) {
            PatternReferenceGuide()
        }
        .sheet(isPresented: $showingPatternNote) {
            if let pattern = editingPattern {
                PatternNoteEditor(pattern: pattern) { updatedPattern in
                    if let index = scriptBreakdown.allMarkedPatterns.firstIndex(where: { $0.id == updatedPattern.id }) {
                        scriptBreakdown.allMarkedPatterns[index] = updatedPattern
                    }
                }
            }
        }
        .alert("Cannot Add Section Break", isPresented: $showingSectionBreakWarning) {
            Button("Cancel", role: .cancel) {
                pendingSectionBreakSentenceId = nil
            }
            Button("Delete Patterns & Continue", role: .destructive) {
                if let sentenceId = pendingSectionBreakSentenceId {
                    deletePatternsCrossingBoundary(at: sentenceId)
                    pendingSectionBreakSentenceId = nil
                }
            }
        } message: {
            Text("One or more patterns cross this section boundary. Delete the patterns first, or choose a different location for the section break.")
        }
        .alert("Clear All Patterns & Sections?", isPresented: $showingClearAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                performClearAll()
            }
        } message: {
            Text("This will delete all marked patterns and section breaks. The transcript will remain visible. This cannot be undone.")
        }
        .confirmationDialog("Delete Pattern?", isPresented: Binding(
            get: { patternToDelete != nil },
            set: { if !$0 { patternToDelete = nil } }
        )) {
            Button("Delete Pattern", role: .destructive) {
                if let pattern = patternToDelete {
                    deletePattern(pattern)
                }
            }
            Button("Cancel", role: .cancel) {
                patternToDelete = nil
            }
        }
        .confirmationDialog("Delete Section Break?", isPresented: Binding(
            get: { sectionBreakToDelete != nil },
            set: { if !$0 { sectionBreakToDelete = nil } }
        )) {
            Button("Delete Section Break", role: .destructive) {
                if let sentenceId = sectionBreakToDelete {
                    deleteSectionBreak(at: sentenceId)
                }
            }
            Button("Cancel", role: .cancel) {
                sectionBreakToDelete = nil
            }
        } message: {
            Text("This will merge this section with the previous one.")
        }
    }
    
    // MARK: - Subviews
    
    private var readingModeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tap sentences to select:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(Array(scriptBreakdown.sentences.enumerated()), id: \.element.id) { index, sentence in
                    VStack(alignment: .leading, spacing: 4) {
                        if isSectionBreakBefore(sentenceId: sentence.id) {
                            sectionBreakDivider(at: sentence.id)
                        }
                        sentenceRow(sentence: sentence, index: index)
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            if !isInitialized {
                initializeSentences(from: transcript)
            }
        }
    }
    
    private var typingModeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type the transcript as practice (not saved):")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
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
                    .frame(height: 150)
                }
                
                VStack(alignment: .leading) {
                    Text("Your typing:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $typingText)
                        .font(.body)
                        .frame(height: 150)
                        .border(Color.gray.opacity(0.3))
                }
            }
            
            Button(action: markPatternAtCurrentPosition) {
                Label("Mark \(selectedPatternType.rawValue) Pattern", systemImage: "tag.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedPatternType.color.opacity(0.2))
                    .foregroundColor(selectedPatternType.color)
                    .cornerRadius(8)
            }
        }
    }
    
    private func sentenceRow(sentence: ScriptSentence, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: { toggleSentenceSelection(sentence.id) }) {
                Image(systemName: sentence.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(sentence.isSelected ? .blue : .gray)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                let patternsForSentence = scriptBreakdown.allMarkedPatterns.filter { $0.sentenceIds.contains(sentence.id) }
                if !patternsForSentence.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(patternsForSentence) { pattern in
                                Button(action: {
                                    patternToDelete = pattern
                                }) {
                                    HStack(spacing: 2) {
                                        Image(systemName: pattern.type.icon).font(.caption2)
                                        Text(pattern.type.rawValue).font(.caption2)
                                        Image(systemName: "xmark.circle.fill").font(.caption2)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(pattern.type.color.opacity(0.15))
                                    .foregroundColor(pattern.type.color)
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(sentence.isSelected ? Color.blue.opacity(0.05) : Color.clear)
        .cornerRadius(4)
    }
    
    private func sectionBreakDivider(at sentenceId: UUID) -> some View {
        let sectionNumber: Int? = {
            if let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.startSentenceId == sentenceId }) {
                return sectionIndex + 1
            }
            return nil
        }()
        
        let labelText = sectionNumber.map { "SECTION \($0)" } ?? "SECTION BREAK"
        
        return HStack {
            Rectangle().fill(Color.blue).frame(height: 2)
            Text(labelText)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.blue)
            Rectangle().fill(Color.blue).frame(height: 2)
            
            if let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.startSentenceId == sentenceId }),
               sectionIndex > 0 {
                Button(action: {
                    sectionBreakToDelete = sentenceId
                }) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var actionButtons: some View {
        let selectedCount = scriptBreakdown.sentences.filter { $0.isSelected }.count
        
        return VStack(spacing: 8) {
            if selectedCount > 0 {
                Button(action: markPatternAtCurrentPosition) {
                    Label("Mark \(selectedCount) as \(selectedPatternType.rawValue)", systemImage: "tag.fill")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedPatternType.color)
                
                HStack(spacing: 8) {
                    if selectedCount == 1 {
                        Button(action: markSectionBreak) {
                            Label("Section Break", systemImage: "scissors")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button(action: deselectAll) {
                        Label("Deselect", systemImage: "xmark")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Just Clear button now (auto-save handles saving)
            Button(action: { showingClearAllConfirmation = true }) {
                Label("Clear All Patterns & Sections", systemImage: "trash")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
    
    // MARK: - Collapsible Section Editor - REDEFINED HEIGHTS
    
    private func collapsibleSectionEditor(section: OutlineSection) -> some View {
        guard let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.id == section.id }) else {
            return AnyView(EmptyView())
        }
        
        let nameBinding = Binding<String>(
            get: { scriptBreakdown.sections[sectionIndex].name },
            set: { scriptBreakdown.sections[sectionIndex].name = $0 }
        )
        
        let rawNotesBinding = Binding<String>(
            get: { scriptBreakdown.sections[sectionIndex].rawNotes ?? "" },
            set: { scriptBreakdown.sections[sectionIndex].rawNotes = $0.isEmpty ? nil : $0 }
        )
        
        let beliefBinding = Binding<String>(
            get: { scriptBreakdown.sections[sectionIndex].beliefInstalled ?? "" },
            set: { scriptBreakdown.sections[sectionIndex].beliefInstalled = $0.isEmpty ? nil : $0 }
        )
        
        return AnyView(
            VStack(spacing: 0) {
                // Header bar (always visible)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sectionEditorHeight.cycle()
                    }
                }) {
                    HStack {
                        Image(systemName: sectionEditorHeight == .collapsed ? "chevron.up" :
                                         sectionEditorHeight == .mid ? "chevron.up" : "chevron.down")
                            .font(.caption)
                        
                        Text("SECTION \(getSectionNumber(scriptBreakdown.sections[sectionIndex])): \(scriptBreakdown.sections[sectionIndex].name)")
                            .font(.caption)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        // Height indicator
                        HStack(spacing: 2) {
                            Circle()
                                .fill(sectionEditorHeight == .collapsed ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Circle()
                                .fill(sectionEditorHeight == .mid ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Circle()
                                .fill(sectionEditorHeight == .full ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                }
                .buttonStyle(.plain)
                
                // Content based on height state
                if sectionEditorHeight == .mid {
                    // MID HEIGHT - All basic editing fields
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Section Title", text: nameBinding)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: OutlineSection.FieldType.rawNotes.icon)
                                        .foregroundColor(OutlineSection.FieldType.rawNotes.color)
                                    Text("Your Notes:")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                
                                TextEditor(text: rawNotesBinding)
                                    .frame(height: 80)
                                    .font(.caption)
                                    .border(Color.gray.opacity(0.3))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: OutlineSection.FieldType.beliefInstalled.icon)
                                        .foregroundColor(OutlineSection.FieldType.beliefInstalled.color)
                                    Text("Belief Installed:")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                
                                TextEditor(text: beliefBinding)
                                    .frame(height: 60)
                                    .font(.caption)
                                    .border(Color.gray.opacity(0.3))
                            }
                            
                            let patternsInSection = scriptBreakdown.allMarkedPatterns.filter { $0.sectionId == scriptBreakdown.sections[sectionIndex].id }
                            if !patternsInSection.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Patterns in Section:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(Array(Set(patternsInSection.map { $0.type })), id: \.self) { type in
                                                Text(type.rawValue)
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(type.color.opacity(0.15))
                                                    .foregroundColor(type.color)
                                                    .cornerRadius(4)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    .frame(maxHeight: 280)
                    
                } else if sectionEditorHeight == .full {
                    // FULL HEIGHT - Everything including AI analysis
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Basic fields
                            TextField("Section Title", text: nameBinding)
                                .textFieldStyle(.roundedBorder)
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: OutlineSection.FieldType.rawNotes.icon)
                                        .foregroundColor(OutlineSection.FieldType.rawNotes.color)
                                    Text("Your Notes:")
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                
                                TextEditor(text: rawNotesBinding)
                                    .frame(height: 100)
                                    .font(.body)
                                    .padding(4)
                                    .border(Color.gray.opacity(0.3))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: OutlineSection.FieldType.beliefInstalled.icon)
                                        .foregroundColor(OutlineSection.FieldType.beliefInstalled.color)
                                    Text("Belief Installed:")
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                
                                TextEditor(text: beliefBinding)
                                    .frame(height: 80)
                                    .font(.body)
                                    .padding(4)
                                    .border(Color.gray.opacity(0.3))
                            }
                            
                            Divider()
                            
                            // AI Analysis Section
                            Text("AI Analysis")
                                .font(.headline)
                                .foregroundColor(.purple)
                            
                            if let aiTitle = scriptBreakdown.sections[sectionIndex].aiTitle {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("AI Title:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(aiTitle)
                                        .font(.body)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.purple.opacity(0.05))
                                        .cornerRadius(4)
                                }
                            }
                            
                            if let aiSummary = scriptBreakdown.sections[sectionIndex].aiSummary {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("AI Summary:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(aiSummary)
                                        .font(.caption)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.purple.opacity(0.05))
                                        .cornerRadius(4)
                                }
                            }
                            
                            if let purpose = scriptBreakdown.sections[sectionIndex].aiStrategicPurpose {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Strategic Purpose:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(purpose)
                                        .font(.caption)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.purple.opacity(0.05))
                                        .cornerRadius(4)
                                }
                            }
                            
                            if let mechanism = scriptBreakdown.sections[sectionIndex].aiMechanism {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Mechanism:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(mechanism)
                                        .font(.caption)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.purple.opacity(0.05))
                                        .cornerRadius(4)
                                }
                            }
                            
                            let patternsInSection = scriptBreakdown.allMarkedPatterns.filter { $0.sectionId == scriptBreakdown.sections[sectionIndex].id }
                            if !patternsInSection.isEmpty {
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Patterns in Section:")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
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
                            }
                        }
                        .padding(12)
                    }
                    .frame(maxHeight: 1800)
                }
            }
            .background(Color.gray.opacity(0.05))
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(Color.blue),
                alignment: .top
            )
        )
    }
    
    // MARK: - Actions
    
    private func loadScriptBreakdown() async {
        do {
            let firebaseService = YouTubeFirebaseService()
            if let loadedBreakdown = try await firebaseService.loadScriptBreakdown(videoId: video.videoId) {
                scriptBreakdown = loadedBreakdown
                isInitialized = !loadedBreakdown.sentences.isEmpty
                print("✅ Loaded script breakdown with \(loadedBreakdown.sentences.count) sentences")
            }
        } catch {
            print("❌ Error loading script breakdown: \(error)")
        }
    }
    
    private func initializeSentences(from transcript: String) {
        let sentences = SentenceParser.parse(transcript)
        
        scriptBreakdown.sentences = sentences.map { ScriptSentence(text: $0) }
        
        if let firstSentence = scriptBreakdown.sentences.first {
            scriptBreakdown.sections.append(OutlineSection(
                startSentenceId: firstSentence.id,
                name: "Section 1"
            ))
        }
        
        isInitialized = true
    }
    
    private func toggleSentenceSelection(_ sentenceId: UUID) {
        guard let currentIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == sentenceId }) else { return }
        
        let wasSelected = scriptBreakdown.sentences[currentIndex].isSelected
        
        if !wasSelected, let lastIndex = lastSelectedIndex, lastIndex != currentIndex {
            let start = min(lastIndex, currentIndex)
            let end = max(lastIndex, currentIndex)
            
            for index in start...end {
                scriptBreakdown.sentences[index].isSelected = true
            }
            
            lastSelectedIndex = currentIndex
            
        } else {
            scriptBreakdown.sentences[currentIndex].isSelected.toggle()
            
            if scriptBreakdown.sentences[currentIndex].isSelected {
                lastSelectedIndex = currentIndex
            } else {
                if let lastRemaining = scriptBreakdown.sentences.indices.last(where: { scriptBreakdown.sentences[$0].isSelected }) {
                    lastSelectedIndex = lastRemaining
                } else {
                    lastSelectedIndex = nil
                }
            }
        }
    }
    
    private func markPatternAtCurrentPosition() {
        let selectedSentenceIds = scriptBreakdown.sentences.filter { $0.isSelected }.map { $0.id }
        guard !selectedSentenceIds.isEmpty else { return }
        
        let currentSectionId = scriptBreakdown.sections.last?.id
        
        let pattern = MarkedPattern(
            type: selectedPatternType,
            sentenceIds: selectedSentenceIds,
            sectionId: currentSectionId
        )
        
        scriptBreakdown.allMarkedPatterns.append(pattern)
        
        if let lastSectionIndex = scriptBreakdown.sections.indices.last {
            scriptBreakdown.sections[lastSectionIndex].patternIds.append(pattern.id)
        }
        
        for index in scriptBreakdown.sentences.indices {
            scriptBreakdown.sentences[index].isSelected = false
        }
        lastSelectedIndex = nil
        
        if selectedPatternType == .fact || selectedPatternType == .phrase {
              Task {
                  await autoExportPattern(pattern)
              }
          }
    }
    
    private func deletePattern(_ pattern: MarkedPattern) {
        scriptBreakdown.allMarkedPatterns.removeAll { $0.id == pattern.id }
        
        if let sectionId = pattern.sectionId,
           let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.id == sectionId }) {
            scriptBreakdown.sections[sectionIndex].patternIds.removeAll { $0 == pattern.id }
        }
        
        patternToDelete = nil
    }
    
    private func deleteSectionBreak(at sentenceId: UUID) {
        guard let sectionIndex = scriptBreakdown.sections.firstIndex(where: { $0.startSentenceId == sentenceId }),
              sectionIndex > 0 else { return }
        
        let deletedSection = scriptBreakdown.sections[sectionIndex]
        let patternsToMove = scriptBreakdown.allMarkedPatterns.filter { $0.sectionId == deletedSection.id }
        
        let previousSection = scriptBreakdown.sections[sectionIndex - 1]
        for patternIndex in scriptBreakdown.allMarkedPatterns.indices {
            if patternsToMove.contains(where: { $0.id == scriptBreakdown.allMarkedPatterns[patternIndex].id }) {
                scriptBreakdown.allMarkedPatterns[patternIndex].sectionId = previousSection.id
            }
        }
        
        if let endSentenceId = deletedSection.endSentenceId {
            scriptBreakdown.sections[sectionIndex - 1].endSentenceId = endSentenceId
        } else {
            scriptBreakdown.sections[sectionIndex - 1].endSentenceId = nil
        }
        
        scriptBreakdown.sections.remove(at: sectionIndex)
        
        sectionBreakToDelete = nil
    }
    
    private func markSectionBreak() {
        guard let firstSelectedId = scriptBreakdown.sentences.first(where: { $0.isSelected })?.id else {
            print("⚠️ No sentence selected for section break")
            return
        }
        
        guard let sentenceIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == firstSelectedId }),
              sentenceIndex > 0 else {
            print("⚠️ Cannot add section break before first sentence")
            return
        }
        
        let previousSentenceId = scriptBreakdown.sentences[sentenceIndex - 1].id
        let crossingPatterns = scriptBreakdown.allMarkedPatterns.filter { pattern in
            pattern.sentenceIds.contains(previousSentenceId) && pattern.sentenceIds.contains(firstSelectedId)
        }
        
        if !crossingPatterns.isEmpty {
            pendingSectionBreakSentenceId = firstSelectedId
            showingSectionBreakWarning = true
            return
        }
        
        if let lastSectionIndex = scriptBreakdown.sections.indices.last {
            scriptBreakdown.sections[lastSectionIndex].endSentenceId = previousSentenceId
        }
        
        let newSection = OutlineSection(
            startSentenceId: firstSelectedId,
            name: "Section \(scriptBreakdown.sections.count + 1)"
        )
        
        scriptBreakdown.sections.append(newSection)
        scriptBreakdown.lastEditedDate = Date()
        
        for index in scriptBreakdown.sentences.indices {
            scriptBreakdown.sentences[index].isSelected = false
        }
        lastSelectedIndex = nil
    }
    
    private func deletePatternsCrossingBoundary(at sentenceId: UUID) {
        guard let sentenceIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == sentenceId }),
              sentenceIndex > 0 else { return }
        
        let previousSentenceId = scriptBreakdown.sentences[sentenceIndex - 1].id
        
        scriptBreakdown.allMarkedPatterns.removeAll { pattern in
            pattern.sentenceIds.contains(previousSentenceId) && pattern.sentenceIds.contains(sentenceId)
        }
        
        if let lastSectionIndex = scriptBreakdown.sections.indices.last {
            scriptBreakdown.sections[lastSectionIndex].endSentenceId = previousSentenceId
        }
        
        let newSection = OutlineSection(
            startSentenceId: sentenceId,
            name: "Section \(scriptBreakdown.sections.count + 1)"
        )
        
        scriptBreakdown.sections.append(newSection)
        scriptBreakdown.lastEditedDate = Date()
    }
    
    private func deselectAll() {
        for index in scriptBreakdown.sentences.indices {
            scriptBreakdown.sentences[index].isSelected = false
        }
        lastSelectedIndex = nil
    }
    
    private func autoExportPattern(_ pattern: MarkedPattern) async {
           do {
               // Get channel info
               let firebaseService = YouTubeFirebaseService()
               let channel = try? await firebaseService.getChannel(channelId: video.channelId)
               let channelName = channel?.name ?? video.channelId
               
               // Get section info
               guard let sectionId = pattern.sectionId,
                     let section = scriptBreakdown.sections.first(where: { $0.id == sectionId }) else {
                   return
               }
               
               // Get sentence text
               let sentenceText = scriptBreakdown.sentences
                   .filter { pattern.sentenceIds.contains($0.id) }
                   .map { $0.text }
                   .joined(separator: " ")
               
               // Create exported pattern
               let exportedPattern = ExportedPattern(
                   videoId: video.videoId,
                   videoTitle: video.title,
                   channelId: video.channelId,
                   channelName: channelName,
                   sectionTitle: section.name,
                   patternType: pattern.type,
                   sentenceText: sentenceText,
                   note: pattern.note,
                   creatorId: video.channelId,
                   creatorName: channelName,
                   originalPatternId: pattern.id
               )
               
               // Export immediately
               try await exportManager.exportPatterns([exportedPattern])
               
               print("✅ Auto-exported \(pattern.type.rawValue)")
               
               // Optional: Show brief status
               autoExportStatus = "✅ \(pattern.type.rawValue) saved"
               Task {
                   try? await Task.sleep(nanoseconds: 2_000_000_000)
                   autoExportStatus = ""
               }
               
           } catch {
               print("❌ Auto-export failed: \(error)")
               autoExportStatus = "❌ Export failed"
           }
       }
    
    private func performClearAll() {
        scriptBreakdown.allMarkedPatterns.removeAll()
        scriptBreakdown.sections.removeAll()
        
        if let firstSentence = scriptBreakdown.sentences.first {
            scriptBreakdown.sections.append(OutlineSection(
                startSentenceId: firstSentence.id,
                name: "Section 1"
            ))
        }
        
        for index in scriptBreakdown.sentences.indices {
            scriptBreakdown.sentences[index].isSelected = false
        }
        lastSelectedIndex = nil
    }
    
    private func isSectionBreakBefore(sentenceId: UUID) -> Bool {
        return scriptBreakdown.sections.contains(where: { $0.startSentenceId == sentenceId })
    }
    
    private func saveScriptBreakdown() async {
        do {
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.saveScriptBreakdown(videoId: video.videoId, breakdown: scriptBreakdown)
            print("✅ Auto-saved script breakdown")
        } catch {
            print("❌ Error saving script breakdown: \(error)")
        }
    }
    
    private func getCurrentSection() -> OutlineSection? {
        if let editingSectionId,
           let section = scriptBreakdown.sections.first(where: { $0.id == editingSectionId }) {
            return section
        }

        if let selectedSentence = scriptBreakdown.sentences.first(where: { $0.isSelected }),
           let inferred = sectionContainingSentenceId(selectedSentence.id) {
            return inferred
        }

        return scriptBreakdown.sections.last
    }

    private func sectionContainingSentenceId(_ sentenceId: UUID) -> OutlineSection? {
        guard let sentenceIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == sentenceId }) else {
            return nil
        }

        for (i, section) in scriptBreakdown.sections.enumerated() {
            guard let startIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == section.startSentenceId }) else {
                continue
            }

            let endIndex: Int = {
                if let endId = section.endSentenceId,
                   let end = scriptBreakdown.sentences.firstIndex(where: { $0.id == endId }) {
                    return end
                }
                if i + 1 < scriptBreakdown.sections.count,
                   let nextStart = scriptBreakdown.sentences.firstIndex(where: { $0.id == scriptBreakdown.sections[i + 1].startSentenceId }) {
                    return max(startIndex, nextStart - 1)
                }
                return scriptBreakdown.sentences.count - 1
            }()

            if sentenceIndex >= startIndex && sentenceIndex <= endIndex {
                return section
            }
        }

        return nil
    }

    private func getSectionNumber(_ section: OutlineSection) -> Int {
        return (scriptBreakdown.sections.firstIndex(where: { $0.id == section.id }) ?? 0) + 1
    }
    
    // MARK: - Export Functions
    
    private func copyPatternGuidePrompt() {
        let selectedText = getSelectedOrMarkedText()
        let fullScript = transcript
        let prompt = YouTubeAIPrompts().copyPatternGuideAnalysisPrompt(
            selectedText: selectedText,
            fullScript: fullScript
        )
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #else
        UIPasteboard.general.string = prompt
        #endif
        
        print("✅ Copied pattern guide analysis prompt to clipboard")
    }

    private func getSelectedOrMarkedText() -> String {
        let selected = scriptBreakdown.sentences
            .filter { $0.isSelected }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !selected.isEmpty {
            return selected.joined(separator: " ")
        }

        if let editingPattern {
            let ids = Set(editingPattern.sentenceIds)
            let text = scriptBreakdown.sentences
                .filter { ids.contains($0.id) }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !text.isEmpty { return text.joined(separator: " ") }
        }

        if let lastPattern = scriptBreakdown.allMarkedPatterns.last {
            let ids = Set(lastPattern.sentenceIds)
            let text = scriptBreakdown.sentences
                .filter { ids.contains($0.id) }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !text.isEmpty { return text.joined(separator: " ") }
        }

        return "No text selected or marked yet."
    }

    private func getSentencesForSection(_ section: OutlineSection) -> [ScriptSentence] {
        guard let startIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == section.startSentenceId }) else {
            return []
        }
        
        if let endSentenceId = section.endSentenceId,
           let endIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == endSentenceId }) {
            return Array(scriptBreakdown.sentences[startIndex...endIndex])
        } else {
            if let currentIdx = scriptBreakdown.sections.firstIndex(where: { $0.id == section.id }),
               currentIdx + 1 < scriptBreakdown.sections.count {
                let nextSection = scriptBreakdown.sections[currentIdx + 1]
                if let nextStartIndex = scriptBreakdown.sentences.firstIndex(where: { $0.id == nextSection.startSentenceId }) {
                    return Array(scriptBreakdown.sentences[startIndex..<nextStartIndex])
                }
            }
            return Array(scriptBreakdown.sentences[startIndex...])
        }
    }
}
