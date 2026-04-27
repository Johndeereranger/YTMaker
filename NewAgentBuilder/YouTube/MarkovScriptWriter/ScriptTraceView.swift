//
//  ScriptTraceView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import SwiftUI

// MARK: - Script Trace View (Side B Pipeline Tab)

/// Shows the full Side B writing flow for the current chain:
/// W1.5 (Payload Decomposition) → W2 (Slot Walk) → W3 (Donor Retrieval)
/// → W4 (Tier Adaptation) → W5 (Seam Check) → Final Script
struct ScriptTraceView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @State private var expandedBeats: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if coordinator.isRunningScriptTrace {
                    runningProgress
                }

                if coordinator.scriptTraceBeats.isEmpty && !coordinator.isRunningScriptTrace {
                    emptyState
                } else {
                    tierDistribution
                    beatList
                }
            }
            .padding()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Trace")
                        .font(.title3.bold())
                    Text("Retrieval-anchored style transfer pipeline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if !coordinator.isRunningScriptTrace {
                    Button {
                        Task { await coordinator.runScriptTracePipeline() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Run Pipeline")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(coordinator.session.ramblingGists.isEmpty ? Color.gray.opacity(0.15) : Color.green.opacity(0.15))
                        .foregroundColor(coordinator.session.ramblingGists.isEmpty ? .gray : .green)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(coordinator.session.ramblingGists.isEmpty)
                }
            }

            if coordinator.session.ramblingGists.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No gists available. Go to the Input tab and extract gists first.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Running Progress

    private var runningProgress: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(coordinator.scriptTraceProgress)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Tier Distribution

    private var tierDistribution: some View {
        let beats = coordinator.scriptTraceBeats
        guard !beats.isEmpty else { return AnyView(EmptyView()) }

        let t1 = beats.filter { $0.adaptationTier == .tier1 }.count
        let t2 = beats.filter { $0.adaptationTier == .tier2 }.count
        let t3 = beats.filter { $0.adaptationTier == .tier3 }.count
        let total = beats.count

        return AnyView(
            HStack(spacing: 12) {
                tierBadge(label: "T1", count: t1, total: total, color: .green)
                tierBadge(label: "T2", count: t2, total: total, color: .yellow)
                tierBadge(label: "T3", count: t3, total: total, color: .red)
                Spacer()
                Text("\(beats.count) beats")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        )
    }

    private func tierBadge(label: String, count: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? Int(Double(count) / Double(total) * 100) : 0
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label): \(count) (\(pct)%)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.primary)
        }
    }

    // MARK: - Beat List

    private var beatList: some View {
        ForEach(coordinator.scriptTraceBeats) { beat in
            beatCard(beat)
        }
    }

    // MARK: - Beat Card

    private func beatCard(_ beat: ScriptBeat) -> some View {
        let isExpanded = expandedBeats.contains(beat.beatIndex)

        return VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedBeats.remove(beat.beatIndex)
                    } else {
                        expandedBeats.insert(beat.beatIndex)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Beat index
                    Text("\(beat.beatIndex + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(beat.adaptationTier.color.opacity(0.8))
                        .cornerRadius(6)

                    // Move badge
                    Text(beat.sectionMove)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)

                    // Tier badge
                    Text(beat.adaptationTier.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(beat.adaptationTier.color.opacity(0.15))
                        .foregroundColor(beat.adaptationTier.color)
                        .cornerRadius(4)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Final text (always visible)
            if let finalText = beat.finalText {
                Text(finalText)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    // W1.5: Payloads
                    if !beat.payloads.isEmpty {
                        stageSection(title: "W1.5 Payloads", icon: "rectangle.split.3x1") {
                            ForEach(beat.payloads) { payload in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(payload.payloadIndex + 1).")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(payload.contentText)
                                            .font(.caption)
                                        Text(payload.payloadType.displayName)
                                            .font(.system(size: 9))
                                            .foregroundColor(.purple)
                                    }
                                }
                            }
                        }
                    }

                    // W2: Target Signature
                    if let sig = beat.targetSlotSignature {
                        stageSection(title: "W2 Target Signature", icon: "arrow.triangle.branch") {
                            Text(sig)
                                .font(.caption.monospaced())
                                .foregroundColor(.teal)
                        }
                    }

                    // W3: Donor
                    if let donor = beat.donorSentence {
                        stageSection(title: "W3 Donor", icon: "doc.text") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(donor.rawText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                                if let reason = beat.donorMatchReason {
                                    Text(reason)
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)
                                }
                                if let score = beat.donorSimilarityScore {
                                    Text("Similarity: \(String(format: "%.2f", score))")
                                        .font(.system(size: 9).monospacedDigit())
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }

                    // W4: Adaptation (side-by-side)
                    if let adapted = beat.adaptedText, let donor = beat.donorSentence {
                        stageSection(title: "W4 Adaptation (\(beat.adaptationTier.rawValue))", icon: "arrow.left.arrow.right") {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Donor")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Text(donor.rawText)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 1)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Adapted")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(beat.adaptationTier.color)
                                        Text(adapted)
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    // W5: Seam Edit
                    if let seam = beat.seamEdit {
                        stageSection(title: "W5 Seam Edit", icon: "link") {
                            Text(seam)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // Error
                    if let error = beat.error {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(beat.adaptationTier.color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Stage Section Helper

    private func stageSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            content()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("No trace data yet")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            Text("Run the pipeline to decompose gists, retrieve donors, and generate adapted script beats.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
