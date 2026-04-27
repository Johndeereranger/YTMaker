//
//  SemanticScriptWriterView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct SemanticScriptWriterView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var forceFitService = TemplateForceFitService.shared

    // MARK: - State

    @State private var phase: ForceFitPhase = .selectingCreators
    @State private var selectedCreatorIds: Set<String> = []
    @State private var availableCreators: [YouTubeChannel] = []

    @State private var rambling: String = ""
    @State private var followUpRambling: String = ""

    // Step results
    @State private var step1Results: Step1Results?
    @State private var step2Results: QuestionAggregationResult?
    @State private var step4Results: Step4Results?
    @State private var evaluationResult: EvaluationResult?

    @State private var selectedReFitResult: ReFitResult?
    @State private var loadedCreatorTemplates: [String: [StructuralTemplate]] = [:]
    @State private var isLoadingCreatorTemplates: Bool = false

    // UI state
    @State private var expandedResultId: UUID? = nil
    @State private var showRawResponse: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            phaseProgressBar

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch phase {
                    case .selectingCreators:
                        creatorSelectionView
                    case .rambling:
                        ramblingInputView
                    case .forceFitting:
                        step1ProgressView
                    case .aggregatingQuestions:
                        step2ProgressView
                    case .reviewingQuestions:
                        questionsReviewView
                    case .ramblingAgain:
                        followUpRamblingView
                    case .refitting:
                        step4ProgressView
                    case .evaluating:
                        step5ProgressView
                    case .selectingTemplate:
                        templateSelectionView
                    case .done:
                        completionView
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Script Writer")
        .task {
            await loadCreators()
        }
    }

    // MARK: - Phase Progress Bar

    private var phaseProgressBar: some View {
        let phases: [(ForceFitPhase, String)] = [
            (.selectingCreators, "Setup"),
            (.rambling, "Ramble"),
            (.forceFitting, "Fit"),
            (.reviewingQuestions, "Q's"),
            (.ramblingAgain, "Answer"),
            (.selectingTemplate, "Select")
        ]

        return HStack(spacing: 4) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, item in
                let isActive = isPhaseActive(item.0)
                let isComplete = isPhaseComplete(item.0)

                HStack(spacing: 4) {
                    Circle()
                        .fill(isComplete ? Color.green : (isActive ? Color.blue : Color.gray.opacity(0.3)))
                        .frame(width: 8, height: 8)

                    Text(item.1)
                        .font(.caption2)
                        .foregroundColor(isActive ? .primary : .secondary)

                    if index < phases.count - 1 {
                        Rectangle()
                            .fill(isComplete ? Color.green : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
    }

    private func isPhaseActive(_ p: ForceFitPhase) -> Bool {
        return phase == p
    }

    private func isPhaseComplete(_ p: ForceFitPhase) -> Bool {
        let order: [ForceFitPhase] = [.selectingCreators, .rambling, .forceFitting, .aggregatingQuestions, .reviewingQuestions, .ramblingAgain, .refitting, .evaluating, .selectingTemplate]
        guard let currentIndex = order.firstIndex(of: phase),
              let checkIndex = order.firstIndex(of: p) else {
            return false
        }
        return checkIndex < currentIndex
    }

    // MARK: - Creator Selection

    private var creatorSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 1: Choose Your Style Sources")
                .font(.title2.bold())

            Text("Select creators whose templates you want to use. Templates are discovered from analyzing their real videos.")
                .foregroundStyle(.secondary)

            // Info about how templates work
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("How it works")
                        .font(.headline)
                }
                Text("Templates are discovered by analyzing sentence-level patterns across a creator's videos. Select creators whose style matches what you want to create.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            Divider()

            HStack {
                Text("Available Creators")
                    .font(.headline)

                Spacer()

                if !availableCreators.isEmpty {
                    Button {
                        if selectedCreatorIds.count == availableCreators.count {
                            // Deselect all
                            selectedCreatorIds.removeAll()
                        } else {
                            // Select all
                            Task {
                                for creator in availableCreators {
                                    if !selectedCreatorIds.contains(creator.channelId) {
                                        selectedCreatorIds.insert(creator.channelId)
                                        await loadCreatorTemplates(for: creator.channelId)
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(selectedCreatorIds.count == availableCreators.count ? "Deselect All" : "Select All")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if availableCreators.isEmpty {
                VStack(spacing: 8) {
                    Text("No creators with sentence analysis found.")
                        .foregroundStyle(.secondary)
                        .italic()
                    Text("To use the script writer:\n1. Go to Study Creators and select a channel\n2. Run sentence analysis on their videos\n3. Templates will be automatically extracted from analyzed videos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                ForEach(availableCreators) { creator in
                    creatorRow(creator)
                }
            }

            // Template count summary
            let totalTemplates = selectedCreatorIds.compactMap { loadedCreatorTemplates[$0]?.count }.reduce(0, +)
            if totalTemplates > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(totalTemplates) templates selected from \(selectedCreatorIds.count) creator(s)")
                        .font(.subheadline)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer().frame(height: 20)

            Button {
                phase = .rambling
            } label: {
                HStack {
                    Text("Continue to Rambling")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCreatorIds.isEmpty)
        }
    }

    private func creatorRow(_ creator: YouTubeChannel) -> some View {
        let isSelected = selectedCreatorIds.contains(creator.channelId)
        let templateCount = loadedCreatorTemplates[creator.channelId]?.count ?? 0
        let isLoading = isLoadingCreatorTemplates && isSelected && templateCount == 0

        return Button {
            if isSelected {
                selectedCreatorIds.remove(creator.channelId)
            } else {
                selectedCreatorIds.insert(creator.channelId)
                Task {
                    await loadCreatorTemplates(for: creator.channelId)
                }
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)

                VStack(alignment: .leading) {
                    Text(creator.name)
                        .font(.headline)
                    Text("\(creator.videoCount) videos analyzed")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isLoading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Loading templates...")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    } else if templateCount > 0 {
                        Text("\(templateCount) templates discovered")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if isSelected {
                        Text("No templates found - run 'Extract Templates' first")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rambling Input

    private var ramblingInputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 2: Ramble Your Ideas")
                .font(.title2.bold())

            Text("Dump everything you know about your topic. Don't worry about structure.")
                .foregroundStyle(.secondary)

            TextEditor(text: $rambling)
                .font(.body)
                .frame(minHeight: 300)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Text("\(rambling.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Button("Back") {
                    phase = .selectingCreators
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await runStep1() }
                } label: {
                    HStack {
                        Text("Match to Templates")
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(rambling.trimmingCharacters(in: .whitespacesAndNewlines).count < 50)
            }
        }
    }

    // MARK: - Progress Views

    private var step1ProgressView: some View {
        progressView(
            title: "Step 1: Force-Fitting",
            subtitle: forceFitService.currentPhase,
            progress: forceFitService.progress
        )
    }

    private var step2ProgressView: some View {
        progressView(
            title: "Step 2: Aggregating Questions",
            subtitle: forceFitService.currentPhase,
            progress: nil
        )
    }

    private var step4ProgressView: some View {
        progressView(
            title: "Step 4: Re-Fitting with Answers",
            subtitle: forceFitService.currentPhase,
            progress: forceFitService.progress
        )
    }

    private var step5ProgressView: some View {
        progressView(
            title: "Step 5: Evaluating & Ranking",
            subtitle: forceFitService.currentPhase,
            progress: nil
        )
    }

    private func progressView(title: String, subtitle: String, progress: Double?) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .foregroundStyle(.secondary)

            if let progress = progress {
                ProgressView(value: progress)
                    .frame(width: 200)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Questions Review (After Step 1 & 2)

    private var questionsReviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 3: Review Template Fits")
                .font(.title2.bold())

            // Step 1 results summary
            if let results = step1Results {
                Text("Fit Results (\(results.results.count) templates)")
                    .font(.headline)

                ForEach(results.sortedByFit) { result in
                    step1ResultCard(result)
                }
            }

            Divider()

            // Step 2 results - consolidated questions
            if let questions = step2Results {
                HStack {
                    Text("Questions to Fill Gaps")
                        .font(.headline)
                    Spacer()
                    Text("\(questions.questionCountBefore) → \(questions.questionCountAfter)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        copyToClipboard(questions.rawResponse)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                }

                if questions.consolidatedQuestions.isEmpty {
                    Text("All templates have good coverage!")
                        .foregroundColor(.green)
                        .italic()
                } else {
                    ForEach(Array(questions.consolidatedQuestions.enumerated()), id: \.offset) { index, question in
                        HStack(alignment: .top) {
                            Text("\(index + 1).")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text(question)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            HStack {
                Button("Start Over") {
                    resetFlow()
                }
                .buttonStyle(.bordered)

                Spacer()

                if step2Results?.consolidatedQuestions.isEmpty == true {
                    Button {
                        Task { await skipToStep4() }
                    } label: {
                        Text("Skip to Ranking")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        phase = .ramblingAgain
                    } label: {
                        HStack {
                            Text("Answer Questions")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func step1ResultCard(_ result: ForceFitResult) -> some View {
        let isExpanded = expandedResultId == result.id

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    expandedResultId = isExpanded ? nil : result.id
                }
            } label: {
                HStack {
                    Text(result.templateName)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    Text("(\(result.template.videoCount) videos)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(result.fitScore)%")
                        .font(.headline)
                        .foregroundColor(fitScoreColor(result.fitScore))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Chunk status bar
            HStack(spacing: 2) {
                ForEach(result.template.typicalSequence, id: \.chunkIndex) { chunk in
                    let isFilled = result.chunksFilled.contains(chunk.chunkIndex)
                    Rectangle()
                        .fill(isFilled ? Color.green : Color.red.opacity(0.5))
                        .frame(height: 6)
                        .cornerRadius(2)
                }
            }

            // Expanded details
            if isExpanded {
                Divider()

                Text("Filled: \(result.chunksFilled.count) | Missing: \(result.chunksMissing.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Show chunks
                ForEach(result.template.typicalSequence, id: \.chunkIndex) { chunk in
                    let isFilled = result.chunksFilled.contains(chunk.chunkIndex)
                    HStack {
                        Image(systemName: isFilled ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(isFilled ? .green : .red)
                            .font(.caption)
                        Text("\(chunk.positionLabel) \(chunk.typicalRole)")
                            .font(.caption)
                        if !chunk.highTags.isEmpty {
                            Text("[\(chunk.highTags.joined(separator: ", "))]")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                if !result.questions.isEmpty {
                    Text("Questions generated:")
                        .font(.caption.bold())
                        .padding(.top, 4)
                    ForEach(result.questions, id: \.self) { q in
                        Text("• \(q)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Raw response toggle + copy
                HStack {
                    Button {
                        showRawResponse.toggle()
                    } label: {
                        Text(showRawResponse ? "Hide Raw Response" : "Show Raw Response")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    Button {
                        copyToClipboard(result.rawResponse)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.top, 4)

                if showRawResponse {
                    Text(result.rawResponse)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Follow-up Rambling

    private var followUpRamblingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 3: Fill the Gaps")
                .font(.title2.bold())

            Text("Answer these questions to strengthen your template fit:")
                .foregroundStyle(.secondary)

            if let questions = step2Results {
                ForEach(Array(questions.consolidatedQuestions.prefix(8).enumerated()), id: \.offset) { index, question in
                    HStack(alignment: .top) {
                        Text("\(index + 1).")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                        Text(question)
                            .font(.subheadline)
                    }
                }
            }

            TextEditor(text: $followUpRambling)
                .font(.body)
                .frame(minHeight: 250)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Back") {
                    phase = .reviewingQuestions
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await runStep4() }
                } label: {
                    HStack {
                        Text("Re-fit Templates")
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(followUpRambling.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
            }
        }
    }

    // MARK: - Template Selection (After Step 5)

    private var templateSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 6: Select Your Template")
                .font(.title2.bold())

            if let evaluation = evaluationResult {
                // Confidence indicator + copy
                HStack {
                    Text("AI Confidence:")
                    Text(evaluation.confidence.rawValue.uppercased())
                        .font(.headline)
                        .foregroundColor(confidenceColor(evaluation.confidence))

                    Spacer()

                    Button {
                        copyToClipboard(evaluation.rawResponse)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Eval")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }

                // Warnings
                if !evaluation.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(evaluation.warnings, id: \.self) { warning in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(warning)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // Ranked templates
                ForEach(evaluation.rankedTemplates) { ranked in
                    rankedTemplateCard(ranked)
                }
            }

            if selectedReFitResult != nil {
                HStack {
                    Spacer()
                    Button {
                        phase = .done
                    } label: {
                        HStack {
                            Text("Use Selected Template")
                            Image(systemName: "checkmark")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func rankedTemplateCard(_ ranked: RankedTemplate) -> some View {
        // Find the corresponding re-fit result
        let reFitResult = step4Results?.results.first { $0.templateId == ranked.templateId }
        let isSelected = selectedReFitResult?.templateId == ranked.templateId
        let isExpanded = expandedResultId == ranked.id

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                if let result = reFitResult {
                    selectedReFitResult = result
                }
            } label: {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)

                    if ranked.rank == 1 {
                        Text("RECOMMENDED")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    }

                    Text("#\(ranked.rank)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(ranked.templateName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(ranked.fitScore)%")
                        .font(.title2.bold())
                        .foregroundColor(fitScoreColor(ranked.fitScore))
                }
            }
            .buttonStyle(.plain)

            Text(ranked.reasoning)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Chunk mapping preview
            if let result = reFitResult {
                HStack(spacing: 2) {
                    ForEach(result.template.typicalSequence, id: \.chunkIndex) { chunk in
                        let mapping = result.chunkMapping[chunk.chunkIndex]
                        let confidence = mapping?.confidence ?? 0
                        Rectangle()
                            .fill(slotConfidenceColor(confidence))
                            .frame(height: 6)
                            .cornerRadius(2)
                    }
                }
            }

            // Expand/collapse for details
            Button {
                withAnimation {
                    expandedResultId = isExpanded ? nil : ranked.id
                }
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(isExpanded ? "Hide Details" : "View Chunk Mapping")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            if isExpanded, let result = reFitResult {
                Divider()

                ForEach(result.template.typicalSequence, id: \.chunkIndex) { chunk in
                    if let mapping = result.chunkMapping[chunk.chunkIndex] {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(chunk.positionLabel) \(chunk.typicalRole)")
                                    .font(.caption.bold())
                                if !chunk.highTags.isEmpty {
                                    Text("[\(chunk.highTags.joined(separator: ", "))]")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(mapping.confidence)%")
                                    .font(.caption)
                                    .foregroundColor(slotConfidenceColor(mapping.confidence))
                            }
                            if !mapping.content.isEmpty {
                                Text(String(mapping.content.prefix(200)) + (mapping.content.count > 200 ? "..." : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No content mapped")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .italic()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result = selectedReFitResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title)
                    Text("Template Selected!")
                        .font(.title2.bold())
                }

                Text("Template: \(result.templateName)")
                    .font(.headline)

                Text("Based on \(result.template.videoCount) real videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Overall Confidence: \(result.overallConfidence)%")
                    .foregroundStyle(.secondary)

                Divider()

                Text("Your Script Structure:")
                    .font(.headline)

                ForEach(result.template.typicalSequence, id: \.chunkIndex) { chunk in
                    if let mapping = result.chunkMapping[chunk.chunkIndex] {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(chunk.positionLabel)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(chunk.typicalRole)
                                    .font(.subheadline.bold())
                                if !chunk.highTags.isEmpty {
                                    Text("[\(chunk.highTags.joined(separator: ", "))]")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(mapping.confidence)%")
                                    .font(.caption)
                                    .foregroundColor(slotConfidenceColor(mapping.confidence))
                            }

                            if !mapping.content.isEmpty {
                                Text(mapping.content)
                                    .font(.body)
                                    .padding(.leading)
                            } else {
                                Text("TODO: \(generateExtractionQuestion(for: chunk))")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.leading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                HStack {
                    Button("Copy Structure") {
                        copyStructureToClipboard()
                    }
                    .buttonStyle(.bordered)

                    Button("Start Over") {
                        resetFlow()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadCreators() async {
        do {
            let channels = try await YouTubeFirebaseService.shared.getAllChannels()
            // Filter to channels that have sentence analysis (from which templates can be built)
            let filtered = channels.filter { $0.hasSentenceAnalysis }

            // Set available creators first
            availableCreators = filtered

            // Auto-select ALL creators by default
            selectedCreatorIds = Set(filtered.map { $0.channelId })

            // Load templates for all selected creators
            for creator in filtered {
                await loadCreatorTemplates(for: creator.channelId)
            }
        } catch {
            print("Failed to load creators: \(error)")
        }
    }

    private func loadCreatorTemplates(for channelId: String) async {
        guard loadedCreatorTemplates[channelId] == nil else { return }

        isLoadingCreatorTemplates = true

        do {
            guard let creator = availableCreators.first(where: { $0.channelId == channelId }) else {
                isLoadingCreatorTemplates = false
                return
            }

            let videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channelId)
            var sentenceData: [String: [SentenceFidelityTest]] = [:]

            for video in videos {
                let runs = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
                if !runs.isEmpty {
                    sentenceData[video.videoId] = runs
                }
            }

            _ = await TemplateExtractionService.shared.extractTemplate(
                channel: creator,
                videos: videos,
                sentenceData: sentenceData
            )

            if let clusteringResult = TemplateExtractionService.shared.currentClusteringResult {
                loadedCreatorTemplates[channelId] = clusteringResult.templates
                print("Loaded \(clusteringResult.templates.count) templates for \(creator.name)")
            }
        } catch {
            print("Failed to load templates for creator \(channelId): \(error)")
        }

        isLoadingCreatorTemplates = false
    }

    private func runStep1() async {
        phase = .forceFitting

        let templates = getTemplatesToUse()
        print("Running Step 1 with \(templates.count) templates")

        guard !templates.isEmpty else {
            print("No templates available - cannot proceed")
            phase = .selectingCreators
            return
        }

        // Step 1: Parallel force-fit
        step1Results = await forceFitService.step1ForceFitAll(rambling: rambling, templates: templates)

        // Step 2: Aggregate questions
        phase = .aggregatingQuestions
        if let results = step1Results {
            step2Results = await forceFitService.step2AggregateQuestions(step1Results: results)
        }

        phase = .reviewingQuestions
    }

    private func runStep4() async {
        phase = .refitting

        let templates = getTemplatesToUse()

        // Step 4: Re-fit with answers
        step4Results = await forceFitService.step4ReFitAll(
            originalRambling: rambling,
            answerRambling: followUpRambling,
            templates: templates
        )

        // Step 5: Evaluate and rank
        phase = .evaluating
        if let results = step4Results {
            evaluationResult = await forceFitService.step5EvaluateAndRank(step4Results: results)
        }

        phase = .selectingTemplate
    }

    private func skipToStep4() async {
        // User has no questions to answer, skip directly to step 4
        followUpRambling = ""
        await runStep4()
    }

    /// Get all templates from selected creators (from database, discovered from real videos)
    private func getTemplatesToUse() -> [StructuralTemplate] {
        var templates: [StructuralTemplate] = []

        // Add creator-specific templates from the database
        for creatorId in selectedCreatorIds {
            if let creatorTemplates = loadedCreatorTemplates[creatorId] {
                templates.append(contentsOf: creatorTemplates)
            }
        }

        return templates
    }

    private func resetFlow() {
        phase = .selectingCreators
        rambling = ""
        followUpRambling = ""
        step1Results = nil
        step2Results = nil
        step4Results = nil
        evaluationResult = nil
        selectedReFitResult = nil
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    private func copyStructureToClipboard() {
        guard let result = selectedReFitResult else { return }

        var output = "TEMPLATE: \(result.templateName)\n"
        output += "Based on: \(result.template.videoCount) real videos\n"
        output += "CONFIDENCE: \(result.overallConfidence)%\n\n"

        for chunk in result.template.typicalSequence {
            if let mapping = result.chunkMapping[chunk.chunkIndex] {
                let tags = chunk.highTags.isEmpty ? "" : " [\(chunk.highTags.joined(separator: ", "))]"
                output += "\(chunk.positionLabel) \(chunk.typicalRole)\(tags) (\(mapping.confidence)%)\n"
                if !mapping.content.isEmpty {
                    output += mapping.content + "\n"
                } else {
                    output += "TODO: \(generateExtractionQuestion(for: chunk))\n"
                }
                output += "\n"
            }
        }

        copyToClipboard(output)
    }

    // MARK: - Helpers

    private func fitScoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    private func slotConfidenceColor(_ confidence: Int) -> Color {
        if confidence >= 70 { return .green }
        if confidence >= 40 { return .orange }
        if confidence > 0 { return .red.opacity(0.7) }
        return .gray.opacity(0.3)
    }

    private func confidenceColor(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}
