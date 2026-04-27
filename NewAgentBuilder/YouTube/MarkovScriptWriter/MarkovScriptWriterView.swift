//
//  MarkovScriptWriterView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/17/26.
//
//  Root view for the Markov Script Writer.
//  Phase-tabbed layout: Input, Markov Explorer, and placeholders for future phases.
//

import SwiftUI

struct MarkovScriptWriterView: View {
    @StateObject private var coordinator = MarkovScriptWriterCoordinator()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(MarkovScriptPhase.allCases.enumerated()), id: \.offset) { index, phase in
                        Button {
                            withAnimation { selectedTab = index }
                        } label: {
                            Text(phase.rawValue)
                                .font(.caption)
                                .fontWeight(selectedTab == index ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedTab == index ? Color.accentColor : Color.secondary.opacity(0.15))
                                .foregroundColor(selectedTab == index ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Tab content — only the selected view is in the hierarchy.
            // Page-style TabView was evaluating multiple children on every tab switch;
            // a switch statement ensures exactly one view exists at a time.
            Group {
                switch selectedTab {
                case 0:  inputView
                case 1:  OpenerMatcherView(coordinator: coordinator)
                case 2:  MarkovExplorerView(coordinator: coordinator)
                case 3:  GistAvailabilityView(coordinator: coordinator)
                case 4:  ManualSequenceBuilderView(coordinator: coordinator)
                case 5:  ChainBuilderView(coordinator: coordinator)
                case 6:  DeadEndsView(coordinator: coordinator)
                case 7:  GapResponseView(coordinator: coordinator)
                case 8:  ChainParametersView(coordinator: coordinator)
                case 9:  SynthesisView(coordinator: coordinator)
                case 10: ChainTraceView(coordinator: coordinator)
                case 11: ScriptTraceView(coordinator: coordinator)
                case 12: StructureWorkbenchView(coordinator: coordinator)
                case 13: OpenerComparisonView(coordinator: coordinator)
                case 14: SkeletonLabView(coordinator: coordinator)
                case 15: AtomExplorerView(coordinator: coordinator)
                case 16: ProseEditorView(coordinator: coordinator)
                case 17: ArcPipelineView(coordinator: coordinator)
                default: inputView
                }
            }
        }
        .navigationTitle("Markov Script Writer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("Refresh from Gist Writer") {
                        coordinator.refreshFromGistWriter()
                    }
                    Button("Clear Session", role: .destructive) {
                        coordinator.clearSession()
                    }
                    Divider()
                    Button {
                        coordinator.expandAllGists()
                    } label: {
                        Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    Button {
                        coordinator.collapseAllGists()
                    } label: {
                        Label("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if let report = coordinator.copyMatrixReport() {
                        MenuCopyButton(
                            text: report,
                            label: "Copy Matrix Report",
                            systemImage: "doc.on.doc"
                        )
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .overlay {
            if coordinator.isLoading {
                loadingOverlay
            }
        }
        .alert("Error", isPresented: .constant(coordinator.errorMessage != nil)) {
            Button("OK") { coordinator.errorMessage = nil }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
        .task {
            await coordinator.loadAvailableChannels()
            await coordinator.loadLatestChainRunIfNeeded()
        }
        .onChange(of: coordinator.phase) { newPhase in
            if let index = MarkovScriptPhase.allCases.firstIndex(of: newPhase) {
                withAnimation { selectedTab = index }
            }
        }
    }

    // MARK: - Input View (Tab 0)

    private var inputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Autoload banner
                if coordinator.hasAutoloadedData {
                    autoloadBanner
                }

                // Gist summary
                if !coordinator.session.ramblingGists.isEmpty {
                    gistSummarySection
                }

                // Gist list
                if !coordinator.session.ramblingGists.isEmpty {
                    gistListSection
                }

                // Raw text section (collapsed by default if we have gists)
                if coordinator.session.ramblingGists.isEmpty {
                    emptyStateSection
                }
            }
            .padding()
        }
    }

    private var autoloadBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Data Autoloaded")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(coordinator.autoloadSource)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(coordinator.session.ramblingGists.count) gists | \(coordinator.session.rawRamblingText.split(separator: " ").count) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                coordinator.refreshFromGistWriter()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(12)
    }

    private var gistSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rambling Gists")
                .font(.headline)

            let gists = coordinator.session.ramblingGists
            let frames = Dictionary(grouping: gists, by: { $0.gistA.frame })
            let moveLabels = gists.compactMap(\.moveLabel)
            let categories = Dictionary(grouping: moveLabels, by: { $0 })

            HStack(spacing: 16) {
                statBadge(value: "\(gists.count)", label: "Chunks")
                statBadge(value: "\(frames.count)", label: "Frames")
                statBadge(value: "\(categories.count)", label: "Moves")
            }

            // Frame distribution
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(frames.sorted(by: { $0.value.count > $1.value.count }), id: \.key) { frame, gists in
                        Text("\(frame.rawValue): \(gists.count)")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }

            // Copy buttons
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    CompactCopyButton(text: coordinator.session.rawRamblingText)
                    Text("Raw Rambling")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    CompactCopyButton(text: formatAllChunksForCopy())
                    Text("All Chunks")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var gistListSection: some View {
        LazyVStack(spacing: 8) {
            ForEach(coordinator.session.ramblingGists) { gist in
                ramblingGistCard(gist)
            }
        }
    }

    private func ramblingGistCard(_ gist: RamblingGist) -> some View {
        let isExpanded = coordinator.expandedGistIds.contains(gist.id)
        let wc = chunkWordCount(gist)
        let parsedMove = gist.moveLabel.flatMap { RhetoricalMoveType.parse($0) }
        let corpusStats = parsedMove.flatMap { coordinator.corpusWordCounts?.perMove[$0] }

        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Chunk \(gist.chunkIndex + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)

                if let moveLabel = gist.moveLabel {
                    Text(moveLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                }

                Text(gist.gistA.frame.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)

                Text("\(wc)w")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(wordCountColor(chunkWords: wc, corpusStats: corpusStats))

                if let stats = corpusStats {
                    Text("\(stats.min)/\(Int(stats.avg))/\(stats.max)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let conf = gist.confidence {
                    Text("\(Int(conf * 100))%")
                        .font(.caption2)
                        .foregroundColor(conf >= 0.8 ? .green : conf >= 0.6 ? .orange : .red)
                }

                CompactCopyButton(text: formatGistForCopy(gist))

                Button {
                    withAnimation { coordinator.toggleGistExpansion(gist.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }

            // Brief description
            Text(gist.gistB.premise)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 2)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()

                    // GistA
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GistA (Deterministic)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text("Subject: \(gist.gistA.subject.joined(separator: ", "))")
                            .font(.caption2)
                        Text("Premise: \(gist.gistA.premise)")
                            .font(.caption2)
                        Text("Frame: \(gist.gistA.frame.rawValue)")
                            .font(.caption2)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)

                    // GistB
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GistB (Flexible)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        Text("Subject: \(gist.gistB.subject.joined(separator: ", "))")
                            .font(.caption2)
                        Text("Premise: \(gist.gistB.premise)")
                            .font(.caption2)
                        Text("Frame: \(gist.gistB.frame.rawValue)")
                            .font(.caption2)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(6)

                    // Source text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Source Text")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text(gist.sourceText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)

                    // Telemetry
                    if let telemetry = gist.telemetry {
                        HStack(spacing: 8) {
                            Text(telemetry.dominantStance.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(4)

                            if telemetry.contrastCount > 0 {
                                Text("contrast:\(telemetry.contrastCount)")
                                    .font(.caption2)
                            }
                            if telemetry.questionCount > 0 {
                                Text("questions:\(telemetry.questionCount)")
                                    .font(.caption2)
                            }
                            if telemetry.numberCount > 0 {
                                Text("numbers:\(telemetry.numberCount)")
                                    .font(.caption2)
                            }
                        }
                    }

                    // Word count diagnostics (eligible moves + category stats)
                    if coordinator.corpusWordCounts != nil {
                        wordCountDiagnosticsSection(gist: gist)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    private func formatGistForCopy(_ gist: RamblingGist) -> String {
        var lines: [String] = []
        lines.append("── Chunk \(gist.chunkIndex + 1) ──")

        if let moveLabel = gist.moveLabel {
            if let conf = gist.confidence {
                lines.append("Move: \(moveLabel) (\(Int(conf * 100))%)")
            } else {
                lines.append("Move: \(moveLabel)")
            }
        }
        lines.append("Frame: \(gist.gistA.frame.rawValue)")

        let wc = chunkWordCount(gist)
        lines.append("Words: \(wc)")
        if let moveLabel = gist.moveLabel,
           let moveType = RhetoricalMoveType.parse(moveLabel),
           let stats = coordinator.corpusWordCounts?.perMove[moveType] {
            lines.append("Corpus (\(moveType.displayName)): min \(stats.min) / avg \(Int(stats.avg)) / max \(stats.max) (\(stats.sampleCount) samples)")
        }
        lines.append("")

        lines.append("GistA (Deterministic)")
        lines.append("  Subject: \(gist.gistA.subject.joined(separator: ", "))")
        lines.append("  Premise: \(gist.gistA.premise)")
        lines.append("  Frame: \(gist.gistA.frame.rawValue)")
        lines.append("")

        lines.append("GistB (Flexible)")
        lines.append("  Subject: \(gist.gistB.subject.joined(separator: ", "))")
        lines.append("  Premise: \(gist.gistB.premise)")
        lines.append("  Frame: \(gist.gistB.frame.rawValue)")
        lines.append("")

        lines.append("Source Text:")
        lines.append("  \(gist.sourceText)")

        if let telemetry = gist.telemetry {
            lines.append("")
            lines.append("Telemetry:")
            lines.append("  Stance: \(telemetry.dominantStance.rawValue)")
            lines.append("  1P: \(telemetry.firstPersonCount)  2P: \(telemetry.secondPersonCount)  3P: \(telemetry.thirdPersonCount)")
            lines.append("  Numbers: \(telemetry.numberCount)  Temporal: \(telemetry.temporalCount)  Contrast: \(telemetry.contrastCount)  Questions: \(telemetry.questionCount)  Quotes: \(telemetry.quoteCount)  Spatial: \(telemetry.spatialCount)  Technical: \(telemetry.technicalCount)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatAllChunksForCopy() -> String {
        let gists = coordinator.session.ramblingGists
        guard !gists.isEmpty else { return "" }

        var sections: [String] = []
        for gist in gists {
            var lines: [String] = []
            lines.append("── Chunk \(gist.chunkIndex + 1) ──")
            lines.append("Frame: \(gist.gistA.frame.rawValue)")

            let expandedMoves = FrameExpansionIndex.expansionMoves(for: gist.gistA.frame)
            let moveNames = expandedMoves.map(\.displayName).joined(separator: ", ")
            lines.append("Expanded Moves: \(moveNames)")
            lines.append("")
            lines.append(gist.sourceText)

            sections.append(lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Word Count Helpers

    private func chunkWordCount(_ gist: RamblingGist) -> Int {
        gist.sourceText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private func wordCountColor(chunkWords: Int, corpusStats: WordCountStats?) -> Color {
        guard let stats = corpusStats else { return .secondary }
        if chunkWords < stats.min { return .red }
        if Double(chunkWords) < stats.avg { return .orange }
        return .green
    }

    @ViewBuilder
    private func wordCountDiagnosticsSection(gist: RamblingGist) -> some View {
        let frame = gist.gistA.frame
        let eligibleMoves = FrameExpansionIndex.expansionMoves(for: frame)
        let assignedMove = gist.moveLabel.flatMap { RhetoricalMoveType.parse($0) }
        let chunkWords = chunkWordCount(gist)
        let corpusWordCounts = coordinator.corpusWordCounts!

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Word Count vs Corpus")
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text("(\(chunkWords) words)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(wordCountColor(
                        chunkWords: chunkWords,
                        corpusStats: assignedMove.flatMap { corpusWordCounts.perMove[$0] }
                    ))
            }

            Divider()

            // Eligible moves from frame expansion
            Text("Eligible Moves (\(frame.displayName))")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.blue)

            ForEach(eligibleMoves, id: \.self) { move in
                let stats = corpusWordCounts.perMove[move]
                let isAssigned = move == assignedMove

                HStack(spacing: 6) {
                    Text(move.displayName)
                        .font(.caption2)
                        .fontWeight(isAssigned ? .bold : .regular)
                        .foregroundColor(isAssigned ? .purple : .primary)

                    if isAssigned {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 8))
                            .foregroundColor(.purple)
                    }

                    Spacer()

                    if let stats = stats {
                        Text("\(stats.min) / \(Int(stats.avg)) / \(stats.max)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("(\(stats.sampleCount))")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    } else {
                        Text("no data")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }

            Divider()

            // Category rollup
            Text("Category Stats")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.blue)

            let categories = Array(Set(eligibleMoves.map(\.category))).sorted { $0.rawValue < $1.rawValue }
            ForEach(categories, id: \.self) { cat in
                HStack {
                    Text(cat.rawValue)
                        .font(.caption2)
                    Spacer()
                    if let stats = corpusWordCounts.perCategory[cat] {
                        Text("\(stats.min) / \(Int(stats.avg)) / \(stats.max)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("(\(stats.sampleCount))")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    } else {
                        Text("no data")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.05))
        .cornerRadius(6)
    }

    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.quote")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Gists Loaded")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Go to the Gist Script Writer first to paste your rambling and extract gists, then come back here. Data will autoload.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                coordinator.refreshFromGistWriter()
            } label: {
                Label("Try Loading from Gist Writer", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Placeholder Views (Future Phases)

    private func placeholderView(_ title: String, description: String, phase: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.3))

            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text(phase)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(coordinator.loadingMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }

    // MARK: - Helpers

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
    }
}
