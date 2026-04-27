//
//  DigestionPipelineView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/28/26.
//

import SwiftUI

// MARK: - Embeddable Pipeline Section (Snake Layout)

/// Inline section for CreatorDetailView showing the 5-step digestion flow
/// in a compact snake grid with expandable detail panel.
struct DigestionPipelineSection: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel
    @ObservedObject private var viewModel = CreatorDetailViewModel.shared
    @State private var selectedStep: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pipelineHeader

            // Row 1: Steps 1 → 2 → 3 (left to right)
            HStack(spacing: 6) {
                compactCard(step: transcriptStep)
                arrowConnector(flowing: transcriptStep.done > 0)
                compactCard(step: sentenceStep)
                arrowConnector(flowing: sentenceStep.done > 0)
                compactCard(step: digressionStep)
            }

            // Turn connector: right side drops down
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(digressionStep.done > 0 ? Color.green.opacity(0.5) : Color.gray.opacity(0.3))
                        .frame(width: 2, height: 10)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(digressionStep.done > 0 ? .green : .gray)
                }
                .padding(.trailing, 40)
            }

            // Row 2: Firebase ← 5 ← 4 (right to left)
            HStack(spacing: 6) {
                firebaseTile
                arrowConnector(flowing: moveGistStep.done > 0, reversed: true)
                compactCard(step: moveGistStep)
                arrowConnector(flowing: boundaryStep.done > 0, reversed: true)
                compactCard(step: boundaryStep)
            }

            // Expanded detail panel for selected step
            if let sel = selectedStep, let step = stepFor(sel) {
                expandedDetail(step: step)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Pipeline Header

    private var pipelineHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.subheadline)
                    .foregroundColor(.teal)
                Text("Sentence-Tag Pipeline (Deterministic)")
                    .font(.subheadline.bold())
                Spacer()

                let total = viewModel.videos.count
                let done = viewModel.videosWithRhetoricalSequence
                let pct = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text("\(pct)%")
                    .font(.caption.bold())
                    .foregroundColor(pct >= 100 ? .green : .orange)
            }

            ProgressView(value: viewModel.videos.count > 0
                ? Double(viewModel.videosWithRhetoricalSequence) / Double(viewModel.videos.count)
                : 0)
                .tint(viewModel.videosWithRhetoricalSequence == viewModel.videos.count && viewModel.videos.count > 0 ? .green : .orange)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Compact Card (tile in the grid)

    private func compactCard(step: PipelineStep) -> some View {
        let isSelected = selectedStep == step.number
        let pct = step.total > 0 ? Double(step.done) / Double(step.total) : 0

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStep = isSelected ? nil : step.number
            }
        } label: {
            VStack(spacing: 4) {
                // Badge + title
                HStack(spacing: 4) {
                    stepBadge(step: step)
                    Text(step.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                // Count
                if step.isBlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                } else {
                    Text("\(step.done)/\(step.total)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    // Tiny progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemGray4))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(step.color)
                                .frame(width: geo.size.width * pct, height: 3)
                        }
                    }
                    .frame(height: 3)
                }

                // Running dot
                if step.isRunning {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(height: 8)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(step.isBlocked ? Color(.systemGray6) : step.color.opacity(0.08))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? step.color : (step.isBlocked ? Color.gray.opacity(0.2) : step.color.opacity(0.3)),
                            lineWidth: isSelected ? 2 : 1)
            )
            .opacity(step.isBlocked ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Firebase Tile

    private var firebaseTile: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("Firebase")
                    .font(.system(size: 10, weight: .semibold))
            }
            Text("Corpus")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(viewModel.videosWithRhetoricalSequence > 0 ? .green : .gray)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Arrow Connector

    private func arrowConnector(flowing: Bool, reversed: Bool = false) -> some View {
        Image(systemName: reversed ? "chevron.left" : "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(flowing ? .green : .gray.opacity(0.4))
            .frame(width: 12)
    }

    // MARK: - Expanded Detail Panel

    private func expandedDetail(step: PipelineStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                stepBadge(step: step)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.title)
                        .font(.subheadline.bold())
                    Text(step.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !step.isBlocked {
                    Text("\(step.done)/\(step.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                // Close button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedStep = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if step.isBlocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                    Text("Requires Step \(step.blockedByStep ?? 0) to have completions first")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                // Progress bar
                ProgressView(value: step.total > 0 ? Double(step.done) / Double(step.total) : 0)
                    .tint(step.color)

                // Status line
                HStack(spacing: 12) {
                    if step.isAutoComputed {
                        Label("Auto-computed from sentence data", systemImage: "cpu")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else {
                        Label("\(step.feedsNext) ready for next step", systemImage: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(step.feedsNext > 0 ? .green : .secondary)
                    }
                }

                // Running indicator
                if step.isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(step.runningText ?? "Processing...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Per-video rhetorical queue progress (Step 5 only)
                if step.number == 5 && viewModel.isRunningRhetoricalAnalysis {
                    rhetoricalQueueDetail
                }

                // Action buttons
                if !step.actions.isEmpty && !step.isRunning {
                    HStack(spacing: 6) {
                        ForEach(step.actions.indices, id: \.self) { i in
                            let action = step.actions[i]
                            Button(action: action.handler) {
                                HStack(spacing: 3) {
                                    Text(action.label)
                                        .font(.caption2.bold())
                                    if action.style == .navigation {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(action.style == .secondary ? Color(.systemGray5) : step.color.opacity(0.15))
                                .foregroundColor(action.style == .secondary ? .primary : step.color)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(step.color.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Step Badge

    private func stepBadge(step: PipelineStep) -> some View {
        let badgeColor: Color = {
            if step.isBlocked { return .gray }
            if step.done == step.total && step.total > 0 { return .green }
            return .blue
        }()

        return ZStack {
            Circle()
                .fill(badgeColor)
                .frame(width: 20, height: 20)
            Text("\(step.number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Rhetorical Queue Detail

    private var rhetoricalQueueDetail: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !viewModel.rhetoricalQueueProgress.isEmpty {
                ForEach(Array(viewModel.rhetoricalQueueProgress.keys), id: \.self) { videoId in
                    if let progress = viewModel.rhetoricalQueueProgress[videoId],
                       let video = viewModel.videos.first(where: { $0.videoId == videoId }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.pink)
                            Text(video.title)
                                .font(.caption2)
                                .lineLimit(1)
                            Text("- \(progress)")
                                .font(.caption2)
                                .foregroundColor(.pink)
                        }
                    }
                }
            }
            if !viewModel.videosQueuedForRhetorical.isEmpty {
                Text("\(viewModel.videosQueuedForRhetorical.count) more in queue")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pink.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Step Data Lookup

    private func stepFor(_ number: Int) -> PipelineStep? {
        switch number {
        case 1: return transcriptStep
        case 2: return sentenceStep
        case 3: return digressionStep
        case 4: return boundaryStep
        case 5: return moveGistStep
        default: return nil
        }
    }

    // MARK: - Step Definitions

    private var transcriptStep: PipelineStep {
        let done = viewModel.videosWithTranscripts
        let total = viewModel.videos.count
        let missing = total - done
        return PipelineStep(
            number: 1,
            title: "Transcript",
            subtitle: "Raw text, prerequisite for everything",
            color: .red,
            done: done,
            total: total,
            isBlocked: false,
            blockedByStep: nil,
            feedsNext: done,
            isRunning: viewModel.isFetchingTranscripts,
            runningText: viewModel.transcriptFetchProgress,
            isAutoComputed: false,
            actions: missing > 0 ? [
                .init(label: "Fetch Missing (\(missing))", style: .primary) {
                    Task { await viewModel.fetchAllMissingTranscripts() }
                }
            ] : []
        )
    }

    private var sentenceStep: PipelineStep {
        let done = viewModel.videosWithSentenceAnalysis
        let total = viewModel.videosWithTranscripts
        let missing = total - done
        let isBlocked = total == 0
        let isRunning = viewModel.sentenceBatchService.isRunning || viewModel.isRunningEfficientTest
        return PipelineStep(
            number: 2,
            title: "Sentences",
            subtitle: "Tag each sentence with rhetorical function",
            color: .cyan,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 1 : nil,
            feedsNext: done,
            isRunning: isRunning,
            runningText: viewModel.isRunningEfficientTest ? viewModel.efficientTestProgress : nil,
            isAutoComputed: false,
            actions: isBlocked ? [] : [
                .init(label: "Tag All (\(missing))", style: .primary) {
                    Task { await viewModel.runBatchSentenceAnalysis() }
                },
                .init(label: "Efficient (10)", style: .secondary) {
                    Task { await viewModel.runEfficientSentenceTest() }
                }
            ]
        )
    }

    private var digressionStep: PipelineStep {
        let done = viewModel.batchDigressionService.videoResults.count
        let total = viewModel.videosWithSentenceAnalysis
        let isBlocked = total == 0
        return PipelineStep(
            number: 3,
            title: "Digression",
            subtitle: "Identify off-topic tangents in each video",
            color: .indigo,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 2 : nil,
            feedsNext: done,
            isRunning: false,
            runningText: nil,
            isAutoComputed: false,
            actions: isBlocked ? [] : [
                .init(label: "Run Analysis", style: .navigation) {
                    nav.push(.batchDigressionDashboard(channel))
                }
            ]
        )
    }

    private var boundaryStep: PipelineStep {
        let count = viewModel.videosWithSentenceAnalysis
        let isBlocked = count == 0
        return PipelineStep(
            number: 4,
            title: "Boundaries",
            subtitle: "Auto-computed from sentence data",
            color: .blue,
            done: count,
            total: count,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 2 : nil,
            feedsNext: count,
            isRunning: false,
            runningText: nil,
            isAutoComputed: true,
            actions: []
        )
    }

    private var moveGistStep: PipelineStep {
        let done = viewModel.videosWithRhetoricalSequence
        let total = viewModel.videosWithSentenceAnalysis
        let ready = viewModel.videosReadyForRhetoricalAnalysis
        let needingUpdate = viewModel.videosNeedingEnhancedRhetorical
        let isBlocked = total == 0
        let isRunning = viewModel.isRunningRhetoricalAnalysis
        return PipelineStep(
            number: 5,
            title: "Moves",
            subtitle: "Extract rhetorical moves and gists per chunk",
            color: .pink,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 2 : nil,
            feedsNext: done,
            isRunning: isRunning,
            runningText: viewModel.rhetoricalAnalysisProgress.isEmpty ? nil : viewModel.rhetoricalAnalysisProgress,
            isAutoComputed: false,
            actions: isBlocked ? [] : [
                .init(label: "Extract All (\(ready))", style: .primary) {
                    Task { await viewModel.runBatchRhetoricalAnalysis() }
                },
                .init(label: "Queue (\(needingUpdate))", style: .secondary) {
                    viewModel.queueAllVideosNeedingEnhancedRhetorical()
                },
                .init(label: "View Style", style: .navigation) {
                    nav.push(.creatorRhetoricalStyle(channel))
                }
            ]
        )
    }
}

// MARK: - Supporting Types

private struct PipelineStep {
    let number: Int
    let title: String
    let subtitle: String
    let color: Color
    let done: Int
    let total: Int
    let isBlocked: Bool
    let blockedByStep: Int?
    let feedsNext: Int
    let isRunning: Bool
    let runningText: String?
    let isAutoComputed: Bool
    let actions: [PipelineAction]
}

private struct PipelineAction {
    enum Style { case primary, secondary, navigation }
    let label: String
    let style: Style
    let handler: () -> Void
}
