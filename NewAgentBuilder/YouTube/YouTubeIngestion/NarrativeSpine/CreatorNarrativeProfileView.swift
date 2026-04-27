//
//  CreatorNarrativeProfileView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import SwiftUI

// MARK: - View Model

@MainActor
class CreatorNarrativeProfileViewModel: ObservableObject {
    let channel: YouTubeChannel
    @Published var profile: CreatorNarrativeProfile?
    @Published var isLoading = false
    @Published var stalenessInfo: (isStale: Bool, newCount: Int, removedCount: Int)?

    private let firebase = CreatorNarrativeProfileFirebaseService.shared
    private let spineFirebase = NarrativeSpineFirebaseService.shared

    init(channel: YouTubeChannel) {
        self.channel = channel
    }

    func load() async {
        isLoading = true
        do {
            profile = try await firebase.loadProfile(channelId: channel.channelId)
        } catch {
            print("⚠️ Failed to load profile: \(error.localizedDescription)")
        }

        // Check staleness
        if profile != nil {
            let spines = (try? await spineFirebase.loadSpines(channelId: channel.channelId)) ?? []
            let currentVideoIds = spines.map { $0.videoId }
            let profileSet = Set(profile?.includedVideoIds ?? [])
            let currentSet = Set(currentVideoIds)
            let newIds = currentSet.subtracting(profileSet)
            let removedIds = profileSet.subtracting(currentSet)
            stalenessInfo = (
                isStale: !newIds.isEmpty || !removedIds.isEmpty,
                newCount: newIds.count,
                removedCount: removedIds.count
            )
        }
        isLoading = false
    }

    var fullProfileText: String {
        profile?.renderedText ?? ""
    }
}

// MARK: - Main View

struct CreatorNarrativeProfileView: View {
    let channel: YouTubeChannel

    @StateObject private var viewModel: CreatorNarrativeProfileViewModel
    @ObservedObject private var buildService = CreatorNarrativeProfileService.shared
    @ObservedObject private var detailVM = CreatorDetailViewModel.shared
    @State private var selectedTab = 0

    init(channel: YouTubeChannel) {
        self.channel = channel
        _viewModel = StateObject(wrappedValue: CreatorNarrativeProfileViewModel(channel: channel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if buildService.buildPhase != .idle && buildService.buildPhase != .complete && buildService.buildPhase != .failed {
                    buildProgressSection
                }

                if let error = buildService.error {
                    errorSection(error)
                }

                if let profile = viewModel.profile {
                    stalenessWarning

                    Picker("Layer", selection: $selectedTab) {
                        Text("Signatures").tag(0)
                        Text("Phases").tag(1)
                        Text("Throughlines").tag(2)
                        Text("Beats").tag(3)
                        Text("Exemplars").tag(4)
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case 0: signatureSection(profile.signatureAggregation, spineCount: profile.spineCount)
                    case 1: phaseSection(profile.phasePatterns)
                    case 2: throughlineSection(profile.throughlinePatterns)
                    case 3: beatSection(profile.beatDistribution)
                    case 4: representativeSection(profile.representativeSpines)
                    default: EmptyView()
                    }
                } else if !viewModel.isLoading && buildService.buildPhase == .idle {
                    noProfileSection
                }
            }
            .padding()
        }
        .navigationTitle("Narrative Profile")
        .task { await viewModel.load() }
        .onChange(of: buildService.buildPhase) { _, newPhase in
            if newPhase == .complete {
                Task { await viewModel.load() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.headline)
                    if let profile = viewModel.profile {
                        Text("Built from \(profile.spineCount) spines | \(profile.generatedAt, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()

                if viewModel.profile != nil {
                    CompactCopyButton(text: viewModel.fullProfileText)
                }
            }

            // Build / Rebuild button
            let isBusy = buildService.buildPhase != .idle
                && buildService.buildPhase != .complete
                && buildService.buildPhase != .failed
            if !isBusy {
                Button {
                    Task {
                        await buildService.buildProfile(channel: channel, videos: detailVM.videos)
                    }
                } label: {
                    Label(
                        viewModel.profile == nil ? "Build Profile" : "Rebuild Profile",
                        systemImage: viewModel.profile == nil ? "hammer.fill" : "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }

    // MARK: - Build Progress

    private var buildProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(buildService.buildPhase.displayName)
                    .font(.subheadline)
            }

            let phases: [ProfileBuildPhase] = [.loadingSpines, .buildingLayers, .selectingRepresentatives, .saving]
            let currentIndex = phases.firstIndex(of: buildService.buildPhase) ?? 0
            ProgressView(value: Double(currentIndex), total: Double(phases.count))
                .tint(.orange)
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Staleness Warning

    @ViewBuilder
    private var stalenessWarning: some View {
        if let info = viewModel.stalenessInfo, info.isStale {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile is stale")
                        .font(.caption.bold())
                    if info.newCount > 0 {
                        Text("\(info.newCount) new spine(s) not included")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if info.removedCount > 0 {
                        Text("\(info.removedCount) spine(s) removed since last build")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // MARK: - Layer 1: Signatures

    @ViewBuilder
    private func signatureSection(_ layer: SignatureAggregationLayer, spineCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Structural Signatures")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(layer.clusteredSignatures.count) patterns from \(layer.totalSignaturesInput) raw")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(layer.clusteredSignatures) { sig in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sig.canonicalName)
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(sig.frequency)/\(spineCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", sig.frequencyPercent))
                            .font(.caption.bold())
                            .foregroundColor(sig.frequencyPercent >= 50 ? .green : .orange)
                    }
                    Text(sig.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if sig.variants.count > 1 {
                        FlowLayout(spacing: 4) {
                            ForEach(sig.variants, id: \.self) { variant in
                                Text(variant)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Layer 2: Phases

    @ViewBuilder
    private func phaseSection(_ layer: PhasePatternLayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Phase Architecture")
                    .font(.subheadline.bold())
                Spacer()
                Text("Typical: \(layer.typicalPhaseCount.mode) phases (range \(layer.typicalPhaseCount.min)-\(layer.typicalPhaseCount.max))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(layer.typicalArchitecture) { phase in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Phase \(phase.phasePosition)")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                        Text(phase.commonNames.first ?? "?")
                            .font(.subheadline)
                        Spacer()
                        Text(phase.typicalBeatSpan)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    if !phase.definingTechniques.isEmpty {
                        Text(phase.definingTechniques.prefix(2).joined(separator: "; "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(4)
            }

            Divider()

            Text(layer.architectureNarrative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Layer 3: Throughlines

    @ViewBuilder
    private func throughlineSection(_ layer: ThroughlinePatternLayer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Throughline Patterns")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Recurring Movement Pattern")
                    .font(.caption.bold())
                Text(layer.recurringMovementPattern)
                    .font(.subheadline)
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opening Moves")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                    ForEach(layer.commonOpeningMoves, id: \.self) { move in
                        Text("- \(move)")
                            .font(.caption)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Closing Moves")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                    ForEach(layer.commonClosingMoves, id: \.self) { move in
                        Text("- \(move)")
                            .font(.caption)
                    }
                }
            }

            Divider()

            Text(layer.throughlineNarrative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Layer 4: Beats

    @ViewBuilder
    private func beatSection(_ layer: BeatDistributionLayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Beat Function Distribution")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(layer.totalBeatsAnalyzed) total beats")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Global distribution as horizontal bars
            ForEach(layer.globalDistribution.prefix(15)) { freq in
                HStack(spacing: 8) {
                    Text(freq.functionLabel)
                        .font(.caption)
                        .frame(width: 120, alignment: .trailing)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(freq.percent / 100.0))
                            .cornerRadius(2)
                    }
                    .frame(height: 14)
                    Text(String(format: "%.1f%%", freq.percent))
                        .font(.caption2.monospacedDigit())
                        .frame(width: 45, alignment: .trailing)
                }
            }

            Divider()

            // Positional patterns
            Text("Positional Patterns")
                .font(.caption.bold())
                .padding(.top, 4)

            ForEach(layer.positionalDistribution.prefix(20)) { pos in
                HStack(spacing: 6) {
                    Text("Beat \(pos.beatPosition)")
                        .font(.caption.monospacedDigit().bold())
                        .frame(width: 50, alignment: .trailing)
                    Text("(\(pos.spinesCoveringThisPosition))")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .trailing)
                    ForEach(pos.topFunctions.indices, id: \.self) { i in
                        let func_ = pos.topFunctions[i]
                        Text("\(String(format: "%.0f%%", func_.percent)) \(func_.functionLabel)")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(i == 0 ? Color.orange.opacity(0.1) : Color(.systemGray6))
                            .cornerRadius(3)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Exemplars

    @ViewBuilder
    private func representativeSection(_ reps: [RepresentativeSpine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Representative Spines (\(reps.count))")
                .font(.subheadline.bold())

            Text("Spines that best match the overall profile pattern")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(reps) { rep in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(rep.videoTitle)
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer()
                        Text(String(format: "%.0f%%", rep.matchScore * 100))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(.orange)
                    }
                    Text(rep.matchReason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - No Profile / Error

    private var noProfileSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No profile generated yet")
                .font(.subheadline)
            Text("Build a profile to aggregate patterns from all narrative spines")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func errorSection(_ message: String) -> some View {
        Text(message)
            .foregroundColor(.red)
            .font(.caption)
            .padding(8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(6)
    }
}
