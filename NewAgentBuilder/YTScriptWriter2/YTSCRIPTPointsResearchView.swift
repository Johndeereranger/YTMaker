//
//  YTSCRIPTPointsResearchView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/6/25.
//


import SwiftUI

struct YTSCRIPTPointsResearchView: View {
    @Bindable var script: YTSCRIPT
    @State private var showingAddPoint = false
    @State private var newPointTitle = ""
    @State private var collapseAllTrigger = 0  // ← SIMPLE TRIGGER
    @State private var expandAllTrigger = 0    // ← SIMPLE TRIGGER
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Points & Research")
                            .font(.title2)
                            .bold()
                        Text("Create research points - organize them later in Outline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    CopyButton(
                        label: "All Research",
                        valueToCopy: generateCopyText(),
                        font: .headline
                    )
                    .buttonStyle(.bordered)
                    
                    Button {
                        collapseAllTrigger += 1  // ← INCREMENT TO TRIGGER
                    } label: {
                        Label("Collapse All", systemImage: "chevron.up.circle")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        expandAllTrigger += 1  // ← INCREMENT TO TRIGGER
                    } label: {
                        Label("Expand All", systemImage: "chevron.down.circle")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        showingAddPoint = true
                    } label: {
                        Label("Add Point", systemImage: "plus.circle.fill")
                    }
                }
                
                // Stats
                HStack {
                    Text("\(script.researchPoints.count) research points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(totalWords) words total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Points List
                if script.researchPoints.isEmpty {
                    ContentUnavailableView(
                        "No Research Points Yet",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Add your first research point to start collecting material")
                    )
                    .padding(.vertical, 60)
                } else {
                    ForEach(script.researchPoints) { point in
                        YTSCRIPTResearchPointCard(
                            script: script,
                            point: point,
                            collapseAllTrigger: collapseAllTrigger,  // ← PASS TRIGGER
                            expandAllTrigger: expandAllTrigger        // ← PASS TRIGGER
                        )
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Points & Research")
        .sheet(isPresented: $showingAddPoint) {
            addPointSheet
        }
    }
    
    private var totalWords: Int {
        script.researchPoints.reduce(0) { $0 + $1.currentWordCount }
    }
    
    private var addPointSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Point Title", text: $newPointTitle)
                }
                Section {
                    Text("Give this research point a clear title. You'll organize them into your script later in the Outline step.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Research Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddPoint = false
                        newPointTitle = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addPoint()
                    }
                    .disabled(newPointTitle.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 250)
    }
    
    private func addPoint() {
        let newPoint = YTSCRIPTResearchPoint(title: newPointTitle)
        script.researchPoints.append(newPoint)
        script.researchPoints = script.researchPoints  // ← FORCE UPDATE
        showingAddPoint = false
        newPointTitle = ""
    }
    
    private func generateCopyText() -> String {
        var output = ""
        
        output += "# \(script.title)\n\n"
        output += "## Research Points (\(script.researchPoints.count) total)\n\n"
        output += "**Total Words:** \(totalWords)\n\n"
        output += "---\n\n"
        
        for (index, point) in script.researchPoints.enumerated() {
            output += "### \(index + 1). \(point.title)\n\n"
            
            if !point.rawNotes.isEmpty {
                output += "**Raw Notes:**\n\(point.rawNotes)\n\n"
            }
            
            if let polished = point.activeVersion {
                output += "**Polished Version:**\n\(polished.content)\n\n"
            }
            
            if !point.visualNotes.isEmpty {
                output += "**Visual Notes:** \(point.visualNotes)\n\n"
            }
            
            output += "---\n\n"
        }
        
        return output
    }
}

// MARK: - Research Point Card
struct YTSCRIPTResearchPointCard: View {
    @Bindable var script: YTSCRIPT
    let point: YTSCRIPTResearchPoint
    let collapseAllTrigger: Int  // ← RECEIVE TRIGGER
    let expandAllTrigger: Int    // ← RECEIVE TRIGGER
    @State private var isExpanded = true
    //@Binding var isExpanded: Bool
    @State private var isPolishing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                
                TextField("Point Title", text: titleBinding)
                    .font(.headline)
                    .textFieldStyle(.plain)
                
                Spacer()
                
                // Quick stats
                if !isExpanded {
                    HStack(spacing: 12) {
                        if point.activeVersion != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        
                        Text("\(point.currentWordCount) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button(role: .destructive) {
                    deletePoint()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                Divider()
                
                // Raw Notes
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Raw Notes (your rambling)")
                            .font(.subheadline)
                            .bold()
                        Spacer()
                        Button {
                            // TODO: Start voice recording
                        } label: {
                            Label("Record", systemImage: "mic.circle")
                                .font(.caption)
                        }
                    }
                    
                    TextEditor(text: rawNotesBinding)
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    
                    Text("\(point.rawNotes.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Polish Button
                HStack {
                    Button {
                        Task { await polishWithAI() }
                    } label: {
                        HStack {
                            if isPolishing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Label(isPolishing ? "Polishing..." : "Polish with AI", 
                                  systemImage: "sparkles")
                        }
                    }
                    .disabled(point.rawNotes.isEmpty || isPolishing)
                    
                    Spacer()
                }
                
                // Polished Version (if exists)
                if let polished = point.activeVersion {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Polished Version", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(.green)
                            
                            Spacer()
                            
                            Text("\(polished.wordCount) words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        ScrollView {
                            Text(polished.content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        .padding(12)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                        
                        HStack {
                            if !polished.note.isEmpty {
                                Text(polished.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(polished.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Visual Notes
                VStack(alignment: .leading, spacing: 4) {
                    Text("Visual Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("B-roll, thermal clips, graphics, drone footage...", text: visualNotesBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }
        }
        .onChange(of: collapseAllTrigger) { _, _ in
            isExpanded = false  // ← COLLAPSE WHEN TRIGGERED
        }
        .onChange(of: expandAllTrigger) { _, _ in
            isExpanded = true  // ← EXPAND WHEN TRIGGERED
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
    }
    
    // Bindings
    private var titleBinding: Binding<String> {
        Binding(
            get: { pointFromScript?.title ?? point.title },
            set: { newValue in
                if let index = script.researchPoints.firstIndex(where: { $0.id == point.id }) {
                    script.researchPoints[index].title = newValue
                    script.researchPoints = script.researchPoints  // ← FORCE UPDATE
                }
            }
        )
    }
    
    private var rawNotesBinding: Binding<String> {
        Binding(
            get: { pointFromScript?.rawNotes ?? point.rawNotes },
            set: { newValue in
                if let index = script.researchPoints.firstIndex(where: { $0.id == point.id }) {
                    script.researchPoints[index].rawNotes = newValue
                    script.researchPoints = script.researchPoints  // ← FORCE UPDATE
                }
            }
        )
    }
    
    private var visualNotesBinding: Binding<String> {
        Binding(
            get: { pointFromScript?.visualNotes ?? point.visualNotes },
            set: { newValue in
                if let index = script.researchPoints.firstIndex(where: { $0.id == point.id }) {
                    script.researchPoints[index].visualNotes = newValue
                    script.researchPoints = script.researchPoints  // ← FORCE UPDATE
                }
            }
        )
    }
    
    private var pointFromScript: YTSCRIPTResearchPoint? {
        script.researchPoints.first(where: { $0.id == point.id })
    }
    
    // Actions
    private func polishWithAI() async {
        isPolishing = true
        
        // TODO: Replace with real AI call
        try? await Task.sleep(for: .seconds(2))
        
        if let index = script.researchPoints.firstIndex(where: { $0.id == point.id }) {
            let polished = YTSCRIPTPointVersion(
                content: "POLISHED: \(point.rawNotes)\n\n[This would be the AI-polished version]",
                note: "AI Polish v\(point.polishedVersions.count + 1)",
                promptUsed: "Polish this hunting research point..."
            )
            script.researchPoints[index].polishedVersions.append(polished)
            script.researchPoints[index].activeVersionIndex = script.researchPoints[index].polishedVersions.count - 1
        }
        
        isPolishing = false
    }
    
    private func deletePoint() {
        script.researchPoints.removeAll { $0.id == point.id }
        script.researchPoints = script.researchPoints  // ← FORCE UPDATE
    }
}
