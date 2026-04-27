//
//  AddYouTubeInsightView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/10/26.
//


import SwiftUI
import Vision

struct AddYouTubeInsightView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var insightManager = YouTubeInsightManager()
    
    @State private var pastedImage: UIImage? = nil
    @State private var extractedText: String = ""
    @State private var channelName: String = ""
    @State private var videoTitle: String = ""
    @State private var timestamp: String = ""
    @State private var insightType: YouTubeInsight.InsightType = .visualCue
    @State private var notes: String = ""
    @State private var errorMessage: String?
    @State private var isProcessing = false
    
    var body: some View {
    
            ScrollView {
                VStack(spacing: 20) {
                    // Paste Image Section
                    pasteImageSection
                    
                    // Extracted Fields
                    if !extractedText.isEmpty {
                        extractedFieldsSection
                    }
                    
                    // Manual Entry Fallback
                    manualEntrySection
                    
                    // Insight Type Picker
                    insightTypeSection
                    
                    // Notes
                    notesSection
                    
                    // Action Buttons
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("New YouTube Insight")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        
    }
    
    // MARK: - View Components
    
    private var pasteImageSectionOld: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 1: Paste Screenshot")
                .font(.headline)
            
            PasteableTextView(
                text: $extractedText,
                placeholder: "Paste YouTube screenshot here...",
                onImagePasted: { image in
                    pastedImage = image
                    recognizeText(from: image)
                }
            )
            .frame(height: 120)
            
            if let image = pastedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 2)
                    )
            }
            
            if isProcessing {
                HStack {
                    ProgressView()
                    Text("Extracting text...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var extractedFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 2: Verify Extracted Data")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Raw Extracted Text", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(extractedText)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
            
            Button {
                parseExtractedData()
            } label: {
                Label("Auto-Parse Fields", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extracted Fields")
                .font(.headline)
            
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channel Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Channel Name", text: $channelName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Video Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Video Title", text: $videoTitle)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Timestamp")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("00:00 / 00:00", text: $timestamp)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
    
    private var insightTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 3: Select Insight Type")
                .font(.headline)
            
            Picker("Insight Type", selection: $insightType) {
                ForEach(YouTubeInsight.InsightType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.icon)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 4: Add Notes")
                .font(.headline)
            
            TextEditor(text: $notes)
                .frame(height: 120)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            
            Text("Describe what you want to copy/learn from this moment")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Button {
                Task { await saveInsight() }
            } label: {
                Text("Save Insight")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValidInsight)
        }
    }
    
    // MARK: - Validation
    
    private var isValidInsight: Bool {
        !channelName.isEmpty && !videoTitle.isEmpty && !timestamp.isEmpty
    }
    
    // MARK: - Actions
    
    private func recognizeText(from image: UIImage) {
        isProcessing = true
        guard let cgImage = image.cgImage else {
            isProcessing = false
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    isProcessing = false
                }
                return
            }
            
            let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
            
            DispatchQueue.main.async {
                extractedText = recognizedStrings.joined(separator: "\n")
                parseExtractedData()
                isProcessing = false
            }
        }
        
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    
    private var pasteImageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Step 1: Paste Screenshot")
                    .font(.headline)
                
                Spacer()
                
                // ⭐ NEW: Direct paste button
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            PasteableTextView(
                text: $extractedText,
                placeholder: "Or tap here and paste manually...",
                onImagePasted: { image in
                    pastedImage = image
                    recognizeText(from: image)
                }
            )
            .frame(height: 120)
            
            if let image = pastedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 2)
                    )
            }
            
            if isProcessing {
                HStack {
                    ProgressView()
                    Text("Extracting text...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func pasteFromClipboard() {
        #if os(iOS)
        if UIPasteboard.general.hasImages, let image = UIPasteboard.general.image {
            pastedImage = image
            recognizeText(from: image)
        } else {
            errorMessage = "No image found in clipboard"
        }
        #else
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            // Convert NSImage to UIImage for macOS
            // (you'll need platform-specific handling here)
            errorMessage = "macOS clipboard handling not implemented yet"
        } else {
            errorMessage = "No image found in clipboard"
        }
        #endif
    }
    
    private func parseExtractedData() {
        let lines = extractedText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        print("📝 Extracted lines:")
        for (index, line) in lines.enumerated() {
            print("  Line \(index): \(line)")
        }
        
        // 1️⃣ Find timestamp (pattern: XX:XX / XX:XX or XX:XX:XX / XX:XX:XX)
        let timestampPattern = #"\d{1,2}:\d{2}(?::\d{2})?\s*/\s*\d{1,2}:\d{2}(?::\d{2})?"#
        for line in lines {
            if let range = line.range(of: timestampPattern, options: .regularExpression) {
                timestamp = String(line[range])
                print("✅ Found timestamp: \(timestamp)")
                break
            }
        }
        
        // 2️⃣ Find channel name (line starting with @)
        var channelLineIndex: Int?
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("@") {
                let components = line.components(separatedBy: " ")
                if let handle = components.first {
                    channelName = String(handle.dropFirst())
                    channelLineIndex = index
                    print("✅ Found channel: \(channelName) at line \(index)")
                    break
                }
            }
        }
        
        // 3️⃣ Find video title - STRATEGY: Line immediately before @channel line
        if let channelIndex = channelLineIndex, channelIndex > 0 {
            // Look backwards from @channel line for the longest substantial line
            for index in stride(from: channelIndex - 1, through: 0, by: -1) {
                let line = lines[index]
                
                // Skip timestamp lines
                if line.range(of: timestampPattern, options: .regularExpression) != nil {
                    continue
                }
                
                // Skip very short lines
                if line.count < 15 {
                    continue
                }
                
                // This should be the title
                videoTitle = line
                print("✅ Found title at line \(index): \(videoTitle)")
                break
            }
        }
        
        // 4️⃣ Fallback: Find the longest line that looks like a title
        if videoTitle.isEmpty {
            var longestTitleLine = ""
            
            for line in lines {
                // Skip timestamp
                if line.range(of: timestampPattern, options: .regularExpression) != nil {
                    continue
                }
                
                // Skip @channel
                if line.hasPrefix("@") {
                    continue
                }
                
                // Skip metadata (views, subscribers, etc)
                if line.contains("views") || line.contains("subscribers") ||
                   line.contains("Subscribe") || line.contains("ago") {
                    continue
                }
                
                // Check if it's longer than current longest
                if line.count > longestTitleLine.count && line.count > 20 {
                    longestTitleLine = line
                }
            }
            
            if !longestTitleLine.isEmpty {
                videoTitle = longestTitleLine
                print("✅ Found title (fallback - longest): \(videoTitle)")
            }
        }
        
        print("\n📊 Final Results:")
        print("  Channel: \(channelName)")
        print("  Title: \(videoTitle)")
        print("  Timestamp: \(timestamp)")
    }
    private func saveInsight() async {
        guard isValidInsight else {
            errorMessage = "Please fill in all required fields"
            return
        }
        
        do {
            let insight = YouTubeInsight(
                channelName: channelName,
                videoTitle: videoTitle,
                timestamp: timestamp,
                insightType: insightType,
                notes: notes,
                extractedText: extractedText
            )
            
            try await insightManager.createInsight(insight)
            print("✅ Insight saved successfully")
            dismiss()
            
        } catch {
            errorMessage = "Failed to save insight: \(error.localizedDescription)"
            print("❌ Save error: \(error)")
        }
    }
}
