//
//  AnalysisStatusView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/21/26.
//
import SwiftUI

struct AnalysisStatusView: View {
    let video: YouTubeVideo
    let status: AnalysisStatus
    let onResume: () -> Void
    let onReprocess: (ReprocessTarget) -> Void
    let onStartFresh: () -> Void

    // In AnalysisStatusView, add:
    let onRunMissingInSection: (SectionAnalysisStatus) -> Void
    let onRunAllMissing: () -> Void
    let onSaveA1aResult: (AlignmentData) -> Void  // Save fidelity result

    // Track which sections are expanded to show raw beat text
    @State private var expandedSections: Set<String> = []

    // MARK: - A1a Fidelity Testing State
    @State private var showFidelitySection = false
    @State private var fidelityRunCount: Int = 10
    @State private var fidelityTemperature: Double = 0.7
    @State private var isRunningFidelity = false
    @State private var fidelityCurrentRun = 0
    @State private var fidelityResults: [A1aFidelityRunResult] = []
    @State private var fidelityError: String?
    @State private var firstSuccessfulAlignment: AlignmentData?  // For saving
    @State private var isSavingResult = false

    // MARK: - A1b Fidelity Testing State (per section)
    @State private var a1bFidelitySection: SectionAnalysisStatus?  // Which section is being tested
    @State private var a1bFidelityRunCount: Int = 10
    @State private var a1bFidelityTemperature: Double = 0.7
    @State private var isRunningA1bFidelity = false
    @State private var a1bFidelityCurrentRun = 0
    @State private var a1bFidelityResults: [A1bFidelityRunResult] = []
    @State private var a1bFidelityError: String?

    // MARK: - Fidelity History State
    @State private var showFidelityHistory = false
    @State private var historicalTests: [StoredFidelityTestRun] = []
    @State private var showCrossVideoComparison = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Analysis Status")
                    .font(.title)
                HStack {
                    Text(video.title)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let transcript = video.transcript, !transcript.isEmpty {
                        CopyButton(label: "Transcript", valueToCopy: transcript, font: .caption)
                            .foregroundColor(.green)
                    }
                    
                    // In the action buttons section, add:
                    Button {
                        copyAllBeatsForVideo()
                    } label: {
                        Label("Copy All Beats (Debug)", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                }
                
                Divider()
                
                // A1a Status
                HStack {
                    Image(systemName: status.a1aComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(status.a1aComplete ? .green : .gray)
                    Text("A1a: Structure Analysis")
                    Spacer()

                    // Always show fidelity test button (only needs transcript)
                    if video.transcript != nil && !video.transcript!.isEmpty {
                        Button("Test Fidelity") {
                            showFidelitySection.toggle()
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                    }

                    if status.a1aComplete {
                        Button("Reprocess") {
                            onReprocess(.a1a)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Fidelity Testing Section - always available with transcript
                if showFidelitySection && video.transcript != nil && !video.transcript!.isEmpty {
                    fidelityTestingSection
                }
                
                // Sections Status - only show if we have sections
                if !status.sectionStatuses.isEmpty {
                    ForEach(status.sectionStatuses, id: \.section.id) { sectionStatus in
                        sectionStatusView(sectionStatus)
                    }
                } else {
                    // No analysis exists yet
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No analysis exists for this video yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Use the fidelity test above to validate prompts, or run a full analysis below")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                Divider()

                // Action Buttons
                VStack(spacing: 12) {
                    // Show "Run Analysis" buttons when no alignment exists
                    if !status.a1aComplete {
                        Button {
                            onStartFresh()  // This triggers A1a analysis
                        } label: {
                            Label("Run A1a Analysis", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }

                    if status.hasIncompleteWork {
                        Button {
                            onResume()
                        } label: {
                            Label("Resume from \(status.nextIncompleteStep)", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    if status.totalMissingBeats > 0 {
                        Button {
                            onRunAllMissing()
                        } label: {
                            Label("Fix All Missing Beats (\(status.totalMissingBeats))", systemImage: "wrench.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    // Only show delete button if there's something to delete
                    if status.a1aComplete {
                        Button {
                            onStartFresh()
                        } label: {
                            Label("Start Fresh (Delete All)", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Analysis Status")
        .sheet(item: $a1bFidelitySection) { sectionStatus in
            A1bFidelityTestSheet(
                video: video,
                sectionStatus: sectionStatus,
                allSections: status.sectionStatuses.map { $0.section },
                runCount: $a1bFidelityRunCount,
                temperature: $a1bFidelityTemperature,
                isRunning: $isRunningA1bFidelity,
                currentRun: $a1bFidelityCurrentRun,
                results: $a1bFidelityResults,
                error: $a1bFidelityError
            )
        }
    }
    private func sectionStatusView(_ sectionStatus: SectionAnalysisStatus) -> some View {
        let isExpanded = expandedSections.contains(sectionStatus.section.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: sectionStatus.isComplete ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                    .foregroundColor(sectionStatus.isComplete ? .green : .orange)
                Text("Section \(sectionStatus.sectionIndex + 1): \(sectionStatus.section.role)")
                Spacer()

                // Expand/collapse button for raw text
                if sectionStatus.a1bComplete && !sectionStatus.beatDocs.isEmpty {
                    Button {
                        withAnimation {
                            if isExpanded {
                                expandedSections.remove(sectionStatus.section.id)
                            } else {
                                expandedSections.insert(sectionStatus.section.id)
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                // Copy all beats button
                Button {
                    copyBeatsToClipboard(sectionStatus.beatDocs)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                if !sectionStatus.incompleteBeatIndices.isEmpty {
                    Button("Fix \(sectionStatus.incompleteBeatIndices.count) Missing") {
                        onRunMissingInSection(sectionStatus)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .font(.caption)
                }

                // A1b Fidelity Test button
                Button {
                    a1bFidelitySection = sectionStatus
                } label: {
                    Image(systemName: "testtube.2")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.purple)

                if sectionStatus.a1bComplete || sectionStatus.isComplete {
                    Button("Reprocess") {
                        print("disabled")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            // Beat details - show what's actually in each beat
            if sectionStatus.a1bComplete {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(sectionStatus.beatDocs.enumerated()), id: \.offset) { index, beat in
                        HStack(spacing: 4) {
                            // Index
                            Text("\(index + 1)")
                                .font(.caption2)
                                .frame(width: 16)

                            // Type
                            Text(beat.type)
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .frame(width: 60, alignment: .leading)

                            // Key fields to show what's populated
                            if !beat.moveKey.isEmpty && beat.moveKey != "UNKNOWN" {
                                Text("moveKey")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(Color.green.opacity(0.3))
                                    .cornerRadius(2)
                            }

                            if !beat.compilerFunction.isEmpty {
                                Text("compiler")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(Color.green.opacity(0.3))
                                    .cornerRadius(2)
                            }

                            if beat.stance != "neutral" && !beat.stance.isEmpty {
                                Text(beat.stance)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(Color.purple.opacity(0.3))
                                    .cornerRadius(2)
                            }

                            if beat.tempo != "medium" && !beat.tempo.isEmpty {
                                Text(beat.tempo)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(Color.orange.opacity(0.3))
                                    .cornerRadius(2)
                            }

                            Spacer()

                            // Word count
                            Text("\(beat.wordCount)w")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                // Expanded raw text view
                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Raw Beat Text")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        ForEach(Array(sectionStatus.beatDocs.enumerated()), id: \.offset) { index, beat in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Beat \(index + 1)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(beat.type)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Spacer()
                                    Text("[\(beat.startWordIndex)-\(beat.endWordIndex)]")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Text(beat.text)
                                    .font(.caption)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.tertiarySystemBackground))
                                    .cornerRadius(6)
                                    .textSelection(.enabled)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func copyAllBeatsForVideo() {
        var output = "=== ALL BEATS FOR \(video.title) ===\n\n"
        for sectionStatus in status.sectionStatuses {
            output += "--- Section \(sectionStatus.sectionIndex + 1): \(sectionStatus.section.role) ---\n"
            output += "beatDocs.count: \(sectionStatus.beatDocs.count)\n\n"
            for (index, beat) in sectionStatus.beatDocs.enumerated() {
                output += """
                Beat \(index + 1):
                  beatId: \(beat.beatId)
                beatText: \(beat.text)
                  type: \(beat.type)
                  moveKey: \(beat.moveKey)
                  compilerFunction: \(beat.compilerFunction)
                  stance: \(beat.stance)
                  tempo: \(beat.tempo)
                  styleFormality: \(beat.styleFormality)
                  wordCount: \(beat.wordCount)
                  startWordIndex: \(beat.startWordIndex)
                  endWordIndex: \(beat.endWordIndex)
                
                """
            }
        }
        UIPasteboard.general.string = output
        print("📋 Copied all beats to clipboard")
    }

    private func copyBeatsToClipboard(_ beats: [BeatDoc]) {
        var output = ""
        for (index, beat) in beats.enumerated() {
            output += """
            === Beat \(index + 1) ===
            beatId: \(beat.beatId)
            type: \(beat.type)
            moveKey: \(beat.moveKey)
            compilerFunction: \(beat.compilerFunction)
            stance: \(beat.stance)
            tempo: \(beat.tempo)
            formality: \(beat.styleFormality)
            wordCount: \(beat.wordCount)
            text: \(String(beat.text))...
            
            """
        }
        UIPasteboard.general.string = output
        print("📋 Copied \(beats.count) beats to clipboard")
    }
    // MARK: - Fidelity Testing Section

    private var fidelityTestingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("A1a Fidelity Test")
                    .font(.headline)
                Spacer()

                // History toggle
                Button {
                    showFidelityHistory.toggle()
                    if showFidelityHistory {
                        loadFidelityHistory()
                    }
                } label: {
                    Label(showFidelityHistory ? "Hide History" : "Show History",
                          systemImage: showFidelityHistory ? "clock.fill" : "clock")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                // Cross-video comparison
                Button {
                    showCrossVideoComparison = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    showFidelitySection = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            Text("Run A1a multiple times to see boundary variance")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Stepper("Runs: \(fidelityRunCount)", value: $fidelityRunCount, in: 5...100, step: 5)
                    .frame(width: 180)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Temp: \(String(format: "%.1f", fidelityTemperature))")
                        .font(.caption)
                    Slider(value: $fidelityTemperature, in: 0...1, step: 0.1)
                        .frame(width: 100)
                }

                Spacer()

                if isRunningFidelity {
                    HStack {
                        ProgressView()
                        Text("Run \(fidelityCurrentRun)/\(fidelityRunCount)")
                            .font(.caption)
                    }
                } else {
                    Button("Run \(fidelityRunCount) Tests") {
                        Task { await runFidelityTests() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }

            if let error = fidelityError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Historical tests for this video
            if showFidelityHistory && !historicalTests.isEmpty {
                fidelityHistoryView
            }

            // Current results
            if !fidelityResults.isEmpty {
                fidelityResultsView
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
        .onAppear {
            loadFidelityHistory()
        }
        .sheet(isPresented: $showCrossVideoComparison) {
            FidelityCrossVideoComparisonView()
        }
    }

    private var fidelityHistoryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Previous Tests (\(historicalTests.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Clear All") {
                    FidelityTestManager.shared.deleteAllForVideo(videoId: video.videoId)
                    loadFidelityHistory()
                }
                .font(.caption)
                .foregroundColor(.red)
            }

            ForEach(historicalTests) { test in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(test.testDate, style: .date)
                            .font(.caption2)
                        Text(test.testDate, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80, alignment: .leading)

                    Text("\(test.successfulRuns)/\(test.runCount) runs")
                        .font(.caption)
                        .frame(width: 60)

                    Text("T: \(String(format: "%.1f", test.temperature))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40)

                    Spacer()

                    // Stability indicator
                    if test.varianceCount == 0 {
                        Text("100% stable")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("\(test.varianceCount) variance")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    // Quick view of which roles had issues
                    HStack(spacing: 2) {
                        ForEach(test.results) { result in
                            Circle()
                                .fill(result.isStable ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Button {
                        FidelityTestManager.shared.deleteRun(id: test.id)
                        loadFidelityHistory()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    private func loadFidelityHistory() {
        historicalTests = FidelityTestManager.shared.loadForVideo(videoId: video.videoId)
            .filter { $0.promptType == .a1a }
    }

    private var fidelityResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Boundary Distribution (\(fidelityResults.count) runs)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    copyFidelityResults()
                } label: {
                    Label("Copy Results", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            ForEach(getAllRolesFromResults(), id: \.self) { role in
                RoleBoundaryDistributionView(
                    role: role,
                    fidelityResults: fidelityResults,
                    transcript: video.transcript ?? ""
                )
            }

            // Show save button if no existing analysis and we have a result
            if !status.a1aComplete, let alignment = firstSuccessfulAlignment {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save First Result?")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("\(alignment.sections.count) sections detected")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isSavingResult {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button {
                            Task { await saveFirstResult(alignment) }
                        } label: {
                            Label("Save to Database", systemImage: "square.and.arrow.down")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func saveFirstResult(_ alignment: AlignmentData) async {
        await MainActor.run { isSavingResult = true }

        // Call the save callback
        onSaveA1aResult(alignment)

        await MainActor.run {
            isSavingResult = false
            firstSuccessfulAlignment = nil  // Clear after save
        }
    }

    private func copyFidelityResults() {
        let sentences = SentenceParser.parse(video.transcript ?? "")
        let engine = SectionPromptEngine(video: video)
        let prompt = engine.generatePrompt()

        var output = """
        === A1a FIDELITY TEST RESULTS ===
        Video: \(video.title)
        VideoId: \(video.videoId)
        Total Runs: \(fidelityResults.count)
        Temperature: \(String(format: "%.1f", fidelityTemperature))
        Total Sentences in Transcript: \(sentences.count)

        ════════════════════════════════════════
        SECTION BOUNDARY VARIANCE ANALYSIS
        ════════════════════════════════════════

        """

        // Get all roles
        let allRoles = getAllRolesFromResults()

        for role in allRoles {
            let boundaries = fidelityResults.compactMap { run in
                run.sections.first(where: { $0.role == role })?.boundarySentence
            }

            // Count occurrences
            var counts: [Int: Int] = [:]
            for boundary in boundaries {
                counts[boundary, default: 0] += 1
            }

            let sortedBoundaries = counts.sorted { $0.key < $1.key }
            let hasVariance = counts.count > 1

            output += "--- \(role) "
            if hasVariance {
                output += "⚠️ VARIANCE ---\n\n"
            } else {
                output += "✓ STABLE ---\n\n"
            }

            // Show each boundary option with its sentence text
            for (boundary, count) in sortedBoundaries {
                let percentage = Int(Double(count) / Double(fidelityResults.count) * 100)
                output += "  [\(boundary)] → \(count)x (\(percentage)%)\n"

                // Show the actual sentence text
                if boundary > 0 && boundary <= sentences.count {
                    let sentenceText = sentences[boundary - 1]
                    output += "     \"\(sentenceText)\"\n"
                }
                output += "\n"
            }
        }

        // Add raw run data
        output += """

        ════════════════════════════════════════
        RAW RUN DATA
        ════════════════════════════════════════

        """

        for run in fidelityResults {
            output += "Run \(run.runNumber): "
            output += run.sections.map { "\($0.role)→[\($0.boundarySentence ?? -1)]" }.joined(separator: ", ")
            output += "\n"
        }

        // Add prompt at the end (it's long, so keep diagnostic info first)
        output += """

        ════════════════════════════════════════
        PROMPT USED (for reference)
        ════════════════════════════════════════

        \(prompt)
        """

        UIPasteboard.general.string = output
        print("📋 Copied fidelity results to clipboard")
    }

    private func getAllRolesFromResults() -> [String] {
        guard let firstRun = fidelityResults.first else { return [] }
        return firstRun.sections.map { $0.role }
    }

    private func runFidelityTests() async {
        guard let transcript = video.transcript, !transcript.isEmpty else {
            fidelityError = "No transcript available"
            return
        }

        await MainActor.run {
            isRunningFidelity = true
            fidelityCurrentRun = 0
            fidelityResults = []
            fidelityError = nil
            firstSuccessfulAlignment = nil
        }

        // Generate prompt ONCE before parallel execution
        let engine = SectionPromptEngine(video: video)
        let prompt = engine.generatePrompt()

        // Debug: Verify prompt was generated correctly
        print("🔬 A1a FIDELITY: Generated prompt length: \(prompt.count) characters")
        if prompt.contains("FULL TRANSCRIPT") || prompt.contains("Transcript") {
            print("✅ A1a FIDELITY: Prompt contains transcript marker")
        } else {
            print("❌ A1a FIDELITY: Prompt MISSING transcript!")
        }

        // Capture values for parallel execution
        let totalRuns = fidelityRunCount
        let temp = fidelityTemperature
        let maxConcurrent = 3
        var allResults: [(A1aFidelityRunResult, AlignmentData?)] = []
        var completedCount = 0

        // Process in batches for parallel execution
        for batchStart in stride(from: 1, through: totalRuns, by: maxConcurrent) {
            let batchEnd = min(batchStart + maxConcurrent - 1, totalRuns)

            let batchResults = await withTaskGroup(of: (Int, A1aFidelityRunResult?, AlignmentData?).self) { group in
                for i in batchStart...batchEnd {
                    group.addTask {
                        do {
                            // Stagger within batch (500ms between starts)
                            let staggerDelay = UInt64((i - batchStart) * 500_000_000)
                            try? await Task.sleep(nanoseconds: staggerDelay)

                            let stepId = UUID()
                            let promptStep = PromptStep(
                                id: stepId,
                                title: "A1a Fidelity Test",
                                prompt: prompt,  // Use pre-generated prompt
                                notes: "",
                                flowStrategy: .promptChaining,
                                isBatchEligible: false,
                                aiModel: .claude4Sonnet,
                                useCashe: false,
                                temperature: temp
                            )

                            // Debug: Verify promptStep has the prompt
                            print("🔬 A1a Run \(i): promptStep.prompt length: \(promptStep.prompt.count)")

                            let agentId = UUID()
                            let tempAgent = Agent(
                                id: agentId,
                                name: "Fidelity Test",
                                promptSteps: [promptStep],
                                chatSessions: []
                            )

                            let tempSession = ChatSession(
                                id: UUID(),
                                agentId: agentId,
                                title: "Fidelity Run \(i)",
                                createdAt: Date()
                            )

                            let executionEngine = AgentExecutionEngine(agent: tempAgent, session: tempSession)

                            let run = try await executionEngine.runStep(
                                step: promptStep,
                                userInput: "Analyze the video structure now and return JSON.",
                                sharedInput: nil,
                                purpose: .normal,
                                inputID: nil
                            )

                            // Debug: Check response format
                            print("🔬 A1a Run \(i) response preview: \(String(run.response.prefix(100)))")

                            // Early check for non-JSON response (allow preamble + JSON or markdown-wrapped JSON)
                            let trimmed = run.response.trimmingCharacters(in: .whitespacesAndNewlines)
                            let containsJSON = trimmed.contains("{") && trimmed.contains("}")
                            if !containsJSON {
                                print("⚠️ A1a Run \(i): Response contains no JSON!")
                                print("⚠️ A1a Run \(i): First 300 chars: \(String(trimmed.prefix(300)))")
                                return (i, nil, nil)
                            }

                            // parseResponse now handles extracting JSON from preamble/markdown
                            let parsed = try engine.parseResponse(run.response)

                            let sections = parsed.sections.map { section in
                                A1aFidelitySectionResult(
                                    role: section.role,
                                    boundarySentence: section.boundarySentence
                                )
                            }

                            // Also compute full AlignmentData for potential saving
                            let alignmentData = engine.calculateTimestamps(response: parsed)

                            return (i, A1aFidelityRunResult(runNumber: i, sections: sections), alignmentData)

                        } catch {
                            print("❌ A1a Run \(i) error: \(error)")
                            return (i, nil, nil)
                        }
                    }
                }

                var batchCollected: [(Int, A1aFidelityRunResult?, AlignmentData?)] = []
                for await result in group {
                    batchCollected.append(result)
                    completedCount += 1
                    await MainActor.run {
                        fidelityCurrentRun = completedCount
                    }
                }
                return batchCollected
            }

            // Collect results with alignment data
            for (_, fidelityResult, alignment) in batchResults {
                if let fidelityResult = fidelityResult {
                    allResults.append((fidelityResult, alignment))
                }
            }

            // 1 second delay between batches
            if batchEnd < totalRuns {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        let sortedResults = allResults.sorted { $0.0.runNumber < $1.0.runNumber }
        let fidelityOnlyResults = sortedResults.map { $0.0 }

        // Get the first successful alignment for potential saving
        let firstAlignment = sortedResults.first?.1

        // Save to history automatically
        if !fidelityOnlyResults.isEmpty {
            let testRun = FidelityTestManager.shared.createA1aTestRun(
                video: video,
                results: fidelityOnlyResults,
                runCount: totalRuns,
                temperature: temp
            )
            FidelityTestManager.shared.save(run: testRun)
        }

        await MainActor.run {
            fidelityResults = fidelityOnlyResults
            firstSuccessfulAlignment = firstAlignment
            isRunningFidelity = false
            if fidelityOnlyResults.count < totalRuns {
                fidelityError = "Only \(fidelityOnlyResults.count)/\(totalRuns) runs succeeded"
            }
            // Refresh history
            loadFidelityHistory()
        }
    }

    private func sectionStatusViewOld(_ sectionStatus: SectionAnalysisStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: sectionStatus.isComplete ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                    .foregroundColor(sectionStatus.isComplete ? .green : .orange)
                Text("Section \(sectionStatus.sectionIndex + 1): \(sectionStatus.section.role)")
                Spacer()
                if !sectionStatus.incompleteBeatIndices.isEmpty {
                               Button("Fix \(sectionStatus.incompleteBeatIndices.count) Missing") {
                                   onRunMissingInSection(sectionStatus)
                               }
                               .buttonStyle(.bordered)
                               .tint(.orange)
                               .font(.caption)
                           }
                           
                           if sectionStatus.a1bComplete || sectionStatus.isComplete {
                               Button("Reprocess") {
                                   print("disabled ")
                                   //onReprocess(.section(sectionStatus.section.id))
                               }
                               .buttonStyle(.bordered)
                               .font(.caption)
                           }
            }
            
            // Beat progress
            if sectionStatus.a1bComplete {
                HStack(spacing: 4) {
                    Text("Beats:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(0..<sectionStatus.totalBeats, id: \.self) { index in
                        Circle()
                            .fill(index < sectionStatus.beatDocs.count && sectionStatus.beatDocs[index].enrichmentLevel == "a1c" ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                    }
                    Text("\(sectionStatus.completedBeats)/\(sectionStatus.totalBeats)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

//enum ReprocessTarget {
//    case a1a
//    case section(String)
//    case beat(String)
//}



struct SectionStatus {
    let sectionId: String
    let sectionIndex: Int
    let sectionRole: String
    let a1bComplete: Bool
    let beatDocs: [BeatDocStatus]
    
    var totalBeats: Int { beatDocs.count }
    var completedBeats: Int { beatDocs.filter { $0.enrichmentLevel == "a1c" }.count }
    var isComplete: Bool { a1bComplete && completedBeats == totalBeats }
}

struct BeatDocStatus {
    let beatId: String
    let type: String
    let enrichmentLevel: String  // "a1b" or "a1c"
}

// MARK: - Fidelity Testing Models

struct A1aFidelityRunResult: Identifiable {
    let id = UUID()
    let runNumber: Int
    let sections: [A1aFidelitySectionResult]
}

struct A1aFidelitySectionResult {
    let role: String
    let boundarySentence: Int?
}

// MARK: - Role Boundary Distribution View

struct RoleBoundaryDistributionView: View {
    let role: String
    let fidelityResults: [A1aFidelityRunResult]
    let transcript: String

    private var boundaries: [Int] {
        fidelityResults.compactMap { run in
            run.sections.first(where: { $0.role == role })?.boundarySentence
        }
    }

    private var counts: [Int: Int] {
        var result: [Int: Int] = [:]
        for boundary in boundaries {
            result[boundary, default: 0] += 1
        }
        return result
    }

    private var sortedBoundaries: [(key: Int, value: Int)] {
        counts.sorted { $0.key < $1.key }
    }

    private var maxCount: Int {
        counts.values.max() ?? 1
    }

    private var sentences: [String] {
        SentenceParser.parse(transcript)
    }

    private var hasVariance: Bool {
        counts.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(role)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(roleColor(role))
                    .frame(width: 80, alignment: .leading)

                // Show distribution bars
                HStack(spacing: 2) {
                    ForEach(sortedBoundaries, id: \.key) { item in
                        VStack(spacing: 2) {
                            Text("[\(item.key)]")
                                .font(.system(size: 8))
                            Rectangle()
                                .fill(roleColor(role))
                                .frame(width: 20, height: CGFloat(item.value) / CGFloat(maxCount) * 30)
                            Text("\(Int(Double(item.value) / Double(fidelityResults.count) * 100))%")
                                .font(.system(size: 8))
                        }
                    }
                }

                Spacer()

                // Variance indicator
                if hasVariance {
                    Text("⚠️ variance")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Text("✓ stable")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            // Show actual sentence text for boundaries with variance
            if hasVariance {
                ForEach(sortedBoundaries, id: \.key) { item in
                    if item.key > 0 && item.key <= sentences.count {
                        HStack(alignment: .top) {
                            Text("[\(item.key)]")
                                .font(.caption2)
                                .frame(width: 30)
                            Text(sentences[item.key - 1])
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "HOOK": return .blue
        case "SETUP": return .green
        case "EVIDENCE": return .purple
        case "TURN": return .orange
        case "PAYOFF": return .pink
        case "CTA": return .red
        case "SPONSORSHIP": return .gray
        default: return .secondary
        }
    }
}

// MARK: - A1b Fidelity Test Sheet

struct A1bFidelityTestSheet: View {
    let video: YouTubeVideo
    let sectionStatus: SectionAnalysisStatus
    let allSections: [SectionData]

    @Binding var runCount: Int
    @Binding var temperature: Double
    @Binding var isRunning: Bool
    @Binding var currentRun: Int
    @Binding var results: [A1bFidelityRunResult]
    @Binding var error: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Section info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Testing: \(sectionStatus.section.role)")
                        .font(.headline)
                    Text("Section \(sectionStatus.sectionIndex + 1)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

                // Controls
                HStack {
                    Stepper("Runs: \(runCount)", value: $runCount, in: 5...50, step: 5)
                        .frame(width: 180)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Temp: \(String(format: "%.1f", temperature))")
                            .font(.caption)
                        Slider(value: $temperature, in: 0...1, step: 0.1)
                            .frame(width: 100)
                    }

                    Spacer()

                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("Run \(currentRun)/\(runCount)")
                                .font(.caption)
                        }
                    } else {
                        Button("Run \(runCount) Tests") {
                            Task { await runA1bFidelityTests() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
                .padding(.horizontal)

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                // Results
                if !results.isEmpty {
                    a1bResultsView
                }

                Spacer()
            }
            .padding()
            .navigationTitle("A1b Fidelity Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !results.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Copy Results") { copyA1bResults() }
                    }
                }
            }
        }
    }

    private var a1bResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Beat Distribution (\(results.count) runs)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                // Beat count variance
                beatCountDistribution

                Divider()

                // Beat boundary variance
                beatBoundaryDistribution
            }
            .padding()
        }
    }

    private var beatCountDistribution: some View {
        let counts = results.map { $0.beatCount }
        var countFreq: [Int: Int] = [:]
        for c in counts {
            countFreq[c, default: 0] += 1
        }
        let sorted = countFreq.sorted { $0.key < $1.key }
        let hasVariance = countFreq.count > 1

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Beat Count")
                    .font(.caption)
                    .fontWeight(.bold)
                Spacer()
                if hasVariance {
                    Text("⚠️ variance")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Text("✓ stable")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            HStack(spacing: 8) {
                ForEach(sorted, id: \.key) { count, freq in
                    VStack {
                        Text("\(count) beats")
                            .font(.caption2)
                        Text("\(Int(Double(freq) / Double(results.count) * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)
                }
            }
        }
    }

    private var beatBoundaryDistribution: some View {
        // Find max beat count across all runs
        let maxBeats = results.map { $0.beatCount }.max() ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            Text("Beat Boundaries (by position)")
                .font(.caption)
                .fontWeight(.bold)

            ForEach(0..<maxBeats, id: \.self) { beatIndex in
                beatPositionDistribution(beatIndex: beatIndex)
            }
        }
    }

    private func beatPositionDistribution(beatIndex: Int) -> some View {
        // Get end sentence for this beat position across all runs
        let boundaries = results.compactMap { run -> Int? in
            guard beatIndex < run.beats.count else { return nil }
            return run.beats[beatIndex].boundarySentence
        }

        var freq: [Int: Int] = [:]
        for b in boundaries {
            freq[b, default: 0] += 1
        }
        let sorted = freq.sorted { $0.key < $1.key }
        let hasVariance = freq.count > 1
        let runsWithThisBeat = boundaries.count

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Beat \(beatIndex + 1)")
                    .font(.caption2)
                    .frame(width: 50, alignment: .leading)

                if runsWithThisBeat < results.count {
                    Text("(\(runsWithThisBeat)/\(results.count) runs)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hasVariance {
                    Text("⚠️")
                        .font(.caption2)
                } else if runsWithThisBeat == results.count {
                    Text("✓")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            HStack(spacing: 4) {
                ForEach(sorted, id: \.key) { sentence, count in
                    Text("[\(sentence)]: \(Int(Double(count) / Double(runsWithThisBeat) * 100))%")
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(hasVariance ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                        .cornerRadius(2)
                }
            }
        }
    }

    private func runA1bFidelityTests() async {
        guard let transcript = video.transcript, !transcript.isEmpty else {
            error = "No transcript available"
            return
        }

        await MainActor.run {
            isRunning = true
            currentRun = 0
            results = []
            error = nil
        }

        let sectionIndex = sectionStatus.sectionIndex

        // Generate prompt ONCE before any parallel execution (matching working A1a pattern)
        let engine = BeatPromptEngine(video: video, sections: allSections, currentIndex: sectionIndex)
        let prompt = engine.generatePrompt()

        // Debug: Verify prompt was generated correctly
        print("🔬 A1b FIDELITY: Generated prompt length: \(prompt.count) characters")
        if prompt.contains("SECTION TRANSCRIPT") {
            print("✅ A1b FIDELITY: Prompt contains SECTION TRANSCRIPT marker")
        } else {
            print("❌ A1b FIDELITY: Prompt MISSING SECTION TRANSCRIPT!")
        }

        // Capture values for parallel execution
        let totalRuns = runCount
        let temp = temperature
        let maxConcurrent = 3
        var allResults: [A1bFidelityRunResult] = []
        var completedCount = 0

        // Process in batches for parallel execution
        for batchStart in stride(from: 1, through: totalRuns, by: maxConcurrent) {
            let batchEnd = min(batchStart + maxConcurrent - 1, totalRuns)

            let batchResults = await withTaskGroup(of: (Int, A1bFidelityRunResult?).self) { group in
                for i in batchStart...batchEnd {
                    group.addTask {
                        do {
                            // Stagger within batch to avoid rate limits (500ms between starts)
                            let staggerDelay = UInt64((i - batchStart) * 500_000_000)
                            try? await Task.sleep(nanoseconds: staggerDelay)

                            let stepId = UUID()
                            let promptStep = PromptStep(
                                id: stepId,
                                title: "A1b Fidelity Test",
                                prompt: prompt,  // Use pre-generated prompt
                                notes: "",
                                flowStrategy: .promptChaining,
                                isBatchEligible: false,
                                aiModel: .claude4Sonnet,
                                useCashe: false,
                                temperature: temp
                            )

                            // Debug: Verify promptStep has the prompt
                            print("🔬 Run \(i): promptStep.prompt length: \(promptStep.prompt.count)")

                            let agentId = UUID()
                            let tempAgent = Agent(
                                id: agentId,
                                name: "A1b Fidelity Test",
                                promptSteps: [promptStep],
                                chatSessions: []
                            )

                            let tempSession = ChatSession(
                                id: UUID(),
                                agentId: agentId,
                                title: "A1b Fidelity Run \(i)",
                                createdAt: Date()
                            )

                            let executionEngine = AgentExecutionEngine(agent: tempAgent, session: tempSession)

                            let run = try await executionEngine.runStep(
                                step: promptStep,
                                userInput: "Analyze the section now and return JSON.",
                                sharedInput: nil,
                                purpose: .normal,
                                inputID: nil
                            )

                            // Debug: Check response format
                            print("🔬 Run \(i) response preview: \(String(run.response.prefix(100)))")

                            // Early check for non-JSON response (allow preamble + JSON or markdown-wrapped JSON)
                            let trimmed = run.response.trimmingCharacters(in: .whitespacesAndNewlines)
                            let containsJSON = trimmed.contains("{") && trimmed.contains("}")
                            if !containsJSON {
                                print("⚠️ Run \(i): Response contains no JSON!")
                                print("⚠️ Run \(i): First 300 chars: \(String(trimmed.prefix(300)))")
                                return (i, nil)
                            }

                            // parseResponse now handles extracting JSON from preamble/markdown
                            let parsed = try engine.parseResponse(run.response)

                            let beatResults = parsed.beats.enumerated().map { index, beat in
                                A1bFidelityBeatResult(
                                    beatIndex: index,
                                    type: beat.type,
                                    boundarySentence: beat.boundarySentence
                                )
                            }

                            return (i, A1bFidelityRunResult(
                                runNumber: i,
                                beatCount: parsed.beats.count,
                                beats: beatResults
                            ))

                        } catch {
                            print("❌ A1b Run \(i) error: \(error)")
                            return (i, nil)
                        }
                    }
                }

                var batchCollected: [(Int, A1bFidelityRunResult?)] = []
                for await result in group {
                    batchCollected.append(result)
                    completedCount += 1
                    await MainActor.run {
                        currentRun = completedCount
                    }
                }
                return batchCollected
            }

            allResults.append(contentsOf: batchResults.compactMap { $0.1 })

            // 1 second delay between batches
            if batchEnd < totalRuns {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        let sortedResults = allResults.sorted { $0.runNumber < $1.runNumber }

        // Save to history automatically
        if !sortedResults.isEmpty {
            let testRun = FidelityTestManager.shared.createA1bTestRun(
                video: video,
                sectionId: sectionStatus.section.id,
                sectionRole: sectionStatus.section.role,
                results: sortedResults,
                runCount: totalRuns,
                temperature: temp
            )
            FidelityTestManager.shared.save(run: testRun)
        }

        await MainActor.run {
            results = sortedResults
            isRunning = false
            if sortedResults.count < totalRuns {
                error = "Only \(sortedResults.count)/\(totalRuns) runs succeeded"
            }
        }
    }

    private func copyA1bResults() {
        let sectionIndex = sectionStatus.sectionIndex
        let engine = BeatPromptEngine(video: video, sections: allSections, currentIndex: sectionIndex)
        let prompt = engine.generatePrompt()
        let section = sectionStatus.section

        // Get section sentences (same logic as BeatPromptEngine)
        let allSentences = SentenceParser.parse(video.transcript ?? "")
        let sectionSentences: [String]
        if let startSentence = section.startSentenceIndex,
           let endSentence = section.endSentenceIndex,
           startSentence >= 0 && endSentence < allSentences.count && startSentence <= endSentence {
            sectionSentences = Array(allSentences[startSentence...endSentence])
        } else {
            sectionSentences = []
        }

        var output = """
        === A1b FIDELITY TEST RESULTS ===
        Video: \(video.title)
        VideoId: \(video.videoId)
        Section: \(sectionStatus.section.role) (Section \(sectionStatus.sectionIndex + 1))
        Total Runs: \(results.count)
        Temperature: \(String(format: "%.1f", temperature))
        Section Sentences: \(sectionSentences.count)

        ════════════════════════════════════════
        SECTION TRANSCRIPT (NUMBERED SENTENCES)
        ════════════════════════════════════════

        """

        // Add numbered sentences so reviewer can see the text
        for (index, sentence) in sectionSentences.enumerated() {
            output += "[\(index + 1)] \(sentence)\n\n"
        }

        output += """

        ════════════════════════════════════════
        BEAT COUNT DISTRIBUTION
        ════════════════════════════════════════

        """

        // Beat count distribution
        let counts = results.map { $0.beatCount }
        var countFreq: [Int: Int] = [:]
        for c in counts {
            countFreq[c, default: 0] += 1
        }
        let sortedCounts = countFreq.sorted { $0.key < $1.key }
        for (count, freq) in sortedCounts {
            output += "\(count) beats: \(freq) times (\(Int(Double(freq) / Double(results.count) * 100))%)\n"
        }

        output += """

        ════════════════════════════════════════
        BEAT BOUNDARY VARIANCE ANALYSIS
        ════════════════════════════════════════

        """

        // Beat boundary distribution WITH sentence text
        let maxBeats = results.map { $0.beatCount }.max() ?? 0
        for beatIndex in 0..<maxBeats {
            let boundaries = results.compactMap { run -> Int? in
                guard beatIndex < run.beats.count else { return nil }
                return run.beats[beatIndex].boundarySentence
            }

            var freq: [Int: Int] = [:]
            for b in boundaries {
                freq[b, default: 0] += 1
            }
            let sorted = freq.sorted { $0.key < $1.key }
            let hasVariance = freq.count > 1
            let runsWithThisBeat = boundaries.count

            output += "--- Beat \(beatIndex + 1) "
            if hasVariance {
                output += "⚠️ VARIANCE"
            } else {
                output += "✓ STABLE"
            }
            if runsWithThisBeat < results.count {
                output += " (\(runsWithThisBeat)/\(results.count) runs have this beat)"
            }
            output += " ---\n\n"

            // Show each boundary option with its sentence text
            for (boundary, count) in sorted {
                let percentage = Int(Double(count) / Double(runsWithThisBeat) * 100)
                output += "  [\(boundary)] → \(count)x (\(percentage)%)\n"

                // Show the actual sentence text
                if boundary > 0 && boundary <= sectionSentences.count {
                    let sentenceText = sectionSentences[boundary - 1]
                    output += "     \"\(sentenceText)\"\n"
                }
                output += "\n"
            }
        }

        output += """

        ════════════════════════════════════════
        RAW RUN DATA
        ════════════════════════════════════════

        """

        for run in results {
            output += "Run \(run.runNumber): \(run.beatCount) beats - "
            output += run.beats.map { "[\($0.boundarySentence.map { String($0) } ?? "END")]" }.joined(separator: ", ")
            output += "\n"
        }

        output += """

        ════════════════════════════════════════
        PROMPT USED (for reference)
        ════════════════════════════════════════

        \(prompt)
        """

        UIPasteboard.general.string = output
        print("📋 Copied A1b fidelity results to clipboard")
    }
}

// MARK: - A1b Fidelity Models

struct A1bFidelityRunResult: Identifiable {
    let id = UUID()
    let runNumber: Int
    let beatCount: Int
    let beats: [A1bFidelityBeatResult]
}

struct A1bFidelityBeatResult {
    let beatIndex: Int
    let type: String
    let boundarySentence: Int?  // Sentence number where beat ends (nil for last beat)
}
