//
//  GroundTruthView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/27/26.
//

import SwiftUI

private enum GroundTruthDisplayMode: String, CaseIterable {
    case currentViews = "Current Views"
    case codexConsensus = "Codex Consensus"
}

struct GroundTruthView: View {
    let video: YouTubeVideo
    @StateObject private var viewModel: GroundTruthViewModel

    @State private var displayMode: GroundTruthDisplayMode = .currentViews
    @State private var selectedTab = 0
    @State private var isReportCopied = false
    @State private var isBoundariesCopied = false
    @State private var isTranscriptCopied = false
    @State private var isCleanCopied = false
    @State private var isScoringCopied = false
    @State private var isAlignmentCopied = false
    @State private var showDisagreements = false
    @State private var expandedAlignmentRows: Set<Int> = []
    @State private var showWindowDetail = false
    @State private var windowDetailRunIndex: Int = 0

    init(video: YouTubeVideo) {
        self.video = video
        _viewModel = StateObject(wrappedValue: GroundTruthViewModel(video: video))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerSection
                if viewModel.result != nil {
                    displayModePicker
                }
                if let result = viewModel.result, !viewModel.isRunning {
                    switch displayMode {
                    case .currentViews:
                        summarySection(result)
                        tabPicker
                        tabContent(result)
                    case .codexConsensus:
                        CodexConsensusView(result: result)
                    }
                } else if viewModel.isRunning {
                    Spacer()
                } else {
                    emptyState
                    Spacer()
                }
                footerButtons
            }

            if viewModel.isRunning {
                runningOverlay
            }
        }
        .navigationTitle("Ground Truth")
        .task {
            await viewModel.loadSentences()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var displayModePicker: some View {
        Picker("Ground Truth Mode", selection: $displayMode) {
            ForEach(GroundTruthDisplayMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Header

    @State private var showConfig = false

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Button {
                    Task { await viewModel.runAnalysis() }
                } label: {
                    Label("Run Analysis", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.isRunning)

                if viewModel.result != nil {
                    Button {
                        Task { await viewModel.runAdditionalPass() }
                    } label: {
                        Label("+1 Run", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(viewModel.isRunning)

                    Text("\(viewModel.currentRunCount) runs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Button {
                    withAnimation { showConfig.toggle() }
                } label: {
                    Label("Config", systemImage: showConfig ? "gearshape.fill" : "gearshape")
                }
                .buttonStyle(.bordered)

                if GroundTruthStorage.load(videoId: video.videoId) != nil && viewModel.result == nil {
                    Button {
                        viewModel.loadFromDefaults()
                    } label: {
                        Label("Load Saved", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if showConfig {
                slidingWindowConfig
            }
        }
        .padding()
    }

    private var slidingWindowConfig: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Sliding Window")
                    .font(.caption.bold())
                Spacer()
                let sentenceCount = viewModel.result?.totalSentences ?? 0
                if sentenceCount > 0 {
                    let windowCount = max(0, (sentenceCount - viewModel.windowSize) / viewModel.stepSize + 1)
                    Text("\(windowCount) windows")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Window Size")
                    .font(.caption)
                    .frame(width: 90, alignment: .leading)
                Stepper("\(viewModel.windowSize)", value: $viewModel.windowSize, in: 3...10)
                    .font(.caption.monospacedDigit())
            }

            HStack {
                Text("Step Size")
                    .font(.caption)
                    .frame(width: 90, alignment: .leading)
                Stepper("\(viewModel.stepSize)", value: $viewModel.stepSize, in: 1...5)
                    .font(.caption.monospacedDigit())
            }

            HStack {
                Text("Temperature")
                    .font(.caption)
                    .frame(width: 90, alignment: .leading)
                Slider(value: $viewModel.temperature, in: 0...1, step: 0.1)
                Text(String(format: "%.1f", viewModel.temperature))
                    .font(.caption.monospacedDigit())
                    .frame(width: 30)
            }

            HStack {
                Text("LLM Passes")
                    .font(.caption)
                    .frame(width: 90, alignment: .leading)
                Stepper("\(viewModel.slidingWindowRunCount)", value: $viewModel.slidingWindowRunCount, in: 1...5)
                    .font(.caption.monospacedDigit())
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Summary

    private func summarySection(_ result: GroundTruthResult) -> some View {
        VStack(spacing: 4) {
            // Method comparison header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(result.methodResults, id: \.method) { methodResult in
                        VStack(spacing: 2) {
                            Text("\(methodResult.boundaryGapIndices.count)")
                                .font(.title3.bold())
                                .foregroundColor(methodResult.method.color)
                            Text(methodResult.method.shortLabel)
                                .font(.caption2.bold())
                                .foregroundColor(methodResult.method.color)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(methodResult.method.color.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal)
            }

            // Consensus tier pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    let tm = result.totalMethods
                    summaryPill(ConsensusTier.definite.label(totalMethods: tm), count: result.definiteCount, color: .green)
                    summaryPill(ConsensusTier.probable.label(totalMethods: tm), count: result.probableCount, color: .yellow)
                    if tm >= 4 {
                        summaryPill(ConsensusTier.contested.label(totalMethods: tm), count: result.contestedCount, color: .orange)
                    }
                    summaryPill("1/\(tm)", count: result.weakCount, color: .gray)
                    summaryPill("Deserts", count: result.deserts.count, color: .red)
                    if result.pendingReviewCount > 0 {
                        summaryPill("Pending", count: result.pendingReviewCount, color: .orange)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryPill(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                tabButton("Consensus", tag: 0, icon: "chart.bar.fill")
                tabButton("Scoring", tag: 1, icon: "list.bullet.rectangle.fill")
                tabButton("Alignment", tag: 2, icon: "rectangle.split.3x3.fill")
                tabButton("Methods", tag: 3, icon: "gearshape.2.fill")
                tabButton("Deserts", tag: 4, icon: "text.line.first.and.arrowtriangle.forward")
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
    }

    private func tabButton(_ label: String, tag: Int, icon: String) -> some View {
        Button {
            selectedTab = tag
        } label: {
            Label(label, systemImage: icon)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedTab == tag ? Color.accentColor : Color.gray.opacity(0.15))
                .foregroundColor(selectedTab == tag ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabContent(_ result: GroundTruthResult) -> some View {
        switch selectedTab {
        case 0: consensusTab(result)
        case 1: scoringTab(result)
        case 2: alignmentTab(result)
        case 3: methodsTab(result)
        case 4: desertsTab(result)
        default: EmptyView()
        }
    }

    // MARK: - Consensus Tab

    private func consensusTab(_ result: GroundTruthResult) -> some View {
        let tm = result.totalMethods

        return VStack(spacing: 0) {
            // Filter row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterButton("All", tier: nil)
                    filterButton(ConsensusTier.definite.label(totalMethods: tm), tier: .definite)
                    filterButton(ConsensusTier.probable.label(totalMethods: tm), tier: .probable)
                    if tm >= 4 {
                        filterButton(ConsensusTier.contested.label(totalMethods: tm), tier: .contested)
                    }
                    filterButton("1/\(tm)", tier: .weak)

                    // Disagreements filter
                    Button {
                        showDisagreements.toggle()
                        if showDisagreements {
                            viewModel.filterTier = nil
                        }
                    } label: {
                        Text("Disagree")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(showDisagreements ? Color.red : Color.gray.opacity(0.2))
                            .foregroundColor(showDisagreements ? .white : .primary)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredVotesForDisplay(result)) { vote in
                        gapRow(vote, result: result)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    /// Filtered votes accounting for both tier filter and disagreements toggle
    private func filteredVotesForDisplay(_ result: GroundTruthResult) -> [SentenceGapVote] {
        var votes = viewModel.filteredVotes
        if showDisagreements {
            votes = result.gapVotes.filter { $0.voteCount > 0 && $0.voteCount < result.totalMethods }
        }
        return votes
    }

    private func filterButton(_ label: String, tier: ConsensusTier?) -> some View {
        Button {
            viewModel.filterTier = tier
            showDisagreements = false
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(!showDisagreements && viewModel.filterTier == tier ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(!showDisagreements && viewModel.filterTier == tier ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func gapRow(_ vote: SentenceGapVote, result: GroundTruthResult) -> some View {
        VStack(spacing: 4) {
            // Sentence before the gap
            HStack(alignment: .top, spacing: 4) {
                Text("[\(vote.gapAfterSentenceIndex + 1)]")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Text(vote.sentenceText)
                    .font(.caption)
                    .lineLimit(2)
            }

            // Gap indicator
            gapIndicator(vote, result: result)

            // Per-method detail row
            methodDetailRow(vote, result: result)

            // Sentence after the gap
            HStack(alignment: .top, spacing: 4) {
                Text("[\(vote.gapAfterSentenceIndex + 2)]")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Text(vote.nextSentenceText)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .background(vote.voteCount >= result.boundaryThreshold ? Color.green.opacity(0.05) : Color.clear)
    }

    private func gapIndicator(_ vote: SentenceGapVote, result: GroundTruthResult) -> some View {
        let tm = result.totalMethods
        let tier = result.tier(for: vote)
        let activeMethods = result.activeMethods

        return HStack(spacing: 6) {
            // Vote badge
            Text(tier?.label(totalMethods: tm) ?? "0/\(tm)")
                .font(.caption2.bold())
                .foregroundColor(tier?.color ?? .gray)

            // Method dots (only active methods)
            HStack(spacing: 3) {
                ForEach(activeMethods, id: \.self) { method in
                    let voted = vote.votes.contains(method)
                    Circle()
                        .fill(voted ? method.color : method.color.opacity(0.15))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(method.color.opacity(0.4), lineWidth: voted ? 0 : 0.5)
                        )
                }
            }

            // Method labels
            HStack(spacing: 2) {
                ForEach(activeMethods, id: \.self) { method in
                    Text(method.shortLabel)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(vote.votes.contains(method) ? method.color : .gray.opacity(0.3))
                }
            }

            Spacer()

            // Manual override icon
            if let override = vote.manualOverride {
                Image(systemName: override ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(override ? .green : .red)
            }

            // Tap target for gaps below threshold
            if vote.voteCount > 0 && vote.voteCount < result.boundaryThreshold {
                Button {
                    viewModel.toggleManualOverride(gapIndex: vote.gapAfterSentenceIndex)
                } label: {
                    Image(systemName: overrideIcon(vote.manualOverride))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(tier?.color.opacity(0.08) ?? Color.clear)
        )
    }

    /// Shows per-method detail below the gap indicator
    private func methodDetailRow(_ vote: SentenceGapVote, result: GroundTruthResult) -> some View {
        HStack(spacing: 8) {
            ForEach(result.methodResults, id: \.method) { methodResult in
                let m = methodResult.method
                let voted = vote.votes.contains(m)
                let detail = methodResult.detail(forGap: vote.gapAfterSentenceIndex)

                HStack(spacing: 2) {
                    Text(m.shortLabel)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(m.color)

                    if voted {
                        // Method fired — show why
                        switch m {
                        case .deterministicClean, .deterministicDigression:
                            Text(detail?.triggerType ?? "?")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(m.color.opacity(0.8))
                        case .slidingWindowP1:
                            let wv = detail?.windowVotes ?? 0
                            let wo = detail?.windowsOverlapping ?? 0
                            Text("\(wv)/\(wo)w")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(m.color.opacity(0.8))
                        case .slidingWindowLLM:
                            let wv = detail?.windowVotes ?? 0
                            let wo = detail?.windowsOverlapping ?? 0
                            let change = detail?.passChange ?? ""
                            let changeTag = change == "confirmed" ? "" : " \(change)"
                            Text("\(wv)/\(wo)w\(changeTag)")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(m.color.opacity(0.8))
                        case .singleShotLLM:
                            Text("yes")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(m.color.opacity(0.8))
                        }
                    } else {
                        // Method did NOT fire
                        Text("—")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func overrideIcon(_ override: Bool?) -> String {
        switch override {
        case nil: return "hand.tap"
        case true: return "checkmark.circle"
        case false: return "xmark.circle"
        default: return "hand.tap"
        }
    }

    // MARK: - Scoring Tab

    private func scoringTab(_ result: GroundTruthResult) -> some View {
        let tm = result.totalMethods

        return VStack(spacing: 0) {
            // Filter row (same as consensus)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterButton("All", tier: nil)
                    filterButton(ConsensusTier.definite.label(totalMethods: tm), tier: .definite)
                    filterButton(ConsensusTier.probable.label(totalMethods: tm), tier: .probable)
                    if tm >= 4 {
                        filterButton(ConsensusTier.contested.label(totalMethods: tm), tier: .contested)
                    }
                    filterButton("1/\(tm)", tier: .weak)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredVotesForDisplay(result)) { vote in
                        scoringCard(vote, result: result)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func scoringCard(_ vote: SentenceGapVote, result: GroundTruthResult) -> some View {
        let tm = result.totalMethods
        let tier = result.tier(for: vote)

        return VStack(alignment: .leading, spacing: 8) {
            // Header: gap index + tier
            HStack {
                Text("[\(vote.gapAfterSentenceIndex + 1)]")
                    .font(.headline.monospaced())
                Text("—")
                    .foregroundColor(.secondary)
                Text(tier?.label(totalMethods: tm) ?? "0/\(tm)")
                    .font(.headline.bold())
                    .foregroundColor(tier?.color ?? .gray)
                Text(tierName(tier))
                    .font(.subheadline)
                    .foregroundColor(tier?.color ?? .gray)
                Spacer()
                if let override = vote.manualOverride {
                    Image(systemName: override ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundColor(override ? .green : .red)
                }
            }

            // Sentence text
            Text("\"\(vote.sentenceText)\"")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            // Method dots row
            HStack(spacing: 6) {
                Text("Methods:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach(result.activeMethods, id: \.self) { method in
                    let voted = vote.votes.contains(method)
                    HStack(spacing: 2) {
                        Text(method.shortLabel)
                            .font(.caption2.bold())
                            .foregroundColor(method.color)
                        Circle()
                            .fill(voted ? method.color : method.color.opacity(0.15))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(method.color.opacity(0.4), lineWidth: voted ? 0 : 0.5)
                            )
                    }
                }
            }

            // Per-method WHAT/WHY detail
            ForEach(result.methodResults, id: \.method) { methodResult in
                let m = methodResult.method
                let voted = vote.votes.contains(m)
                let detail = methodResult.detail(forGap: vote.gapAfterSentenceIndex)

                HStack(alignment: .top, spacing: 6) {
                    Text("[\(m.shortLabel)]")
                        .font(.caption.bold().monospaced())
                        .foregroundColor(m.color)
                        .frame(width: 30, alignment: .leading)

                    if voted {
                        scoringMethodDetail(m, detail: detail)
                    } else {
                        scoringMethodNoFire(m, detail: detail)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tier?.color.opacity(0.06) ?? Color(.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tier?.color.opacity(0.2) ?? Color.gray.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func scoringMethodDetail(_ m: BoundaryMethod, detail: MethodBoundaryDetail?) -> some View {
        switch m {
        case .deterministicClean, .deterministicDigression:
            let trigger = detail?.triggerType ?? "unknown"
            let conf = detail?.triggerConfidence ?? "?"
            Text("\(trigger) (\(conf))")
                .font(.caption)
                .foregroundColor(m.color.opacity(0.9))

        case .slidingWindowP1:
            let wv = detail?.windowVotes ?? 0
            let wo = detail?.windowsOverlapping ?? 0
            let pct = wo > 0 ? Int(Double(wv) / Double(wo) * 100) : 0
            Text("\(wv)/\(wo) windows (\(pct)%)")
                .font(.caption)
                .foregroundColor(m.color.opacity(0.9))

        case .slidingWindowLLM:
            let wv = detail?.windowVotes ?? 0
            let wo = detail?.windowsOverlapping ?? 0
            let pct = wo > 0 ? Int(Double(wv) / Double(wo) * 100) : 0
            let change = detail?.passChange ?? ""
            let changeLabel = change.isEmpty ? "" : " — \(change)"
            Text("\(wv)/\(wo) windows (\(pct)%)\(changeLabel)")
                .font(.caption)
                .foregroundColor(m.color.opacity(0.9))

        case .singleShotLLM:
            Text("consensus vote")
                .font(.caption)
                .foregroundColor(m.color.opacity(0.9))
        }
    }

    @ViewBuilder
    private func scoringMethodNoFire(_ m: BoundaryMethod, detail: MethodBoundaryDetail?) -> some View {
        switch m {
        case .slidingWindowLLM:
            if let change = detail?.passChange, change.contains("REVOKED") {
                Text("— (revoked by pass 2)")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.7))
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.5))
            }
        default:
            Text("—")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.5))
        }
    }

    private func tierName(_ tier: ConsensusTier?) -> String {
        switch tier {
        case .definite: return "DEFINITE"
        case .probable: return "PROBABLE"
        case .contested: return "CONTESTED"
        case .weak: return "WEAK"
        case nil: return ""
        }
    }

    // MARK: - Alignment Tab

    private func alignmentTab(_ result: GroundTruthResult) -> some View {
        let runs = result.allAlignmentRuns

        return VStack(spacing: 0) {
            // Run count summary + Window Detail button
            HStack {
                Text("\(runs.count) columns")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if result.slidingWindowRuns != nil {
                    Button {
                        showWindowDetail = true
                    } label: {
                        Label("Window Detail", systemImage: "rectangle.split.3x3")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Scrollable table
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    alignmentHeader(runs)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(result.gapVotes) { vote in
                                alignmentRow(vote, runs: runs, result: result)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showWindowDetail) {
            windowDetailSheet(result)
        }
    }

    private func alignmentHeader(_ runs: [AlignmentRun]) -> some View {
        HStack(spacing: 0) {
            Text("Gap")
                .font(.caption2.bold())
                .frame(width: 44, alignment: .leading)

            ForEach(runs) { run in
                Text(run.label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(run.color)
                    .frame(width: 28)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Text("Tier")
                .font(.caption2.bold())
                .frame(width: 40)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private func alignmentRow(_ vote: SentenceGapVote, runs: [AlignmentRun], result: GroundTruthResult) -> some View {
        let tm = result.totalMethods
        let tier = result.tier(for: vote)
        let gapIndex = vote.gapAfterSentenceIndex
        let isExpanded = expandedAlignmentRows.contains(gapIndex)

        // Count how many individual runs voted here
        let runVoteCount = runs.filter { $0.boundaryGapIndices.contains(gapIndex) }.count

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedAlignmentRows.remove(gapIndex)
                    } else {
                        expandedAlignmentRows.insert(gapIndex)
                    }
                }
            } label: {
                HStack(spacing: 0) {
                    Text("[\(gapIndex + 1)]")
                        .font(.caption.monospaced())
                        .frame(width: 44, alignment: .leading)

                    ForEach(runs) { run in
                        let voted = run.boundaryGapIndices.contains(gapIndex)
                        Circle()
                            .fill(voted ? run.color : run.color.opacity(0.1))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(run.color.opacity(0.3), lineWidth: voted ? 0 : 0.5)
                            )
                            .frame(width: 28)
                    }

                    Text(tier?.label(totalMethods: tm) ?? "?")
                        .font(.caption2.bold())
                        .foregroundColor(tier?.color ?? .gray)
                        .frame(width: 40)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tier?.color.opacity(0.04) ?? Color.clear)
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\"\(vote.sentenceText)\"")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .padding(.bottom, 2)

                    Text("\(runVoteCount)/\(runs.count) runs voted boundary")
                        .font(.caption2.bold())
                        .foregroundColor(tier?.color ?? .gray)

                    // Show each run that voted
                    ForEach(runs.filter { $0.boundaryGapIndices.contains(gapIndex) }) { run in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(run.color)
                                .frame(width: 6, height: 6)
                            Text(run.label)
                                .font(.caption2.bold().monospaced())
                                .foregroundColor(run.color)
                            if let detail = run.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundColor(run.color.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }

                    if let override = vote.manualOverride {
                        Text("Manual: \(override ? "CONFIRMED" : "REJECTED")")
                            .font(.caption2.bold())
                            .foregroundColor(override ? .green : .red)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
            }

            Divider().padding(.leading, 8)
        }
    }

    // MARK: - Window Detail Sheet

    private func windowDetailSheet(_ result: GroundTruthResult) -> some View {
        let runCount = result.slidingWindowRuns?.count ?? 0

        return NavigationStack {
            VStack(spacing: 0) {
                // Run picker (if multiple runs)
                if runCount > 1 {
                    HStack {
                        Text("Run:")
                            .font(.caption.bold())
                        Picker("Run", selection: $windowDetailRunIndex) {
                            ForEach(0..<runCount, id: \.self) { i in
                                Text("Run \(i + 1)").tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }

                // Run info
                if let swRuns = result.slidingWindowRuns,
                   windowDetailRunIndex < swRuns.count {
                    let run = swRuns[windowDetailRunIndex]
                    HStack(spacing: 12) {
                        Text("\(run.totalWindows) windows")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("W: \(run.windowSize), S: \(run.stepSize)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("T: \(String(format: "%.1f", run.temperature))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }

                // Per-window alignment grid
                let detailRuns = result.windowDetailAlignmentRuns(forRunIndex: windowDetailRunIndex)

                if detailRuns.isEmpty {
                    Spacer()
                    Text("No window data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            // Header
                            HStack(spacing: 0) {
                                Text("Gap")
                                    .font(.caption2.bold())
                                    .frame(width: 44, alignment: .leading)

                                ForEach(detailRuns) { run in
                                    Text(run.label)
                                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                                        .foregroundColor(run.color)
                                        .frame(width: 28)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.4)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground))

                            // Rows — only gaps where at least one window/consensus voted
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 0) {
                                    ForEach(result.gapVotes) { vote in
                                        let gapIndex = vote.gapAfterSentenceIndex
                                        let anyVoted = detailRuns.contains { $0.boundaryGapIndices.contains(gapIndex) }
                                        if anyVoted {
                                            windowDetailRow(vote, runs: detailRuns, result: result)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Window Detail — Run \(windowDetailRunIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showWindowDetail = false }
                }
            }
        }
    }

    private func windowDetailRow(_ vote: SentenceGapVote, runs: [AlignmentRun], result: GroundTruthResult) -> some View {
        let gapIndex = vote.gapAfterSentenceIndex
        let isExpanded = expandedAlignmentRows.contains(gapIndex + 10000) // offset to avoid collision with main alignment

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedAlignmentRows.remove(gapIndex + 10000)
                    } else {
                        expandedAlignmentRows.insert(gapIndex + 10000)
                    }
                }
            } label: {
                HStack(spacing: 0) {
                    Text("[\(gapIndex + 1)]")
                        .font(.caption.monospaced())
                        .frame(width: 44, alignment: .leading)

                    ForEach(runs) { run in
                        let voted = run.boundaryGapIndices.contains(gapIndex)
                        Circle()
                            .fill(voted ? run.color : run.color.opacity(0.1))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(run.color.opacity(0.3), lineWidth: voted ? 0 : 0.5)
                            )
                            .frame(width: 28)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            // Expanded: show sentence text and which windows voted
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\"\(vote.sentenceText)\"")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)

                    let votedRuns = runs.filter { $0.boundaryGapIndices.contains(gapIndex) }
                    Text("\(votedRuns.count)/\(runs.count) columns voted")
                        .font(.caption2.bold())

                    ForEach(votedRuns) { run in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(run.color)
                                .frame(width: 6, height: 6)
                            Text(run.label)
                                .font(.caption2.bold().monospaced())
                                .foregroundColor(run.color)
                            if let detail = run.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundColor(run.color.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
            }

            Divider().padding(.leading, 8)
        }
    }

    // MARK: - Methods Tab

    private func methodsTab(_ result: GroundTruthResult) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(result.methodResults, id: \.method) { methodResult in
                    methodCard(methodResult, result: result)
                }
            }
            .padding()
        }
    }

    private func methodCard(_ method: MethodBoundarySet, result: GroundTruthResult) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Boundaries:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(method.boundaryGapIndices.count)")
                        .font(.caption.bold())
                }

                HStack {
                    Text("Duration:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", method.runDuration))s")
                        .font(.caption.bold())
                }

                if let runs = method.internalRunCount {
                    HStack {
                        Text("Passes:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(runs)-pass system")
                            .font(.caption.bold())
                    }
                }

                // Sliding window pass comparison
                if let pass1Set = method.pass1GapIndices {
                    let finalSet = method.boundaryGapIndices
                    let confirmed = pass1Set.intersection(finalSet).count
                    let revoked = pass1Set.subtracting(finalSet).count
                    let added = finalSet.subtracting(pass1Set).count

                    HStack {
                        Text("Pass 1:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(pass1Set.count) boundaries")
                            .font(.caption.bold())
                    }
                    HStack {
                        Text("Final:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(finalSet.count) — \(confirmed) confirmed, \(revoked) revoked, \(added) added")
                            .font(.caption.bold())
                    }
                }

                Text(method.debugSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                // Boundary indices with trigger info
                if let details = method.perBoundaryDetails, !details.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Per-boundary detail:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ForEach(details.sorted(by: { $0.gapIndex < $1.gapIndex }), id: \.gapIndex) { d in
                            HStack(spacing: 4) {
                                Text("[\(d.gapIndex)]")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                if let trigger = d.triggerType {
                                    Text(trigger)
                                        .font(.caption2)
                                        .foregroundColor(method.method.color)
                                }
                                if let wv = d.windowVotes, let wo = d.windowsOverlapping {
                                    Text("\(wv)/\(wo) windows")
                                        .font(.caption2)
                                        .foregroundColor(method.method.color)
                                }
                                if let change = d.passChange, change != "confirmed" {
                                    Text(change)
                                        .font(.caption2.bold())
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                } else {
                    let sorted = method.boundaryGapIndices.sorted()
                    if !sorted.isEmpty {
                        Text("Gap indices: \(sorted.map { String($0) }.joined(separator: ", "))")
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Circle()
                    .fill(method.method.color)
                    .frame(width: 10, height: 10)
                Text("[\(method.method.shortLabel)]")
                    .font(.caption.bold().monospaced())
                Text(method.method.displayName)
                    .font(.subheadline)
                Spacer()
                Text("\(method.boundaryGapIndices.count)")
                    .font(.caption.bold())
                    .foregroundColor(method.method.color)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Deserts Tab

    private func desertsTab(_ result: GroundTruthResult) -> some View {
        ScrollView {
            if result.deserts.isEmpty {
                Text("No deserts found (no stretches of 10+ consecutive gaps with 0 votes)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(result.deserts) { desert in
                        HStack {
                            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text("Sentences \(desert.startSentenceIndex) – \(desert.endSentenceIndex)")
                                    .font(.subheadline.bold())
                                Text("\(desert.sentenceCount) consecutive gaps with 0 votes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Progress

    private var runningOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)
                    .tint(.white)

                Text("Running Ground Truth Analysis")
                    .font(.headline)
                    .foregroundColor(.white)

                ProgressView(value: viewModel.progressValue)
                    .tint(.green)
                    .frame(width: 250)

                Text(viewModel.progressPhase)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Text("\(Int(viewModel.progressValue * 100))%")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Tap Run Analysis to generate ground truth")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Uses 4 independent boundary detection methods")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
    }

    // MARK: - Footer

    private var footerButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Transcript copy buttons (available whenever sentences are loaded)
                if viewModel.hasSentences {
                    copyButton(
                        label: "Sentences",
                        icon: "list.number",
                        isCopied: $isTranscriptCopied
                    ) {
                        viewModel.copyRawTranscript()
                    }

                    copyButton(
                        label: "Clean",
                        icon: "text.line.first.and.arrowtriangle.forward",
                        isCopied: $isCleanCopied
                    ) {
                        Task { await viewModel.copyTranscriptDigressionsRemoved() }
                    }
                }

                // Result copy buttons (available after analysis)
                if viewModel.result != nil {
                    copyButton(
                        label: "Report",
                        icon: "doc.on.doc",
                        isCopied: $isReportCopied
                    ) {
                        UIPasteboard.general.string = viewModel.exportText
                    }

                    copyButton(
                        label: "Scoring",
                        icon: "list.bullet.rectangle",
                        isCopied: $isScoringCopied
                    ) {
                        viewModel.copyScoring()
                    }

                    copyButton(
                        label: "Alignment",
                        icon: "rectangle.split.3x3",
                        isCopied: $isAlignmentCopied
                    ) {
                        viewModel.copyAlignment()
                    }

                    copyButton(
                        label: "Boundaries",
                        icon: "curlybraces",
                        isCopied: $isBoundariesCopied
                    ) {
                        copyBoundariesJSON()
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func copyButton(
        label: String,
        icon: String,
        isCopied: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied.wrappedValue = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isCopied.wrappedValue = false
                }
            }
        } label: {
            Label(
                isCopied.wrappedValue ? "Copied" : label,
                systemImage: isCopied.wrappedValue ? "checkmark" : icon
            )
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(isCopied.wrappedValue ? .green : nil)
    }

    private func copyBoundariesJSON() {
        guard let result = viewModel.result else { return }
        let boundaries = result.gapVotes
            .filter { result.isBoundary($0) }
            .map { ["gapAfterSentence": $0.gapAfterSentenceIndex, "voteCount": $0.voteCount] }

        if let data = try? JSONSerialization.data(withJSONObject: boundaries, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = json
        }
    }
}
