//
//  FinalScriptView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/18/25.
//
import SwiftUI

struct FinalScriptView: View {
    @Bindable var script: YTSCRIPT
    
    var activeSections: [YTSCRIPTOutlineSection2] {
        script.outlineSections
            .filter { !$0.isArchived }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }
    
    var allSentences: [(section: YTSCRIPTOutlineSection2, sentence: YTSCRIPTOutlineSentence)] {
        var result: [(YTSCRIPTOutlineSection2, YTSCRIPTOutlineSentence)] = []
        for section in activeSections {
            if section.currentVersionIndex >= 0,
               section.currentVersionIndex < section.sectionVersions.count {
                let currentVersion = section.sectionVersions[section.currentVersionIndex]
                for sentence in currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    result.append((section, sentence))
                }
            }
        }
        return result
    }
    
    var totalWordCount: Int {
        allSentences.reduce(0) { $0 + $1.sentence.text.split(separator: " ").count }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                scriptSection
            }
            .padding()
        }
        .navigationTitle("Final Script")
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final Script")
                .font(.title2)
                .bold()
            
            HStack(spacing: 32) {
                VStack(alignment: .leading) {
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(allSentences.count) sentences")
                        .font(.headline)
                }
                
                VStack(alignment: .leading) {
                    Text("Words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(totalWordCount) words")
                        .font(.headline)
                }
                
                VStack(alignment: .leading) {
                    Text("Est. Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f min", Double(totalWordCount) / script.wordsPerMinute))
                        .font(.headline)
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
            
            // Copy buttons
            HStack(spacing: 12) {
                CopyButtonAction(label: "Plain Text") {
                    copyPlainText()
                }
                
                CopyButtonAction(label: "With Line Numbers") {
                    copyWithLineNumbers()
                }
                
                CopyButtonAction(label: "With Section Headers") {
                    copyWithSectionHeaders()
                }
            }
        }
    }
    
    private var scriptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(activeSections) { section in
                sectionBlock(for: section)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
    
    private func sectionBlock(for section: YTSCRIPTOutlineSection2) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(section.name)
                .font(.title3)
                .bold()
                .foregroundColor(.blue)
            
            // Sentences for this section
            if section.currentVersionIndex >= 0,
               section.currentVersionIndex < section.sectionVersions.count {
                let currentVersion = section.sectionVersions[section.currentVersionIndex]
                let sentences = currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex })
                
                ForEach(sentences) { sentence in
                    let globalIndex = globalSentenceIndex(for: sentence, in: section)
                    
                    SimpleSentenceRow(
                        sentence: sentence,
                        globalNumber: globalIndex,
                        onUpdate: { newText in
                            updateSentence(sentenceId: sentence.id, in: section, newText: newText)
                        },
                        onFlag: {
                            toggleSentenceFlag(sentenceId: sentence.id, in: section)
                        },
                        onSplit: {
                            splitSentence(sentenceId: sentence.id, in: section)
                        },
                        onDelete: {
                            deleteSentence(sentenceId: sentence.id, in: section)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func globalSentenceIndex(for sentence: YTSCRIPTOutlineSentence, in targetSection: YTSCRIPTOutlineSection2) -> Int {
        var index = 1
        for section in activeSections {
            if section.id == targetSection.id {
                if let currentVersion = section.sectionVersions[safe: section.currentVersionIndex] {
                    if let sentenceIndex = currentVersion.sentences.firstIndex(where: { $0.id == sentence.id }) {
                        return index + sentenceIndex
                    }
                }
                return index
            } else {
                if let currentVersion = section.sectionVersions[safe: section.currentVersionIndex] {
                    index += currentVersion.sentences.count
                }
            }
        }
        return index
    }
    
    private func updateSentence(sentenceId: UUID, in section: YTSCRIPTOutlineSection2, newText: String) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0,
              let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentenceId }) else { return }
        
        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text = newText
        autoSave()
    }
    
    private func toggleSentenceFlag(sentenceId: UUID, in section: YTSCRIPTOutlineSection2) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0,
              let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentenceId }) else { return }
        
        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].isFlagged.toggle()
        autoSave()
    }
    
    private func splitSentence(sentenceId: UUID, in section: YTSCRIPTOutlineSection2) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0,
              let sentenceIndex = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.firstIndex(where: { $0.id == sentenceId }) else { return }
        
        let sentence = script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex]
        
        if sentence.text.contains("|") {
            let parts = sentence.text.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            if parts.count >= 2 {
                script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[sentenceIndex].text = parts[0]
                
                for (index, part) in parts.dropFirst().enumerated() {
                    let newSentence = YTSCRIPTOutlineSentence(
                        text: part,
                        orderIndex: sentenceIndex + 1 + index,
                        part: sentence.part
                    )
                    script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.insert(newSentence, at: sentenceIndex + 1 + index)
                }
                
                reindexSentences(in: sectionIndex)
                autoSave()
                return
            }
        }
        
        let newSentence = YTSCRIPTOutlineSentence(
            text: "",
            orderIndex: sentenceIndex + 1,
            part: sentence.part
        )
        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.insert(newSentence, at: sentenceIndex + 1)
        reindexSentences(in: sectionIndex)
        autoSave()
    }
    
    private func deleteSentence(sentenceId: UUID, in section: YTSCRIPTOutlineSection2) {
        guard let sectionIndex = script.outlineSections.firstIndex(where: { $0.id == section.id }) else { return }
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0 else { return }
        
        script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.removeAll { $0.id == sentenceId }
        reindexSentences(in: sectionIndex)
        autoSave()
    }
    
    private func reindexSentences(in sectionIndex: Int) {
        let versionIndex = script.outlineSections[sectionIndex].currentVersionIndex
        guard versionIndex >= 0 else { return }
        
        for (index, _) in script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences.enumerated() {
            script.outlineSections[sectionIndex].sectionVersions[versionIndex].sentences[index].orderIndex = index
        }
    }
    
    // MARK: - Copy Functions
    
    private func copyPlainText() {
        var text = ""
        for section in activeSections {
            if section.currentVersionIndex >= 0,
               section.currentVersionIndex < section.sectionVersions.count {
                let currentVersion = section.sectionVersions[section.currentVersionIndex]
                for sentence in currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    text += sentence.text + "\n"
                }
            }
        }
        
        copyToClipboard(text)
    }
    
    private func copyWithLineNumbers() {
        var text = ""
        var globalIndex = 1
        
        for section in activeSections {
            if section.currentVersionIndex >= 0,
               section.currentVersionIndex < section.sectionVersions.count {
                let currentVersion = section.sectionVersions[section.currentVersionIndex]
                for sentence in currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    text += "S\(globalIndex): \(sentence.text)\n"
                    globalIndex += 1
                }
            }
        }
        
        copyToClipboard(text)
    }
    
    private func copyWithSectionHeaders() {
        var text = ""
        var globalIndex = 1
        
        for section in activeSections {
            text += "\(section.name)\n\n"
            
            if section.currentVersionIndex >= 0,
               section.currentVersionIndex < section.sectionVersions.count {
                let currentVersion = section.sectionVersions[section.currentVersionIndex]
                for sentence in currentVersion.sentences.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    text += "S\(globalIndex): \(sentence.text)\n"
                    globalIndex += 1
                }
            }
            
            text += "\n"
        }
        
        copyToClipboard(text)
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
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

// Helper extension for safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
