//
//  DonorLibraryPipelineSection.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import SwiftUI

// MARK: - Donor Library Pipeline Section (Snake Layout)

/// Inline section showing the 4-step donor library pipeline:
/// A2 (Slots) → A3 (Embed) → A4 (Bigram) → A5 (Rhythm) → Firebase
struct DonorLibraryPipelineSection: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel
    @ObservedObject private var viewModel = CreatorDetailViewModel.shared
    @ObservedObject private var a2Service = DonorLibraryA2Service.shared
    @ObservedObject private var a3Service = DonorLibraryA3Service.shared
    @ObservedObject private var a4Service = DonorLibraryA4Service.shared
    @ObservedObject private var a5Service = DonorLibraryA5Service.shared
    @State private var selectedStep: Int? = nil
    @State private var showFidelityVideoPicker = false
    @State private var fidelitySearchText = ""
    @State private var fidelitySearchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pipelineHeader

            // Row 1: Steps 1 → 2 → 3 (left to right)
            HStack(spacing: 6) {
                compactCard(step: slotStep)
                arrowConnector(flowing: slotStep.done > 0)
                compactCard(step: embedStep)
                arrowConnector(flowing: embedStep.done > 0)
                compactCard(step: bigramStep)
            }

            // Turn connector: right side drops down
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(bigramStep.done > 0 ? Color.green.opacity(0.5) : Color.gray.opacity(0.3))
                        .frame(width: 2, height: 10)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(bigramStep.done > 0 ? .green : .gray)
                }
                .padding(.trailing, 40)
            }

            // Row 2: Firebase ← Rhythm (right to left)
            HStack(spacing: 6) {
                firebaseTile
                arrowConnector(flowing: rhythmStep.done > 0, reversed: true)
                compactCard(step: rhythmStep)
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
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.subheadline)
                    .foregroundColor(.teal)
                Text("Donor Library Pipeline")
                    .font(.subheadline.bold())
                Spacer()

                let total = videosWithRhetoricalSequence
                let done = videosWithA5Complete
                let pct = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text("\(pct)%")
                    .font(.caption.bold())
                    .foregroundColor(pct >= 100 ? .green : .teal)
            }

            ProgressView(value: videosWithRhetoricalSequence > 0
                ? Double(videosWithA5Complete) / Double(videosWithRhetoricalSequence)
                : 0)
                .tint(videosWithA5Complete == videosWithRhetoricalSequence && videosWithRhetoricalSequence > 0 ? .green : .teal)

            // Run Full Pipeline buttons
            if !anyServiceRunning {
                let ready = eligibleForFullPipeline
                if ready > 0 {
                    HStack(spacing: 6) {
                        ForEach([1, 3, 5, 10], id: \.self) { limit in
                            Button {
                                Task { await runFullPipeline(limit: limit) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 9))
                                    Text("Run \(limit)")
                                        .font(.caption2.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.teal.opacity(0.08))
                                .foregroundColor(.teal)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            Task { await runFullPipeline(limit: nil) }
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
                            .background(Color.teal.opacity(0.15))
                            .foregroundColor(.teal)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Running progress
                let runningService = currentRunningService
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(runningService?.progress ?? "Processing...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Per-video progress
                let perVideo = runningService?.perVideoProgress ?? [:]
                if !perVideo.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(perVideo.keys.prefix(5)), id: \.self) { videoId in
                            if let stepProgress = perVideo[videoId],
                               let video = viewModel.videos.first(where: { $0.videoId == videoId }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.teal)
                                    Text(video.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                    Text("- \(stepProgress)")
                                        .font(.caption2)
                                        .foregroundColor(.teal)
                                }
                            }
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.teal.opacity(0.05))
                    .cornerRadius(4)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Run Full Pipeline (A2 → A3 → A4 → A5)

    private func runFullPipeline(limit: Int?) async {
        await a2Service.runSlotAnnotation(videos: viewModel.videos, limit: limit)
        // Reload videos to pick up updated donorLibraryStatus
        await viewModel.loadVideos()
        await a3Service.runEmbeddingGeneration(videos: viewModel.videos, limit: limit)
        await viewModel.loadVideos()
        await a4Service.runBigramComputation(videos: viewModel.videos, limit: limit)
        await viewModel.loadVideos()
        await a5Service.runRhythmExtraction(videos: viewModel.videos, limit: limit)
        await viewModel.loadVideos()
    }

    // MARK: - Compact Card

    private func compactCard(step: DonorPipelineStep) -> some View {
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
            Text("Donor Lib")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(videosWithA5Complete > 0 ? .green : .gray)
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

    private func expandedDetail(step: DonorPipelineStep) -> some View {
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
                    Text("Requires Step \(step.blockedByStep ?? 0) to complete first")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                ProgressView(value: step.total > 0 ? Double(step.done) / Double(step.total) : 0)
                    .tint(step.color)

                HStack(spacing: 12) {
                    Label("\(step.feedsNext) ready for next step", systemImage: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(step.feedsNext > 0 ? .green : .secondary)
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

                // Fidelity Test button (only for A2 Slots step)
                if step.number == 1 {
                    Divider()
                    Button {
                        showFidelityVideoPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 10))
                            Text("Slot Fidelity Test")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.12))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showFidelityVideoPicker) {
                        fidelityVideoPickerSheet
                    }

                    Button {
                        nav.push(.batchSlotFidelity(channel))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 10))
                            Text("Batch Fidelity")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        nav.push(.confusablePairs(channel))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 10))
                            Text("Confusable Pairs")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.08))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
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

    // MARK: - Fidelity Video Picker Sheet

    private var fidelityVideoPickerSheet: some View {
        let eligible = viewModel.videos
            .filter { $0.hasRhetoricalSequence && $0.hasTranscript }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let filtered = fidelitySearchQuery.isEmpty
            ? eligible
            : eligible.filter { $0.title.localizedCaseInsensitiveContains(fidelitySearchQuery) }

        return NavigationStack {
            VStack(spacing: 0) {
                // Search bar with button
                HStack(spacing: 8) {
                    TextField("Search videos...", text: $fidelitySearchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit { fidelitySearchQuery = fidelitySearchText }

                    Button {
                        fidelitySearchQuery = fidelitySearchText
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.subheadline.bold())
                            .padding(8)
                            .background(Color.teal.opacity(0.12))
                            .foregroundColor(.teal)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    if !fidelitySearchQuery.isEmpty {
                        Button {
                            fidelitySearchText = ""
                            fidelitySearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                List {
                    if filtered.isEmpty {
                        Text(eligible.isEmpty
                            ? "No eligible videos (need rhetorical sequence + transcript)"
                            : "No videos matching \"\(fidelitySearchQuery)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filtered, id: \.videoId) { video in
                            Button {
                                showFidelityVideoPicker = false
                                fidelitySearchText = ""
                                fidelitySearchQuery = ""
                                nav.push(.slotFidelityTester(video, channel))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(video.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        if video.donorLibraryStatus?.a2Complete == true {
                                            Label("A2 Done", systemImage: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        } else {
                                            Label("A2 Pending", systemImage: "circle")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick Video for Fidelity Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showFidelityVideoPicker = false
                        fidelitySearchText = ""
                        fidelitySearchQuery = ""
                    }
                }
            }
        }
    }

    // MARK: - Step Badge

    private func stepBadge(step: DonorPipelineStep) -> some View {
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

    // MARK: - Step Lookup

    private func stepFor(_ number: Int) -> DonorPipelineStep? {
        switch number {
        case 1: return slotStep
        case 2: return embedStep
        case 3: return bigramStep
        case 4: return rhythmStep
        default: return nil
        }
    }

    // MARK: - Computed Counts

    private var videosWithRhetoricalSequence: Int {
        viewModel.videos.filter { $0.hasRhetoricalSequence }.count
    }

    private var videosWithA2Complete: Int {
        viewModel.videos.filter { $0.donorLibraryStatus?.a2Complete == true }.count
    }

    private var videosWithA3Complete: Int {
        viewModel.videos.filter { $0.donorLibraryStatus?.a3Complete == true }.count
    }

    private var videosWithA4Complete: Int {
        viewModel.videos.filter { $0.donorLibraryStatus?.a4Complete == true }.count
    }

    private var videosWithA5Complete: Int {
        viewModel.videos.filter { $0.donorLibraryStatus?.a5Complete == true }.count
    }

    private var eligibleForFullPipeline: Int {
        viewModel.videos.filter {
            $0.hasRhetoricalSequence &&
            $0.hasTranscript &&
            $0.donorLibraryStatus?.a5Complete != true
        }.count
    }

    private var anyServiceRunning: Bool {
        a2Service.isRunning || a3Service.isRunning || a4Service.isRunning || a5Service.isRunning
    }

    private var currentRunningService: (any DonorServiceProgress)? {
        if a2Service.isRunning { return a2Service }
        if a3Service.isRunning { return a3Service }
        if a4Service.isRunning { return a4Service }
        if a5Service.isRunning { return a5Service }
        return nil
    }

    // MARK: - Step Definitions

    private var slotStep: DonorPipelineStep {
        let total = videosWithRhetoricalSequence
        let done = videosWithA2Complete
        let isBlocked = total == 0
        let ready = total - done
        return DonorPipelineStep(
            number: 1,
            title: "Slots",
            subtitle: "LLM annotates sentence slot sequences",
            color: .teal,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: nil,
            feedsNext: done,
            isRunning: a2Service.isRunning,
            runningText: a2Service.progress,
            actions: isBlocked || ready <= 0 ? [] : buildRunActions(ready: ready) { limit in
                Task { await a2Service.runSlotAnnotation(videos: viewModel.videos, limit: limit) }
            }
        )
    }

    private var embedStep: DonorPipelineStep {
        let total = videosWithA2Complete
        let done = videosWithA3Complete
        let isBlocked = total == 0
        let ready = total - done
        return DonorPipelineStep(
            number: 2,
            title: "Embed",
            subtitle: "Generate sentence embeddings",
            color: .cyan,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 1 : nil,
            feedsNext: done,
            isRunning: a3Service.isRunning,
            runningText: a3Service.progress,
            actions: isBlocked || ready <= 0 ? [] : buildRunActions(ready: ready) { limit in
                Task { await a3Service.runEmbeddingGeneration(videos: viewModel.videos, limit: limit) }
            }
        )
    }

    private var bigramStep: DonorPipelineStep {
        let total = videosWithA3Complete
        let done = videosWithA4Complete
        let isBlocked = total == 0
        let ready = total - done
        return DonorPipelineStep(
            number: 3,
            title: "Bigram",
            subtitle: "Compute slot transition tables",
            color: .blue,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 2 : nil,
            feedsNext: done,
            isRunning: a4Service.isRunning,
            runningText: a4Service.progress,
            actions: isBlocked || ready <= 0 ? [] : buildRunActions(ready: ready) { limit in
                Task { await a4Service.runBigramComputation(videos: viewModel.videos, limit: limit) }
            }
        )
    }

    private var rhythmStep: DonorPipelineStep {
        let total = videosWithA4Complete
        let done = videosWithA5Complete
        let isBlocked = total == 0
        let ready = total - done
        return DonorPipelineStep(
            number: 4,
            title: "Rhythm",
            subtitle: "Extract structural skeletons",
            color: .indigo,
            done: done,
            total: total,
            isBlocked: isBlocked,
            blockedByStep: isBlocked ? 3 : nil,
            feedsNext: done,
            isRunning: a5Service.isRunning,
            runningText: a5Service.progress,
            actions: isBlocked || ready <= 0 ? [] : buildRunActions(ready: ready) { limit in
                Task { await a5Service.runRhythmExtraction(videos: viewModel.videos, limit: limit) }
            }
        )
    }

    // MARK: - Build Run Actions

    private func buildRunActions(ready: Int, handler: @escaping (Int?) -> Void) -> [DonorPipelineAction] {
        var actions: [DonorPipelineAction] = []
        for limit in [1, 3, 5, 10] {
            actions.append(.init(label: "Run \(limit)", style: .secondary) { handler(limit) })
        }
        actions.append(.init(label: "All (\(ready))", style: .primary) { handler(nil) })
        return actions
    }
}

// MARK: - Progress Protocol

protocol DonorServiceProgress {
    var progress: String { get }
    var perVideoProgress: [String: String] { get }
}

extension DonorLibraryA2Service: DonorServiceProgress {}
extension DonorLibraryA3Service: DonorServiceProgress {}
extension DonorLibraryA4Service: DonorServiceProgress {}
extension DonorLibraryA5Service: DonorServiceProgress {}

// MARK: - Supporting Types

private struct DonorPipelineStep {
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
    let actions: [DonorPipelineAction]
}

private struct DonorPipelineAction {
    enum Style { case primary, secondary }
    let label: String
    let style: Style
    let handler: () -> Void
}
