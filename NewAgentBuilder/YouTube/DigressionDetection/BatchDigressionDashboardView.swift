import SwiftUI
import Combine

// MARK: - View Model

@MainActor
class BatchDigressionDashboardViewModel: ObservableObject {
    let channel: YouTubeChannel
    let service = BatchDigressionAnalysisService()

    // Filters
    @Published var selectedTier: ConfidenceTier? = nil      // nil = All
    @Published var selectedType: DigressionType? = nil       // nil = All
    @Published var selectedVerdict: RulesVerdict? = nil      // nil = All
    @Published var minSentenceCount: Int = 1                  // 1 = no filter

    // Video data (loaded from CreatorDetailViewModel)
    @Published var videos: [YouTubeVideo] = []
    @Published var sentenceData: [String: [SentenceFidelityTest]] = [:]
    @Published var isLoading = true

    private var cancellables = Set<AnyCancellable>()

    init(channel: YouTubeChannel) {
        self.channel = channel

        service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: Computed

    var filteredDigressions: [AggregatedDigression] {
        service.aggregate?.filtered(tier: selectedTier, type: selectedType, verdict: selectedVerdict, minSentenceCount: minSentenceCount) ?? []
    }

    var groupedByVideo: [(videoTitle: String, videoId: String, digressions: [AggregatedDigression])] {
        service.aggregate?.groupedByVideo(tier: selectedTier, type: selectedType, verdict: selectedVerdict, minSentenceCount: minSentenceCount) ?? []
    }

    var filteredCopyText: String {
        service.generateFilteredCopyText(
            channelName: channel.name,
            tier: selectedTier,
            type: selectedType,
            verdict: selectedVerdict,
            minSentenceCount: minSentenceCount
        )
    }

    var llmDetailCopyText: String {
        service.generateLLMDetailCopyText(
            channelName: channel.name,
            tier: selectedTier,
            type: selectedType,
            verdict: selectedVerdict,
            minSentenceCount: minSentenceCount
        )
    }

    var rulesDetailCopyText: String {
        service.generateRulesDetailCopyText(
            channelName: channel.name,
            tier: selectedTier,
            type: selectedType,
            verdict: selectedVerdict,
            minSentenceCount: minSentenceCount
        )
    }

    // Progress
    var completedVideoCount: Int {
        service.videoResults.filter { $0.isComplete }.count
    }

    var totalVideoCount: Int {
        service.videoResults.count
    }

    var videosWithSentenceData: Int {
        videos.filter { sentenceData[$0.videoId] != nil }.count
    }

    // MARK: Load

    func load() async {
        isLoading = true

        // Load videos and sentence data from shared VM
        let vm = CreatorDetailViewModel.shared
        await vm.setChannel(channel)
        videos = vm.videos
        sentenceData = vm.videoSentenceData

        // Load existing results and build aggregate
        await service.loadResults(forChannelId: channel.channelId)
        await service.buildAggregate(channelId: channel.channelId, sentenceData: sentenceData)

        isLoading = false
    }

    // MARK: Actions

    func runBatch() async {
        await service.runBatchAnalysis(
            channel: channel,
            videos: videos,
            sentenceData: sentenceData
        )
    }

    func resumeBatch() async {
        await service.resumeBatchAnalysis(
            channel: channel,
            videos: videos,
            sentenceData: sentenceData
        )
    }
}

// MARK: - Main View

struct BatchDigressionDashboardView: View {
    @StateObject private var viewModel: BatchDigressionDashboardViewModel
    @EnvironmentObject var nav: NavigationViewModel

    init(channel: YouTubeChannel) {
        _viewModel = StateObject(wrappedValue: BatchDigressionDashboardViewModel(channel: channel))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                loadingView
            } else {
                controlsSection
                Divider()

                if viewModel.service.isRunning {
                    progressSection
                    Divider()
                }

                if viewModel.service.aggregate != nil {
                    summaryStatsBar
                    filterBar
                    Divider()
                    mainContent
                } else {
                    emptyStateView
                }
            }
        }
        .navigationTitle("Batch Digression Analysis")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    nav.push(.digressionChunkComparison(viewModel.channel))
                } label: {
                    Label("Chunk Comparison", systemImage: "rectangle.split.2x1")
                }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading data...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.channel.name)
                    .font(.subheadline.bold())
                Text("\(viewModel.videosWithSentenceData) videos with sentence data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if viewModel.service.isRunning {
                Button("Stop") {}
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(true) // Informational only — stopping not yet supported
            } else {
                // Show incomplete count
                let incompleteCount = viewModel.videosWithSentenceData - viewModel.completedVideoCount
                if incompleteCount > 0 {
                    Button {
                        Task { await viewModel.resumeBatch() }
                    } label: {
                        Label("Resume (\(incompleteCount))", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    Task { await viewModel.runBatch() }
                } label: {
                    Label("Run Batch", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.videosWithSentenceData == 0)
            }
        }
        .padding()
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(viewModel.service.overallPhase)
                    .font(.caption.bold())
                    .foregroundColor(.blue)
                Spacer()
                Text("\(viewModel.service.currentVideoIndex)/\(viewModel.service.totalVideos)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            ProgressView(
                value: Double(viewModel.service.currentVideoIndex),
                total: Double(max(1, viewModel.service.totalVideos))
            )

            if !viewModel.service.currentVideoTitle.isEmpty {
                Text("Current: \(viewModel.service.currentVideoTitle) — Run \(viewModel.service.currentRunInVideo)/3")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
    }

    // MARK: - Summary Stats

    private var summaryStatsBar: some View {
        HStack(spacing: 8) {
            if let agg = viewModel.service.aggregate {
                Text("\(agg.totalDigressions) digressions across \(agg.videosComplete) videos")
                    .font(.caption.bold())

                Spacer()

                statBadge("\(agg.highConfidenceCount) 100%", color: .green)
                statBadge("\(agg.mediumConfidenceCount) 66%", color: .orange)
                statBadge("\(agg.lowConfidenceCount) 33%", color: .yellow)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 6) {
            // Row 1: Tier, Type, Verdict filters
            HStack(spacing: 12) {
                // Confidence Tier
                Picker("Tier", selection: $viewModel.selectedTier) {
                    Text("All Tiers").tag(ConfidenceTier?.none)
                    ForEach(ConfidenceTier.allCases) { tier in
                        Text(tier.shortLabel).tag(ConfidenceTier?.some(tier))
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                // Type
                Picker("Type", selection: $viewModel.selectedType) {
                    Text("All Types").tag(DigressionType?.none)
                    ForEach(DigressionType.allCases) { type in
                        HStack {
                            Circle().fill(type.color).frame(width: 8, height: 8)
                            Text(type.displayName)
                        }
                        .tag(DigressionType?.some(type))
                    }
                }
                .pickerStyle(.menu)

                // Verdict
                Picker("Verdict", selection: $viewModel.selectedVerdict) {
                    Text("All Verdicts").tag(RulesVerdict?.none)
                    Text("Confirmed").tag(RulesVerdict?.some(.confirmed))
                    Text("Neutral").tag(RulesVerdict?.some(.neutral))
                    Text("Contradicted").tag(RulesVerdict?.some(.contradicted))
                }
                .pickerStyle(.menu)

                // Sentence Length
                HStack(spacing: 4) {
                    Text("Min:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper(
                        "\(viewModel.minSentenceCount)s",
                        value: $viewModel.minSentenceCount,
                        in: 1...20
                    )
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 100)
                }

                Spacer()

                Text("\(viewModel.filteredDigressions.count) showing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Row 2: Copy buttons
            HStack(spacing: 8) {
                Spacer()

                FadeOutCopyButton(
                    text: viewModel.filteredCopyText,
                    label: "Copy Context",
                    systemImage: "doc.on.doc"
                )

                FadeOutCopyButton(
                    text: viewModel.llmDetailCopyText,
                    label: "Copy LLM Detail",
                    systemImage: "brain"
                )

                FadeOutCopyButton(
                    text: viewModel.rulesDetailCopyText,
                    label: "Copy Rules Detail",
                    systemImage: "checklist"
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.groupedByVideo, id: \.videoId) { group in
                    videoGroupSection(group)
                }

                if viewModel.filteredDigressions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("No digressions match current filters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
    }

    // MARK: - Video Group

    private func videoGroupSection(_ group: (videoTitle: String, videoId: String, digressions: [AggregatedDigression])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Video header
            HStack {
                Text(group.videoTitle)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text("(\(group.digressions.count) digressions)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))

            // Digression rows
            ForEach(group.digressions) { digression in
                digressionRow(digression)
                Divider().padding(.leading)
            }
        }
    }

    // MARK: - Digression Row

    private func digressionRow(_ digression: AggregatedDigression) -> some View {
        Button {
            nav.push(.digressionDeepDive(digression))
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(digression.region.primaryType.color)
                    .frame(width: 8, height: 8)

                Text(digression.region.primaryType.displayName)
                    .font(.caption)
                    .frame(width: 110, alignment: .leading)

                Text(digression.region.rangeLabel)
                    .font(.caption.monospaced())
                    .frame(width: 65, alignment: .leading)

                Text(digression.confidenceTier.fraction)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(digression.confidenceTier.color)
                    .frame(width: 30)

                Image(systemName: digression.rulesVerdict.symbol)
                    .foregroundColor(digression.rulesVerdict.color)
                    .font(.caption2)
                    .frame(width: 20)

                Text(digression.region.briefContent ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Batch Digression Analysis")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Run 3 digression detection tests per video across all videos for this creator, then analyze consistency patterns across all results.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if viewModel.videosWithSentenceData > 0 {
                Text("\(viewModel.videosWithSentenceData) videos ready for analysis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No videos with sentence data. Run sentence tagging first.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
