//
//  PromptFidelityDebugger.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/23/26.
//

import SwiftUI

// MARK: - Data Models

struct FidelityTestRun: Identifiable {
    let id = UUID()
    let runNumber: Int
    let sections: [FidelitySectionResult]
    let rawJSON: String
    let timestamp: Date
}

struct FidelitySectionResult: Identifiable {
    var id: String { "\(role)_\(runNumber)" }
    let runNumber: Int
    let role: String
    let boundarySentence: Int?  // nil for final section
    let boundaryText: String?   // The actual sentence text at the boundary
    let sectionIndex: Int       // Position in this run's output
}

struct FidelityDivergence: Identifiable {
    let id = UUID()
    let role: String
    let sentenceNumber: Int     // The sentence where divergence occurs
    let sentenceText: String    // The actual text
    let runBoundaries: [Int: Int?]  // runNumber -> boundarySentence for that run
    let description: String     // Human readable description
}

// MARK: - View Model

@MainActor
class PromptFidelityViewModel: ObservableObject {
    @Published var selectedVideo: YouTubeVideo?
    @Published var runCount: Int = 5
    @Published var isRunning: Bool = false
    @Published var currentRun: Int = 0
    @Published var testRuns: [FidelityTestRun] = []
    @Published var divergences: [FidelityDivergence] = []
    @Published var sentences: [String] = []  // Parsed transcript sentences
    @Published var errorMessage: String?

    func runFidelityTest() async {
        guard let video = selectedVideo, let transcript = video.transcript else {
            errorMessage = "No video or transcript selected"
            return
        }

        isRunning = true
        currentRun = 0
        testRuns = []
        divergences = []
        errorMessage = nil

        // Parse sentences once
        sentences = SentenceParser.parse(transcript)

        print("\n========================================")
        print("🧪 STARTING PROMPT FIDELITY TEST")
        print("========================================")
        print("Video: \(video.title)")
        print("Transcript sentences: \(sentences.count)")
        print("Runs to execute: \(runCount)")

        for i in 1...runCount {
            currentRun = i
            print("\n--- Run \(i) of \(runCount) ---")

            do {
                let result = try await executeSingleRun(video: video, runNumber: i)
                testRuns.append(result)
                print("✅ Run \(i) complete: \(result.sections.count) sections")
            } catch {
                print("❌ Run \(i) failed: \(error)")
                errorMessage = "Run \(i) failed: \(error.localizedDescription)"
            }

            // Small delay between runs to avoid rate limiting
            if i < runCount {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
            }
        }

        // Analyze divergences
        analyzeDivergences()

        isRunning = false
        currentRun = 0

        print("\n========================================")
        print("🧪 FIDELITY TEST COMPLETE")
        print("========================================")
        print("Total runs: \(testRuns.count)")
        print("Divergences found: \(divergences.count)")
    }

    private func executeSingleRun(video: YouTubeVideo, runNumber: Int) async throws -> FidelityTestRun {
        let engine = SectionPromptEngine(video: video)
        let prompt = engine.generatePrompt()

        // Call Claude API
        let response = try await callClaudeAPI(prompt: prompt)

        // Parse response
        let parsed = try engine.parseResponse(response)

        // Build section results with boundary text
        var sectionResults: [FidelitySectionResult] = []
        for (index, section) in parsed.sections.enumerated() {
            let boundaryText: String?
            if let boundary = section.boundarySentence, boundary > 0, boundary <= sentences.count {
                boundaryText = sentences[boundary - 1]  // Convert 1-indexed to 0-indexed
            } else {
                boundaryText = nil
            }

            sectionResults.append(FidelitySectionResult(
                runNumber: runNumber,
                role: section.role,
                boundarySentence: section.boundarySentence,
                boundaryText: boundaryText,
                sectionIndex: index
            ))
        }

        return FidelityTestRun(
            runNumber: runNumber,
            sections: sectionResults,
            rawJSON: response,
            timestamp: Date()
        )
    }

    private func callClaudeAPI(prompt: String) async throws -> String {
        // Use AgentExecutionEngine pattern (same as ManualIngestionViewModel)
        let stepId = UUID()
        let promptStep = PromptStep(
            id: stepId,
            title: "Fidelity Test",
            prompt: prompt,
            notes: "",
            flowStrategy: .promptChaining,
            isBatchEligible: false,
            aiModel: .claude4Sonnet,
            useCashe: false
        )

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
            title: "Fidelity API Call",
            createdAt: Date()
        )

        let executionEngine = AgentExecutionEngine(agent: tempAgent, session: tempSession)

        let run = try await executionEngine.runStep(
            step: promptStep,
            userInput: "You are a helpful youtube video analyst",
            sharedInput: nil,
            purpose: .normal,
            inputID: nil
        )

        return run.response
    }

    private func analyzeDivergences() {
        guard testRuns.count >= 2 else { return }

        divergences = []

        // Get all unique roles across all runs
        let allRoles = Set(testRuns.flatMap { $0.sections.map { $0.role } })

        for role in allRoles.sorted() {
            // Get boundary for this role from each run
            var runBoundaries: [Int: Int?] = [:]
            for run in testRuns {
                if let section = run.sections.first(where: { $0.role == role }) {
                    runBoundaries[run.runNumber] = section.boundarySentence
                }
            }

            // Check if all runs agree
            let uniqueBoundaries = Set(runBoundaries.values.map { $0 ?? -999 })

            if uniqueBoundaries.count > 1 {
                // Divergence found!
                let boundaryValues = runBoundaries.values.compactMap { $0 }
                let minBoundary = boundaryValues.min() ?? 0
                let maxBoundary = boundaryValues.max() ?? 0

                // Get the sentence text at the divergence point
                let sentenceIndex = minBoundary - 1  // Convert to 0-indexed
                let sentenceText = sentenceIndex >= 0 && sentenceIndex < sentences.count
                    ? sentences[sentenceIndex]
                    : "(unknown)"

                let description = buildDivergenceDescription(role: role, runBoundaries: runBoundaries)

                divergences.append(FidelityDivergence(
                    role: role,
                    sentenceNumber: minBoundary,
                    sentenceText: sentenceText,
                    runBoundaries: runBoundaries,
                    description: description
                ))
            }
        }

        // Sort by sentence number to show earliest divergence first
        divergences.sort { ($0.sentenceNumber) < ($1.sentenceNumber) }
    }

    private func buildDivergenceDescription(role: String, runBoundaries: [Int: Int?]) -> String {
        var counts: [String: [Int]] = [:]  // boundary description -> run numbers

        for (runNum, boundary) in runBoundaries {
            let key = boundary.map { "[\($0)]" } ?? "null"
            counts[key, default: []].append(runNum)
        }

        let parts = counts.map { key, runs in
            "\(key): runs \(runs.sorted().map(String.init).joined(separator: ","))"
        }

        return parts.joined(separator: " | ")
    }
}

// MARK: - Main View

struct PromptFidelityDebugger: View {
    @StateObject private var viewModel = PromptFidelityViewModel()
    @State private var videos: [YouTubeVideo] = []
    @State private var expandedRuns: Set<Int> = []
    @State private var selectedDivergence: FidelityDivergence?

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            controlsSection

            Divider()

            if viewModel.isRunning {
                runningView
            } else if !viewModel.testRuns.isEmpty {
                resultsView
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Prompt Fidelity Debugger")
        .task {
            await loadVideos()
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                // Video picker
                Picker("Video", selection: $viewModel.selectedVideo) {
                    Text("Select a video").tag(nil as YouTubeVideo?)
                    ForEach(videos, id: \.videoId) { video in
                        Text(video.title).tag(video as YouTubeVideo?)
                    }
                }
                .frame(maxWidth: 400)

                Spacer()

                // Run count
                Stepper("Runs: \(viewModel.runCount)", value: $viewModel.runCount, in: 2...10)
                    .frame(width: 150)

                // Run button
                Button {
                    Task {
                        await viewModel.runFidelityTest()
                    }
                } label: {
                    Label("Run Test", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedVideo == nil || viewModel.isRunning)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    // MARK: - Running View

    private var runningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Running test \(viewModel.currentRun) of \(viewModel.runCount)...")
                .font(.headline)

            Text("This may take a minute")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "testtube.2")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Select a video and run a fidelity test")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("This will run A1a multiple times and compare the outputs to find where the LLM makes inconsistent decisions.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results View

    @State private var selectedResultsTab: ResultsTab = .analysis

    private enum ResultsTab: String, CaseIterable {
        case analysis = "Analysis"
        case transcript = "Transcript"
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Tab picker for switching views
            Picker("View", selection: $selectedResultsTab) {
                ForEach(ResultsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content based on selected tab
            switch selectedResultsTab {
            case .analysis:
                VStack(alignment: .leading, spacing: 0) {
                    divergencesList

                    Divider()

                    comparisonTable
                }
            case .transcript:
                transcriptView
            }
        }
    }

    // MARK: - Divergences List

    private var divergencesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Divergences Found: \(viewModel.divergences.count)")
                    .font(.headline)

                Spacer()

                if viewModel.divergences.isEmpty {
                    Label("All runs agree!", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            if !viewModel.divergences.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.divergences) { divergence in
                            divergenceRow(divergence)
                                .onTapGesture {
                                    selectedDivergence = divergence
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private func divergenceRow(_ divergence: FidelityDivergence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(divergence.role)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(roleColor(divergence.role).opacity(0.2))
                    .foregroundColor(roleColor(divergence.role))
                    .cornerRadius(4)

                Text("boundary diverges at sentences \(divergence.sentenceNumber)-\(divergence.sentenceNumber + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(divergence.description)
                .font(.caption2)
                .foregroundColor(.orange)

            Text("\"\(String(divergence.sentenceText.prefix(80)))...\"")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedDivergence?.id == divergence.id ? Color.blue.opacity(0.1) : Color(.tertiarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boundary Comparison by Role")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Role")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 100, alignment: .leading)

                        ForEach(viewModel.testRuns) { run in
                            Text("Run \(run.runNumber)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .frame(width: 60)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))

                    // Data rows
                    let allRoles = getAllRolesInOrder()
                    ForEach(allRoles, id: \.self) { role in
                        comparisonRow(role: role)
                    }
                }
            }
        }
    }

    private func comparisonRow(role: String) -> some View {
        let hasDivergence = viewModel.divergences.contains { $0.role == role }

        return HStack(spacing: 0) {
            Text(role)
                .font(.caption)
                .frame(width: 100, alignment: .leading)

            ForEach(viewModel.testRuns) { run in
                let boundary = run.sections.first(where: { $0.role == role })?.boundarySentence
                let boundaryText = boundary.map { "[\($0)]" } ?? "null"

                Text(boundaryText)
                    .font(.caption.monospaced())
                    .frame(width: 60)
                    .foregroundColor(hasDivergence ? .orange : .primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(hasDivergence ? Color.orange.opacity(0.1) : Color.clear)
    }

    // MARK: - Transcript View

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript (sentences)")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.sentences.enumerated()), id: \.offset) { index, sentence in
                        sentenceRow(index: index + 1, text: sentence)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func sentenceRow(index: Int, text: String) -> some View {
        let isBoundary = isSentenceBoundary(index)
        let divergesHere = viewModel.divergences.contains { $0.sentenceNumber == index || $0.sentenceNumber == index - 1 }

        return HStack(alignment: .top, spacing: 8) {
            Text("[\(index)]")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            Text(text)
                .font(.caption)
                .foregroundColor(divergesHere ? .orange : .primary)

            Spacer()

            if isBoundary {
                Image(systemName: "arrow.turn.down.left")
                    .font(.caption2)
                    .foregroundColor(divergesHere ? .orange : .blue)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(divergesHere ? Color.orange.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }

    // MARK: - Helpers

    private func loadVideos() async {
        do {
            videos = try await YouTubeFirebaseService.shared.fetchAllVideos()
        } catch {
            print("Failed to load videos: \(error)")
        }
    }

    private func getAllRolesInOrder() -> [String] {
        // Get roles in the order they appear in run 1
        guard let firstRun = viewModel.testRuns.first else { return [] }
        return firstRun.sections.map { $0.role }
    }

    private func isSentenceBoundary(_ sentenceNumber: Int) -> Bool {
        for run in viewModel.testRuns {
            for section in run.sections {
                if section.boundarySentence == sentenceNumber {
                    return true
                }
            }
        }
        return false
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

#Preview {
    PromptFidelityDebugger()
}
