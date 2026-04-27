//
//  AtomExplorerView.swift
//  NewAgentBuilder
//
//  Atom-level Markov explorer — the sentence-level analog of MarkovExplorerView.
//  Select a move type (which owns the corpus), build an atom transition matrix,
//  and interactively explore atom connectivity, sequence building,
//  break probabilities, and global n-gram patterns.
//

import SwiftUI

struct AtomExplorerView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @StateObject private var vm: AtomExplorerViewModel

    @State private var showAtomDetail: AtomDetailItem?
    @State private var showProofSheet = false
    @State private var selectedNgram: NgramSelection?

    init(coordinator: MarkovScriptWriterCoordinator) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self._vm = StateObject(wrappedValue: AtomExplorerViewModel(coordinator: coordinator))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                controlsSection

                if vm.atomMatrix != nil {
                    matrixStatsSection
                }

                if vm.atomMatrix != nil {
                    sequenceBuilderSection
                }

                if vm.atomMatrix != nil {
                    transitionOverviewSection
                }

                if vm.atomMatrix != nil {
                    breakRampSection
                }

                if vm.atomMatrix != nil {
                    globalPatternsSection
                }
            }
            .padding()
        }
        .sheet(item: $showAtomDetail) { item in
            NavigationView {
                atomDetailSheet(item.atom)
                    .navigationTitle(item.atom)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showAtomDetail = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showProofSheet) {
            NavigationView {
                proofSheet
                    .navigationTitle("Corpus Proof")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showProofSheet = false }
                        }
                    }
            }
        }
        .sheet(item: $selectedNgram) { ngram in
            NavigationView {
                phraseDrillDownSheet(ngram)
                    .navigationTitle("Phrases")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { selectedNgram = nil }
                        }
                    }
            }
        }
        .task {
            if vm.dataState == .needsLoad, coordinator.donorCorpusState == .loaded {
                await vm.loadCorpusData()
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Channel selector
            if !coordinator.availableChannels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channels")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button {
                                coordinator.selectedChannelIds.removeAll()
                            } label: {
                                Text("All")
                                    .font(.caption2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(coordinator.selectedChannelIds.isEmpty ? Color.accentColor : Color.secondary.opacity(0.15))
                                    .foregroundColor(coordinator.selectedChannelIds.isEmpty ? .white : .primary)
                                    .cornerRadius(6)
                            }

                            ForEach(coordinator.availableChannels, id: \.channelId) { channel in
                                let isSelected = coordinator.selectedChannelIds.contains(channel.channelId)
                                Button {
                                    if isSelected {
                                        coordinator.selectedChannelIds.remove(channel.channelId)
                                    } else {
                                        coordinator.selectedChannelIds.insert(channel.channelId)
                                    }
                                } label: {
                                    Text(channel.name)
                                        .font(.caption2)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
            }

            // Move type picker
            if vm.dataState == .ready, !vm.availableMoveTypes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Move Type (corpus owner)")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(vm.availableMoveTypes, id: \.self) { moveType in
                                let isSelected = vm.selectedMoveType == moveType
                                Button {
                                    vm.selectMoveType(moveType)
                                } label: {
                                    Text(moveType)
                                        .font(.caption2)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
            }

            // Build / status row
            HStack {
                if case .loading = vm.dataState {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(vm.loadingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if case .error(let msg) = vm.dataState {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if case .ready = vm.dataState {
                    Text(vm.loadingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    Task { await vm.loadCorpusData() }
                } label: {
                    Label(
                        vm.dataState == .needsLoad ? "Load Corpus" : "Reload",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.dataState == .loading)
            }
        }
    }

    // MARK: - Matrix Stats

    private var matrixStatsSection: some View {
        guard let matrix = vm.atomMatrix else { return AnyView(EmptyView()) }
        let totalAtoms = matrix.atomCounts.values.reduce(0, +)

        return AnyView(
            HStack(spacing: 16) {
                statBadge(value: "\(vm.sectionsForMove.count)", label: "Sections")
                statBadge(value: "\(matrix.totalTransitionCount)", label: "Transitions")
                statBadge(value: "\(matrix.atomCounts.count)", label: "Atom Types")
                statBadge(value: "\(totalAtoms)", label: "Total Atoms")

                Spacer()

                CompactCopyButton(text: vm.buildReport())
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(10)
        )
    }

    // MARK: - Sequence Builder

    private var sequenceBuilderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Atom Sequence Builder")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if !vm.explorerPath.isEmpty {
                    Button("Clear") { vm.clearSequence() }
                        .font(.caption)
                }
            }

            // History depth control
            HStack {
                Stepper("Context: \(vm.historyDepth == 1 ? "Bigram" : "Trigram")",
                        value: $vm.historyDepth,
                        in: 1...2)
                    .font(.caption)
            }

            if vm.explorerPath.isEmpty {
                // Show openers
                Text("Tap an atom to start building a sequence:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let matrix = vm.atomMatrix {
                    let openers = matrix.topOpeners(topK: 12)
                    let totalOpeners = openers.reduce(0) { $0 + $1.count }

                    FlowLayout(spacing: 6) {
                        ForEach(openers, id: \.atom) { opener in
                            let pct = totalOpeners > 0 ? Double(opener.count) / Double(totalOpeners) * 100 : 0
                            Button {
                                vm.startSequence(with: opener.atom)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(AtomDisplayHelpers.abbreviate(opener.atom))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                    Text("\(String(format: "%.0f", pct))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AtomDisplayHelpers.color(for: opener.atom).opacity(0.2))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            } else {
                // Current path display
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(vm.explorerPath.enumerated()), id: \.offset) { index, atom in
                            Text(AtomDisplayHelpers.abbreviate(atom))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AtomDisplayHelpers.color(for: atom).opacity(0.2))
                                .cornerRadius(5)

                            if index < vm.explorerPath.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Lookup info + proof button
                HStack(spacing: 6) {
                    Text(vm.lookupType)
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)

                    // Break probability indicator
                    if let breakProb = vm.lastBreakProbability {
                        HStack(spacing: 2) {
                            Image(systemName: "scissors")
                                .font(.system(size: 9))
                            Text("P(break)=\(String(format: "%.0f", breakProb * 100))%")
                                .font(.caption2)
                        }
                        .foregroundColor(breakProb > 0.6 ? .red : breakProb > 0.3 ? .orange : .green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(4)
                    }

                    Spacer()

                    if vm.explorerPath.count >= 2 {
                        Button {
                            showProofSheet = true
                        } label: {
                            Label("Find in Corpus", systemImage: "text.magnifyingglass")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if vm.isDeadEnd {
                    // Dead end display
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dead End")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                                Text("No atom transitions exist from this point in the corpus.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.06))
                    .cornerRadius(8)
                } else {
                    // Next atoms
                    Text("Next atoms:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    let results = vm.nextAtoms(topK: 12)
                    FlowLayout(spacing: 6) {
                        ForEach(results, id: \.atom) { next in
                            Button {
                                vm.extendSequence(with: next.atom)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(AtomDisplayHelpers.abbreviate(next.atom))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                    Text("\(String(format: "%.0f", next.probability * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(probabilityBackground(next.probability))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Transition Overview

    private var transitionOverviewSection: some View {
        guard let matrix = vm.atomMatrix else { return AnyView(EmptyView()) }
        let sorted = matrix.atomsByFrequency()

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Atom Transitions")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                LazyVStack(spacing: 6) {
                    ForEach(sorted, id: \.atom) { item in
                        atomTransitionCard(atom: item.atom, count: item.count, matrix: matrix)
                    }
                }
            }
        )
    }

    private func atomTransitionCard(atom: String, count: Int, matrix: AtomTransitionMatrix) -> some View {
        Button {
            showAtomDetail = AtomDetailItem(atom: atom)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    // Atom color badge
                    Circle()
                        .fill(AtomDisplayHelpers.color(for: atom))
                        .frame(width: 8, height: 8)

                    Text(atom)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Entropy badge
                    let h = matrix.normalizedEntropy(from: atom)
                    Text("H:\(String(format: "%.2f", h))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(h > 0.7 ? .green : h > 0.4 ? .orange : .red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(3)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Top 3 successors
                let nextAtoms = matrix.topNextAtoms(after: atom, topK: 3)
                if !nextAtoms.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(nextAtoms, id: \.atom) { next in
                            HStack(spacing: 2) {
                                Text("\u{2192}")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(AtomDisplayHelpers.abbreviate(next.atom))
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                Text("\(String(format: "%.0f", next.probability * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(probabilityBackground(next.probability))
                            .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        }
    }

    // MARK: - Break Ramp Chart

    private var breakRampSection: some View {
        guard let matrix = vm.atomMatrix, !matrix.positionBreakRamp.isEmpty else {
            return AnyView(EmptyView())
        }

        let maxPos = matrix.positionBreakRamp.keys.max() ?? 0
        let maxVal = matrix.positionBreakRamp.values.max() ?? 1.0

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Sentence Break Hazard Rate")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("P(sentence ends at position N | lasted \u{2265} N)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0...maxPos, id: \.self) { pos in
                        let val = matrix.positionBreakRamp[pos] ?? 0
                        let height = maxVal > 0 ? CGFloat(val / maxVal) * 60 : 0

                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", val))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)

                            Rectangle()
                                .fill(val > 1.5 ? Color.red.opacity(0.6) : val > 0.8 ? Color.orange.opacity(0.6) : Color.green.opacity(0.6))
                                .frame(width: 20, height: max(height, 2))
                                .cornerRadius(2)

                            Text("\(pos)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }

    // MARK: - Global Patterns

    private var globalPatternsSection: some View {
        guard let matrix = vm.atomMatrix else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Global Atom Patterns")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                // Top bigrams
                let bigrams = matrix.globalAtomBigrams(topK: 20)
                if !bigrams.isEmpty {
                    Text("Top Bigrams (\(bigrams.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(bigrams, id: \.pattern) { gram in
                        ngramRow(pattern: gram.pattern, count: gram.count)
                    }
                }

                // Top trigrams
                let trigrams = matrix.globalAtomTrigrams(topK: 20)
                if !trigrams.isEmpty {
                    Text("Top Trigrams (\(trigrams.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    ForEach(trigrams, id: \.pattern) { gram in
                        ngramRow(pattern: gram.pattern, count: gram.count)
                    }
                }

                // Top 4-grams
                let fourgrams = vm.computeFourgrams(topK: 15)
                if !fourgrams.isEmpty {
                    Text("Top 4-grams (\(fourgrams.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    ForEach(fourgrams, id: \.pattern) { gram in
                        ngramRow(pattern: gram.pattern, count: gram.count)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }

    // MARK: - Atom Detail Sheet

    private func atomDetailSheet(_ atom: String) -> some View {
        guard let matrix = vm.atomMatrix else {
            return AnyView(Text("No matrix data"))
        }

        return AnyView(ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Overview
                HStack(spacing: 16) {
                    Circle()
                        .fill(AtomDisplayHelpers.color(for: atom))
                        .frame(width: 12, height: 12)

                    statBadge(value: "\(matrix.atomCounts[atom] ?? 0)", label: "Total")

                    let openerCount = Int(matrix.openerDistribution[atom] ?? 0)
                    statBadge(value: "\(openerCount)", label: "Opens")

                    statBadge(value: String(format: "%.2f", matrix.entropy(from: atom)), label: "Entropy")
                    statBadge(value: String(format: "%.2f", matrix.normalizedEntropy(from: atom)), label: "Norm H")
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)

                // Intent category
                ForEach(IntentCategory.allCases.filter { $0.atomTypes.contains(atom) }, id: \.rawValue) { category in
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                        Text("Intent: \(category.rawValue)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("— \(category.description)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Followed by (successors)
                let nextAtoms = matrix.topNextAtoms(after: atom, topK: 15)
                if !nextAtoms.isEmpty {
                    sectionHeader("Followed By")
                    ForEach(nextAtoms, id: \.atom) { next in
                        transitionRow(
                            atom: next.atom,
                            probability: next.probability,
                            count: next.count
                        )
                    }
                }

                // Preceded by (predecessors)
                let prevAtoms = matrix.topPreviousAtoms(before: atom, topK: 15)
                if !prevAtoms.isEmpty {
                    sectionHeader("Preceded By")
                    ForEach(prevAtoms, id: \.atom) { prev in
                        transitionRow(
                            atom: prev.atom,
                            probability: prev.probability,
                            count: prev.count
                        )
                    }
                }

                // Break behavior
                if let breakRow = matrix.breakProbabilities[atom], !breakRow.isEmpty {
                    sectionHeader("Break Probability (this atom \u{2192} next)")
                    let sorted = breakRow.sorted { $0.value > $1.value }.prefix(10)
                    ForEach(Array(sorted), id: \.key) { nextAtom, prob in
                        HStack {
                            Circle()
                                .fill(AtomDisplayHelpers.color(for: nextAtom))
                                .frame(width: 6, height: 6)
                            Text("\u{2192} \(AtomDisplayHelpers.abbreviate(nextAtom))")
                                .font(.caption)
                            Spacer()
                            Text("\(String(format: "%.0f", prob * 100))%")
                                .font(.caption)
                                .foregroundColor(prob > 0.6 ? .red : prob > 0.3 ? .orange : .green)
                        }
                    }
                }

                // Trigram contexts involving this atom
                let trigramContexts = findTrigramContexts(for: atom, in: matrix)
                if !trigramContexts.isEmpty {
                    sectionHeader("Trigram Contexts")
                    ForEach(trigramContexts, id: \.pattern) { ctx in
                        HStack {
                            Text(ctx.pattern)
                                .font(.caption2)
                            Spacer()
                            Text("\(ctx.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        })
    }

    // MARK: - Proof Sheet

    private var proofSheet: some View {
        let pattern = vm.explorerPath
        let matches = vm.findSentencesMatchingPattern(pattern)
        let patternLabel = pattern.map { AtomDisplayHelpers.abbreviate($0) }.joined(separator: " \u{2192} ")

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pattern (\(pattern.count) atoms)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(patternLabel)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(8)

                Text("\(matches.count) sentence\(matches.count == 1 ? "" : "s") found")
                    .font(.caption)
                    .fontWeight(.semibold)

                if matches.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No sentences in the corpus contain this exact atom sequence.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { match in
                            proofMatchRow(match: match, patternLength: pattern.count)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func proofMatchRow(match: AtomExplorerViewModel.SentenceMatch, patternLength: Int) -> some View {
        let matchEnd = match.matchStartIndex + patternLength

        return VStack(alignment: .leading, spacing: 6) {
            // Sentence text
            Text(match.sentenceText)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(3)

            // Match position
            Text("Match at position \(match.matchStartIndex + 1) of \(match.fullSlotSequence.count) slots")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Slot ribbon with match highlighted
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(match.fullSlotSequence.enumerated()), id: \.offset) { idx, slot in
                        let isInMatch = idx >= match.matchStartIndex && idx < matchEnd
                        Text(AtomDisplayHelpers.abbreviate(slot))
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(isInMatch ? Color.orange.opacity(0.3) : AtomDisplayHelpers.color(for: slot).opacity(0.1))
                            .foregroundColor(isInMatch ? .primary : .secondary)
                            .fontWeight(isInMatch ? .bold : .regular)
                            .cornerRadius(3)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }

    // MARK: - N-gram Phrase Drill-Down

    /// Tappable row for bigram/trigram/4-gram that opens the phrase sheet
    private func ngramRow(pattern: String, count: Int) -> some View {
        Button {
            let atoms = pattern.components(separatedBy: " \u{2192} ").map { $0.trimmingCharacters(in: .whitespaces) }
            selectedNgram = NgramSelection(atoms: atoms, patternLabel: pattern)
        } label: {
            HStack {
                Text(pattern)
                    .font(.caption2)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }

    /// Sheet showing all real phrase text from corpus that matches an n-gram pattern
    private func phraseDrillDownSheet(_ ngram: NgramSelection) -> some View {
        let matches = vm.findPhrasesForPattern(ngram.atoms)
        let slotCount = vm.countSlotSequenceMatches(ngram.atoms)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Pattern header
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ngram.atoms.count)-gram Pattern")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    // Atom pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(ngram.atoms.enumerated()), id: \.offset) { idx, atom in
                                Text(atom)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AtomDisplayHelpers.color(for: atom).opacity(0.2))
                                    .cornerRadius(5)

                                if idx < ngram.atoms.count - 1 {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(8)

                // Count + Copy All
                HStack {
                    if slotCount == matches.count {
                        Text("\(matches.count) phrase\(matches.count == 1 ? "" : "s") found")
                            .font(.caption)
                            .fontWeight(.semibold)
                    } else {
                        Text("\(slotCount) occurrences (\(matches.count) have phrase text)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    if !matches.isEmpty {
                        CopyAllButton(
                            items: [vm.copyablePhrasesReport(ngram.atoms)],
                            separator: "",
                            label: "Copy All"
                        )
                    }
                }

                if matches.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.badge.xmark")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No sentences with phrase data match this pattern.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { match in
                            phraseMatchRow(match: match, atoms: ngram.atoms)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func phraseMatchRow(match: AtomExplorerViewModel.PhraseMatch, atoms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Combined phrase (bold, copyable)
            HStack {
                Text(match.combinedPhrase)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                CompactCopyButton(text: match.combinedPhrase)
            }

            // Per-slot breakdown with color badges
            HStack(spacing: 4) {
                ForEach(Array(match.phraseTexts.enumerated()), id: \.offset) { idx, text in
                    let atom = idx < atoms.count ? atoms[idx] : "other"
                    Text(text)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AtomDisplayHelpers.color(for: atom).opacity(0.15))
                        .cornerRadius(4)
                }
            }

            // Full sentence context
            Text(match.sentenceText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }

    // MARK: - Helpers

    private func findTrigramContexts(for atom: String, in matrix: AtomTransitionMatrix) -> [(pattern: String, count: Int)] {
        var results: [String: Int] = [:]
        for (key, row) in matrix.trigramTransitions {
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { continue }
            let keyAtoms = [String(parts[0]), String(parts[1])]

            if keyAtoms.contains(atom) {
                for (next, count) in row {
                    let pattern = "\(parts[0]) \u{2192} \(parts[1]) \u{2192} \(next)"
                    results[pattern, default: 0] += Int(count)
                }
            } else {
                for (next, count) in row where next == atom {
                    let pattern = "\(parts[0]) \u{2192} \(parts[1]) \u{2192} \(next)"
                    results[pattern, default: 0] += Int(count)
                }
            }
        }
        return results
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { ($0.key, $0.value) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.accentColor)
            .padding(.top, 4)
    }

    private func transitionRow(atom: String, probability: Double, count: Int) -> some View {
        HStack {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 20)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(probabilityColor(probability))
                        .frame(width: geo.size.width * probability, height: 20)
                        .cornerRadius(4)
                }
            }
            .frame(height: 20)
            .frame(maxWidth: 100)

            Circle()
                .fill(AtomDisplayHelpers.color(for: atom))
                .frame(width: 6, height: 6)

            Text(atom)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(String(format: "%.1f", probability * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .trailing)

            Text("(\(count))")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
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
    }

    private func probabilityBackground(_ prob: Double) -> Color {
        if prob >= 0.3 { return Color.green.opacity(0.15) }
        if prob >= 0.15 { return Color.yellow.opacity(0.15) }
        return Color.secondary.opacity(0.1)
    }

    private func probabilityColor(_ prob: Double) -> Color {
        if prob >= 0.3 { return .green.opacity(0.6) }
        if prob >= 0.15 { return .orange.opacity(0.6) }
        return .secondary.opacity(0.4)
    }
}

// MARK: - Atom Detail Item (Identifiable wrapper for sheet)

struct AtomDetailItem: Identifiable {
    let id: String
    let atom: String

    init(atom: String) {
        self.id = atom
        self.atom = atom
    }
}

// MARK: - N-gram Selection (Identifiable wrapper for phrase drill-down sheet)

struct NgramSelection: Identifiable {
    let id: String
    let atoms: [String]
    let patternLabel: String

    init(atoms: [String], patternLabel: String) {
        self.id = patternLabel
        self.atoms = atoms
        self.patternLabel = patternLabel
    }
}
