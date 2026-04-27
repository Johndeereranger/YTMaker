//
//  TemplateIterationComparisonView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import SwiftUI

// MARK: - Iteration History Model

struct PromptIteration: Identifiable, Codable {
    let id: String
    let version: Int
    let prompt: String
    let stabilityScore: Double?
    let testedAt: Date?
    let createdAt: Date

    init(version: Int, prompt: String, stabilityScore: Double? = nil, testedAt: Date? = nil, createdAt: Date = Date()) {
        self.id = "\(version)"
        self.version = version
        self.prompt = prompt
        self.stabilityScore = stabilityScore
        self.testedAt = testedAt
        self.createdAt = createdAt
    }
}

// MARK: - Comparison View

struct TemplateIterationComparisonView: View {
    let channel: YouTubeChannel
    let template: StyleTemplate

    @Environment(\.dismiss) private var dismiss

    @State private var iterations: [PromptIteration] = []
    @State private var selectedIterations: Set<Int> = []  // version numbers
    @State private var isLoading = true
    @State private var showingDiffView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with template info
                headerSection

                Divider()

                if isLoading {
                    ProgressView("Loading history...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if iterations.isEmpty {
                    emptyStateView
                } else {
                    iterationsContent
                }
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Compare") {
                        showingDiffView = true
                    }
                    .disabled(selectedIterations.count != 2)
                }
            }
            .task {
                await loadIterations()
            }
            .sheet(isPresented: $showingDiffView) {
                if let v1 = iterations.first(where: { selectedIterations.contains($0.version) }),
                   let v2 = iterations.last(where: { selectedIterations.contains($0.version) }),
                   v1.version != v2.version {
                    let earlier = v1.version < v2.version ? v1 : v2
                    let later = v1.version < v2.version ? v2 : v1
                    PromptDiffView(earlier: earlier, later: later)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name)
                .font(.headline)

            HStack(spacing: 16) {
                if template.hasA1aPrompt {
                    Label("Has Prompt", systemImage: "doc.text")
                }
                if let score = template.a1aStabilityScore {
                    Label("\(Int(score * 100))%", systemImage: "chart.bar")
                        .foregroundColor(scoreColor(score))
                }
                Label("\(iterations.count) versions", systemImage: "clock.arrow.circlepath")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if selectedIterations.count == 2 {
                Text("Tap 'Compare' to see differences")
                    .font(.caption)
                    .foregroundColor(.blue)
            } else if selectedIterations.count == 1 {
                Text("Select one more version to compare")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Select 2 versions to compare")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Version History")
                .font(.headline)

            Text("Previous prompt versions will appear here once you save multiple iterations.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Iterations Content

    private var iterationsContent: some View {
        VStack(spacing: 0) {
            // Stability Score Chart
            if hasStabilityData {
                stabilityChartSection
                Divider()
            }

            // Iterations List
            List {
                ForEach(iterations) { iteration in
                    iterationRow(iteration)
                }
            }
            .listStyle(.plain)
        }
    }

    private var hasStabilityData: Bool {
        iterations.contains { $0.stabilityScore != nil }
    }

    private var stabilityChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stability Trend")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            // Simple bar chart showing stability across versions
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(iterations) { iteration in
                    VStack(spacing: 4) {
                        if let score = iteration.stabilityScore {
                            Rectangle()
                                .fill(scoreColor(score))
                                .frame(width: 30, height: CGFloat(score * 60))

                            Text("\(Int(score * 100))%")
                                .font(.caption2)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 30, height: 10)

                            Text("--")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("v\(iteration.version)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 100)
            .padding(.vertical, 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private func iterationRow(_ iteration: PromptIteration) -> some View {
        let isSelected = selectedIterations.contains(iteration.version)

        return Button {
            toggleSelection(iteration.version)
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title3)

                // Version info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Version \(iteration.version)")
                            .font(.headline)
                    }

                    Text(iteration.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(iteration.prompt.count) characters")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Stability score
                if let score = iteration.stabilityScore {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(score * 100))%")
                            .font(.title3.bold())
                            .foregroundColor(scoreColor(score))
                        Text("stable")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("--")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("not tested")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.blue.opacity(0.1) : Color.clear)
    }

    // MARK: - Helpers

    private func toggleSelection(_ version: Int) {
        if selectedIterations.contains(version) {
            selectedIterations.remove(version)
        } else {
            if selectedIterations.count >= 2 {
                // Replace the first selected with new selection
                selectedIterations.removeFirst()
            }
            selectedIterations.insert(version)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .yellow }
        return .red
    }

    private func loadIterations() async {
        isLoading = true

        // For now, create iterations from current template state
        // In a full implementation, this would load from Firebase history
        var loadedIterations: [PromptIteration] = []

        // Add current version
        if let prompt = template.a1aSystemPrompt {
            loadedIterations.append(PromptIteration(
                version: 1,  // Version tracking removed
                prompt: prompt,
                stabilityScore: template.a1aStabilityScore,
                testedAt: template.a1aLastTestedAt,
                createdAt: Date()
            ))
        }

        // In production, load historical versions from Firebase:
        // let history = try await YouTubeFirebaseService.shared.loadTemplateHistory(
        //     channelId: channel.channelId,
        //     templateId: template.id
        // )

        iterations = loadedIterations.sorted { $0.version > $1.version }
        isLoading = false
    }
}

// MARK: - Prompt Diff View

struct PromptDiffView: View {
    let earlier: PromptIteration
    let later: PromptIteration

    @Environment(\.dismiss) private var dismiss
    @State private var diffMode: DiffMode = .sideBySide

    enum DiffMode: String, CaseIterable {
        case sideBySide = "Side by Side"
        case unified = "Unified"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("View Mode", selection: $diffMode) {
                    ForEach(DiffMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Score comparison
                scoreComparisonView

                Divider()

                // Diff content
                switch diffMode {
                case .sideBySide:
                    sideBySideView
                case .unified:
                    unifiedView
                }
            }
            .navigationTitle("v\(earlier.version) vs v\(later.version)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var scoreComparisonView: some View {
        HStack(spacing: 32) {
            // Earlier version
            VStack(spacing: 4) {
                Text("v\(earlier.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let score = earlier.stabilityScore {
                    Text("\(Int(score * 100))%")
                        .font(.title2.bold())
                        .foregroundColor(scoreColor(score))
                } else {
                    Text("--")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            // Arrow with change
            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(.secondary)

                if let e = earlier.stabilityScore, let l = later.stabilityScore {
                    let diff = Int((l - e) * 100)
                    Text(diff >= 0 ? "+\(diff)%" : "\(diff)%")
                        .font(.caption.bold())
                        .foregroundColor(diff >= 0 ? .green : .red)
                }
            }

            // Later version
            VStack(spacing: 4) {
                Text("v\(later.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let score = later.stabilityScore {
                    Text("\(Int(score * 100))%")
                        .font(.title2.bold())
                        .foregroundColor(scoreColor(score))
                } else {
                    Text("--")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private var sideBySideView: some View {
        HStack(spacing: 0) {
            // Earlier prompt
            VStack(alignment: .leading, spacing: 4) {
                Text("v\(earlier.version)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                ScrollView {
                    Text(earlier.prompt)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                }
                .background(Color(.secondarySystemBackground))
            }

            Divider()

            // Later prompt
            VStack(alignment: .leading, spacing: 4) {
                Text("v\(later.version)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                ScrollView {
                    Text(later.prompt)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                }
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    private var unifiedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Show character count difference
                let diff = later.prompt.count - earlier.prompt.count
                HStack {
                    Text("Character change:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(diff >= 0 ? "+\(diff)" : "\(diff)")
                        .font(.caption.bold())
                        .foregroundColor(diff >= 0 ? .green : .red)
                }
                .padding(.horizontal)

                Divider()

                // Simple line-by-line comparison
                let earlierLines = earlier.prompt.components(separatedBy: "\n")
                let laterLines = later.prompt.components(separatedBy: "\n")

                let maxLines = max(earlierLines.count, laterLines.count)

                ForEach(0..<maxLines, id: \.self) { index in
                    let earlierLine = index < earlierLines.count ? earlierLines[index] : ""
                    let laterLine = index < laterLines.count ? laterLines[index] : ""

                    if earlierLine != laterLine {
                        // Show difference
                        VStack(alignment: .leading, spacing: 2) {
                            if !earlierLine.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("-")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.red)
                                    Text(earlierLine)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                            }
                            if !laterLine.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("+")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.green)
                                    Text(laterLine)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                            }
                        }
                    } else if !earlierLine.isEmpty {
                        // Unchanged line
                        HStack(alignment: .top, spacing: 8) {
                            Text(" ")
                                .font(.caption.monospaced())
                            Text(earlierLine)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                    }
                }
            }
            .padding()
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .yellow }
        return .red
    }
}

#Preview {
    TemplateIterationComparisonView(
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
        )
    )
}
