//
//  StructureWorkbenchView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/16/26.
//
//  Structure Workbench tab for the Markov Script Writer.
//  100% deterministic data exploration — no LLM calls.
//  5 sections: Data Overview, Sequence Generation, Rhythm Constraints,
//  Donor Preview, and Spec Preview + Apply.
//

import SwiftUI

struct StructureWorkbenchView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @StateObject private var vm: StructureWorkbenchViewModel

    init(coordinator: MarkovScriptWriterCoordinator) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self._vm = StateObject(wrappedValue: StructureWorkbenchViewModel(coordinator: coordinator))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                loadSection
                moveTypeSelector

                if vm.selectedMoveType != nil {
                    dataOverviewSection
                    rollupComparisonSection
                    flattenedChainSection
                    atomTransitionStatsSection
                    sentenceBoundaryAnalysisSection
                    atomLengthAnalysisSection
                    sequenceGenerationSection
                    rhythmConstraintsSection
                    donorPreviewSection
                    specPreviewSection
                    moveProbeSection
                    batchProbeSection
                    skeletonComplianceSection
                }
            }
            .padding()
        }
        .task {
            if vm.loadingState == .idle, coordinator.donorCorpusState == .loaded {
                await vm.loadData()
            }
        }
    }

    // MARK: - Load Section

    private var loadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch vm.loadingState {
            case .idle:
                Button {
                    Task { await vm.loadData() }
                } label: {
                    Label("Load Corpus Data", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)

            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text(vm.loadingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .loaded:
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(vm.loadingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task { await vm.loadData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                // Fidelity Baseline
                HStack(spacing: 12) {
                    if vm.isComputingBaseline {
                        ProgressView()
                            .controlSize(.small)
                        Text("Computing baseline...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let status = vm.baselineStatus {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !vm.allSentences.isEmpty {
                            FadeOutCopyButton(
                                text: vm.copyCorpus(),
                                label: "Copy Corpus"
                            )
                            FadeOutCopyButton(
                                text: vm.copyCorpusDetails(),
                                label: "Copy Details"
                            )
                        }
                        FadeOutCopyButton(
                            text: vm.copyBaselineReport(),
                            label: "Copy Report"
                        )
                        Button("Recompute") {
                            vm.computeFidelityBaseline()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            vm.computeFidelityBaseline()
                        } label: {
                            Label("Compute Fidelity Baseline", systemImage: "waveform.path.ecg")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        if !vm.allSentences.isEmpty {
                            FadeOutCopyButton(
                                text: vm.copyCorpus(),
                                label: "Copy Corpus"
                            )
                            FadeOutCopyButton(
                                text: vm.copyCorpusDetails(),
                                label: "Copy Details"
                            )
                        }
                    }
                }

                // Per-dimension debug copy buttons
                if vm.baselineStatus != nil && !vm.allSentences.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(FidelityDimension.allCases, id: \.self) { dim in
                            FadeOutCopyButton(
                                text: vm.debugCopy(dim),
                                label: dim.shortLabel
                            )
                        }
                    }
                }

            case .error(let msg):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Button("Retry") {
                    Task { await vm.loadData() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Move Type Selector

    @ViewBuilder
    private var moveTypeSelector: some View {
        if vm.loadingState == .loaded {
            parameterCard("Move Type") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(vm.availableMoveTypes, id: \.self) { mt in
                            let isSelected = vm.selectedMoveType == mt
                            Button {
                                vm.selectMoveType(mt)
                            } label: {
                                Text(mt)
                                    .font(.caption2)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }

                // Move-type-specific copy buttons
                if let mt = vm.selectedMoveType {
                    HStack(spacing: 8) {
                        FadeOutCopyButton(
                            text: vm.copyCorpusForMoveType(),
                            label: "Copy \(mt) Corpus"
                        )
                        FadeOutCopyButton(
                            text: vm.copyCorpusDetailsForMoveType(),
                            label: "Copy \(mt) Details"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Section 1: Data Overview

    private var dataOverviewSection: some View {
        parameterCard("Data Overview") {
            VStack(alignment: .leading, spacing: 12) {
                // Stat badges
                let dist = vm.computeSentenceCountDistribution()
                let sigFreqs = vm.computeSignatureFrequencies()
                let sectionCount = vm.sectionsForMove.count
                let sentenceCounts = vm.sectionsForMove.map(\.sentenceCount)
                let minSC = sentenceCounts.min() ?? 0
                let maxSC = sentenceCounts.max() ?? 0
                let medianSC = sentenceCounts.sorted().isEmpty ? 0 : sentenceCounts.sorted()[sentenceCounts.count / 2]

                let totalSentences = sentenceCounts.reduce(0, +)

                HStack(spacing: 16) {
                    statBadge(value: "\(sectionCount)", label: "Sections")
                    statBadge(value: "\(totalSentences)", label: "Sentences")
                    statBadge(value: "\(minSC)–\(maxSC)", label: "Range")
                    statBadge(value: "\(medianSC)", label: "Median")
                    statBadge(value: "\(sigFreqs.count)", label: "Unique Sigs")
                }

                // Signature frequency breakdown
                let once = sigFreqs.filter { $0.count == 1 }.count
                let twoThree = sigFreqs.filter { $0.count >= 2 && $0.count <= 3 }.count
                let fourNine = sigFreqs.filter { $0.count >= 4 && $0.count <= 9 }.count
                let tenPlus = sigFreqs.filter { $0.count >= 10 }.count

                HStack(spacing: 12) {
                    freqBucket(count: once, label: "1x", color: .red)
                    freqBucket(count: twoThree, label: "2-3x", color: .orange)
                    freqBucket(count: fourNine, label: "4-9x", color: .yellow)
                    freqBucket(count: tenPlus, label: "10+", color: .green)
                }

                Divider()

                // Sentence count distribution
                sentenceCountDistributionView(dist, totalSections: sectionCount)

                Divider()

                // Signature frequencies
                signatureFrequenciesView(sigFreqs)

                Divider()

                // Real sections browser
                realSectionsBrowser
            }
        }
    }

    private func sentenceCountDistributionView(_ dist: [(length: Int, count: Int)], totalSections: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sentence Count Distribution")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if dist.isEmpty {
                Text("No sections found")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                let maxCount = dist.map(\.count).max() ?? 1
                ForEach(dist, id: \.length) { item in
                    HStack(spacing: 8) {
                        Text("\(item.length)s")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .frame(width: 28, alignment: .trailing)

                        GeometryReader { geo in
                            let barWidth = geo.size.width * CGFloat(item.count) / CGFloat(maxCount)
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: max(barWidth, 2))
                                .cornerRadius(2)
                        }
                        .frame(height: 16)

                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .leading)
                    }
                }
            }
        }
    }

    @State private var signatureFilterText = ""
    @State private var showAllSignatures = false

    private func signatureFrequenciesView(_ freqs: [(signature: String, count: Int)]) -> some View {
        let oneOffs = freqs.filter { $0.count == 1 }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Signature Frequencies")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(freqs.count) unique")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Copy buttons
            HStack(spacing: 8) {
                CompactCopyButton(text: formatSignatureList(freqs))
                Text("All \(freqs.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                CompactCopyButton(text: formatSignatureList(oneOffs))
                Text("1x only (\(oneOffs.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                CompactCopyButton(text: formatSignatureList(freqs.filter { $0.count >= 2 }))
                Text("2+ (\(freqs.count - oneOffs.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            let displayed = showAllSignatures ? freqs : Array(freqs.prefix(30))

            FlowLayout(spacing: 4) {
                ForEach(displayed, id: \.signature) { item in
                    HStack(spacing: 3) {
                        Text(item.signature)
                            .font(.system(size: 9))
                        Text("\(item.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.7))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                }
            }

            if freqs.count > 30 {
                Button(showAllSignatures ? "Show Top 30" : "Show All \(freqs.count)") {
                    showAllSignatures.toggle()
                }
                .font(.caption2)
            }
        }
    }

    private func formatSignatureList(_ freqs: [(signature: String, count: Int)]) -> String {
        freqs.map { "\($0.signature)\t\($0.count)" }.joined(separator: "\n")
    }

    @State private var expandedSectionIds: Set<String> = []

    private var realSectionsBrowser: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Real Sections (\(vm.sectionsForMove.count))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Menu {
                    Button("Sort by Sentence Count") { sortSections(by: .sentenceCount) }
                    Button("Sort by Video ID") { sortSections(by: .videoId) }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                }
            }

            LazyVStack(spacing: 6) {
                ForEach(vm.sectionsForMove) { section in
                    let isExpanded = expandedSectionIds.contains(section.id)
                    VStack(alignment: .leading, spacing: 6) {
                        // Collapsed header
                        Button {
                            withAnimation {
                                if isExpanded {
                                    expandedSectionIds.remove(section.id)
                                } else {
                                    expandedSectionIds.insert(section.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 12)

                                Text(section.videoId.prefix(12) + "...")
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text("S\(section.sectionIndex)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text("\(section.sentenceCount)s")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.15))
                                    .cornerRadius(4)

                                Spacer()

                                // Compact signature chips
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 2) {
                                        ForEach(Array(section.signatureSequence.enumerated()), id: \.offset) { _, sig in
                                            Text(abbreviateSignature(sig))
                                                .font(.system(size: 8))
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 1)
                                                .background(Color.purple.opacity(0.1))
                                                .cornerRadius(3)
                                        }
                                    }
                                }
                                .frame(maxWidth: 180)
                            }
                        }

                        // Expanded: show each sentence
                        if isExpanded {
                            ForEach(Array(section.sentences.enumerated()), id: \.offset) { idx, sentence in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 16, alignment: .trailing)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sentence.rawText)
                                            .font(.caption2)
                                            .foregroundColor(.primary)

                                        HStack(spacing: 6) {
                                            Text(sentence.slotSignature)
                                                .font(.system(size: 8))
                                                .foregroundColor(.purple)
                                            Text("\(sentence.wordCount)w")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                            Text("\(sentence.clauseCount)cl")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.leading, 16)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
    }

    enum SectionSort { case sentenceCount, videoId }
    @State private var sectionSortOrder: SectionSort = .sentenceCount

    private func sortSections(by order: SectionSort) {
        sectionSortOrder = order
        // ViewModel sorts by sentence count desc by default; this could be extended
    }

    // MARK: - Rollup Comparison Diagnostic

    @State private var expandedRollupStrategies: Set<String> = []

    private var rollupComparisonSection: some View {
        parameterCard("Rollup Comparison") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Signature rollup reduces sparsity by coarsening signatures into fewer categories for the bigram walk.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if vm.rollupDiagnostics.isEmpty {
                    Button {
                        vm.computeRollupDiagnostics()
                    } label: {
                        Label("Compute Diagnostics", systemImage: "chart.bar.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    // Summary comparison — horizontal scroll of strategy columns
                    rollupSummaryTable

                    Divider()

                    // Per-strategy expandable detail cards
                    ForEach(vm.rollupDiagnostics) { diag in
                        rollupDetailCard(diag)
                    }
                }
            }
        }
    }

    private var rollupSummaryTable: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(vm.rollupDiagnostics) { diag in
                    VStack(spacing: 6) {
                        Text(diag.strategy.shortLabel)
                            .font(.caption2)
                            .fontWeight(.bold)

                        Text("\(diag.uniqueCountAfter)")
                            .font(.title3)
                            .fontWeight(.bold)

                        Text("\(diag.uniqueCountBefore) \u{2192} \(diag.uniqueCountAfter)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)

                        Text(String(format: "%.1fx", diag.compressionRatio))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)

                        // Frequency buckets
                        VStack(spacing: 2) {
                            freqBucket(count: diag.bucket1x, label: "1x", color: .red)
                            freqBucket(count: diag.bucket2to3, label: "2-3x", color: .orange)
                            freqBucket(count: diag.bucket4to9, label: "4-9x", color: .yellow)
                            freqBucket(count: diag.bucket10plus, label: "10+", color: .green)
                        }
                    }
                    .frame(minWidth: 70)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func rollupDetailCard(_ diag: RollupDiagnostic) -> some View {
        let isExpanded = expandedRollupStrategies.contains(diag.id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation {
                    if isExpanded { expandedRollupStrategies.remove(diag.id) }
                    else { expandedRollupStrategies.insert(diag.id) }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text(diag.strategy.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(diag.uniqueCountAfter) unique")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if isExpanded {
                // Copy button for all frequencies
                HStack(spacing: 8) {
                    CompactCopyButton(text: formatRollupFreqs(diag.allFrequencies))
                    Text("Copy all \(diag.allFrequencies.count) frequencies")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Top 10 as FlowLayout chips
                Text("Top 10:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                FlowLayout(spacing: 4) {
                    ForEach(Array(diag.topFrequencies.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 3) {
                            Text(item.rolledUp)
                                .font(.system(size: 9))
                            Text("\(item.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.7))
                                .cornerRadius(4)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func formatRollupFreqs(_ freqs: [(rolledUp: String, count: Int)]) -> String {
        freqs.map { "\($0.rolledUp)\t\($0.count)" }.joined(separator: "\n")
    }

    // MARK: - Section 2: Sequence Generation

    private var sequenceGenerationSection: some View {
        parameterCard("Sequence Generation") {
            VStack(alignment: .leading, spacing: 12) {
                // Approach picker
                Picker("Approach", selection: $vm.selectedApproach) {
                    ForEach(StructureWorkbenchViewModel.SequenceApproach.allCases, id: \.self) { approach in
                        Text(approach.rawValue).tag(approach)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.selectedApproach) { _ in
                    vm.regenerateForCurrentApproach()
                }

                Divider()

                // Active approach content
                switch vm.selectedApproach {
                case .realSection:
                    realSectionApproachView
                case .bigramWalk:
                    bigramWalkApproachView
                case .statistical:
                    statisticalApproachView
                }

                // Active sequence summary strip
                if !vm.activeSignatureSequence.isEmpty {
                    Divider()
                    activeSequenceSummary
                }
            }
        }
    }

    // MARK: Approach A: Real Section

    private var realSectionApproachView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick a real section from the corpus to use as the structural template.")
                .font(.caption2)
                .foregroundColor(.secondary)

            LazyVStack(spacing: 6) {
                ForEach(vm.sectionsForMove) { section in
                    let isSelected = vm.selectedRealSectionId == section.id
                    Button {
                        vm.selectRealSection(section.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .font(.caption)
                                    .foregroundColor(isSelected ? .accentColor : .secondary)

                                Text(section.videoId.prefix(16) + (section.videoId.count > 16 ? "..." : ""))
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text("S\(section.sectionIndex)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text("\(section.sentenceCount) sentences")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)

                                Spacer()
                            }

                            // Signature chips
                            FlowLayout(spacing: 3) {
                                ForEach(Array(section.signatureSequence.enumerated()), id: \.offset) { idx, sig in
                                    signatureChip(sig, position: idx, total: section.sentenceCount)
                                }
                            }

                            // Show sentence texts when selected
                            if isSelected {
                                ForEach(Array(section.sentences.enumerated()), id: \.offset) { idx, sentence in
                                    HStack(alignment: .top, spacing: 4) {
                                        Text("\(idx + 1).")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text(sentence.rawText)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.leading, 4)
                                }
                            }
                        }
                        .padding(8)
                        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: Approach B: Bigram Walk

    private var bigramWalkApproachView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Controls
            VStack(alignment: .leading, spacing: 8) {
                // Sentence count
                HStack {
                    Text("Sentence Count")
                        .font(.caption)
                    Spacer()
                    Stepper("\(vm.bigramSentenceCount)", value: $vm.bigramSentenceCount,
                            in: vm.observedMinSentences...vm.observedMaxSentences)
                        .font(.caption)
                }

                // Starting signature
                if !vm.availableOpeningSignatures.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start Signature")
                            .font(.caption)
                        Picker("", selection: $vm.bigramStartingSignature) {
                            ForEach(vm.availableOpeningSignatures, id: \.self) { sig in
                                Text(sig)
                                    .font(.caption2)
                                    .tag(Optional(sig))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Top-1 vs weighted
                Toggle(isOn: $vm.bigramUseTopOne) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Greedy (Top-1)")
                            .font(.caption)
                        Text("Always pick highest probability; off = weighted random")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Rollup strategy picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signature Rollup")
                        .font(.caption)
                    Picker("", selection: $vm.selectedRollupStrategy) {
                        ForEach(RollupStrategy.allCases) { strategy in
                            Text(strategy.rawValue).tag(strategy)
                        }
                    }
                    .pickerStyle(.menu)

                    if vm.selectedRollupStrategy != .none {
                        if let diag = vm.rollupDiagnostics.first(where: { $0.strategy == vm.selectedRollupStrategy }) {
                            Text("\(diag.uniqueCountBefore) \u{2192} \(diag.uniqueCountAfter) unique (\(String(format: "%.1f", diag.compressionRatio))x compression)")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }

                // Generate / Re-roll
                HStack(spacing: 8) {
                    Button {
                        vm.generateBigramWalk()
                        vm.buildRhythmDefaults()
                        vm.buildDonorPreviews()
                    } label: {
                        Label("Generate", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        vm.rerollBigramWalk()
                    } label: {
                        Label("Re-roll", systemImage: "dice.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("Seed: \(vm.bigramSeed)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Walk result
            if !vm.bigramWalkResult.isEmpty {
                Divider()
                Text("Walk Result")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(vm.bigramWalkResult) { step in
                    bigramStepRow(step)
                }
            }
        }
    }

    @State private var expandedBigramSteps: Set<Int> = []

    private func bigramStepRow(_ step: StructureWorkbenchViewModel.BigramWalkStep) -> some View {
        let isExpanded = expandedBigramSteps.contains(step.positionIndex)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded {
                        expandedBigramSteps.remove(step.positionIndex)
                    } else {
                        expandedBigramSteps.insert(step.positionIndex)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("\(step.positionIndex + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    signatureChip(step.chosenSignature, position: step.positionIndex,
                                  total: vm.bigramSentenceCount)

                    Text(String(format: "%.0f%%", step.probability * 100))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(probabilityColor(step.probability))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(probabilityColor(step.probability).opacity(0.12))
                        .cornerRadius(4)

                    // Expansion indicator (raw mode)
                    if step.expandedCandidateCount > step.exactCandidateCount {
                        Text("\(step.exactCandidateCount)\u{2192}\(step.expandedCandidateCount)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.blue)
                    }

                    // Rollup indicator
                    if let coarse = step.coarseSignature {
                        Text("R: \(abbreviateSignature(coarse))")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.cyan)

                        if step.rollupCandidateCount > 0 {
                            Text("\(step.rollupCandidateCount) trans")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                        }
                    }

                    if !step.alternatives.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("\(step.alternatives.count) alts")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }

            if isExpanded && !step.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(step.alternatives.enumerated()), id: \.offset) { _, alt in
                        HStack(spacing: 6) {
                            Text(abbreviateSignature(alt.signature))
                                .font(.system(size: 8))
                                .foregroundColor(.purple)
                            Text(String(format: "%.1f%%", alt.probability * 100))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: Approach C: Statistical

    private var statisticalApproachView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Controls
            HStack {
                Text("Sentence Count")
                    .font(.caption)
                Spacer()
                Stepper("\(vm.statisticalSentenceCount)", value: $vm.statisticalSentenceCount,
                        in: vm.observedMinSentences...vm.observedMaxSentences)
                    .font(.caption)
            }

            Button {
                vm.generateStatisticalSequence()
                vm.buildRhythmDefaults()
                vm.buildDonorPreviews()
            } label: {
                Label("Generate", systemImage: "chart.bar.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)

            // Low coverage warning
            if let lowCoverage = vm.statisticalResult.first(where: { $0.totalAtPosition < 3 }) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Position \(lowCoverage.positionIndex + 1) has only \(lowCoverage.totalAtPosition) sections contributing")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            // Results
            if !vm.statisticalResult.isEmpty {
                Divider()
                Text("Positional Frequencies")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(vm.statisticalResult) { stat in
                    statisticalPositionRow(stat)
                }
            }
        }
    }

    @State private var expandedStatPositions: Set<Int> = []

    private func statisticalPositionRow(_ stat: StructureWorkbenchViewModel.PositionalSignatureStat) -> some View {
        let isExpanded = expandedStatPositions.contains(stat.positionIndex)
        let confidence = stat.totalAtPosition > 0 ? Double(stat.frequency) / Double(stat.totalAtPosition) : 0

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded {
                        expandedStatPositions.remove(stat.positionIndex)
                    } else {
                        expandedStatPositions.insert(stat.positionIndex)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("\(stat.positionIndex + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    signatureChip(stat.topSignature, position: stat.positionIndex,
                                  total: vm.statisticalSentenceCount)

                    // Frequency fraction
                    Text("\(stat.frequency)/\(stat.totalAtPosition)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(confidenceColor(confidence))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(confidenceColor(confidence).opacity(0.12))
                        .cornerRadius(4)

                    if stat.alternatives.count > 1 {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("\(stat.alternatives.count) alts")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(stat.alternatives.enumerated()), id: \.offset) { _, alt in
                        HStack(spacing: 6) {
                            Text(abbreviateSignature(alt.signature))
                                .font(.system(size: 8))
                                .foregroundColor(.purple)
                            Text("\(alt.count)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            if stat.totalAtPosition > 0 {
                                Text(String(format: "%.0f%%", Double(alt.count) / Double(stat.totalAtPosition) * 100))
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: Active Sequence Summary

    private var activeSequenceSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Active Sequence (\(vm.activeSignatureSequence.count) sentences)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                Spacer()
                CompactCopyButton(text: vm.activeSignatureSequence.joined(separator: "\n"))
            }

            FlowLayout(spacing: 4) {
                ForEach(Array(vm.activeSignatureSequence.enumerated()), id: \.offset) { idx, sig in
                    signatureChip(sig, position: idx, total: vm.activeSignatureSequence.count)
                }
            }
        }
    }

    // MARK: - Section 3: Rhythm Constraints

    private var rhythmConstraintsSection: some View {
        parameterCard("Rhythm Constraints") {
            VStack(alignment: .leading, spacing: 8) {
                if vm.activeSignatureSequence.isEmpty {
                    Text("Generate a sequence first to see rhythm constraints.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(vm.activeSignatureSequence.enumerated()), id: \.offset) { idx, sig in
                        rhythmCardForPosition(idx, signature: sig)
                        if idx < vm.activeSignatureSequence.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func rhythmCardForPosition(_ idx: Int, signature: String) -> some View {
        let posLabel: String
        if idx == 0 { posLabel = "opening" }
        else if idx == vm.activeSignatureSequence.count - 1 { posLabel = "closing" }
        else { posLabel = "mid" }

        let override = vm.rhythmOverrides[idx]

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Sentence \(idx + 1) (\(posLabel))")
                    .font(.caption)
                    .fontWeight(.semibold)

                signatureChip(signature, position: idx, total: vm.activeSignatureSequence.count)

                // Corpus match count
                let matchCount = vm.rhythmMatchCounts[idx] ?? 0
                Text("(\(matchCount) matches)")
                    .font(.system(size: 9))
                    .foregroundColor(matchCount >= 5 ? .green : matchCount >= 2 ? .orange : .red)

                Spacer()

                Button {
                    vm.buildRhythmDefaults()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
            }

            if let rhythm = override {
                // Word count
                HStack(spacing: 4) {
                    Text("Words:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .leading)

                    Stepper("\(rhythm.wordCountMin)", onIncrement: {
                        vm.rhythmOverrides[idx]?.wordCountMin += 1
                    }, onDecrement: {
                        if rhythm.wordCountMin > 1 {
                            vm.rhythmOverrides[idx]?.wordCountMin -= 1
                        }
                    })
                    .font(.caption2)

                    Text("–")
                        .font(.caption2)

                    Stepper("\(rhythm.wordCountMax)", onIncrement: {
                        vm.rhythmOverrides[idx]?.wordCountMax += 1
                    }, onDecrement: {
                        if rhythm.wordCountMax > rhythm.wordCountMin {
                            vm.rhythmOverrides[idx]?.wordCountMax -= 1
                        }
                    })
                    .font(.caption2)
                }

                // Clause count
                HStack(spacing: 4) {
                    Text("Clauses:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .leading)

                    Stepper("\(rhythm.clauseCountMin)", onIncrement: {
                        vm.rhythmOverrides[idx]?.clauseCountMin += 1
                    }, onDecrement: {
                        if rhythm.clauseCountMin > 1 {
                            vm.rhythmOverrides[idx]?.clauseCountMin -= 1
                        }
                    })
                    .font(.caption2)

                    Text("–")
                        .font(.caption2)

                    Stepper("\(rhythm.clauseCountMax)", onIncrement: {
                        vm.rhythmOverrides[idx]?.clauseCountMax += 1
                    }, onDecrement: {
                        if rhythm.clauseCountMax > rhythm.clauseCountMin {
                            vm.rhythmOverrides[idx]?.clauseCountMax -= 1
                        }
                    })
                    .font(.caption2)
                }

                // Common openers
                if !rhythm.commonOpeners.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Common Openers:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        FlowLayout(spacing: 3) {
                            ForEach(rhythm.commonOpeners, id: \.self) { opener in
                                Text(opener)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            } else {
                Text("No rhythm data — generate a sequence first")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Section 4: Donor Preview

    private var donorPreviewSection: some View {
        parameterCard("Donor Preview") {
            VStack(alignment: .leading, spacing: 8) {
                if vm.donorPreviews.isEmpty {
                    Text("Generate a sequence first to see donor availability.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    // Summary
                    let totalDonors = vm.donorPreviews.reduce(0) { $0 + $1.expandedMatchCount }
                    let minCoverage = vm.donorPreviews.map(\.expandedMatchCount).min() ?? 0
                    let zeroPosCount = vm.donorPreviews.filter { $0.expandedMatchCount == 0 }.count

                    HStack(spacing: 16) {
                        statBadge(value: "\(totalDonors)", label: "Total Donors")
                        statBadge(value: "\(minCoverage)", label: "Min Coverage")
                        if zeroPosCount > 0 {
                            statBadge(value: "\(zeroPosCount)", label: "Zero Pos")
                        }
                    }

                    if zeroPosCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("\(zeroPosCount) position(s) have NO matching donors in the corpus")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }

                    Divider()

                    ForEach(vm.donorPreviews) { preview in
                        donorPreviewRow(preview)
                    }
                }
            }
        }
    }

    @State private var expandedDonorPositions: Set<Int> = []

    private func donorPreviewRow(_ preview: StructureWorkbenchViewModel.DonorPreview) -> some View {
        let isExpanded = expandedDonorPositions.contains(preview.positionIndex)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded {
                        expandedDonorPositions.remove(preview.positionIndex)
                    } else {
                        expandedDonorPositions.insert(preview.positionIndex)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("\(preview.positionIndex + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Text(abbreviateSignature(preview.targetSignature))
                        .font(.system(size: 9))
                        .foregroundColor(.purple)

                    // Exact match badge
                    Text("\(preview.exactMatchCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(coverageBadgeColor(preview.exactMatchCount))
                        .cornerRadius(4)

                    if preview.expandedMatchCount > preview.exactMatchCount {
                        Text("+\(preview.expandedMatchCount - preview.exactMatchCount) expanded")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }

                    if !preview.topDonors.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }

            if isExpanded {
                ForEach(Array(preview.topDonors.prefix(5).enumerated()), id: \.offset) { _, donor in
                    HStack(alignment: .top, spacing: 4) {
                        Text("\"")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(donor.rawText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.leading, 24)
                }
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: - Section 5: Spec Preview + Apply

    private var specPreviewSection: some View {
        parameterCard("Spec Preview + Apply") {
            VStack(alignment: .leading, spacing: 10) {
                if vm.activeSignatureSequence.isEmpty {
                    Text("Generate a sequence to preview the structural specification.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    // Preview text
                    Text(vm.generateSpecPreviewText())
                        .font(.system(size: 10, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)

                    HStack(spacing: 12) {
                        FadeOutCopyButton(
                            text: vm.generateSpecPreviewText(),
                            label: "Copy Spec"
                        )

                        Button {
                            vm.applySpec()
                        } label: {
                            Label("Apply to Compare Tab", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    // Active spec status
                    if let spec = coordinator.approvedStructuralSpec {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Active spec: \(spec.approachUsed), \(spec.sentenceCount) sentences")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Spacer()
                            Text(spec.approvedAt, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    // MARK: - Section 6: Move Probe

    @State private var expandedProbeDimensions: Set<String> = []

    private var moveProbeSection: some View {
        parameterCard("Move Probe") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Evaluate a single section against the corpus baseline for the selected move type.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if vm.baselineStatus == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Compute fidelity baseline first to use the probe.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } else {
                    // Input area
                    probeInputArea

                    // Result display
                    if let result = vm.probeResult {
                        Divider()
                        probeResultDisplay(result)
                    }
                }
            }
        }
    }

    private var probeInputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $vm.probeInputText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                if vm.probeInputText.isEmpty {
                    Text("Paste section text here...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await vm.evaluateProbeWithS2() }
                } label: {
                    if vm.isAnnotatingS2 {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Annotating S2...").font(.caption)
                        }
                    } else {
                        Label("Evaluate", systemImage: "play.fill")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.probeInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || coordinator.fidelityCache == nil
                          || vm.isAnnotatingS2)

                Menu {
                    ForEach(vm.sectionsForMove) { section in
                        Button {
                            vm.loadSectionAsProbe(sectionId: section.id)
                        } label: {
                            Text("\(section.videoId.prefix(12))... S\(section.sectionIndex) — \(section.sentenceCount)s")
                        }
                    }
                } label: {
                    Label("Load \(vm.selectedMoveType ?? "Section")", systemImage: "doc.text")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(vm.sectionsForMove.isEmpty)

                Button {
                    vm.probeInputText = ""
                    vm.probeResult = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(vm.probeInputText.isEmpty && vm.probeResult == nil)

                Spacer()
            }
        }
    }

    private func probeResultDisplay(_ result: SectionFidelityResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Composite score + stats
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", result.compositeScore))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(probeScoreColor(result.compositeScore))
                    Text("COMPOSITE")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 70)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        statBadge(value: "\(result.sentenceCount)", label: "Sentences")
                        statBadge(value: "\(result.wordCount)", label: "Words")
                    }
                }

                Spacer()

                FadeOutCopyButton(
                    text: vm.copyProbeReport(),
                    label: "Copy Report"
                )
            }

            // Hard-fail chips
            let failedChecks = result.hardFailResults.filter { !$0.passed }
            if !failedChecks.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(Array(failedChecks.enumerated()), id: \.offset) { _, hf in
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 8))
                            Text(hf.rule.label)
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(hf.rule.severity == .fail
                                    ? Color.red.opacity(0.15)
                                    : Color.orange.opacity(0.15))
                        .foregroundColor(hf.rule.severity == .fail ? .red : .orange)
                        .cornerRadius(4)
                    }
                }
            }

            Divider()

            // 8 dimension bars
            ForEach(FidelityDimension.allCases, id: \.self) { dim in
                if let dimScore = result.dimensionScores[dim] {
                    probeDimensionRow(dim: dim, dimScore: dimScore)
                }
            }
        }
    }

    private func probeDimensionRow(dim: FidelityDimension, dimScore: DimensionScore) -> some View {
        let isExpanded = expandedProbeDimensions.contains(dim.rawValue)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded {
                        expandedProbeDimensions.remove(dim.rawValue)
                    } else {
                        expandedProbeDimensions.insert(dim.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(dim.shortLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background track
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 10)

                            // Baseline P25–P75 range overlay
                            if let range = dimScore.baselineRange {
                                let p25X = geo.size.width * CGFloat(max(0, min(range.p25, 100)) / 100.0)
                                let p75X = geo.size.width * CGFloat(max(0, min(range.p75, 100)) / 100.0)
                                Rectangle()
                                    .fill(Color.yellow.opacity(0.25))
                                    .frame(width: max(p75X - p25X, 1), height: 10)
                                    .offset(x: p25X)
                            }

                            // Score bar
                            Rectangle()
                                .fill(probeScoreColor(dimScore.score))
                                .frame(width: geo.size.width * CGFloat(max(0, min(dimScore.score, 100)) / 100.0),
                                       height: 10)
                        }
                        .cornerRadius(5)
                    }
                    .frame(height: 10)

                    Text(String(format: "%.0f", dimScore.score))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(probeScoreColor(dimScore.score))
                        .frame(width: 26, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }

            // Sub-metrics (expanded)
            if isExpanded && !dimScore.subMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    // Baseline range header
                    if let range = dimScore.baselineRange {
                        Text("Baseline: P25=\(String(format: "%.1f", range.p25)) | Med=\(String(format: "%.1f", range.median)) | P75=\(String(format: "%.1f", range.p75))")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                            .padding(.leading, 16)
                    }

                    ForEach(Array(dimScore.subMetrics.enumerated()), id: \.offset) { _, sub in
                        HStack(spacing: 4) {
                            Text(sub.name)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Raw: \(String(format: "%.2f", sub.rawValue))")
                                .font(.system(size: 8))
                                .foregroundColor(.primary)

                            Text("Corpus: \(String(format: "%.2f", sub.corpusMean))")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)

                            Text(String(format: "%.0f", sub.score))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(probeScoreColor(sub.score))
                                .frame(width: 22, alignment: .trailing)
                        }
                        .padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func probeScoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    // MARK: - Section 7: Batch Probe

    @State private var expandedBatchEntries: Set<String> = []

    private var batchProbeSection: some View {
        parameterCard("Batch Probe — All Other Moves") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Load and evaluate all non-corpus position-1 sections to find which dimensions discriminate best.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if vm.baselineStatus == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Compute fidelity baseline first.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } else {
                    // Controls
                    HStack(spacing: 8) {
                        if vm.isLoadingOtherMoves {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading videos...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Button {
                                Task {
                                    await vm.loadOtherMoveTypes()
                                    vm.evaluateAllProbes()
                                }
                            } label: {
                                Label(vm.otherMoveEntries.isEmpty ? "Load & Evaluate All" : "Reload",
                                      systemImage: "play.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if !vm.otherMoveEntries.isEmpty {
                            let evaluated = vm.otherMoveEntries.filter { $0.result != nil }.count
                            Text("\(vm.otherMoveEntries.count) loaded, \(evaluated) evaluated")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            if let coverage = vm.s2CoverageInfo {
                                let fallback = coverage.total - coverage.withS2
                                Text("S2: \(coverage.withS2)/\(coverage.total) LLM" + (fallback > 0 ? ", \(fallback) hint" : ""))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(fallback == 0 ? .green : .orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((fallback == 0 ? Color.green : Color.orange).opacity(0.1))
                                    .cornerRadius(4)
                            }

                            Spacer()

                            FadeOutCopyButton(
                                text: vm.copyBatchReport(),
                                label: "Copy Report"
                            )
                        }

                        if let diagnostic = vm.batchLoadDiagnostic {
                            Text(diagnostic)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    // Distribution summary
                    let distributions = vm.computeDimensionDistributions()
                    if !distributions.isEmpty {
                        Divider()
                        batchDistributionSummary(distributions)
                    }

                    // Per-video scorecard
                    if !vm.otherMoveEntries.isEmpty {
                        Divider()
                        batchScorecardList
                    }
                }
            }
        }
    }

    private func batchDistributionSummary(_ distributions: [StructureWorkbenchViewModel.DimensionDistribution]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dimension Discrimination (best first)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(distributions) { dist in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(dist.dimension.shortLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 42, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Background track
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.08))
                                    .frame(height: 14)

                                // Baseline P25-P75 range (yellow)
                                if let bP25 = dist.baselineP25, let bP75 = dist.baselineP75 {
                                    let x25 = geo.size.width * CGFloat(max(0, min(bP25, 100)) / 100.0)
                                    let x75 = geo.size.width * CGFloat(max(0, min(bP75, 100)) / 100.0)
                                    Rectangle()
                                        .fill(Color.yellow.opacity(0.4))
                                        .frame(width: max(x75 - x25, 2), height: 14)
                                        .offset(x: x25)
                                }

                                // Other-move range (red)
                                let xMin = geo.size.width * CGFloat(max(0, min(dist.min, 100)) / 100.0)
                                let xMax = geo.size.width * CGFloat(max(0, min(dist.max, 100)) / 100.0)
                                Rectangle()
                                    .fill(Color.red.opacity(0.35))
                                    .frame(width: max(xMax - xMin, 2), height: 14)
                                    .offset(x: xMin)

                                // Other-move mean marker
                                let xMean = geo.size.width * CGFloat(max(0, min(dist.mean, 100)) / 100.0)
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: 2, height: 14)
                                    .offset(x: xMean)

                                // Baseline median marker
                                if let bMed = dist.baselineMedian {
                                    let xBMed = geo.size.width * CGFloat(max(0, min(bMed, 100)) / 100.0)
                                    Rectangle()
                                        .fill(Color.yellow)
                                        .frame(width: 2, height: 14)
                                        .offset(x: xBMed)
                                }
                            }
                            .cornerRadius(4)
                        }
                        .frame(height: 14)

                        Text(String(format: "%.0f", dist.separation))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(dist.separation >= 20 ? .green : dist.separation >= 10 ? .orange : .red)
                            .frame(width: 24, alignment: .trailing)
                    }

                    // Stats line
                    HStack(spacing: 8) {
                        if let bMed = dist.baselineMedian {
                            Text("Baseline: \(String(format: "%.0f", bMed))")
                                .foregroundColor(.yellow)
                        }
                        Text("Others: \(String(format: "%.0f", dist.mean)) [\(String(format: "%.0f", dist.min))-\(String(format: "%.0f", dist.max))]")
                            .foregroundColor(.red)
                    }
                    .font(.system(size: 8))
                    .padding(.leading, 48)
                }
            }

            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Rectangle().fill(Color.yellow.opacity(0.4)).frame(width: 12, height: 8).cornerRadius(2)
                    Text("Baseline P25-P75")
                }
                HStack(spacing: 3) {
                    Rectangle().fill(Color.red.opacity(0.35)).frame(width: 12, height: 8).cornerRadius(2)
                    Text("Other moves range")
                }
                HStack(spacing: 3) {
                    Text("Score = separation")
                }
            }
            .font(.system(size: 7))
            .foregroundColor(.secondary)
        }
    }

    private var batchScorecardList: some View {
        let sorted = vm.otherMoveEntries
            .filter { $0.result != nil }
            .sorted { ($0.result?.compositeScore ?? 0) < ($1.result?.compositeScore ?? 0) }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Per-Video Scorecard (\(sorted.count) entries, worst first)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            LazyVStack(spacing: 4) {
                ForEach(sorted) { entry in
                    let isExpanded = expandedBatchEntries.contains(entry.id)
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation {
                                if isExpanded {
                                    expandedBatchEntries.remove(entry.id)
                                } else {
                                    expandedBatchEntries.insert(entry.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                // Composite score
                                let composite = entry.result?.compositeScore ?? 0
                                Text(String(format: "%.0f", composite))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(probeScoreColor(composite))
                                    .frame(width: 26, alignment: .trailing)

                                // Move type chip
                                Text(entry.moveType)
                                    .font(.system(size: 8))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.12))
                                    .cornerRadius(4)

                                // Video title
                                Text(entry.videoTitle)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()

                                // Tap to load into single probe
                                Button {
                                    vm.loadProbeEntry(entry)
                                } label: {
                                    Image(systemName: "arrow.up.doc")
                                        .font(.system(size: 9))
                                        .foregroundColor(.accentColor)
                                }

                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 7))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Expanded: mini dimension bars
                        if isExpanded, let result = entry.result {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(FidelityDimension.allCases, id: \.self) { dim in
                                    if let dimScore = result.dimensionScores[dim] {
                                        HStack(spacing: 4) {
                                            Text(dim.shortLabel)
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                                .frame(width: 36, alignment: .leading)

                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    Rectangle()
                                                        .fill(Color.secondary.opacity(0.08))
                                                        .frame(height: 6)
                                                    Rectangle()
                                                        .fill(probeScoreColor(dimScore.score))
                                                        .frame(width: geo.size.width * CGFloat(max(0, min(dimScore.score, 100)) / 100.0),
                                                               height: 6)
                                                }
                                                .cornerRadius(3)
                                            }
                                            .frame(height: 6)

                                            Text(String(format: "%.0f", dimScore.score))
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(probeScoreColor(dimScore.score))
                                                .frame(width: 20, alignment: .trailing)

                                            // S2 source badge: LLM (green) vs hint (orange)
                                            if dim == .slotSignatureS2 {
                                                let hasLLM = entry.s2Signatures != nil && !(entry.s2Signatures?.isEmpty ?? true)
                                                Text(hasLLM ? "LLM" : "hint")
                                                    .font(.system(size: 7, weight: .semibold))
                                                    .foregroundColor(hasLLM ? .green : .orange)
                                                    .padding(.horizontal, 3)
                                                    .padding(.vertical, 1)
                                                    .background((hasLLM ? Color.green : Color.orange).opacity(0.15))
                                                    .cornerRadius(3)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.leading, 32)
                        }
                    }
                    .padding(6)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Section 8: Skeleton Compliance Test

    @State private var expandedCompliancePositions: Set<Int> = []
    @State private var expandedComplianceDimensions: Set<String> = []

    private var skeletonComplianceSection: some View {
        parameterCard("Skeleton Compliance Test") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Phase B proof of concept: clone a real corpus skeleton, generate new content for a different topic, validate with deterministic hint detectors, and score with ScriptFidelityService.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if vm.baselineStatus == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Compute fidelity baseline first to run the compliance test.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } else {
                    // Config row
                    complianceConfigRow

                    // Skeleton preview
                    if let skeleton = vm.complianceSkeletonSection, vm.complianceResult == nil && !vm.complianceIsRunning {
                        complianceSkeletonPreview(skeleton)
                    }

                    // Progress
                    if vm.complianceIsRunning, let progress = vm.complianceProgress {
                        complianceProgressView(progress)
                    }

                    // Results
                    if let result = vm.complianceResult {
                        Divider()
                        complianceResultView(result)
                    }
                }
            }
        }
    }

    private var complianceConfigRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content Topic")
                .font(.caption2)
                .fontWeight(.semibold)

            TextField("Topic for generated content", text: $vm.complianceTopic)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button {
                    Task { await vm.runComplianceTest() }
                } label: {
                    Label("Run Test", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    vm.complianceTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || coordinator.fidelityCache == nil
                    || vm.sectionsForMove.isEmpty
                    || vm.complianceIsRunning
                )

                if vm.complianceResult != nil {
                    Button {
                        vm.complianceResult = nil
                        expandedCompliancePositions.removeAll()
                        expandedComplianceDimensions.removeAll()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let skeleton = vm.complianceSkeletonSection {
                    Text("\(skeleton.sentenceCount) positions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func complianceSkeletonPreview(_ section: StructureWorkbenchViewModel.ReconstructedSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Skeleton Preview")
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text("(\(section.videoId.prefix(12))... S\(section.sectionIndex))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            ForEach(Array(section.sentences.enumerated()), id: \.offset) { i, sentence in
                HStack(spacing: 6) {
                    Text("[\(i)]")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: .trailing)

                    Text(abbreviateSignature(sentence.slotSignature))
                        .font(.system(size: 8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(3)

                    Text("\(sentence.wordCount)w")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Text(sentence.isQuestion ? "Q" : sentence.isFragment ? "F" : "S")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(.secondary)

                    let preview = sentence.rawText.split(separator: " ").prefix(8).joined(separator: " ")
                    Text(preview + (sentence.rawText.split(separator: " ").count > 8 ? "..." : ""))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(6)
    }

    private func complianceProgressView(_ progress: (current: Int, total: Int, text: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(progress.text)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: Double(progress.current), total: Double(progress.total))
                .tint(.accentColor)
        }
    }

    private func complianceResultView(_ result: ComplianceTestResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary badges
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    let hits = result.positions.filter(\.signatureMatch).count
                    Text("\(hits)/\(result.positions.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(result.signatureHitRate >= 0.8 ? .green : result.signatureHitRate >= 0.5 ? .orange : .red)
                    Text("SIG HITS")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 70)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f", result.avgWordCountDelta))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(result.avgWordCountDelta <= 3 ? .green : result.avgWordCountDelta <= 5 ? .orange : .red)
                    Text("AVG WC \u{0394}")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                if let fidelity = result.sectionFidelity {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", fidelity.compositeScore))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(probeScoreColor(fidelity.compositeScore))
                        Text("FIDELITY")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70)
                }

                Spacer()

                FadeOutCopyButton(
                    text: SkeletonComplianceService.formatDebugReport(result),
                    label: "Copy Report"
                )
            }

            Divider()

            // Per-position cards
            Text("Per-Position Results")
                .font(.caption2)
                .fontWeight(.semibold)

            ForEach(result.positions, id: \.index) { pos in
                compliancePositionRow(pos)
            }

            // Fidelity dimension scores
            if let fidelity = result.sectionFidelity {
                Divider()

                Text("Fidelity Dimensions")
                    .font(.caption2)
                    .fontWeight(.semibold)

                ForEach(FidelityDimension.allCases, id: \.self) { dim in
                    if let dimScore = fidelity.dimensionScores[dim] {
                        complianceDimensionRow(dim: dim, dimScore: dimScore)
                    }
                }
            }
        }
    }

    private func compliancePositionRow(_ pos: ComplianceTestResult.PositionResult) -> some View {
        let isExpanded = expandedCompliancePositions.contains(pos.index)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded {
                        expandedCompliancePositions.remove(pos.index)
                    } else {
                        expandedCompliancePositions.insert(pos.index)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("[\(pos.index)]")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: .trailing)

                    Image(systemName: pos.signatureMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(pos.signatureMatch ? .green : .red)

                    Text(abbreviateSignature(pos.targetSignature))
                        .font(.system(size: 8))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(3)

                    if !pos.signatureMatch {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 6))
                            .foregroundColor(.red)
                        Text(abbreviateSignature(pos.actualSignature))
                            .font(.system(size: 8))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(3)
                    }

                    Spacer()

                    let wcDelta = pos.actualWordCount - pos.targetWordCount
                    let wcColor: Color = abs(wcDelta) <= 3 ? .green : abs(wcDelta) <= 5 ? .orange : .red
                    Text("\(pos.actualWordCount)w")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(wcColor)
                    Text("(\(wcDelta >= 0 ? "+" : "")\(wcDelta))")
                        .font(.system(size: 7))
                        .foregroundColor(wcColor)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generated:")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.blue)
                        Text(pos.generatedText)
                            .font(.system(size: 9))
                            .padding(6)
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Donor (voice ref):")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.green)
                        Text(pos.donorText)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.green.opacity(0.05))
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Requirements:")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.orange)
                        Text(SkeletonComplianceService.combinedTokenRequirements(for: pos.targetSignature))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.orange.opacity(0.05))
                            .cornerRadius(4)
                    }
                }
                .padding(.leading, 26)
            }
        }
    }

    private func complianceDimensionRow(dim: FidelityDimension, dimScore: DimensionScore) -> some View {
        let isExpanded = expandedComplianceDimensions.contains(dim.rawValue)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded {
                        expandedComplianceDimensions.remove(dim.rawValue)
                    } else {
                        expandedComplianceDimensions.insert(dim.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(dim.shortLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 10)

                            if let range = dimScore.baselineRange {
                                let p25X = geo.size.width * CGFloat(max(0, min(range.p25, 100)) / 100.0)
                                let p75X = geo.size.width * CGFloat(max(0, min(range.p75, 100)) / 100.0)
                                Rectangle()
                                    .fill(Color.yellow.opacity(0.25))
                                    .frame(width: max(p75X - p25X, 1), height: 10)
                                    .offset(x: p25X)
                            }

                            Rectangle()
                                .fill(probeScoreColor(dimScore.score))
                                .frame(width: geo.size.width * CGFloat(max(0, min(dimScore.score, 100)) / 100.0),
                                       height: 10)
                        }
                        .cornerRadius(5)
                    }
                    .frame(height: 10)

                    Text(String(format: "%.0f", dimScore.score))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(probeScoreColor(dimScore.score))
                        .frame(width: 26, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }

            if isExpanded && !dimScore.subMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    if let range = dimScore.baselineRange {
                        Text("Baseline: P25=\(String(format: "%.1f", range.p25)) | Med=\(String(format: "%.1f", range.median)) | P75=\(String(format: "%.1f", range.p75))")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                            .padding(.leading, 16)
                    }

                    ForEach(Array(dimScore.subMetrics.enumerated()), id: \.offset) { _, sub in
                        HStack(spacing: 4) {
                            Text(sub.name)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Raw: \(String(format: "%.2f", sub.rawValue))")
                                .font(.system(size: 8))
                                .foregroundColor(.primary)

                            Text("Corpus: \(String(format: "%.2f", sub.corpusMean))")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)

                            Text(String(format: "%.0f", sub.score))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(probeScoreColor(sub.score))
                                .frame(width: 22, alignment: .trailing)
                        }
                        .padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Flattened Atom Chains

    @State private var expandedFlattenedChainIds: Set<String> = []

    private var flattenedChainSection: some View {
        parameterCard("Flattened Atom Chains") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Each section's slot sequences concatenated into one continuous atom ribbon. Faint dividers mark sentence boundaries. Look for rhythmic patterns independent of punctuation.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if vm.flattenedChains.isEmpty {
                    Button {
                        vm.computeFlattenedChains()
                    } label: {
                        Label("Compute Flattened Chains", systemImage: "arrow.right.arrow.left")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    // Summary stats
                    HStack(spacing: 16) {
                        let totalAtoms = vm.flattenedChains.reduce(0) { $0 + $1.atoms.count }
                        let avgAtoms = vm.flattenedChains.isEmpty ? 0 : totalAtoms / vm.flattenedChains.count
                        statBadge(value: "\(vm.flattenedChains.count)", label: "Sections")
                        statBadge(value: "\(totalAtoms)", label: "Total Atoms")
                        statBadge(value: "\(avgAtoms)", label: "Avg/Section")
                    }

                    HStack(spacing: 8) {
                        FadeOutCopyButton(
                            text: vm.copyAllFlattenedChains(),
                            label: "Copy All Chains"
                        )
                        Button("Recompute") {
                            vm.computeFlattenedChains()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }

                    // Atom legend
                    atomLegend

                    Divider()

                    LazyVStack(spacing: 6) {
                        ForEach(vm.flattenedChains) { chain in
                            flattenedChainRow(chain)
                        }
                    }
                }
            }
        }
    }

    private var atomLegend: some View {
        FlowLayout(spacing: 3) {
            ForEach(SlotType.allCases, id: \.self) { slot in
                Text(abbreviateSignature(slot.rawValue))
                    .font(.system(size: 7))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(atomColor(for: slot.rawValue).opacity(0.3))
                    .cornerRadius(3)
            }
        }
    }

    private func flattenedChainRow(_ chain: StructureWorkbenchViewModel.FlattenedChain) -> some View {
        let isExpanded = expandedFlattenedChainIds.contains(chain.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded { expandedFlattenedChainIds.remove(chain.id) }
                    else { expandedFlattenedChainIds.insert(chain.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(chain.videoId.prefix(12)) + "...")
                        .font(.caption2)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("S\(chain.sectionIndex)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(chain.atoms.count) atoms")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text("\(chain.sentenceCount) sent")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    CompactCopyButton(text: vm.copyFlattenedChain(chain))
                }
            }

            // Atom ribbon
            FlowLayout(spacing: 1) {
                ForEach(chain.atoms) { atom in
                    HStack(spacing: 0) {
                        if chain.sentenceBoundaryIndices.contains(atom.id) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 14)
                                .padding(.horizontal, 1)
                        }
                        Text(abbreviateSignature(atom.slotType))
                            .font(.system(size: 7))
                            .padding(.horizontal, 2)
                            .padding(.vertical, 1)
                            .background(atomColor(for: atom.slotType).opacity(0.25))
                            .cornerRadius(2)
                    }
                }
            }

            // Expanded: raw sentence text with per-sentence atoms
            if isExpanded {
                if let section = vm.sectionsForMove.first(where: { $0.id == chain.id }) {
                    ForEach(Array(section.sentences.enumerated()), id: \.offset) { idx, sentence in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(idx + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 16, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sentence.rawText)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                FlowLayout(spacing: 1) {
                                    ForEach(Array(sentence.slotSequence.enumerated()), id: \.offset) { _, slot in
                                        Text(abbreviateSignature(slot))
                                            .font(.system(size: 7))
                                            .padding(.horizontal, 2)
                                            .padding(.vertical, 1)
                                            .background(atomColor(for: slot).opacity(0.25))
                                            .cornerRadius(2)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 16)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Atom-Level Transition Stats

    @State private var expandedAtomTransitionRows: Set<String> = []

    private var atomTransitionStatsSection: some View {
        parameterCard("Atom-Level Transition Stats") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Transition probabilities between individual slot types (atoms) within sentences. Low entropy = strong patterns, high entropy = unpredictable. Helps determine if atom-level Markov chains have enough signal.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if vm.atomTransitionMatrix.isEmpty {
                    Button {
                        vm.computeAtomTransitionMatrix()
                    } label: {
                        Label("Compute Transition Matrix", systemImage: "square.grid.3x3")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 16) {
                        statBadge(value: "\(vm.atomTransitionMatrix.count)", label: "Source Types")
                        statBadge(value: "\(vm.atomTransitionTotalCount)", label: "Transitions")
                        let avgEntropy = vm.atomTransitionMatrix.reduce(0.0) { $0 + $1.normalizedEntropy } / max(1, Double(vm.atomTransitionMatrix.count))
                        statBadge(value: String(format: "%.2f", avgEntropy), label: "Avg Norm H")
                    }

                    HStack(spacing: 8) {
                        FadeOutCopyButton(
                            text: vm.copyAtomTransitionMatrix(),
                            label: "Copy Matrix"
                        )
                        Button("Recompute") {
                            vm.computeAtomTransitionMatrix()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    LazyVStack(spacing: 4) {
                        ForEach(vm.atomTransitionMatrix) { row in
                            atomTransitionRowView(row)
                        }
                    }
                }
            }
        }
    }

    private func atomTransitionRowView(_ row: StructureWorkbenchViewModel.AtomTransitionRow) -> some View {
        let isExpanded = expandedAtomTransitionRows.contains(row.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded { expandedAtomTransitionRows.remove(row.id) }
                    else { expandedAtomTransitionRows.insert(row.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(abbreviateSignature(row.sourceSlotType))
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(atomColor(for: row.sourceSlotType).opacity(0.3))
                        .cornerRadius(4)

                    Text("\(row.totalTransitions)x")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    // Entropy bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.08))
                                .frame(height: 8)
                            Rectangle()
                                .fill(row.normalizedEntropy > 0.8 ? Color.red : row.normalizedEntropy > 0.5 ? Color.orange : Color.green)
                                .frame(width: geo.size.width * CGFloat(row.normalizedEntropy), height: 8)
                        }
                        .cornerRadius(4)
                    }
                    .frame(width: 60, height: 8)

                    Text("H=\(String(format: "%.2f", row.normalizedEntropy))")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Top 3 targets inline
                    ForEach(Array(row.top3.enumerated()), id: \.offset) { _, t in
                        HStack(spacing: 1) {
                            Text(abbreviateSignature(t.targetSlotType))
                                .font(.system(size: 7))
                            Text("\(String(format: "%.0f%%", t.probability * 100))")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(atomColor(for: t.targetSlotType).opacity(0.2))
                        .cornerRadius(3)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }

            // Expanded: full probability distribution
            if isExpanded {
                ForEach(Array(row.transitions.enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 6) {
                        Text(abbreviateSignature(t.targetSlotType))
                            .font(.system(size: 8))
                            .frame(width: 60, alignment: .leading)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(atomColor(for: t.targetSlotType).opacity(0.2))
                            .cornerRadius(3)

                        GeometryReader { geo in
                            Rectangle()
                                .fill(atomColor(for: t.targetSlotType).opacity(0.5))
                                .frame(width: geo.size.width * CGFloat(t.probability))
                                .cornerRadius(2)
                        }
                        .frame(height: 10)

                        Text("\(t.count)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        Text(String(format: "%.1f%%", t.probability * 100))
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: - Sentence Boundary Analysis

    private var sentenceBoundaryAnalysisSection: some View {
        parameterCard("Sentence Boundary Analysis") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Compares atom transitions ACROSS sentence boundaries vs WITHIN sentences. If distributions differ, sentence breaks carry structural meaning. If similar, breaks may be arbitrary and pure atom-level chains could work.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if vm.boundaryAnalysis == nil {
                    Button {
                        vm.computeBoundaryAnalysis()
                    } label: {
                        Label("Compute Boundary Analysis", systemImage: "arrow.left.arrow.right")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                } else if let analysis = vm.boundaryAnalysis {
                    // Verdict banner
                    boundaryVerdictBanner(analysis)

                    HStack(spacing: 16) {
                        statBadge(value: "\(analysis.crossBoundaryTotal)", label: "Cross-Boundary")
                        statBadge(value: "\(analysis.withinSentenceTotal)", label: "Within-Sent")
                        statBadge(value: String(format: "%.4f", analysis.jsDivergence), label: "JS Divergence")
                    }

                    HStack(spacing: 8) {
                        FadeOutCopyButton(
                            text: vm.copyBoundaryAnalysis(),
                            label: "Copy Report"
                        )
                        Button("Recompute") {
                            vm.computeBoundaryAnalysis()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    // Boundary-enriched transitions
                    Text("Boundary-Enriched (more common at sentence breaks)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)

                    ForEach(Array(analysis.topBoundaryBiased.prefix(10))) { t in
                        boundaryTransitionRow(t)
                    }

                    Divider()

                    // Interior-enriched transitions
                    Text("Interior-Enriched (more common within sentences)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)

                    ForEach(Array(analysis.topInteriorBiased.prefix(10))) { t in
                        boundaryTransitionRow(t)
                    }
                }
            }
        }
    }

    private func boundaryVerdictBanner(_ analysis: StructureWorkbenchViewModel.BoundaryAnalysisResult) -> some View {
        let js = analysis.jsDivergence
        let icon: String
        let color: Color
        let text: String
        if js > 0.1 {
            icon = "exclamationmark.triangle.fill"
            color = .red
            text = "DIFFERENT distributions — sentence breaks carry structural meaning"
        } else if js > 0.03 {
            icon = "info.circle.fill"
            color = .orange
            text = "Moderate difference — some structural signal at boundaries"
        } else {
            icon = "checkmark.circle.fill"
            color = .green
            text = "SIMILAR distributions — sentence breaks may be arbitrary"
        }

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    private func boundaryTransitionRow(_ t: StructureWorkbenchViewModel.BoundaryAnalysisResult.TransitionComparison) -> some View {
        HStack(spacing: 6) {
            Text(abbreviateSignature(t.fromSlotType))
                .font(.system(size: 8))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(atomColor(for: t.fromSlotType).opacity(0.25))
                .cornerRadius(3)

            Image(systemName: "arrow.right")
                .font(.system(size: 7))
                .foregroundColor(.secondary)

            Text(abbreviateSignature(t.toSlotType))
                .font(.system(size: 8))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(atomColor(for: t.toSlotType).opacity(0.25))
                .cornerRadius(3)

            Spacer()

            VStack(spacing: 0) {
                Text(String(format: "%.1f%%", t.crossBoundaryPct * 100))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.orange)
                Text("\(t.crossBoundaryCount)x")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .frame(width: 40)

            VStack(spacing: 0) {
                Text(String(format: "%.1f%%", t.withinSentencePct * 100))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.blue)
                Text("\(t.withinSentenceCount)x")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .frame(width: 40)

            Text(String(format: "%+.1f", t.delta * 100))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(t.delta > 0 ? .orange : .blue)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Atom-Length Analysis

    @State private var expandedAtomCoOccurrenceRows: Set<String> = []
    @State private var expandedAtomLengthSections: Set<String> = Set(["atomCount", "wordCount", "wordBudget", "coOccurrence", "position", "breakProb"])

    private var atomLengthAnalysisSection: some View {
        parameterCard("Atom-Length Analysis") {
            VStack(alignment: .leading, spacing: 12) {
                Text("How sentence word count and atom composition relate. Answers: how many atoms per sentence, what word count to expect per atom count, which atoms tend to appear together, and which atom pairs signal sentence boundaries.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if vm.atomLengthAnalysis == nil {
                    Button {
                        vm.computeAtomLengthAnalysis()
                    } label: {
                        Label("Compute Atom-Length Analysis", systemImage: "chart.bar.xaxis")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                } else if let analysis = vm.atomLengthAnalysis {
                    // Summary badges
                    HStack(spacing: 16) {
                        statBadge(value: "\(analysis.totalSentences)", label: "Sentences")
                        statBadge(value: "\(analysis.totalAtoms)", label: "Atoms")
                        statBadge(value: String(format: "%.2f", Double(analysis.totalAtoms) / max(1, Double(analysis.totalSentences))), label: "Avg Atoms/Sent")
                    }

                    HStack(spacing: 8) {
                        FadeOutCopyButton(
                            text: vm.copyAtomLengthAnalysis(),
                            label: "Copy Report"
                        )
                        Button("Recompute") {
                            vm.atomLengthAnalysis = nil
                            vm.computeAtomLengthAnalysis()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    // Sub-section 1: Atom Count Distribution
                    atomLengthDisclosure("atomCount", title: "Atom Count Distribution") {
                        ForEach(analysis.atomCountDistribution) { bucket in
                            atomCountBarRow(bucket, totalSentences: analysis.totalSentences)
                        }
                    }

                    // Sub-section 2: Word Count by Atom Count
                    atomLengthDisclosure("wordCount", title: "Word Count by Atom Count") {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                Text("Atoms")
                                    .frame(width: 36, alignment: .leading)
                                Text("N")
                                    .frame(width: 30, alignment: .trailing)
                                Text("Min")
                                    .frame(width: 30, alignment: .trailing)
                                Text("Q1")
                                    .frame(width: 36, alignment: .trailing)
                                Text("Med")
                                    .frame(width: 36, alignment: .trailing)
                                Text("Q3")
                                    .frame(width: 36, alignment: .trailing)
                                Text("Max")
                                    .frame(width: 30, alignment: .trailing)
                                Text("Mean")
                                    .frame(width: 40, alignment: .trailing)
                                Text("SD")
                                    .frame(width: 36, alignment: .trailing)
                            }
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                            ForEach(analysis.wordCountByAtomCount) { b in
                                wordCountStatsRow(b)
                            }
                        }
                    }

                    // Sub-section 3: Per-Atom Word Budget
                    atomLengthDisclosure("wordBudget", title: "Per-Atom Word Budget") {
                        ForEach(analysis.perAtomWordBudget) { budget in
                            atomWordBudgetRow(budget)
                        }
                    }

                    // Sub-section 4: Atom Co-Occurrence
                    atomLengthDisclosure("coOccurrence", title: "Atom Co-Occurrence") {
                        LazyVStack(spacing: 4) {
                            ForEach(analysis.atomCoOccurrence) { row in
                                atomCoOccurrenceRowView(row)
                            }
                        }
                    }

                    // Sub-section 5: Atom Position Distribution
                    atomLengthDisclosure("position", title: "Atom Position Distribution") {
                        ForEach(analysis.atomPositionDistribution) { row in
                            atomPositionRowView(row)
                        }
                    }

                    // Sub-section 6: Sentence Break Probability
                    atomLengthDisclosure("breakProb", title: "Sentence Break Probability") {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                Text("From → To")
                                    .frame(width: 160, alignment: .leading)
                                Text("Break")
                                    .frame(width: 36, alignment: .trailing)
                                Text("Cont")
                                    .frame(width: 36, alignment: .trailing)
                                Text("P(brk)")
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                            ForEach(analysis.sentenceBreakMatrix) { row in
                                sentenceBreakRowView(row)
                            }
                        }
                    }
                }
            }
        }
    }

    private func atomLengthDisclosure<Content: View>(_ key: String, title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedAtomLengthSections.contains(key) },
                set: { newVal in
                    if newVal { expandedAtomLengthSections.insert(key) }
                    else { expandedAtomLengthSections.remove(key) }
                }
            )
        ) {
            content()
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }

    // MARK: Atom-Length Sub-view Helpers

    private func atomCountBarRow(_ bucket: StructureWorkbenchViewModel.AtomCountBucket, totalSentences: Int) -> some View {
        HStack(spacing: 6) {
            Text(bucket.atomCount == 5 ? "5+" : "\(bucket.atomCount)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 20, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 14)
                    Rectangle()
                        .fill(Color.blue.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(bucket.fraction), height: 14)
                }
                .cornerRadius(3)
            }
            .frame(height: 14)

            Text("\(bucket.sentenceCount)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .frame(width: 30, alignment: .trailing)

            Text(String(format: "%.0f%%", bucket.fraction * 100))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(String(format: "%.0fw", bucket.avgWordCount))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    private func wordCountStatsRow(_ b: StructureWorkbenchViewModel.WordCountByAtomBucket) -> some View {
        HStack(spacing: 0) {
            Text(b.atomCount == 5 ? "5+" : "\(b.atomCount)")
                .frame(width: 36, alignment: .leading)
            Text("\(b.sampleSize)")
                .frame(width: 30, alignment: .trailing)
            Text("\(b.min)")
                .frame(width: 30, alignment: .trailing)
            Text(String(format: "%.1f", b.q1))
                .frame(width: 36, alignment: .trailing)
            Text(String(format: "%.1f", b.median))
                .frame(width: 36, alignment: .trailing)
                .fontWeight(.bold)
            Text(String(format: "%.1f", b.q3))
                .frame(width: 36, alignment: .trailing)
            Text("\(b.max)")
                .frame(width: 30, alignment: .trailing)
            Text(String(format: "%.1f", b.mean))
                .frame(width: 40, alignment: .trailing)
            Text(String(format: "%.1f", b.sd))
                .frame(width: 36, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 9, design: .monospaced))
    }

    private func atomWordBudgetRow(_ budget: StructureWorkbenchViewModel.AtomWordBudget) -> some View {
        HStack(spacing: 6) {
            Text(abbreviateSignature(budget.atomType))
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(atomColor(for: budget.atomType).opacity(0.3))
                .cornerRadius(4)
                .frame(width: 70, alignment: .leading)

            Text("\(budget.totalOccurrences)x")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)

            if budget.soloSentenceCount > 0 {
                Text("solo: \(budget.soloSentenceCount)x \(String(format: "%.0fw", budget.soloAvgWordCount))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.orange)
                    .frame(width: 80, alignment: .leading)
            } else {
                Text("no solo")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 80, alignment: .leading)
            }

            Text(String(format: "%.0fw", budget.avgWordsInSentence))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 28, alignment: .trailing)

            Text(String(format: "%.1fa", budget.avgAtomsInSentence))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    private func atomCoOccurrenceRowView(_ row: StructureWorkbenchViewModel.AtomCoOccurrenceRow) -> some View {
        let isExpanded = expandedAtomCoOccurrenceRows.contains(row.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation {
                    if isExpanded { expandedAtomCoOccurrenceRows.remove(row.id) }
                    else { expandedAtomCoOccurrenceRows.insert(row.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(abbreviateSignature(row.atomType))
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(atomColor(for: row.atomType).opacity(0.3))
                        .cornerRadius(4)

                    Text("\(row.totalSentencesContaining) sents")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    ForEach(Array(row.topCoOccurring.prefix(3).enumerated()), id: \.offset) { _, co in
                        HStack(spacing: 1) {
                            Text(abbreviateSignature(co.atomType))
                                .font(.system(size: 7))
                            Text(String(format: "%.0f%%", co.conditionalProb * 100))
                                .font(.system(size: 7, weight: .bold))
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(atomColor(for: co.atomType).opacity(0.2))
                        .cornerRadius(3)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }

            if isExpanded {
                ForEach(Array(row.topCoOccurring.enumerated()), id: \.offset) { _, co in
                    HStack(spacing: 6) {
                        Text(abbreviateSignature(co.atomType))
                            .font(.system(size: 8))
                            .frame(width: 60, alignment: .leading)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(atomColor(for: co.atomType).opacity(0.2))
                            .cornerRadius(3)

                        GeometryReader { geo in
                            Rectangle()
                                .fill(atomColor(for: co.atomType).opacity(0.5))
                                .frame(width: geo.size.width * CGFloat(co.conditionalProb))
                                .cornerRadius(2)
                        }
                        .frame(height: 10)

                        Text("\(co.count)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        Text(String(format: "%.1f%%", co.conditionalProb * 100))
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    private func atomPositionRowView(_ row: StructureWorkbenchViewModel.AtomPositionRow) -> some View {
        HStack(spacing: 6) {
            Text(abbreviateSignature(row.atomType))
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(atomColor(for: row.atomType).opacity(0.3))
                .cornerRadius(4)
                .frame(width: 70, alignment: .leading)

            Text("\(row.totalOccurrences)x")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            // First/last fraction bars
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text("1st")
                        .font(.system(size: 7))
                        .foregroundColor(.green)
                        .frame(width: 16)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.green.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(row.firstPositionFraction))
                            .cornerRadius(2)
                    }
                    .frame(height: 6)
                    Text(String(format: "%.0f%%", row.firstPositionFraction * 100))
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 26, alignment: .trailing)
                }
                HStack(spacing: 2) {
                    Text("last")
                        .font(.system(size: 7))
                        .foregroundColor(.purple)
                        .frame(width: 16)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.purple.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(row.lastPositionFraction))
                            .cornerRadius(2)
                    }
                    .frame(height: 6)
                    Text(String(format: "%.0f%%", row.lastPositionFraction * 100))
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func sentenceBreakRowView(_ row: StructureWorkbenchViewModel.SentenceBreakRow) -> some View {
        let breakColor: Color = row.breakProbability > 0.6 ? .red
            : row.breakProbability > 0.3 ? .orange : .green
        return HStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(abbreviateSignature(row.fromAtom))
                    .font(.system(size: 7))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(atomColor(for: row.fromAtom).opacity(0.2))
                    .cornerRadius(2)
                Text("→")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                Text(abbreviateSignature(row.toAtom))
                    .font(.system(size: 7))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(atomColor(for: row.toAtom).opacity(0.2))
                    .cornerRadius(2)
            }
            .frame(width: 160, alignment: .leading)

            Text("\(row.breakCount)")
                .frame(width: 36, alignment: .trailing)
            Text("\(row.continueCount)")
                .frame(width: 36, alignment: .trailing)

            Text(String(format: "%.2f", row.breakProbability))
                .fontWeight(.bold)
                .foregroundColor(breakColor)
                .frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 9, design: .monospaced))
        .padding(.vertical, 1)
    }

    // MARK: - Atom Color Helper

    private func atomColor(for slotType: String) -> Color {
        AtomDisplayHelpers.color(for: slotType)
    }

    // MARK: - Shared Helpers

    private func parameterCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            content()
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

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

    private func freqBucket(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func signatureChip(_ sig: String, position: Int, total: Int) -> some View {
        let bgColor: Color
        if position == 0 { bgColor = .green.opacity(0.15) }
        else if position == total - 1 { bgColor = .red.opacity(0.15) }
        else { bgColor = .purple.opacity(0.1) }

        return Text(abbreviateSignature(sig))
            .font(.system(size: 8))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(bgColor)
            .cornerRadius(4)
    }

    private func abbreviateSignature(_ sig: String) -> String {
        // Shorten each component: geographic_location → geo_loc, visual_detail → vis_det
        let parts = sig.split(separator: "|")
        let abbreviated = parts.map { part -> String in
            let words = part.split(separator: "_")
            if words.count == 1 {
                return String(words[0].prefix(5))
            }
            return words.map { String($0.prefix(3)) }.joined(separator: "_")
        }
        return abbreviated.joined(separator: "|")
    }

    private func probabilityColor(_ prob: Double) -> Color {
        if prob >= 0.5 { return .green }
        if prob >= 0.2 { return .orange }
        return .red
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.5 { return .green }
        if confidence >= 0.25 { return .orange }
        return .red
    }

    private func coverageBadgeColor(_ count: Int) -> Color {
        if count >= 5 { return .green }
        if count >= 2 { return .orange }
        if count >= 1 { return .yellow }
        return .red
    }
}
