//
//  LLMPipelineSection.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/4/26.
//

import SwiftUI

// MARK: - LLM Pipeline Section (Snake Layout)

/// Inline section showing the 4-step LLM digestion flow:
/// Transcript → Digression (LLM) → Boundaries (LLM) → Moves → Firebase
struct LLMPipelineSection: View {
    let channel: YouTubeChannel
    @ObservedObject private var viewModel = CreatorDetailViewModel.shared
    @ObservedObject private var llmService = LLMDigestionService.shared
    @State private var selectedStep: Int? = nil
    @State private var isDemoting = false
    @State private var demoteResult: String?
    @State private var showDemoteConfirm = false

    /// Videos with bad sentence structure that need demoting back to transcript-only
    private let demoteTitles: [String] = [
        "Why most of our money isn't real",
        "VOX BORDERS CANCELED",
        "You Ask, I Answer | Q&A",
        "Junk Mail, Explained",
        "How I Took a Picture of a Galaxy",
        "How the U.S. Stole an Island",
        "How We Map the Stars",
        "How To Map a Virus",
        "Why Canada's Maple Leafs Are Like Switzerland | Banff, Lake Louise, and Sunshine Village",
        "My Recipe for Escape | Italy & Switzerland",
        "How I Use Music | Thoughts on the Creative Power of Music",
        "My Favorite Places on Earth in 2019",
        "I'm Dyslexic",
        "Why I Can't Stop Thinking About This Photo",
        "What's With My Orange Coat",
        "Why Everyone is Going to Iceland Lately",
        "Should You Go to College?",
        "The 5 Things I Do When I Get to a New City",
        "How I Got My Job at Vox | Lessons About Getting a Job in Video",
        "How I Got My Start in Video"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pipelineHeader

            // Row 1: Steps 1 → 2 → 3 (left to right)
            HStack(spacing: 6) {
                compactCard(step: transcriptStep)
                arrowConnector(flowing: transcriptStep.done > 0)
                compactCard(step: digressionStep)
                arrowConnector(flowing: digressionStep.done > 0)
                compactCard(step: boundaryStep)
            }

            // Turn connector: right side drops down
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(boundaryStep.done > 0 ? Color.green.opacity(0.5) : Color.gray.opacity(0.3))
                        .frame(width: 2, height: 10)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(boundaryStep.done > 0 ? .green : .gray)
                }
                .padding(.trailing, 40)
            }

            // Row 2: Firebase ← 4 (right to left)
            HStack(spacing: 6) {
                firebaseTile
                arrowConnector(flowing: moveStep.done > 0, reversed: true)
                compactCard(step: moveStep)
                // Spacer to balance the 3-column row above
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
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
                Image(systemName: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundColor(.purple)
                Text("LLM Pipeline")
                    .font(.subheadline.bold())
                Spacer()

                let total = viewModel.videosWithTranscripts
                let done = viewModel.videosWithRhetoricalSequence
                let pct = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text("\(pct)%")
                    .font(.caption.bold())
                    .foregroundColor(pct >= 100 ? .green : .purple)
            }

            ProgressView(value: viewModel.videosWithTranscripts > 0
                ? Double(viewModel.videosWithRhetoricalSequence) / Double(viewModel.videosWithTranscripts)
                : 0)
                .tint(viewModel.videosWithRhetoricalSequence == viewModel.videosWithTranscripts && viewModel.videosWithTranscripts > 0 ? .green : .purple)

            // Run Full Pipeline buttons
            if !llmService.isRunning {
                let ready = eligibleForFullPipeline
                if ready > 0 {
                    HStack(spacing: 6) {
                        Button {
                            Task { await llmService.runFullPipeline(videos: viewModel.videos, limit: 1) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text("Run 1")
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.08))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await llmService.runFullPipeline(videos: viewModel.videos, limit: 3) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text("Run 3")
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.08))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await llmService.runFullPipeline(videos: viewModel.videos, limit: 5) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text("Run 5")
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.08))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await llmService.runFullPipeline(videos: viewModel.videos, limit: 10) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text("Run 10")
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.08))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await llmService.runFullPipeline(videos: viewModel.videos) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text("All (\(ready))")
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Running progress
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(llmService.progress)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Per-video progress
                if !llmService.perVideoProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(llmService.perVideoProgress.keys.prefix(5)), id: \.self) { videoId in
                            if let stepProgress = llmService.perVideoProgress[videoId],
                               let video = viewModel.videos.first(where: { $0.videoId == videoId }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.purple)
                                    Text(video.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                    Text("- \(stepProgress)")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(4)
                }
            }

            // MARK: Demote Buttons
            if !llmService.isRunning {
                demoteSection
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .alert("Demote All?", isPresented: $showDemoteConfirm) {
            Button("Demote \(remainingDemoteCount) Videos", role: .destructive) {
                Task {
                    isDemoting = true
                    demoteResult = nil
                    await llmService.demoteVideos(
                        titles: demoteTitles,
                        videos: viewModel.videos,
                        channelId: channel.channelId
                    )
                    demoteResult = llmService.progress.isEmpty ? "Done" : llmService.progress
                    isDemoting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will strip all pipeline data (digression, boundaries, moves) from \(remainingDemoteCount) videos, leaving only transcripts.")
        }
    }

    // MARK: - Demote Section

    /// Count how many of the demote-list videos still have pipeline data
    private var remainingDemoteCount: Int {
        let digressionIds = Set(CreatorDetailViewModel.shared.batchDigressionService.videoResults.map { $0.videoId })
        let boundaryIds = Set(CreatorDetailViewModel.shared.llmBoundaryService.videoResults.map { $0.videoId })

        return matchedDemoteVideos.filter { video in
            digressionIds.contains(video.videoId) ||
            boundaryIds.contains(video.videoId) ||
            video.rhetoricalSequence != nil
        }.count
    }

    /// Normalize curly apostrophes to straight for title matching
    private func normalizeTitle(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    /// Videos from the demote list that match actual video objects
    private var matchedDemoteVideos: [YouTubeVideo] {
        demoteTitles.compactMap { title in
            let norm = normalizeTitle(title)
            return viewModel.videos.first(where: { normalizeTitle($0.title) == norm })
                ?? viewModel.videos.first(where: { normalizeTitle($0.title).contains(norm) || norm.contains(normalizeTitle($0.title)) })
        }
    }

    /// The next un-demoted video from the list (first one still with pipeline data)
    private var nextDemoteVideo: YouTubeVideo? {
        let digressionIds = Set(CreatorDetailViewModel.shared.batchDigressionService.videoResults.map { $0.videoId })
        let boundaryIds = Set(CreatorDetailViewModel.shared.llmBoundaryService.videoResults.map { $0.videoId })

        return matchedDemoteVideos.first { video in
            digressionIds.contains(video.videoId) ||
            boundaryIds.contains(video.videoId) ||
            video.rhetoricalSequence != nil
        }
    }

    private var demoteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            let remaining = remainingDemoteCount

            if remaining > 0 {
                HStack(spacing: 6) {
                    // Demote 1 button
                    Button {
                        guard let video = nextDemoteVideo else { return }
                        Task {
                            isDemoting = true
                            demoteResult = nil
                            let result = await llmService.demoteVideo(video: video, channelId: channel.channelId)
                            // Reload so counters update
                            await CreatorDetailViewModel.shared.loadVideos()
                            if let ch = CreatorDetailViewModel.shared.currentChannel {
                                await CreatorDetailViewModel.shared.batchDigressionService.loadResults(forChannelId: ch.channelId)
                                await CreatorDetailViewModel.shared.llmBoundaryService.loadResults(forChannelId: ch.channelId)
                            }
                            demoteResult = "\(video.title): \(result)"
                            isDemoting = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            if isDemoting {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 9))
                            }
                            Text("Demote 1")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDemoting)

                    // Demote All button
                    Button {
                        showDemoteConfirm = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9))
                            Text("Demote All (\(remaining))")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDemoting)

                    Spacer()
                }

                if let next = nextDemoteVideo {
                    Text("Next: \(next.title)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            if let result = demoteResult {
                Text(result)
                    .font(.caption2)
                    .foregroundColor(.green)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Compact Card

    private func compactCard(step: LLMPipelineStep) -> some View {
        let isSelected = selectedStep == step.number
        let pct = step.total > 0 ? Double(step.done) / Double(step.total) : 0

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStep = isSelected ? nil : step.number
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    stepBadge(step: step)
                    Text(step.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if step.isBlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                } else {
                    Text("\(step.done)/\(step.total)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

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

                if let partial = step.partialCount {
                    Text("\(partial) Partial")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(partial > 0 ? .orange : .green)
                }

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

    private func expandedDetail(step: LLMPipelineStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                ProgressView(value: step.total > 0 ? Double(step.done) / Double(step.total) : 0)
                    .tint(step.color)

                HStack(spacing: 12) {
                    if step.isAutoComputed {
                        Label("Computed during pipeline run", systemImage: "cpu")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else {
                        Label("\(step.feedsNext) ready for next step", systemImage: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(step.feedsNext > 0 ? .green : .secondary)
                    }
                }

                if step.isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(step.runningText ?? "Processing...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
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

    private func stepBadge(step: LLMPipelineStep) -> some View {
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

    // MARK: - Step Data Lookup

    private func stepFor(_ number: Int) -> LLMPipelineStep? {
        switch number {
        case 1: return transcriptStep
        case 2: return digressionStep
        case 3: return boundaryStep
        case 4: return moveStep
        default: return nil
        }
    }

    // MARK: - Computed Counts

    private var eligibleForFullPipeline: Int {
        viewModel.videos.filter { $0.hasTranscript && $0.rhetoricalSequence == nil }.count
    }

    // MARK: - Step Definitions

    private var transcriptStep: LLMPipelineStep {
        let done = viewModel.videosWithTranscripts
        let total = viewModel.videos.count
        let missing = total - done
        return LLMPipelineStep(
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

    private var digressionStep: LLMPipelineStep {
        let done = viewModel.batchDigressionService.videoResults.count
        let total = viewModel.videosWithTranscripts
        let isBlocked = total == 0
        let ready = total - done
        return LLMPipelineStep(
            number: 2,
            title: "Digression",
            subtitle: "LLM detects off-topic tangents",
            color: .indigo,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 1 : nil,
            feedsNext: done,
            isRunning: llmService.isRunning && llmService.currentStep == "Digression",
            runningText: llmService.progress,
            isAutoComputed: false,
            actions: isBlocked || ready <= 0 ? [] : [
                .init(label: "Run 1", style: .secondary) {
                    Task { await llmService.runDigressionOnly(videos: viewModel.videos, limit: 1) }
                },
                .init(label: "Run 3", style: .secondary) {
                    Task { await llmService.runDigressionOnly(videos: viewModel.videos, limit: 3) }
                },
                .init(label: "Run 5", style: .secondary) {
                    Task { await llmService.runDigressionOnly(videos: viewModel.videos, limit: 5) }
                },
                .init(label: "Run 10", style: .secondary) {
                    Task { await llmService.runDigressionOnly(videos: viewModel.videos, limit: 10) }
                },
                .init(label: "All (\(ready))", style: .primary) {
                    Task { await llmService.runDigressionOnly(videos: viewModel.videos) }
                }
            ]
        )
    }

    private var boundaryStep: LLMPipelineStep {
        // Boundaries are now persisted to Firebase (LLM splitter is non-deterministic).
        // done = videos with saved boundary results
        // total = videos with digressions (eligible for boundary computation)
        let total = viewModel.batchDigressionService.videoResults.count
        let done = viewModel.llmBoundaryService.videoResults.count
        let isBlocked = total == 0
        let ready = total - done
        let partials = LLMDigestionService.findPartialBoundaryResults().count

        var actions: [LLMPipelineAction] = []
        if !isBlocked && ready > 0 {
            actions.append(.init(label: "Run 1", style: .secondary) {
                Task { await llmService.runBoundariesOnly(videos: viewModel.videos, limit: 1) }
            })
            actions.append(.init(label: "Run 3", style: .secondary) {
                Task { await llmService.runBoundariesOnly(videos: viewModel.videos, limit: 3) }
            })
            actions.append(.init(label: "Run 5", style: .secondary) {
                Task { await llmService.runBoundariesOnly(videos: viewModel.videos, limit: 5) }
            })
            actions.append(.init(label: "Run 10", style: .secondary) {
                Task { await llmService.runBoundariesOnly(videos: viewModel.videos, limit: 10) }
            })
            actions.append(.init(label: "All (\(ready))", style: .primary) {
                Task { await llmService.runBoundariesOnly(videos: viewModel.videos) }
            })
        }
        if partials > 0 {
            actions.append(.init(label: "Fix Partial (\(partials))", style: .secondary) {
                Task { await llmService.rerunPartialBoundaries(videos: viewModel.videos) }
            })
        }

        return LLMPipelineStep(
            number: 3,
            title: "Boundaries",
            subtitle: "LLM splitter finds section breaks",
            color: .blue,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 2 : nil,
            feedsNext: done,
            isRunning: llmService.isRunning && llmService.currentStep == "Boundaries",
            runningText: llmService.progress,
            isAutoComputed: false,
            actions: actions,
            partialCount: partials
        )
    }

    private var moveStep: LLMPipelineStep {
        let done = viewModel.videosWithRhetoricalSequence
        // total = videos with boundaries (eligible for move extraction)
        let total = viewModel.llmBoundaryService.videoResults.count
        let isBlocked = total == 0
        // ready = videos that have boundaries but no rhetorical sequence yet
        let boundaryVideoIds = Set(viewModel.llmBoundaryService.videoResults.map { $0.videoId })
        let ready = viewModel.videos.filter {
            boundaryVideoIds.contains($0.videoId) && $0.rhetoricalSequence == nil
        }.count
        return LLMPipelineStep(
            number: 4,
            title: "Moves",
            subtitle: "Extract rhetorical moves per section",
            color: .pink,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 3 : nil,
            feedsNext: done,
            isRunning: llmService.isRunning && llmService.currentStep == "Moves",
            runningText: llmService.progress,
            isAutoComputed: false,
            actions: isBlocked || ready <= 0 ? [] : [
                .init(label: "Run 1", style: .secondary) {
                    Task { await llmService.runMovesOnly(videos: viewModel.videos, limit: 1) }
                },
                .init(label: "Run 3", style: .secondary) {
                    Task { await llmService.runMovesOnly(videos: viewModel.videos, limit: 3) }
                },
                .init(label: "Run 5", style: .secondary) {
                    Task { await llmService.runMovesOnly(videos: viewModel.videos, limit: 5) }
                },
                .init(label: "Run 10", style: .secondary) {
                    Task { await llmService.runMovesOnly(videos: viewModel.videos, limit: 10) }
                },
                .init(label: "All (\(ready))", style: .primary) {
                    Task { await llmService.runMovesOnly(videos: viewModel.videos) }
                }
            ]
        )
    }
}

// MARK: - Supporting Types

private struct LLMPipelineStep {
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
    let actions: [LLMPipelineAction]
    var partialCount: Int? = nil
}

private struct LLMPipelineAction {
    enum Style { case primary, secondary }
    let label: String
    let style: Style
    let handler: () -> Void
}
