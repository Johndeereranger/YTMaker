//
//  Pass2ResultsView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  Shows Pass 2 results: smoothed script, side-by-side comparison with Pass 1,
//  and debug disclosures.
//

import SwiftUI

struct Pass2ResultsView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @State private var showDebug = false
    @State private var showComparison = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let script = coordinator.activeSynthesis {
                    if let smoothed = script.smoothedScript, !smoothed.isEmpty {
                        pass2Content(script: script, smoothed: smoothed)
                    } else {
                        noPass2View
                    }
                } else {
                    noResultsView
                }
            }
            .padding()
        }
    }

    // MARK: - Pass 2 Content

    private func pass2Content(script: SynthesizedScript, smoothed: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Pass 2: Transition Smoothing")
                    .font(.headline)
                Spacer()
                CompactCopyButton(text: smoothed)
            }

            // Full smoothed script
            VStack(alignment: .leading, spacing: 4) {
                Text("Final Script")
                    .font(.caption.bold())
                Text(smoothed)
                    .font(.body)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            }

            // Side-by-side comparison (v1: two text blocks, not diff)
            DisclosureGroup(
                isExpanded: $showComparison
            ) {
                comparisonView(script: script, smoothed: smoothed)
            } label: {
                Text("Compare Pass 1 vs Pass 2")
                    .font(.caption.bold())
            }

            // Debug disclosure
            DisclosureGroup(
                isExpanded: $showDebug
            ) {
                debugSection(script: script)
            } label: {
                Text("Debug")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }

            // Telemetry
            if let t = script.pass2Telemetry {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("Pass 2 Totals")
                        .font(.caption.bold())
                    Text("Tokens: \(t.promptTokens) in / \(t.completionTokens) out / \(t.totalTokens) total")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Comparison View

    private func comparisonView(script: SynthesizedScript, smoothed: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pass 1 concatenation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pass 1 (concatenated)")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    Spacer()
                    if let draft = script.pass1ConcatenatedDraft {
                        CompactCopyButton(text: draft)
                    }
                }
                ScrollView {
                    Text(script.pass1ConcatenatedDraft ?? "(no Pass 1 draft)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: 300)
                .padding(8)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(6)
            }

            // Pass 2 smoothed
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pass 2 (smoothed)")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                    Spacer()
                    CompactCopyButton(text: smoothed)
                }
                ScrollView {
                    Text(smoothed)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: 300)
                .padding(8)
                .background(Color.green.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Debug Section

    private func debugSection(script: SynthesizedScript) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // System Prompt
            if let sys = script.pass2SystemPromptSent, !sys.isEmpty {
                debugBlock(title: "System Prompt", content: sys)
            }

            // User Prompt
            if let prompt = script.pass2PromptSent, !prompt.isEmpty {
                debugBlock(title: "User Prompt", content: prompt)
            }

            // Raw Response
            if let raw = script.pass2RawResponse, !raw.isEmpty {
                debugBlock(title: "Raw LLM Response", content: raw)
            }

            // Seam inventory
            seamInventory(script: script)
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

    // MARK: - Seam Inventory

    private func seamInventory(script: SynthesizedScript) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Seam Inventory")
                .font(.caption2.bold())

            if script.sections.count >= 2 {
                ForEach(0..<(script.sections.count - 1), id: \.self) { i in
                    let sectionA = script.sections[i]
                    let sectionB = script.sections[i + 1]
                    HStack(spacing: 4) {
                        Text("Seam \(i + 1):")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(sectionA.moveType.displayName) → \(sectionB.moveType.displayName)")
                            .font(.caption2)
                        if sectionA.transitionBridgeUsed || sectionB.transitionBridgeUsed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Text("(no bridge)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var noPass2View: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Pass 2 not yet run")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Pass 2 runs automatically after Pass 1 completes.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No synthesis results yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Run a synthesis from the Pass 1 tab first.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
