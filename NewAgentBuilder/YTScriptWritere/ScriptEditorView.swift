//
//  ScriptEditorView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 11/19/25.
//
import SwiftUI

// MARK: - Script Editor View (Outline + Points)
struct ScriptEditorView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var store = ScriptStore.instance
    @ObservedObject var script: YTScript
    
    @State private var showingTitleIdeas = false
    @State private var pastedTitles = ""
    @State private var titleIdeas: [String] = []
    
    var fullScriptText: String {
        var text = ""
        
        if let hook = script.hook {
            text += "HOOK:\n"
            text += hook.variations[hook.selectedIndex]
            text += "\n\n"
        }
        
        for point in script.points {
            text += "\(point.title.uppercased()):\n"
            for sentence in point.sentences {
                text += sentence.text + " "
            }
            text += "\n\n"
        }
        
        if let outro = script.outro {
            text += "OUTRO:\n"
            text += outro.text
        }
        
        return text
    }
    
    var titlePrompt: String {
        var context = "Current title: \(script.title)\n\n"
        
        // Add points for context
        context += "Video points:\n"
        for (index, point) in script.points.enumerated() {
            context += "\(index + 1). \(point.title)\n"
        }
        
        // Add hook if exists
        if let hook = script.hook, !hook.variations.isEmpty {
            context += "\nHook: \(hook.variations[hook.selectedIndex])\n"
        }
        
        return """
        You are helping create YouTube video titles for a hunting education channel.
        
        \(context)
        
        Task: Generate 5-7 compelling YouTube video titles. Each title should be:
        - Attention-grabbing and click-worthy
        - Accurate to the content
        - 50-70 characters ideal
        - Use curiosity, numbers, or bold claims when appropriate
        
        Output one title per line.
        """
    }
    
    var body: some View {
        List {
            // Title Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Title", text: $script.title, axis: .vertical)
                        .font(.title3)
                        .bold()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .onChange(of: script.title) { _, _ in
                            store.updateScript(script)
                        }
                }
                
                Button {
                    showingTitleIdeas.toggle()
                } label: {
                    Label(
                        showingTitleIdeas ? "Hide Title Ideas" : "Generate Title Ideas",
                        systemImage: showingTitleIdeas ? "chevron.up" : "sparkles"
                    )
                }
            }
            
            // Title Ideas Section (Expandable)
            if showingTitleIdeas {
                Section {
                    CopyButton(label: "Title Prompt", valueToCopy: titlePrompt)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste AI Title Ideas Here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $pastedTitles)
                            .frame(height: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                        
                        HStack {
                            Button {
                                parseTitleIdeas()
                            } label: {
                                Label("Parse Titles", systemImage: "text.badge.checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(pastedTitles.isEmpty)
                            
                            if !pastedTitles.isEmpty {
                                Button {
                                    pastedTitles = ""
                                } label: {
                                    Label("Clear", systemImage: "xmark.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    
                    if !titleIdeas.isEmpty {
                        ForEach(Array(titleIdeas.enumerated()), id: \.offset) { index, title in
                            Button {
                                script.title = title
                                store.updateScript(script)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        
                                        Text("\(title.count) characters")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if script.title == title {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button(role: .destructive) {
                            titleIdeas.removeAll()
                            pastedTitles = ""
                        } label: {
                            Label("Clear Title Ideas", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Title Ideas")
                }
            }
            
            // Hook Section
            Section {
                if let hook = script.hook {
                    ForEach(hook.variations.indices, id: \.self) { index in
                        HStack {
                            Text(hook.variations[index])
                                .font(.body)
                            Spacer()
                            if index == hook.selectedIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            hook.selectedIndex = index
                            store.updateScript(script)
                        }
                    }
                } else {
                    Button {
                        // Generate hook
                        generateMockHook()
                    } label: {
                        Label("Generate Hook", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("Hook")
            }
            
            // Points Section
            Section {
                ForEach(script.points) { point in
                    Button {
                        nav.push(.pointEditor(script, point))
                    } label: {
                        HStack {
                            Text("\(point.orderIndex + 1).")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .leading)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(point.title)
                                    .font(.headline)
                                
                                if point.wordCount > 0 {
                                    Text("\(point.wordCount) words • \(point.estimatedDuration)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onMove { from, to in
                    script.points.move(fromOffsets: from, toOffset: to)
                    for (index, point) in script.points.enumerated() {
                        point.orderIndex = index
                    }
                    store.updateScript(script)
                }
            } header: {
                Text("Points")
            }
            
            // Outro Section
            Section {
                if let outro = script.outro {
                    Text(outro.text)
                } else {
                    Button {
                        generateMockOutro()
                    } label: {
                        Label("Generate Outro", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("Outro")
            }
            
            // Stats Section
            Section {
                HStack {
                    Text("Total Word Count")
                    Spacer()
                    Text("\(script.totalWordCount)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Estimated Duration")
                    Spacer()
                    Text(script.estimatedDuration)
                        .foregroundStyle(.secondary)
                }
                
                Picker("Status", selection: $script.status) {
                    ForEach(ScriptStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .onChange(of: script.status) { _, _ in
                    store.updateScript(script)
                }
            } header: {
                Text("Script Stats")
            }
            
            // Actions
            Section {
                Button {
                    nav.push(.fullScriptView(script))
                } label: {
                    Label("View Full Script", systemImage: "doc.text")
                }
                
                HStack {
                    CopyButton(
                        label: "Full Script",
                        valueToCopy: fullScriptText
                    )
                }
            }
        }
        .navigationTitle("Edit Script")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
    }
    
    func generateMockHook() {
        script.hook = Hook(
            variations: [
                "Hook variation 1 for \(script.title)",
                "Hook variation 2 for \(script.title)",
                "Hook variation 3 for \(script.title)"
            ],
            selectedIndex: 0
        )
        store.updateScript(script)
    }
    
    func generateMockOutro() {
        script.outro = Outro(text: "Thanks for watching! Don't forget to subscribe for more content.")
        store.updateScript(script)
    }
    
    func parseTitleIdeas() {
        titleIdeas = pastedTitles
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        pastedTitles = ""
    }
}
//```
//
//---
//
//## NOW YOU CAN:
//
//### **1. Edit Title Directly**
//- Tap in the title field at the top
//- Edit it like any text field
//- Auto-saves on change
//
//### **2. Generate Title Ideas**
//- Tap "Generate Title Ideas" button
//- Tap "Copy Title Prompt" 
//- Paste into Claude.ai
//- Copy the list of titles Claude generates
//- Paste back into "Paste AI Title Ideas Here"
//- Tap "Parse Titles"
//- See list of clickable title options
//- Tap any title to use it
//- Character count shown for each
//
//### **3. Workflow:**
//```
//1. Create script with rough title
//2. Fill in points, hook, etc.
//3. Tap "Generate Title Ideas"
//4. Copy prompt → Claude.ai
//5. Get 5-7 title suggestions
//6. Paste back
//7. Parse
//8. Tap to select best one
//9. Or manually edit the title field
