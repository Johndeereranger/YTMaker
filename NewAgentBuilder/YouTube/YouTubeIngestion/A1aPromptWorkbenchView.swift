//
//  A1aPromptWorkbenchView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/25/26.
//

import SwiftUI

/// Workbench for developing and testing template-specific A1a prompts
/// This view supports the external prompt engineering workflow:
/// 1. Export context (taxonomy, Phase 0, transcripts) for external development
/// 2. Paste developed prompt back and test fidelity
/// 3. Save stable prompts to the template
struct A1aPromptWorkbenchView: View {
    let channel: YouTubeChannel
    let template: LockedTemplate

    @EnvironmentObject var nav: NavigationViewModel

    // MARK: - State

    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Prompt editing state
    @State private var editingPrompt: String = ""
    @State private var hasUnsavedChanges = false

    // Fidelity testing state
    @State private var isRunningFidelity = false
    @State private var fidelityRunCount: Int = 5
    @State private var fidelityTemperature: Double = 0.2
    @State private var fidelityCurrentRun = 0
    @State private var fidelityResults: [A1aWorkbenchFidelityResult] = []
    @State private var fidelityError: String?
    @State private var selectedTestVideoId: String? = nil  // nil = not selected, must pick one

    // Saving state
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSaveSuccess = false

    // Copy confirmation
    @State private var showCopyConfirmation = false
    @State private var copyConfirmationText = ""

    // Computed properties
    private var exemplarVideos: [YouTubeVideo] {
        videos.filter { template.exemplarVideoIds.contains($0.videoId) }
    }

    private var exemplarsWithTranscript: [YouTubeVideo] {
        exemplarVideos.filter { $0.hasTranscript }
    }

    private var exemplarsWithPhase0: [YouTubeVideo] {
        exemplarVideos.filter { $0.phase0Result != nil }
    }

    private var selectedTestVideo: YouTubeVideo? {
        guard let id = selectedTestVideoId else { return nil }
        return exemplarsWithTranscript.first { $0.videoId == id }
    }

    private var canRunFidelity: Bool {
        !editingPrompt.isEmpty && selectedTestVideo != nil && !isRunningFidelity
    }

    // MARK: - Body

    var body: some View {
        List {
            // Template Info Section
            Section {
                templateInfoCard
            }

            // Export Section - Copy data for external prompt development
            Section("Export Context") {
                exportContextSection
            }

            // Prompt Editor Section
            Section("A1a Prompt") {
                promptEditorSection
            }

            // Fidelity Testing Section
            if !editingPrompt.isEmpty {
                Section("Fidelity Testing") {
                    fidelityTestingSection
                }
            }

            // Results Section
            if !fidelityResults.isEmpty {
                Section("Fidelity Results") {
                    fidelityResultsSection
                }
            }

            // Save Section
            if hasUnsavedChanges && !editingPrompt.isEmpty {
                Section("Save") {
                    saveSection
                }
            }
        }
        .navigationTitle("A1a Workbench")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadVideos()
        }
        .overlay {
            if isRunningFidelity {
                fidelityProgressOverlay
            }
        }
        .overlay(alignment: .bottom) {
            if showCopyConfirmation {
                copyConfirmationBanner
            }
        }
    }

    // MARK: - Template Info Card

    private var templateInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.name)
                    .font(.headline)

                Spacer()

                if template.hasA1aPrompt {
                    Label("Has Prompt", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("No Prompt", systemImage: "circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(template.description)
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(template.exemplarCount)")
                        .font(.title3.bold())
                    Text("Exemplars")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(exemplarsWithTranscript.count)")
                        .font(.title3.bold())
                        .foregroundColor(exemplarsWithTranscript.count == template.exemplarCount ? .green : .orange)
                    Text("w/ Transcript")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(exemplarsWithPhase0.count)")
                        .font(.title3.bold())
                        .foregroundColor(exemplarsWithPhase0.count == template.exemplarCount ? .green : .orange)
                    Text("w/ Phase 0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if template.hasBeenTested {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.0f%%", (template.a1aStabilityScore ?? 0) * 100))
                            .font(.title3.bold())
                            .foregroundColor(stabilityColor(template.a1aStabilityScore ?? 0))
                        Text("Stability")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Export Context Section

    private var exportContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy data for external prompt development in Claude/ChatGPT")
                .font(.caption)
                .foregroundColor(.secondary)

            // Copy All Context Button (most useful)
            Button {
                copyAllContext()
            } label: {
                HStack {
                    Image(systemName: "doc.on.clipboard.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy All Context")
                            .font(.subheadline.bold())
                        Text("Taxonomy + Phase 0 + Transcripts + Current Prompt")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Individual copy buttons
            HStack(spacing: 8) {
                copyButton(
                    title: "Taxonomy",
                    icon: "rectangle.3.group",
                    action: copyTaxonomy
                )

                copyButton(
                    title: "Phase 0s",
                    icon: "sparkles",
                    action: copyPhase0Data
                )
            }

            HStack(spacing: 8) {
                copyButton(
                    title: "Transcripts",
                    icon: "text.alignleft",
                    action: copyTranscripts
                )

                copyButton(
                    title: "Current Prompt",
                    icon: "doc.text",
                    action: copyCurrentPrompt
                )
            }

            HStack(spacing: 8) {
                copyButton(
                    title: "Baseline A1a",
                    icon: "doc.badge.gearshape",
                    action: copyBaselineA1aPrompt
                )

                if let roles = template.roleVocabulary, !roles.isEmpty {
                    copyButton(
                        title: "Role Vocab (\(roles.count))",
                        icon: "list.bullet",
                        action: copyRoleVocabulary
                    )
                }
            }

            // Output format reference
            Button {
                copyOutputFormatReference()
            } label: {
                HStack {
                    Image(systemName: "doc.plaintext")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy Output Format Reference")
                            .font(.caption.bold())
                        Text("JSON schema your prompt MUST produce")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    private func copyButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prompt Editor Section

    private var promptEditorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Template-specific A1a extraction prompt")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if hasUnsavedChanges {
                    Text("Unsaved")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            TextEditor(text: $editingPrompt)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: editingPrompt) { _, newValue in
                    hasUnsavedChanges = newValue != (template.a1aSystemPrompt ?? "")
                }

            HStack {
                Button("Clear") {
                    editingPrompt = ""
                }
                .buttonStyle(.bordered)
                .disabled(editingPrompt.isEmpty)

                Spacer()

                Button("Paste from Clipboard") {
                    if let pasted = UIPasteboard.general.string {
                        editingPrompt = pasted
                    }
                }
                .buttonStyle(.bordered)

                if template.hasA1aPrompt {
                    Button("Restore Saved") {
                        editingPrompt = template.a1aSystemPrompt ?? ""
                        hasUnsavedChanges = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Fidelity Testing Section

    private var fidelityTestingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test prompt consistency on a single video first")
                .font(.caption)
                .foregroundColor(.secondary)

            // Video picker - REQUIRED before running
            VStack(alignment: .leading, spacing: 4) {
                Text("Select Test Video")
                    .font(.caption.bold())

                Picker("Test Video", selection: $selectedTestVideoId) {
                    Text("Select a video...").tag(nil as String?)

                    ForEach(exemplarsWithTranscript, id: \.videoId) { video in
                        Text(video.title)
                            .lineLimit(1)
                            .tag(video.videoId as String?)
                    }
                }
                .pickerStyle(.menu)

                if let video = selectedTestVideo {
                    HStack(spacing: 8) {
                        if video.phase0Result != nil {
                            Label("Has Phase 0", systemImage: "checkmark.circle")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        Text("\(video.transcript?.count ?? 0) chars")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(6)

            // Settings row
            HStack {
                Stepper("\(fidelityRunCount) runs", value: $fidelityRunCount, in: 3...15, step: 1)
                    .frame(width: 130)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Temp: \(String(format: "%.1f", fidelityTemperature))")
                        .font(.caption)
                    Slider(value: $fidelityTemperature, in: 0...1, step: 0.1)
                        .frame(width: 100)
                }
            }

            // Run button
            Button {
                Task { await runFidelityTests() }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Run \(fidelityRunCount) Tests")
                    if let video = selectedTestVideo {
                        Text("on 1 video")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRunFidelity)

            // Copy buttons for selected video
            if let video = selectedTestVideo {
                HStack(spacing: 8) {
                    Button {
                        copyNumberedTranscript(video: video)
                    } label: {
                        HStack {
                            Image(systemName: "list.number")
                            Text("Copy Numbered Transcript")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyVideoContext(video: video)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Copy Full Context")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if selectedTestVideoId == nil && !exemplarsWithTranscript.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Select a video above to run fidelity tests")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if exemplarsWithTranscript.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No exemplar videos have transcripts. Fetch transcripts first.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if let error = fidelityError {
                HStack {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Fidelity Results Section

    private var fidelityResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Overall stability score
            let overallStability = calculateOverallStability()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overall Stability")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", overallStability * 100))
                        .font(.title.bold())
                        .foregroundColor(stabilityColor(overallStability))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(fidelityResults.count) runs")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let firstStart = fidelityResults.map({ $0.startedAt }).min(),
                       let lastEnd = fidelityResults.map({ $0.completedAt }).max() {
                        let wallTime = lastEnd.timeIntervalSince(firstStart)
                        Text("Wall: \(String(format: "%.1fs", wallTime))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Field stability breakdown
            Text("Field Stability")
                .font(.caption.bold())

            fieldStabilityRow(label: "Section Count", stability: calculateSectionCountStability())
            fieldStabilityRow(label: "Role Distribution", stability: calculateRoleStability())
            fieldStabilityRow(label: "Logic Spine", stability: calculateLogicSpineStability())

            Divider()

            // Copy buttons
            HStack(spacing: 8) {
                Button {
                    copyFidelityResults()
                } label: {
                    Label("Copy Results", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    copyFidelityDebug()
                } label: {
                    Label("Copy Debug", systemImage: "ladybug")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            // Individual run details (collapsible)
            DisclosureGroup("Run Details") {
                ForEach(fidelityResults.sorted { $0.runNumber < $1.runNumber }) { result in
                    runDetailRow(result)
                }
            }
        }
    }

    private func fieldStabilityRow(label: String, stability: Double) -> some View {
        HStack {
            Text(label)
                .font(.caption)

            Spacer()

            stabilityIndicator(stability)

            Text(String(format: "%.0f%%", stability * 100))
                .font(.caption.bold())
                .foregroundColor(stabilityColor(stability))
                .frame(width: 45, alignment: .trailing)
        }
    }

    private func stabilityIndicator(_ stability: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Rectangle()
                    .fill(Double(i) / 5.0 < stability ? stabilityColor(stability) : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 8)
                    .cornerRadius(2)
            }
        }
    }

    private func stabilityColor(_ stability: Double) -> Color {
        if stability >= 0.9 { return .green }
        if stability >= 0.7 { return .orange }
        return .red
    }

    private func runDetailRow(_ result: A1aWorkbenchFidelityResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Run \(result.runNumber)")
                    .font(.caption.bold())

                Spacer()

                Text(result.videoTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(String(format: "%.1fs", result.durationSeconds))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let error = result.error {
                Text("Error: \(error)")
                    .font(.caption2)
                    .foregroundColor(.red)
            } else {
                HStack(spacing: 12) {
                    Text("\(result.sectionCount) sections")
                        .font(.caption2)

                    Text(result.rolesSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Save Section

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let currentStability = fidelityResults.isEmpty ? nil : calculateOverallStability()

            if let stability = currentStability {
                HStack {
                    if stability >= 0.8 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Prompt is stable (\(String(format: "%.0f%%", stability * 100))) - safe to save")
                            .font(.caption)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Prompt stability is low (\(String(format: "%.0f%%", stability * 100))) - consider iterating")
                            .font(.caption)
                    }
                }
            }

            Button {
                Task { await savePromptToTemplate() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text("Save Prompt to Template")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || editingPrompt.isEmpty)

            if let error = saveError {
                HStack {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            if showSaveSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Prompt saved successfully!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - Progress Overlay

    private var fidelityProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)

                Text("Running A1a Fidelity Test")
                    .font(.headline)

                if let video = selectedTestVideo {
                    Text(video.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 250)
                }

                Text("Run \(fidelityCurrentRun) of \(fidelityRunCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ProgressView(value: Double(fidelityCurrentRun), total: Double(fidelityRunCount))
                    .frame(width: 200)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 20)
            )
        }
    }

    // MARK: - Copy Confirmation Banner

    private var copyConfirmationBanner: some View {
        Text(copyConfirmationText)
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(20)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Data Loading

    private func loadVideos() async {
        isLoading = true

        do {
            videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channel.channelId)

            // Initialize editing prompt from template
            editingPrompt = template.a1aSystemPrompt ?? ""
            hasUnsavedChanges = false

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Copy Functions

    private func showCopySuccess(_ message: String) {
        copyConfirmationText = message
        withAnimation {
            showCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }

    private func copyAllContext() {
        var output = """
        ═══════════════════════════════════════════════════════════════
        A1a PROMPT DEVELOPMENT CONTEXT
        ═══════════════════════════════════════════════════════════════

        Creator: \(channel.name)
        Template: \(template.name)
        Exemplar Videos: \(template.exemplarCount)
        Videos with Transcripts: \(exemplarsWithTranscript.count)
        Videos with Phase 0: \(exemplarsWithPhase0.count)

        ═══════════════════════════════════════════════════════════════
        TEMPLATE DEFINITION
        ═══════════════════════════════════════════════════════════════

        ID: \(template.id)
        Name: \(template.name)
        Description: \(template.description)

        Classification Criteria:
        - Required Signals: \(template.classificationCriteria.requiredSignals.joined(separator: ", "))
        - Anti Signals: \(template.classificationCriteria.antiSignals.joined(separator: ", "))

        """

        if let roles = template.roleVocabulary, !roles.isEmpty {
            output += """

            Role Vocabulary: \(roles.joined(separator: ", "))

            """
        }

        // Add Phase 0 data
        output += """

        ═══════════════════════════════════════════════════════════════
        PHASE 0 EXECUTION TRACES (Exemplar Videos)
        ═══════════════════════════════════════════════════════════════

        """

        for video in exemplarsWithPhase0 {
            if let phase0 = video.phase0Result, let trace = phase0.executionTrace {
                output += """

                ───────────────────────────────────────────────────────────────
                VIDEO: \(video.title)
                ID: \(video.videoId)
                ───────────────────────────────────────────────────────────────

                Opening:
                  Hook Type: \(trace.opening.hookType)
                  Duration: \(trace.opening.durationSeconds)s
                  What Happens: \(trace.opening.whatHappens)

                Pivots (\(trace.pivots.count)):
                \(trace.pivots.map { "  [\($0.timestampPercent)%] \($0.triggerMoment)\n    Assumption Challenged: \($0.assumptionChallenged)" }.joined(separator: "\n"))

                Evidence Flow: \(trace.evidenceFlow.joined(separator: " → "))

                Escalation: \(trace.escalation)

                Resolution: \(trace.resolution)

                Narrator Role: \(trace.narratorRole)

                """
            }
        }

        // Add transcripts
        output += """

        ═══════════════════════════════════════════════════════════════
        TRANSCRIPTS (Exemplar Videos)
        ═══════════════════════════════════════════════════════════════

        """

        for video in exemplarsWithTranscript {
            let transcriptPreview = String(video.transcript?.prefix(5000) ?? "")
            let wasTruncated = (video.transcript?.count ?? 0) > 5000

            output += """

            ───────────────────────────────────────────────────────────────
            VIDEO: \(video.title)
            ID: \(video.videoId)
            Duration: \(video.duration)
            ───────────────────────────────────────────────────────────────

            \(transcriptPreview)\(wasTruncated ? "\n\n[...TRUNCATED - full transcript is \(video.transcript?.count ?? 0) chars...]" : "")

            """
        }

        // Add current prompt if exists
        if let currentPrompt = template.a1aSystemPrompt, !currentPrompt.isEmpty {
            output += """

            ═══════════════════════════════════════════════════════════════
            CURRENT A1a PROMPT
            ═══════════════════════════════════════════════════════════════

            \(currentPrompt)

            """

            if let lastTested = template.a1aLastTestedAt {
                output += "Last Tested: \(lastTested.formatted())\n"
            }
            if let stability = template.a1aStabilityScore {
                output += "Stability Score: \(String(format: "%.0f%%", stability * 100))\n"
            }
        }

        output += """

        ═══════════════════════════════════════════════════════════════
        YOUR TASK
        ═══════════════════════════════════════════════════════════════

        Develop an A1a extraction prompt that:
        1. Extracts sections with roles, timestamps, and key quotes
        2. Identifies the "logic spine" (core argument flow)
        3. Captures bridge points (transitions between sections)
        4. Produces consistent, stable output across multiple runs

        The prompt should be SPECIFIC to this template's structure.
        Use the Phase 0 execution traces to understand what makes this
        template unique.

        When done, paste the prompt back into the workbench and run
        fidelity tests to verify stability.
        """

        UIPasteboard.general.string = output
        showCopySuccess("Copied all context to clipboard")
    }

    private func copyTaxonomy() {
        var output = """
        TEMPLATE: \(template.name)
        ID: \(template.id)

        Description:
        \(template.description)

        Classification Criteria:
        - Required Signals: \(template.classificationCriteria.requiredSignals.joined(separator: ", "))
        - Anti Signals: \(template.classificationCriteria.antiSignals.joined(separator: ", "))

        Exemplar Video IDs:
        \(template.exemplarVideoIds.joined(separator: "\n"))
        """

        UIPasteboard.general.string = output
        showCopySuccess("Copied taxonomy")
    }

    private func copyPhase0Data() {
        var output = "PHASE 0 EXECUTION TRACES\n\n"

        for video in exemplarsWithPhase0 {
            if let phase0 = video.phase0Result, let trace = phase0.executionTrace {
                output += """
                ═══════════════════════════════════════════════════════════════
                \(video.title)
                ═══════════════════════════════════════════════════════════════

                Opening:
                  Hook Type: \(trace.opening.hookType)
                  Duration: \(trace.opening.durationSeconds)s
                  What Happens: \(trace.opening.whatHappens)

                Pivots (\(trace.pivots.count)):
                \(trace.pivots.map { "  [\($0.timestampPercent)%] \($0.triggerMoment)" }.joined(separator: "\n"))

                Evidence Flow: \(trace.evidenceFlow.joined(separator: " → "))
                Escalation: \(trace.escalation)
                Resolution: \(trace.resolution)
                Narrator Role: \(trace.narratorRole)


                """
            }
        }

        if exemplarsWithPhase0.isEmpty {
            output += "No exemplar videos have Phase 0 results yet."
        }

        UIPasteboard.general.string = output
        showCopySuccess("Copied \(exemplarsWithPhase0.count) Phase 0 results")
    }

    private func copyTranscripts() {
        var output = "TRANSCRIPTS\n\n"

        for video in exemplarsWithTranscript {
            output += """
            ═══════════════════════════════════════════════════════════════
            \(video.title)
            Duration: \(video.duration)
            ═══════════════════════════════════════════════════════════════

            \(video.transcript ?? "")


            """
        }

        if exemplarsWithTranscript.isEmpty {
            output += "No exemplar videos have transcripts yet."
        }

        UIPasteboard.general.string = output
        showCopySuccess("Copied \(exemplarsWithTranscript.count) transcripts")
    }

    private func copyCurrentPrompt() {
        if let prompt = template.a1aSystemPrompt, !prompt.isEmpty {
            UIPasteboard.general.string = prompt
            showCopySuccess("Copied current A1a prompt")
        } else {
            showCopySuccess("No prompt saved yet")
        }
    }

    private func copyRoleVocabulary() {
        if let roles = template.roleVocabulary, !roles.isEmpty {
            let output = """
            ROLE VOCABULARY

            Allowed section roles for this template:
            \(roles.map { "- \($0)" }.joined(separator: "\n"))
            """
            UIPasteboard.general.string = output
            showCopySuccess("Copied role vocabulary")
        }
    }

    private func copyBaselineA1aPrompt() {
        // Copy the canonical A1a prompt from SectionPromptEngine
        // This gives users the baseline to customize from
        let output = """
        ════════════════════════════════════════════════════════════════
        BASELINE A1a PROMPT (from SectionPromptEngine)
        ════════════════════════════════════════════════════════════════

        This is the canonical A1a prompt structure. When building template-specific
        prompts, you should:

        1. KEEP the output format exactly as specified below
        2. CUSTOMIZE the role definitions and rules for your template
        3. ADD template-specific signals and patterns to look for

        The full baseline prompt is ~470 lines. Key sections:

        - OUTPUT FORMAT: JSON ONLY (strict)
        - BOUNDARY IDENTIFICATION: Uses sentence numbers [1], [2], etc.
        - SECTION ROLE DEFINITIONS: HOOK, SETUP, EVIDENCE, TURN, PAYOFF, CTA, SPONSORSHIP
        - STRUCTURAL RULES: 3-8 sections, exactly ONE TURN
        - EXTRACTION INSTRUCTIONS: videoSummary, sections, logicSpine, bridgePoints

        ════════════════════════════════════════════════════════════════
        REQUIRED OUTPUT FORMAT (DO NOT CHANGE)
        ════════════════════════════════════════════════════════════════

        {
          "videoSummary": "2-4 sentence prose summary",
          "sections": [
            {
              "id": "sect_1",
              "boundarySentence": 12,
              "role": "HOOK",
              "goal": "Generate curiosity about...",
              "logicSpineStep": "Claims that X causes Y"
            },
            {
              "id": "sect_2",
              "boundarySentence": null,
              "role": "PAYOFF",
              "goal": "...",
              "logicSpineStep": "..."
            }
          ],
          "logicSpine": {
            "chain": ["HOOK claims X", "SETUP introduces Y"],
            "causalLinks": [
              {
                "from": "sect_1",
                "to": "sect_2",
                "connection": "HOOK leads into context"
              }
            ]
          },
          "bridgePoints": [
            {
              "text": "Exact bridge sentence from transcript",
              "belongsTo": ["sect_1", "sect_2"]
            }
          ]
        }

        ════════════════════════════════════════════════════════════════
        FIELD DEFINITIONS
        ════════════════════════════════════════════════════════════════

        sections[].id: "sect_1", "sect_2", etc. (sequential)
        sections[].boundarySentence: Integer sentence number where section ENDS (null for last section)
        sections[].role: HOOK | SETUP | EVIDENCE | TURN | PAYOFF | CTA | SPONSORSHIP
        sections[].goal: What this section accomplishes
        sections[].logicSpineStep: One sentence describing this step in the argument

        logicSpine.chain: Array of STRINGS (not objects) describing argument progression
        logicSpine.causalLinks: Array of {from, to, connection} linking section IDs

        bridgePoints[].text: EXACT quote from transcript
        bridgePoints[].belongsTo: Array of section IDs this bridges

        ════════════════════════════════════════════════════════════════
        WHAT YOU CAN CUSTOMIZE
        ════════════════════════════════════════════════════════════════

        ✓ Role definitions (what HOOK/SETUP/EVIDENCE/TURN/PAYOFF mean for this template)
        ✓ Structural rules (e.g., "this template typically has 2 EVIDENCE sections")
        ✓ Signals to look for (e.g., "mystery-reveal templates start with a question")
        ✓ Tie-breaker rules for ambiguous boundaries

        ✗ DO NOT change the JSON field names
        ✗ DO NOT add new fields
        ✗ DO NOT change boundarySentence to timestamps
        ✗ DO NOT change belongsTo to connectsSections

        ════════════════════════════════════════════════════════════════

        To get the FULL baseline prompt (~470 lines), see:
        SectionPromptEngine.swift → generatePrompt()
        """

        UIPasteboard.general.string = output
        showCopySuccess("Copied baseline A1a reference")
    }

    private func copyNumberedTranscript(video: YouTubeVideo) {
        guard let transcript = video.transcript else {
            showCopySuccess("No transcript available")
            return
        }

        // Parse into sentences using the same logic as SectionPromptEngine
        let sentences = SentenceParser.parse(transcript)

        var output = """
        ════════════════════════════════════════════════════════════════
        NUMBERED TRANSCRIPT
        ════════════════════════════════════════════════════════════════

        Video: \(video.title)
        Duration: \(video.duration)
        Total Sentences: \(sentences.count)
        Total Characters: \(transcript.count)

        ════════════════════════════════════════════════════════════════
        SENTENCES (use these numbers for boundarySentence)
        ════════════════════════════════════════════════════════════════

        """

        for (index, sentence) in sentences.enumerated() {
            output += "[\(index + 1)] \(sentence)\n\n"
        }

        UIPasteboard.general.string = output
        showCopySuccess("Copied \(sentences.count) numbered sentences")
    }

    private func copyVideoContext(video: YouTubeVideo) {
        guard let transcript = video.transcript else {
            showCopySuccess("No transcript available")
            return
        }

        let sentences = SentenceParser.parse(transcript)

        var output = """
        ════════════════════════════════════════════════════════════════
        FULL VIDEO CONTEXT FOR A1a TESTING
        ════════════════════════════════════════════════════════════════

        Video: \(video.title)
        Video ID: \(video.videoId)
        Duration: \(video.duration)
        Total Sentences: \(sentences.count)

        """

        // Add Phase 0 if available
        if let phase0 = video.phase0Result, let trace = phase0.executionTrace {
            output += """

            ════════════════════════════════════════════════════════════════
            PHASE 0 EXECUTION TRACE
            ════════════════════════════════════════════════════════════════

            Opening:
              Hook Type: \(trace.opening.hookType)
              Duration: \(trace.opening.durationSeconds)s
              What Happens: \(trace.opening.whatHappens)

            Pivots (\(trace.pivots.count)):
            \(trace.pivots.map { "  [\($0.timestampPercent)%] \($0.triggerMoment)" }.joined(separator: "\n"))

            Evidence Flow: \(trace.evidenceFlow.joined(separator: " → "))
            Escalation: \(trace.escalation)
            Resolution: \(trace.resolution)
            Narrator Role: \(trace.narratorRole)

            """
        }

        output += """

        ════════════════════════════════════════════════════════════════
        NUMBERED TRANSCRIPT
        ════════════════════════════════════════════════════════════════

        """

        for (index, sentence) in sentences.enumerated() {
            output += "[\(index + 1)] \(sentence)\n\n"
        }

        UIPasteboard.general.string = output
        showCopySuccess("Copied full context with \(sentences.count) sentences")
    }

    private func copyOutputFormatReference() {
        let output = """
        ════════════════════════════════════════════════════════════════
        A1a OUTPUT FORMAT REFERENCE (CANONICAL)
        ════════════════════════════════════════════════════════════════

        Your custom A1a prompt MUST produce JSON matching this exact schema.
        Downstream parsing code expects these exact field names.

        {
          "videoSummary": "string (2-4 sentences)",

          "sections": [
            {
              "id": "sect_1",              // REQUIRED: "sect_1", "sect_2", etc.
              "boundarySentence": 12,       // REQUIRED: int (sentence number) or null for last
              "role": "HOOK",               // REQUIRED: HOOK|SETUP|EVIDENCE|TURN|PAYOFF|CTA|SPONSORSHIP
              "goal": "string",             // REQUIRED: what section accomplishes
              "logicSpineStep": "string"    // REQUIRED: one sentence argument step
            }
          ],

          "logicSpine": {
            "chain": ["string", "string"],  // REQUIRED: array of STRINGS (not objects!)
            "causalLinks": [
              {
                "from": "sect_1",           // REQUIRED: section id
                "to": "sect_2",             // REQUIRED: section id
                "connection": "string"      // REQUIRED: how they connect
              }
            ]
          },

          "bridgePoints": [
            {
              "text": "exact quote",         // REQUIRED: exact transcript text
              "belongsTo": ["sect_1", "sect_2"]  // REQUIRED: array of section ids
            }
          ]
        }

        ════════════════════════════════════════════════════════════════
        COMMON MISTAKES TO AVOID
        ════════════════════════════════════════════════════════════════

        ❌ "sectionId" instead of "id"
        ❌ "startTime"/"endTime" instead of "boundarySentence"
        ❌ "keyQuote" (not in schema)
        ❌ chain as objects instead of strings
        ❌ "coreArgument" in logicSpine (not in schema)
        ❌ "connectsSections" instead of "belongsTo"
        ❌ "function" in bridgePoints (not in schema)

        ════════════════════════════════════════════════════════════════
        """

        UIPasteboard.general.string = output
        showCopySuccess("Copied output format reference")
    }

    // MARK: - Fidelity Testing

    private func runFidelityTests() async {
        guard canRunFidelity, let video = selectedTestVideo else { return }

        await MainActor.run {
            isRunningFidelity = true
            fidelityCurrentRun = 0
            fidelityResults = []
            fidelityError = nil
        }

        let totalRuns = fidelityRunCount
        var allResults: [A1aWorkbenchFidelityResult] = []
        var completedCount = 0

        // Run all tests on the SINGLE selected video in parallel
        await withTaskGroup(of: A1aWorkbenchFidelityResult?.self) { group in
            for runNum in 1...fidelityRunCount {
                group.addTask {
                    let start = Date()

                    do {
                        // Run A1a extraction with the editing prompt
                        let result = try await self.runA1aExtraction(
                            video: video,
                            prompt: self.editingPrompt,
                            temperature: self.fidelityTemperature
                        )

                        let end = Date()

                        return A1aWorkbenchFidelityResult(
                            runNumber: runNum,
                            videoId: video.videoId,
                            videoTitle: video.title,
                            sectionCount: result.sectionCount,
                            roles: result.roles,
                            logicSpineLength: result.logicSpineLength,
                            bridgePointCount: result.bridgePointCount,
                            startedAt: start,
                            completedAt: end,
                            error: nil
                        )
                    } catch {
                        return A1aWorkbenchFidelityResult(
                            runNumber: runNum,
                            videoId: video.videoId,
                            videoTitle: video.title,
                            sectionCount: 0,
                            roles: [],
                            logicSpineLength: 0,
                            bridgePointCount: 0,
                            startedAt: start,
                            completedAt: Date(),
                            error: error.localizedDescription
                        )
                    }
                }
            }

            for await result in group {
                if let result = result {
                    allResults.append(result)
                    completedCount += 1

                    await MainActor.run {
                        fidelityCurrentRun = completedCount
                    }
                }
            }
        }

        await MainActor.run {
            fidelityResults = allResults.sorted { $0.runNumber < $1.runNumber }
            isRunningFidelity = false

            if allResults.count < totalRuns {
                fidelityError = "Only \(allResults.count)/\(totalRuns) runs succeeded"
            }
        }
    }

    // Stub for A1a extraction - this would call the actual A1a service
    private func runA1aExtraction(video: YouTubeVideo, prompt: String, temperature: Double) async throws -> A1aExtractionResult {
        // TODO: Implement actual A1a extraction call
        // For now, return mock data for structure testing

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let fullPrompt = """
        \(prompt)

        VIDEO TITLE: \(video.title)
        VIDEO DURATION: \(video.duration)

        TRANSCRIPT:
        \(String(video.transcript?.prefix(15000) ?? ""))
        """

        let systemPrompt = """
        You are extracting structural sections from a YouTube video transcript.
        Follow the provided prompt exactly and return valid JSON.
        """

        let response = await adapter.generate_response(
            prompt: fullPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 4000]
        )

        // Parse the response to extract metrics
        // This is simplified - actual implementation would parse the full A1a output
        let sectionCount = response.components(separatedBy: "\"role\"").count - 1
        let roles = extractRoles(from: response)

        return A1aExtractionResult(
            sectionCount: max(sectionCount, 1),
            roles: roles,
            logicSpineLength: response.contains("logic_spine") ? 5 : 0,
            bridgePointCount: response.components(separatedBy: "bridge").count - 1
        )
    }

    private func extractRoles(from response: String) -> [String] {
        // Simple extraction of role values from JSON response
        var roles: [String] = []
        let pattern = #"\"role\"\s*:\s*\"([^\"]+)\""#

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(response.startIndex..., in: response)
            let matches = regex.matches(in: response, range: range)

            for match in matches {
                if let roleRange = Range(match.range(at: 1), in: response) {
                    roles.append(String(response[roleRange]))
                }
            }
        }

        return roles
    }

    // MARK: - Stability Calculations

    private func calculateOverallStability() -> Double {
        let sectionStability = calculateSectionCountStability()
        let roleStability = calculateRoleStability()
        let logicStability = calculateLogicSpineStability()

        return (sectionStability + roleStability + logicStability) / 3.0
    }

    private func calculateSectionCountStability() -> Double {
        let successfulResults = fidelityResults.filter { $0.error == nil }
        guard !successfulResults.isEmpty else { return 0 }

        let counts = successfulResults.map { $0.sectionCount }
        let countFreq = Dictionary(grouping: counts, by: { $0 }).mapValues { $0.count }
        let maxFreq = countFreq.values.max() ?? 0

        return Double(maxFreq) / Double(successfulResults.count)
    }

    private func calculateRoleStability() -> Double {
        let successfulResults = fidelityResults.filter { $0.error == nil }
        guard !successfulResults.isEmpty else { return 0 }

        // Compare role sequences
        let roleSequences = successfulResults.map { $0.roles.joined(separator: ",") }
        let seqFreq = Dictionary(grouping: roleSequences, by: { $0 }).mapValues { $0.count }
        let maxFreq = seqFreq.values.max() ?? 0

        return Double(maxFreq) / Double(successfulResults.count)
    }

    private func calculateLogicSpineStability() -> Double {
        let successfulResults = fidelityResults.filter { $0.error == nil }
        guard !successfulResults.isEmpty else { return 0 }

        let lengths = successfulResults.map { $0.logicSpineLength }
        let lengthFreq = Dictionary(grouping: lengths, by: { $0 }).mapValues { $0.count }
        let maxFreq = lengthFreq.values.max() ?? 0

        return Double(maxFreq) / Double(successfulResults.count)
    }

    // MARK: - Copy Results Functions

    private func copyFidelityResults() {
        let stability = calculateOverallStability()

        var output = """
        A1a FIDELITY TEST RESULTS

        Template: \(template.name)
        Total Runs: \(fidelityResults.count)
        Temperature: \(String(format: "%.1f", fidelityTemperature))

        ═══════════════════════════════════════════════════════════════
        STABILITY SCORES
        ═══════════════════════════════════════════════════════════════

        Overall: \(String(format: "%.0f%%", stability * 100))
        Section Count: \(String(format: "%.0f%%", calculateSectionCountStability() * 100))
        Role Distribution: \(String(format: "%.0f%%", calculateRoleStability() * 100))
        Logic Spine: \(String(format: "%.0f%%", calculateLogicSpineStability() * 100))

        """

        // Group by video
        let videoGroups = Dictionary(grouping: fidelityResults, by: { $0.videoId })

        for (videoId, runs) in videoGroups.sorted(by: { $0.key < $1.key }) {
            let videoTitle = runs.first?.videoTitle ?? videoId
            let successfulRuns = runs.filter { $0.error == nil }

            output += """

            ───────────────────────────────────────────────────────────────
            \(videoTitle)
            ───────────────────────────────────────────────────────────────

            """

            for run in successfulRuns.sorted(by: { $0.runNumber < $1.runNumber }) {
                output += "Run \(run.runNumber): \(run.sectionCount) sections, roles: \(run.roles.joined(separator: ", "))\n"
            }
        }

        UIPasteboard.general.string = output
        showCopySuccess("Copied fidelity results")
    }

    private func copyFidelityDebug() {
        var output = """
        A1a FIDELITY DEBUG OUTPUT

        Template: \(template.name)
        Creator: \(channel.name)

        ═══════════════════════════════════════════════════════════════
        TEST CONFIGURATION
        ═══════════════════════════════════════════════════════════════

        Runs per video: \(fidelityRunCount)
        Temperature: \(String(format: "%.1f", fidelityTemperature))
        Videos tested: \(exemplarsWithTranscript.count)
        Total runs: \(fidelityResults.count)

        ═══════════════════════════════════════════════════════════════
        PROMPT UNDER TEST
        ═══════════════════════════════════════════════════════════════

        \(editingPrompt)

        ═══════════════════════════════════════════════════════════════
        STABILITY ANALYSIS
        ═══════════════════════════════════════════════════════════════

        Overall: \(String(format: "%.0f%%", calculateOverallStability() * 100))
        Section Count: \(String(format: "%.0f%%", calculateSectionCountStability() * 100))
        Role Distribution: \(String(format: "%.0f%%", calculateRoleStability() * 100))
        Logic Spine: \(String(format: "%.0f%%", calculateLogicSpineStability() * 100))

        ═══════════════════════════════════════════════════════════════
        RAW RUN DATA
        ═══════════════════════════════════════════════════════════════

        """

        for result in fidelityResults.sorted(by: { ($0.videoId, $0.runNumber) < ($1.videoId, $1.runNumber) }) {
            output += """

            Video: \(result.videoTitle)
            Run: \(result.runNumber)
            Duration: \(String(format: "%.2fs", result.durationSeconds))
            Sections: \(result.sectionCount)
            Roles: \(result.roles.joined(separator: ", "))
            Logic Spine Length: \(result.logicSpineLength)
            Bridge Points: \(result.bridgePointCount)
            \(result.error != nil ? "ERROR: \(result.error!)" : "")

            """
        }

        UIPasteboard.general.string = output
        showCopySuccess("Copied debug output")
    }

    // MARK: - Save Functions

    private func savePromptToTemplate() async {
        await MainActor.run {
            isSaving = true
            saveError = nil
            showSaveSuccess = false
        }

        do {
            // Calculate stability if we have results
            let stability = fidelityResults.isEmpty ? nil : calculateOverallStability()

            // Update template in Firebase
            try await updateTemplateA1aPrompt(
                channelId: channel.channelId,
                templateId: template.id,
                prompt: editingPrompt,
                stability: stability
            )

            await MainActor.run {
                isSaving = false
                hasUnsavedChanges = false
                showSaveSuccess = true
            }

            // Hide success message after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showSaveSuccess = false
            }

        } catch {
            await MainActor.run {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }

    private func updateTemplateA1aPrompt(channelId: String, templateId: String, prompt: String, stability: Double?) async throws {
        // Load current taxonomy
        guard var taxonomy = try await YouTubeFirebaseService.shared.getLockedTaxonomy(forChannel: channelId) else {
            throw NSError(domain: "A1aWorkbench", code: 404, userInfo: [NSLocalizedDescriptionKey: "No locked taxonomy found"])
        }

        // Find and update the template
        guard let index = taxonomy.templates.firstIndex(where: { $0.id == templateId }) else {
            throw NSError(domain: "A1aWorkbench", code: 404, userInfo: [NSLocalizedDescriptionKey: "Template not found in taxonomy"])
        }

        // Update the template's A1a prompt fields
        taxonomy.templates[index].a1aSystemPrompt = prompt
        taxonomy.templates[index].a1aLastTestedAt = stability != nil ? Date() : taxonomy.templates[index].a1aLastTestedAt
        taxonomy.templates[index].a1aStabilityScore = stability ?? taxonomy.templates[index].a1aStabilityScore

        // Update taxonomy timestamp
        taxonomy = LockedTaxonomy(
            channelId: taxonomy.channelId,
            templates: taxonomy.templates,
            createdAt: taxonomy.createdAt,
            updatedAt: Date(),
            lockedAt: taxonomy.lockedAt
        )

        // Save back to Firebase
        try await YouTubeFirebaseService.shared.saveLockedTaxonomy(taxonomy, forChannel: channelId)

        print("✅ Saved A1a prompt for template \(templateId)")
        print("   Prompt length: \(prompt.count) chars")
        print("   Stability: \(stability.map { String(format: "%.0f%%", $0 * 100) } ?? "not tested")")
    }
}

// MARK: - Supporting Models

struct A1aWorkbenchFidelityResult: Identifiable {
    let id = UUID()
    let runNumber: Int
    let videoId: String
    let videoTitle: String
    let sectionCount: Int
    let roles: [String]
    let logicSpineLength: Int
    let bridgePointCount: Int
    let startedAt: Date
    let completedAt: Date
    let error: String?

    var durationSeconds: Double {
        completedAt.timeIntervalSince(startedAt)
    }

    var rolesSummary: String {
        let roleFreq = Dictionary(grouping: roles, by: { $0 }).mapValues { $0.count }
        return roleFreq.map { "\($0.key):\($0.value)" }.joined(separator: ", ")
    }
}

struct A1aExtractionResult {
    let sectionCount: Int
    let roles: [String]
    let logicSpineLength: Int
    let bridgePointCount: Int
}
