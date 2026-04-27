//
//  SpineAlignmentPipelineSection.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/2/26.
//

import SwiftUI

struct SpineAlignmentPipelineSection: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel
    @ObservedObject private var viewModel = CreatorDetailViewModel.shared
    @ObservedObject private var alignmentService = SpineAlignmentService.shared

    @State private var showFidelityPicker = false
    @State private var fidelitySearchText = ""
    @State private var fidelitySearchQuery = ""

    // MARK: - Computed Properties

    /// Videos that have BOTH narrative spine and rhetorical sequence
    private var videosWithBoth: Int {
        viewModel.videos.filter { $0.hasNarrativeSpine && $0.hasRhetoricalSequence }.count
    }

    /// Videos with at least 1 alignment run
    private var videosWithAlignmentComplete: Int {
        viewModel.videos.filter { $0.hasSpineAlignment }.count
    }

    /// Videos with all 3 alignment runs complete
    private var videosWithAllRuns: Int {
        viewModel.videos.filter { $0.hasAllSpineAlignmentRuns }.count
    }

    /// Videos eligible for more runs (have both spine + rhetorical, but < 3 runs)
    private var eligibleCount: Int {
        viewModel.videos.filter {
            $0.hasNarrativeSpine && $0.hasRhetoricalSequence &&
            ($0.spineAlignmentStatus?.completedRunCount ?? 0) < 3
        }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pipelineHeader
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Header

    private var pipelineHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "link.circle")
                    .font(.subheadline)
                    .foregroundColor(.teal)
                Text("Spine-Move Alignment")
                    .font(.subheadline.bold())
                Spacer()

                let total = videosWithBoth
                let allDone = videosWithAllRuns
                let pct = total > 0 ? Int(Double(allDone) / Double(total) * 100) : 0
                Text("\(allDone)/\(total) (3x)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text("\(pct)%")
                    .font(.caption.bold())
                    .foregroundColor(pct >= 100 ? .green : .teal)
            }

            // Progress bar — tracks 3-run completion
            ProgressView(value: videosWithBoth > 0
                ? Double(videosWithAllRuns) / Double(videosWithBoth)
                : 0)
                .tint(videosWithAllRuns == videosWithBoth && videosWithBoth > 0 ? .green : .teal)

            // Run breakdown
            if videosWithBoth > 0 {
                HStack(spacing: 12) {
                    Label("\(videosWithAlignmentComplete) w/ 1+ run", systemImage: "1.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Label("\(videosWithAllRuns) w/ 3 runs", systemImage: "3.circle")
                        .font(.caption2)
                        .foregroundColor(videosWithAllRuns == videosWithBoth ? .green : .secondary)
                }
            }

            // Run buttons or progress
            if !alignmentService.isRunning {
                if eligibleCount > 0 {
                    runButtonsRow
                }

                // Fidelity test button
                if videosWithBoth > 0 {
                    fidelityButton
                }

                // Mapping table button
                if videosWithAlignmentComplete >= 3 {
                    mappingTableButton
                }

                // Confusable pairs button (appears once any videos have 3 runs)
                if videosWithAllRuns > 0 {
                    confusablePairsButton
                }
            } else {
                runningProgressSection
            }
        }
    }

    // MARK: - Run Buttons

    private var runButtonsRow: some View {
        HStack(spacing: 6) {
            ForEach([1, 3, 5, 10], id: \.self) { limit in
                Button {
                    Task {
                        await alignmentService.runBatchAlignment(videos: viewModel.videos, limit: limit)
                        await viewModel.loadVideos()
                    }
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
                Task {
                    await alignmentService.runBatchAlignment(videos: viewModel.videos, limit: nil)
                    await viewModel.loadVideos()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                    Text("All (\(eligibleCount))")
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

    // MARK: - Running Progress

    private var runningProgressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(alignmentService.progress)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Per-video progress
            let perVideo = alignmentService.perVideoProgress
            if !perVideo.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(perVideo.keys.prefix(15)), id: \.self) { videoId in
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

    // MARK: - Fidelity Test Button

    private var fidelityButton: some View {
        Button {
            showFidelityPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 10))
                Text("Alignment Fidelity Test")
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.purple.opacity(0.12))
            .foregroundColor(.purple)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFidelityPicker) {
            fidelityVideoPickerSheet
        }
    }

    // MARK: - Mapping Table Button

    private var mappingTableButton: some View {
        Button {
            nav.push(.spineAlignmentMappingTable(channel))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tablecells")
                    .font(.system(size: 10))
                Text("Mapping Table")
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.indigo.opacity(0.12))
            .foregroundColor(.indigo)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confusable Pairs Button

    private var confusablePairsButton: some View {
        Button {
            nav.push(.spineAlignmentConfusablePairs(channel))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 10))
                Text("Confusable Pairs (\(videosWithAllRuns) videos)")
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.12))
            .foregroundColor(.orange)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Picker Sheet

    private var fidelityVideoPickerSheet: some View {
        let eligible = viewModel.videos
            .filter { $0.hasNarrativeSpine && $0.hasRhetoricalSequence }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let filtered = fidelitySearchQuery.isEmpty
            ? eligible
            : eligible.filter { $0.title.localizedCaseInsensitiveContains(fidelitySearchQuery) }

        return NavigationStack {
            VStack(spacing: 0) {
                // Search bar
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
                            ? "No eligible videos (need both spine + rhetorical sequence)"
                            : "No videos matching \"\(fidelitySearchQuery)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filtered, id: \.videoId) { video in
                            Button {
                                showFidelityPicker = false
                                fidelitySearchText = ""
                                fidelitySearchQuery = ""
                                nav.push(.spineAlignmentFidelityTester(video, channel))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(video.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        let runCount = video.spineAlignmentStatus?.completedRunCount ?? 0
                                        if runCount >= 3 {
                                            Label("3/3 runs", systemImage: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        } else if runCount > 0 {
                                            Label("\(runCount)/3 runs", systemImage: "arrow.triangle.2.circlepath")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        } else {
                                            Label("Not Aligned", systemImage: "circle")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Text(video.durationFormatted)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick Video for Alignment Fidelity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showFidelityPicker = false
                        fidelitySearchText = ""
                        fidelitySearchQuery = ""
                    }
                }
            }
        }
    }
}
