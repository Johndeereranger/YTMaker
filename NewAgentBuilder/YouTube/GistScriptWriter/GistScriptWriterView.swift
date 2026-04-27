//
//  GistScriptWriterView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/29/26.
//

import SwiftUI

struct GistScriptWriterView: View {
    @StateObject private var coordinator = GistScriptWriterCoordinator()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("View", selection: $selectedTab) {
                Text("Input").tag(0)
                Text("Gists (\(coordinator.ramblingGists.count))").tag(1)
                Text("Search").tag(2)
                Text("Matches").tag(3)
                Text("Fidelity").tag(4)
                Text("Versions").tag(5)
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab content
            TabView(selection: $selectedTab) {
                inputView.tag(0)
                gistsReviewView.tag(1)
                manualSearchView.tag(2)
                matchResultsView.tag(3)
                fidelityTestView.tag(4)
                promptVersionsView.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Gist Script Writer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("New Session") {
                        coordinator.newSession()
                    }
                    Button("Clear All") {
                        coordinator.clearSession()
                    }
                    Divider()
                    Button {
                        coordinator.expandAll()
                    } label: {
                        Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    Button {
                        coordinator.collapseAll()
                    } label: {
                        Label("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    MenuCopyButton(
                        text: coordinator.exportAllAsText(),
                        label: "Copy All Results",
                        systemImage: "doc.on.doc.fill"
                    )
                    MenuCopyButton(
                        text: coordinator.currentSession.exportGistsAsText(),
                        label: "Copy Gists Only",
                        systemImage: "doc.on.doc"
                    )
                    if !coordinator.fidelityTests.isEmpty {
                        MenuCopyButton(
                            text: coordinator.exportFidelityTestsAsText(),
                            label: "Copy Fidelity Results",
                            systemImage: "chart.bar.doc.horizontal"
                        )
                    }
                    if !coordinator.promptVersions.isEmpty {
                        MenuCopyButton(
                            text: coordinator.exportAllVersionsAsText(),
                            label: "Copy Prompt Versions",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .overlay {
            if coordinator.isProcessing {
                processingOverlay
            }
        }
        .alert("Error", isPresented: .constant(coordinator.errorMessage != nil)) {
            Button("OK") { coordinator.errorMessage = nil }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
    }

    // MARK: - Input View

    private var inputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste Your Rambling")
                        .font(.headline)
                    Text("Paste your raw notes, ideas, or rambling text below. The AI will extract structural chunks and generate gists for matching against Johnny's video corpus.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Text input
                TextEditor(text: Binding(
                    get: { coordinator.currentSession.rawRamblingText },
                    set: { coordinator.updateRamblingText($0) }
                ))
                .frame(minHeight: 300)
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

                // Word count
                HStack {
                    Text("\(coordinator.currentSession.rawRamblingText.split(separator: " ").count) words")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if !coordinator.currentSession.rawRamblingText.isEmpty {
                        Button("Clear") {
                            coordinator.updateRamblingText("")
                        }
                        .font(.caption)
                    }
                }

                // Extract button
                Button {
                    Task {
                        await coordinator.extractGistsFromRambling()
                        selectedTab = 1
                    }
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Extract Gists")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.currentSession.rawRamblingText.isEmpty || coordinator.isProcessing)

                // Session info
                if !coordinator.ramblingGists.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Previous Session")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("\(coordinator.ramblingGists.count) gists extracted")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("View Gists →") {
                            selectedTab = 1
                        }
                        .font(.caption)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    // MARK: - Gists Review View

    private var gistsReviewView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if coordinator.ramblingGists.isEmpty {
                    emptyStateView(
                        icon: "doc.text.magnifyingglass",
                        title: "No Gists Yet",
                        message: "Extract gists from your rambling text first."
                    )
                } else {
                    ForEach(coordinator.ramblingGists) { gist in
                        RamblingGistCard(
                            gist: gist,
                            isExpanded: coordinator.expandedGistIds.contains(gist.id),
                            onToggleExpand: { coordinator.toggleGistExpansion(gist.id) },
                            onFindMatches: {
                                Task {
                                    let matches = await coordinator.searchForSimilar(to: gist)
                                    coordinator.matchResults[gist.id] = matches
                                    selectedTab = 3
                                }
                            },
                            onSearchMore: {
                                coordinator.searchContextGist = gist
                                selectedTab = 2
                            }
                        )
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Manual Search View

    private var manualSearchView: some View {
        VStack(spacing: 0) {
            // Search context banner
            if let contextGist = coordinator.searchContextGist {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Searching for matches")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Gist #\(contextGist.chunkIndex + 1): \(contextGist.gistB.premise)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        coordinator.searchQuery = contextGist.gistB.premise
                        coordinator.searchJohnnyGists()
                    } label: {
                        Label("Apply", systemImage: "text.insert")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }

                    Button {
                        coordinator.searchContextGist = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .background(Color.blue)
            }

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search Johnny's gists...", text: $coordinator.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        coordinator.searchJohnnyGists()
                    }
                if !coordinator.searchQuery.isEmpty {
                    Button {
                        coordinator.searchQuery = ""
                        coordinator.searchResults = []
                        coordinator.hasPerformedSearch = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                Button {
                    coordinator.searchJohnnyGists()
                } label: {
                    Text("Search")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.johnnyGistsLoaded)
            }
            .padding()
            .background(Color.primary.opacity(0.05))

            // Filters
            FiltersView(filters: $coordinator.searchFilters, onApply: {
                coordinator.searchJohnnyGists()
            })

            // Load corpus button if not loaded
            if !coordinator.johnnyGistsLoaded {
                VStack(spacing: 12) {
                    Text("Load Johnny's Gists")
                        .font(.headline)
                    Text("Load analyzed video gists from the corpus to enable matching.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task {
                            await coordinator.loadJohnnyGists()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Load Corpus")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(40)
            } else {
                // Results
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Text("\(coordinator.johnnyGists.count) Johnny gists loaded")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !coordinator.searchResults.isEmpty {
                            Text("\(coordinator.searchResults.count) results")
                                .font(.caption)
                                .fontWeight(.semibold)

                            ForEach(coordinator.searchResults) { gist in
                                JohnnyGistCard(
                                    gist: gist,
                                    onAddAsMatch: coordinator.searchContextGist != nil ? {
                                        if let contextGist = coordinator.searchContextGist {
                                            coordinator.addManualMatch(
                                                johnnyGist: gist,
                                                forRamblingGist: contextGist
                                            )
                                        }
                                    } : nil
                                )
                            }
                        } else if coordinator.hasPerformedSearch {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("No results found")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Try a different search term or adjust your filters.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(40)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Match Results View

    private var matchResultsView: some View {
        VStack(spacing: 0) {
            // Match type selector
            HStack {
                Text("Match Type:")
                    .font(.caption)
                Picker("Match Type", selection: $coordinator.selectedMatchType) {
                    ForEach(GistMatchType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    Task {
                        await coordinator.matchAllGists(matchType: coordinator.selectedMatchType)
                    }
                } label: {
                    Text("Match All")
                }
                .buttonStyle(.bordered)
                .disabled(!coordinator.johnnyGistsLoaded || coordinator.ramblingGists.isEmpty)
            }
            .padding()

            // Results
            ScrollView {
                LazyVStack(spacing: 16) {
                    if coordinator.matchResults.isEmpty {
                        emptyStateView(
                            icon: "arrow.triangle.2.circlepath",
                            title: "No Matches Yet",
                            message: "Run matching to find similar Johnny gists for your chunks."
                        )
                    } else {
                        ForEach(coordinator.ramblingGists) { gist in
                            if let matches = coordinator.matchResults[gist.id], !matches.isEmpty {
                                MatchResultCard(
                                    ramblingGist: gist,
                                    matches: matches,
                                    isExpanded: coordinator.expandedGistIds.contains(gist.id),
                                    onToggle: { coordinator.toggleGistExpansion(gist.id) }
                                )
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Fidelity Test View (Extraction Prompt Stability)

    private var fidelityTestView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Configuration Section
                extractionFidelityConfigSection

                // Progress Section (when running)
                if coordinator.isProcessing && coordinator.extractionFidelityCurrentRun > 0 {
                    extractionFidelityProgressSection
                }

                // Results Section
                if let result = coordinator.extractionFidelityResult {
                    extractionFidelityResultSection(result)
                } else if !coordinator.extractionFidelityRuns.isEmpty {
                    // Runs completed but no analysis yet
                    Text("Analyzing results...")
                        .foregroundColor(.secondary)
                } else if !coordinator.isProcessing {
                    emptyStateView(
                        icon: "testtube.2",
                        title: "No Fidelity Test Run",
                        message: "Test extraction prompt stability by running the same input multiple times."
                    )
                }

                // Run Details Section
                if !coordinator.extractionFidelityRuns.isEmpty {
                    extractionFidelityRunsSection
                }
            }
            .padding()
        }
    }

    // MARK: - Extraction Fidelity Config

    private var extractionFidelityConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extraction Fidelity Test")
                .font(.headline)

            Text("Test how stable the extraction prompt is by running it multiple times with the same input.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // Temperature
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f", coordinator.extractionFidelityTemperature))
                        .font(.subheadline.monospaced())
                        .foregroundColor(.blue)
                }
                Slider(value: $coordinator.extractionFidelityTemperature, in: 0.0...1.0, step: 0.05)

                HStack {
                    Text("0.0 (deterministic)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("1.0 (creative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Run Count
            HStack {
                Text("Number of Runs")
                    .font(.subheadline)
                Spacer()
                Stepper("\(coordinator.extractionFidelityRunCount)", value: $coordinator.extractionFidelityRunCount, in: 2...10)
                    .frame(width: 140)
            }

            Divider()

            // Actions
            HStack {
                Button {
                    Task {
                        await coordinator.runExtractionFidelityTest()
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run Fidelity Test")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.currentSession.rawRamblingText.isEmpty || coordinator.isProcessing)

                if coordinator.extractionFidelityResult != nil {
                    Button {
                        coordinator.clearExtractionFidelityResults()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if coordinator.currentSession.rawRamblingText.isEmpty {
                Text("Enter rambling text in the Input tab first")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Extraction Fidelity Progress

    private var extractionFidelityProgressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(coordinator.extractionFidelityCurrentRun),
                        total: Double(coordinator.extractionFidelityRunCount))

            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(coordinator.extractionFidelityStatus)
                    .font(.subheadline)
                Spacer()
                Text("\(coordinator.extractionFidelityCurrentRun)/\(coordinator.extractionFidelityRunCount)")
                    .font(.subheadline.monospaced())
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Extraction Fidelity Results

    private func extractionFidelityResultSection(_ result: ExtractionFidelityResult) -> some View {
        VStack(spacing: 16) {
            // Big Score
            VStack(spacing: 8) {
                Text("\(Int(result.stabilityScore * 100))%")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(stabilityScoreColor(result.stabilityScore))

                Text("Stability Score")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Quick stats
                HStack(spacing: 24) {
                    VStack {
                        Text("\(result.successfulRuns)")
                            .font(.title2.bold())
                        Text("Runs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    VStack {
                        Text(String(format: "%.2f", result.temperature))
                            .font(.title2.bold())
                        Text("Temp")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    VStack {
                        Text("\(result.inputWordCount)")
                            .font(.title2.bold())
                        Text("Words")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(stabilityScoreColor(result.stabilityScore).opacity(0.1))
            .cornerRadius(12)

            // Chunk Count Variance
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: result.chunkCountVariance.isStable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(result.chunkCountVariance.isStable ? .green : .orange)
                    Text("Chunk Count")
                        .font(.subheadline.bold())
                }

                Text(result.chunkCountVariance.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)

            // Divergences
            if !result.chunkBoundaryDivergences.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Boundary Divergences (\(result.chunkBoundaryDivergences.count))")
                            .font(.subheadline.bold())
                    }

                    ForEach(result.chunkBoundaryDivergences) { div in
                        HStack {
                            Text("Chunk \(div.chunkIndex + 1)")
                                .font(.caption.bold())
                            Spacer()
                            Text("±\(div.variance) words")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Move Variances
            if !result.moveVariances.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.purple)
                        Text("Move Label Variance (\(result.moveVariances.count))")
                            .font(.subheadline.bold())
                    }

                    ForEach(result.moveVariances) { mv in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chunk \(mv.chunkIndex + 1)")
                                .font(.caption.bold())
                            Text(mv.summaryText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }

            // Copy Results
            HStack {
                Spacer()
                FadeOutCopyButton(
                    text: coordinator.exportExtractionFidelityAsText(),
                    label: "Copy Results"
                )
            }
        }
    }

    // MARK: - Extraction Fidelity Runs Detail

    private var extractionFidelityRunsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run Details")
                .font(.subheadline.bold())

            ForEach(coordinator.extractionFidelityRuns) { run in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(run.gists, id: \.id) { gist in
                            HStack(alignment: .top) {
                                Text("[\(gist.chunkIndex + 1)]")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        if let move = gist.moveLabel {
                                            Text(move)
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.purple.opacity(0.2))
                                                .cornerRadius(4)
                                        }
                                        Text(gist.gistB.frame.rawValue)
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                    Text(gist.briefDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                CompactCopyButton(text: coordinator.exportRunGistAsText(gist))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.leading)
                    HStack {
                        Spacer()
                        CompactCopyButton(text: run.rawResponse)
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text("Run \(run.runNumber)")
                            .font(.caption.bold())
                        Spacer()
                        Text("\(run.chunkCount) chunks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", run.durationSeconds))s")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    private func stabilityScoreColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .orange }
        return .red
    }

    // MARK: - Prompt Versions View

    private var promptVersionsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Save Current Prompt Section
                saveVersionSection

                // Version History
                if coordinator.promptVersions.isEmpty {
                    emptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No Versions Saved",
                        message: "Save the current extraction prompt as a version to start tracking changes."
                    )
                } else {
                    versionHistorySection

                    // Comparison Section (only if 2+ versions)
                    if coordinator.promptVersions.count >= 2 {
                        versionComparisonSection
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Save Version Section

    private var saveVersionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Current Prompt")
                .font(.headline)

            Text("Snapshot the extraction prompt currently in code. Run a fidelity test first to attach stability scores.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // Version Label
            HStack {
                Text("Label")
                    .font(.subheadline)
                    .frame(width: 60, alignment: .leading)
                TextField("e.g. v1", text: $coordinator.newVersionLabel)
                    .textFieldStyle(.roundedBorder)
            }

            // Change Notes
            VStack(alignment: .leading, spacing: 4) {
                Text("What changed")
                    .font(.subheadline)
                TextField("e.g. Baseline prompt, Simplified frame definitions...", text: $coordinator.newVersionNotes)
                    .textFieldStyle(.roundedBorder)
            }

            // Status indicators
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: coordinator.extractionFidelityResult != nil ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(coordinator.extractionFidelityResult != nil ? .green : .secondary)
                    Text("Fidelity data")
                        .font(.caption)
                        .foregroundColor(coordinator.extractionFidelityResult != nil ? .primary : .secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: !coordinator.ramblingGists.isEmpty ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(!coordinator.ramblingGists.isEmpty ? .green : .secondary)
                    Text("Chunk count")
                        .font(.caption)
                        .foregroundColor(!coordinator.ramblingGists.isEmpty ? .primary : .secondary)
                }
            }

            Button {
                coordinator.saveCurrentAsVersion()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save as Version")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.newVersionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Version History Section

    private var versionHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Version History")
                    .font(.headline)
                Spacer()
                Text("\(coordinator.promptVersions.count) versions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(coordinator.promptVersions.sorted(by: { $0.createdAt > $1.createdAt })) { version in
                versionCard(version)
            }
        }
    }

    private func versionCard(_ version: PromptVersion) -> some View {
        let isExpanded = coordinator.expandedVersionIds.contains(version.id)

        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Version badge
                Text(version.versionLabel)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(version.changeNotes)
                        .font(.caption)
                        .lineLimit(isExpanded ? nil : 1)
                    Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Stability badge
                if let score = version.stabilityScore {
                    Text("\(Int(score * 100))%")
                        .font(.caption.bold().monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stabilityScoreColor(score).opacity(0.2))
                        .foregroundColor(stabilityScoreColor(score))
                        .cornerRadius(4)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Quick stats row
            HStack(spacing: 12) {
                Label("\(version.promptCharCount) chars", systemImage: "doc.text")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let chunks = version.chunkCountFromLastRun {
                    Label("\(chunks) chunks", systemImage: "rectangle.split.3x1")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Copy buttons
                CompactCopyButton(text: version.systemPromptText)
                FadeOutCopyButton(
                    text: coordinator.exportVersionSummaryAsText(version),
                    label: "Summary",
                    systemImage: "list.bullet"
                )
                FadeOutCopyButton(
                    text: coordinator.exportVersionAsText(version),
                    label: "Full Report",
                    systemImage: "doc.plaintext"
                )
            }

            // Expanded content
            if isExpanded {
                Divider()

                // System prompt preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt")
                        .font(.caption.bold())
                    ScrollView {
                        Text(version.systemPromptText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                }

                // Fidelity details if attached
                if let result = version.fidelityResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fidelity Results")
                            .font(.caption.bold())

                        HStack(spacing: 16) {
                            VStack {
                                Text("\(Int(result.stabilityScore * 100))%")
                                    .font(.title3.bold())
                                    .foregroundColor(stabilityScoreColor(result.stabilityScore))
                                Text("Stability")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            VStack {
                                Text("\(result.successfulRuns)")
                                    .font(.title3.bold())
                                Text("Runs")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            VStack {
                                Text(String(format: "%.2f", result.temperature))
                                    .font(.title3.bold())
                                Text("Temp")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text(result.chunkCountVariance.summaryText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                }

                // Individual runs if attached
                if let runs = version.fidelityRuns, !runs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Run Details")
                            .font(.caption.bold())

                        ForEach(runs) { run in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(run.gists, id: \.id) { gist in
                                        HStack(alignment: .top) {
                                            Text("[\(gist.chunkIndex + 1)]")
                                                .font(.caption2.monospaced())
                                                .foregroundColor(.secondary)
                                                .frame(width: 24, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 1) {
                                                HStack(spacing: 4) {
                                                    if let move = gist.moveLabel {
                                                        Text(move)
                                                            .font(.caption2)
                                                            .padding(.horizontal, 3)
                                                            .background(Color.purple.opacity(0.15))
                                                            .cornerRadius(3)
                                                    }
                                                    Text(gist.gistB.frame.rawValue)
                                                        .font(.caption2)
                                                        .padding(.horizontal, 3)
                                                        .background(Color.blue.opacity(0.15))
                                                        .cornerRadius(3)
                                                }
                                                Text(gist.briefDescription)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                            }
                                            Spacer()
                                            CompactCopyButton(text: coordinator.exportRunGistAsText(gist))
                                        }
                                    }
                                    HStack {
                                        Spacer()
                                        CompactCopyButton(text: run.rawResponse)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Run \(run.runNumber)")
                                        .font(.caption2.bold())
                                    Spacer()
                                    Text("\(run.chunkCount) chunks")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", run.durationSeconds))s")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                }

                // Delete button
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        coordinator.deletePromptVersion(id: version.id)
                    } label: {
                        Label("Delete Version", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                coordinator.toggleVersionExpansion(version.id)
            }
        }
    }

    // MARK: - Version Comparison Section

    private var versionComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare Versions")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version A")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Version A", selection: $coordinator.selectedVersionAId) {
                        Text("Select...").tag(nil as UUID?)
                        ForEach(coordinator.promptVersions.sorted(by: { $0.createdAt < $1.createdAt })) { v in
                            Text(v.versionLabel).tag(v.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Version B")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Version B", selection: $coordinator.selectedVersionBId) {
                        Text("Select...").tag(nil as UUID?)
                        ForEach(coordinator.promptVersions.sorted(by: { $0.createdAt < $1.createdAt })) { v in
                            Text(v.versionLabel).tag(v.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if let comparison = coordinator.compareSelectedVersions() {
                Divider()

                // Delta cards
                HStack(spacing: 12) {
                    // Stability delta
                    VStack(spacing: 4) {
                        if let delta = comparison.stabilityDelta {
                            HStack(spacing: 2) {
                                Image(systemName: delta > 0 ? "arrow.up" : (delta < 0 ? "arrow.down" : "minus"))
                                    .foregroundColor(delta > 0 ? .green : (delta < 0 ? .red : .secondary))
                                Text("\(Int(abs(delta) * 100))%")
                                    .font(.title3.bold())
                                    .foregroundColor(delta > 0 ? .green : (delta < 0 ? .red : .secondary))
                            }
                        } else {
                            Text("—")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        Text("Stability")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)

                    // Chunk count delta
                    VStack(spacing: 4) {
                        if let delta = comparison.chunkCountDelta {
                            Text("\(delta > 0 ? "+" : "")\(delta)")
                                .font(.title3.bold())
                                .foregroundColor(delta == 0 ? .secondary : .primary)
                        } else {
                            Text("—")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        Text("Chunks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)

                    // Prompt length delta
                    VStack(spacing: 4) {
                        Text("\(comparison.promptLengthDelta > 0 ? "+" : "")\(comparison.promptLengthDelta)")
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                        Text("Chars")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                }

                // Length breakdown
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("System Prompt:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(comparison.versionA.systemPromptText.count) → \(comparison.versionB.systemPromptText.count) chars")
                            .font(.caption.monospaced())
                    }
                    HStack {
                        Text("User Template:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(comparison.versionA.userPromptTemplate.count) → \(comparison.versionB.userPromptTemplate.count) chars")
                            .font(.caption.monospaced())
                    }
                }

                // Summary
                Text(comparison.summary)
                    .font(.subheadline.bold())
                    .foregroundColor(comparison.isImproved == true ? .green : (comparison.isImproved == false ? .red : .secondary))
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background((comparison.isImproved == true ? Color.green : (comparison.isImproved == false ? Color.red : Color.secondary)).opacity(0.1))
                    .cornerRadius(8)

                // Copy comparison
                HStack {
                    Spacer()
                    FadeOutCopyButton(
                        text: coordinator.exportVersionComparisonAsText(),
                        label: "Copy Comparison"
                    )
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(coordinator.processingMessage)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }

    // MARK: - Empty State

    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Rambling Gist Card

struct RamblingGistCard: View {
    let gist: RamblingGist
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onFindMatches: () -> Void
    let onSearchMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Chunk \(gist.chunkIndex + 1)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let label = gist.moveLabel {
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(4)
                }

                Spacer()

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }

            // Brief description
            Text(gist.briefDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            // Gist B premise (primary)
            Text(gist.gistB.premise)
                .font(.callout)

            // Action buttons (always visible)
            HStack(spacing: 8) {
                Button(action: onFindMatches) {
                    Label("Find Matches", systemImage: "magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: onSearchMore) {
                    Label("Search", systemImage: "text.magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                FadeOutCopyButton(
                    text: formatGistForCopy(gist),
                    label: "Copy"
                )
            }

            if isExpanded {
                Divider()

                // Full details
                VStack(alignment: .leading, spacing: 8) {
                    // Gist A
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GIST_A (Deterministic)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text("Subject: \(gist.gistA.subject.joined(separator: ", "))")
                            .font(.caption)
                        Text("Premise: \(gist.gistA.premise)")
                            .font(.caption)
                        Text("Frame: \(gist.gistA.frame.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    // Gist B
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GIST_B (Flexible)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text("Subject: \(gist.gistB.subject.joined(separator: ", "))")
                            .font(.caption)
                        Text("Premise: \(gist.gistB.premise)")
                            .font(.caption)
                        Text("Frame: \(gist.gistB.frame.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)

                    // Source text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SOURCE TEXT")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text(gist.sourceText)
                            .font(.caption)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)

                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    private func formatGistForCopy(_ gist: RamblingGist) -> String {
        """
        CHUNK \(gist.chunkIndex + 1)\(gist.moveLabel.map { " — \($0)" } ?? "")

        GIST_A:
        Subject: \(gist.gistA.subject.joined(separator: ", "))
        Premise: \(gist.gistA.premise)
        Frame: \(gist.gistA.frame.rawValue)

        GIST_B:
        Subject: \(gist.gistB.subject.joined(separator: ", "))
        Premise: \(gist.gistB.premise)
        Frame: \(gist.gistB.frame.rawValue)

        Brief: \(gist.briefDescription)

        SOURCE:
        \(gist.sourceText)
        """
    }
}

// MARK: - Johnny Gist Card

struct JohnnyGistCard: View {
    let gist: JohnnyGist
    var onAddAsMatch: (() -> Void)? = nil
    @State private var isExpanded = false
    @State private var wasAdded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gist.channelName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(gist.videoTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                }

                Spacer()

                Text("Chunk \(gist.chunkIndex + 1)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)

                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
            }

            // Move label
            HStack {
                Text(gist.moveLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)

                Text(gist.positionLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Gist premise
            Text(gist.gistB.premise)
                .font(.callout)

            // Use as Match button (when searching for a specific gist)
            if let onAddAsMatch = onAddAsMatch {
                Button {
                    onAddAsMatch()
                    wasAdded = true
                } label: {
                    Label(
                        wasAdded ? "Added" : "Use as Match",
                        systemImage: wasAdded ? "checkmark.circle.fill" : "plus.circle.fill"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(wasAdded ? .gray : .green)
                .disabled(wasAdded)
            }

            if isExpanded {
                Divider()

                // Full chunk text
                Text(gist.fullChunkText)
                    .font(.caption)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)

                HStack {
                    Spacer()
                    FadeOutCopyButton(
                        text: gist.fullChunkText,
                        label: "Copy Chunk"
                    )
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Match Result Card

struct MatchResultCard: View {
    let ramblingGist: RamblingGist
    let matches: [GistMatch]
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Your chunk header
            HStack {
                Text("Your Chunk \(ramblingGist.chunkIndex + 1)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(matches.count) matches")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
            }

            Text(ramblingGist.gistB.premise)
                .font(.caption)
                .foregroundColor(.secondary)

            // Top matches
            ForEach(Array(matches.prefix(isExpanded ? matches.count : 3).enumerated()), id: \.element.id) { index, match in
                MatchRow(match: match, rank: index + 1, showFull: isExpanded)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct MatchRow: View {
    let match: GistMatch
    let rank: Int
    let showFull: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Rank badge
                Text("#\(rank)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(scoreColor)
                    .clipShape(Circle())

                // Score
                Text("\(Int(match.similarityScore * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(scoreColor)

                // Channel
                Text(match.johnnyGist.channelName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if showFull {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
            }

            // Johnny's gist premise
            Text(match.johnnyGist.gistB.premise)
                .font(.caption)
                .lineLimit(isExpanded ? nil : 2)

            if isExpanded {
                // Full chunk text
                VStack(alignment: .leading, spacing: 4) {
                    Text("JOHNNY'S FULL CHUNK:")
                        .font(.caption2)
                        .fontWeight(.semibold)
                    Text(match.johnnyGist.fullChunkText)
                        .font(.caption)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

                HStack {
                    Text(match.johnnyGist.videoTitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    FadeOutCopyButton(
                        text: match.johnnyGist.fullChunkText,
                        label: "Copy"
                    )
                }
            }
        }
        .padding(8)
        .background(scoreColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var scoreColor: Color {
        if match.similarityScore >= 0.8 { return .green }
        if match.similarityScore >= 0.6 { return .orange }
        return .red
    }
}

// MARK: - Fidelity Test Result Card

struct FidelityTestResultCard: View {
    let test: GistFidelityTest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Test Run")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(test.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(test.successRate * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(test.successRate >= 0.7 ? .green : .orange)
            }

            HStack {
                Text("Match Type: \(test.matchType.rawValue)")
                    .font(.caption)
                Text("Top K: \(test.topK)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            // Results breakdown
            HStack(spacing: 16) {
                statBadge("Strong", value: test.strongMatches, total: test.totalGists, color: .green)
                statBadge("Moderate", value: test.moderateMatches, total: test.totalGists, color: .orange)
                statBadge("Weak", value: test.weakMatches, total: test.totalGists, color: .red)
                statBadge("None", value: test.noMatches, total: test.totalGists, color: .gray)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    private func statBadge(_ label: String, value: Int, total: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Fidelity Comparison Card

struct FidelityComparisonCard: View {
    let comparison: FidelityComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comparison")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                Image(systemName: comparison.isImproved ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(comparison.isImproved ? .green : .red)
                Text(comparison.summary)
                    .font(.caption)
            }

            if comparison.strongMatchDelta != 0 {
                Text("Strong matches: \(comparison.strongMatchDelta > 0 ? "+" : "")\(comparison.strongMatchDelta)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background((comparison.isImproved ? Color.green : Color.red).opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Filters View

struct FiltersView: View {
    @Binding var filters: GistSearchFilters
    let onApply: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filters")
                    if filters.isActive {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 12) {
                    // Move category filter
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Move Category")
                            .font(.caption2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(RhetoricalCategory.allCases, id: \.self) { category in
                                    FilterChip(
                                        label: category.rawValue,
                                        isSelected: filters.moveCategories.contains(category.rawValue),
                                        onTap: {
                                            if filters.moveCategories.contains(category.rawValue) {
                                                filters.moveCategories.remove(category.rawValue)
                                            } else {
                                                filters.moveCategories.insert(category.rawValue)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }

                    // Frame filter
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Frame")
                            .font(.caption2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(GistFrame.allCases, id: \.self) { frame in
                                    FilterChip(
                                        label: frame.displayName,
                                        isSelected: filters.frames.contains(frame),
                                        onTap: {
                                            if filters.frames.contains(frame) {
                                                filters.frames.remove(frame)
                                            } else {
                                                filters.frames.insert(frame)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }

                    HStack {
                        Button("Reset") {
                            filters.reset()
                        }
                        .font(.caption)

                        Spacer()

                        Button("Apply") {
                            onApply()
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.03))
            }
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color.primary.opacity(0.1))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    GistScriptWriterView()
}
