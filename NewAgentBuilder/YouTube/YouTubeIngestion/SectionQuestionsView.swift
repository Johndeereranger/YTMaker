//
//  SectionQuestionsView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/29/26.
//

import SwiftUI

struct SectionQuestionsView: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel

    // MARK: - State

    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // All collected sections (unfiltered)
    @State private var allSections: [SectionQuestionInput] = []

    // Existing results from Firebase
    @State private var existingDocs: [SectionQuestionsDocument] = []

    // Individual testing
    @State private var selectedVideoId: String?
    @State private var selectedSectionId: String? // SectionQuestionInput.id
    @State private var individualResult: SectionQuestionResult?
    @State private var isRunningIndividual = false
    @State private var showIndividualDebug = false

    // Batch filtering
    @State private var batchPositionFilter: FingerprintPosition? = .first
    @State private var batchMoveLabelFilter: RhetoricalMoveType?

    // Batch service
    @StateObject private var batchService = SectionQuestionsService()

    // MARK: - Computed

    private var videosWithSequences: [YouTubeVideo] {
        videos.filter { $0.rhetoricalSequence != nil && $0.transcript != nil }
    }

    private var selectedVideo: YouTubeVideo? {
        guard let id = selectedVideoId else { return nil }
        return videosWithSequences.first { $0.videoId == id }
    }

    private var sectionsForSelectedVideo: [SectionQuestionInput] {
        guard let id = selectedVideoId else { return [] }
        return allSections.filter { $0.videoId == id }
    }

    private var selectedSection: SectionQuestionInput? {
        guard let id = selectedSectionId else { return nil }
        return allSections.first { $0.id == id }
    }

    private var filteredBatchSections: [SectionQuestionInput] {
        SectionQuestionsService.collectSections(
            from: videos,
            filterMoveLabel: batchMoveLabelFilter,
            filterPosition: batchPositionFilter
        )
    }

    private var existingDocIds: Set<String> {
        Set(existingDocs.map { "\($0.videoId)_\($0.chunkIndex)" })
    }

    private var categorizedMoveLabels: [(category: RhetoricalCategory, moves: [RhetoricalMoveType])] {
        let grouped = Dictionary(grouping: RhetoricalMoveType.allCases, by: { $0.category })
        return RhetoricalCategory.allCases.compactMap { cat in
            guard let moves = grouped[cat], !moves.isEmpty else { return nil }
            return (category: cat, moves: moves)
        }
    }

    // Position counts for dashboard
    private var sectionCountByPosition: [FingerprintPosition: Int] {
        Dictionary(grouping: allSections, by: { $0.position })
            .mapValues { $0.count }
    }

    // MARK: - Body

    var body: some View {
        List {
            dashboardSection
            individualTestingSection
            batchRunSection
            existingResultsSection
        }
        .navigationTitle("Section Questions")
        .task {
            await loadData()
        }
    }

    // MARK: - Section 1: Dashboard

    private var dashboardSection: some View {
        Section {
            if isLoading {
                ProgressView("Loading video data...")
            } else if let error = errorMessage {
                Text(error).foregroundColor(.red)
            } else {
                // Summary stats
                HStack(spacing: 16) {
                    statBadge("\(allSections.count)", label: "Sections", color: .blue)
                    statBadge("\(videosWithSequences.count)", label: "Videos", color: .purple)
                    statBadge("\(existingDocs.count)", label: "Analyzed", color: .green)
                }
                .font(.caption)

                // Per-position counts
                HStack(spacing: 12) {
                    ForEach(FingerprintPosition.allCases, id: \.self) { pos in
                        let count = sectionCountByPosition[pos] ?? 0
                        VStack(spacing: 2) {
                            Text("\(count)")
                                .font(.caption.monospacedDigit().bold())
                            Text(pos.shortLabel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)

                // Move label summary
                DisclosureGroup("Sections by Move Type") {
                    ForEach(categorizedMoveLabels, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.category.rawValue)
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                            ForEach(group.moves, id: \.self) { move in
                                let count = allSections.filter { $0.moveType == move }.count
                                if count > 0 {
                                    HStack {
                                        Text(move.displayName)
                                            .font(.caption)
                                        Spacer()
                                        Text("\(count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } header: {
            Text("Data Overview")
        }
    }

    private func statBadge(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section 2: Individual Testing

    private var individualTestingSection: some View {
        Section {
            // Video picker
            Picker("Video", selection: $selectedVideoId) {
                Text("Select a video").tag(String?.none)
                ForEach(videosWithSequences, id: \.videoId) { video in
                    Text(video.title).tag(Optional(video.videoId))
                }
            }

            // Show moves for selected video
            if let _ = selectedVideo {
                let sections = sectionsForSelectedVideo
                if sections.isEmpty {
                    Text("No sections with valid sentence ranges")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sections) { section in
                        let isSelected = selectedSectionId == section.id
                        let alreadyAnalyzed = existingDocIds.contains(section.id)
                        Button {
                            selectedSectionId = isSelected ? nil : section.id
                        } label: {
                            HStack(spacing: 8) {
                                Text("#\(section.chunkIndex)")
                                    .font(.caption.monospacedDigit().bold())
                                    .frame(width: 28)
                                Text(section.moveType.displayName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .cornerRadius(4)
                                Text(section.position.shortLabel)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(3)
                                Spacer()
                                if alreadyAnalyzed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Selected section details + actions
            if let section = selectedSection {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.briefDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    DisclosureGroup("Transcript Text") {
                        Text(section.sectionText)
                            .font(.caption)
                            .textSelection(.enabled)
                        CompactCopyButton(text: section.sectionText, fadeDuration: 2.0)
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        Task { await runIndividualTest(section: section, save: false) }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(isRunningIndividual ? "Testing..." : "Generate Test")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunningIndividual)

                    Button {
                        Task { await runIndividualTest(section: section, save: true) }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.doc.fill")
                            Text(isRunningIndividual ? "Storing..." : "Generate & Store")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunningIndividual)
                }

                // Individual result display
                if let result = individualResult {
                    individualResultView(result)
                }
            }
        } header: {
            Text("Individual Testing")
        }
    }

    private func individualResultView(_ result: SectionQuestionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.status.displayText)
                    .font(.caption.bold())
                    .foregroundColor(result.status == .success ? .green : .red)
                Spacer()
                if let text = result.questionsAnswered {
                    CompactCopyButton(text: text, fadeDuration: 2.0)
                }
            }

            if let text = result.questionsAnswered {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let tokens = result.tokensUsed {
                Text("Tokens: \(tokens)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Toggle("Show Debug", isOn: $showIndividualDebug)
                .font(.caption)

            if showIndividualDebug {
                debugView(result)
            }
        }
    }

    private func debugView(_ result: SectionQuestionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let system = result.systemPromptSent {
                DisclosureGroup("System Prompt") {
                    ScrollView {
                        Text(system).font(.caption2).textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    CompactCopyButton(text: system, fadeDuration: 2.0)
                }
            }

            if let prompt = result.promptSent {
                DisclosureGroup("User Prompt") {
                    ScrollView {
                        Text(prompt).font(.caption2).textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    CompactCopyButton(text: prompt, fadeDuration: 2.0)
                }
            }

            if let raw = result.rawResponse {
                DisclosureGroup("Raw Response") {
                    ScrollView {
                        Text(raw).font(.caption2).textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    CompactCopyButton(text: raw, fadeDuration: 2.0)
                }
            }
        }
    }

    // MARK: - Section 3: Batch Run

    private var batchRunSection: some View {
        Section {
            // Position filter
            Picker("Position", selection: $batchPositionFilter) {
                Text("All Positions").tag(FingerprintPosition?.none)
                ForEach(FingerprintPosition.allCases, id: \.self) { pos in
                    Text(pos.displayName).tag(Optional(pos))
                }
            }

            // Move label filter
            Picker("Move Label", selection: $batchMoveLabelFilter) {
                Text("All Move Types").tag(RhetoricalMoveType?.none)
                ForEach(categorizedMoveLabels, id: \.category) { group in
                    ForEach(group.moves, id: \.self) { move in
                        Text(move.displayName).tag(Optional(move))
                    }
                }
            }

            // Match count
            let matchCount = filteredBatchSections.count
            let alreadyDone = filteredBatchSections.filter { existingDocIds.contains($0.id) }.count
            HStack {
                Text("\(matchCount) sections match")
                    .font(.callout)
                Spacer()
                if alreadyDone > 0 {
                    Text("\(alreadyDone) already analyzed")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Run buttons
            HStack(spacing: 12) {
                Button {
                    Task { await runBatch(save: true) }
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Run Batch")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(batchService.isRunning || matchCount == 0)

                Button {
                    Task { await runBatch(save: false) }
                } label: {
                    HStack {
                        Image(systemName: "eye")
                        Text("Preview")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(batchService.isRunning || matchCount == 0)
            }

            // Progress
            if batchService.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(batchService.completedCount + batchService.failedCount),
                                 total: Double(batchService.totalCount))
                    Text("Completed: \(batchService.completedCount) | Failed: \(batchService.failedCount) / \(batchService.totalCount)")
                        .font(.caption)
                    if !batchService.currentLabel.isEmpty {
                        Text(batchService.currentLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Button("Cancel") {
                    batchService.cancel()
                }
                .foregroundColor(.red)
            }

            // Batch results
            if !batchService.results.isEmpty {
                let terminalResults = batchService.results.filter { $0.status.isTerminal }
                if !terminalResults.isEmpty {
                    DisclosureGroup("Batch Results (\(terminalResults.count))") {
                        ForEach(terminalResults) { result in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(result.input.moveType.displayName) #\(result.input.chunkIndex)")
                                        .font(.caption.bold())
                                    Text(result.input.videoTitle)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text(result.status.displayText)
                                        .font(.caption2)
                                        .foregroundColor(result.status == .success ? .green : .red)
                                }
                                Spacer()
                                if let text = result.questionsAnswered {
                                    CompactCopyButton(text: text, fadeDuration: 2.0)
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Batch Run")
        }
    }

    // MARK: - Section 4: Existing Results

    private var existingResultsSection: some View {
        Section {
            if existingDocs.isEmpty {
                Text("No section questions analyzed yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                // Copy all
                CopyAllButton(
                    items: existingDocs.map { doc in
                        let moveName = doc.moveLabelType?.displayName ?? doc.moveLabel
                        let posName = doc.positionType?.displayName ?? doc.position
                        return "## \(doc.videoTitle) — \(moveName) (\(posName)) #\(doc.chunkIndex)\n\n\(doc.questionsAnswered)"
                    },
                    separator: "\n\n---\n\n",
                    label: "Copy All Results"
                )

                // Group by video
                let groupedByVideo = Dictionary(grouping: existingDocs, by: { $0.videoId })
                let sortedVideoIds = groupedByVideo.keys.sorted { a, b in
                    let titleA = groupedByVideo[a]?.first?.videoTitle ?? a
                    let titleB = groupedByVideo[b]?.first?.videoTitle ?? b
                    return titleA < titleB
                }

                ForEach(sortedVideoIds, id: \.self) { videoId in
                    if let videoDocs = groupedByVideo[videoId] {
                        let videoTitle = videoDocs.first?.videoTitle ?? videoId
                        let sortedDocs = videoDocs.sorted { $0.chunkIndex < $1.chunkIndex }

                        DisclosureGroup("\(videoTitle) (\(sortedDocs.count))") {
                            ForEach(sortedDocs, id: \.id) { doc in
                                existingDocRow(doc)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Existing Results (\(existingDocs.count))")
        }
    }

    private func existingDocRow(_ doc: SectionQuestionsDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("#\(doc.chunkIndex)")
                    .font(.caption.monospacedDigit().bold())
                if let move = doc.moveLabelType {
                    Text(move.displayName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(3)
                }
                if let pos = doc.positionType {
                    Text(pos.shortLabel)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(3)
                }
                Spacer()
                CompactCopyButton(text: doc.questionsAnswered, fadeDuration: 2.0)
            }

            Text(doc.questionsAnswered)
                .font(.caption)
                .lineLimit(4)
                .textSelection(.enabled)

            Text("\(doc.generatedAt, style: .date) | \(doc.tokensUsed) tokens")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load videos
            videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channel.channelId)
            let withSequences = videosWithSequences.count
            print("SectionQuestions: \(withSequences)/\(videos.count) videos have rhetorical sequences + transcript")

            // Collect all sections
            allSections = SectionQuestionsService.collectSections(from: videos)

            // Load existing results
            existingDocs = try await SectionQuestionsFirebaseService.shared.loadAll(
                creatorId: channel.channelId
            )

        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Actions

    private func runIndividualTest(section: SectionQuestionInput, save: Bool) async {
        isRunningIndividual = true
        individualResult = nil

        let service = SectionQuestionsService()
        let result = await service.generateSingle(
            input: section,
            creatorName: channel.name,
            creatorId: channel.channelId,
            saveToFirebase: save
        )

        individualResult = result

        if save && result.status == .success {
            await refreshExistingDocs()
        }

        isRunningIndividual = false
    }

    private func runBatch(save: Bool) async {
        let inputs = filteredBatchSections

        await batchService.generateBatch(
            inputs: inputs,
            creatorName: channel.name,
            creatorId: channel.channelId,
            saveToFirebase: save
        )

        if save {
            await refreshExistingDocs()
        }
    }

    private func refreshExistingDocs() async {
        if let docs = try? await SectionQuestionsFirebaseService.shared.loadAll(
            creatorId: channel.channelId, forceRefresh: true
        ) {
            existingDocs = docs
        }
    }
}
