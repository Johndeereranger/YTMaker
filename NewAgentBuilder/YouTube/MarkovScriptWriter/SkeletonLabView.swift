//
//  SkeletonLabView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/24/26.
//
//  Full view for the Skeleton Lab tab.
//  Config section, run controls, and ALL results visible
//  simultaneously in a vertical scroll with cards, disclosure
//  groups, and copy buttons at every level.
//

import SwiftUI

struct SkeletonLabView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @StateObject private var vm: SkeletonLabViewModel

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
        _vm = StateObject(wrappedValue: SkeletonLabViewModel(coordinator: coordinator))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                loadSection
                if vm.dataState == .ready {
                    configSection
                    if vm.isRunning { progressSection }
                    if !vm.results.isEmpty { masterCopyButtons }
                    resultsSection
                }
            }
            .padding()
        }
        .task {
            if vm.dataState == .needsLoad, coordinator.donorCorpusState == .loaded {
                await vm.loadCorpusData()
            }
        }
    }

    // MARK: - Load Section

    private var loadSection: some View {
        Group {
            switch vm.dataState {
            case .needsLoad:
                VStack(spacing: 12) {
                    Image(systemName: "flask")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Skeleton Lab")
                        .font(.headline)
                    Text("Load corpus data to begin generating and comparing atom-level skeletons.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Load Corpus Data") {
                        Task { await vm.loadCorpusData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            case .loading:
                VStack(spacing: 8) {
                    ProgressView()
                    Text(vm.loadingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            case .error(let msg):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await vm.loadCorpusData() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)

            case .ready:
                EmptyView()
            }
        }
    }

    // MARK: - Config Section

    private var configSection: some View {
        parameterCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configuration")
                    .font(.headline)

                // Move type picker
                HStack {
                    Text("Move Type").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Picker("Move Type", selection: Binding(
                        get: { vm.selectedMoveType ?? "" },
                        set: { vm.selectMoveType($0) }
                    )) {
                        ForEach(vm.availableMoveTypes, id: \.self) { move in
                            Text(move).tag(move)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Content input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Content / Topic").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $vm.config.contentInput)
                        .font(.caption)
                        .frame(height: 60)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                }

                // Target sentence count
                Stepper(
                    "Target Sentences: \(vm.config.targetSentenceCount)",
                    value: $vm.config.targetSentenceCount,
                    in: 2...20
                )
                .font(.caption)

                // Path toggles
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enabled Paths").font(.caption).fontWeight(.semibold)
                    ForEach(SkeletonPath.allCases) { path in
                        HStack(spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { vm.config.enabledPaths.contains(path) },
                                set: { enabled in
                                    if enabled { vm.config.enabledPaths.insert(path) }
                                    else { vm.config.enabledPaths.remove(path) }
                                }
                            )) {
                                HStack(spacing: 6) {
                                    Text(path.shortName)
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(path.badgeColor)
                                        .cornerRadius(4)
                                    Text(path.displayName)
                                        .font(.caption)
                                    if path.requiresLLM {
                                        Text("LLM")
                                            .font(.system(size: 8))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.2))
                                            .cornerRadius(3)
                                    }
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }
                }

                // Advanced parameters
                DisclosureGroup("Advanced Parameters") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Entropy Threshold (P2)")
                                .font(.caption2)
                            Spacer()
                            Text(String(format: "%.2f", vm.config.entropyThreshold))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Slider(value: $vm.config.entropyThreshold, in: 0.3...1.0, step: 0.05)

                        Stepper(
                            "Cluster Count (P5): \(vm.config.clusterCount)",
                            value: $vm.config.clusterCount,
                            in: 2...8
                        )
                        .font(.caption2)

                        HStack {
                            Text("Collapse Temperature (P3)")
                                .font(.caption2)
                            Spacer()
                            Text(String(format: "%.1f", vm.config.collapseTemperature))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Slider(value: $vm.config.collapseTemperature, in: 0.3...1.5, step: 0.1)

                        HStack {
                            Text("Seed").font(.caption2)
                            Spacer()
                            TextField("Seed", value: $vm.config.seed, format: .number)
                                .font(.caption2)
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .font(.caption)

                // Run buttons
                HStack(spacing: 12) {
                    Button {
                        Task { await vm.runAll() }
                    } label: {
                        Label("Run All Enabled", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isRunning || vm.selectedMoveType == nil)

                    Text("\(vm.sectionsForMove.count) sections")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let matrix = vm.atomMatrix {
                        Text("\(matrix.totalTransitionCount) transitions")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        parameterCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView()
                    Text(vm.progressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                FlowLayout(spacing: 6) {
                    ForEach(SkeletonPath.executionOrder.filter { vm.config.enabledPaths.contains($0) }) { path in
                        let result = vm.results.first { $0.path == path }
                        let status = result?.status ?? .pending
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(status))
                                .frame(width: 8, height: 8)
                            Text(path.shortName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(status).opacity(0.15))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    // MARK: - Master Copy Buttons

    private var masterCopyButtons: some View {
        HStack(spacing: 12) {
            CopyAllButton(
                items: [vm.copyAllSkeletons()],
                label: "Copy All Skeletons"
            )
            CopyAllButton(
                items: [vm.copyAllWithDebug()],
                label: "Copy All + Debug"
            )
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(vm.results) { result in
                skeletonResultCard(result)
            }
        }
    }

    // MARK: - Skeleton Result Card

    private func skeletonResultCard(_ result: SkeletonResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(result.path.shortName)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(result.path.badgeColor)
                    .cornerRadius(6)

                Text(result.path.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                statusBadge(result.status)
                CompactCopyButton(text: vm.copyResult(result))

                // Run S5 / S6 / S7 prose generation from this skeleton
                if result.status == .completed {
                    let anyProseRunning = vm.s5RunningForId != nil || vm.s6RunningForId != nil || vm.s7RunningForId != nil || vm.isRunning

                    Button {
                        Task { await vm.runS5(for: result) }
                    } label: {
                        if vm.s5RunningForId == result.id {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("S5", systemImage: "text.badge.plus")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                    .disabled(anyProseRunning)

                    Button {
                        Task { await vm.runS6(for: result) }
                    } label: {
                        if vm.s6RunningForId == result.id {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("S6", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(anyProseRunning)

                    Button {
                        Task { await vm.runS7(for: result) }
                    } label: {
                        if vm.s7RunningForId == result.id {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("S7", systemImage: "text.book.closed")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                    .disabled(anyProseRunning)
                }

                Button {
                    Task { await vm.runPath(result.path) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .disabled(vm.isRunning)
            }

            // Atom ribbon (always visible)
            if !result.atoms.isEmpty {
                atomRibbon(result)
            }

            // Stats row
            if result.status == .completed {
                HStack(spacing: 10) {
                    telemetryPill("\(result.atomCount) atoms")
                    telemetryPill("\(result.sentenceCount) sent")
                    telemetryPill("\(result.durationMs)ms")
                    if result.llmCallCount > 0 {
                        telemetryPill("\(result.llmCallCount) LLM")
                        telemetryPill(String(format: "$%.4f", result.estimatedCost))
                    }
                }
            }

            // Failed message
            if result.status == .failed, let error = result.intermediateOutputs["error"] {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Sentence Breakdown
            if result.status == .completed, !result.atoms.isEmpty {
                DisclosureGroup("Sentence Breakdown") {
                    ForEach(Array(result.sentences.enumerated()), id: \.offset) { idx, sentence in
                        HStack(spacing: 6) {
                            Text("S\(idx + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .frame(width: 24)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 3) {
                                    ForEach(Array(sentence.enumerated()), id: \.offset) { aIdx, atom in
                                        Text(abbreviateAtom(atom))
                                            .font(.system(size: 9))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(atomColor(for: atom).opacity(0.25))
                                            .cornerRadius(3)
                                    }
                                }
                            }

                            Spacer()
                            CompactCopyButton(text: sentence.joined(separator: " -> "))
                        }
                    }
                }
                .font(.caption)
            }

            // Intermediate Outputs
            if !result.intermediateOutputs.isEmpty {
                DisclosureGroup("Intermediate Outputs") {
                    ForEach(result.intermediateOutputs.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(key).font(.caption).fontWeight(.semibold)
                                Spacer()
                                CompactCopyButton(text: value)
                            }
                            Text(value)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(10)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .font(.caption)
            }

            // Transition Quality
            if result.status == .completed, let matrix = vm.atomMatrix {
                transitionQualityDisclosure(result: result, matrix: matrix)
            }

            // Debug: Prompts & Responses
            if !result.llmCalls.isEmpty {
                DisclosureGroup("Debug: Prompts & Responses") {
                    ForEach(result.llmCalls) { call in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Call \(call.callIndex + 1): \(call.callLabel)")
                                .font(.caption)
                                .fontWeight(.semibold)

                            Text("In: \(call.promptTokens) | Out: \(call.completionTokens) | \(call.durationMs)ms")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            DisclosureGroup("System Prompt") {
                                HStack {
                                    Spacer()
                                    CompactCopyButton(text: call.systemPrompt)
                                }
                                Text(call.systemPrompt)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption2)

                            DisclosureGroup("User Prompt") {
                                HStack {
                                    Spacer()
                                    CompactCopyButton(text: call.userPrompt)
                                }
                                Text(call.userPrompt)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption2)

                            DisclosureGroup("Raw Response") {
                                HStack {
                                    Spacer()
                                    CompactCopyButton(text: call.rawResponse)
                                }
                                Text(call.rawResponse)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption2)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .font(.caption)
            }

            // S5/S6 Progress Status Bar (visible during generation)
            proseProgressBar(for: result)

            // S5 Prose Output
            if let s5 = result.s5ProseResult {
                s5ProseSection(s5)
            }

            // S6 Adaptive Prose Output
            if let s6 = result.s6ProseResult {
                s6ProseSection(s6)
            }

            // S7 Phrase-Library Prose Output
            if let s7 = result.s7ProseResult {
                s7ProseSection(s7)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - S5/S6/S7 Progress Status Bar

    private func proseProgressBar(for result: SkeletonResult) -> some View {
        Group {
            if let progress = vm.proseProgress,
               (vm.s5RunningForId == result.id || vm.s6RunningForId == result.id || vm.s7RunningForId == result.id) {

                let isS5 = vm.s5RunningForId == result.id
                let isS7 = vm.s7RunningForId == result.id
                let label = isS5 ? "S5 Progress" : isS7 ? "S7 Progress" : "S6 Progress"
                let icon = isS5 ? "text.badge.plus" : isS7 ? "text.book.closed" : "arrow.triangle.2.circlepath"
                let tintColor: Color = isS5 ? .indigo : isS7 ? .teal : .purple

                VStack(alignment: .leading, spacing: 6) {
                    Divider()

                    // Header row
                    HStack {
                        Image(systemName: icon)
                            .foregroundColor(tintColor)
                        Text(label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(tintColor)
                        Spacer()
                        Text("\(progress.completedSentences)/\(progress.totalSentences) calls")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Progress bar
                    ProgressView(value: Double(progress.completedSentences),
                               total: max(Double(progress.totalSentences), 1))
                        .tint(tintColor)

                    // Telemetry pills
                    HStack(spacing: 8) {
                        telemetryPill("\(progress.totalPromptTokens + progress.totalCompletionTokens) tok")
                        telemetryPill(String(format: "$%.4f",
                            Double(progress.totalPromptTokens) * 3.0 / 1_000_000 +
                            Double(progress.totalCompletionTokens) * 15.0 / 1_000_000))
                        telemetryPill("\(String(format: "%.1f", Double(progress.elapsedMs) / 1000.0))s")
                        if progress.replanCount > 0 {
                            telemetryPill("\(progress.replanCount) replans")
                        }
                        if let match = progress.lastSignatureMatch {
                            telemetryPill(match ? "Last: MATCH" : "Last: MISS")
                        }
                    }

                    // Phase text
                    Text(progress.currentPhase)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - S5 Prose Output Section

    private func s5ProseSection(_ s5: SkeletonS5Runner.S5ProseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Header
            HStack {
                Image(systemName: "text.badge.checkmark")
                    .foregroundColor(.indigo)
                Text("S5 Prose Output")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.indigo)
                Spacer()
                CompactCopyButton(text: SkeletonS5Runner.formatForCopy(s5))
            }

            // Telemetry row
            HStack(spacing: 10) {
                telemetryPill("Sig Hit: \(String(format: "%.0f%%", s5.signatureHitRate * 100))")
                telemetryPill("\(s5.totalPromptTokens + s5.totalCompletionTokens) tok")
                telemetryPill(String(format: "$%.4f", s5.totalCost))
                telemetryPill("\(s5.durationMs)ms")
            }

            // Full generated text
            Text(s5.finalText)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.05))
                .cornerRadius(8)

            // Per-sentence breakdown
            DisclosureGroup("Per-Sentence Validation") {
                ForEach(s5.sentences) { sentence in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("S\(sentence.index + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .frame(width: 24)

                            Text(sentence.signatureMatch ? "MATCH" : "MISS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(sentence.signatureMatch ? Color.green : Color.red)
                                .cornerRadius(4)

                            Text(sentence.targetSignature)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)

                            if !sentence.signatureMatch {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.red)
                                Text(sentence.actualSignature)
                                    .font(.system(size: 9))
                                    .foregroundColor(.red)
                            }

                            Spacer()
                            Text("\(sentence.promptTokens)+\(sentence.completionTokens)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                        Text(sentence.generatedText)
                            .font(.caption2)
                            .foregroundColor(.primary)

                        if !sentence.donorReference.isEmpty {
                            Text("Donor: \(sentence.donorReference)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .font(.caption)

            // Expandable prompts per sentence
            DisclosureGroup("S5 Debug: Prompts & Responses") {
                ForEach(s5.sentences) { sentence in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sentence \(sentence.index + 1)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            CompactCopyButton(text: "SYSTEM:\n\(sentence.systemPrompt)\n\nUSER:\n\(sentence.userPrompt)\n\nRESPONSE:\n\(sentence.rawResponse)")
                        }

                        DisclosureGroup("System Prompt") {
                            Text(sentence.systemPrompt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)

                        DisclosureGroup("User Prompt") {
                            Text(sentence.userPrompt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)

                        DisclosureGroup("Raw Response") {
                            Text(sentence.rawResponse)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .font(.caption)

            // Copy with full prompts
            HStack(spacing: 12) {
                CompactCopyButton(text: SkeletonS5Runner.formatForCopyWithPrompts(s5))
            }
        }
    }

    // MARK: - S6 Adaptive Prose Output Section

    private func s6ProseSection(_ s6: SkeletonS6Runner.S6ProseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.purple)
                Text("S6 Adaptive Prose Output")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                Spacer()
                CompactCopyButton(text: SkeletonS6Runner.formatForCopy(s6))
            }

            // Telemetry row
            HStack(spacing: 10) {
                telemetryPill("Sig Hit: \(String(format: "%.0f%%", s6.signatureHitRate * 100))")
                telemetryPill("Replans: \(s6.replanCount)")
                telemetryPill("\(s6.totalPromptTokens + s6.totalCompletionTokens) tok")
                telemetryPill(String(format: "$%.4f", s6.totalCost))
                telemetryPill("\(s6.durationMs)ms")
            }

            // Original vs final stats
            HStack(spacing: 10) {
                telemetryPill("Orig: \(s6.originalAtomCount)a/\(s6.originalSentenceCount)s")
                telemetryPill("Final: \(s6.finalAtomCount)a/\(s6.finalSentenceCount)s")
            }

            // Full generated text
            Text(s6.finalText)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.05))
                .cornerRadius(8)

            // Per-sentence breakdown with replan tags
            DisclosureGroup("Per-Sentence Validation") {
                ForEach(s6.sentences) { sentence in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("S\(sentence.index + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .frame(width: 24)

                            Text(sentence.signatureMatch ? "MATCH" : "MISS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(sentence.signatureMatch ? Color.green : Color.red)
                                .cornerRadius(4)

                            if sentence.wasReplanned {
                                Text("REPLANNED")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.purple)
                                    .cornerRadius(4)
                            }

                            Text(sentence.targetSignature)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)

                            if !sentence.signatureMatch {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.red)
                                Text(sentence.actualSignature)
                                    .font(.system(size: 9))
                                    .foregroundColor(.red)
                            }

                            Spacer()
                            Text("\(sentence.promptTokens)+\(sentence.completionTokens)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                        Text(sentence.generatedText)
                            .font(.caption2)
                            .foregroundColor(.primary)

                        if !sentence.donorReference.isEmpty {
                            Text("Donor: \(sentence.donorReference)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .font(.caption)

            // Replan events detail
            if !s6.replanEvents.isEmpty {
                DisclosureGroup("Replan Events (\(s6.replanEvents.count))") {
                    ForEach(Array(s6.replanEvents.enumerated()), id: \.offset) { idx, event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Replan #\(idx + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.purple)
                                Text("after sentence \(event.afterSentenceIndex + 1)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                CompactCopyButton(text: event.walkTrace)
                            }

                            Text(event.triggerReason)
                                .font(.caption2)
                                .foregroundColor(.orange)

                            HStack(spacing: 4) {
                                Text("Landing:")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(event.actualLastAtom)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(atomColor(for: event.actualLastAtom).opacity(0.25))
                                    .cornerRadius(3)
                                if let prev = event.actualPrevAtom {
                                    Text("prev: \(prev)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Original vs re-walked atoms ribbon
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Original remaining:")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 2) {
                                        ForEach(Array(event.originalRemainingAtoms.enumerated()), id: \.offset) { _, atom in
                                            Text(abbreviateAtom(atom))
                                                .font(.system(size: 8))
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 1)
                                                .background(atomColor(for: atom).opacity(0.2))
                                                .cornerRadius(3)
                                        }
                                    }
                                }

                                Text("Re-walked:")
                                    .font(.system(size: 9))
                                    .foregroundColor(.purple)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 2) {
                                        ForEach(Array(event.rewalkedAtoms.enumerated()), id: \.offset) { _, atom in
                                            Text(abbreviateAtom(atom))
                                                .font(.system(size: 8))
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 1)
                                                .background(atomColor(for: atom).opacity(0.3))
                                                .cornerRadius(3)
                                        }
                                    }
                                }
                            }

                            DisclosureGroup("Walk Trace") {
                                Text(event.walkTrace)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption2)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .font(.caption)
            }

            // Expandable prompts per sentence
            DisclosureGroup("S6 Debug: Prompts & Responses") {
                ForEach(s6.sentences) { sentence in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sentence \(sentence.index + 1)\(sentence.wasReplanned ? " [REPLANNED]" : "")")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            CompactCopyButton(text: "SYSTEM:\n\(sentence.systemPrompt)\n\nUSER:\n\(sentence.userPrompt)\n\nRESPONSE:\n\(sentence.rawResponse)")
                        }

                        DisclosureGroup("System Prompt") {
                            Text(sentence.systemPrompt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)

                        DisclosureGroup("User Prompt") {
                            Text(sentence.userPrompt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)

                        DisclosureGroup("Raw Response") {
                            Text(sentence.rawResponse)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .font(.caption)

            // Copy with full prompts
            HStack(spacing: 12) {
                CompactCopyButton(text: SkeletonS6Runner.formatForCopyWithPrompts(s6))
            }
        }
    }

    // MARK: - S7 Phrase-Library Prose Output Section

    private func s7ProseSection(_ s7: SkeletonS7Runner.S7ProseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Header
            HStack {
                Image(systemName: "text.book.closed")
                    .foregroundColor(.teal)
                Text("S7 Phrase-Library Prose Output")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.teal)
                Spacer()
                CompactCopyButton(text: SkeletonS7Runner.formatForCopy(s7))
            }

            // Telemetry row
            HStack(spacing: 10) {
                telemetryPill("Sig Hit: \(String(format: "%.0f%%", s7.signatureHitRate * 100))")
                telemetryPill("\(s7.totalPromptTokens + s7.totalCompletionTokens) tok")
                telemetryPill(String(format: "$%.4f", s7.totalCost))
                telemetryPill("\(s7.durationMs)ms")
            }

            // Full generated text
            Text(s7.finalText)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.teal.opacity(0.05))
                .cornerRadius(8)

            // Per-sentence breakdown
            DisclosureGroup("Per-Sentence Validation") {
                ForEach(s7.sentences) { sentence in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("S\(sentence.index + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .frame(width: 24)

                            Text(sentence.signatureMatch ? "MATCH" : "MISS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(sentence.signatureMatch ? Color.green : Color.red)
                                .cornerRadius(4)

                            Text(sentence.targetSignature)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)

                            if !sentence.signatureMatch {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.red)
                                Text(sentence.actualSignature)
                                    .font(.system(size: 9))
                                    .foregroundColor(.red)
                            }

                            Spacer()
                            Text("\(sentence.promptTokens)+\(sentence.completionTokens)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                        Text(sentence.generatedText)
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .font(.caption)

            // Phrase Library Debug per sentence
            DisclosureGroup("S7 Debug: Phrase Libraries Sent") {
                ForEach(s7.sentences) { sentence in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sentence \(sentence.index + 1)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            CompactCopyButton(text: sentence.phraseLibrarySummary)
                        }

                        Text(sentence.phraseLibrarySummary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .font(.caption)

            // Expandable prompts per sentence
            DisclosureGroup("S7 Debug: Prompts & Responses") {
                ForEach(s7.sentences) { sentence in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sentence \(sentence.index + 1)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            CompactCopyButton(text: "SYSTEM:\n\(sentence.systemPrompt)\n\nUSER:\n\(sentence.userPrompt)\n\nRESPONSE:\n\(sentence.rawResponse)")
                        }

                        DisclosureGroup("System Prompt") {
                            Text(sentence.systemPrompt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)

                        DisclosureGroup("User Prompt") {
                            Text(sentence.userPrompt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)

                        DisclosureGroup("Raw Response") {
                            Text(sentence.rawResponse)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .font(.caption)

            // Copy with full prompts
            HStack(spacing: 12) {
                CompactCopyButton(text: SkeletonS7Runner.formatForCopyWithPrompts(s7))
            }
        }
    }

    // MARK: - Atom Ribbon

    private func atomRibbon(_ result: SkeletonResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(result.atoms.enumerated()), id: \.offset) { idx, atom in
                    if result.sentenceBreaks.contains(idx) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.3))
                            .frame(width: 2, height: 22)
                    }
                    Text(abbreviateAtom(atom))
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(atomColor(for: atom).opacity(0.3))
                        .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - Transition Quality Disclosure

    private func transitionQualityDisclosure(result: SkeletonResult, matrix: AtomTransitionMatrix) -> some View {
        DisclosureGroup("Transition Quality") {
            let quality = result.transitionQuality(matrix: matrix)
            ForEach(Array(quality.enumerated()), id: \.offset) { idx, pair in
                HStack(spacing: 6) {
                    Text(abbreviateAtom(pair.from))
                        .font(.system(size: 9))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(atomColor(for: pair.from).opacity(0.2))
                        .cornerRadius(3)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(abbreviateAtom(pair.to))
                        .font(.system(size: 9))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(atomColor(for: pair.to).opacity(0.2))
                        .cornerRadius(3)
                    Text(String(format: "%.1f%%", pair.probability * 100))
                        .font(.caption2)
                        .foregroundColor(transitionColor(pair.probability))
                    if pair.isCrossBoundary {
                        Text("BRK")
                            .font(.system(size: 8))
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
            }
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func parameterCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }

    private func telemetryPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
    }

    private func statusBadge(_ status: SkeletonRunStatus) -> some View {
        Image(systemName: statusIcon(status))
            .font(.caption)
            .foregroundColor(statusColor(status))
    }

    private func statusIcon(_ status: SkeletonRunStatus) -> String {
        switch status {
        case .pending:   return "clock"
        case .running:   return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: SkeletonRunStatus) -> Color {
        switch status {
        case .pending:   return .gray
        case .running:   return .blue
        case .completed: return .green
        case .failed:    return .red
        }
    }

    private func transitionColor(_ probability: Double) -> Color {
        if probability >= 0.1 { return .green }
        if probability >= 0.03 { return .orange }
        return .red
    }

    private func abbreviateAtom(_ atom: String) -> String {
        AtomDisplayHelpers.abbreviate(atom)
    }

    private func atomColor(for slotType: String) -> Color {
        AtomDisplayHelpers.color(for: slotType)
    }
}
