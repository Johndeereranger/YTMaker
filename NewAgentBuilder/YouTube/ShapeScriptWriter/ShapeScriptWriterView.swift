//
//  ShapeScriptWriterView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/27/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shape Script Writer View

/// New script writing flow using Creator Profiles (Shape + Ingredients)
/// Completely separate from the original SemanticScriptWriterView
struct ShapeScriptWriterView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var viewModel = ShapeScriptWriterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            phaseProgressBar

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch viewModel.phase {
                    case .selectingCreator:
                        creatorSelectionView
                    case .inputtingRambling:
                        ramblingInputView
                    case .extractingContent:
                        progressView(title: "Extracting Content", subtitle: viewModel.progress)
                    case .reviewingExtraction:
                        extractionReviewView
                    case .analyzingGaps:
                        progressView(title: "Analyzing Gaps", subtitle: viewModel.progress)
                    case .answeringQuestions:
                        questionsView
                    case .generatingOutline:
                        progressView(title: "Generating Outline", subtitle: viewModel.progress)
                    case .reviewingOutline:
                        outlineReviewView
                    case .generatingScript:
                        progressView(title: "Generating Script", subtitle: viewModel.progress)
                    case .complete:
                        completionView
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Shape Script Writer")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Debug panel toggle - see raw AI responses
                Button {
                    viewModel.showDebugPanel.toggle()
                } label: {
                    Image(systemName: viewModel.showDebugPanel ? "ladybug.fill" : "ladybug")
                }
                .help("View raw AI responses")

                // New session - start fresh
                Button {
                    viewModel.reset()
                } label: {
                    Image(systemName: "plus.square")
                }
                .help("Start new session")
            }
        }
        .sheet(isPresented: $viewModel.showSessionPicker) {
            sessionPickerSheet
        }
        .sheet(isPresented: $viewModel.showDebugPanel) {
            debugPanelSheet
        }
        .task {
            await viewModel.loadCreators()
            viewModel.autoLoadLastSession()
        }
    }

    // MARK: - Debug Panel Sheet

    private var debugPanelSheet: some View {
        NavigationView {
            VStack {
                if viewModel.rawAIResponses.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "ladybug")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No AI Responses Yet")
                            .font(.headline)
                        Text("Run extraction, gap analysis, or outline generation to see raw AI responses here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(viewModel.rawAIResponses.reversed()) { record in
                            debugResponseRow(record)
                        }
                    }
                }
            }
            .navigationTitle("AI Response History")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.showDebugPanel = false
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All") {
                        viewModel.rawAIResponses = []
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }

    private func debugResponseRow(_ record: AIResponseRecord) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                // Copy All button at top
                HStack {
                    Button {
                        copyToClipboard(formatFullAICall(record))
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                            Text("Copy Full Call (Prompt + Response)")
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }

                // Prompt section
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("PROMPT SENT")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                        Spacer()
                        Button {
                            copyToClipboard(record.prompt)
                        } label: {
                            Text("Copy Prompt")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    ScrollView {
                        Text(record.prompt)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)
                }

                // Response section
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("AI RESPONSE")
                            .font(.caption.bold())
                            .foregroundColor(record.success ? .green : .red)
                        Spacer()
                        Button {
                            copyToClipboard(record.response)
                        } label: {
                            Text("Copy Response")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    ScrollView {
                        Text(record.response)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 300)
                    .padding(8)
                    .background(record.success ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                    .cornerRadius(6)
                }

                // Error if any
                if let error = record.errorMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PARSE ERROR")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(record.success ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.callName)
                        .font(.subheadline.bold())
                    Text(record.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Quick copy button without expanding
                Button {
                    copyToClipboard(formatFullAICall(record))
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("\(record.response.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Format a full AI call for copying (prompt + response together)
    private func formatFullAICall(_ record: AIResponseRecord) -> String {
        """
        ════════════════════════════════════════════════════════════════════
        AI CALL: \(record.callName)
        TIME: \(record.timestamp.formatted())
        STATUS: \(record.success ? "SUCCESS" : "FAILED")
        ════════════════════════════════════════════════════════════════════

        ────────────────────────────────────────────────────────────────────
        PROMPT SENT
        ────────────────────────────────────────────────────────────────────

        \(record.prompt)

        ────────────────────────────────────────────────────────────────────
        AI RESPONSE
        ────────────────────────────────────────────────────────────────────

        \(record.response)

        \(record.errorMessage.map { "────────────────────────────────────────────────────────────────────\nPARSE ERROR: \($0)\n" } ?? "")
        """
    }

    // MARK: - Session Picker Sheet

    private var sessionPickerSheet: some View {
        NavigationView {
            VStack {
                if viewModel.savedSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Saved Sessions")
                            .font(.headline)
                        Text("Your progress will be saved here when you use the save button.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(viewModel.savedSessions) { session in
                            sessionRow(session)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteSession(viewModel.savedSessions[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showSessionPicker = false
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: ShapeScriptSession) -> some View {
        Button {
            viewModel.restoreSession(session)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    // Phase indicator
                    Text(phaseLabel(session.phase))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(phaseColor(session.phase).opacity(0.2))
                        .foregroundColor(phaseColor(session.phase))
                        .cornerRadius(4)
                }

                HStack {
                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !session.rambling.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("\(session.rambling.split(separator: " ").count) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if session.scriptOutline != nil {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Image(systemName: "list.bullet")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    if session.fullScript != nil {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Image(systemName: "doc.text.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                // Preview of rambling
                if !session.rambling.isEmpty {
                    Text(session.rambling.prefix(100) + (session.rambling.count > 100 ? "..." : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func phaseLabel(_ phase: ShapeScriptPhase) -> String {
        switch phase {
        case .selectingCreator: return "Creator"
        case .inputtingRambling: return "Rambling"
        case .extractingContent: return "Extracting"
        case .reviewingExtraction: return "Extracted"
        case .analyzingGaps: return "Analyzing"
        case .answeringQuestions: return "Q&A"
        case .generatingOutline: return "Outlining"
        case .reviewingOutline: return "Outlined"
        case .generatingScript: return "Writing"
        case .complete: return "Complete"
        }
    }

    private func phaseColor(_ phase: ShapeScriptPhase) -> Color {
        switch phase {
        case .selectingCreator, .inputtingRambling: return .gray
        case .extractingContent, .analyzingGaps, .generatingOutline, .generatingScript: return .orange
        case .reviewingExtraction, .answeringQuestions, .reviewingOutline: return .blue
        case .complete: return .green
        }
    }

    // MARK: - Phase Progress Bar

    private var phaseProgressBar: some View {
        let phases: [(ShapeScriptPhase, String)] = [
            (.selectingCreator, "Creator"),
            (.inputtingRambling, "Ramble"),
            (.reviewingExtraction, "Extract"),
            (.answeringQuestions, "Q&A"),
            (.reviewingOutline, "Outline"),
            (.complete, "Script")
        ]

        return HStack(spacing: 4) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, item in
                let isActive = viewModel.phase == item.0 || viewModel.isPhaseActive(item.0)
                let isComplete = viewModel.isPhaseComplete(item.0)

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

    // MARK: - Creator Selection

    private var creatorSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 1: Choose Your Style Source")
                .font(.title2.bold())

            Text("Select a creator whose style you want to emulate. You need a Creator Profile generated first.")
                .foregroundStyle(.secondary)

            // Info box
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Shape-Based Writing")
                        .font(.headline)
                }
                Text("This approach uses the creator's Shape (intro/middle/close patterns) and Ingredient List (required/optional elements) to guide script generation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            Divider()

            if viewModel.isLoadingCreators {
                HStack {
                    ProgressView()
                    Text("Loading creators...")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.creatorsWithProfiles.isEmpty {
                noProfilesView
            } else {
                Text("Creators with Profiles (\(viewModel.creatorsWithProfiles.count))")
                    .font(.headline)

                ForEach(viewModel.creatorsWithProfiles) { item in
                    creatorRow(item)
                }
            }

            Spacer().frame(height: 20)

            Button {
                viewModel.phase = .inputtingRambling
                viewModel.saveCurrentSession() // Auto-save creator selection
            } label: {
                HStack {
                    Text("Continue with \(viewModel.selectedCreatorIds.count) Creator\(viewModel.selectedCreatorIds.count == 1 ? "" : "s")")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedCreatorIds.isEmpty)
        }
    }

    private var noProfilesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("No Creator Profiles Found")
                .font(.headline)

            Text("To use Shape Script Writer, you need to generate a Creator Profile first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Steps:\n1. Go to Study Creators\n2. Select a channel\n3. Run sentence analysis on videos\n4. Generate Creator Profile")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func creatorRow(_ item: CreatorWithProfile) -> some View {
        let isSelected = viewModel.selectedCreatorIds.contains(item.channel.channelId)

        return Button {
            // Toggle selection (multi-select)
            if isSelected {
                viewModel.selectedCreatorIds.remove(item.channel.channelId)
            } else {
                viewModel.selectedCreatorIds.insert(item.channel.channelId)
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.channel.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Label("\(item.profile.videosAnalyzed) videos", systemImage: "video")
                        Label("v\(item.profile.profileVersion)", systemImage: "tag")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // Shape summary
                    Text("Shape: \(item.profile.shape.middle.name)")
                        .font(.caption)
                        .foregroundColor(.blue)

                    // Ingredients summary
                    Text("Required: \(item.profile.ingredientList.required.count) | Common: \(item.profile.ingredientList.common.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
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
            Text("Step 2: Dump Your Ideas")
                .font(.title2.bold())

            if let profile = viewModel.mergedProfile {
                // Show what we're writing in the style of
                HStack {
                    Image(systemName: viewModel.selectedCreatorIds.count > 1 ? "person.3.fill" : "person.fill")
                    Text("Writing in the style of: \(profile.channelName)")
                        .font(.subheadline)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            // Target video length picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Target Video Length")
                    .font(.subheadline.bold())

                HStack(spacing: 8) {
                    ForEach([5, 8, 10, 15, 20], id: \.self) { minutes in
                        Button {
                            viewModel.targetMinutes = minutes
                        } label: {
                            Text("\(minutes) min")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.targetMinutes == minutes ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(viewModel.targetMinutes == minutes ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Show calculated targets
                HStack(spacing: 16) {
                    Label("~\(viewModel.targetWordCount) words", systemImage: "text.word.spacing")
                    Label("~\(viewModel.targetSectionCount) sections", systemImage: "list.number")
                    Label("~\(viewModel.targetPivotCount) pivots", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            Text("Ramble everything you know about your topic. Don't worry about structure - we'll shape it later.")
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.rambling)
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
                Text("\(viewModel.rambling.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Show if rambling is enough for target
                let ramblingWords = viewModel.rambling.split(separator: " ").count
                let targetWords = viewModel.targetWordCount
                if ramblingWords > 0 {
                    let coverage = min(100, Int(Double(ramblingWords) / Double(targetWords) * 100))
                    Text("\(coverage)% of target")
                        .font(.caption)
                        .foregroundColor(coverage >= 50 ? .green : .orange)
                }
            }

            HStack {
                Button("Back") {
                    viewModel.phase = .selectingCreator
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await viewModel.extractContent() }
                } label: {
                    HStack {
                        Text("Extract Content")
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.rambling.trimmingCharacters(in: .whitespacesAndNewlines).count < 50)
            }
        }
    }

    // MARK: - Extraction Review

    private var extractionReviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 3: Review Extracted Content")
                .font(.title2.bold())

            Text("Here's what we extracted from your rambling:")
                .foregroundStyle(.secondary)

            if let extracted = viewModel.extractedContent {
                Group {
                    extractedSection(title: "Hook Candidates", items: extracted.hookCandidates, icon: "sparkles")
                    extractedSection(title: "Core Points", items: extracted.corePoints, icon: "list.bullet")
                    extractedSection(title: "Evidence/Examples", items: extracted.evidenceExamples, icon: "doc.text")

                    if let aha = extracted.ahaRevelation {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("The 'Aha' Moment", systemImage: "lightbulb.fill")
                                .font(.subheadline.bold())
                            Text(aha)
                                .font(.body)
                                .padding(8)
                                .background(Color.yellow.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }

                    if let landing = extracted.landing {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Landing", systemImage: "flag.fill")
                                .font(.subheadline.bold())
                            Text(landing)
                                .font(.body)
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            HStack {
                Button("Edit Rambling") {
                    viewModel.phase = .inputtingRambling
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.clearStep(.reviewingExtraction)
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Re-extract")
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)

                Spacer()

                Button {
                    Task { await viewModel.analyzeGaps() }
                } label: {
                    HStack {
                        Text("Check for Gaps")
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func extractedSection(title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())

            if items.isEmpty {
                Text("None found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top) {
                        Text("•")
                        Text(item)
                    }
                    .font(.body)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Questions View

    private var questionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 4: Fill the Gaps")
                .font(.title2.bold())

            if let gaps = viewModel.gapAnalysis {
                // Coverage indicator
                HStack {
                    Text("Content Coverage:")
                    Text("\(gaps.coverageScore)%")
                        .font(.headline)
                        .foregroundColor(gaps.coverageScore >= 70 ? .green : (gaps.coverageScore >= 40 ? .orange : .red))
                }

                if gaps.questions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("Your rambling covers all required ingredients!")
                            .font(.headline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    Text("Answer these questions to strengthen your script:")
                        .foregroundStyle(.secondary)

                    ForEach(gaps.questions) { question in
                        questionRow(question)
                    }

                    Text("Your Answers")
                        .font(.headline)
                        .padding(.top)

                    TextEditor(text: $viewModel.questionAnswers)
                        .font(.body)
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            HStack {
                Button("Back") {
                    viewModel.phase = .reviewingExtraction
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.clearStep(.answeringQuestions)
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Re-analyze")
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)

                Spacer()

                Button {
                    Task { await viewModel.generateOutline() }
                } label: {
                    HStack {
                        Text(viewModel.gapAnalysis?.questions.isEmpty == true ? "Generate Outline" : "Continue with Answers")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func questionRow(_ question: GapQuestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Q\(question.priority)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(question.priority == 1 ? Color.red : (question.priority == 2 ? Color.orange : Color.gray))
                    .cornerRadius(4)

                Text(question.ingredientType)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Copy button to copy question for inline answering
                Button {
                    let textToCopy = "Q: \(question.question)\nA: "
                    copyToClipboard(textToCopy)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy question to clipboard")
            }

            Text(question.question)
                .font(.body)

            Text(question.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Outline Review

    private var outlineReviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 5: Review Outline")
                .font(.title2.bold())

            if let outline = viewModel.scriptOutline {
                // Target vs Actual metrics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target vs Generated")
                        .font(.subheadline.bold())

                    let actualSections = outline.sections.count
                    let actualPivots = outline.sections.filter { $0.isPivot }.count

                    HStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text("Length")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(viewModel.targetMinutes) min")
                                .font(.headline)
                        }

                        VStack(alignment: .leading) {
                            Text("Sections")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text("\(actualSections)")
                                    .font(.headline)
                                    .foregroundColor(actualSections >= viewModel.targetSectionCount - 2 ? .green : .orange)
                                Text("/ \(viewModel.targetSectionCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading) {
                            Text("Pivots")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text("\(actualPivots)")
                                    .font(.headline)
                                    .foregroundColor(actualPivots >= viewModel.targetPivotCount - 1 ? .green : .orange)
                                Text("/ \(viewModel.targetPivotCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading) {
                            Text("Words/Section")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("~\(viewModel.wordsPerSection)")
                                .font(.headline)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)

                if !outline.structureNotes.isEmpty {
                    Text(outline.structureNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }

                ForEach(outline.sections) { section in
                    outlineSectionRow(section)
                }
            }

            // Selected creators info
            VStack(alignment: .leading, spacing: 8) {
                Text("Writing in style of:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ForEach(viewModel.selectedProfiles, id: \.id) { profile in
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        Text(profile.channelName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(profile.videosAnalyzed) videos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)

            HStack {
                Button("Back") {
                    viewModel.phase = .answeringQuestions
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.clearStep(.reviewingOutline)
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Regenerate")
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)

                // Copy outline button
                Button {
                    if let outline = viewModel.scriptOutline {
                        copyToClipboard(formatOutlineForCopy(outline))
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Outline")
                    }
                }
                .buttonStyle(.bordered)

                // Copy creator profiles button
                Button {
                    copyToClipboard(formatProfilesForCopy(viewModel.selectedProfiles))
                } label: {
                    HStack {
                        Image(systemName: "person.text.rectangle")
                        Text("Copy Profiles")
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await viewModel.generateScript() }
                } label: {
                    HStack {
                        Text("Generate Script")
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Format outline as readable text for copying
    private func formatOutlineForCopy(_ outline: ScriptOutline) -> String {
        var text = "SCRIPT OUTLINE\n"
        text += "==============\n"
        text += "Estimated Length: \(outline.estimatedLength)\n"
        if !outline.structureNotes.isEmpty {
            text += "Notes: \(outline.structureNotes)\n"
        }
        text += "\n"

        for (index, section) in outline.sections.enumerated() {
            let pivotMarker = section.isPivot ? " [PIVOT]" : ""
            text += "\(index + 1). \(section.sectionName)\(pivotMarker)\n"
            text += "   Position: \(section.positionRange)\n"
            text += "   Content: \(section.contentSummary)\n"
            text += "   Tags: \(section.targetTags.joined(separator: ", "))\n"
            text += "\n"
        }

        return text
    }

    /// Format creator profiles as readable text for copying
    private func formatProfilesForCopy(_ profiles: [CreatorProfile]) -> String {
        var text = ""

        for (index, profile) in profiles.enumerated() {
            if index > 0 {
                text += "\n\n"
                text += "════════════════════════════════════════════════════════════════════\n\n"
            }
            text += profile.exportText
        }

        return text
    }

    private func outlineSectionRow(_ section: ShapeOutlineSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(section.sectionName)
                    .font(.subheadline.bold())

                if section.isPivot {
                    Text("PIVOT")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple)
                        .cornerRadius(4)
                }

                Spacer()

                Text(section.positionRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(section.contentSummary)
                .font(.body)

            HStack {
                Text("Tags:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(section.targetTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(section.isPivot ? Color.purple.opacity(0.1) : Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title)
                Text("Script Generated!")
                    .font(.title2.bold())
            }

            if let profile = viewModel.mergedProfile {
                Text("Style: \(profile.channelName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Generated sections
            ForEach(viewModel.generatedSections) { section in
                generatedSectionView(section)
            }

            // Full script
            if !viewModel.fullScript.isEmpty {
                Divider()

                HStack {
                    Text("Full Script")
                        .font(.headline)
                    Spacer()
                    // Total word count
                    let totalWords = viewModel.generatedSections.reduce(0) { $0 + $1.wordCount }
                    Text("\(totalWords) words")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    // Estimated read time (~150 words/min for video scripts)
                    let minutes = Double(totalWords) / 150.0
                    Text("~\(String(format: "%.1f", minutes)) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.fullScript)
                    .font(.body)
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
            }

            HStack {
                Button("Copy Script") {
                    copyToClipboard(viewModel.fullScript)
                }
                .buttonStyle(.bordered)

                Button("Start Over") {
                    viewModel.reset()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func generatedSectionView(_ section: ShapeGeneratedSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.sectionName)
                    .font(.subheadline.bold())

                Spacer()

                Text("\(section.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(section.confidence)% match")
                    .font(.caption)
                    .foregroundColor(section.confidence >= 70 ? .green : .orange)
            }

            Text(section.scriptText)
                .font(.body)

            HStack {
                Text("Tags hit:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(section.tagsHit, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(3)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Progress View

    private func progressView(title: String, subtitle: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - View Model

@MainActor
class ShapeScriptWriterViewModel: ObservableObject {
    @Published var phase: ShapeScriptPhase = .selectingCreator
    @Published var progress: String = ""

    // Creator selection - MULTI-SELECT (like Semantic Script Writer)
    @Published var isLoadingCreators = false
    @Published var creatorsWithProfiles: [CreatorWithProfile] = []
    @Published var selectedCreatorIds: Set<String> = []

    /// All selected profiles
    var selectedProfiles: [CreatorProfile] {
        creatorsWithProfiles
            .filter { selectedCreatorIds.contains($0.channel.channelId) }
            .map { $0.profile }
    }

    /// Merged profile combining all selected creators (for AI calls)
    var mergedProfile: CreatorProfile? {
        guard !selectedProfiles.isEmpty else { return nil }

        // If only one selected, return it directly
        if selectedProfiles.count == 1 {
            return selectedProfiles.first
        }

        // Merge multiple profiles
        return mergeProfiles(selectedProfiles)
    }

    /// Merge multiple creator profiles into one combined profile
    private func mergeProfiles(_ profiles: [CreatorProfile]) -> CreatorProfile {
        guard let first = profiles.first else {
            fatalError("Cannot merge empty profiles array")
        }

        // Average the style fingerprints
        let avgFingerprint = StyleFingerprint(
            firstPersonUsage: profiles.map { $0.styleFingerprint.firstPersonUsage }.reduce(0, +) / Double(profiles.count),
            secondPersonUsage: profiles.map { $0.styleFingerprint.secondPersonUsage }.reduce(0, +) / Double(profiles.count),
            thirdPersonUsage: profiles.map { $0.styleFingerprint.thirdPersonUsage }.reduce(0, +) / Double(profiles.count),
            assertingUsage: profiles.map { $0.styleFingerprint.assertingUsage }.reduce(0, +) / Double(profiles.count),
            questioningUsage: profiles.map { $0.styleFingerprint.questioningUsage }.reduce(0, +) / Double(profiles.count),
            challengingUsage: profiles.map { $0.styleFingerprint.challengingUsage }.reduce(0, +) / Double(profiles.count),
            statisticDensity: profiles.map { $0.styleFingerprint.statisticDensity }.reduce(0, +) / Double(profiles.count),
            entityDensity: profiles.map { $0.styleFingerprint.entityDensity }.reduce(0, +) / Double(profiles.count),
            quoteDensity: profiles.map { $0.styleFingerprint.quoteDensity }.reduce(0, +) / Double(profiles.count),
            contrastFrequency: profiles.map { $0.styleFingerprint.contrastFrequency }.reduce(0, +) / Double(profiles.count),
            revealFrequency: profiles.map { $0.styleFingerprint.revealFrequency }.reduce(0, +) / Double(profiles.count),
            challengeLanguageFrequency: profiles.map { $0.styleFingerprint.challengeLanguageFrequency }.reduce(0, +) / Double(profiles.count),
            averageChunksPerVideo: profiles.map { $0.styleFingerprint.averageChunksPerVideo }.reduce(0, +) / Double(profiles.count),
            averageSentencesPerChunk: profiles.map { $0.styleFingerprint.averageSentencesPerChunk }.reduce(0, +) / Double(profiles.count),
            averagePivotCount: profiles.map { $0.styleFingerprint.averagePivotCount }.reduce(0, +) / Double(profiles.count)
        )

        // Combine ingredients (union of all, adjust frequencies)
        var allRequired: [Ingredient] = []
        var allCommon: [Ingredient] = []
        var allOptional: [Ingredient] = []

        for profile in profiles {
            allRequired.append(contentsOf: profile.ingredientList.required)
            allCommon.append(contentsOf: profile.ingredientList.common)
            allOptional.append(contentsOf: profile.ingredientList.optional)
        }

        // Deduplicate by type, keeping highest frequency
        func dedupeIngredients(_ ingredients: [Ingredient]) -> [Ingredient] {
            var byType: [String: Ingredient] = [:]
            for ing in ingredients {
                if let existing = byType[ing.type] {
                    if ing.frequency > existing.frequency {
                        byType[ing.type] = ing
                    }
                } else {
                    byType[ing.type] = ing
                }
            }
            return Array(byType.values).sorted { $0.frequency > $1.frequency }
        }

        let mergedIngredients = IngredientList(
            required: dedupeIngredients(allRequired),
            common: dedupeIngredients(allCommon),
            optional: dedupeIngredients(allOptional)
        )

        // Use first profile's shape as base (shapes are harder to merge)
        let channelNames = profiles.map { $0.channelName }.joined(separator: " + ")

        return CreatorProfile(
            id: "merged-\(UUID().uuidString)",
            channelId: profiles.map { $0.channelId }.joined(separator: "+"),
            channelName: channelNames,
            videosAnalyzed: profiles.map { $0.videosAnalyzed }.reduce(0, +),
            videoIds: profiles.flatMap { $0.videoIds },
            styleFingerprint: avgFingerprint,
            shape: first.shape,  // Use first profile's shape
            ingredientList: mergedIngredients,
            profileVersion: "merged"
        )
    }

    // Input
    @Published var rambling: String = ""
    @Published var questionAnswers: String = ""
    @Published var targetMinutes: Int = 10  // Default 10 minutes
    @Published var wordsPerMinute: Int = 150  // Spoken word rate

    // MARK: - Length-Driven Calculations

    /// Target word count based on minutes × words per minute
    var targetWordCount: Int {
        targetMinutes * wordsPerMinute
    }

    /// Calculated words per chunk based on creator's average
    /// Uses averageChunksPerVideo and averageSentencesPerChunk
    /// Assumes ~15 words per sentence average
    var creatorWordsPerChunk: Double {
        guard let profile = mergedProfile else { return 140 } // Default
        let sentencesPerChunk = profile.styleFingerprint.averageSentencesPerChunk
        return sentencesPerChunk * 15.0  // ~15 words per sentence
    }

    /// How many sections we should generate for target length
    var targetSectionCount: Int {
        let count = Double(targetWordCount) / creatorWordsPerChunk
        return max(5, Int(count.rounded()))  // Minimum 5 sections
    }

    /// How many pivots based on creator's pivot ratio
    var targetPivotCount: Int {
        guard let profile = mergedProfile else { return 3 }
        let chunksPerVideo = profile.styleFingerprint.averageChunksPerVideo
        let pivotsPerVideo = profile.styleFingerprint.averagePivotCount
        let pivotRatio = pivotsPerVideo / max(chunksPerVideo, 1)
        let pivots = Double(targetSectionCount) * pivotRatio
        return max(2, Int(pivots.rounded()))  // Minimum 2 pivots
    }

    /// Words per section for even distribution
    var wordsPerSection: Int {
        targetWordCount / max(targetSectionCount, 1)
    }

    // AI outputs
    @Published var extractedContent: ExtractedContent?
    @Published var gapAnalysis: GapAnalysis?
    @Published var scriptOutline: ScriptOutline?
    @Published var generatedSections: [ShapeGeneratedSection] = []
    @Published var fullScript: String = ""

    // MARK: - Debug: Raw AI Responses
    // Store the raw responses from each AI call for debugging

    @Published var rawAIResponses: [AIResponseRecord] = []
    @Published var showDebugPanel: Bool = false

    // MARK: - Load Creators

    func loadCreators() async {
        isLoadingCreators = true

        do {
            // Get all channels with sentence analysis
            let channels = try await YouTubeFirebaseService.shared.getAllChannels()
            let analyzedChannels = channels.filter { $0.hasSentenceAnalysis }

            // Get profiles for these channels
            let channelIds = analyzedChannels.map { $0.channelId }
            let profiles = try await CreatorProfileFirebaseService.shared.getProfiles(forChannelIds: channelIds)

            // Match channels with profiles
            var results: [CreatorWithProfile] = []
            for profile in profiles {
                if let channel = analyzedChannels.first(where: { $0.channelId == profile.channelId }) {
                    results.append(CreatorWithProfile(channel: channel, profile: profile))
                }
            }

            creatorsWithProfiles = results.sorted { $0.profile.updatedAt > $1.profile.updatedAt }

            // Auto-select ALL creators by default (like Semantic Script Writer)
            selectedCreatorIds = Set(results.map { $0.channel.channelId })

        } catch {
            print("Failed to load creators: \(error)")
        }

        isLoadingCreators = false
    }

    // MARK: - AI Calls

    private let service = ShapeScriptWriterService.shared

    func extractContent() async {
        phase = .extractingContent
        progress = "Analyzing your rambling..."

        let result = await service.extractContent(from: rambling) { [weak self] progressText in
            Task { @MainActor in
                self?.progress = progressText
            }
        }

        // Record the AI response for debugging
        recordAIResponse(
            callName: "Content Extraction",
            prompt: result.prompt,
            response: result.rawResponse,
            success: result.success,
            errorMessage: result.errorMessage
        )

        if let content = result.result {
            extractedContent = content
            phase = .reviewingExtraction
            saveCurrentSession() // Auto-save after extraction
        } else {
            // Fallback to allow user to retry
            progress = "Extraction failed. Check debug panel for details."
            phase = .inputtingRambling
        }
    }

    func analyzeGaps() async {
        phase = .analyzingGaps
        progress = "Checking against creator's ingredients..."

        guard let profile = mergedProfile,
              let extracted = extractedContent else {
            phase = .reviewingExtraction
            return
        }

        let result = await service.analyzeGaps(
            extractedContent: extracted,
            profile: profile
        ) { [weak self] progressText in
            Task { @MainActor in
                self?.progress = progressText
            }
        }

        // Record the AI response for debugging
        recordAIResponse(
            callName: "Gap Analysis",
            prompt: result.prompt,
            response: result.rawResponse,
            success: result.success,
            errorMessage: result.errorMessage
        )

        if let gaps = result.result {
            gapAnalysis = gaps
            phase = .answeringQuestions
            saveCurrentSession() // Auto-save after gap analysis
        } else {
            // Fallback - no gaps found, proceed
            gapAnalysis = GapAnalysis(
                missingIngredients: [],
                questions: [],
                coverageScore: 70
            )
            phase = .answeringQuestions
        }
    }

    func generateOutline() async {
        phase = .generatingOutline
        progress = "Building outline from shape..."

        guard let profile = mergedProfile,
              let extracted = extractedContent else {
            phase = .answeringQuestions
            return
        }

        let result = await service.generateOutline(
            extractedContent: extracted,
            questionAnswers: questionAnswers,
            profile: profile,
            targetMinutes: targetMinutes,
            targetWordCount: targetWordCount,
            targetSectionCount: targetSectionCount,
            targetPivotCount: targetPivotCount,
            wordsPerSection: wordsPerSection
        ) { [weak self] progressText in
            Task { @MainActor in
                self?.progress = progressText
            }
        }

        // Record the AI response for debugging
        recordAIResponse(
            callName: "Outline Generation",
            prompt: result.prompt,
            response: result.rawResponse,
            success: result.success,
            errorMessage: result.errorMessage
        )

        if let outline = result.result {
            scriptOutline = outline
            phase = .reviewingOutline
            saveCurrentSession() // Auto-save after outline
        } else {
            progress = "Outline generation failed. Check debug panel for details."
            phase = .answeringQuestions
        }
    }

    func generateScript() async {
        phase = .generatingScript
        progress = "Writing script sections..."

        guard let outline = scriptOutline,
              let profile = mergedProfile,
              let extracted = extractedContent else {
            phase = .reviewingOutline
            return
        }

        var sections: [ShapeGeneratedSection] = []
        var fullText = ""

        // Get all selected channel IDs for fetching examples
        let channelIds = Array(selectedCreatorIds)

        for (index, outlineSection) in outline.sections.enumerated() {
            progress = "Writing section \(index + 1) of \(outline.sections.count): \(outlineSection.sectionName)"

            // Fetch style examples from ALL selected creators
            var allExamples: [SentenceTelemetry] = []
            for channelId in channelIds {
                let examples = await service.findStyleExamples(
                    channelId: channelId,
                    targetTags: outlineSection.targetTags,
                    positionRange: outlineSection.positionRange,
                    maxResults: 3  // Fewer per creator, more variety
                )
                allExamples.append(contentsOf: examples)
            }
            // Limit total examples
            let examples = Array(allExamples.prefix(5))

            // Generate the section
            if let section = await service.writeSection(
                section: outlineSection,
                profile: profile,
                allContent: extracted,
                questionAnswers: questionAnswers,
                styleExamples: examples
            ) {
                sections.append(section)
                fullText += "[\(outlineSection.sectionName)]\n\(section.scriptText)\n\n"
            } else {
                // Fallback for failed section
                let fallbackSection = ShapeGeneratedSection(
                    sectionName: outlineSection.sectionName,
                    scriptText: "[Failed to generate - please regenerate this section]",
                    wordCount: 0,
                    tagsHit: [],
                    confidence: 0
                )
                sections.append(fallbackSection)
                fullText += "[\(outlineSection.sectionName)]\n[Generation failed]\n\n"
            }
        }

        generatedSections = sections
        fullScript = fullText

        phase = .complete
        saveCurrentSession() // Auto-save completed script
    }

    // MARK: - Navigation Helpers

    func isPhaseActive(_ phase: ShapeScriptPhase) -> Bool {
        return self.phase == phase
    }

    func isPhaseComplete(_ phase: ShapeScriptPhase) -> Bool {
        let order: [ShapeScriptPhase] = [
            .selectingCreator, .inputtingRambling, .extractingContent,
            .reviewingExtraction, .analyzingGaps, .answeringQuestions,
            .generatingOutline, .reviewingOutline, .generatingScript, .complete
        ]
        guard let currentIndex = order.firstIndex(of: self.phase),
              let checkIndex = order.firstIndex(of: phase) else {
            return false
        }
        return checkIndex < currentIndex
    }

    func reset() {
        currentSessionId = nil
        phase = .selectingCreator
        rambling = ""
        questionAnswers = ""
        targetMinutes = 10  // Reset to default
        extractedContent = nil
        gapAnalysis = nil
        scriptOutline = nil
        generatedSections = []
        fullScript = ""
        rawAIResponses = []
    }

    /// Clear a specific step and go back
    func clearStep(_ step: ShapeScriptPhase) {
        switch step {
        case .reviewingExtraction, .extractingContent:
            extractedContent = nil
            gapAnalysis = nil
            scriptOutline = nil
            generatedSections = []
            fullScript = ""
            phase = .inputtingRambling
        case .answeringQuestions, .analyzingGaps:
            gapAnalysis = nil
            scriptOutline = nil
            generatedSections = []
            fullScript = ""
            phase = .reviewingExtraction
        case .reviewingOutline, .generatingOutline:
            scriptOutline = nil
            generatedSections = []
            fullScript = ""
            phase = .answeringQuestions
        case .complete, .generatingScript:
            generatedSections = []
            fullScript = ""
            phase = .reviewingOutline
        default:
            break
        }
        saveCurrentSession()
    }

    /// Add a raw AI response record
    func recordAIResponse(callName: String, prompt: String, response: String, success: Bool = true, errorMessage: String? = nil) {
        let record = AIResponseRecord(
            callName: callName,
            prompt: prompt,
            response: response,
            success: success,
            errorMessage: errorMessage
        )
        rawAIResponses.append(record)
    }

    // MARK: - Session Persistence

    private var currentSessionId: String?
    @Published var savedSessions: [ShapeScriptSession] = []
    @Published var showSessionPicker = false

    func loadSavedSessions() {
        savedSessions = ShapeScriptSessionManager.shared.loadSessions()
    }

    /// Auto-load the most recent session on startup
    func autoLoadLastSession() {
        loadSavedSessions()
        if let lastSession = savedSessions.first {
            restoreSession(lastSession)
        }
    }

    /// Save current state to a session
    func saveCurrentSession(name: String? = nil) {
        var session = ShapeScriptSession(
            id: currentSessionId ?? UUID().uuidString,
            name: name ?? "Session \(Date().formatted(date: .abbreviated, time: .shortened))",
            phase: phase,
            selectedCreatorIds: Array(selectedCreatorIds),
            rambling: rambling,
            questionAnswers: questionAnswers,
            targetMinutes: targetMinutes
        )

        // If we already have a session, preserve the original name and creation date
        if let existingId = currentSessionId,
           let existing = savedSessions.first(where: { $0.id == existingId }) {
            session = ShapeScriptSession(
                id: existingId,
                name: name ?? existing.name,
                phase: phase,
                selectedCreatorIds: Array(selectedCreatorIds),
                rambling: rambling,
                questionAnswers: questionAnswers,
                targetMinutes: targetMinutes
            )
        }

        session.updatedAt = Date()
        session.extractedContent = extractedContent
        session.gapAnalysis = gapAnalysis
        session.scriptOutline = scriptOutline
        session.generatedSections = generatedSections.isEmpty ? nil : generatedSections
        session.fullScript = fullScript.isEmpty ? nil : fullScript
        session.rawAIResponses = rawAIResponses.isEmpty ? nil : rawAIResponses

        currentSessionId = session.id
        ShapeScriptSessionManager.shared.saveSession(session)
        loadSavedSessions()
    }

    /// Restore state from a saved session
    func restoreSession(_ session: ShapeScriptSession) {
        currentSessionId = session.id
        phase = session.phase
        selectedCreatorIds = Set(session.selectedCreatorIds)
        rambling = session.rambling
        questionAnswers = session.questionAnswers
        targetMinutes = session.targetMinutes
        extractedContent = session.extractedContent
        gapAnalysis = session.gapAnalysis
        scriptOutline = session.scriptOutline
        generatedSections = session.generatedSections ?? []
        fullScript = session.fullScript ?? ""
        rawAIResponses = session.rawAIResponses ?? []
        showSessionPicker = false
    }

    /// Delete a saved session
    func deleteSession(_ session: ShapeScriptSession) {
        ShapeScriptSessionManager.shared.deleteSession(session.id)
        loadSavedSessions()
    }

    /// Check if we have unsaved changes
    var hasUnsavedChanges: Bool {
        return !rambling.isEmpty || extractedContent != nil || scriptOutline != nil
    }
}

// MARK: - Supporting Types

enum ShapeScriptPhase: String, Codable {
    case selectingCreator
    case inputtingRambling
    case extractingContent
    case reviewingExtraction
    case analyzingGaps
    case answeringQuestions
    case generatingOutline
    case reviewingOutline
    case generatingScript
    case complete
}

/// Record of a raw AI response for debugging
struct AIResponseRecord: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let callName: String        // e.g., "Content Extraction", "Gap Analysis"
    let prompt: String          // What we sent
    let response: String        // What we got back
    let success: Bool           // Did parsing succeed?
    let errorMessage: String?   // If parsing failed, why?

    init(
        callName: String,
        prompt: String,
        response: String,
        success: Bool = true,
        errorMessage: String? = nil
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.callName = callName
        self.prompt = prompt
        self.response = response
        self.success = success
        self.errorMessage = errorMessage
    }
}

struct CreatorWithProfile: Identifiable {
    var id: String { channel.channelId }
    let channel: YouTubeChannel
    let profile: CreatorProfile
}

// MARK: - Session Persistence

/// Saved session state for Shape Script Writer
struct ShapeScriptSession: Codable, Identifiable {
    let id: String
    let createdAt: Date
    var updatedAt: Date
    var name: String

    // State
    var phase: ShapeScriptPhase
    var selectedCreatorIds: [String]
    var rambling: String
    var questionAnswers: String
    var targetMinutes: Int

    // AI outputs (optional - may not have been generated yet)
    var extractedContent: ExtractedContent?
    var gapAnalysis: GapAnalysis?
    var scriptOutline: ScriptOutline?
    var generatedSections: [ShapeGeneratedSection]?
    var fullScript: String?

    // Debug: Raw AI responses
    var rawAIResponses: [AIResponseRecord]?

    init(
        id: String = UUID().uuidString,
        name: String = "",
        phase: ShapeScriptPhase = .selectingCreator,
        selectedCreatorIds: [String] = [],
        rambling: String = "",
        questionAnswers: String = "",
        targetMinutes: Int = 10
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.name = name.isEmpty ? "Session \(Date().formatted(date: .abbreviated, time: .shortened))" : name
        self.phase = phase
        self.selectedCreatorIds = selectedCreatorIds
        self.rambling = rambling
        self.questionAnswers = questionAnswers
        self.targetMinutes = targetMinutes
    }
}

/// Manager for saving/loading Shape Script sessions
class ShapeScriptSessionManager {
    static let shared = ShapeScriptSessionManager()

    private let sessionsKey = "shapeScriptSessions"

    private init() {}

    func saveSessions(_ sessions: [ShapeScriptSession]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            UserDefaults.standard.set(data, forKey: sessionsKey)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }

    func loadSessions() -> [ShapeScriptSession] {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([ShapeScriptSession].self, from: data)
        } catch {
            print("Failed to load sessions: \(error)")
            return []
        }
    }

    func saveSession(_ session: ShapeScriptSession) {
        var sessions = loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        // Keep only last 10 sessions
        if sessions.count > 10 {
            sessions = Array(sessions.prefix(10))
        }
        saveSessions(sessions)
    }

    func deleteSession(_ id: String) {
        var sessions = loadSessions()
        sessions.removeAll { $0.id == id }
        saveSessions(sessions)
    }
}
