//
//  YTSCRIPTStep.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/5/25.
//


import SwiftUI
enum YTSCRIPTStep: String, CaseIterable, Identifiable {
    case pitchDeck = "Pitch Deck"  // ← ADD AT TOP
    case mission = "Mission"
    case brainDump = "Brain Dump"
    case pointsResearch = "Points & Research"
    case angle = "Angle"
    case outline = "Outline"
    case package = "Package"
    case finalScript = "Final Script"
    case polish = "Polish"
    case guidelines = "Guidelines"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .pitchDeck: return "rectangle.stack"  // ← ADD THIS
        case .angle: return "angle.turn.left.fill"
        case .brainDump: return "briefcase.fill"
        case .mission: return "target"
        case .pointsResearch: return "list.bullet.clipboard"
        case .outline: return "list.bullet.indent"
        case .package: return "shippingbox"
        case .finalScript: return "doc.text"
        case .polish: return "sparkles"
        case .guidelines: return "pencil.and.outline"
        }
    }
}
//
//enum YTSCRIPTStep: String, CaseIterable, Identifiable {
//    case mission = "Mission"
//    case brainDump = "Brain Dump"
//    case pointsResearch = "Points & Research"  // NEW
//    case angle = "Angle"
//    case outline = "Outline"                    // NEW
//    case package = "Package"
//    case finalScript = "Final Script"
//    case polish = "Polish"
//    case guidelines = "Guidelines"
//    var id: String { rawValue }
//    var icon: String {
//        switch self {
//        case .angle: return "angle.turn.left.fill"
//        case .brainDump: return "briefcase.fill"
//        case .mission: return "target"
//        case .pointsResearch: return "list.bullet.clipboard"
//        case .outline: return "list.bullet.indent"
//        case .package: return "shippingbox"
//        case .finalScript: return "doc.text"
//        case .polish: return "sparkles"
//        case .guidelines: return "pencil.and.outline"
//        }
//    }
//}
//



// MARK: - Mission View
struct YTSCRIPTMissionView: View {
    @Bindable var script: YTSCRIPT
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Objective
                
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Objective")
                            .font(.headline)
                        Spacer()
                        CopyButton(
                            label: "Mission",
                            valueToCopy: generateCopyText(),
                            font: .headline
                        )
                        .buttonStyle(.bordered)
                        
                    }
                    Text("After watching, the viewer will...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $script.objective)
                        .frame(minHeight: 100)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    
                    Text("\(script.objective.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Target Emotion
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Emotion")
                        .font(.headline)
                    
                    TextField("e.g., surprise, shock, relief", text: $script.targetEmotion)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Audience Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audience Notes")
                        .font(.headline)
                    Text("Who is this for?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $script.audienceNotes)
                        .frame(minHeight: 80)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Writing Style")
                        .font(.headline)
                    
                    Picker("Style", selection: $script.writingStyle) {
                        ForEach(WritingStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text(script.writingStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("Mission")
    }
    
    private func generateCopyText() -> String {
        var output = ""
        
        output += "# \(script.title)\n\n"
        output += "**Objective:** \(script.objective)\n"
        output += "**Target Emotion:** \(script.targetEmotion)\n"
        output += "**Audience Notes:** \(script.audienceNotes)\n\n"
    
        
        return output
    }
}

// MARK: - Brain Dump View
struct YTSCRIPTBrainDumpView: View {
    @Bindable var script: YTSCRIPT
    @State private var newPointText = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                HStack {
                    Spacer()
                    CopyButton(
                        label: "Raw Brain Dump",
                        valueToCopy: generateCopyText(),
                        font: .headline
                    )
                    .buttonStyle(.bordered)
                }
                // Raw Brain Dump
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Raw Recording")
                            .font(.headline)
                        Spacer()
                        Button {
                            // TODO: Start voice recording
                        } label: {
                            Label("Record", systemImage: "mic.circle.fill")
                        }
                    }
                    
                    Text("Dump everything here - voice-to-text or type")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $script.brainDumpRaw)
                        .frame(minHeight: 200)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    
                    HStack {
                        Text("\(script.brainDumpRaw.wordCount) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("Est. \(String(format: "%.1f", Double(script.brainDumpRaw.wordCount) / script.wordsPerMinute)) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // Extracted Points
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Extracted Points")
                            .font(.headline)
                        Spacer()
                        Button {
                            // TODO: AI extract points
                        } label: {
                            Label("Extract with AI", systemImage: "sparkles")
                        }
                    }
                    
                    // Add point manually
                    HStack {
                        TextField("Add a point manually...", text: $newPointText)
                            .textFieldStyle(.roundedBorder)
                        
                        Button {
                            addPoint()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(newPointText.isEmpty)
                    }
                    
                    // Points list
                    if script.points.isEmpty {
                        Text("No points yet")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(script.points) { point in
                            PointRow(point: point, onDelete: {
                                deletePoint(point)
                            })
                        }
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("Brain Dump")
    }
    
    private func generateCopyText() -> String {
        var output = ""
        
        // Script Info
        output += "# \(script.title)\n\n"
        
        output += "---\n\n"
        
        // Raw Brain Dump
        if !script.brainDumpRaw.isEmpty {
            output += "## Raw Brain Dump\n"
            output += "**(\(script.brainDumpRaw.wordCount) words, ~\(String(format: "%.1f", Double(script.brainDumpRaw.wordCount) / script.wordsPerMinute)) min)**\n\n"
            output += script.brainDumpRaw
            output += "\n\n---\n\n"
        }
        
        // Extracted Points
        if !script.points.isEmpty {
            output += "## Extracted Research Points (\(script.points.count) total)\n\n"
            
            // Group by keeper status
            let keeperPoints = script.points.filter { $0.isKeeper }
            let otherPoints = script.points.filter { !$0.isKeeper }
            
            if !keeperPoints.isEmpty {
                output += "### ⭐ Keeper Points\n\n"
                for (index, point) in keeperPoints.enumerated() {
                    output += "\(index + 1). **[\(point.tag.uppercased())]"
                    if point.shockScore > 0 {
                        output += " 🔥\(point.shockScore)"
                    }
                    output += "** \(point.text)\n"
                }
                output += "\n"
            }
            
            if !otherPoints.isEmpty {
                output += "### Other Points\n\n"
                for (index, point) in otherPoints.enumerated() {
                    output += "\(index + 1). **[\(point.tag.uppercased())]"
                    if point.shockScore > 0 {
                        output += " 🔥\(point.shockScore)"
                    }
                    output += "** \(point.text)\n"
                }
            }
        }
        
        return output
    }
    
    private func addPoint() {
        let newPoint = YTSCRIPTPoint(text: newPointText)
        script.points.append(newPoint)
        newPointText = ""
    }
    
    private func deletePoint(_ point: YTSCRIPTPoint) {
        script.points.removeAll { $0.id == point.id }
    }
}

struct PointRow: View {
    let point: YTSCRIPTPoint
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(point.text)
                    .font(.body)
                
                HStack {
                    Text(point.tag)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                    
                    if point.shockScore > 0 {
                        Text("🔥 \(point.shockScore)")
                            .font(.caption)
                    }
                    
                    if point.isKeeper {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            
            Spacer()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
