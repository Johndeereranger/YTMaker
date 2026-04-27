//
//  CreatorFingerprintView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/14/26.
//

import SwiftUI

struct CreatorFingerprintView: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel

    // MARK: - State

    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Slot availability
    @State private var slotAvailabilities: [FingerprintSlotKey: FingerprintSlotAvailability] = [:]
    @State private var existingFingerprints: [FingerprintDocument] = []

    // Configuration
    @State private var minimumSampleSize: Int = 3

    // Slot inspector (tapped cell)
    @State private var selectedInspectSlot: FingerprintSlotKey?

    // Testing section
    @State private var selectedMoveLabel: RhetoricalMoveType = .personalStake
    @State private var selectedPosition: FingerprintPosition = .first
    @State private var testResults: [FingerprintPromptType: FingerprintGenerationResult] = [:]
    @State private var isRunningTest = false
    @State private var showTestDebug = false

    // Batch run
    @StateObject private var generationService = FingerprintGenerationService()

    // Data collector
    private var collector: FingerprintDataCollector {
        var c = FingerprintDataCollector()
        c.minimumSampleSize = minimumSampleSize
        return c
    }

    // MARK: - Computed

    private var selectedSlotKey: FingerprintSlotKey {
        FingerprintSlotKey(moveLabel: selectedMoveLabel, position: selectedPosition)
    }

    private var selectedAvailability: FingerprintSlotAvailability? {
        slotAvailabilities[selectedSlotKey]
    }

    private var inspectedAvailability: FingerprintSlotAvailability? {
        guard let key = selectedInspectSlot else { return nil }
        return slotAvailabilities[key]
    }

    private var summary: SlotSummary {
        FingerprintDataCollector.summarize(slotAvailabilities, minimum: minimumSampleSize)
    }

    private var categorizedMoveLabels: [(category: RhetoricalCategory, moves: [RhetoricalMoveType])] {
        let grouped = Dictionary(grouping: RhetoricalMoveType.allCases, by: { $0.category })
        return RhetoricalCategory.allCases.compactMap { cat in
            guard let moves = grouped[cat], !moves.isEmpty else { return nil }
            return (category: cat, moves: moves)
        }
    }

    private var promptTypeCount: Int {
        FingerprintPromptType.allCases.count
    }

    // MARK: - Body

    var body: some View {
        List {
            dashboardSection
            if selectedInspectSlot != nil {
                slotInspectorSection
            }
            testingSection
            batchRunSection
            existingFingerprintsSection
        }
        .navigationTitle("Fingerprints")
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
                summaryRow

                // Minimum sample size
                Stepper("Min samples: \(minimumSampleSize)", value: $minimumSampleSize, in: 1...20)

                // Grid by category
                ForEach(categorizedMoveLabels, id: \.category) { group in
                    categoryGrid(group.category, moves: group.moves)
                }

                // Copy availability summary
                CompactCopyButton(text: availabilitySummaryText, fadeDuration: 2.0)

                // Bulk copy: all Position #1 titles + sample texts (excl. Scene Set)
                if hasAnyPositionOneData {
                    FadeOutCopyButton(
                        text: positionOneSamplesText,
                        label: "Copy All Pos #1 Titles + Samples (excl. Scene Set)"
                    )
                }
            }
        } header: {
            Text("Data Availability")
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 16) {
            statBadge("\(summary.slotsWithData)", label: "With Data", color: .blue)
            statBadge("\(summary.slotsWithSufficientData)", label: "Ready", color: .yellow)
            statBadge("\(summary.slotsGenerated)", label: "Generated", color: .green)
            if summary.slotsStale > 0 {
                statBadge("\(summary.slotsStale)", label: "Stale", color: .orange)
            }
            if summary.totalFingerprints > 0 {
                statBadge("\(summary.totalFingerprints)", label: "Total FPs", color: .purple)
            }
        }
        .font(.caption)
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

    private func categoryGrid(_ category: RhetoricalCategory, moves: [RhetoricalMoveType]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.rawValue)
                .font(.caption.bold())
                .foregroundColor(.secondary)

            // Header row
            HStack(spacing: 2) {
                Text("Move")
                    .font(.caption2)
                    .frame(width: 100, alignment: .leading)
                ForEach(FingerprintPosition.allCases, id: \.self) { pos in
                    Text(pos.shortLabel)
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity)
                }
            }

            // Data rows
            ForEach(moves, id: \.self) { move in
                HStack(spacing: 2) {
                    Text(move.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(width: 100, alignment: .leading)

                    ForEach(FingerprintPosition.allCases, id: \.self) { pos in
                        let key = FingerprintSlotKey(moveLabel: move, position: pos)
                        let avail = slotAvailabilities[key]
                        tappableSlotCell(key: key, availability: avail)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tappableSlotCell(key: FingerprintSlotKey, availability: FingerprintSlotAvailability?) -> some View {
        let count = availability?.exampleCount ?? 0
        let generatedCount = availability?.generatedCount ?? 0
        let hasAnyFingerprint = generatedCount > 0
        let isFullyGenerated = availability?.isFullyGenerated ?? false
        let isStale = availability?.isStale ?? false
        let isSelected = selectedInspectSlot == key

        let color: Color = {
            if count == 0 { return .gray.opacity(0.3) }
            if isFullyGenerated && !isStale { return .green }
            if hasAnyFingerprint && isStale { return .orange }
            if hasAnyFingerprint { return .mint }
            if count >= minimumSampleSize { return .yellow }
            return .red.opacity(0.6)
        }()

        return Button {
            if count > 0 {
                selectedInspectSlot = isSelected ? nil : key
                // Also update testing pickers to match
                selectedMoveLabel = key.moveLabel
                selectedPosition = key.position
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                if hasAnyFingerprint {
                    Text("\(generatedCount)/\(promptTypeCount)")
                        .font(.system(size: 7).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(color.opacity(isSelected ? 0.7 : 0.3))
            .cornerRadius(3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }

    // MARK: - Section 1.5: Slot Inspector (appears when cell tapped)

    private var slotInspectorSection: some View {
        Section {
            if let key = selectedInspectSlot, let avail = inspectedAvailability {
                // Header
                HStack {
                    Text(key.moveLabel.displayName)
                        .font(.headline)
                    Text(key.position.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                    Spacer()
                    Button {
                        selectedInspectSlot = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("\(avail.exampleCount) examples from \(avail.sourceVideoIds.count) videos")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Stored fingerprint type indicators
                if avail.generatedCount > 0 {
                    storedFingerprintIndicators(avail)
                }

                // Copy all raw texts
                CopyAllButton(
                    items: avail.sampleTexts.enumerated().map { i, text in
                        let title = i < avail.sourceVideoTitles.count ? avail.sourceVideoTitles[i] : "Video \(i + 1)"
                        return "## \(title)\n\n\(text)"
                    },
                    separator: "\n\n---\n\n",
                    label: "Copy All Examples"
                )

                // Each example with video title
                ForEach(Array(avail.sampleTexts.enumerated()), id: \.offset) { i, text in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            let title = i < avail.sourceVideoTitles.count ? avail.sourceVideoTitles[i] : "Video \(i + 1)"
                            Text(title)
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                            Spacer()
                            CompactCopyButton(text: text, fadeDuration: 2.0)
                        }
                        Text(text)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Slot Inspector")
        }
    }

    private func storedFingerprintIndicators(_ avail: FingerprintSlotAvailability) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stored Fingerprints (\(avail.generatedCount)/\(promptTypeCount))")
                .font(.caption.bold())

            FlowLayout(spacing: 4) {
                ForEach(FingerprintPromptType.allCases, id: \.self) { type in
                    let exists = avail.existingFingerprints[type] != nil
                    let isStale = avail.stalePromptTypes.contains(type)
                    Text(type.shortLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            exists
                                ? (isStale ? Color.orange.opacity(0.3) : Color.green.opacity(0.3))
                                : Color.gray.opacity(0.15)
                        )
                        .cornerRadius(4)
                        .foregroundColor(exists ? (isStale ? .orange : .green) : .secondary)
                }
            }

            // Expandable view of each stored fingerprint
            ForEach(FingerprintPromptType.allCases, id: \.self) { type in
                if let fp = avail.existingFingerprints[type] {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fp.fingerprintText)
                                .font(.caption)
                                .textSelection(.enabled)
                            Text("\(fp.sourceVideoCount) videos | \(fp.generatedAt, style: .date)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: type.iconName)
                                .foregroundColor(type.tintColor)
                            Text(type.displayName)
                                .font(.caption.bold())
                            Spacer()
                            CompactCopyButton(text: fp.fingerprintText, fadeDuration: 2.0)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 2: Testing

    private var testingSection: some View {
        Section {
            // Move label picker
            Picker("Move", selection: $selectedMoveLabel) {
                ForEach(categorizedMoveLabels, id: \.category) { group in
                    ForEach(group.moves, id: \.self) { move in
                        Text(move.displayName).tag(move)
                    }
                }
            }

            // Position picker
            Picker("Position", selection: $selectedPosition) {
                ForEach(FingerprintPosition.allCases, id: \.self) { pos in
                    Text(pos.displayName).tag(pos)
                }
            }
            .pickerStyle(.segmented)

            // Availability info with stored-type indicators
            if let avail = selectedAvailability {
                HStack {
                    Text("\(avail.exampleCount) examples from \(avail.sourceVideoIds.count) videos")
                        .font(.callout)
                    Spacer()
                    if avail.generatedCount > 0 {
                        Text("\(avail.generatedCount)/\(promptTypeCount)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(avail.isFullyGenerated ? Color.green.opacity(0.2) : Color.mint.opacity(0.2))
                            .cornerRadius(4)
                        if avail.isStale {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
            } else {
                Text("No data for this slot")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            // Two buttons: Generate Test (preview) and Generate & Store (all types, save)
            HStack(spacing: 12) {
                Button {
                    Task { await runTestPreview() }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text(isRunningTest ? "Testing..." : "Generate Test")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRunningTest || (selectedAvailability?.exampleCount ?? 0) == 0)

                Button {
                    Task { await runGenerateAndStore() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                        Text(isRunningTest ? "Storing..." : "Generate & Store")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningTest || (selectedAvailability?.exampleCount ?? 0) == 0)
            }

            // Per-type test results
            if !testResults.isEmpty {
                ForEach(FingerprintPromptType.allCases, id: \.self) { type in
                    if let result = testResults[type] {
                        DisclosureGroup {
                            testResultView(result)
                        } label: {
                            HStack {
                                Image(systemName: type.iconName)
                                    .foregroundColor(type.tintColor)
                                Text(type.displayName)
                                    .font(.caption.bold())
                                Spacer()
                                Text(result.status.displayText)
                                    .font(.caption2)
                                    .foregroundColor(result.status == .success ? .green : .red)
                                if let text = result.fingerprintText {
                                    CompactCopyButton(text: text, fadeDuration: 2.0)
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Test Single Slot")
        }
    }

    private func testResultView(_ result: FingerprintGenerationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = result.fingerprintText {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let tokens = result.tokensUsed {
                Text("Tokens: \(tokens)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Debug toggle
            Toggle("Show Debug", isOn: $showTestDebug)
                .font(.caption)

            if showTestDebug {
                debugView(result)
            }
        }
    }

    private func debugView(_ result: FingerprintGenerationResult) -> some View {
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
            HStack {
                Text("\(summary.slotsWithSufficientData) slots ready")
                    .font(.callout)
                if promptTypeCount > 1 {
                    Text("x \(promptTypeCount) types = \(summary.slotsWithSufficientData * promptTypeCount) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("/ \(summary.totalSlots) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task { await runBatch() }
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Run All")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(generationService.isRunning || summary.slotsWithSufficientData == 0)

            if generationService.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(generationService.completedCount + generationService.failedCount),
                                 total: Double(generationService.totalCount))
                    Text("Completed: \(generationService.completedCount) | Failed: \(generationService.failedCount) / \(generationService.totalCount)")
                        .font(.caption)
                    if !generationService.currentSlotLabel.isEmpty {
                        Text(generationService.currentSlotLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Button("Cancel") {
                    generationService.cancel()
                }
                .foregroundColor(.red)
            }

            // Batch results
            if !generationService.results.isEmpty {
                ForEach(generationService.results.filter { $0.status.isTerminal }) { result in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(result.slotKey.moveLabel.displayName) - \(result.slotKey.position.displayName)")
                                .font(.caption.bold())
                            HStack(spacing: 4) {
                                Text(result.promptType.shortLabel)
                                    .font(.system(size: 9).bold())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(result.promptType.tintColor.opacity(0.2))
                                    .cornerRadius(3)
                                Text(result.status.displayText)
                                    .font(.caption2)
                                    .foregroundColor(result.status == .success ? .green : .red)
                            }
                        }
                        Spacer()
                        if let text = result.fingerprintText {
                            CompactCopyButton(text: text, fadeDuration: 2.0)
                        }
                    }
                }
            }
        } header: {
            Text("Batch Generation")
        }
    }

    // MARK: - Section 4: Existing Fingerprints

    private var existingFingerprintsSection: some View {
        Section {
            if existingFingerprints.isEmpty {
                Text("No fingerprints generated yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                // Copy all
                CopyAllButton(
                    items: existingFingerprints.map { fp in
                        let typeName = fp.promptTypeEnum?.displayName ?? fp.promptType
                        return "## \(fp.moveLabelType?.displayName ?? fp.moveLabel) (\(fp.positionType?.displayName ?? fp.position)) - \(typeName)\n\n\(fp.fingerprintText)"
                    },
                    separator: "\n\n---\n\n",
                    label: "Copy All Fingerprints"
                )

                // Grouped by category, then by slot, then by prompt type
                ForEach(categorizedMoveLabels, id: \.category) { group in
                    let fps = existingFingerprints.filter { fp in
                        group.moves.contains(where: { $0.rawValue == fp.moveLabel })
                    }
                    if !fps.isEmpty {
                        DisclosureGroup("\(group.category.rawValue) (\(fps.count))") {
                            // Sub-group by slot (moveLabel + position)
                            let grouped = Dictionary(grouping: fps) { "\($0.moveLabel)_\($0.position)" }
                            ForEach(grouped.keys.sorted(), id: \.self) { slotId in
                                if let slotFps = grouped[slotId], let first = slotFps.first {
                                    DisclosureGroup {
                                        ForEach(slotFps.sorted(by: { $0.promptType < $1.promptType }), id: \.id) { fp in
                                            fingerprintRow(fp)
                                        }
                                    } label: {
                                        HStack {
                                            Text(first.moveLabelType?.displayName ?? first.moveLabel)
                                                .font(.caption.bold())
                                            Text(first.positionType?.displayName ?? first.position)
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.blue.opacity(0.2))
                                                .cornerRadius(3)
                                            Spacer()
                                            Text("\(slotFps.count)/\(promptTypeCount)")
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
        } header: {
            Text("Existing Fingerprints (\(existingFingerprints.count))")
        }
    }

    private func fingerprintRow(_ fp: FingerprintDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let type = fp.promptTypeEnum {
                    Image(systemName: type.iconName)
                        .font(.caption2)
                        .foregroundColor(type.tintColor)
                    Text(type.displayName)
                        .font(.caption.bold())
                } else {
                    Text(fp.promptType)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                Spacer()
                CompactCopyButton(text: fp.fingerprintText, fadeDuration: 2.0)
            }

            Text("\(fp.sourceVideoCount) videos | \(fp.generatedAt, style: .date)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(fp.fingerprintText)
                .font(.caption)
                .lineLimit(4)
                .textSelection(.enabled)
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
            let videosWithSequences = videos.filter { $0.rhetoricalSequence != nil && $0.transcript != nil }
            print("Fingerprint: \(videosWithSequences.count)/\(videos.count) videos have rhetorical sequences + transcript")

            // Collect slot availability (uses raw transcript text)
            slotAvailabilities = collector.collectSlotAvailability(
                channelId: channel.channelId,
                videos: videos
            )

            // Load existing fingerprints
            existingFingerprints = try await FingerprintFirebaseService.shared.loadFingerprints(
                creatorId: channel.channelId
            )

            // Merge existing fingerprints into availability for stale detection
            var mutableSlots = slotAvailabilities
            collector.mergeExistingFingerprints(existingFingerprints, into: &mutableSlots)
            slotAvailabilities = mutableSlots

        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Actions

    /// Preview test: runs ALL prompt types without saving to Firebase
    private func runTestPreview() async {
        guard let avail = selectedAvailability, avail.exampleCount > 0 else { return }
        isRunningTest = true
        testResults = [:]

        let results = await generationService.generateAllTypes(
            slotKey: selectedSlotKey,
            availability: avail,
            creatorName: channel.name,
            creatorId: channel.channelId,
            saveToFirebase: false
        )

        for result in results {
            testResults[result.promptType] = result
        }
        isRunningTest = false
    }

    /// Generate all prompt types for the selected slot and store to Firebase
    private func runGenerateAndStore() async {
        guard let avail = selectedAvailability, avail.exampleCount > 0 else { return }
        isRunningTest = true
        testResults = [:]

        let results = await generationService.generateAllTypes(
            slotKey: selectedSlotKey,
            availability: avail,
            creatorName: channel.name,
            creatorId: channel.channelId,
            saveToFirebase: true
        )

        for result in results {
            testResults[result.promptType] = result
        }

        // Refresh existing fingerprints
        await refreshFingerprints()
        isRunningTest = false
    }

    private func runBatch() async {
        await generationService.generateAll(
            availabilities: slotAvailabilities,
            minimumSamples: minimumSampleSize,
            creatorName: channel.name,
            creatorId: channel.channelId
        )

        // Refresh existing fingerprints
        await refreshFingerprints()
    }

    private func refreshFingerprints() async {
        if let fps = try? await FingerprintFirebaseService.shared.loadFingerprints(
            creatorId: channel.channelId, forceRefresh: true
        ) {
            existingFingerprints = fps
            var mutableSlots = slotAvailabilities
            collector.mergeExistingFingerprints(fps, into: &mutableSlots)
            slotAvailabilities = mutableSlots
        }
    }

    // MARK: - Helpers

    private var availabilitySummaryText: String {
        var lines: [String] = ["Fingerprint Availability for \(channel.name)"]
        lines.append("Videos with sequences + transcript: \(videos.filter { $0.rhetoricalSequence != nil && $0.transcript != nil }.count)")
        lines.append("")

        for group in categorizedMoveLabels {
            lines.append("## \(group.category.rawValue)")
            for move in group.moves {
                var parts: [String] = [move.displayName]
                for pos in FingerprintPosition.allCases {
                    let key = FingerprintSlotKey(moveLabel: move, position: pos)
                    let count = slotAvailabilities[key]?.exampleCount ?? 0
                    parts.append("\(pos.shortLabel):\(count)")
                }
                lines.append(parts.joined(separator: " | "))
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Position #1 Bulk Copy

    private var hasAnyPositionOneData: Bool {
        RhetoricalMoveType.allCases.contains { move in
            guard move != .sceneSet else { return false }
            let key = FingerprintSlotKey(moveLabel: move, position: .first)
            return (slotAvailabilities[key]?.exampleCount ?? 0) > 0
        }
    }

    private var positionOneSamplesText: String {
        var lines: [String] = []
        let divider = String(repeating: "═", count: 50)
        lines.append(divider)
        lines.append("POSITION #1 SAMPLES — ALL TYPES (excl. Scene Set)")
        lines.append(divider)

        for group in categorizedMoveLabels {
            let filteredMoves = group.moves.filter { $0 != .sceneSet }
            guard !filteredMoves.isEmpty else { continue }

            // Check if any move in this category has Position #1 data
            let categoryHasData = filteredMoves.contains { move in
                let key = FingerprintSlotKey(moveLabel: move, position: .first)
                return (slotAvailabilities[key]?.exampleCount ?? 0) > 0
            }
            guard categoryHasData else { continue }

            lines.append("")
            lines.append("── \(group.category.rawValue.uppercased()) " + String(repeating: "─", count: max(0, 46 - group.category.rawValue.count)))

            for move in filteredMoves {
                let key = FingerprintSlotKey(moveLabel: move, position: .first)
                guard let avail = slotAvailabilities[key], avail.exampleCount > 0 else { continue }

                lines.append("")
                lines.append("### \(move.displayName) (Position #1) — \(avail.exampleCount) examples")
                lines.append("")

                for i in 0..<avail.sampleTexts.count {
                    let title = i < avail.sourceVideoTitles.count ? avail.sourceVideoTitles[i] : "Video \(i + 1)"
                    lines.append("**Video: \"\(title)\"**")
                    lines.append(avail.sampleTexts[i])
                    lines.append("")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
