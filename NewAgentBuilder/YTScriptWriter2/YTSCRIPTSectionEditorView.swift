//
//  YTSCRIPTSectionEditorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/9/25.
//


import SwiftUI

struct PartsJSON: Codable {
    let parts: [PartGroup]
}

struct PartGroup: Codable {
    let part: String
    let sentences: [String]
}

enum SentenceComparisonStatus {
    case matched
    case modified
    case added
    case deleted
}


struct YTSCRIPTSectionEditorView: View {
    @Bindable var script: YTSCRIPT
    var section: YTSCRIPTOutlineSection2
    
    @State private var pastedText = ""
    @State private var expandedSentenceId: UUID? = nil
    @State private var showingHacksSidebar = false
    
    @State private var jsonInput = ""
    //    @State private var showAlert = false
    //    @State private var alertMessage = ""
    @State private var parsedAndCopied = false
    @State private var jsonParsed = false
    @State private var rewrittenFlaggedText = ""
    @State private var showFlaggedPaste = false
    
    @State private var comparisonText = ""
    @State private var comparedSentences: [YTSCRIPTOutlineSentence] = []
    @State private var comparisonPairs: [(current: YTSCRIPTOutlineSentence?, new: YTSCRIPTOutlineSentence?)] = []
    
    private var currentWordCount: Int {
        currentVersion?.sentences.reduce(0) { $0 + $1.text.split(separator: " ").count } ?? 0
    }
    
    private var comparedWordCount: Int {
        comparedSentences.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
    
    private var wordDelta: Int {
        comparedWordCount - currentWordCount
    }
    
    // MARK: - JSON Parsing Structs
    
    var sectionIndex: Int {
        script.outlineSections.firstIndex(where: { $0.id == section.id }) ?? 0
    }
    
    var currentVersion: YTSCRIPTSectionVersion? {
        section.currentVersion
    }
    
    var wordCountDelta: Int {
        section.currentWordCount - section.effectiveWordCount
    }
    
    var wordCountWarning: String {
        let delta = abs(wordCountDelta)
        if wordCountDelta > 0 {
            return "+\(delta) over"
        } else if wordCountDelta < 0 {
            return "\(delta) short"
        }
        return "On target"
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Main Content
            mainContentView
                .frame(maxWidth: .infinity)
            
            // Hacks Sidebar
            if showingHacksSidebar {
                hacksSidebarView
                    .frame(width: 350)
                    .transition(.move(edge: .trailing))
            }
        }
        .navigationTitle("Edit Section")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation {
                        showingHacksSidebar.toggle()
                    }
                } label: {
                    Image(systemName: showingHacksSidebar ? "sidebar.right" : "sidebar.left")
                }
            }
        }
        
    }
    
    // MARK: - Main Content
    
    private var mainContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                outlineSection  // ← ADD THIS
                Divider()
                rawTextSection
                Divider()
                versionHistorySection
                pasteSection
                Divider()
                sentencesSection
                Divider()
                
                comparisonSection
            }
            .padding()
        }
    }
    
    
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.name)
                .font(.title2)
                .bold()
            
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(section.effectiveWordCount) words")
                        .font(.headline)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("\(section.currentWordCount) words")
                            .font(.headline)
                            .foregroundColor(abs(wordCountDelta) > 50 ? .red : .primary)
                        if abs(wordCountDelta) > 10 {
                            Text("(\(wordCountWarning))")
                                .font(.caption)
                                .foregroundColor(abs(wordCountDelta) > 50 ? .red : .orange)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Est. Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f min", Double(section.currentWordCount) / script.wordsPerMinute))
                        .font(.headline)
                }
                
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    private func toggleSentenceFlag(sentenceId: UUID) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0 else { return }
        
        if let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentenceId }) {
            script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].isFlagged.toggle()
            autoSave()
        }
    }
    
    private var outlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Outline")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    copyOutline()
                } label: {
                    Label("Copy Section Notes", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    addBulletPoint()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            if section.bulletPoints.isEmpty {
                Text("No outline points yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(section.bulletPoints.enumerated()), id: \.offset) { index, bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            
                            TextField("Bullet point", text: Binding(
                                get: { script.outlineSections[sectionIndex].bulletPoints[index] },
                                set: {
                                    script.outlineSections[sectionIndex].bulletPoints[index] = $0
                                    autoSave()
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.body)
                            
                            Button {
                                deleteBulletPoint(at: index)
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
    
    private var rawTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Spoken Text (Speech-to-Text)")
                .font(.headline)
            
            TextEditor(text: Binding(
                get: { script.outlineSections[sectionIndex].rawSpokenText },
                set: { script.outlineSections[sectionIndex].rawSpokenText = $0 }
            ))
            .frame(minHeight: 150)
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            HStack {
                Text("\(script.outlineSections[sectionIndex].rawSpokenText.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                CopyButtonAction(label: "Kallaway Prompt", action: { copyKallawayPromptToClipboard() }, isDisabled: script.outlineSections[sectionIndex].rawSpokenText.isEmpty)
          
                
                CopyButtonAction(label: "Derrick Prompt", action: { copyDerrickPromptToClipboard() }, isDisabled: script.outlineSections[sectionIndex].rawSpokenText.isEmpty)

            }
        }
    }
    private func parseAndCompare() {
        // Parse new text
        let sentences = parseSentences(from: comparisonText)
        comparedSentences = sentences.enumerated().map { index, text in
            YTSCRIPTOutlineSentence(text: text, orderIndex: index, part: .unknown)
        }
        
        guard let currentVersion = currentVersion else { return }
        
        // Content-based diff algorithm
        var pairs: [(current: YTSCRIPTOutlineSentence?, new: YTSCRIPTOutlineSentence?)] = []
        
        var usedCurrentIndices = Set<Int>()
        var usedNewIndices = Set<Int>()
        
        // First pass: find exact matches
        for (currentIdx, currentSentence) in currentVersion.sentences.enumerated() {
            if let newIdx = comparedSentences.firstIndex(where: { $0.text == currentSentence.text }),
               !usedNewIndices.contains(newIdx) {
                pairs.append((current: currentSentence, new: comparedSentences[newIdx]))
                usedCurrentIndices.insert(currentIdx)
                usedNewIndices.insert(newIdx)
            }
        }
        
        // Second pass: add deleted sentences (in current but not matched)
        for (currentIdx, currentSentence) in currentVersion.sentences.enumerated() {
            if !usedCurrentIndices.contains(currentIdx) {
                // Insert at appropriate position
                let insertIndex = pairs.filter { pair in
                    if let curr = pair.current {
                        return curr.orderIndex < currentSentence.orderIndex
                    }
                    return false
                }.count
                pairs.insert((current: currentSentence, new: nil), at: insertIndex)
            }
        }
        
        // Third pass: add new sentences (in new but not matched)
        for (newIdx, newSentence) in comparedSentences.enumerated() {
            if !usedNewIndices.contains(newIdx) {
                // Insert at appropriate position
                let insertIndex = pairs.filter { pair in
                    if let new = pair.new {
                        return new.orderIndex < newSentence.orderIndex
                    }
                    return false
                }.count
                pairs.insert((current: nil, new: newSentence), at: insertIndex)
            }
        }
        
        comparisonPairs = pairs
    }
    private func parseAndCompareMatchingPositionsOLD() {
        // Parse new text
        let sentences = parseSentences(from: comparisonText)
        comparedSentences = sentences.enumerated().map { index, text in
            YTSCRIPTOutlineSentence(text: text, orderIndex: index, part: .unknown)
        }
        
        // Match sentences
        guard let currentVersion = currentVersion else { return }
        let maxCount = max(currentVersion.sentences.count, comparedSentences.count)
        comparisonPairs = (0..<maxCount).map { index in
            let current = index < currentVersion.sentences.count ? currentVersion.sentences[index] : nil
            let new = index < comparedSentences.count ? comparedSentences[index] : nil
            return (current, new)
        }
    }
    
    private func acceptNewVersion() {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        
        let newVersion = YTSCRIPTSectionVersion(
            polishedText: comparisonText,
            sentences: comparedSentences
        )
        
        script.outlineSections[sectionIndex].sectionVersions.append(newVersion)
        script.outlineSections[sectionIndex].currentVersionIndex = script.outlineSections[sectionIndex].sectionVersions.count - 1
        
        // Clear
        comparisonText = ""
        comparedSentences = []
        comparisonPairs = []
        
        autoSave()
    }
    
    private func copyOutline() {
        let outlineText = section.bulletPoints.map { "• \($0)" }.joined(separator: "\n")
        
#if os(iOS)
        UIPasteboard.general.string = outlineText
#else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outlineText, forType: .string)
#endif
    }
    
    private func deleteSentence(sentenceId: UUID) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0 else { return }
        
        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.removeAll { $0.id == sentenceId }
        
        reindexSentences()
        autoSave()
    }
    
    private func splitSentenceOnlyOne(sentenceId: UUID) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0 else { return }
        
        guard let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentenceId }) else { return }
        
        let sentence = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex]
        
        // ⭐ DEBUG: Print what we're checking
        print("🔍 Splitting sentence:")
        print("   Text: '\(sentence.text)'")
        print("   Contains |: \(sentence.text.contains("|"))")
        
        // Check if user added a pipe "|" to mark split point
        if sentence.text.contains("|") {
            let parts = sentence.text.components(separatedBy: "|")
            print("   Parts count: \(parts.count)")
            
            if parts.count == 2 {
                let firstPart = parts[0].trimmingCharacters(in: .whitespaces)
                let secondPart = parts[1].trimmingCharacters(in: .whitespaces)
                
                print("   First part: '\(firstPart)'")
                print("   Second part: '\(secondPart)'")
                print("   First empty: \(firstPart.isEmpty)")
                print("   Second empty: \(secondPart.isEmpty)")
                
                if !firstPart.isEmpty && !secondPart.isEmpty {
                    print("✅ Splitting into 2 sentences")
                    
                    // Update first sentence
                    script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text = firstPart
                    
                    // Insert second sentence
                    let newSentence = YTSCRIPTOutlineSentence(
                        text: secondPart,
                        orderIndex: sentenceIndex + 1,
                        part: sentence.part
                    )
                    script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.insert(newSentence, at: sentenceIndex + 1)
                    
                    reindexSentences()
                    autoSave()
                    return
                }
            }
        }
        
        print("❌ Creating blank sentence instead")
        
        // Otherwise create a blank sentence below
        let newSentence = YTSCRIPTOutlineSentence(
            text: "",
            orderIndex: sentenceIndex + 1,
            part: sentence.part
        )
        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.insert(newSentence, at: sentenceIndex + 1)
        reindexSentences()
        autoSave()
    }
    
    private func splitSentence(sentenceId: UUID) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0 else { return }
        
        guard let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentenceId }) else { return }
        
        let sentence = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex]
        
        // ⭐ DEBUG: Print what we're checking
        print("🔍 Splitting sentence:")
        print("   Text: '\(sentence.text)'")
        print("   Contains |: \(sentence.text.contains("|"))")
        
        // Check if user added pipe(s) "|" to mark split point(s)
        if sentence.text.contains("|") {
            let parts = sentence.text.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }  // ⭐ Remove empty parts
            
            print("   Parts count: \(parts.count)")
            
            if parts.count >= 2 {  // ⭐ CHANGED: Handle 2 or more parts
                print("✅ Splitting into \(parts.count) sentences")
                
                // Update first sentence with first part
                script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text = parts[0]
                
                // Insert remaining parts as new sentences
                for (index, part) in parts.dropFirst().enumerated() {
                    let newSentence = YTSCRIPTOutlineSentence(
                        text: part,
                        orderIndex: sentenceIndex + 1 + index,
                        part: sentence.part
                    )
                    script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.insert(newSentence, at: sentenceIndex + 1 + index)
                }
                
                reindexSentences()
                autoSave()
                return
            }
        }
        
        print("❌ Creating blank sentence instead")
        
        // Otherwise create a blank sentence below
        let newSentence = YTSCRIPTOutlineSentence(
            text: "",
            orderIndex: sentenceIndex + 1,
            part: sentence.part
        )
        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.insert(newSentence, at: sentenceIndex + 1)
        reindexSentences()
        autoSave()
    }
    private var versionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version History")
                .font(.headline)
            
            if section.sectionVersions.isEmpty {
                Text("No versions yet. Paste AI output below to create your first version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(section.sectionVersions.enumerated().reversed()), id: \.element.id) { index, version in
                        VersionCard(
                            version: version,
                            versionNumber: section.sectionVersions.count - index,
                            isCurrent: index == section.currentVersionIndex,
                            timeAgo: timeAgoString(from: version.timestamp ?? Date()),
                            onRestore: {
                                restoreVersion(at: index)
                            }
                        )
                    }
                }
            }
        }
    }
    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste AI Output Here")
                .font(.headline)
            
            TextEditor(text: $pastedText)
                .font(.body)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            
            HStack {
                Button {
                    parseAndSaveVersion()
                } label: {
                    Label(
                        parsedAndCopied ? "Splitter Copied!" : "Parse & Copy Splitter",
                        systemImage: parsedAndCopied ? "checkmark.circle.fill" : "arrow.down.doc"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(pastedText.isEmpty)
                
                //                Button {
                //                    copySplitterPrompt()
                //                } label: {
                //                    Label("Split into Parts", systemImage: "scissors")
                //                }
                //                .buttonStyle(.bordered)
                //                .disabled(currentVersion == nil)
                
                Button {
                    pastedText = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            
            // JSON Parts Input
            if currentVersion != nil {
                Divider()
                    .padding(.vertical, 8)
                
                Text("Paste Parts JSON Here")
                    .font(.headline)
                
                TextEditor(text: $jsonInput)
                    .font(.body.monospaced())
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                
                HStack {
                    Button {
                        parsePartsJSON(jsonInput)
                    } label: {
                        Label(
                            jsonParsed ? "Parts Applied!" : "Parse JSON & Apply Parts",
                            systemImage: jsonParsed ? "checkmark.circle.fill" : "checkmark.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(jsonInput.isEmpty)
                    
                    Button {
                        jsonInput = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
    
    
    private func updateSentenceInPart(sentenceId: UUID, newText: String) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0,
              let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentenceId }) else { return }
        
        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text = newText
        autoSave()
    }
    private var sentencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Script by Part")
                    .font(.headline)
                Spacer()
                if flaggedCount > 0 {
                    Button {
                        copyRewritePromptForFlagged()
                        showFlaggedPaste = true
                    } label: {
                        Label("Rewrite \(flaggedCount) Flagged", systemImage: "flag.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
                
                CopyButtonAction(label: "All") {
                    copyAllText()
                }
                Button {
                    copyAllText()
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                CopyButtonAction(label: "With Line #s") {  // ⭐ NEW
                    copyAllTextWithLineNumbers()
                }
            }
            
            if showFlaggedPaste {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste rewritten sentences (S3: text format):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $rewrittenFlaggedText)
                        .font(.body)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    
                    HStack {
                        Button {
                            applyRewrittenFlagged(rewrittenFlaggedText)
                            rewrittenFlaggedText = ""
                            showFlaggedPaste = false
                        } label: {
                            Label("Apply Rewrites", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button {
                            rewrittenFlaggedText = ""
                            showFlaggedPaste = false
                        } label: {
                            Text("Cancel")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red, lineWidth: 2)
                )
            }
            
            if let version = currentVersion {
                // Group sentences by part
                ForEach(KallawayPart.allCases.filter { $0 != .unknown }, id: \.self) { part in
                    let partSentences = version.sentences.filter { $0.part == part }
                    
                    if !partSentences.isEmpty {
                        PartGroupView(
                            part: part,
                            sentences: partSentences,
                            onUpdateSentence: { sentenceId, newText in
                                updateSentenceInPart(sentenceId: sentenceId, newText: newText)
                            },
                            onRewrite: {
                                copyRewritePromptForPart(part)
                            },
                            onApplyRewrite: { rewrittenText in
                                applyRewriteToPart(part: part, newText: rewrittenText)
                            },
                            onFlagSentence: { sentenceId in  // ⭐ ADD THIS
                                toggleSentenceFlag(sentenceId: sentenceId)
                            },
                            onSplitSentence: { sentenceId in  // ⭐ CHANGED from onSplit to onSplitSentence
                                splitSentence(sentenceId: sentenceId)  // ⭐ Now sentenceId is in scope
                            },
                            onDeleteSentence: { sentenceId in  // ⭐ ADD THIS
                                deleteSentence(sentenceId: sentenceId)
                            }
                        )
                    }
                }
                
                // Show uncategorized sentences if any
                // Show uncategorized sentences if any
                let unknownSentences = version.sentences.filter { $0.part == .unknown }
                if !unknownSentences.isEmpty {
                    PartGroupView(
                        part: .unknown,
                        sentences: unknownSentences,
                        onUpdateSentence: { sentenceId, newText in
                            updateSentenceInPart(sentenceId: sentenceId, newText: newText)
                        },
                        onRewrite: { },
                        onApplyRewrite: { _ in },
                        onFlagSentence: { sentenceId in  // ⭐ ADD THIS
                            toggleSentenceFlag(sentenceId: sentenceId)
                        },
                        onSplitSentence: { sentenceId in  // ⭐ CORRECTED
                            splitSentence(sentenceId: sentenceId)  // ⭐ Calls splitSentence, not onSplitSentence
                        },
                        onDeleteSentence: { sentenceId in  // ⭐ ADD THIS
                            deleteSentence(sentenceId: sentenceId)
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
    
    private func copyAllTextWithLineNumbers() {
        guard let current = currentVersion else { return }
        
        let text = current.sentences
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .enumerated()
            .map { index, sentence in
                "S\(index + 1): \(sentence.text)"
            }
            .joined(separator: "\n")
        
#if os(iOS)
        UIPasteboard.general.string = text
#else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
        
    }
        
        
        private var comparisonSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Compare New Version")
                    .font(.headline)
                
                Text("Paste revised section to see what changed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Input area
                TextEditor(text: $comparisonText)
                    .font(.body)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                
                HStack {
                    Button {
                        parseAndCompare()
                    } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(comparisonText.isEmpty || currentVersion == nil)
                    
                    Button {
                        comparisonText = ""
                        comparedSentences = []
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                
                // Show comparison inline (if parsed)
                if !comparedSentences.isEmpty {
                    Divider()
                        .padding(.vertical, 8)
                    
                    comparisonResultsView
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
        }
        
        private var comparisonResultsView: some View {
            VStack(alignment: .leading, spacing: 16) {
                // Stats header
                HStack(spacing: 32) {
                    VStack(alignment: .leading) {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(currentVersion?.sentences.count ?? 0) sentences")
                            .font(.headline)
                        Text("\(currentWordCount) words")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading) {
                        Text("New")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(comparedSentences.count) sentences")
                            .font(.headline)
                        Text("\(comparedWordCount) words")
                            .font(.subheadline)
                            .foregroundColor(wordDelta < 0 ? .green : wordDelta > 0 ? .orange : .blue)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Delta")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(wordDelta >= 0 ? "+" : "")\(wordDelta) words")
                            .font(.headline)
                            .foregroundColor(wordDelta < 0 ? .green : wordDelta > 0 ? .orange : .gray)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                
                // Two columns - each in their own order
                HStack(alignment: .top, spacing: 12) {
                    // Left column: Current version
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Version")
                            .font(.subheadline.bold())
                            .padding(.bottom, 8)
                        
                        ForEach(Array((currentVersion?.sentences ?? []).enumerated()), id: \.element.id) { index, sentence in
                            let isMatched = comparedSentences.contains(where: { $0.text == sentence.text })
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("S\(index + 1)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    
                                    if isMatched {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "trash.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                                
                                Text(sentence.text)
                                    .font(.body)
                                    .foregroundColor(isMatched ? .primary : .secondary)
                                    .strikethrough(!isMatched)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isMatched ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right column: New version
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New Version")
                            .font(.subheadline.bold())
                            .padding(.bottom, 8)
                        
                        ForEach(Array(comparedSentences.enumerated()), id: \.element.id) { index, sentence in
                            let isMatched = currentVersion?.sentences.contains(where: { $0.text == sentence.text }) ?? false
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("S\(index + 1)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    
                                    if isMatched {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Text(sentence.text)
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isMatched ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Summary
                HStack(spacing: 16) {
                    Label("\(matchedCount) kept", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Label("\(deletedCount) deleted", systemImage: "trash.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    Label("\(addedCount) added", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                
                // Accept/Reject buttons
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        comparisonText = ""
                        comparedSentences = []
                    } label: {
                        Label("Keep Current", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button {
                        acceptNewVersion()
                    } label: {
                        Label("Accept New Version", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        
        // Add computed properties for summary
        private var matchedCount: Int {
            let currentTexts = Set(currentVersion?.sentences.map { $0.text } ?? [])
            return comparedSentences.filter { currentTexts.contains($0.text) }.count
        }
        
        private var deletedCount: Int {
            let newTexts = Set(comparedSentences.map { $0.text })
            return (currentVersion?.sentences.filter { !newTexts.contains($0.text) }.count ?? 0)
        }
        
        private var addedCount: Int {
            let currentTexts = Set(currentVersion?.sentences.map { $0.text } ?? [])
            return comparedSentences.filter { !currentTexts.contains($0.text) }.count
        }
        
        
        private func sentenceComparisonCell(text: String, number: Int, status: SentenceComparisonStatus) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("S\(number)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    
                    statusBadge(status)
                }
                
                Text(text)
                    .font(.body)
                    .foregroundColor(status == .deleted ? .secondary : .primary)
                    .strikethrough(status == .deleted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(backgroundColor(for: status))
            .cornerRadius(8)
        }
        
        private func statusBadge(_ status: SentenceComparisonStatus) -> some View {
            Group {
                switch status {
                case .matched:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                case .modified:
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                case .added:
                    Image(systemName: "plus.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                case .deleted:
                    Image(systemName: "trash.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
        
        private func backgroundColor(for status: SentenceComparisonStatus) -> Color {
            switch status {
            case .matched: return Color.green.opacity(0.1)
            case .modified: return Color.orange.opacity(0.1)
            case .added: return Color.blue.opacity(0.1)
            case .deleted: return Color.red.opacity(0.1)
            }
        }
        
        private var flaggedCount: Int {
            guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return 0 }
            let currentSection = script.outlineSections[sectionIndex]
            guard currentSection.currentVersionIndex >= 0,
                  currentSection.currentVersionIndex < currentSection.sectionVersions.count else { return 0 }
            let currentVersion = currentSection.sectionVersions[currentSection.currentVersionIndex]
            return currentVersion.sentences.filter { $0.isFlagged }.count
        }
        
        private func applyRewriteToPart(part: KallawayPart, newText: String) {
            guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
            let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
            guard versionIndex >= 0 else { return }
            
            // Parse the new text into sentences
            let newSentences = parseSentences(from: newText)
            
            // Get current version
            var currentVersion = script.outlineSections[sectionIndex].sectionVersions[versionIndex]
            
            // Remove old sentences for this part
            currentVersion.sentences.removeAll { $0.part == part }
            
            // Find the highest orderIndex to continue from
            let maxIndex = currentVersion.sentences.map { $0.orderIndex }.max() ?? -1
            
            // Add new sentences with correct part and orderIndex
            let newSentenceObjects = newSentences.enumerated().map { offset, text in
                YTSCRIPTOutlineSentence(
                    text: text,
                    orderIndex: maxIndex + 1 + offset,
                    part: part
                )
            }
            
            currentVersion.sentences.append(contentsOf: newSentenceObjects)
            
            // Re-sort by orderIndex
            currentVersion.sentences.sort { $0.orderIndex < $1.orderIndex }
            
            // Update the version
            script.outlineSections[sectionIndex].sectionVersions[versionIndex] = currentVersion
            
            autoSave()
        }
        private func copyRewritePromptForFlagged() {
            guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
            let currentSection = script.outlineSections[sectionIndex]
            
            guard currentSection.currentVersionIndex >= 0,
                  currentSection.currentVersionIndex < currentSection.sectionVersions.count else { return }
            
            let currentVersion = currentSection.sectionVersions[currentSection.currentVersionIndex]
            let flaggedSentences = currentVersion.sentences.filter { $0.isFlagged }
            
            guard !flaggedSentences.isEmpty else { return }
            
            var prompt = """
        SECTION: \(currentSection.name)
        MISSION: \(script.objective)
        
        FULL CONTEXT (all sentences):
        
        """
            
            // Show all sentences with flags
            for sentence in currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let flag = sentence.isFlagged ? "🚩 " : ""
                prompt += "\(flag)S\(sentence.orderIndex + 1): \(sentence.text)\n"
            }
            
            prompt += """
        
        
        ===========================================
        FLAGGED SENTENCES (need rewriting):
        ===========================================
        
        """
            
            for sentence in flaggedSentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                prompt += "🚩 S\(sentence.orderIndex + 1): \(sentence.text)\n"
            }
            
            prompt += """
        
        
        ===========================================
        RAW NOTES FOR THIS ENTIRE SCRIPT:
        ===========================================
        
        ===========================================
        YOUR FEEDBACK (what's wrong with these):
        ===========================================
        
        [Explain what's wrong with the flagged sentences here]
        
        
        ===========================================
        INSTRUCTIONS FOR AI:
        ===========================================
        
        Rewrite ONLY the flagged sentences above.
        Output format (nothing else):
        
        S3: [your rewritten sentence]
        S5: [your rewritten sentence]
        
        Do not output any other sentences. Do not explain. Just the sentence numbers and new text.
        
        """
            
#if os(iOS)
            UIPasteboard.general.string = prompt
#else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
#endif
        }
        
        private func applyRewrittenFlagged(_ pastedText: String) {
            guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
            let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
            guard versionIndex >= 0 else { return }
            
            // Parse format: "S3: New sentence text"
            let lines = pastedText.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("S") else { continue }
                
                // Extract sentence number and text
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                
                let numberPart = parts[0].dropFirst() // Remove "S"
                guard let sentenceNum = Int(numberPart) else { continue }
                
                let newText = String(parts[1]).trimmingCharacters(in: .whitespaces)
                let targetOrderIndex = sentenceNum - 1 // Convert to 0-indexed
                
                // Find and update the sentence
                if let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.orderIndex == targetOrderIndex }) {
                    script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text = newText
                    script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].isFlagged = false // Unflag after rewrite
                }
            }
            
            autoSave()
        }
        private func copyRewritePromptForPart(_ part: KallawayPart) {
            guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
            let currentSection = script.outlineSections[sectionIndex]
            
            guard currentSection.currentVersionIndex >= 0,
                  currentSection.currentVersionIndex < currentSection.sectionVersions.count else { return }
            
            let currentVersion = currentSection.sectionVersions[currentSection.currentVersionIndex]
            let partSentences = currentVersion.sentences.filter { $0.part == part }
            let wordCount = partSentences.reduce(0) { $0 + $1.text.split(separator: " ").count }
            
            // Group ALL sentences by part for full context
            let allPartGroups = Dictionary(grouping: currentVersion.sentences) { $0.part }
            
            var prompt = """
        MISSION: \(script.objective)
        
        SECTION: \(currentSection.name)
        
        FULL SECTION CONTEXT (all parts):
        
        """
            
            // Show all 7 parts in order for context
            for contextPart in KallawayPart.allCases where contextPart != .unknown {
                let contextSentences = allPartGroups[contextPart] ?? []
                if !contextSentences.isEmpty {
                    prompt += "[\(contextPart.displayName)]\n"
                    for sentence in contextSentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                        prompt += "\(sentence.text)\n"
                    }
                    prompt += "\n"
                }
            }
            
            prompt += """
        
        
        REWRITE TARGET: \(part.displayName)
        
        Current text (\(partSentences.count) sentences, \(wordCount) words):
        
        """
            
            for sentence in partSentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                prompt += "\(sentence.text)\n"
            }
            
            prompt += """
        
        
        YOUR GUIDANCE (add below):
        
        
        [What's wrong with the current text? What needs to change? Add your notes here]
        
        
        REWRITE REQUIREMENTS:
        - Maintain approximately \(partSentences.count) sentences (can vary by 1-2)
        - Keep sentence-per-line format
        - Output ONLY the rewritten sentences for \(part.displayName)
        - No preamble, no explanation, just the sentences
        
        """
            
#if os(iOS)
            UIPasteboard.general.string = prompt
#else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
#endif
        }
        private func copyRewritePromptForPart3(_ part: KallawayPart) {
            guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
            let currentSection = script.outlineSections[sectionIndex]
            
            guard currentSection.currentVersionIndex >= 0,
                  currentSection.currentVersionIndex < currentSection.sectionVersions.count else { return }
            
            let currentVersion = currentSection.sectionVersions[currentSection.currentVersionIndex]
            let partSentences = currentVersion.sentences.filter { $0.part == part }
            let wordCount = partSentences.reduce(0) { $0 + $1.text.split(separator: " ").count }
            
            // Group ALL sentences by part for full context
            let allPartGroups = Dictionary(grouping: currentVersion.sentences) { $0.part }
            
            var prompt = """
        MISSION: \(script.objective)
        
        SECTION: \(currentSection.name)
        
        FULL SECTION CONTEXT (all parts):
        
        """
            
            // Show all 7 parts in order for context
            for contextPart in KallawayPart.allCases where contextPart != .unknown {
                let contextSentences = allPartGroups[contextPart] ?? []
                if !contextSentences.isEmpty {
                    prompt += "[\(contextPart.displayName)]\n"
                    for sentence in contextSentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                        prompt += "\(sentence.text)\n"
                    }
                    prompt += "\n"
                }
            }
            
            prompt += """
        
        ═══════════════════════════════════════════
        REWRITE TARGET: \(part.displayName)
        ═══════════════════════════════════════════
        
        Current text (\(partSentences.count) sentences, \(wordCount) words):
        
        """
            
            for sentence in partSentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                prompt += "\(sentence.text)\n"
            }
            
            prompt += """
        
        
        ═══════════════════════════════════════════
        YOUR GUIDANCE (add below):
        ═══════════════════════════════════════════
        
        [What's wrong with the current text? What needs to change? Add your notes here]
        
        
        ═══════════════════════════════════════════
        REWRITE REQUIREMENTS:
        ═══════════════════════════════════════════
        - Maintain approximately \(partSentences.count) sentences (can vary by 1-2)
        - Keep sentence-per-line format
        - Output ONLY the rewritten sentences for \(part.displayName)
        - No preamble, no explanation, just the sentences
        
        """
            
#if os(iOS)
            UIPasteboard.general.string = prompt
#else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
#endif
        }
        private func copyRewritePromptForPart2(_ part: KallawayPart, sentences: [YTSCRIPTOutlineSentence]) {
            let currentText = sentences.map { $0.text }.joined(separator: "\n")
            let sentenceCount = sentences.count
            let wordCount = sentences.reduce(0) { $0 + $1.text.split(separator: " ").count }
            
            let prompt = """
        You are rewriting ONLY \(part.displayName) of a YouTube hunting script.
        
        CONTEXT:
        - Video Mission: \(script.objective)
        - Section: \(section.name)
        - Current word count for this part: \(wordCount) words
        
        CURRENT TEXT (\(sentenceCount) sentences):
        \(currentText)
        
        REWRITE REQUIREMENTS:
        - Maintain approximately \(sentenceCount) sentences (can vary by 1-2)
        - Keep sentence-per-line format
        - Output ONLY the rewritten sentences, nothing else
        
        \(getPartSpecificInstructions(for: part))
        """
            
#if os(iOS)
            UIPasteboard.general.string = prompt
#else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
#endif
        }
        
        private func getPartSpecificInstructions(for part: KallawayPart) -> String {
            switch part {
            case .authorityProof:
                return """
            CRITICAL FOR AUTHORITY PROOF:
            - Only use data from Byron's raw notes
            - If no specific research mentioned, use Byron's thermal observations as authority
            - NEVER invent fake studies, universities, or percentages
            - Use patterns like: "After analyzing thermal footage from 50+ properties..."
            """
                
            case .tacticalApplication:
                let missionLower = script.objective.lowercased()
                if missionLower.contains("hire") || missionLower.contains("thermal drone study") {
                    return """
                MISSION ALIGNMENT:
                - Focus on what questions to ask when hiring thermal analysis
                - Emphasize what only thermal can reveal
                - Create desire for professional help
                - DO NOT give DIY instructions
                """
                } else {
                    return """
                TACTICAL FOCUS:
                - Give immediately actionable steps
                - Focus on stand placement, timing, access routes
                - End with strong conclusion
                """
                }
                
            case .simplifyIt:
                return """
            SIMPLIFY IT REQUIREMENTS:
            - Must use ONE strong metaphor
            - Explain the same concept as Part 2 but for a 5-year-old
            - Use concrete comparisons (cafeteria, hotel, parking lot, etc.)
            """
                
            default:
                return ""
            }
        }
        
        //    private var sentencesSectionold: some View {
        //        VStack(alignment: .leading, spacing: 12) {
        //            if let current = currentVersion, !current.sentences.isEmpty {
        //                HStack {
        //                    Text("Current Version (v\(section.currentVersionIndex + 1))")
        //                        .font(.headline)
        //
        //                    Spacer()
        //
        //                    Text("\(current.sentences.count) sentences")
        //                        .font(.caption)
        //                        .foregroundStyle(.secondary)
        //                }
        //
        //                Text("Click any sentence to edit")
        //                    .font(.caption)
        //                    .foregroundStyle(.secondary)
        //
        //                VStack(spacing: 8) {
        //                    ForEach(Array(current.sentences.enumerated()), id: \.element.id) { index, sentence in
        //                        SectionSentenceRow(
        //                            script: script,
        //                            sectionIndex: sectionIndex,
        //                            sentence: sentence,
        //                            isExpanded: expandedSentenceId == sentence.id,
        //                            onTap: {
        //                                withAnimation {
        //                                    expandedSentenceId = expandedSentenceId == sentence.id ? nil : sentence.id
        //                                }
        //                            },
        //                            onSplit: {
        //                                splitSentence(sentence)
        //                            },
        //                            onMergeWithNext: index < current.sentences.count - 1 ? {
        //                                mergeWithNext(sentence)
        //                            } : nil,
        //                            onDelete: {
        //                                deleteSentence(sentence)
        //                            }
        //                        )
        //                    }
        //                }
        //
        //                // Quick Actions
        //                HStack(spacing: 12) {
        //                    Button {
        //                        copyAllText()
        //                    } label: {
        //                        Label("Copy All Text", systemImage: "doc.on.doc")
        //                    }
        //                    .buttonStyle(.bordered)
        //
        //                    Menu {
        //                        Button {
        //                            // TODO: Implement
        //                            print("Check duplication")
        //                        } label: {
        //                            Label("Check Duplication", systemImage: "magnifyingglass")
        //                        }
        //
        //                        Button {
        //                            // TODO: Implement
        //                            print("Check bleeding")
        //                        } label: {
        //                            Label("Check Bleeding", systemImage: "arrow.left.arrow.right")
        //                        }
        //
        //                        Button {
        //                            // TODO: Implement
        //                            print("Rhythm analysis")
        //                        } label: {
        //                            Label("Rhythm Analysis", systemImage: "waveform")
        //                        }
        //                    } label: {
        //                        Label("Quick Analysis", systemImage: "chart.bar")
        //                    }
        //                    .buttonStyle(.bordered)
        //                }
        //            } else {
        //                VStack(spacing: 8) {
        //                    Image(systemName: "text.alignleft")
        //                        .font(.system(size: 48))
        //                        .foregroundStyle(.secondary)
        //                    Text("No sentences yet")
        //                        .font(.headline)
        //                        .foregroundStyle(.secondary)
        //                    Text("Paste AI output above to generate sentences")
        //                        .font(.caption)
        //                        .foregroundStyle(.secondary)
        //                }
        //                .frame(maxWidth: .infinity)
        //                .padding(40)
        //                .background(Color(.tertiarySystemBackground))
        //                .cornerRadius(12)
        //            }
        //        }
        //    }
        
        // MARK: - Hacks Sidebar
        
        private var hacksSidebarView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HacksChecklistView(script: script, sectionIndex: sectionIndex)
                }
                .padding()
            }
            .background(Color(.secondarySystemBackground))
        }
        
        // MARK: - Actions
        
        private func addBulletPoint() {
            script.outlineSections[sectionIndex].bulletPoints.append("")
            autoSave()
        }
        
        private func deleteBulletPoint(at index: Int) {
            script.outlineSections[sectionIndex].bulletPoints.remove(at: index)
            autoSave()
        }
        
//        private func copyPromptToClipboard() {
//            let prompt = generatePolishPrompt()
//            
//#if os(iOS)
//            UIPasteboard.general.string = prompt
//#else
//            NSPasteboard.general.clearContents()
//            NSPasteboard.general.setString(prompt, forType: .string)
//#endif
//        }
    
    private func copyKallawayPromptToClipboard() {
        let prompt = generateKallawayPolishPrompt()
        
        #if os(iOS)
        UIPasteboard.general.string = prompt
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
    }

    private func copyDerrickPromptToClipboard() {
        let prompt = generateDerrickPolishPrompt()
        
        #if os(iOS)
        UIPasteboard.general.string = prompt
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
    }
        
    
    private func generateDerrickPolishPrompt() -> String {
        let section = script.outlineSections[sectionIndex]
        
        let outlineBullets = section.bulletPoints.isEmpty
            ? "(No outline bullets provided)"
            : section.bulletPoints.map { "• \($0)" }.joined(separator: "\n")
        
        return """
        You are writing a YouTube script section in DERRICK'S OWNERSHIP-DENSE STYLE.
        
        SECTION: \(section.name)
        TARGET: \(section.effectiveWordCount) words (acceptable range: \(section.effectiveWordCount) to \(section.effectiveWordCount + 100))
        
        VIDEO MISSION: \(script.objective)
        
        SECTION OUTLINE BULLETS:
        \(outlineBullets)
        
        RAW NOTES (YOUR unique observations from YOUR property):
        \(section.rawSpokenText.isEmpty ? "(No raw notes yet - ADD YOUR SPECIFIC OBSERVATIONS)" : section.rawSpokenText)
        
        ═══════════════════════════════════════════════════════════
        DERRICK STYLE - HIGH OWNERSHIP DENSITY REQUIREMENTS
        ═══════════════════════════════════════════════════════════
        
        🎯 OWNERSHIP CHECKLIST (MANDATORY):
        ✓ Named specifics: Use actual names (stands, properties, bucks, locations)
        ✓ Time investment visible: "20 years managing", "this season", "3 attempts"
        ✓ YOUR unique data: Exact numbers from YOUR thermal footage/trail cams
        ✓ Personal journey: "I discovered", "I was wrong about", "Here's what surprised me"
        ✓ Vulnerability: Admit failures, wrong predictions, confusion
        ✓ Footage dependency: References to YOUR specific thermal/trail cam footage
        ✓ Uncopyable: Another creator could NOT make this without YOUR property access
        
        VOICE & PERSPECTIVE:
        - Write as "I" (first person) - this is YOUR story
        - Use specific names, not generic terms ("DD stand" not "a stand")
        - Show your work: "After flying 50+ properties, here's what I found..."
        - Include mistakes: "I assumed X, but the data showed Y"
        - Reference YOUR footage: "Watch this buck on the thermal" or "Trail cam #3 captured this"
        
        CRITICAL RULE:
        Every claim must tie back to YOUR specific property, YOUR footage, or YOUR investment.
        If raw notes lack specifics, OUTPUT THIS INSTEAD:
        "INSUFFICIENT OWNERSHIP - Need more specific details about:
        - Named locations/stands/bucks
        - Exact measurements from YOUR data
        - Time investment visible
        - Personal failures or surprises
        - Footage references"
        
        FORMAT:
        - One sentence per line
        - No line numbers
        - No bracketed tags
        - Conversational hunting buddy tone
        - Target \(section.effectiveWordCount) words
        
        Write the script section now, or request specific details if raw notes lack ownership density.
        """
    }
        
        // MARK: - Part Splitting
        
        private func generateSplitterPrompt() -> String {
            guard let version = currentVersion else { return "" }
            let scriptText = version.sentences.map { $0.text }.joined(separator: "\n")
            
            return """
        Analyze this YouTube hunting script and categorize each sentence into the 7 Kallaway parts.
        
        Return ONLY valid JSON with this exact structure (no markdown, no explanation, no code fences):
        
        {
          "parts": [
            {
              "part": "nameIt",
              "sentences": ["First sentence here."]
            },
            {
              "part": "compressIt",
              "sentences": [
                "Second sentence here.",
                "Third sentence here."
              ]
            },
            {
              "part": "simplifyIt",
              "sentences": ["Sentence with metaphor."]
            },
            {
              "part": "whyItMatters",
              "sentences": ["Why this matters..."]
            },
            {
              "part": "authorityProof",
              "sentences": ["Research or authority..."]
            },
            {
              "part": "yourExample",
              "sentences": ["Personal story..."]
            },
            {
              "part": "tacticalApplication",
              "sentences": ["Actionable steps..."]
            }
          ]
        }
        
        Valid part values ONLY: nameIt, compressIt, simplifyIt, whyItMatters, authorityProof, yourExample, tacticalApplication
        
        Rules:
        - Part 1 (nameIt) is always the first sentence - the punchy label
        - Part 2 (compressIt) is technical/expert language (2-4 sentences)
        - Part 3 (simplifyIt) uses metaphor/5-year-old explanation (2-3 sentences)
        - Part 4 (whyItMatters) connects to pain/problem (3-4 sentences)
        - Part 5 (authorityProof) references research/authority (3-5 sentences)
        - Part 6 (yourExample) is Byron's personal thermal story (5-8 sentences)
        - Part 7 (tacticalApplication) is actionable tactics (5-8 sentences)
        
        Script to analyze:
        
        \(scriptText)
        """
        }
        
        //    private func copySplitterPrompt() {
        //        let prompt = generateSplitterPrompt()
        //
        //        #if os(iOS)
        //        UIPasteboard.general.string = prompt
        //        #else
        //        NSPasteboard.general.clearContents()
        //        NSPasteboard.general.setString(prompt, forType: .string)
        //        #endif
        //
        //        showAlert = true
        //        alertMessage = "Splitter prompt copied! Paste into Claude, copy the JSON result, then paste it back here."
        //    }
        
        private func parsePartsJSON(_ jsonString: String) {
            guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
            
            let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
            guard versionIndex >= 0 else { return }
            
            var cleanJSON = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanJSON.hasPrefix("```json") {
                cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
            }
            if cleanJSON.hasPrefix("```") {
                cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
            }
            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let jsonData = cleanJSON.data(using: .utf8) else { return }
            
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(PartsJSON.self, from: jsonData)
                
                var newSentences: [YTSCRIPTOutlineSentence] = []
                var orderIndex = 0
                
                for partGroup in result.parts {
                    guard let part = KallawayPart(rawValue: partGroup.part) else { continue }
                    
                    for sentenceText in partGroup.sentences {
                        newSentences.append(YTSCRIPTOutlineSentence(
                            id: UUID(),
                            text: sentenceText,
                            orderIndex: orderIndex,
                            part: part
                        ))
                        orderIndex += 1
                    }
                }
                
                script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences = newSentences
                
                // Show feedback
                withAnimation {
                    jsonParsed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        jsonParsed = false
                    }
                }
                
                jsonInput = ""
                autoSave()
                
            } catch {
                print("❌ Failed to parse JSON: \(error)")
            }
        }
        
        
        
        private func generateKallawayPolishPrompt() -> String {
            let section = script.outlineSections[sectionIndex]
            
            // Format outline bullets
            let outlineBullets = section.bulletPoints.isEmpty
            ? "(No outline bullets provided - create structure from raw notes)"
            : section.bulletPoints.map { "• \($0)" }.joined(separator: "\n")
            
            // Format full outline context if available
            let fullOutlineContext = script.outlineSections.map { outlineSection in
                var text = "\(outlineSection.name)"
                if !outlineSection.bulletPoints.isEmpty {
                    text += "\n" + outlineSection.bulletPoints.map { "  • \($0)" }.joined(separator: "\n")
                }
                return text
            }.joined(separator: "\n\n")
            
            return """
        You are an expert YouTube script writer for whitetail hunting education content, applying Alex Kallaway's methodology exactly.
        
        ═══════════════════════════════════════════════════════════
        SECTION METADATA
        ═══════════════════════════════════════════════════════════
        
        Section Title: \(section.name)
        Target Word Count: \(section.effectiveWordCount) words
        Acceptable Range: \(section.effectiveWordCount) to \(section.effectiveWordCount + 100) words
        Video Mission: \(script.objective)
        Target Audience: \(script.audienceNotes)
        
        ═══════════════════════════════════════════════════════════
        FULL VIDEO OUTLINE (FOR CONTEXT)
        ═══════════════════════════════════════════════════════════
        
        \(fullOutlineContext)
        
        ═══════════════════════════════════════════════════════════
        MANDATORY OUTLINE – YOU MUST HIT EVERY BULLET
        ═══════════════════════════════════════════════════════════
        
        \(outlineBullets)
        
        ═══════════════════════════════════════════════════════════
        RAW NOTES – YOUR ONLY FACT SOURCE
        ═══════════════════════════════════════════════════════════
        
        \(section.rawSpokenText.isEmpty ? "(No raw notes provided yet)" : section.rawSpokenText)
        
        CRITICAL RULE: If outline or instructions conflict with raw notes, PREFER THE RAW NOTES for all facts, numbers, distances, and observations. Do NOT invent facts not present in raw notes.
        
        ═══════════════════════════════════════════════════════════
        INSUFFICIENT CONTENT CHECK – READ THIS FIRST
        ═══════════════════════════════════════════════════════════
        
        BEFORE writing the script, evaluate if the raw notes contain enough substance to reach \(section.effectiveWordCount) words while following the 7-part structure.
        
        Ask yourself:
        - Can I write this section with specific details from these notes?
        - Are there actual numbers, distances, or observations to reference?
        - Do I understand what the core insight is?
        - Do I know why this matters to hunters?
        - Is there enough here for tactical application?
        
        IF THE ANSWER TO ANY IS "NO" - STOP AND ASK CLARIFYING QUESTIONS.
        
        Be specific about what's missing
        
        DO NOT ask generic template questions. Identify the SPECIFIC gaps in THESE notes and ask about those.
        
        ONLY PROCEED with script writing if you have sufficient detail.
        
        
        
        ONLY PROCEED if raw notes contain sufficient detail. Do NOT pad with fluff to hit word count.
        
        ═══════════════════════════════════════════════════════════
        HARD RULES – DO NOT DEVIATE
        ═══════════════════════════════════════════════════════════
        
        WORD COUNT: \(section.effectiveWordCount) to \(section.effectiveWordCount + 100) words (never go under target, can go up to 100 over)
        FORMAT: One sentence per line (no line numbers, no labels, no tags)
        TONE: Conversational, like explaining to a hunting buddy at camp
        PERSPECTIVE: Use "you" constantly (audience of one, not "you guys")
        FACTS: Only use data/numbers/observations from raw notes - do NOT hallucinate
        OUTPUT: Script only - no commentary, no "here's the script," no preamble
        TAGS: Do NOT include [B-ROLL:], [PAUSE], or any bracketed production notes
        
        SIGNATURE SAUCE (Byron's Style):
        - Thermal drone data emphasis with specific distances/numbers from raw notes
        - Whitetail biology and behavior framing
        - Data-driven hunting insights
        - Slight engineer/analytical tone mixed with hunting vernacular
        - "Here's what the data shows..." patterns
        - Slight Texas/southern hunting camp phrasing where natural
        
        ═══════════════════════════════════════════════════════════
        7-PART KALLAWAY STRUCTURE – MANDATORY ORDER
        ═══════════════════════════════════════════════════════════
        
        Part 1: NAME IT (3 seconds / 1 sentence)
        → Create one punchy, quotable label for this insight
        → Make it shareable, memorable
        → Examples: "The Cafeteria Effect," "The Bedding Gap," "The 500-Yard Commute"
        
        Part 2: COMPRESS IT (10 seconds / 2-3 sentences)
        → Dense, expert-to-expert hunting language
        → Technical delivery for experienced hunters
        → Use precise terminology: bedding pressure, thermal signature, daylight movement, doe groups, clearcut, etc.
        
        Part 3: SIMPLIFY IT (10 seconds / 2-3 sentences)
        → CRITICAL: Explain the exact same concept using a 5-year-old explanation
        → Use ONE strong metaphor (cafeteria, parking lot security guard, neighborhood, hotel, etc.)
        → This is 2x delivery - same idea, different lens
        
        Part 4: WHY IT MATTERS (15 seconds / 3-4 sentences)
        → Connect to specific hunter pain point: empty cameras, nocturnal bucks, blown stands, wasted food plot effort
        → Show consequence of NOT understanding this insight
        → Create urgency - this matters RIGHT NOW for this season
        
        Part 5: AUTHORITY PROOF (20 seconds / 2-5 sentences)
        → ONLY USE DATA FROM RAW NOTES - do not invent research
        → If raw notes don't have specific research, use Byron's thermal observations as the authority
        → Patterns like: "After analyzing thermal footage from 50+ properties..." or "The pattern we see consistently..."
        → NEVER say: "GPS collar studies show" or "Biologists have documented" unless Byron provided this in raw notes
        → If you need research backing and it's not in raw notes, ASK BYRON for specific studies
        
        Part 6: YOUR EXAMPLE (30 seconds / 6-7 sentences)
        → Tell the specific story from the raw notes using Byron's thermal drone work
        → Include exact distances, deer counts, nights observed, and thermal signatures ONLY from raw notes
        → Weave in credibility naturally: "After flying this property multiple nights..." or "The thermal footage clearly showed..."
        → This is proof Byron practices what he teaches
        
        Part 7: TACTICAL APPLICATION (30 seconds / 6-7 sentences)
        → Give step-by-step, immediately actionable hunting tactics
        → Focus on: stand placement, access routes, timing, what to change on their property
        → End with strong conclusion that ties back to the named concept
        → Make it feel like: "This changes how you hunt these properties"
        
        ═══════════════════════════════════════════════════════════
        FLEXIBILITY IN STRUCTURE – ADAPT TO CONTENT
        ═══════════════════════════════════════════════════════════
        
        The sentence counts above are GUIDELINES, not rigid rules:
        - If a part needs 2 sentences, use 2. If it needs 5, use 5.
        - Match the substance of the raw notes, not an arbitrary count
        - Better to be concise and powerful than padded to hit a number
        - The 7-part sequence is mandatory, but length per part is flexible
        
        Priority order:
        1. Hit every part in sequence (NAME → COMPRESS → SIMPLIFY → WHY → AUTHORITY → EXAMPLE → TACTICAL)
        2. Stay within total word count range
        3. Make each part as long or short as the content demands
        
        ═══════════════════════════════════════════════════════════
        STORY LOOPS – BUILD INTO EVERY PART
        ═══════════════════════════════════════════════════════════
        
        Each part must contain a micro story loop:
        - CONTEXT: Set up what hunters typically believe or expect
        - REVEAL: Deliver something better/more specific/unexpected than they expect
        - NEVER deliver worse-than-expected or confusing reveals
        - Create mini "aha" moments throughout
        
        Example patterns:
        "Most hunters assume X... but the thermal data shows Y."
        "You'd think A would happen... but here's what actually happened: B."
        "Everyone says you need X... turns out Y is what actually matters."
        
        ═══════════════════════════════════════════════════════════
        PSYCHOLOGY TACTICS – WEAVE IN NATURALLY
        ═══════════════════════════════════════════════════════════
        
        COMPREHENSION MAXING:
        - Keep vocabulary simple (smart 8-year-old test)
        - Break complex ideas into multiple simple sentences
        - Use concrete examples and specific numbers from raw notes
        
        CONTRAST BUILDING:
        - Set up common belief first
        - Then reveal contrarian data from Byron's research
        - Emphasize the gap between what they think and what's real
        
        PAIN → SOLUTION:
        - Name their frustration explicitly early
        - Show how this insight solves it
        - Where they are vs. where they want to be
        
        SENTENCE RHYTHM:
        - Vary length: short → medium → long → short (jagged margin test)
        - Most sentences short and punchy
        - Occasional longer explanatory sentence
        - End sentences with down energy (avoid "right?" or "you know?")
        
        VALUE COMPRESSION:
        - First valuable insight within first 10 seconds
        - No fluff windup - pitch the ball immediately
        - If struggling to hit word count, you need more from Byron - ASK
        
        AUTHENTICITY:
        - Conversational hunting buddy tone throughout
        - Slight southern/Texas phrasing where natural
        - Engineer-meets-hunter analytical style
        
        ═══════════════════════════════════════════════════════════
        BEFORE YOU OUTPUT – VERIFY CHECKLIST
        ═══════════════════════════════════════════════════════════
        
        Structure Check:
        □ Part 1 (NAME IT) present as 1 punchy sentence?
        □ Part 2 (COMPRESS IT) present as 2-3 expert sentences?
        □ Part 3 (SIMPLIFY IT) present with clear metaphor?
        □ Part 4 (WHY IT MATTERS) connects to hunter pain?
        □ Part 5 (AUTHORITY PROOF) references real research patterns (no fake studies)?
        □ Part 6 (YOUR EXAMPLE) uses specific data from raw notes only?
        □ Part 7 (TACTICAL APPLICATION) gives actionable steps?
        
        Content Check:
        □ Every fact/number anchored to raw notes (no hallucination)?
        □ Word count between \(section.effectiveWordCount) and \(section.effectiveWordCount + 100)?
        □ One sentence per line with no numbering?
        □ "You" language dominant (not "we" or "I" heavy)?
        □ At least one story loop (expectation → better reveal) per part?
        □ NO [B-ROLL:], [PAUSE], or any bracketed tags?
        
        Tone Check:
        □ Conversational hunting buddy tone?
        □ No mention of "Part 1/2/3" in output?
        □ No talking about "this script" or "this section"?
        □ Speaks directly as if recording the video?
        □ Slight southern/hunting camp phrasing present?
        
        ═══════════════════════════════════════════════════════════
        NOW WRITE THE COMPLETE FILMING-READY SCRIPT
        ═══════════════════════════════════════════════════════════
        
        IF raw notes are insufficient, STOP and ask Byron clarifying questions first.
        IF raw notes are sufficient, output ONLY the finished script with nothing else.
        """
        }
        
        private func parseAndSaveVersion() {
            let sentences = parseSentences(from: pastedText)
            
            let sentenceObjects = sentences.enumerated().map { index, text in
                YTSCRIPTOutlineSentence(text: text, orderIndex: index, part: .unknown)
            }
            
            let newVersion = YTSCRIPTSectionVersion(
                polishedText: pastedText,
                sentences: sentenceObjects
            )
            
            guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
            
            script.outlineSections[sectionIndex].sectionVersions.append(newVersion)
            script.outlineSections[sectionIndex].currentVersionIndex = script.outlineSections[sectionIndex].sectionVersions.count - 1
            
            // Copy splitter prompt
            let prompt = generateSplitterPrompt()
#if os(iOS)
            UIPasteboard.general.string = prompt
#else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
#endif
            
            // Show feedback
            withAnimation {
                parsedAndCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    parsedAndCopied = false
                }
            }
            
            pastedText = ""
            expandedSentenceId = nil
            autoSave()
        }
        
        
        private func parseSentences(from text: String) -> [String] {
            return SentenceParser.parse(text)
        }
        
        private func restoreVersion(at index: Int) {
            script.outlineSections[sectionIndex].currentVersionIndex = index
            expandedSentenceId = nil
            autoSave()
        }
        
        private func splitSentence(_ sentence: YTSCRIPTOutlineSentence) {
            let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
            guard versionIndex >= 0,
                  let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentence.id }) else { return }
            
            if sentence.text.contains("|") {
                let parts = sentence.text.components(separatedBy: "|")
                if parts.count == 2 {
                    let firstPart = parts[0].trimmingCharacters(in: .whitespaces)
                    let secondPart = parts[1].trimmingCharacters(in: .whitespaces)
                    
                    if !firstPart.isEmpty && !secondPart.isEmpty {
                        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text = firstPart
                        let newSentence = YTSCRIPTOutlineSentence(text: secondPart, orderIndex: sentenceIndex + 1, part: sentence.part)
                        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.insert(newSentence, at: sentenceIndex + 1)
                        reindexSentences()
                        autoSave()
                        expandedSentenceId = nil
                        return
                    }
                }
            }
            
            let newSentence = YTSCRIPTOutlineSentence(text: "", orderIndex: sentenceIndex + 1, part: sentence.part)
            script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.insert(newSentence, at: sentenceIndex + 1)
            reindexSentences()
            autoSave()
            expandedSentenceId = newSentence.id
        }
        
        private func mergeWithNext(_ sentence: YTSCRIPTOutlineSentence) {
            let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
            guard versionIndex >= 0,
                  let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentence.id }),
                  sentenceIndex < script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.count - 1 else { return }
            
            let nextSentence = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex + 1]
            script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text += " " + nextSentence.text
            
            script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.remove(at: sentenceIndex + 1)
            reindexSentences()
            autoSave()
        }
        
        private func deleteSentence(_ sentence: YTSCRIPTSectionSentence) {
            let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
            guard versionIndex >= 0 else { return }
            
            script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.removeAll { $0.id == sentence.id }
            reindexSentences()
            expandedSentenceId = nil
            autoSave()
        }
        
        private func reindexSentences() {
            let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
            guard versionIndex >= 0 else { return }
            
            for (index, _) in script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.enumerated() {
                script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[index].orderIndex = index
            }
        }
        
        private func copyAllText() {
            guard let current = currentVersion else { return }
            let text = current.sentences.map { $0.text }.joined(separator: "\n")
            
#if os(iOS)
            UIPasteboard.general.string = text
#else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
#endif
        }
        
        private func timeAgoString(from date: Date) -> String {
            let seconds = Int(Date().timeIntervalSince(date))
            
            if seconds < 60 {
                return "\(seconds) sec ago"
            } else if seconds < 3600 {
                let minutes = seconds / 60
                return "\(minutes) min ago"
            } else if seconds < 86400 {
                let hours = seconds / 3600
                return "\(hours) hr ago"
            } else {
                let days = seconds / 86400
                return "\(days) day\(days == 1 ? "" : "s") ago"
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

    
    // MARK: - Version Card
    
    struct VersionCard: View {
        let version: YTSCRIPTSectionVersion
        let versionNumber: Int
        let isCurrent: Bool
        let timeAgo: String
        let onRestore: () -> Void
        
        var body: some View {
            HStack {
                Circle()
                    .fill(isCurrent ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("v\(versionNumber)")
                            .font(.headline)
                            .foregroundColor(isCurrent ? .primary : .secondary)
                        
                        if isCurrent {
                            Text("CURRENT")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Text(version.timestamp ?? Date(), style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .foregroundStyle(.secondary)
                        
                        Text(timeAgo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .foregroundStyle(.secondary)
                        
                        Text("\(version.wordCount) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if !isCurrent {
                    Button {
                        onRestore()
                    } label: {
                        Text("Restore")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(isCurrent ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCurrent ? Color.green : Color.clear, lineWidth: 2)
            )
        }
    }
    
    // MARK: - Section Sentence Row
    
    struct SectionSentenceRow: View {
        @Bindable var script: YTSCRIPT
        let sectionIndex: Int
        var sentence: YTSCRIPTSectionSentence
        let isExpanded: Bool
        let onTap: () -> Void
        let onSplit: () -> Void
        let onMergeWithNext: (() -> Void)?
        let onDelete: () -> Void
        
        var versionIndex: Int {
            script.outlineSections[sectionIndex].currentVersionIndex
        }
        
        var sentenceIndex: Int {
            guard versionIndex >= 0 else { return 0 }
            return script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentence.id }) ?? 0
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if !isExpanded {
                    // Collapsed view
                    HStack(alignment: .top, spacing: 12) {
                        Text("S\(sentence.orderIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)
                        
                        Text(sentence.text)
                            .font(.body)
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap()
                    }
                } else {
                    // Expanded view
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("S\(sentence.orderIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button {
                                onTap()
                            } label: {
                                Image(systemName: "chevron.up.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        TextEditor(text: Binding(
                            get: { script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text },
                            set: { script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text = $0 }
                        ))
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        
                        Text("Tip: Add | where you want to split")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Divider()
                        
                        HStack(spacing: 8) {
                            Button {
                                onSplit()
                            } label: {
                                Label("Split", systemImage: "scissors")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            if let onMergeWithNext {
                                Button {
                                    onMergeWithNext()
                                } label: {
                                    Label("Merge ↓", systemImage: "arrow.down.to.line")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Spacer()
                            
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                }
            }
        }
    }
    
    // MARK: - Hacks Checklist View
    
    struct HacksChecklistView: View {
        @Bindable var script: YTSCRIPT
        let sectionIndex: Int
        
        var section: YTSCRIPTOutlineSection2 {
            script.outlineSections[sectionIndex]
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Psychology Hacks - Body Section")
                    .font(.headline)
                
                // Checkpoint 5
                hackCheckpoint(
                    title: "Checkpoint 5: Harness Attention",
                    hacks: [
                        ("hack_13", "Hack 13: Create a Hunt"),
                        ("hack_14", "Hack 14: Rehooking"),
                        ("hack_15", "Hack 15: Trance Rhythm")
                    ]
                )
                
                Divider()
                
                // Story Loops
                VStack(alignment: .leading, spacing: 12) {
                    Text("Story Loops Framework")
                        .font(.subheadline)
                        .bold()
                    
                    Toggle(isOn: Binding(
                        get: { section.appliedHacks.contains("storyloop") },
                        set: { isOn in
                            if isOn {
                                if !script.outlineSections[sectionIndex].appliedHacks.contains("storyloop") {
                                    script.outlineSections[sectionIndex].appliedHacks.append("storyloop")
                                }
                            } else {
                                script.outlineSections[sectionIndex].appliedHacks.removeAll { $0 == "storyloop" }
                            }
                        }
                    )) {
                        Text("Context → Reveal Structure")
                            .font(.caption)
                    }
                    
                    HStack(spacing: 8) {
                        Button {
                            copyPrompt(for: "storyloop", type: "check")
                        } label: {
                            Text("Check")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        Button {
                            copyPrompt(for: "storyloop", type: "fix")
                        } label: {
                            Text("Fix")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Context:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("What context are you setting?", text: Binding(
                            get: { script.outlineSections[sectionIndex].storyLoopContext },
                            set: { script.outlineSections[sectionIndex].storyLoopContext = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        
                        Text("Reveal:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("What's the payoff?", text: Binding(
                            get: { script.outlineSections[sectionIndex].storyLoopReveal },
                            set: { script.outlineSections[sectionIndex].storyLoopReveal = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        
                        Toggle("Exceeds expectations?", isOn: Binding(
                            get: { script.outlineSections[sectionIndex].revealExceedsExpectations },
                            set: { script.outlineSections[sectionIndex].revealExceedsExpectations = $0 }
                        ))
                        .font(.caption)
                    }
                }
                
                Divider()
                
                // Advanced Detection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Advanced Detection")
                        .font(.subheadline)
                        .bold()
                    
                    Button {
                        // TODO: Implement
                    } label: {
                        HStack {
                            Label("Check Duplication", systemImage: "magnifyingglass")
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    
                    Button {
                        // TODO: Implement
                    } label: {
                        HStack {
                            Label("Check Bleeding", systemImage: "arrow.left.arrow.right")
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    
                    Button {
                        // TODO: Implement
                    } label: {
                        HStack {
                            Label("Rhythm Analysis", systemImage: "waveform")
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
            }
        }
        
        private func hackCheckpoint(title: String, hacks: [(String, String)]) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .bold()
                
                ForEach(hacks, id: \.0) { hackId, hackName in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { section.appliedHacks.contains(hackId) },
                            set: { isOn in
                                if isOn {
                                    if !script.outlineSections[sectionIndex].appliedHacks.contains(hackId) {
                                        script.outlineSections[sectionIndex].appliedHacks.append(hackId)
                                    }
                                } else {
                                    script.outlineSections[sectionIndex].appliedHacks.removeAll { $0 == hackId }
                                }
                            }
                        )) {
                            Text(hackName)
                                .font(.caption)
                        }
                        
                        HStack(spacing: 8) {
                            Button {
                                copyPrompt(for: hackId, type: "check")
                            } label: {
                                Text("Check")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Button {
                                copyPrompt(for: hackId, type: "fix")
                            } label: {
                                Text("Fix")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
        
        private func copyPrompt(for hackId: String, type: String) {
            let sectionText = section.currentVersion?.sentences.map { $0.text }.joined(separator: "\n") ?? ""
            
            let prompt: String
            if type == "check" {
                prompt = generateCheckPrompt(for: hackId, sectionText: sectionText)
            } else {
                prompt = generateFixPrompt(for: hackId, sectionText: sectionText)
            }
            
#if os(iOS)
            UIPasteboard.general.string = prompt
#else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
#endif
        }
        
        private func generateCheckPrompt(for hackId: String, sectionText: String) -> String {
            let hackDescription = hackDescriptions[hackId] ?? ""
            
            return """
        Analyze this section for the following technique:
        
        \(hackDescription)
        
        Section text:
        \(sectionText)
        
        Does this section effectively use this technique? 
        Give specific examples of where it's present or missing.
        """
        }
        
        private func generateFixPrompt(for hackId: String, sectionText: String) -> String {
            let hackDescription = hackDescriptions[hackId] ?? ""
            
            return """
        Rewrite this section to implement the following technique:
        
        \(hackDescription)
        
        Current section:
        \(sectionText)
        
        Rewrite to include this technique while maintaining the target word count.
        Output sentence by sentence, one sentence per line.
        """
        }
        
        private let hackDescriptions: [String: String] = [
            "hack_13": "Create a Hunt - Open loops that viewers need to close. Tease valuable information throughout.",
            "hack_14": "Rehooking - Continually reignite the pain/solution gap to maintain attention.",
            "hack_15": "Trance Rhythm - Vary sentence length and cadence to create an engaging rhythm.",
            "storyloop": "Story Loops - Set clear context, then deliver a reveal that exceeds expectations."
        ]
    }
    
    struct PartGroupView: View {
        let part: KallawayPart
        let sentences: [YTSCRIPTOutlineSentence]
        let onUpdateSentence: (UUID, String) -> Void
        let onRewrite: () -> Void
        let onApplyRewrite: (String) -> Void  // ← NEW callback
        let onFlagSentence: (UUID) -> Void
        let onSplitSentence: (UUID) -> Void
        let onDeleteSentence: (UUID) -> Void
        
        @State private var isExpanded = true
        @State private var rewriteCopied = false
        @State private var showPasteArea = false  // ← NEW
        @State private var rewrittenText = ""      // ← NEW
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    
                    Text(part.displayName)
                        .font(.subheadline.bold())
                        .foregroundColor(partColor)
                    
                    Text("(\(sentences.count) sentences, \(wordCount) words)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if part != .unknown {
                        Button {
                            onRewrite()
                            showPasteArea = true  // ← Show paste area
                            
                            withAnimation {
                                rewriteCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation {
                                    rewriteCopied = false
                                }
                            }
                        } label: {
                            Label(
                                rewriteCopied ? "Copied!" : "Rewrite",
                                systemImage: rewriteCopied ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                // ← NEW: Paste Area (appears after clicking Rewrite)
                if showPasteArea {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste rewritten sentences below:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $rewrittenText)
                            .font(.body)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                        
                        HStack {
                            Button {
                                onApplyRewrite(rewrittenText)
                                rewrittenText = ""
                                showPasteArea = false
                            } label: {
                                Label("Apply Rewrite", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(rewrittenText.isEmpty)
                            
                            Button {
                                rewrittenText = ""
                                showPasteArea = false
                            } label: {
                                Text("Cancel")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                }
                
                // Sentences (when expanded)
                if isExpanded {
                    VStack(spacing: 4) {
                        ForEach(sentences) { sentence in
                            SimpleSentenceRow(
                                sentence: sentence,
                                onUpdate: { newText in
                                    onUpdateSentence(sentence.id, newText)
                                },
                                onFlag: {
                                    onFlagSentence(sentence.id)  // ⭐ NEW
                                },
                                onSplit: {
                                    onSplitSentence(sentence.id)  // ⭐ ADD THIS
                                },
                                onDelete: {  // ⭐ ADD THIS
                                    onDeleteSentence(sentence.id)
                                }
                            )
                        }
                    }
                    .padding(.leading, 20)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        
        //    // ... rest of the code stays the same
        //}
        //struct PartGroupView: View {
        //    let part: KallawayPart
        //    let sentences: [YTSCRIPTOutlineSentence]
        //    let onUpdateSentence: (UUID, String) -> Void
        //    let onRewrite: () -> Void
        //
        //    @State private var isExpanded = true
        //    @State private var rewriteCopied = false  // ← NEW
        //
        //    var body: some View {
        //        VStack(alignment: .leading, spacing: 8) {
        //            // Header
        //            HStack {
        //                Button {
        //                    isExpanded.toggle()
        //                } label: {
        //                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
        //                        .font(.caption)
        //                }
        //                .buttonStyle(.plain)
        //
        //                Text(part.displayName)
        //                    .font(.subheadline.bold())
        //                    .foregroundColor(partColor)
        //
        //                Text("(\(sentences.count) sentences, \(wordCount) words)")
        //                    .font(.caption)
        //                    .foregroundStyle(.secondary)
        //
        //                Spacer()
        //
        //                if part != .unknown {
        //                    Button {
        //                        onRewrite()
        //
        //                        // Show feedback
        //                        withAnimation {
        //                            rewriteCopied = true
        //                        }
        //                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        //                            withAnimation {
        //                                rewriteCopied = false
        //                            }
        //                        }
        //                    } label: {
        //                        Label(
        //                            rewriteCopied ? "Copied!" : "Rewrite",
        //                            systemImage: rewriteCopied ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
        //                        )
        //                        .font(.caption)
        //                    }
        //                    .buttonStyle(.bordered)
        //                    .controlSize(.small)
        //                }
        //            }
        //
        //            // Sentences (when expanded)
        //            if isExpanded {
        //                VStack(spacing: 4) {
        //                    ForEach(sentences) { sentence in
        //                        SimpleSentenceRow(
        //                            sentence: sentence,
        //                            onUpdate: { newText in
        //                                onUpdateSentence(sentence.id, newText)
        //                            }
        //                        )
        //                    }
        //                }
        //                .padding(.leading, 20)
        //            }
        //        }
        //        .padding()
        //        .background(Color(.secondarySystemBackground))
        //        .cornerRadius(8)
        //    }
        
        private var partColor: Color {
            switch part.color {
            case "purple": return .purple
            case "blue": return .blue
            case "green": return .green
            case "orange": return .orange
            case "red": return .red
            case "cyan": return .cyan
            case "indigo": return .indigo
            default: return .gray
            }
        }
        
        private var wordCount: Int {
            sentences.reduce(0) { $0 + $1.text.split(separator: " ").count }
        }
    }
    //struct PartGroupViewold: View {
    //    let part: KallawayPart
    //    let sentences: [YTSCRIPTOutlineSentence]
    //    let onUpdateSentence: (UUID, String) -> Void  // ← CHANGED
    //    let onRewrite: () -> Void
    //
    //    @State private var isExpanded = true
    //
    //    var body: some View {
    //        VStack(alignment: .leading, spacing: 8) {
    //            // Header
    //            HStack {
    //                Button {
    //                    isExpanded.toggle()
    //                } label: {
    //                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
    //                        .font(.caption)
    //                }
    //                .buttonStyle(.plain)
    //
    //                Text(part.displayName)
    //                    .font(.subheadline.bold())
    //                    .foregroundColor(partColor)
    //
    //                Text("(\(sentences.count) sentences, \(wordCount) words)")
    //                    .font(.caption)
    //                    .foregroundStyle(.secondary)
    //
    //                Spacer()
    //
    //                if part != .unknown {
    //                    Button {
    //                        onRewrite()
    //                    } label: {
    //                        Label("Rewrite", systemImage: "arrow.triangle.2.circlepath")
    //                            .font(.caption)
    //                    }
    //                    .buttonStyle(.bordered)
    //                    .controlSize(.small)
    //                }
    //            }
    //
    //            // Sentences (when expanded)
    //            if isExpanded {
    //                VStack(spacing: 4) {
    //                    ForEach(sentences) { sentence in
    //                        SimpleSentenceRow(
    //                            sentence: sentence,
    //                            onUpdate: { newText in
    //                                onUpdateSentence(sentence.id, newText)
    //                            }
    //                        )
    //                    }
    //                }
    //                .padding(.leading, 20)
    //            }
    //        }
    //        .padding()
    //        .background(Color(.secondarySystemBackground))
    //        .cornerRadius(8)
    //    }
    //
    //    private var partColor: Color {
    //        switch part.color {
    //        case "purple": return .purple
    //        case "blue": return .blue
    //        case "green": return .green
    //        case "orange": return .orange
    //        case "red": return .red
    //        case "cyan": return .cyan
    //        case "indigo": return .indigo
    //        default: return .gray
    //        }
    //    }
    //
    //    private var wordCount: Int {
    //        sentences.reduce(0) { $0 + $1.text.split(separator: " ").count }
    //    }
    //}
    
    // MARK: - Simple Sentence Row
    struct SimpleSentenceRow: View {
        let sentence: YTSCRIPTOutlineSentence
        let globalNumber: Int?  // Optional for backward compatibility
        let onUpdate: (String) -> Void
        let onFlag: () -> Void
        let onSplit: () -> Void
        let onDelete: () -> Void
        
        @State private var isExpanded = false
        @State private var editedText: String
        
        init(sentence: YTSCRIPTOutlineSentence,
             globalNumber: Int? = nil,
             onUpdate: @escaping (String) -> Void,
             onFlag: @escaping () -> Void,
             onSplit: @escaping () -> Void,
             onDelete: @escaping () -> Void) {
            self.sentence = sentence
            self.globalNumber = globalNumber
            self.onUpdate = onUpdate
            self.onFlag = onFlag
            self.onSplit = onSplit
            self.onDelete = onDelete
            self._editedText = State(initialValue: sentence.text)
        }
        
        var sentenceNumber: String {
            if let global = globalNumber {
                return "S\(global)"
            }
            return "S\(sentence.orderIndex + 1)"
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack {
                        Image(systemName: sentence.isFlagged ? "flag.fill" : "flag")
                            .font(.caption)
                            .foregroundColor(sentence.isFlagged ? .red : .gray)
                            .onTapGesture {
                                onFlag()
                            }
                        
                        Text(sentenceNumber)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .leading)
                        
                        Text(sentence.text)
                            .font(.body)
                            .lineLimit(isExpanded ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(sentence.isFlagged ? Color.red.opacity(0.1) : Color.clear)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    VStack(spacing: 8) {
                        TextEditor(text: $editedText)
                            .font(.body)
                            .frame(minHeight: 60)
                            .padding(8)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(4)
                            .onChange(of: editedText) { _, newValue in
                                onUpdate(newValue)
                            }
                            .onChange(of: sentence.text) { _, newValue in
                                editedText = newValue
                            }
                        
                        HStack {
                            Text("Tip: Add | to mark split point")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button {
                                onSplit()
                            } label: {
                                Label("Split", systemImage: "scissors")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    struct SimpleSentenceRowOld: View {
        let sentence: YTSCRIPTOutlineSentence
        let onUpdate: (String) -> Void
        let onFlag: () -> Void  // ⭐ NEW
        let onSplit: () -> Void
        let onDelete: () -> Void
        
        @State private var isExpanded = false
        @State private var editedText: String
        
        init(sentence: YTSCRIPTOutlineSentence,
             onUpdate: @escaping (String) -> Void,
             onFlag: @escaping () -> Void,
             onSplit: @escaping () -> Void,
             onDelete: @escaping () -> Void) {  // ⭐ ADD THIS
            self.sentence = sentence
            self.onUpdate = onUpdate
            self.onFlag = onFlag
            self.onSplit = onSplit
            self.onDelete = onDelete  // ⭐ ADD THIS
            self._editedText = State(initialValue: sentence.text)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack {
                        // ⭐ NEW: Flag indicator
                        Image(systemName: sentence.isFlagged ? "flag.fill" : "flag")
                            .font(.caption)
                            .foregroundColor(sentence.isFlagged ? .red : .gray)
                            .onTapGesture {
                                onFlag()
                            }
                        
                        Text("S\(sentence.orderIndex + 1)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)
                        
                        Text(sentence.text)
                            .font(.body)
                            .lineLimit(isExpanded ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(sentence.isFlagged ? Color.red.opacity(0.1) : Color.clear)  // ⭐ Highlight flagged
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    VStack(spacing: 8) {
                        TextEditor(text: $editedText)
                            .font(.body)
                            .frame(minHeight: 60)
                            .padding(8)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(4)
                            .onChange(of: editedText) { _, newValue in
                                onUpdate(newValue)
                            }
                            .onChange(of: sentence.text) { _, newValue in  // ⭐ ADD THIS
                                editedText = newValue  // Sync when sentence changes externally
                            }
                        
                        // ⭐ ADD SPLIT BUTTON HERE
                        HStack {
                            Text("Tip: Add | to mark split point")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button {
                                onSplit()  // ← NEW callback
                            } label: {
                                Label("Split", systemImage: "scissors")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    struct SimpleSentenceRow1: View {
        let sentence: YTSCRIPTOutlineSentence
        let onUpdate: (String) -> Void
        
        @State private var isExpanded = false
        @State private var editedText: String
        
        init(sentence: YTSCRIPTOutlineSentence, onUpdate: @escaping (String) -> Void) {
            self.sentence = sentence
            self.onUpdate = onUpdate
            self._editedText = State(initialValue: sentence.text)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack {
                        Text("S\(sentence.orderIndex + 1)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)
                        
                        Text(sentence.text)
                            .font(.body)
                            .lineLimit(isExpanded ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    TextEditor(text: $editedText)
                        .font(.body)
                        .frame(minHeight: 60)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(4)
                        .onChange(of: editedText) { _, newValue in
                            onUpdate(newValue)
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

