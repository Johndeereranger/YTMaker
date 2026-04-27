//
//  Pass1ResultsView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  Shows Pass 1 results: per-section expandable cards with written text,
//  summaries, callbacks, and debug disclosures.
//

import SwiftUI

struct Pass1ResultsView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @State private var expandedSections: Set<Int> = []
    @State private var expandedDebug: Set<Int> = []
    @State private var sectionLimit: Int = 0  // 0 = not yet initialized

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Synthesize button + chain summary
                headerSection

                if let script = coordinator.activeSynthesis {
                    // Chain summary strip
                    chainSummaryStrip(script: script)

                    // Per-section cards
                    ForEach(script.sections) { section in
                        sectionCard(section: section, totalSections: script.sections.count)
                    }

                    // Telemetry footer
                    telemetryFooter(script: script)
                } else {
                    noResultsView
                }
            }
            .padding()
        }
    }

    // MARK: - Header

    private var totalPositions: Int {
        coordinator.currentChainRun?.bestChain?.positions.count ?? 0
    }

    private var effectiveLimit: Int {
        sectionLimit > 0 ? min(sectionLimit, totalPositions) : totalPositions
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pass 1: Section Synthesis")
                        .font(.headline)
                    if let chain = coordinator.currentChainRun?.bestChain {
                        Text("\(chain.positions.count) positions, \(String(format: "%.0f", chain.coverageScore * 100))% coverage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    coordinator.synthesizeScript(sectionLimit: effectiveLimit)
                } label: {
                    Label("Synthesize", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isLoading || coordinator.currentChainRun?.bestChain == nil)
            }

            if totalPositions > 0 {
                HStack(spacing: 8) {
                    Text("Sections to write:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper(
                        "\(effectiveLimit) of \(totalPositions)",
                        value: Binding(
                            get: { effectiveLimit },
                            set: { sectionLimit = max(1, min($0, totalPositions)) }
                        ),
                        in: 1...max(totalPositions, 1)
                    )
                    .font(.caption)
                }
                .onAppear {
                    if sectionLimit == 0 { sectionLimit = totalPositions }
                }
            }
        }
    }

    // MARK: - Chain Summary Strip

    private func chainSummaryStrip(script: SynthesizedScript) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(script.moveSequence.enumerated()), id: \.offset) { idx, move in
                    Text(move.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorForCategory(move.category).opacity(0.2))
                        .foregroundColor(colorForCategory(move.category))
                        .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Section Card

    private func sectionCard(section: SynthesisSection, totalSections: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button {
                toggleSet(&expandedSections, section.positionIndex)
            } label: {
                HStack {
                    Circle()
                        .fill(colorForCategory(section.moveType.category))
                        .frame(width: 8, height: 8)
                    Text("Position \(section.positionIndex + 1) of \(totalSections): \(section.moveType.displayName)")
                        .font(.subheadline.bold())
                    Spacer()

                    if section.parseError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }

                    Image(systemName: expandedSections.contains(section.positionIndex) ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expandedSections.contains(section.positionIndex) {
                // Rambling gist premise (collapsed label)
                if let ramblingText = section.ramblingSourceText, !ramblingText.isEmpty {
                    DisclosureGroup("Rambling Input") {
                        Text(ramblingText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        CompactCopyButton(text: ramblingText)
                    }
                    .font(.caption.bold())
                }

                // Pattern analysis
                if !section.analysis.isEmpty {
                    DisclosureGroup("Pattern Analysis") {
                        Text(section.analysis)
                            .font(.caption)
                            .padding(8)
                            .background(Color.purple.opacity(0.05))
                            .cornerRadius(6)
                        CompactCopyButton(text: section.analysis)
                    }
                    .font(.caption.bold())
                }

                // Written text
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Written Text")
                            .font(.caption.bold())
                        Spacer()
                        CompactCopyButton(text: section.writtenText)
                    }
                    Text(section.writtenText)
                        .font(.body)
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }

                // Summary
                if !section.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Summary")
                            .font(.caption.bold())
                        Text(section.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Callbacks
                if !section.callbacks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Callbacks Introduced")
                            .font(.caption.bold())
                        ForEach(section.callbacks, id: \.self) { cb in
                            Text("  \(cb)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Ending Note
                if !section.endingNote.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ending Note")
                            .font(.caption.bold())
                        Text(section.endingNote)
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                    }
                }

                // Debug disclosure
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedDebug.contains(section.positionIndex) },
                        set: { if $0 { expandedDebug.insert(section.positionIndex) } else { expandedDebug.remove(section.positionIndex) } }
                    )
                ) {
                    debugContent(section: section)
                } label: {
                    Text("Debug")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Debug Content

    private func debugContent(section: SynthesisSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // System Prompt
            debugBlock(title: "System Prompt", content: section.systemPromptSent)

            // User Prompt
            debugBlock(title: "User Prompt", content: section.promptSent)

            // Raw Response
            debugBlock(title: "Raw LLM Response", content: section.rawResponse)

            // Telemetry
            if let telemetry = coordinator.activeSynthesis?.pass1Telemetry,
               section.positionIndex < telemetry.count {
                let t = telemetry[section.positionIndex]
                HStack {
                    Text("Tokens: \(t.promptTokens) in / \(t.completionTokens) out / \(t.totalTokens) total")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Corpus context
            HStack {
                Text("Creator sections: \(section.creatorSectionCount)")
                    .font(.caption2)
                if !section.creatorVideoTitles.isEmpty {
                    Text("from: \(section.creatorVideoTitles.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            if section.transitionBridgeUsed {
                Text("Transition bridge: used")
                    .font(.caption2)
                    .foregroundColor(.green)
            }

            if section.parseError {
                Text("Parse error: raw response used as fallback (retry count: \(section.retryCount))")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private func debugBlock(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2.bold())
                Spacer()
                CompactCopyButton(text: content)
            }
            ScrollView {
                Text(content)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxHeight: 150)
            .padding(6)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(4)
        }
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No synthesis results yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Build a completed chain, then tap Synthesize.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Telemetry Footer

    private func telemetryFooter(script: SynthesizedScript) -> some View {
        let totalPrompt = script.pass1Telemetry.reduce(0) { $0 + $1.promptTokens }
        let totalCompletion = script.pass1Telemetry.reduce(0) { $0 + $1.completionTokens }
        let totalTokens = script.pass1Telemetry.reduce(0) { $0 + $1.totalTokens }

        return VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("Pass 1 Totals")
                .font(.caption.bold())
            Text("Tokens: \(totalPrompt) in / \(totalCompletion) out / \(totalTokens) total")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Prompt version: \(script.promptVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func toggleSet(_ set: inout Set<Int>, _ value: Int) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func colorForCategory(_ category: RhetoricalCategory) -> Color {
        switch category {
        case .hook: return .red
        case .setup: return .blue
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .green
        case .closing: return .gray
        }
    }
}
