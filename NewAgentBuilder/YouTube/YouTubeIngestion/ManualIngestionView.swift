//
//  ManualIngestionView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/16/26.
//

//
//import SwiftUI
//
//// MARK: - Manual Ingestion View
//struct ManualIngestionView: View {
//    let video: YouTubeVideo
//    @Environment(\.dismiss) private var dismiss
//    
//    @State private var currentStep: IngestionStep = .showPrompt
//    @State private var generatedPrompt: String = ""
//    @State private var jsonResponse: String = ""
//    @State private var processedAlignment: AlignmentData?
//    @State private var isSaving = false
//    @State private var saveError: String?
//    @State private var savedAlignment: AlignmentData?
//    
//    enum IngestionStep {
//        case showPrompt
//        case pasteResponse
//        case processing
//        case reviewCalculated
//        case saving
//        case complete
//    }
//    
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 20) {
//                
//                // Video Info
//                VStack(alignment: .leading, spacing: 8) {
//                    Text(video.title)
//                        .font(.headline)
//                    
//                    HStack {
//                        Label(video.duration, systemImage: "clock")
//                        Spacer()
//                        if let transcript = video.transcript {
//                            Label("\(transcript.split(separator: " ").count) words", systemImage: "text.alignleft")
//                        }
//                    }
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                }
//                .padding()
//                .background(Color(.secondarySystemBackground))
//                .cornerRadius(8)
//                
//                Divider()
//                
//                // Step Views
//                switch currentStep {
//                case .showPrompt:
//                    promptStepView
//                case .pasteResponse:
//                    responseStepView
//                case .processing:
//                    processingStepView
//                case .reviewCalculated:
//                    reviewStepView
//                case .saving:
//                    savingStepView
//                case .complete:
//                    completeStepView
//                }
//            }
//            .padding()
//        }
//        .navigationTitle("Analyze Structure (A1a)")
//        .navigationBarTitleDisplayMode(.inline)
//        .toolbar {
//            ToolbarItem(placement: .cancellationAction) {
//                Button("Cancel") {
//                    dismiss()
//                }
//            }
//        }
//        .onAppear {
//            generatePrompt()
//        }
//    }
//    
//    // MARK: - Step 1: Show Prompt
//    private var promptStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "1.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.blue)
//                Text("Copy Prompt")
//                    .font(.headline)
//            }
//            
//            Text("Copy this prompt and paste it into Claude.ai (or any AI)")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//            
//            ScrollView {
//                Text(generatedPrompt)
//                    .font(.system(.body, design: .monospaced))
//                    .textSelection(.enabled)
//                    .padding()
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                    .background(Color(.tertiarySystemBackground))
//                    .cornerRadius(8)
//            }
//            .frame(height: 300)
//            
//            HStack {
//                Button(action: {
//                    UIPasteboard.general.string = generatedPrompt
//                }) {
//                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    currentStep = .pasteResponse
//                }) {
//                    Label("Next: Paste Response", systemImage: "arrow.right")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//    
//    // MARK: - Step 2: Paste Response
//    private var responseStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "2.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.green)
//                Text("Paste JSON Response")
//                    .font(.headline)
//            }
//            
//            Text("Paste Claude's JSON response below (without timestamps)")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//            
//            TextEditor(text: $jsonResponse)
//                .font(.system(.body, design: .monospaced))
//                .frame(height: 300)
//                .padding(4)
//                .background(Color(.tertiarySystemBackground))
//                .cornerRadius(8)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 8)
//                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
//                )
//            
//            if let error = saveError {
//                HStack {
//                    Image(systemName: "exclamationmark.triangle.fill")
//                        .foregroundColor(.red)
//                    Text(error)
//                        .font(.caption)
//                        .foregroundColor(.red)
//                }
//                .padding(8)
//                .background(Color.red.opacity(0.1))
//                .cornerRadius(8)
//            }
//            
//            HStack {
//                Button(action: {
//                    currentStep = .showPrompt
//                    saveError = nil
//                }) {
//                    Label("Back", systemImage: "arrow.left")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    Task {
//                        await processResponse()
//                    }
//                }) {
//                    Label("Process & Calculate", systemImage: "gearshape.2")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//                .disabled(jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
//            }
//        }
//    }
//    
//    // MARK: - Step 3: Processing
//    private var processingStepView: some View {
//        VStack(spacing: 20) {
//            ProgressView()
//                .scaleEffect(1.5)
//            Text("Calculating timestamps...")
//                .font(.headline)
//            Text("Using word-count-based positioning")
//                .font(.caption)
//                .foregroundColor(.secondary)
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//    }
//    
//    // MARK: - Step 4: Review Calculated
//    private var reviewStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "3.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.orange)
//                Text("Review Calculated Timestamps")
//                    .font(.headline)
//            }
//            
//            if let alignment = processedAlignment {
//                ScrollView {
//                    VStack(alignment: .leading, spacing: 12) {
//                        ForEach(Array(alignment.sections.enumerated()), id: \.element.id) { index, section in
//                            VStack(alignment: .leading, spacing: 4) {
//                                HStack {
//                                    Text(section.role)
//                                        .font(.caption)
//                                        .padding(.horizontal, 8)
//                                        .padding(.vertical, 4)
//                                        .background(roleColor(section.role).opacity(0.2))
//                                        .foregroundColor(roleColor(section.role))
//                                        .cornerRadius(4)
//                                    
//                                    Text("\(formatSeconds(section.timeRange.start)) - \(formatSeconds(section.timeRange.end))")
//                                        .font(.caption)
//                                        .foregroundColor(.secondary)
//                                    
//                                    Spacer()
//                                }
//                                
//                                Text(section.goal)
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                            .padding(8)
//                            .background(Color(.secondarySystemBackground))
//                            .cornerRadius(6)
//                        }
//                        
//                        Divider()
//                        
//                        Text("Bridge Points: \(alignment.bridgePoints.count)")
//                            .font(.subheadline)
//                            .fontWeight(.medium)
//                        
//                        Text("Logic Spine: \(alignment.logicSpine.chain.count) steps")
//                            .font(.subheadline)
//                            .fontWeight(.medium)
//                        
//                        if let issues = alignment.validationIssues, !issues.isEmpty {
//                            VStack(alignment: .leading, spacing: 8) {
//                                Text("Validation Issues:")
//                                    .font(.subheadline)
//                                    .fontWeight(.medium)
//                                
//                                ForEach(issues, id: \.message) { issue in
//                                    HStack(alignment: .top, spacing: 8) {
//                                        Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
//                                            .foregroundColor(issue.severity == .error ? .red : .orange)
//                                        Text(issue.message)
//                                            .font(.caption)
//                                    }
//                                }
//                            }
//                            .padding()
//                            .background(Color.orange.opacity(0.1))
//                            .cornerRadius(8)
//                        }
//                    }
//                }
//                .frame(maxHeight: 400)
//            }
//            
//            HStack {
//                Button(action: {
//                    currentStep = .pasteResponse
//                    saveError = nil
//                }) {
//                    Label("Back", systemImage: "arrow.left")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    Task {
//                        await saveToFirebase()
//                    }
//                }) {
//                    Label("Save to Firebase", systemImage: "square.and.arrow.down")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//    
//    // MARK: - Step 5: Saving
//    private var savingStepView: some View {
//        VStack(spacing: 20) {
//            ProgressView()
//                .scaleEffect(1.5)
//            Text("Saving to Firebase...")
//                .font(.headline)
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//    }
//    
//    // MARK: - Step 6: Complete
//    private var completeStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "checkmark.circle.fill")
//                    .font(.title)
//                    .foregroundColor(.green)
//                Text("Analysis Complete!")
//                    .font(.headline)
//            }
//            
//            if let alignment = savedAlignment {
//                VStack(alignment: .leading, spacing: 12) {
//                    Text("✅ Extracted \(alignment.sections.count) sections")
//                    Text("✅ Logic spine: \(alignment.logicSpine.chain.count) steps")
//                    Text("✅ Bridge points: \(alignment.bridgePoints.count)")
//                    Text("✅ Timestamps calculated with ~5% accuracy")
//                    
//                    if let issues = alignment.validationIssues, !issues.isEmpty {
//                        Text("⚠️ \(issues.filter { $0.severity == .warning }.count) warnings")
//                            .foregroundColor(.orange)
//                    }
//                }
//                .font(.subheadline)
//                .padding()
//                .background(Color(.secondarySystemBackground))
//                .cornerRadius(8)
//            }
//            
//            Button(action: {
//                dismiss()
//            }) {
//                Text("Done")
//                    .frame(maxWidth: .infinity)
//            }
//            .buttonStyle(.borderedProminent)
//        }
//    }
//    
//    // MARK: - Helper Methods
//    
////    private func generatePrompt() {
////        guard let transcript = video.transcript else {
////            generatedPrompt = "⚠️ No transcript available for this video"
////            return
////        }
////        
////        generatedPrompt = PromptDatabase.get(.a1a_structuralSpine, variables: [
////            "transcript": transcript,
////            "title": video.title,
////            "duration": video.duration
////        ])
////    }
//    
////    private func processResponse() async {
////        currentStep = .processing
////        saveError = nil
////        
////        // Small delay for UI feedback
////        try? await Task.sleep(nanoseconds: 500_000_000)
////        
////        do {
////            // Clean JSON
////            var cleanJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
////            if cleanJSON.hasPrefix("```json") {
////                cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
////                cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
////                cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
////            }
////            
////            guard let jsonData = cleanJSON.data(using: .utf8) else {
////                throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON string"])
////            }
////            
////            // Parse response (without timestamps)
////            struct AlignmentResponse: Codable {
////                struct SectionResponse: Codable {
////                    let id: String
////                    let startText: String
////                    let endText: String
////                    let role: String
////                    let goal: String
////                    let logicSpineStep: String
////                }
////                
////                let sections: [SectionResponse]
////                let logicSpine: LogicSpineData
////                let bridgePoints: [BridgePoint]
////            }
////            
////            let decoder = JSONDecoder()
////            let response = try decoder.decode(AlignmentResponse.self, from: jsonData)
////            
////            // Calculate timestamps
////            guard let transcript = video.transcript else {
////                throw NSError(domain: "Process", code: -1, userInfo: [NSLocalizedDescriptionKey: "No transcript available"])
////            }
////            
////            let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
////            
////            var sectionsWithTimestamps: [SectionData] = []
////            
////            for section in response.sections {
////                let startTime = calculator.calculateTimestamp(for: section.startText)
////                let endTime = calculator.calculateTimestamp(for: section.endText)
////                
////                let sectionData = SectionData(
////                    id: section.id,
////                    timeRange: TimeRange(start: startTime, end: endTime),
////                    role: section.role,
////                    goal: section.goal,
////                    logicSpineStep: section.logicSpineStep
////                )
////                
////                sectionsWithTimestamps.append(sectionData)
////            }
////            
////            // Calculate bridge point timestamps
////            var bridgePointsWithTimestamps: [BridgePoint] = []
////            
////            for bridge in response.bridgePoints {
////                let timestamp = calculator.calculateTimestamp(for: bridge.text)
////                
////                let bridgeData = BridgePoint(
////                    text: bridge.text,
////                    belongsTo: bridge.belongsTo,
////                    timestamp: timestamp
////                )
////                
////                bridgePointsWithTimestamps.append(bridgeData)
////            }
////            
////            // Create alignment data
////            let alignmentData = AlignmentData(
////                videoId: video.videoId,
////                channelId: video.channelId,
////                sections: sectionsWithTimestamps,
////                logicSpine: response.logicSpine,
////                bridgePoints: bridgePointsWithTimestamps
////            )
////            
////            // Validate
////            let validator = AlignmentValidator()
////            let validation = validator.validate(alignmentData)
////            
////            var finalData = alignmentData
////            finalData.validationStatus = validation.status
////            finalData.validationIssues = validation.issues.isEmpty ? nil : validation.issues
////            
////            processedAlignment = finalData
////            currentStep = .reviewCalculated
////            
////        } catch {
////            saveError = "Failed to process: \(error.localizedDescription)"
////            currentStep = .pasteResponse
////        }
////    }
//    private func processResponse() async {
//        currentStep = .processing
//        saveError = nil
//        
//        print("\n")
//        print("========================================")
//        print("🔍 STARTING RESPONSE PROCESSING")
//        print("========================================")
//        
//        // Small delay for UI feedback
//        try? await Task.sleep(nanoseconds: 500_000_000)
//        
//        print("\n📥 RAW JSON RESPONSE:")
//        print("Length: \(jsonResponse.count) characters")
//        print("First 200 chars: \(String(jsonResponse.prefix(200)))")
//        print("Last 200 chars: \(String(jsonResponse.suffix(200)))")
//        print("\nFULL RAW JSON:")
//        print(jsonResponse)
//        print("\n")
//        
//        // Clean JSON
//        var cleanJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        print("🧹 CLEANING JSON...")
//        print("Has markdown fence: \(cleanJSON.hasPrefix("```json"))")
//        
//        if cleanJSON.hasPrefix("```json") {
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
//            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
//            print("✅ Removed markdown fences")
//        }
//        
//        print("\n📋 CLEANED JSON:")
//        print("Length: \(cleanJSON.count) characters")
//        print("First 200 chars: \(String(cleanJSON.prefix(200)))")
//        print("Last 200 chars: \(String(cleanJSON.suffix(200)))")
//        print("\nFULL CLEANED JSON:")
//        print(cleanJSON)
//        print("\n")
//        
//        guard let jsonData = cleanJSON.data(using: .utf8) else {
//            print("❌ FATAL: Could not convert string to UTF-8 data")
//            saveError = "Could not convert string to UTF-8 data"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        print("✅ Successfully converted to Data object")
//        print("Data size: \(jsonData.count) bytes")
//        
//        // Temporary decode structures (no UUIDs)
//        struct AlignmentResponse: Codable {
//            struct SectionResponse: Codable {
//                let id: String
//                let startText: String
//                let endText: String
//                let role: String
//                let goal: String
//                let logicSpineStep: String
//            }
//            
//            struct CausalLinkResponse: Codable {
//                let from: String
//                let to: String
//                let connection: String
//            }
//            
//            struct LogicSpineResponse: Codable {
//                let chain: [String]
//                let causalLinks: [CausalLinkResponse]
//            }
//            
//            struct BridgePointResponse: Codable {
//                let text: String
//                let belongsTo: [String]
//            }
//            
//            let sections: [SectionResponse]
//            let logicSpine: LogicSpineResponse
//            let bridgePoints: [BridgePointResponse]
//        }
//        
//        print("\n🔬 ATTEMPTING TO DECODE JSON...")
//        
//        let decoder = JSONDecoder()
//        let response: AlignmentResponse
//        
//        do {
//            response = try decoder.decode(AlignmentResponse.self, from: jsonData)
//            print("✅ JSON DECODED SUCCESSFULLY!")
//            print("Sections found: \(response.sections.count)")
//            print("Logic spine steps: \(response.logicSpine.chain.count)")
//            print("Causal links: \(response.logicSpine.causalLinks.count)")
//            print("Bridge points: \(response.bridgePoints.count)")
//            
//            print("\n📊 DECODED SECTIONS:")
//            for (index, section) in response.sections.enumerated() {
//                print("  Section \(index + 1):")
//                print("    id: \(section.id)")
//                print("    role: \(section.role)")
//                print("    startText: \(section.startText.prefix(50))...")
//                print("    endText: \(section.endText.prefix(50))...")
//            }
//            
//        } catch let DecodingError.dataCorrupted(context) {
//            print("❌ DECODING ERROR: Data Corrupted")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Data Corrupted: \(context.debugDescription)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.keyNotFound(key, context) {
//            print("❌ DECODING ERROR: Key Not Found")
//            print("Missing key: \(key)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Missing key: \(key.stringValue)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.valueNotFound(value, context) {
//            print("❌ DECODING ERROR: Value Not Found")
//            print("Missing value type: \(value)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Value not found: \(value)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.typeMismatch(type, context) {
//            print("❌ DECODING ERROR: Type Mismatch")
//            print("Expected type: \(type)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Type mismatch: expected \(type)"
//            currentStep = .pasteResponse
//            return
//        } catch {
//            print("❌ UNKNOWN DECODING ERROR")
//            print("Error: \(error)")
//            print("Error type: \(type(of: error))")
//            print("Localized description: \(error.localizedDescription)")
//            saveError = "Decoding failed: \(error.localizedDescription)"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        // Calculate timestamps
//        print("\n⏱️ CALCULATING TIMESTAMPS...")
//        
//        guard let transcript = video.transcript else {
//            print("❌ FATAL: No transcript available")
//            saveError = "No transcript available"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        print("Transcript length: \(transcript.count) characters")
//        print("Transcript word count: \(transcript.split(separator: " ").count) words")
//        print("Video duration: \(video.duration)")
//        
//        let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
//        
//        print("Words per second: \(calculator.wordsPerSecond)")
//        
//        var sectionsWithTimestamps: [SectionData] = []
//        
//        print("\n🔢 PROCESSING SECTIONS...")
//        for (index, section) in response.sections.enumerated() {
//            print("\nSection \(index + 1) (\(section.id)):")
//            print("  Start text search: '\(section.startText.prefix(40))...'")
//            
//            let startTime = calculator.calculateTimestamp(for: section.startText)
//            print("  ✅ Start time: \(startTime)s (\(formatSeconds(startTime)))")
//            
//            print("  End text search: '\(section.endText.prefix(40))...'")
//            let endTime = calculator.calculateTimestamp(for: section.endText)
//            print("  ✅ End time: \(endTime)s (\(formatSeconds(endTime)))")
//            
//            let sectionData = SectionData(
//                id: section.id,
//                timeRange: TimeRange(start: startTime, end: endTime),
//                role: section.role,
//                goal: section.goal,
//                logicSpineStep: section.logicSpineStep
//            )
//            
//            sectionsWithTimestamps.append(sectionData)
//        }
//        
//        print("\n✅ All sections processed")
//        
//        // Convert causal links
//        print("\n🔗 PROCESSING CAUSAL LINKS...")
//        let causalLinks = response.logicSpine.causalLinks.map { link in
//            CausalLink(from: link.from, to: link.to, connection: link.connection)
//        }
//        print("✅ Converted \(causalLinks.count) causal links")
//        
//        // Calculate bridge point timestamps
//        print("\n🌉 PROCESSING BRIDGE POINTS...")
//        var bridgePointsWithTimestamps: [BridgePoint] = []
//        
//        for (index, bridge) in response.bridgePoints.enumerated() {
//            print("\nBridge \(index + 1):")
//            print("  Text: '\(bridge.text.prefix(60))...'")
//            
//            let timestamp = calculator.calculateTimestamp(for: bridge.text)
//            print("  ✅ Timestamp: \(timestamp)s (\(formatSeconds(timestamp)))")
//            
//            let bridgeData = BridgePoint(
//                text: bridge.text,
//                belongsTo: bridge.belongsTo,
//                timestamp: timestamp
//            )
//            
//            bridgePointsWithTimestamps.append(bridgeData)
//        }
//        
//        print("\n✅ All bridge points processed")
//        
//        // Create alignment data
//        print("\n📦 CREATING ALIGNMENT DATA...")
//        let alignmentData = AlignmentData(
//            videoId: video.videoId,
//            channelId: video.channelId,
//            sections: sectionsWithTimestamps,
//            logicSpine: LogicSpineData(
//                chain: response.logicSpine.chain,
//                causalLinks: causalLinks
//            ),
//            bridgePoints: bridgePointsWithTimestamps
//        )
//        
//        print("✅ AlignmentData created")
//        
//        // Validate
//        print("\n========================================")
//        print("✔️ VALIDATION ANALYSIS")
//        print("========================================")
//        let validator = AlignmentValidator()
//        let validation = validator.validate(alignmentData)
//        
//        print("\n📊 VALIDATION SUMMARY:")
//        print("Status: \(validation.status)")
//        print("Total issues: \(validation.issues.count)")
//        print("  Errors: \(validation.issues.filter { $0.severity == .error }.count)")
//        print("  Warnings: \(validation.issues.filter { $0.severity == .warning }.count)")
//        
//        if validation.issues.isEmpty {
//            print("\n✅ NO ISSUES FOUND - Data is clean!")
//        } else {
//            print("\n📋 DETAILED ISSUE BREAKDOWN:")
//            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
//            
//            for (index, issue) in validation.issues.enumerated() {
//                print("\n\(index + 1). [\(issue.severity.rawValue.uppercased())] \(issue.type.rawValue)")
//                print("   Message: \(issue.message)")
//                
//                // Provide detailed context based on issue type
//                switch issue.type {
//                case .sectionCount:
//                    print("   Context:")
//                    print("     - Found: \(alignmentData.sections.count) sections")
//                    print("     - Expected: 3-8 sections")
//                    print("     - All sections:")
//                    for (idx, section) in alignmentData.sections.enumerated() {
//                        print("       \(idx + 1). \(section.id) [\(section.role)] - \(formatSeconds(section.timeRange.start)) to \(formatSeconds(section.timeRange.end))")
//                    }
//                    
//                case .timeOverlap:
//                    // Parse which sections overlap from message
//                    if let match = issue.message.range(of: "Section (\\d+) overlaps with (\\d+)", options: .regularExpression) {
//                        let nums = issue.message[match].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
//                        if nums.count >= 2, nums[0] < alignmentData.sections.count, nums[1] < alignmentData.sections.count {
//                            let sect1 = alignmentData.sections[nums[0]]
//                            let sect2 = alignmentData.sections[nums[1]]
//                            print("   Context:")
//                            print("     Section \(nums[0]) (\(sect1.id)):")
//                            print("       Role: \(sect1.role)")
//                            print("       Time: \(formatSeconds(sect1.timeRange.start)) - \(formatSeconds(sect1.timeRange.end)) (\(sect1.timeRange.end)s)")
//                            print("       Goal: \(sect1.goal)")
//                            print("     Section \(nums[1]) (\(sect2.id)):")
//                            print("       Role: \(sect2.role)")
//                            print("       Time: \(formatSeconds(sect2.timeRange.start)) - \(formatSeconds(sect2.timeRange.end)) (\(sect2.timeRange.start)s)")
//                            print("       Goal: \(sect2.goal)")
//                            print("     ⚠️ OVERLAP: Section \(nums[0]) ends at \(sect1.timeRange.end)s but Section \(nums[1]) starts at \(sect2.timeRange.start)s")
//                            print("     Overlap duration: \(sect1.timeRange.end - sect2.timeRange.start) seconds")
//                        }
//                    }
//                    
//                case .timeGap:
//                    // Parse which sections have gap from message
//                    if let match = issue.message.range(of: "Gap between sections (\\d+) and (\\d+)", options: .regularExpression) {
//                        let nums = issue.message[match].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
//                        if nums.count >= 2, nums[0] < alignmentData.sections.count, nums[1] < alignmentData.sections.count {
//                            let sect1 = alignmentData.sections[nums[0]]
//                            let sect2 = alignmentData.sections[nums[1]]
//                            let gap = sect2.timeRange.start - sect1.timeRange.end
//                            print("   Context:")
//                            print("     Section \(nums[0]) (\(sect1.id)):")
//                            print("       Role: \(sect1.role)")
//                            print("       Ends at: \(formatSeconds(sect1.timeRange.end)) (\(sect1.timeRange.end)s)")
//                            print("       End text: '\(sect1.goal.prefix(60))...'")
//                            print("     Section \(nums[1]) (\(sect2.id)):")
//                            print("       Role: \(sect2.role)")
//                            print("       Starts at: \(formatSeconds(sect2.timeRange.start)) (\(sect2.timeRange.start)s)")
//                            print("       Start text: '\(sect2.goal.prefix(60))...'")
//                            print("     ⚠️ GAP: \(gap) seconds of content unaccounted for")
//                            print("     Gap location: \(formatSeconds(sect1.timeRange.end)) to \(formatSeconds(sect2.timeRange.start))")
//                            print("     Analysis: Check if there's missing content between these sections")
//                        }
//                    }
//                    
//                case .incompleteSpine:
//                    print("   Context:")
//                    print("     - Sections: \(alignmentData.sections.count)")
//                    print("     - Logic spine steps: \(alignmentData.logicSpine.chain.count)")
//                    print("     - These should match!")
//                    print("     Section IDs:")
//                    for (idx, section) in alignmentData.sections.enumerated() {
//                        print("       \(idx + 1). \(section.id) [\(section.role)]")
//                    }
//                    print("     Logic spine chain:")
//                    for (idx, step) in alignmentData.logicSpine.chain.enumerated() {
//                        print("       \(idx + 1). \(step.prefix(80))...")
//                    }
//                    
//                case .illogicalFlow:
//                    print("   Context:")
//                    print("     Role sequence: \(alignmentData.sections.map { $0.role }.joined(separator: " → "))")
//                    print("     Issue: \(issue.message)")
//                    print("     Expected patterns:")
//                    print("       - HOOK should establish question/curiosity")
//                    print("       - PAYOFF should deliver on HOOK's promise")
//                    print("       - SETUP typically follows HOOK")
//                    
//                default:
//                    print("   Context: Additional details not available for this issue type")
//                }
//                
//                print("   ─────────────────────────────────────────")
//            }
//            
//            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
//            print("END VALIDATION REPORT")
//            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
//        }
//        
//        var finalData = alignmentData
//        finalData.validationStatus = validation.status
//        finalData.validationIssues = validation.issues.isEmpty ? nil : validation.issues
//        
//        print("✅ Validation complete")
//        
//        processedAlignment = finalData
//        currentStep = .reviewCalculated
//        
//        print("\n========================================")
//        print("✅ PROCESSING COMPLETE")
//        print("========================================")
//        print("\n")
//    }
//    private func processResponseBadValidation() async {
//        currentStep = .processing
//        saveError = nil
//        
//        print("\n")
//        print("========================================")
//        print("🔍 STARTING RESPONSE PROCESSING")
//        print("========================================")
//        
//        // Small delay for UI feedback
//        try? await Task.sleep(nanoseconds: 500_000_000)
//        
//        print("\n📥 RAW JSON RESPONSE:")
//        print("Length: \(jsonResponse.count) characters")
//        print("First 200 chars: \(String(jsonResponse.prefix(200)))")
//        print("Last 200 chars: \(String(jsonResponse.suffix(200)))")
//        print("\nFULL RAW JSON:")
//        print(jsonResponse)
//        print("\n")
//        
//        // Clean JSON
//        var cleanJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        print("🧹 CLEANING JSON...")
//        print("Has markdown fence: \(cleanJSON.hasPrefix("```json"))")
//        
//        if cleanJSON.hasPrefix("```json") {
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
//            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
//            print("✅ Removed markdown fences")
//        }
//        
//        print("\n📋 CLEANED JSON:")
//        print("Length: \(cleanJSON.count) characters")
//        print("First 200 chars: \(String(cleanJSON.prefix(200)))")
//        print("Last 200 chars: \(String(cleanJSON.suffix(200)))")
//        print("\nFULL CLEANED JSON:")
//        print(cleanJSON)
//        print("\n")
//        
//        guard let jsonData = cleanJSON.data(using: .utf8) else {
//            print("❌ FATAL: Could not convert string to UTF-8 data")
//            saveError = "Could not convert string to UTF-8 data"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        print("✅ Successfully converted to Data object")
//        print("Data size: \(jsonData.count) bytes")
//        
//        // Temporary decode structures (no UUIDs)
//        struct AlignmentResponse: Codable {
//            struct SectionResponse: Codable {
//                let id: String
//                let startText: String
//                let endText: String
//                let role: String
//                let goal: String
//                let logicSpineStep: String
//            }
//            
//            struct CausalLinkResponse: Codable {
//                let from: String
//                let to: String
//                let connection: String
//            }
//            
//            struct LogicSpineResponse: Codable {
//                let chain: [String]
//                let causalLinks: [CausalLinkResponse]
//            }
//            
//            struct BridgePointResponse: Codable {
//                let text: String
//                let belongsTo: [String]
//            }
//            
//            let sections: [SectionResponse]
//            let logicSpine: LogicSpineResponse
//            let bridgePoints: [BridgePointResponse]
//        }
//        
//        print("\n🔬 ATTEMPTING TO DECODE JSON...")
//        
//        let decoder = JSONDecoder()
//        let response: AlignmentResponse
//        
//        do {
//            response = try decoder.decode(AlignmentResponse.self, from: jsonData)
//            print("✅ JSON DECODED SUCCESSFULLY!")
//            print("Sections found: \(response.sections.count)")
//            print("Logic spine steps: \(response.logicSpine.chain.count)")
//            print("Causal links: \(response.logicSpine.causalLinks.count)")
//            print("Bridge points: \(response.bridgePoints.count)")
//            
//            print("\n📊 DECODED SECTIONS:")
//            for (index, section) in response.sections.enumerated() {
//                print("  Section \(index + 1):")
//                print("    id: \(section.id)")
//                print("    role: \(section.role)")
//                print("    startText: \(section.startText.prefix(50))...")
//                print("    endText: \(section.endText.prefix(50))...")
//            }
//            
//        } catch let DecodingError.dataCorrupted(context) {
//            print("❌ DECODING ERROR: Data Corrupted")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Data Corrupted: \(context.debugDescription)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.keyNotFound(key, context) {
//            print("❌ DECODING ERROR: Key Not Found")
//            print("Missing key: \(key)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Missing key: \(key.stringValue)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.valueNotFound(value, context) {
//            print("❌ DECODING ERROR: Value Not Found")
//            print("Missing value type: \(value)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Value not found: \(value)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.typeMismatch(type, context) {
//            print("❌ DECODING ERROR: Type Mismatch")
//            print("Expected type: \(type)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Type mismatch: expected \(type)"
//            currentStep = .pasteResponse
//            return
//        } catch {
//            print("❌ UNKNOWN DECODING ERROR")
//            print("Error: \(error)")
//            print("Error type: \(type(of: error))")
//            print("Localized description: \(error.localizedDescription)")
//            saveError = "Decoding failed: \(error.localizedDescription)"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        // Calculate timestamps
//        print("\n⏱️ CALCULATING TIMESTAMPS...")
//        
//        guard let transcript = video.transcript else {
//            print("❌ FATAL: No transcript available")
//            saveError = "No transcript available"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        print("Transcript length: \(transcript.count) characters")
//        print("Transcript word count: \(transcript.split(separator: " ").count) words")
//        print("Video duration: \(video.duration)")
//        
//        let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
//        
//        print("Words per second: \(calculator.wordsPerSecond)")
//        
//        var sectionsWithTimestamps: [SectionData] = []
//        
//        print("\n🔢 PROCESSING SECTIONS...")
//        for (index, section) in response.sections.enumerated() {
//            print("\nSection \(index + 1) (\(section.id)):")
//            print("  Start text search: '\(section.startText.prefix(40))...'")
//            
//            let startTime = calculator.calculateTimestamp(for: section.startText)
//            print("  ✅ Start time: \(startTime)s (\(formatSeconds(startTime)))")
//            
//            print("  End text search: '\(section.endText.prefix(40))...'")
//            let endTime = calculator.calculateTimestamp(for: section.endText)
//            print("  ✅ End time: \(endTime)s (\(formatSeconds(endTime)))")
//            
//            let sectionData = SectionData(
//                id: section.id,
//                timeRange: TimeRange(start: startTime, end: endTime),
//                role: section.role,
//                goal: section.goal,
//                logicSpineStep: section.logicSpineStep
//            )
//            
//            sectionsWithTimestamps.append(sectionData)
//        }
//        
//        print("\n✅ All sections processed")
//        
//        // Convert causal links
//        print("\n🔗 PROCESSING CAUSAL LINKS...")
//        let causalLinks = response.logicSpine.causalLinks.map { link in
//            CausalLink(from: link.from, to: link.to, connection: link.connection)
//        }
//        print("✅ Converted \(causalLinks.count) causal links")
//        
//        // Calculate bridge point timestamps
//        print("\n🌉 PROCESSING BRIDGE POINTS...")
//        var bridgePointsWithTimestamps: [BridgePoint] = []
//        
//        for (index, bridge) in response.bridgePoints.enumerated() {
//            print("\nBridge \(index + 1):")
//            print("  Text: '\(bridge.text.prefix(60))...'")
//            
//            let timestamp = calculator.calculateTimestamp(for: bridge.text)
//            print("  ✅ Timestamp: \(timestamp)s (\(formatSeconds(timestamp)))")
//            
//            let bridgeData = BridgePoint(
//                text: bridge.text,
//                belongsTo: bridge.belongsTo,
//                timestamp: timestamp
//            )
//            
//            bridgePointsWithTimestamps.append(bridgeData)
//        }
//        
//        print("\n✅ All bridge points processed")
//        
//        // Create alignment data
//        print("\n📦 CREATING ALIGNMENT DATA...")
//        let alignmentData = AlignmentData(
//            videoId: video.videoId,
//            channelId: video.channelId,
//            sections: sectionsWithTimestamps,
//            logicSpine: LogicSpineData(
//                chain: response.logicSpine.chain,
//                causalLinks: causalLinks
//            ),
//            bridgePoints: bridgePointsWithTimestamps
//        )
//        
//        print("✅ AlignmentData created")
//        
//        // Validate
//        print("\n✔️ VALIDATING ALIGNMENT DATA...")
//        let validator = AlignmentValidator()
//        let validation = validator.validate(alignmentData)
//        
//        print("Validation status: \(validation.status)")
//        print("Issues found: \(validation.issues.count)")
//        
//        for (index, issue) in validation.issues.enumerated() {
//            print("  Issue \(index + 1): [\(issue.severity)] \(issue.message)")
//        }
//        
//        var finalData = alignmentData
//        finalData.validationStatus = validation.status
//        finalData.validationIssues = validation.issues.isEmpty ? nil : validation.issues
//        
//        print("\n✅ Validation complete")
//        
//        processedAlignment = finalData
//        currentStep = .reviewCalculated
//        
//        print("\n========================================")
//        print("✅ PROCESSING COMPLETE")
//        print("========================================")
//        print("\n")
//    }
//    private func processResponseoldANDBROKE() async {
//        currentStep = .processing
//        saveError = nil
//        
//        print("\n")
//        print("========================================")
//        print("🔍 STARTING RESPONSE PROCESSING")
//        print("========================================")
//        
//        // Small delay for UI feedback
//        try? await Task.sleep(nanoseconds: 500_000_000)
//        
//        print("\n📥 RAW JSON RESPONSE:")
//        print("Length: \(jsonResponse.count) characters")
//        print("First 200 chars: \(String(jsonResponse.prefix(200)))")
//        print("Last 200 chars: \(String(jsonResponse.suffix(200)))")
//        print("\nFULL RAW JSON:")
//        print(jsonResponse)
//        print("\n")
//        
//        // Clean JSON
//        var cleanJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        print("🧹 CLEANING JSON...")
//        print("Has markdown fence: \(cleanJSON.hasPrefix("```json"))")
//        
//        if cleanJSON.hasPrefix("```json") {
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
//            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
//            print("✅ Removed markdown fences")
//        }
//        
//        print("\n📋 CLEANED JSON:")
//        print("Length: \(cleanJSON.count) characters")
//        print("First 200 chars: \(String(cleanJSON.prefix(200)))")
//        print("Last 200 chars: \(String(cleanJSON.suffix(200)))")
//        print("\nFULL CLEANED JSON:")
//        print(cleanJSON)
//        print("\n")
//        
//        guard let jsonData = cleanJSON.data(using: .utf8) else {
//            print("❌ FATAL: Could not convert string to UTF-8 data")
//            saveError = "Could not convert string to UTF-8 data"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        print("✅ Successfully converted to Data object")
//        print("Data size: \(jsonData.count) bytes")
//        
//        // Parse response (without timestamps)
//        struct AlignmentResponse: Codable {
//            struct SectionResponse: Codable {
//                let id: String
//                let startText: String
//                let endText: String
//                let role: String
//                let goal: String
//                let logicSpineStep: String
//            }
//            
//            let sections: [SectionResponse]
//            let logicSpine: LogicSpineData
//            let bridgePoints: [BridgePoint]
//        }
//        
//        print("\n🔬 ATTEMPTING TO DECODE JSON...")
//        print("Expected structure:")
//        print("  - sections: Array<SectionResponse>")
//        print("    - id: String")
//        print("    - startText: String")
//        print("    - endText: String")
//        print("    - role: String")
//        print("    - goal: String")
//        print("    - logicSpineStep: String")
//        print("  - logicSpine: LogicSpineData")
//        print("  - bridgePoints: Array<BridgePoint>")
//        print("\n")
//        
//        let decoder = JSONDecoder()
//        let response: AlignmentResponse
//        
//        do {
//            response = try decoder.decode(AlignmentResponse.self, from: jsonData)
//            print("✅ JSON DECODED SUCCESSFULLY!")
//            print("Sections found: \(response.sections.count)")
//            print("Logic spine steps: \(response.logicSpine.chain.count)")
//            print("Bridge points: \(response.bridgePoints.count)")
//            
//            print("\n📊 DECODED SECTIONS:")
//            for (index, section) in response.sections.enumerated() {
//                print("  Section \(index + 1):")
//                print("    id: \(section.id)")
//                print("    role: \(section.role)")
//                print("    startText: \(section.startText.prefix(50))...")
//                print("    endText: \(section.endText.prefix(50))...")
//                print("    goal: \(section.goal.prefix(50))...")
//            }
//            
//        } catch let DecodingError.dataCorrupted(context) {
//            print("❌ DECODING ERROR: Data Corrupted")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Data Corrupted: \(context.debugDescription)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.keyNotFound(key, context) {
//            print("❌ DECODING ERROR: Key Not Found")
//            print("Missing key: \(key)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Missing key: \(key.stringValue) at \(context.codingPath)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.valueNotFound(value, context) {
//            print("❌ DECODING ERROR: Value Not Found")
//            print("Missing value type: \(value)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Value not found: \(value) at \(context.codingPath)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.typeMismatch(type, context) {
//            print("❌ DECODING ERROR: Type Mismatch")
//            print("Expected type: \(type)")
//            print("Context: \(context)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug description: \(context.debugDescription)")
//            saveError = "Type mismatch: expected \(type) at \(context.codingPath)"
//            currentStep = .pasteResponse
//            return
//        } catch {
//            print("❌ UNKNOWN DECODING ERROR")
//            print("Error: \(error)")
//            print("Error type: \(type(of: error))")
//            print("Localized description: \(error.localizedDescription)")
//            saveError = "Decoding failed: \(error.localizedDescription)"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        // Calculate timestamps
//        print("\n⏱️ CALCULATING TIMESTAMPS...")
//        
//        guard let transcript = video.transcript else {
//            print("❌ FATAL: No transcript available")
//            saveError = "No transcript available"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        print("Transcript length: \(transcript.count) characters")
//        print("Transcript word count: \(transcript.split(separator: " ").count) words")
//        print("Video duration: \(video.duration)")
//        
//        let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
//        
//        print("Words per second: \(calculator.wordsPerSecond)")
//        
//        var sectionsWithTimestamps: [SectionData] = []
//        
//        print("\n🔢 PROCESSING SECTIONS...")
//        for (index, section) in response.sections.enumerated() {
//            print("\nSection \(index + 1) (\(section.id)):")
//            print("  Start text search: '\(section.startText.prefix(40))...'")
//            
//            let startTime = calculator.calculateTimestamp(for: section.startText)
//            print("  ✅ Start time: \(startTime)s (\(formatSeconds(startTime)))")
//            
//            print("  End text search: '\(section.endText.prefix(40))...'")
//            let endTime = calculator.calculateTimestamp(for: section.endText)
//            print("  ✅ End time: \(endTime)s (\(formatSeconds(endTime)))")
//            
//            let sectionData = SectionData(
//                id: section.id,
//                timeRange: TimeRange(start: startTime, end: endTime),
//                role: section.role,
//                goal: section.goal,
//                logicSpineStep: section.logicSpineStep
//            )
//            
//            sectionsWithTimestamps.append(sectionData)
//        }
//        
//        print("\n✅ All sections processed")
//        
//        // Calculate bridge point timestamps
//        print("\n🌉 PROCESSING BRIDGE POINTS...")
//        var bridgePointsWithTimestamps: [BridgePoint] = []
//        
//        for (index, bridge) in response.bridgePoints.enumerated() {
//            print("\nBridge \(index + 1):")
//            print("  Text: '\(bridge.text.prefix(60))...'")
//            
//            let timestamp = calculator.calculateTimestamp(for: bridge.text)
//            print("  ✅ Timestamp: \(timestamp)s (\(formatSeconds(timestamp)))")
//            
//            let bridgeData = BridgePoint(
//                text: bridge.text,
//                belongsTo: bridge.belongsTo,
//                timestamp: timestamp
//            )
//            
//            bridgePointsWithTimestamps.append(bridgeData)
//        }
//        
//        print("\n✅ All bridge points processed")
//        
//        // Create alignment data
//        print("\n📦 CREATING ALIGNMENT DATA...")
//        let alignmentData = AlignmentData(
//            videoId: video.videoId,
//            channelId: video.channelId,
//            sections: sectionsWithTimestamps,
//            logicSpine: response.logicSpine,
//            bridgePoints: bridgePointsWithTimestamps
//        )
//        
//        print("✅ AlignmentData created")
//        
//        // Validate
//        print("\n✔️ VALIDATING ALIGNMENT DATA...")
//        let validator = AlignmentValidator()
//        let validation = validator.validate(alignmentData)
//        
//        print("Validation status: \(validation.status)")
//        print("Issues found: \(validation.issues.count)")
//        
//        for (index, issue) in validation.issues.enumerated() {
//            print("  Issue \(index + 1): [\(issue.severity)] \(issue.message)")
//        }
//        
//        var finalData = alignmentData
//        finalData.validationStatus = validation.status
//        finalData.validationIssues = validation.issues.isEmpty ? nil : validation.issues
//        
//        print("\n✅ Validation complete")
//        
//        processedAlignment = finalData
//        currentStep = .reviewCalculated
//        
//        print("\n========================================")
//        print("✅ PROCESSING COMPLETE")
//        print("========================================")
//        print("\n")
//    }
//    
//    private func saveToFirebase() async {
//        guard let alignment = processedAlignment else { return }
//        
//        currentStep = .saving
//        saveError = nil
//        
//        do {
//            try await CreatorAnalysisFirebase.shared.saveAlignmentDoc(data: alignment)
//            savedAlignment = alignment
//            currentStep = .complete
//        } catch {
//            saveError = "Failed to save: \(error.localizedDescription)"
//            currentStep = .reviewCalculated
//        }
//    }
//    
//    private func formatSeconds(_ seconds: Int) -> String {
//        let minutes = seconds / 60
//        let secs = seconds % 60
//        return String(format: "%d:%02d", minutes, secs)
//    }
//    
//    private func roleColor(_ role: String) -> Color {
//        switch role {
//        case "HOOK": return .blue
//        case "SETUP": return .green
//        case "EVIDENCE": return .purple
//        case "TURN": return .orange
//        case "PAYOFF": return .pink
//        case "CTA": return .red
//        case "SPONSORSHIP": return .gray
//        default: return .secondary
//        }
//    }
//}
//
// MARK: - Timestamp Calculator
struct TimestampCalculatorOld {
    let transcript: String
    let wordsPerSecond: Double
    
    init(transcript: String, duration: String) {
        let totalWords = transcript.split(separator: " ").count
        let totalSeconds = Self.parseDuration(duration)
        self.transcript = transcript
        self.wordsPerSecond = totalSeconds > 0 ? Double(totalWords) / Double(totalSeconds) : 0
        
        print("📊 TIMESTAMP CALCULATOR INIT:")
        print("  Duration string: '\(duration)'")
        print("  Parsed seconds: \(totalSeconds)")
        print("  Total words: \(totalWords)")
        print("  Words per second: \(wordsPerSecond)")
    }
    
    func calculateTimestamp(for textSnippet: String) -> Int {
        let wordPosition = findWordPosition(textSnippet, in: transcript)
        
        // Handle division by zero
        guard wordsPerSecond > 0 else {
            print("⚠️ WARNING: wordsPerSecond is 0, cannot calculate timestamp")
            return 0
        }
        
        let timestampDouble = Double(wordPosition) / wordsPerSecond
        
        // Check for NaN or infinity
        guard timestampDouble.isFinite else {
            print("⚠️ WARNING: timestamp calculation resulted in NaN/Infinity")
            return 0
        }
        
        let timestamp = Int(timestampDouble)
        return max(0, timestamp)
    }
    
    private func findWordPosition(_ snippet: String, in fullText: String) -> Int {
        let words = fullText.split(separator: " ").map { String($0) }
        let snippetWords = snippet.split(separator: " ").map { String($0) }
        
        guard snippetWords.count > 0 else { return 0 }
        
        // Search for matching sequence
        for i in 0...(words.count - snippetWords.count) {
            var match = true
            for j in 0..<snippetWords.count {
                let word1 = words[i + j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                let word2 = snippetWords[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                if word1 != word2 {
                    match = false
                    break
                }
            }
            if match {
                return i
            }
        }
        
        // Fallback: fuzzy search
        return fuzzySearch(snippetWords, in: words)
    }
    
    private func fuzzySearch(_ snippetWords: [String], in words: [String]) -> Int {
        var bestMatch = 0
        var bestScore = 0
        
        for i in 0...(words.count - snippetWords.count) {
            var score = 0
            for j in 0..<snippetWords.count {
                let word1 = words[i + j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                let word2 = snippetWords[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                if word1 == word2 {
                    score += 1
                }
            }
            if score > bestScore {
                bestScore = score
                bestMatch = i
            }
        }
        
        return bestMatch
    }
    
    static func parseDuration(_ duration: String) -> Int {
        // Handle ISO 8601 duration format (e.g., "PT12M58S")
        if duration.hasPrefix("PT") {
            let timeString = duration.dropFirst(2) // Remove "PT"
            var hours = 0
            var minutes = 0
            var seconds = 0
            
            let parts = timeString.components(separatedBy: CharacterSet(charactersIn: "HMS"))
            var currentValue = ""
            
            for char in timeString {
                if char.isNumber {
                    currentValue.append(char)
                } else if char == "H" {
                    hours = Int(currentValue) ?? 0
                    currentValue = ""
                } else if char == "M" {
                    minutes = Int(currentValue) ?? 0
                    currentValue = ""
                } else if char == "S" {
                    seconds = Int(currentValue) ?? 0
                    currentValue = ""
                }
            }
            
            let totalSeconds = hours * 3600 + minutes * 60 + seconds
            print("  Parsed ISO 8601: \(hours)h \(minutes)m \(seconds)s = \(totalSeconds)s")
            return totalSeconds
        }
        
        // Handle MM:SS or HH:MM:SS format
        let components = duration.split(separator: ":")
        if components.count == 2 {
            // MM:SS
            let minutes = Int(components[0]) ?? 0
            let seconds = Int(components[1]) ?? 0
            return minutes * 60 + seconds
        } else if components.count == 3 {
            // HH:MM:SS
            let hours = Int(components[0]) ?? 0
            let minutes = Int(components[1]) ?? 0
            let seconds = Int(components[2]) ?? 0
            return hours * 3600 + minutes * 60 + seconds
        }
        
        print("⚠️ WARNING: Could not parse duration '\(duration)'")
        return 0
    }
}

//// MARK: - Timestamp Calculator
//struct TimestampCalculatorold {
//    let transcript: String
//    let wordsPerSecond: Double
//    
//    init(transcript: String, duration: String) {
//        let totalWords = transcript.split(separator: " ").count
//        let totalSeconds = Self.parseDuration(duration)
//        self.transcript = transcript
//        self.wordsPerSecond = totalSeconds > 0 ? Double(totalWords) / Double(totalSeconds) : 0
//    }
//    
//    func calculateTimestamp(for textSnippet: String) -> Int {
//        let wordPosition = findWordPosition(textSnippet, in: transcript)
//        let timestamp = Int(Double(wordPosition) / wordsPerSecond)
//        return max(0, timestamp)
//    }
//    
//    private func findWordPosition(_ snippet: String, in fullText: String) -> Int {
//        let words = fullText.split(separator: " ").map { String($0) }
//        let snippetWords = snippet.split(separator: " ").map { String($0) }
//        
//        guard snippetWords.count > 0 else { return 0 }
//        
//        // Search for matching sequence
//        for i in 0...(words.count - snippetWords.count) {
//            var match = true
//            for j in 0..<snippetWords.count {
//                let word1 = words[i + j].lowercased().trimmingCharacters(in: .punctuationCharacters)
//                let word2 = snippetWords[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
//                if word1 != word2 {
//                    match = false
//                    break
//                }
//            }
//            if match {
//                return i
//            }
//        }
//        
//        // Fallback: fuzzy search
//        return fuzzySearch(snippetWords, in: words)
//    }
//    
//    private func fuzzySearch(_ snippetWords: [String], in words: [String]) -> Int {
//        var bestMatch = 0
//        var bestScore = 0
//        
//        for i in 0...(words.count - snippetWords.count) {
//            var score = 0
//            for j in 0..<snippetWords.count {
//                let word1 = words[i + j].lowercased().trimmingCharacters(in: .punctuationCharacters)
//                let word2 = snippetWords[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
//                if word1 == word2 {
//                    score += 1
//                }
//            }
//            if score > bestScore {
//                bestScore = score
//                bestMatch = i
//            }
//        }
//        
//        return bestMatch
//    }
//    
//    static func parseDuration(_ duration: String) -> Int {
//        let components = duration.split(separator: ":")
//        if components.count == 2 {
//            // MM:SS
//            let minutes = Int(components[0]) ?? 0
//            let seconds = Int(components[1]) ?? 0
//            return minutes * 60 + seconds
//        } else if components.count == 3 {
//            // HH:MM:SS
//            let hours = Int(components[0]) ?? 0
//            let minutes = Int(components[1]) ?? 0
//            let seconds = Int(components[2]) ?? 0
//            return hours * 3600 + minutes * 60 + seconds
//        }
//        return 0
//    }
//}
//
// MARK: - Alignment Validator (unchanged)
struct AlignmentValidatorOld {
    func validate(_ alignment: AlignmentData) -> (status: ValidationStatus, issues: [ValidationIssue]) {
        var issues: [ValidationIssue] = []
        
        // Check 1: Section count reasonable
        if alignment.sections.count < 2 {
            issues.append(ValidationIssue(
                severity: .error,
                type: .sectionCount,
                message: "Only \(alignment.sections.count) sections (expected 3-8)"
            ))
        }
        if alignment.sections.count > 12 {
            issues.append(ValidationIssue(
                severity: .warning,
                type: .sectionCount,
                message: "Many sections (\(alignment.sections.count)) - may be over-segmented"
            ))
        }
        
        // Check 2: Section boundaries valid (word indexes or time ranges)
        for i in 0..<alignment.sections.count-1 {
            let current = alignment.sections[i]
            let next = alignment.sections[i+1]

            // Check word boundaries (new format)
            if let currentEnd = current.endWordIndex, let nextStart = next.startWordIndex {
                if currentEnd >= nextStart {
                    issues.append(ValidationIssue(
                        severity: .error,
                        type: .timeOverlap,
                        message: "Section \(i) overlaps with \(i+1) (word indexes)"
                    ))
                }
                if currentEnd + 1 < nextStart {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        type: .timeGap,
                        message: "Gap between sections \(i) and \(i+1) (word indexes)"
                    ))
                }
            }
            // Fall back to time range checks (legacy format)
            else if let currentTime = current.timeRange, let nextTime = next.timeRange {
                if currentTime.end > nextTime.start {
                    issues.append(ValidationIssue(
                        severity: .error,
                        type: .timeOverlap,
                        message: "Section \(i) overlaps with \(i+1)"
                    ))
                }
                if currentTime.end < nextTime.start - 5 {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        type: .timeGap,
                        message: "Gap between sections \(i) and \(i+1)"
                    ))
                }
            }
        }
        
        // Check 3: Logic spine complete
        if alignment.logicSpine.chain.count != alignment.sections.count {
            issues.append(ValidationIssue(
                severity: .error,
                type: .incompleteSpine,
                message: "Logic spine has \(alignment.logicSpine.chain.count) steps but \(alignment.sections.count) sections"
            ))
        }
        
        // Check 4: Roles logical
        let roleSequence = alignment.sections.map { $0.role }
        if roleSequence.contains("PAYOFF") && !roleSequence.contains("HOOK") {
            issues.append(ValidationIssue(
                severity: .warning,
                type: .illogicalFlow,
                message: "PAYOFF without HOOK"
            ))
        }
        
        let status: ValidationStatus = issues.contains { $0.severity == .error } ? .failed : .passed
        
        return (status: status, issues: issues)
    }
}
//
//
//// MARK: - Paste this at the bottom of ManualIngestionView.swift
//extension ManualIngestionView {
//    private func generatePromptBroke() {
//        guard let transcript = video.transcript else {
//            generatedPrompt = "⚠️ No transcript available for this video"
//            return
//        }
//        
//        generatedPrompt = """
//You are analyzing a YouTube video transcript to extract its structural spine.
//
//TRANSCRIPT:
//\(transcript)
//
//VIDEO METADATA:
//Title: \(video.title)
//Duration: \(video.duration)
//
//Extract the following:
//
//1. SECTIONS WITH ROLES
//Identify 3-8 major sections. For each section:
//- startText: First 8-12 words of the section (EXACT text from transcript)
//- endText: Last 8-12 words of the section (EXACT text from transcript)
//- role: HOOK, SETUP, EVIDENCE, TURN, PAYOFF, CTA, or SPONSORSHIP
//- goal: What this section accomplishes
//- logicSpineStep: One sentence describing this step in the argument
//
//IMPORTANT ROLES:
//- HOOK: Generate curiosity, establish question
//- SETUP: Provide context, establish stakes
//- EVIDENCE: Build case with data, stories, authority
//- TURN: Subvert expectations, reveal insight
//- PAYOFF: Deliver on hook's promise
//- CTA: Call to action
//- SPONSORSHIP: Sponsorship/ad read (don't remove, just flag it)
//
//2. LOGIC SPINE (Causal Chain)
//Write out how each section builds on the previous as a simple array of strings.
//Example: ["HOOK claims X causes Y", "SETUP introduces context Z", "EVIDENCE proves X with data"...]
//
//3. BRIDGE POINTS
//Identify 1-3 sentences that belong to TWO sections (transitions).
//Provide the EXACT text of the bridge sentence.
//
//OUTPUT FORMAT (strict JSON):
//{
//  "sections": [
//    {
//      "id": "sect_1",
//      "startText": "Exact first 8-12 words from transcript...",
//      "endText": "Exact last 8-12 words from transcript...",
//      "role": "HOOK",
//      "goal": "Generate curiosity about...",
//      "logicSpineStep": "Claims that X causes Y"
//    }
//  ],
//  "logicSpine": {
//    "chain": ["HOOK claims X→Y", "SETUP introduces Z"...]
//  },
//  "bridgePoints": [
//    {
//      "text": "Exact bridge sentence text from transcript...",
//      "belongsTo": ["sect_3", "sect_4"]
//    }
//  ]
//}
//
//CRITICAL:
//- Use EXACT text from transcript for startText, endText, and bridge text
//- DO NOT include causalLinks in logicSpine - just the chain array
//- DO NOT include timestamps - we will calculate them from word positions
//- Return ONLY valid JSON, no markdown formatting
//"""
//    }
//}
//
//
//extension ManualIngestionView {
//    private func generatePrompt() {
//        guard let transcript = video.transcript else {
//            generatedPrompt = "⚠️ No transcript available for this video"
//            return
//        }
//        
//        generatedPrompt = """
//You are analyzing a YouTube video transcript to extract its structural spine.
//
//TRANSCRIPT:
//\(transcript)
//
//VIDEO METADATA:
//Title: \(video.title)
//Duration: \(video.duration)
//
//Extract the following:
//
//1. SECTIONS WITH ROLES
//Identify 3-8 major sections. For each section:
//- id: "sect_1", "sect_2", etc.
//- startText: First 8-12 words of the section (EXACT text from transcript)
//- endText: Last 8-12 words of the section (EXACT text from transcript)
//- role: HOOK, SETUP, EVIDENCE, TURN, PAYOFF, CTA, or SPONSORSHIP
//- goal: What this section accomplishes
//- logicSpineStep: One sentence describing this step in the argument
//
//2. LOGIC SPINE
//- chain: Array of strings describing each step
//- causalLinks: Array of connections between sections with "from", "to", "connection"
//
//3. BRIDGE POINTS
//- text: EXACT bridge sentence from transcript
//- belongsTo: Array of section IDs this bridges
//
//OUTPUT FORMAT (strict JSON):
//{
//  "sections": [
//    {
//      "id": "sect_1",
//      "startText": "Exact first 8-12 words from transcript",
//      "endText": "Exact last 8-12 words from transcript",
//      "role": "HOOK",
//      "goal": "Generate curiosity about...",
//      "logicSpineStep": "Claims that X causes Y"
//    }
//  ],
//  "logicSpine": {
//    "chain": [
//      "HOOK claims X→Y",
//      "SETUP introduces Z"
//    ],
//    "causalLinks": [
//      {
//        "from": "sect_1",
//        "to": "sect_2",
//        "connection": "HOOK's question leads to SETUP's context"
//      }
//    ]
//  },
//  "bridgePoints": [
//    {
//      "text": "Exact bridge sentence from transcript",
//      "belongsTo": ["sect_1", "sect_2"]
//    }
//  ]
//}
//
//CRITICAL:
//- DO NOT include "id" in causalLinks or bridgePoints (auto-generated)
//- DO NOT include "timestamp" in bridgePoints (calculated later)
//- DO NOT include "timeRange" in sections (calculated later)
//- Use EXACT text from transcript for startText, endText, and bridge text
//- Return ONLY valid JSON, no markdown formatting
//"""
//    }
//}

import SwiftUI

//
//// MARK: - Manual Ingestion View (Extended for A1b)
//struct ManualIngestionViewOld: View {
//    let video: YouTubeVideo
//    @Environment(\.dismiss) private var dismiss
//    
//    @State private var currentStep: IngestionStep = .showPrompt
//    @State private var generatedPrompt: String = ""
//    @State private var jsonResponse: String = ""
//    @State private var processedAlignment: AlignmentData?
//    @State private var savedAlignment: AlignmentData?
//    @State private var isSaving = false
//    @State private var saveError: String?
//    
//    // A1b Beat Extraction State
//    @State private var beatExtractionStep: BeatExtractionStep = .notStarted
//    @State private var currentSectionIndex: Int = 0
//    @State private var beatPrompt: String = ""
//    @State private var beatResponse: String = ""
//    @State private var extractedBeats: [BeatData] = []
//    @State private var processedBeatData: BeatData?
//    
//    enum IngestionStep {
//        case showPrompt          // A1a: Show structural spine prompt
//        case pasteResponse       // A1a: Paste JSON response
//        case processing          // A1a: Processing response
//        case reviewCalculated    // A1a: Review calculated timestamps
//        case saving              // A1a: Saving to Firebase
//        case complete            // A1a: Complete - ready for A1b
//        case beatExtraction      // A1b: Beat extraction flow
//    }
//    
//    enum BeatExtractionStep {
//        case notStarted
//        case showBeatPrompt
//        case pasteBeatResponse
//        case processingBeat
//        case reviewBeat
//        case savingBeat
//        case allBeatsComplete
//    }
//    
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 20) {
//                
//                // Video Info
//                videoInfoSection
//                
//                Divider()
//                
//                // Step Views
//                switch currentStep {
//                case .showPrompt:
//                    promptStepView
//                case .pasteResponse:
//                    responseStepView
//                case .processing:
//                    processingStepView
//                case .reviewCalculated:
//                    reviewStepView
//                case .saving:
//                    savingStepView
//                case .complete:
//                    completeStepView
//                case .beatExtraction:
//                    beatExtractionFlowView
//                }
//            }
//            .padding()
//        }
//        .navigationTitle(currentStep == .beatExtraction ? "A1b: Extract Beats" : "A1a: Analyze Structure")
//        .navigationBarTitleDisplayMode(.inline)
//        .toolbar {
//            ToolbarItem(placement: .cancellationAction) {
//                Button("Cancel") {
//                    dismiss()
//                }
//            }
//        }
//        .onAppear {
//            if currentStep == .showPrompt {
//                generatePrompt()
//            }
//        }
//    }
//    
//    // MARK: - Video Info Section
//    private var videoInfoSection: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            Text(video.title)
//                .font(.headline)
//            
//            HStack {
//                Label(video.duration, systemImage: "clock")
//                Spacer()
//                if let transcript = video.transcript {
//                    Label("\(transcript.split(separator: " ").count) words", systemImage: "text.alignleft")
//                }
//            }
//            .font(.caption)
//            .foregroundColor(.secondary)
//        }
//        .padding()
//        .background(Color(.secondarySystemBackground))
//        .cornerRadius(8)
//    }
//    
//    // MARK: - A1a Steps (existing code - keeping as is)
//    
//    private var promptStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "1.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.blue)
//                Text("Copy Prompt")
//                    .font(.headline)
//            }
//            
//            Text("Copy this prompt and paste it into Claude.ai")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//            
//            ScrollView {
//                Text(generatedPrompt)
//                    .font(.system(.body, design: .monospaced))
//                    .textSelection(.enabled)
//                    .padding()
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                    .background(Color(.tertiarySystemBackground))
//                    .cornerRadius(8)
//            }
//            .frame(height: 300)
//            
//            HStack {
//                Button(action: {
//                    UIPasteboard.general.string = generatedPrompt
//                }) {
//                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    currentStep = .pasteResponse
//                }) {
//                    Label("Next: Paste Response", systemImage: "arrow.right")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//    
//    private var responseStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "2.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.green)
//                Text("Paste JSON Response")
//                    .font(.headline)
//            }
//            
//            Text("Paste Claude's JSON response below (without timestamps)")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//            
//            TextEditor(text: $jsonResponse)
//                .font(.system(.body, design: .monospaced))
//                .frame(height: 300)
//                .padding(4)
//                .background(Color(.tertiarySystemBackground))
//                .cornerRadius(8)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 8)
//                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
//                )
//            
//            if let error = saveError {
//                HStack {
//                    Image(systemName: "exclamationmark.triangle.fill")
//                        .foregroundColor(.red)
//                    Text(error)
//                        .font(.caption)
//                        .foregroundColor(.red)
//                }
//                .padding(8)
//                .background(Color.red.opacity(0.1))
//                .cornerRadius(8)
//            }
//            
//            HStack {
//                Button(action: {
//                    currentStep = .showPrompt
//                    saveError = nil
//                }) {
//                    Label("Back", systemImage: "arrow.left")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    Task {
//                        await processResponse()
//                    }
//                }) {
//                    Label("Process & Calculate", systemImage: "gearshape.2")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//                .disabled(jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
//            }
//        }
//    }
//    
//    private var processingStepView: some View {
//        VStack(spacing: 20) {
//            ProgressView()
//                .scaleEffect(1.5)
//            Text("Calculating timestamps...")
//                .font(.headline)
//            Text("Using word-count-based positioning")
//                .font(.caption)
//                .foregroundColor(.secondary)
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//    }
//    
//    private var reviewStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "3.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.orange)
//                Text("Review Calculated Timestamps")
//                    .font(.headline)
//            }
//            
//            if let alignment = processedAlignment {
//                ScrollView {
//                    VStack(alignment: .leading, spacing: 12) {
//                        ForEach(Array(alignment.sections.enumerated()), id: \.element.id) { index, section in
//                            VStack(alignment: .leading, spacing: 4) {
//                                HStack {
//                                    Text(section.role)
//                                        .font(.caption)
//                                        .padding(.horizontal, 8)
//                                        .padding(.vertical, 4)
//                                        .background(roleColor(section.role).opacity(0.2))
//                                        .foregroundColor(roleColor(section.role))
//                                        .cornerRadius(4)
//                                    
//                                    Text("\(formatSeconds(section.timeRange.start)) - \(formatSeconds(section.timeRange.end))")
//                                        .font(.caption)
//                                        .foregroundColor(.secondary)
//                                    
//                                    Spacer()
//                                }
//                                
//                                Text(section.goal)
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                            .padding(8)
//                            .background(Color(.secondarySystemBackground))
//                            .cornerRadius(6)
//                        }
//                        
//                        Divider()
//                        
//                        Text("Bridge Points: \(alignment.bridgePoints.count)")
//                            .font(.subheadline)
//                            .fontWeight(.medium)
//                        
//                        Text("Logic Spine: \(alignment.logicSpine.chain.count) steps")
//                            .font(.subheadline)
//                            .fontWeight(.medium)
//                        
//                        if let issues = alignment.validationIssues, !issues.isEmpty {
//                            VStack(alignment: .leading, spacing: 8) {
//                                Text("Validation Issues:")
//                                    .font(.subheadline)
//                                    .fontWeight(.medium)
//                                
//                                ForEach(issues, id: \.message) { issue in
//                                    HStack(alignment: .top, spacing: 8) {
//                                        Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
//                                            .foregroundColor(issue.severity == .error ? .red : .orange)
//                                        Text(issue.message)
//                                            .font(.caption)
//                                    }
//                                }
//                            }
//                            .padding()
//                            .background(Color.orange.opacity(0.1))
//                            .cornerRadius(8)
//                        }
//                    }
//                }
//                .frame(maxHeight: 400)
//            }
//            
//            HStack {
//                Button(action: {
//                    currentStep = .pasteResponse
//                    saveError = nil
//                }) {
//                    Label("Back", systemImage: "arrow.left")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    Task {
//                        await saveToFirebase()
//                    }
//                }) {
//                    Label("Save to Firebase", systemImage: "square.and.arrow.down")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//    
//    private var savingStepView: some View {
//        VStack(spacing: 20) {
//            ProgressView()
//                .scaleEffect(1.5)
//            Text("Saving to Firebase...")
//                .font(.headline)
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//    }
//    
//    private var completeStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "checkmark.circle.fill")
//                    .font(.title)
//                    .foregroundColor(.green)
//                Text("A1a Complete!")
//                    .font(.headline)
//            }
//            
//            if let alignment = savedAlignment {
//                VStack(alignment: .leading, spacing: 12) {
//                    Text("✅ Extracted \(alignment.sections.count) sections")
//                    Text("✅ Logic spine: \(alignment.logicSpine.chain.count) steps")
//                    Text("✅ Bridge points: \(alignment.bridgePoints.count)")
//                    Text("✅ Timestamps calculated with ~5% accuracy")
//                    
//                    if let issues = alignment.validationIssues, !issues.isEmpty {
//                        Text("⚠️ \(issues.filter { $0.severity == .warning }.count) warnings")
//                            .foregroundColor(.orange)
//                    }
//                }
//                .font(.subheadline)
//                .padding()
//                .background(Color(.secondarySystemBackground))
//                .cornerRadius(8)
//            }
//            
//            Divider()
//            
//            Text("Ready for A1b: Beat Extraction")
//                .font(.headline)
//            
//            Text("Extract beats for each of the \(savedAlignment?.sections.count ?? 0) sections")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//            
//            HStack {
//                Button(action: {
//                    dismiss()
//                }) {
//                    Text("Done")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    currentStep = .beatExtraction
//                    beatExtractionStep = .showBeatPrompt
//                    currentSectionIndex = 0
//                    generateBeatPrompt()
//                }) {
//                    Label("Continue to A1b", systemImage: "arrow.right")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//    
//    // MARK: - A1b Beat Extraction Flow
//    
//    private var beatExtractionFlowView: some View {
//        VStack(alignment: .leading, spacing: 20) {
//            
//            // Progress indicator
//            if let alignment = savedAlignment {
//                beatProgressSection(alignment: alignment)
//            }
//            
//            Divider()
//            
//            // Beat extraction steps
//            switch beatExtractionStep {
//            case .notStarted:
//                EmptyView()
//            case .showBeatPrompt:
//                beatPromptStepView
//            case .pasteBeatResponse:
//                beatResponseStepView
//            case .processingBeat:
//                processingBeatStepView
//            case .reviewBeat:
//                reviewBeatStepView
//            case .savingBeat:
//                savingBeatStepView
//            case .allBeatsComplete:
//                allBeatsCompleteView
//            }
//        }
//    }
//    
//    private func beatProgressSection(alignment: AlignmentData) -> some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("Section \(currentSectionIndex + 1) of \(alignment.sections.count)")
//                .font(.headline)
//            
//            ProgressView(value: Double(currentSectionIndex), total: Double(alignment.sections.count))
//            
//            ForEach(Array(alignment.sections.enumerated()), id: \.element.id) { index, section in
//                HStack {
//                    if index < currentSectionIndex {
//                        Image(systemName: "checkmark.circle.fill")
//                            .foregroundColor(.green)
//                    } else if index == currentSectionIndex {
//                        Image(systemName: "arrow.right.circle.fill")
//                            .foregroundColor(.blue)
//                    } else {
//                        Image(systemName: "circle")
//                            .foregroundColor(.secondary)
//                    }
//                    
//                    Text("\(section.role)")
//                        .font(.subheadline)
//                        .fontWeight(index == currentSectionIndex ? .bold : .regular)
//                    
//                    Spacer()
//                }
//                .padding(8)
//                .background(index == currentSectionIndex ? Color.blue.opacity(0.1) : Color.clear)
//                .cornerRadius(6)
//            }
//        }
//        .padding()
//        .background(Color(.secondarySystemBackground))
//        .cornerRadius(8)
//    }
//    
//    private var beatPromptStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "1.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.purple)
//                Text("Copy Beat Extraction Prompt")
//                    .font(.headline)
//            }
//            
//            if let alignment = savedAlignment {
//                let section = alignment.sections[currentSectionIndex]
//                Text("Section: \(section.role)")
//                    .font(.subheadline)
//                    .foregroundColor(.secondary)
//            }
//            
//            ScrollView {
//                Text(beatPrompt)
//                    .font(.system(.body, design: .monospaced))
//                    .textSelection(.enabled)
//                    .padding()
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                    .background(Color(.tertiarySystemBackground))
//                    .cornerRadius(8)
//            }
//            .frame(height: 300)
//            
//            HStack {
//                Button(action: {
//                    UIPasteboard.general.string = beatPrompt
//                }) {
//                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    beatExtractionStep = .pasteBeatResponse
//                }) {
//                    Label("Next: Paste Response", systemImage: "arrow.right")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//    
//    private var beatResponseStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "2.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.green)
//                Text("Paste Beat JSON Response")
//                    .font(.headline)
//            }
//            
//            TextEditor(text: $beatResponse)
//                .font(.system(.body, design: .monospaced))
//                .frame(height: 300)
//                .padding(4)
//                .background(Color(.tertiarySystemBackground))
//                .cornerRadius(8)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 8)
//                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
//                )
//            
//            if let error = saveError {
//                HStack {
//                    Image(systemName: "exclamationmark.triangle.fill")
//                        .foregroundColor(.red)
//                    Text(error)
//                        .font(.caption)
//                        .foregroundColor(.red)
//                }
//                .padding(8)
//                .background(Color.red.opacity(0.1))
//                .cornerRadius(8)
//            }
//            
//            HStack {
//                Button(action: {
//                    beatExtractionStep = .showBeatPrompt
//                    saveError = nil
//                }) {
//                    Label("Back", systemImage: "arrow.left")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    Task {
//                        await processBeatResponse()
//                    }
//                }) {
//                    Label("Process Beats", systemImage: "gearshape.2")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//                .disabled(beatResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
//            }
//        }
//    }
//    
//    private var processingBeatStepView: some View {
//        VStack(spacing: 20) {
//            ProgressView()
//                .scaleEffect(1.5)
//            Text("Processing beats...")
//                .font(.headline)
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//    }
//    
//    private var reviewBeatStepView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "3.circle.fill")
//                    .font(.title2)
//                    .foregroundColor(.orange)
//                Text("Review Extracted Beats")
//                    .font(.headline)
//            }
//            
//            if let beatData = processedBeatData {
//                ScrollView {
//                    VStack(alignment: .leading, spacing: 16) {
//                        // Beats
//                        Text("Beats (\(beatData.beats.count))")
//                            .font(.headline)
//                        
//                        ForEach(Array(beatData.beats.enumerated()), id: \.offset) { index, beat in
//                            VStack(alignment: .leading, spacing: 8) {
//                                HStack {
//                                    Text(beat.type)
//                                        .font(.caption)
//                                        .padding(.horizontal, 8)
//                                        .padding(.vertical, 4)
//                                        .background(beatTypeColor(beat.type).opacity(0.2))
//                                        .foregroundColor(beatTypeColor(beat.type))
//                                        .cornerRadius(4)
//                                    
//                                    Spacer()
//                                    
//                                    Text(formatSeconds(beat.timeRange.start))
//                                        .font(.caption)
//                                        .foregroundColor(.secondary)
//                                }
//                                
//                                Text(beat.text)
//                                    .font(.body)
//                                
//                                Text(beat.function)
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                                    .italic()
//                            }
//                            .padding()
//                            .background(Color(.tertiarySystemBackground))
//                            .cornerRadius(8)
//                        }
//                        
//                        Divider()
//                        
//                        // Transition
//                        if let transition = beatData.transitionOut {
//                            VStack(alignment: .leading, spacing: 8) {
//                                Text("Transition")
//                                    .font(.headline)
//                                
//                                Text("Type: \(transition.type)")
//                                    .font(.subheadline)
//                                
//                                if let bridge = transition.bridgeSentence {
//                                    Text("Bridge: \"\(bridge)\"")
//                                        .font(.body)
//                                        .italic()
//                                }
//                            }
//                            .padding()
//                            .background(Color(.tertiarySystemBackground))
//                            .cornerRadius(8)
//                        }
//                        
//                        Divider()
//                        
//                        // Anchor lines
//                        VStack(alignment: .leading, spacing: 8) {
//                            Text("Anchor Lines (\(beatData.anchorLines.count))")
//                                .font(.headline)
//                            
//                            ForEach(beatData.anchorLines, id: \.self) { anchor in
//                                Text("• \(anchor)")
//                                    .font(.body)
//                            }
//                        }
//                        .padding()
//                        .background(Color(.tertiarySystemBackground))
//                        .cornerRadius(8)
//                    }
//                }
//                .frame(maxHeight: 400)
//            }
//            
//            HStack {
//                Button(action: {
//                    beatExtractionStep = .pasteBeatResponse
//                    saveError = nil
//                }) {
//                    Label("Back", systemImage: "arrow.left")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//                
//                Button(action: {
//                    Task {
//                        await saveBeatData()
//                    }
//                }) {
//                    Label("Save & Continue", systemImage: "arrow.right")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//            }
//        }
//    }
//    
//    private var savingBeatStepView: some View {
//        VStack(spacing: 20) {
//            ProgressView()
//                .scaleEffect(1.5)
//            Text("Saving beats to Firebase...")
//                .font(.headline)
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//    }
//    
//    private var allBeatsCompleteView: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Image(systemName: "checkmark.circle.fill")
//                    .font(.title)
//                    .foregroundColor(.green)
//                Text("All Beats Extracted!")
//                    .font(.headline)
//            }
//            
//            VStack(alignment: .leading, spacing: 12) {
//                Text("✅ Processed \(extractedBeats.count) sections")
//                Text("✅ Total beats: \(extractedBeats.reduce(0) { $0 + $1.beats.count })")
//                Text("✅ Anchor lines: \(extractedBeats.reduce(0) { $0 + $1.anchorLines.count })")
//            }
//            .font(.subheadline)
//            .padding()
//            .background(Color(.secondarySystemBackground))
//            .cornerRadius(8)
//            
//            Button(action: {
//                dismiss()
//            }) {
//                Text("Done")
//                    .frame(maxWidth: .infinity)
//            }
//            .buttonStyle(.borderedProminent)
//        }
//    }
//    
//    // MARK: - A1a Helper Methods (keeping existing)
//    
//    private func generatePrompt() {
//        guard let transcript = video.transcript else {
//            generatedPrompt = "⚠️ No transcript available for this video"
//            return
//        }
//        
//        generatedPrompt = """
//You are analyzing a YouTube video transcript to extract its structural spine.
//
//TRANSCRIPT:
//\(transcript)
//
//VIDEO METADATA:
//Title: \(video.title)
//Duration: \(video.duration)
//
//Extract the following:
//
//1. SECTIONS WITH ROLES
//Identify 3-8 major sections. For each section:
//- id: "sect_1", "sect_2", etc.
//- startText: First 8-12 words of the section (EXACT text from transcript)
//- endText: Last 8-12 words of the section (EXACT text from transcript)
//- role: HOOK, SETUP, EVIDENCE, TURN, PAYOFF, CTA, or SPONSORSHIP
//- goal: What this section accomplishes
//- logicSpineStep: One sentence describing this step in the argument
//
//2. LOGIC SPINE
//- chain: Array of strings describing each step
//- causalLinks: Array of connections between sections with "from", "to", "connection"
//
//3. BRIDGE POINTS
//- text: EXACT bridge sentence from transcript
//- belongsTo: Array of section IDs this bridges
//
//OUTPUT FORMAT (strict JSON):
//{
//  "sections": [
//    {
//      "id": "sect_1",
//      "startText": "Exact first 8-12 words from transcript",
//      "endText": "Exact last 8-12 words from transcript",
//      "role": "HOOK",
//      "goal": "Generate curiosity about...",
//      "logicSpineStep": "Claims that X causes Y"
//    }
//  ],
//  "logicSpine": {
//    "chain": [
//      "HOOK claims X→Y",
//      "SETUP introduces Z"
//    ],
//    "causalLinks": [
//      {
//        "from": "sect_1",
//        "to": "sect_2",
//        "connection": "HOOK's question leads to SETUP's context"
//      }
//    ]
//  },
//  "bridgePoints": [
//    {
//      "text": "Exact bridge sentence from transcript",
//      "belongsTo": ["sect_1", "sect_2"]
//    }
//  ]
//}
//
//CRITICAL:
//- DO NOT include "id" in causalLinks or bridgePoints (auto-generated)
//- DO NOT include "timestamp" in bridgePoints (calculated later)
//- DO NOT include "timeRange" in sections (calculated later)
//- Use EXACT text from transcript for startText, endText, and bridge text
//- Return ONLY valid JSON, no markdown formatting
//"""
//    }
//    
//    // MARK: - A1b Helper Methods
//    
//    private func generateBeatPrompt() {
//        guard let alignment = savedAlignment,
//              let transcript = video.transcript else {
//            beatPrompt = "⚠️ Missing data"
//            return
//        }
//        
//        let section = alignment.sections[currentSectionIndex]
//        
//        // Extract section text from transcript
//        let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
//        // For now, we'll include full transcript - ideally would extract section text
//        
//        beatPrompt = """
//You are analyzing a section from a transcript to extract beat sequences.
//
//SECTION DATA:
//ID: \(section.id)
//Role: \(section.role)
//Time Range: \(formatSeconds(section.timeRange.start)) - \(formatSeconds(section.timeRange.end))
//Goal: \(section.goal)
//Logic Spine Step: \(section.logicSpineStep)
//
//FULL TRANSCRIPT:
//\(transcript)
//
//For this \(section.role) section, extract:
//
//1. BEAT SEQUENCE
//Break the section into 2-6 beats. For each beat:
//- type: TEASE, QUESTION, PROMISE, DATA, STORY, AUTHORITY, SYNTHESIS, TURN, CALLBACK, or CTA
//- text: EXACT text from transcript (first few words of the beat)
//- function: What this beat accomplishes (one sentence)
//
//2. TRANSITION TYPE
//How does this section connect to the next?
//Types: callback, direct_pivot, contrarian_flip, question_bridge
//
//3. ANCHOR LINES
//Find 2-6 sentences that are distinctively "this creator" - NOT generic phrases.
//DO NOT include: "let's dive in", "without further ado", "make sure to subscribe"
//
//OUTPUT FORMAT (strict JSON):
//{
//  "sectionId": "\(section.id)",
//  "beats": [
//    {
//      "type": "TEASE",
//      "text": "First 8-12 words of beat from transcript...",
//      "function": "Generate curiosity via unexpected claim"
//    }
//  ],
//  "transitionOut": {
//    "type": "callback",
//    "bridgeSentence": "Exact transition sentence from transcript..."
//  },
//  "anchorLines": [
//    "Exact distinctive sentence from transcript...",
//    "Another distinctive sentence..."
//  ]
//}
//
//BEAT TYPES:
//- TEASE: Create curiosity/tension
//- QUESTION: Rhetorical or genuine question
//- PROMISE: What you'll deliver
//- DATA: Statistics, facts, numbers
//- STORY: Narrative example
//- AUTHORITY: Expert quote, study citation
//- SYNTHESIS: "Here's what this means"
//- TURN: Subvert expectation, reveal
//- CALLBACK: Reference earlier point
//- CTA: Call to action
//
//CRITICAL:
//- Use EXACT text from transcript for beat text and anchor lines
//- DO NOT include generic YouTube phrases as anchors
//- Return ONLY valid JSON, no markdown formatting
//"""
//    }
//    
//    private func processBeatResponse() async {
//        beatExtractionStep = .processingBeat
//        saveError = nil
//        
//        try? await Task.sleep(nanoseconds: 500_000_000)
//        
//        print("\n")
//        print("========================================")
//        print("🎯 PROCESSING BEAT RESPONSE")
//        print("========================================")
//        
//        // Clean JSON
//        var cleanJSON = beatResponse.trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        print("📥 RAW RESPONSE:")
//        print("Length: \(beatResponse.count) characters")
//        print("First 200 chars: \(String(beatResponse.prefix(200)))")
//        
//        if cleanJSON.hasPrefix("```json") {
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
//            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
//            print("✅ Removed markdown fences")
//        }
//        
//        print("\n📋 CLEANED JSON:")
//        print(cleanJSON)
//        print("\n")
//        
//        guard let jsonData = cleanJSON.data(using: .utf8) else {
//            print("❌ Could not convert to UTF-8 data")
//            saveError = "Invalid JSON string"
//            beatExtractionStep = .pasteBeatResponse
//            return
//        }
//        
//        print("✅ Converted to Data: \(jsonData.count) bytes")
//        
//        // Temporary decode structures
//        struct BeatResponse: Codable {
//            let sectionId: String
//            let beats: [BeatItem]
//            let transitionOut: TransitionItem?
//            let anchorLines: [String]
//            
//            struct BeatItem: Codable {
//                let type: String
//                let text: String
//                let function: String
//            }
//            
//            struct TransitionItem: Codable {
//                let type: String
//                let bridgeSentence: String?
//            }
//        }
//        
//        let decoder = JSONDecoder()
//        let beatResponseData: BeatResponse
//        
//        do {
//            beatResponseData = try decoder.decode(BeatResponse.self, from: jsonData)
//            print("✅ JSON DECODED SUCCESSFULLY!")
//            print("Section ID: \(beatResponseData.sectionId)")
//            print("Beats found: \(beatResponseData.beats.count)")
//            print("Anchor lines: \(beatResponseData.anchorLines.count)")
//            
//        } catch let DecodingError.keyNotFound(key, context) {
//            print("❌ KEY NOT FOUND")
//            print("Missing key: \(key)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug: \(context.debugDescription)")
//            saveError = "Missing key: \(key.stringValue)"
//            beatExtractionStep = .pasteBeatResponse
//            return
//        } catch let DecodingError.typeMismatch(type, context) {
//            print("❌ TYPE MISMATCH")
//            print("Expected: \(type)")
//            print("Coding path: \(context.codingPath)")
//            print("Debug: \(context.debugDescription)")
//            saveError = "Type mismatch: expected \(type)"
//            beatExtractionStep = .pasteBeatResponse
//            return
//        } catch {
//            print("❌ DECODING ERROR")
//            print("Error: \(error)")
//            print("Type: \(type(of: error))")
//            saveError = "Decoding failed: \(error.localizedDescription)"
//            beatExtractionStep = .pasteBeatResponse
//            return
//        }
//        
//        // Calculate timestamps
//        guard let transcript = video.transcript else {
//            print("❌ No transcript available")
//            saveError = "No transcript"
//            beatExtractionStep = .pasteBeatResponse
//            return
//        }
//        
//        print("\n⏱️ CALCULATING BEAT TIMESTAMPS...")
//        let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
//        print("Words per second: \(calculator.wordsPerSecond)")
//        
//        var beatsWithTimestamps: [Beat] = []
//        
//        for (index, beatItem) in beatResponseData.beats.enumerated() {
//            print("\nBeat \(index + 1):")
//            print("  Type: \(beatItem.type)")
//            print("  Text: '\(beatItem.text.prefix(40))...'")
//            
//            let startTime = calculator.calculateTimestamp(for: beatItem.text)
//            print("  ✅ Timestamp: \(startTime)s (\(formatSeconds(startTime)))")
//            
//            let beat = Beat(
//                type: beatItem.type,
//                timeRange: TimeRange(start: startTime, end: startTime + 15), // Estimate
//                text: beatItem.text,
//                function: beatItem.function
//            )
//            
//            beatsWithTimestamps.append(beat)
//        }
//        
//        print("\n✅ All beats processed")
//        
//        // Create transition
//        let transition = beatResponseData.transitionOut.map { item in
//            Transition(
//                type: item.type,
//                bridgeSentence: item.bridgeSentence
//            )
//        }
//        
//        // Create BeatData
//        let beatData = BeatData(
//            sectionId: beatResponseData.sectionId,
//            beats: beatsWithTimestamps,
//            transitionOut: transition,
//            anchorLines: beatResponseData.anchorLines
//        )
//        
//        print("\n📦 BEAT DATA CREATED")
//        print("Section ID: \(beatData.sectionId)")
//        print("Beats: \(beatData.beats.count)")
//        print("Transition: \(beatData.transitionOut?.type ?? "none")")
//        print("Anchors: \(beatData.anchorLines.count)")
//        
//        processedBeatData = beatData
//        beatExtractionStep = .reviewBeat
//        
//        print("\n========================================")
//        print("✅ BEAT PROCESSING COMPLETE")
//        print("========================================")
//        print("\n")
//    }
//    
//    private func saveBeatData() async {
//        guard let beatData = processedBeatData else { return }
//        
//        beatExtractionStep = .savingBeat
//        saveError = nil
//        
//        do {
//            // Save to Firebase
//            //try await CreatorAnalysisFirebase.shared.saveBeatDoc(data: beatData, videoId: video.videoId)
//            try await CreatorAnalysisFirebase.shared.saveBeatData(
//                videoId: video.videoId,
//                channelId: video.channelId, // Assuming YouTubeVideo has channelId
//                data: beatData
//            )
//            
//            // Add to extracted beats
//            extractedBeats.append(beatData)
//            
//            // Move to next section or complete
//            if currentSectionIndex < (savedAlignment?.sections.count ?? 0) - 1 {
//                currentSectionIndex += 1
//                beatResponse = ""
//                processedBeatData = nil
//                beatExtractionStep = .showBeatPrompt
//                generateBeatPrompt()
//            } else {
//                beatExtractionStep = .allBeatsComplete
//            }
//            
//        } catch {
//            saveError = "Failed to save: \(error.localizedDescription)"
//            beatExtractionStep = .reviewBeat
//        }
//    }
//    
//    // MARK: - Shared Processing Methods (from original)
//    
//    private func processResponse() async {
//        currentStep = .processing
//        saveError = nil
//        
//        print("\n")
//        print("========================================")
//        print("🔍 STARTING RESPONSE PROCESSING")
//        print("========================================")
//        
//        // Small delay for UI feedback
//        try? await Task.sleep(nanoseconds: 500_000_000)
//        
//        print("\n📥 RAW JSON RESPONSE:")
//        print("Length: \(jsonResponse.count) characters")
//        print("First 200 chars: \(String(jsonResponse.prefix(200)))")
//        
//        // Clean JSON
//        var cleanJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
//        
//        print("🧹 CLEANING JSON...")
//        
//        if cleanJSON.hasPrefix("```json") {
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
//            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
//            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
//            print("✅ Removed markdown fences")
//        }
//        
//        guard let jsonData = cleanJSON.data(using: .utf8) else {
//            print("❌ Could not convert to UTF-8 data")
//            saveError = "Invalid JSON string"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        print("✅ Converted to Data: \(jsonData.count) bytes")
//        
//        // Temporary decode structures
//        struct AlignmentResponse: Codable {
//            struct SectionResponse: Codable {
//                let id: String
//                let startText: String
//                let endText: String
//                let role: String
//                let goal: String
//                let logicSpineStep: String
//            }
//            
//            struct CausalLinkResponse: Codable {
//                let from: String
//                let to: String
//                let connection: String
//            }
//            
//            struct LogicSpineResponse: Codable {
//                let chain: [String]
//                let causalLinks: [CausalLinkResponse]
//            }
//            
//            struct BridgePointResponse: Codable {
//                let text: String
//                let belongsTo: [String]
//            }
//            
//            let sections: [SectionResponse]
//            let logicSpine: LogicSpineResponse
//            let bridgePoints: [BridgePointResponse]
//        }
//        
//        print("\n🔬 ATTEMPTING TO DECODE JSON...")
//        
//        let decoder = JSONDecoder()
//        let response: AlignmentResponse
//        
//        do {
//            response = try decoder.decode(AlignmentResponse.self, from: jsonData)
//            print("✅ JSON DECODED SUCCESSFULLY!")
//            print("Sections found: \(response.sections.count)")
//            
//        } catch let DecodingError.keyNotFound(key, context) {
//            print("❌ KEY NOT FOUND")
//            print("Missing key: \(key)")
//            saveError = "Missing key: \(key.stringValue)"
//            currentStep = .pasteResponse
//            return
//        } catch let DecodingError.typeMismatch(type, context) {
//            print("❌ TYPE MISMATCH")
//            print("Expected: \(type)")
//            saveError = "Type mismatch: expected \(type)"
//            currentStep = .pasteResponse
//            return
//        } catch {
//            print("❌ DECODING ERROR")
//            print("Error: \(error)")
//            saveError = "Decoding failed: \(error.localizedDescription)"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        // Calculate timestamps
//        guard let transcript = video.transcript else {
//            print("❌ No transcript available")
//            saveError = "No transcript"
//            currentStep = .pasteResponse
//            return
//        }
//        
//        print("\n⏱️ CALCULATING TIMESTAMPS...")
//        let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
//        
//        var sectionsWithTimestamps: [SectionData] = []
//        
//        for (index, section) in response.sections.enumerated() {
//            print("\nSection \(index + 1) (\(section.id)):")
//            
//            let startTime = calculator.calculateTimestamp(for: section.startText)
//            let endTime = calculator.calculateTimestamp(for: section.endText)
//            
//            let sectionData = SectionData(
//                id: section.id,
//                timeRange: TimeRange(start: startTime, end: endTime),
//                role: section.role,
//                goal: section.goal,
//                logicSpineStep: section.logicSpineStep
//            )
//            
//            sectionsWithTimestamps.append(sectionData)
//        }
//        
//        // Convert causal links
//        let causalLinks = response.logicSpine.causalLinks.map { link in
//            CausalLink(from: link.from, to: link.to, connection: link.connection)
//        }
//        
//        // Calculate bridge point timestamps
//        var bridgePointsWithTimestamps: [BridgePoint] = []
//        
//        for bridge in response.bridgePoints {
//            let timestamp = calculator.calculateTimestamp(for: bridge.text)
//            
//            let bridgeData = BridgePoint(
//                text: bridge.text,
//                belongsTo: bridge.belongsTo,
//                timestamp: timestamp
//            )
//            
//            bridgePointsWithTimestamps.append(bridgeData)
//        }
//        
//        // Create alignment data
//        let alignmentData = AlignmentData(
//            videoId: video.videoId,
//            channelId: video.channelId,
//            sections: sectionsWithTimestamps,
//            logicSpine: LogicSpineData(
//                chain: response.logicSpine.chain,
//                causalLinks: causalLinks
//            ),
//            bridgePoints: bridgePointsWithTimestamps
//        )
//        
//        // Validate
//        let validator = AlignmentValidator()
//        let validation = validator.validate(alignmentData)
//        
//        var finalData = alignmentData
//        finalData.validationStatus = validation.status
//        finalData.validationIssues = validation.issues.isEmpty ? nil : validation.issues
//        
//        processedAlignment = finalData
//        currentStep = .reviewCalculated
//        
//        print("\n========================================")
//        print("✅ PROCESSING COMPLETE")
//        print("========================================")
//    }
//    
//    private func saveToFirebase() async {
//        guard let alignment = processedAlignment else { return }
//        
//        currentStep = .saving
//        saveError = nil
//        
//        do {
//            try await CreatorAnalysisFirebase.shared.saveAlignmentDoc(data: alignment)
//            savedAlignment = alignment
//            currentStep = .complete
//        } catch {
//            saveError = "Failed to save: \(error.localizedDescription)"
//            currentStep = .reviewCalculated
//        }
//    }
//    
//    // MARK: - Helper Methods
//    
//    private func formatSeconds(_ seconds: Int) -> String {
//        let minutes = seconds / 60
//        let secs = seconds % 60
//        return String(format: "%d:%02d", minutes, secs)
//    }
//    
//    private func roleColor(_ role: String) -> Color {
//        switch role {
//        case "HOOK": return .blue
//        case "SETUP": return .green
//        case "EVIDENCE": return .purple
//        case "TURN": return .orange
//        case "PAYOFF": return .pink
//        case "CTA": return .red
//        case "SPONSORSHIP": return .gray
//        default: return .secondary
//        }
//    }
//    
//    private func beatTypeColor(_ type: String) -> Color {
//        switch type {
//        case "TEASE": return .purple
//        case "QUESTION": return .blue
//        case "PROMISE": return .green
//        case "DATA": return .orange
//        case "STORY": return .pink
//        case "AUTHORITY": return .red
//        case "SYNTHESIS": return .cyan
//        case "TURN": return .indigo
//        case "CALLBACK": return .yellow
//        case "CTA": return .brown
//        default: return .gray
//        }
//    }
//}
