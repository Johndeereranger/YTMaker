//
//  TemplateFidelityTesterView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import SwiftUI

// MARK: - Template Fidelity Test Models

struct TemplateFidelityRun: Identifiable {
    let id = UUID()
    let runNumber: Int
    let sections: [TemplateFidelitySection]
    let rawJSON: String
    let timestamp: Date
}

struct TemplateFidelitySection: Identifiable {
    var id: String { "\(role)_\(runNumber)" }
    let runNumber: Int
    let role: String
    let boundarySentence: Int?
    let sectionIndex: Int
}

struct TemplateFidelityResult {
    let totalRuns: Int
    let consistentRoles: Int
    let totalRoles: Int
    let stabilityScore: Double  // 0.0 to 1.0
    let divergences: [TemplateFidelityDivergence]
}

struct TemplateFidelityDivergence: Identifiable {
    let id = UUID()
    let role: String
    let runBoundaries: [Int: Int?]
    let variance: Int  // Max difference in boundary across runs
}

// MARK: - View Model

@MainActor
class TemplateFidelityViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var currentRun = 0
    @Published var totalRuns = 5
    @Published var runs: [TemplateFidelityRun] = []
    @Published var result: TemplateFidelityResult?
    @Published var errorMessage: String?
    @Published var sentences: [String] = []

    func runTest(template: StyleTemplate, video: YouTubeVideo, prompt: String, runCount: Int) async {
        guard let transcript = video.transcript else {
            errorMessage = "Video has no transcript"
            return
        }

        isRunning = true
        currentRun = 0
        totalRuns = runCount
        runs = []
        result = nil
        errorMessage = nil

        // Parse sentences
        sentences = SentenceParser.parse(transcript)

        print("\n========================================")
        print("TEMPLATE FIDELITY TEST")
        print("========================================")
        print("Template: \(template.name)")
        print("Video: \(video.title)")
        print("Sentences: \(sentences.count)")
        print("Runs: \(runCount)")

        for i in 1...runCount {
            currentRun = i

            do {
                let run = try await executeSingleRun(
                    video: video,
                    prompt: prompt,
                    runNumber: i
                )
                runs.append(run)
                print("Run \(i) complete: \(run.sections.count) sections")
            } catch {
                print("Run \(i) failed: \(error)")
                errorMessage = "Run \(i) failed: \(error.localizedDescription)"
            }

            // Delay between runs
            if i < runCount {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        // Analyze results
        analyzeResults()

        isRunning = false
        currentRun = 0
    }

    private func executeSingleRun(video: YouTubeVideo, prompt: String, runNumber: Int) async throws -> TemplateFidelityRun {
        // Build the full prompt with transcript
        let fullPrompt = buildFullPrompt(systemPrompt: prompt, video: video)

        // Call Claude API
        let response = try await callClaudeAPI(prompt: fullPrompt)

        // Parse sections from response
        let sections = parseSectionsFromResponse(response: response, runNumber: runNumber)

        return TemplateFidelityRun(
            runNumber: runNumber,
            sections: sections,
            rawJSON: response,
            timestamp: Date()
        )
    }

    private func buildFullPrompt(systemPrompt: String, video: YouTubeVideo) -> String {
        let numberedTranscript = sentences.enumerated().map { index, sentence in
            "[\(index + 1)] \(sentence)"
        }.joined(separator: "\n")

        return """
        \(systemPrompt)

        VIDEO TITLE: \(video.title)

        TRANSCRIPT (numbered sentences):
        \(numberedTranscript)

        Analyze this transcript and return the sections as JSON.
        """
    }

    private func callClaudeAPI(prompt: String) async throws -> String {
        let stepId = UUID()
        let promptStep = PromptStep(
            id: stepId,
            title: "Template Fidelity Test",
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
            name: "Template Fidelity Test",
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
            userInput: "You are analyzing a YouTube video transcript.",
            sharedInput: nil,
            purpose: .normal,
            inputID: nil
        )

        return run.response
    }

    private func parseSectionsFromResponse(response: String, runNumber: Int) -> [TemplateFidelitySection] {
        // Try to extract JSON and parse sections
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            return []
        }

        // Generic section parsing - look for sections array with role and boundary
        struct GenericSection: Codable {
            let role: String?
            let sectionRole: String?
            let startSentence: Int?
            let endSentence: Int?
            let boundarySentence: Int?
        }

        struct GenericResponse: Codable {
            let sections: [GenericSection]?
        }

        do {
            let decoded = try JSONDecoder().decode(GenericResponse.self, from: data)
            guard let sections = decoded.sections else { return [] }

            return sections.enumerated().map { index, section in
                let role = section.role ?? section.sectionRole ?? "UNKNOWN"
                let boundary = section.endSentence ?? section.boundarySentence

                return TemplateFidelitySection(
                    runNumber: runNumber,
                    role: role,
                    boundarySentence: boundary,
                    sectionIndex: index
                )
            }
        } catch {
            print("Failed to parse sections: \(error)")
            return []
        }
    }

    private func extractJSON(from response: String) -> String? {
        // Try ```json block
        if let jsonBlockRange = response.range(of: "```json"),
           let endBlockRange = response.range(of: "```", range: jsonBlockRange.upperBound..<response.endIndex) {
            return String(response[jsonBlockRange.upperBound..<endBlockRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try generic ``` block
        if let startRange = response.range(of: "```"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            let content = String(response[startRange.upperBound..<endRange.lowerBound])
            if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Try first { to last }
        if let firstBrace = response.firstIndex(of: "{"),
           let lastBrace = response.lastIndex(of: "}") {
            return String(response[firstBrace...lastBrace])
        }

        return nil
    }

    private func analyzeResults() {
        guard runs.count >= 2 else {
            result = TemplateFidelityResult(
                totalRuns: runs.count,
                consistentRoles: 0,
                totalRoles: 0,
                stabilityScore: 0,
                divergences: []
            )
            return
        }

        // Get all unique roles
        let allRoles = Set(runs.flatMap { $0.sections.map { $0.role } })
        var divergences: [TemplateFidelityDivergence] = []
        var consistentCount = 0

        for role in allRoles.sorted() {
            var runBoundaries: [Int: Int?] = [:]

            for run in runs {
                if let section = run.sections.first(where: { $0.role == role }) {
                    runBoundaries[run.runNumber] = section.boundarySentence
                } else {
                    runBoundaries[run.runNumber] = nil
                }
            }

            // Check consistency
            let boundaryValues = runBoundaries.values.compactMap { $0 }
            let uniqueBoundaries = Set(boundaryValues)

            if uniqueBoundaries.count <= 1 {
                // Consistent
                consistentCount += 1
            } else {
                // Divergent
                let minBoundary = boundaryValues.min() ?? 0
                let maxBoundary = boundaryValues.max() ?? 0

                divergences.append(TemplateFidelityDivergence(
                    role: role,
                    runBoundaries: runBoundaries,
                    variance: maxBoundary - minBoundary
                ))
            }
        }

        // Calculate stability score
        let totalRoles = allRoles.count
        let stabilityScore = totalRoles > 0 ? Double(consistentCount) / Double(totalRoles) : 0.0

        result = TemplateFidelityResult(
            totalRuns: runs.count,
            consistentRoles: consistentCount,
            totalRoles: totalRoles,
            stabilityScore: stabilityScore,
            divergences: divergences.sorted { $0.variance > $1.variance }
        )

        print("\nStability Score: \(Int(stabilityScore * 100))%")
        print("Consistent roles: \(consistentCount)/\(totalRoles)")
        print("Divergences: \(divergences.count)")
    }
}

// MARK: - Main View

struct TemplateFidelityTesterView: View {
    let channel: YouTubeChannel
    let template: StyleTemplate
    let video: YouTubeVideo
    let prompt: String
    let onComplete: (Double, Date) -> Void  // (stabilityScore, testedAt)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TemplateFidelityViewModel()

    @State private var runCount = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerSection

                Divider()

                // Content
                if viewModel.isRunning {
                    runningView
                } else if let result = viewModel.result {
                    resultView(result)
                } else {
                    configurationView
                }
            }
            .navigationTitle("Fidelity Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.result != nil {
                        Button("Save Result") {
                            saveAndDismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                    Text(video.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if template.a1aStabilityScore != nil {
                    VStack(alignment: .trailing) {
                        Text("Previous")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(Int(template.a1aStabilityScore! * 100))%")
                            .font(.title3.bold())
                            .foregroundColor(scoreColor(template.a1aStabilityScore!))
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Configuration View

    private var configurationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "testtube.2")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Ready to Test")
                .font(.headline)

            Text("This will run the A1a prompt \(runCount) times and measure consistency.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Stepper("Runs: \(runCount)", value: $runCount, in: 3...10)
                .frame(width: 200)

            Button {
                Task {
                    await viewModel.runTest(
                        template: template,
                        video: video,
                        prompt: prompt,
                        runCount: runCount
                    )
                }
            } label: {
                Label("Start Test", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Running View

    private var runningView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Running test \(viewModel.currentRun) of \(viewModel.totalRuns)...")
                .font(.headline)

            ProgressView(value: Double(viewModel.currentRun), total: Double(viewModel.totalRuns))
                .frame(width: 200)

            Spacer()
        }
    }

    // MARK: - Result View

    private func resultView(_ result: TemplateFidelityResult) -> some View {
        List {
            // Score Section
            Section {
                VStack(spacing: 16) {
                    // Big score display
                    Text("\(Int(result.stabilityScore * 100))%")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor(result.stabilityScore))

                    Text("Stability Score")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Stats
                    HStack(spacing: 24) {
                        VStack {
                            Text("\(result.totalRuns)")
                                .font(.title2.bold())
                            Text("Runs")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        VStack {
                            Text("\(result.consistentRoles)")
                                .font(.title2.bold())
                                .foregroundColor(.green)
                            Text("Consistent")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        VStack {
                            Text("\(result.divergences.count)")
                                .font(.title2.bold())
                                .foregroundColor(result.divergences.isEmpty ? .green : .orange)
                            Text("Divergent")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }

            // Divergences Section
            if !result.divergences.isEmpty {
                Section("Divergences") {
                    ForEach(result.divergences) { divergence in
                        divergenceRow(divergence)
                    }
                }
            }

            // Run Details Section
            Section("Run Details") {
                ForEach(viewModel.runs) { run in
                    DisclosureGroup {
                        ForEach(run.sections) { section in
                            HStack {
                                Text(section.role)
                                    .font(.caption)
                                Spacer()
                                if let boundary = section.boundarySentence {
                                    Text("[\(boundary)]")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("null")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Run \(run.runNumber)")
                                .font(.subheadline)
                            Spacer()
                            Text("\(run.sections.count) sections")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func divergenceRow(_ divergence: TemplateFidelityDivergence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(divergence.role)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)

                Spacer()

                Text("variance: \(divergence.variance)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Show boundaries from each run
            HStack(spacing: 8) {
                ForEach(divergence.runBoundaries.sorted(by: { $0.key < $1.key }), id: \.key) { runNum, boundary in
                    VStack(spacing: 2) {
                        Text("R\(runNum)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(boundary.map { "[\($0)]" } ?? "null")
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .yellow }
        return .red
    }

    private func saveAndDismiss() {
        guard let result = viewModel.result else { return }
        onComplete(result.stabilityScore, Date())
        dismiss()
    }
}

#Preview {
    TemplateFidelityTesterView(
        channel: YouTubeChannel(
            channelId: "test",
            name: "Johnny Harris",
            handle: "johnnyharris",
            thumbnailUrl: "",
            videoCount: 100,
            lastSynced: Date()
        ),
        template: StyleTemplate(
            id: "test_historical",
            name: "Historical Investigation",
            description: "Videos that trace the origins of institutions or events",
            videoIds: ["video1", "video2"],
            expectedPivotMin: 4,
            expectedPivotMax: 6,
            retentionStrategy: "mystery-reveal",
            argumentType: "investigative",
            sectionDensity: "dense",
            commonTransitionMarkers: [],
            commonEvidenceTypes: ["historical-data", "document-reveal"],
            expectedSectionsMin: 5,
            expectedSectionsMax: 8,
            turnSignals: []
        ),
        video: YouTubeVideo(
            videoId: "test123",
            channelId: "test",
            title: "Test Video Title",
            description: "",
            publishedAt: Date(),
            duration: "10:00",
            thumbnailUrl: "",
            stats: VideoStats(viewCount: 1000, likeCount: 100, commentCount: 10),
            createdAt: Date()
        ),
        prompt: "Test prompt",
        onComplete: { _, _ in }
    )
}
