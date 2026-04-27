//
//  NarrativeSpinePipelineSection.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import SwiftUI

struct NarrativeSpinePipelineSection: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel
    @ObservedObject private var viewModel = CreatorDetailViewModel.shared
    @ObservedObject private var spineService = NarrativeSpineService.shared

    @State private var showFidelityPicker = false
    @State private var fidelitySearchText = ""
    @State private var fidelitySearchQuery = ""

    // MARK: - Computed Properties

    private var videosWithTranscript: Int {
        viewModel.videos.filter { $0.hasTranscript }.count
    }

    private var videosWithSpineComplete: Int {
        viewModel.videos.filter { $0.hasNarrativeSpine }.count
    }

    private var eligibleCount: Int {
        viewModel.videos.filter {
            $0.hasTranscript && $0.narrativeSpineStatus?.complete != true
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
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                Text("Narrative Spine Pipeline")
                    .font(.subheadline.bold())
                Spacer()

                let total = videosWithTranscript
                let done = videosWithSpineComplete
                let pct = total > 0 ? Int(Double(done) / Double(total) * 100) : 0
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text("\(pct)%")
                    .font(.caption.bold())
                    .foregroundColor(pct >= 100 ? .green : .orange)
            }

            // Progress bar
            ProgressView(value: videosWithTranscript > 0
                ? Double(videosWithSpineComplete) / Double(videosWithTranscript)
                : 0)
                .tint(videosWithSpineComplete == videosWithTranscript && videosWithTranscript > 0 ? .green : .orange)

            // Run buttons or progress
            if !spineService.isRunning {
                if eligibleCount > 0 {
                    runButtonsRow
                }

                // Fidelity test button
                if videosWithTranscript > 0 {
                    fidelityButton
                }

                // Creator Narrative Profile button
                if videosWithSpineComplete >= 3 {
                    profileButton
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
                        await spineService.runSpineExtraction(videos: viewModel.videos, limit: limit)
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
                    .background(Color.orange.opacity(0.08))
                    .foregroundColor(.orange)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task {
                    await spineService.runSpineExtraction(videos: viewModel.videos, limit: nil)
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
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
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
                Text(spineService.progress)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Per-video progress
            let perVideo = spineService.perVideoProgress
            if !perVideo.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(perVideo.keys.prefix(5)), id: \.self) { videoId in
                        if let stepProgress = perVideo[videoId],
                           let video = viewModel.videos.first(where: { $0.videoId == videoId }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                                Text(video.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Text("- \(stepProgress)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.05))
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
                Text("Spine Fidelity Test")
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

    // MARK: - Creator Narrative Profile Button

    private var profileButton: some View {
        Button {
            nav.push(.creatorNarrativeProfile(channel))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 10))
                Text("Creator Narrative Profile")
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.12))
            .foregroundColor(.blue)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Picker Sheet

    private var fidelityVideoPickerSheet: some View {
        let eligible = viewModel.videos
            .filter { $0.hasTranscript }
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
                            .background(Color.orange.opacity(0.12))
                            .foregroundColor(.orange)
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
                            ? "No eligible videos (need transcript)"
                            : "No videos matching \"\(fidelitySearchQuery)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filtered, id: \.videoId) { video in
                            Button {
                                showFidelityPicker = false
                                fidelitySearchText = ""
                                fidelitySearchQuery = ""
                                nav.push(.narrativeSpineFidelityTester(video, channel))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(video.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        if video.hasNarrativeSpine {
                                            Label("Spine Done", systemImage: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        } else {
                                            Label("No Spine", systemImage: "circle")
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
            .navigationTitle("Pick Video for Spine Fidelity Test")
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
