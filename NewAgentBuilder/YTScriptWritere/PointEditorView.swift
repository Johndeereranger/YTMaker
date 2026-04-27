//
//  PointEditorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/19/25.
//

import SwiftUI// MARK: - Point Editor View
// MARK: - Point Editor View
// MARK: - Point Editor View
// MARK: - Point Editor View
struct PointEditorView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var store = ScriptStore.instance
    @ObservedObject var script: YTScript
    @ObservedObject var point: Point
    
    @State private var expandedSentenceId: UUID? = nil
    @State private var pastedText = ""
    @State private var showingNotSetupAlert = false
    
    var promptText: String {
        """
        You are writing ONE point for a YouTube hunting education video.
        
        Point Title: \(point.title)
        
        Raw Notes:
        \(point.rawNotes)
        
        Task: Expand these raw notes into a complete, filming-ready script for this ONE point. Output sentence by sentence, one sentence per line.
        """
    }
    
    var pointText: String {
        point.sentences.map { $0.text }.joined(separator: "\n")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Point Title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Point title", text: $point.title)
                        .font(.title2)
                        .bold()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: point.title) { _, _ in
                            store.updateScript(script)
                        }
                }
                
                // Raw Notes (ALWAYS VISIBLE)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw Notes (Speech-to-Text)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $point.rawNotes)
                        .frame(minHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: point.rawNotes) { _, _ in
                            store.updateScript(script)
                        }
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button {
                        showingNotSetupAlert = true
                    } label: {
                        Label("Generate with AI", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(point.rawNotes.isEmpty)
                    
                    CopyButton(label: "Prompt", valueToCopy: promptText)
                        .disabled(point.rawNotes.isEmpty)
                        .opacity(point.rawNotes.isEmpty ? 0.5 : 1.0)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // PASTE AREA (ALWAYS VISIBLE)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Paste AI Output Here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if !point.sentences.isEmpty {
                            Text("(Will replace current script)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                    
                    HStack(spacing: 12) {
                        Button {
                            parsePastedText()
                        } label: {
                            Label("Parse into Sentences", systemImage: "text.badge.checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pastedText.isEmpty)
                        
                        if !pastedText.isEmpty {
                            Button {
                                pastedText = ""
                            } label: {
                                Label("Clear", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                // Generated Script Section
                if !point.sentences.isEmpty {
                    Divider()
                        .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Generated Script")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("\(point.wordCount) words • \(point.estimatedDuration)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Sentences with inline editing
                        ForEach(Array(point.sentences.enumerated()), id: \.element.id) { index, sentence in
                            InlineSentenceEditor(
                                sentence: sentence,
                                isExpanded: expandedSentenceId == sentence.id,
                                onTap: {
                                    withAnimation {
                                        if expandedSentenceId == sentence.id {
                                            expandedSentenceId = nil
                                        } else {
                                            expandedSentenceId = sentence.id
                                        }
                                    }
                                },
                                onSplit: {
                                    splitSentence(sentence)
                                },
                                onMergeWithNext: index < point.sentences.count - 1 ? {
                                    mergeWithNext(sentence)
                                } : nil,
                                onDelete: {
                                    deleteSentence(sentence)
                                },
                                onUpdate: {
                                    store.updateScript(script)
                                }
                            )
                        }
                        
                        // Quick Actions
                        HStack(spacing: 12) {
                            CopyButton(label: "Point Text", valueToCopy: pointText)
                            
                            Button {
                                checkDuplication()
                            } label: {
                                Label("Check Duplications", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(role: .destructive) {
                                clearSentences()
                            } label: {
                                Label("Clear Script", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Edit Point")
        .navigationBarTitleDisplayMode(.inline)
        .alert("AI Generation Not Set Up", isPresented: $showingNotSetupAlert) {
            Button("OK") { }
        } message: {
            Text("Direct AI generation is not yet implemented. Please use 'Copy Prompt' and paste into Claude.ai for now.")
        }
    }
    
    func parsePastedText() {
        let sentences = parseSentences(from: pastedText)
        
        point.sentences = sentences.enumerated().map { index, text in
            Sentence(orderIndex: index, text: text)
        }
        
        pastedText = ""
        expandedSentenceId = nil
        store.updateScript(script)
    }
    
    func parseSentences(from text: String) -> [String] {
        return SentenceParser.parse(text)
    }
    
    func splitSentence(_ sentence: Sentence) {
        guard let index = point.sentences.firstIndex(where: { $0.id == sentence.id }) else { return }
        
        // Check if user added a pipe character "|" to mark split point
        if sentence.text.contains("|") {
            let parts = sentence.text.components(separatedBy: "|")
            if parts.count == 2 {
                let firstPart = parts[0].trimmingCharacters(in: .whitespaces)
                let secondPart = parts[1].trimmingCharacters(in: .whitespaces)
                
                if !firstPart.isEmpty && !secondPart.isEmpty {
                    sentence.text = firstPart
                    let newSentence = Sentence(orderIndex: index + 1, text: secondPart)
                    point.sentences.insert(newSentence, at: index + 1)
                    reindexSentences()
                    store.updateScript(script)
                    expandedSentenceId = nil
                    return
                }
            }
        }
        
        // Otherwise create a blank sentence below for them to fill
        let newSentence = Sentence(orderIndex: index + 1, text: "")
        point.sentences.insert(newSentence, at: index + 1)
        reindexSentences()
        store.updateScript(script)
        expandedSentenceId = newSentence.id
    }
    
    func mergeWithNext(_ sentence: Sentence) {
        guard let index = point.sentences.firstIndex(where: { $0.id == sentence.id }),
              index < point.sentences.count - 1 else { return }
        
        let nextSentence = point.sentences[index + 1]
        sentence.text = sentence.text + " " + nextSentence.text
        
        point.sentences.remove(at: index + 1)
        reindexSentences()
        store.updateScript(script)
    }
    
    func deleteSentence(_ sentence: Sentence) {
        point.sentences.removeAll { $0.id == sentence.id }
        reindexSentences()
        expandedSentenceId = nil
        store.updateScript(script)
    }
    
    func reindexSentences() {
        for (index, sentence) in point.sentences.enumerated() {
            sentence.orderIndex = index
        }
    }
    
    func checkDuplication() {
        for sentence in point.sentences {
            if sentence.text.lowercased().contains("mock") {
                if !sentence.flags.contains(.duplicate) {
                    sentence.flags.append(.duplicate)
                }
            }
        }
        store.updateScript(script)
    }
    
    func clearSentences() {
        point.sentences.removeAll()
        expandedSentenceId = nil
        store.updateScript(script)
    }
}

// MARK: - Inline Sentence Editor Component
struct InlineSentenceEditor: View {
    @ObservedObject var sentence: Sentence
    let isExpanded: Bool
    let onTap: () -> Void
    let onSplit: () -> Void
    let onMergeWithNext: (() -> Void)?
    let onDelete: () -> Void
    let onUpdate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed view (tap to expand)
            if !isExpanded {
                HStack(alignment: .top, spacing: 12) {
                    Text("S\(sentence.orderIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                    
                    Text(sentence.text)
                        .font(.body)
                    
                    Spacer()
                    
                    if !sentence.flags.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(sentence.flags, id: \.self) { flag in
                                Image(systemName: flag.icon)
                                    .foregroundStyle(flag.color)
                                    .font(.caption)
                            }
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }
            }
            
            // Expanded view (inline editor)
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
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
                    
                    // Text Editor
                    TextEditor(text: $sentence.text)
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        .onChange(of: sentence.text) { _, _ in
                            onUpdate()
                        }
                    
                    Text("Tip: Add | where you want to split")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    // Flags
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Flags")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        ForEach(SentenceFlag.allCases, id: \.self) { flag in
                            Toggle(flag.rawValue, isOn: Binding(
                                get: { sentence.flags.contains(flag) },
                                set: { isOn in
                                    if isOn {
                                        if !sentence.flags.contains(flag) {
                                            sentence.flags.append(flag)
                                        }
                                    } else {
                                        sentence.flags.removeAll { $0 == flag }
                                    }
                                    onUpdate()
                                }
                            ))
                            .toggleStyle(.switch)
                            .font(.caption)
                        }
                    }
                    
                    Divider()
                    
                    // Action Buttons
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
