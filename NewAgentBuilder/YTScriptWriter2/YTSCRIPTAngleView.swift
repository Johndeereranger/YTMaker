//
//  YTSCRIPTAngleView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/8/25.
//


import SwiftUI

import SwiftUI

struct YTSCRIPTAngleView: View {
    @Bindable var script: YTSCRIPT
    @State private var jsonInput: String = ""
    @State private var showingPasteSheet: Bool = false
    @State private var parseError: String? = nil
    @State private var showingCopiedAlert: Bool = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Step 4: Lock Core Angle")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Generate multiple angles and pick the strongest one")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                Divider()
                
                // ========== NEW: MANUAL ENTRY SECTION ==========
                VStack(alignment: .leading, spacing: 12) {
                    Label("Quick Entry: Final Angle", systemImage: "pencil.circle.fill")
                        .font(.headline)
                    
                    Text("Paste your synthesized angle statement here (skip JSON workflow)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $script.manualAngle)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    
                    if !script.manualAngle.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Manual angle saved")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Spacer()
                            
                            Button("Clear") {
                                script.manualAngle = ""
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                // ========== END MANUAL ENTRY ==========
                
                Text("— OR —")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                // Step 1: Copy Prompt
                VStack(alignment: .leading, spacing: 12) {
                    Label("Step 1: Copy Prompt", systemImage: "1.circle.fill")
                        .font(.headline)
                    
                    Text("Copy the prompt below and paste it into Claude, ChatGPT, or Grok to generate angle options.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button(action: copyPromptToClipboard) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Prompt")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Step 2: Paste JSON
                VStack(alignment: .leading, spacing: 12) {
                    Label("Step 2: Paste AI Response", systemImage: "2.circle.fill")
                        .font(.headline)
                    
                    Text("After AI generates the angles, copy the JSON response and paste it here. Multiple pastes will ADD angles.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Button(action: { showingPasteSheet = true }) {
                            HStack {
                                Image(systemName: "arrow.down.doc")
                                Text(script.generatedAngles.isEmpty ? "Paste JSON Response" : "Add More Angles")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        if !script.generatedAngles.isEmpty {
                            Button(action: {
                                script.generatedAngles = []
                                script.selectedAngleId = nil
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
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
                
                // Step 3: Review and Select
                if !script.generatedAngles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Step 3: Select Best Angle", systemImage: "3.circle.fill")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("\(script.generatedAngles.count) angles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        
                        ForEach(script.generatedAngles) { angle in
                            AngleCard(
                                angle: angle,
                                isSelected: script.selectedAngleId == angle.id,
                                onSelect: { selectAngle(angle) }
                            )
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Selected Angle Preview
                if let selectedAngle = script.generatedAngles.first(where: { $0.id == script.selectedAngleId }) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Selected Angle", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text(selectedAngle.angleStatement)
                                .font(.body)
                                .fontWeight(.semibold)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nuke Point")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Point \(selectedAngle.nukePoint)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hook Type")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(selectedAngle.hookType.capitalized)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Supporting Points")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(selectedAngle.supportingPoints.joined(separator: ", "))
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingPasteSheet) {
            PasteJSONSheet(
                jsonInput: $jsonInput,
                onParse: parseJSON,
                onDismiss: { showingPasteSheet = false }
            )
        }
        .alert("Prompt Copied", isPresented: $showingCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The prompt has been copied to your clipboard. Paste it into your AI assistant.")
        }
    }
    var body2: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Step 4: Lock Core Angle")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Generate multiple angles and pick the strongest one")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                Divider()
                
                // Step 1: Copy Prompt
                VStack(alignment: .leading, spacing: 12) {
                    Label("Step 1: Copy Prompt", systemImage: "1.circle.fill")
                        .font(.headline)
                    
                    Text("Copy the prompt below and paste it into Claude, ChatGPT, or Grok to generate angle options.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button(action: copyPromptToClipboard) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Prompt")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Step 2: Paste JSON
                VStack(alignment: .leading, spacing: 12) {
                    Label("Step 2: Paste AI Response", systemImage: "2.circle.fill")
                        .font(.headline)
                    
                    Text("After AI generates the angles, copy the JSON response and paste it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button(action: { showingPasteSheet = true }) {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            Text(script.generatedAngles.isEmpty ? "Paste JSON Response" : "Update Angles")
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
                
                // Step 3: Review and Select
                if !script.generatedAngles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Step 3: Select Best Angle", systemImage: "3.circle.fill")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(script.generatedAngles) { angle in
                            AngleCard(
                                angle: angle,
                                isSelected: script.selectedAngleId == angle.id,
                                onSelect: { selectAngle(angle) }
                            )
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Selected Angle Preview
                if let selectedAngle = script.generatedAngles.first(where: { $0.id == script.selectedAngleId }) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Selected Angle", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text(selectedAngle.angleStatement)
                                .font(.body)
                                .fontWeight(.semibold)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nuke Point")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Point \(selectedAngle.nukePoint)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hook Type")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(selectedAngle.hookType.capitalized)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Supporting Points")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(selectedAngle.supportingPoints.joined(separator: ", "))
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingPasteSheet) {
            PasteJSONSheet(
                jsonInput: $jsonInput,
                onParse: parseJSON,
                onDismiss: { showingPasteSheet = false }
            )
        }
        .alert("Prompt Copied", isPresented: $showingCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The prompt has been copied to your clipboard. Paste it into your AI assistant.")
        }
    }
    
    // MARK: - Actions
    
    private func copyPromptToClipboard() {
        let prompt = generatePrompt()
        
        #if os(iOS)
        UIPasteboard.general.string = prompt
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
        
        showingCopiedAlert = true
    }
    
    private func generatePrompt() -> String {
        // Format research points
        let pointsText = script.researchPoints.enumerated().map { index, point in
            """
            ### Point \(index + 1): \(point.title)
            \(point.rawNotes)
            """
        }.joined(separator: "\n\n")
        
        return """
        You are analyzing thermal drone research findings to identify potential story angles for a YouTube video script.
        
        CONTEXT:
        - Mission Objective: \(script.objective)
        - Target Emotion: \(script.targetEmotion)
        - Audience: \(script.audienceNotes)
        
        RESEARCH POINTS:
        \(pointsText)
        
        BRAIN DUMP:
        \(script.brainDumpRaw)
        
        YOUR TASK:
        Generate 5-7 potential "core angle" options. Each angle should:
        1. Be ONE sentence that captures the main contrarian truth/revelation
        2. Identify which research point(s) serve as the "nuke" (most shocking discovery)
        3. Explain why this angle matters to the target audience
        4. Be rooted in the research data provided
        
        ANGLE TYPES TO CONSIDER:
        - Contrarian (common belief vs. what you discovered)
        - Problem reveal (what's actually causing their issue)
        - Unexpected insight (data that surprises even serious land managers)
        
        OUTPUT FORMAT:
        Return ONLY valid JSON in this exact structure:
        
        {
          "angles": [
            {
              "id": 1,
              "angle_statement": "One sentence capturing the core truth",
              "nuke_point": "1",
              "hook_type": "contrarian",
              "why_it_matters": "2-3 sentences explaining why audience cares",
              "supporting_points": ["1", "3", "6"]
            }
          ]
        }
        
        Generate 5-7 angle options and return as JSON.
        """
    }
    private func parseJSON() {
        parseError = nil
        
        guard !jsonInput.isEmpty else {
            parseError = "Please paste the JSON response"
            return
        }
        
        // Clean the input (remove markdown code fences if present)
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
            let response = try JSONDecoder().decode(AngleResponse.self, from: data)
            
            // ========== CHANGED: APPEND INSTEAD OF REPLACE ==========
            script.generatedAngles.append(contentsOf: response.angles)
            // ========================================================
            
            showingPasteSheet = false
            jsonInput = ""
            
            print("✅ Added \(response.angles.count) angles (total: \(script.generatedAngles.count))")
        } catch {
            parseError = "JSON parsing failed: \(error.localizedDescription)"
            print("❌ Parse error: \(error)")
        }
    }
    private func parseJSONold() {
        parseError = nil
        
        guard !jsonInput.isEmpty else {
            parseError = "Please paste the JSON response"
            return
        }
        
        // Clean the input (remove markdown code fences if present)
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
            let response = try JSONDecoder().decode(AngleResponse.self, from: data)
            script.generatedAngles = response.angles
            showingPasteSheet = false
            jsonInput = ""
            
            print("✅ Parsed \(response.angles.count) angles")
        } catch {
            parseError = "JSON parsing failed: \(error.localizedDescription)"
            print("❌ Parse error: \(error)")
        }
    }
    
    private func selectAngle(_ angle: YTSCRIPTAngleOption) {  // ← CHANGED
        script.selectedAngleId = angle.id
        
        // Trigger auto-save
        Task {
            do {
                try await YTSCRIPTManager.shared.updateScript(script)
                print("💾 Auto-saved angle selection")
            } catch {
                print("❌ Auto-save failed: \(error)")
            }
        }
    }
}

// MARK: - Supporting Views

struct AngleCard: View {
    let angle: YTSCRIPTAngleOption  // ← CHANGED
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with checkbox
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
                    .font(.title3)
                
                Text("Angle #\(angle.id)")
                    .font(.headline)
                
                Spacer()
                
                Text(angle.hookType.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }
            
            // Angle statement
            Text(angle.angleStatement)
                .font(.body)
                .fontWeight(.semibold)
            
            // Nuke point
            HStack {
                Text("Nuke Point:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Point \(angle.nukePoint)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            // Why it matters
            Text(angle.whyItMatters)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Supporting points
            HStack {
                Text("Supporting Points:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(angle.supportingPoints.joined(separator: ", "))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            // Select button
            if !isSelected {
                Button(action: onSelect) {
                    Text("Select This Angle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(isSelected ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
        )
        .cornerRadius(12)
    }
}

struct PasteJSONSheet: View {
    @Binding var jsonInput: String
    let onParse: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Paste the JSON response from your AI assistant")
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
            .navigationTitle("Paste JSON")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - JSON Decoding

struct AngleResponse: Codable {
    let angles: [YTSCRIPTAngleOption]  // ← CHANGED
}
