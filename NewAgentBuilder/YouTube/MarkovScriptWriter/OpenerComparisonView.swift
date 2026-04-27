//
//  OpenerComparisonView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//
//  UI for running all 8 opener methods side-by-side,
//  comparing outputs, toggling models, and persisting results.
//

import SwiftUI

struct OpenerComparisonView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @StateObject private var viewModel: OpenerComparisonViewModel

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: OpenerComparisonViewModel(coordinator: coordinator))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: - Prerequisites
                if let message = viewModel.prerequisiteMessage {
                    prerequisiteWarning(message)
                } else {
                    configSection
                    progressSection
                    resultsSection
                    fidelitySection
                    historySection
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.loadDependencies()
        }
    }

    // MARK: - Prerequisite Warning

    private func prerequisiteWarning(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 40)
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Prerequisites Required")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Config Section

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comparison Configuration")
                .font(.headline)

            HStack(spacing: 16) {
                // Model picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model").font(.caption).foregroundColor(.secondary)
                    Picker("Model", selection: $viewModel.selectedModel) {
                        ForEach(claudeModels, id: \.self) { model in
                            Text(modelDisplayName(model)).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }

                // Strategy picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strategy").font(.caption).foregroundColor(.secondary)
                    Picker("Strategy", selection: $viewModel.selectedStrategyId) {
                        if let match = viewModel.matchResult {
                            ForEach(match.strategies, id: \.strategyId) { strat in
                                Text("\(strat.strategyId): \(strat.strategyName)").tag(strat.strategyId)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                }

                // Move type picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Move Type").font(.caption).foregroundColor(.secondary)
                    Picker("Move Type", selection: $viewModel.selectedMoveType) {
                        ForEach(RhetoricalMoveType.allCases, id: \.self) { move in
                            Text(move.displayName).tag(move)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }
            }

            // Method toggles
            VStack(alignment: .leading, spacing: 6) {
                Text("Methods").font(.caption).foregroundColor(.secondary)
                methodToggles
            }

            // Run button
            HStack {
                Button {
                    Task { await viewModel.startRun() }
                } label: {
                    HStack {
                        if viewModel.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text(viewModel.isRunning ? "Running..." : "Run Comparison")
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canRun)

                if viewModel.currentRun != nil {
                    CopyAllButton(
                        items: [viewModel.copyAllOutput()],
                        label: "Copy All Outputs"
                    )
                    CopyAllButton(
                        items: [viewModel.copyAllWithMethodology()],
                        label: "Copy with Prompts"
                    )
                    CopyAllButton(
                        items: [viewModel.copyAllWithMethodologyShort()],
                        label: "Copy Short"
                    )
                    CopyAllButton(
                        items: [viewModel.copyPromptsOnly()],
                        label: "Copy Prompts"
                    )
                }
            }

            if !viewModel.progressMessage.isEmpty {
                Text(viewModel.progressMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Method Toggles

    private var methodToggles: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Legacy Methods (M1-M11)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Legacy Methods (M1-M11)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        let legacyMethods = OpenerMethod.allCases.filter { !$0.isStructured }
                        let allEnabled = legacyMethods.allSatisfy { viewModel.enabledMethods.contains($0) }
                        if allEnabled {
                            for m in legacyMethods { viewModel.enabledMethods.remove(m) }
                        } else {
                            for m in legacyMethods { viewModel.enabledMethods.insert(m) }
                        }
                    } label: {
                        Text("Toggle All")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 6) {
                    ForEach(OpenerMethod.allCases.filter { !$0.isStructured }) { method in
                        methodToggleRow(method)
                    }
                }
            }

            Divider()

            // Structured Methods (S1-S4)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Structured Methods (S1-S4)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.indigo)
                    Spacer()
                    Button {
                        let sMethods = OpenerMethod.allCases.filter(\.isStructured)
                        let allEnabled = sMethods.allSatisfy { viewModel.enabledMethods.contains($0) }
                        if allEnabled {
                            for m in sMethods { viewModel.enabledMethods.remove(m) }
                        } else {
                            for m in sMethods { viewModel.enabledMethods.insert(m) }
                        }
                    } label: {
                        Text("Toggle All")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 6) {
                    ForEach(OpenerMethod.allCases.filter(\.isStructured)) { method in
                        methodToggleRow(method, accentColor: .indigo)
                    }
                }

                // Structured input status
                if viewModel.hasStructuredMethods {
                    structuredInputStatus
                    if viewModel.structuredBundle != nil {
                        fingerprintDebugPanel
                    }
                }
            }
        }
    }

    private var structuredInputStatus: some View {
        HStack(spacing: 6) {
            if viewModel.isLoadingStructuredInputs {
                ProgressView().controlSize(.small)
                Text("Loading structured inputs...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let bundle = viewModel.structuredBundle {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text(bundle.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let error = viewModel.structuredInputError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await viewModel.loadStructuredInputs() }
            } label: {
                Text("Load")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoadingStructuredInputs)
        }
        .padding(.top, 4)
    }

    // MARK: - Fingerprint Debug Panel

    @State private var showFingerprintDebug = false
    @State private var expandedFingerprints: Set<FingerprintPromptType> = []

    private var fingerprintDebugPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Disclosure toggle
            Button {
                withAnimation { showFingerprintDebug.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showFingerprintDebug ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "fingerprint")
                        .font(.caption)
                        .foregroundColor(.indigo)
                    Text("Fingerprint Debug")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.indigo)
                    Spacer()
                    let available = viewModel.structuredBundle?.availableFingerprintTypes.count ?? 0
                    let enabled = viewModel.enabledFingerprintTypes.count
                    Text("\(enabled)/\(available) enabled")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if showFingerprintDebug, let bundle = viewModel.structuredBundle {
                // Copy All Enabled button
                HStack(spacing: 8) {
                    CompactCopyButton(text: formatAllEnabledFingerprints(bundle: bundle))
                    Text("Copy All Enabled")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Per-fingerprint rows
                ForEach(bundle.availableFingerprintTypes, id: \.self) { fpType in
                    fingerprintRow(fpType, bundle: bundle)
                }
            }
        }
        .padding(.top, 4)
    }

    private func fingerprintRow(_ fpType: FingerprintPromptType, bundle: StructuredInputBundle) -> some View {
        let isEnabled = viewModel.enabledFingerprintTypes.contains(fpType)
        let isExpanded = expandedFingerprints.contains(fpType)
        let doc = bundle.fingerprints[fpType]

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Toggle
                Toggle(isOn: Binding(
                    get: { viewModel.enabledFingerprintTypes.contains(fpType) },
                    set: { enabled in
                        if enabled {
                            viewModel.enabledFingerprintTypes.insert(fpType)
                        } else {
                            viewModel.enabledFingerprintTypes.remove(fpType)
                        }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(SwitchToggleStyle(tint: fpType.tintColor))
                .labelsHidden()

                // Expand button
                Button {
                    withAnimation {
                        if isExpanded { expandedFingerprints.remove(fpType) }
                        else { expandedFingerprints.insert(fpType) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: fpType.iconName)
                            .font(.caption)
                            .foregroundColor(fpType.tintColor)
                        Text(fpType.shortLabel)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(fpType.tintColor)
                        Text(fpType.displayName)
                            .font(.caption)
                            .foregroundColor(isEnabled ? .primary : .secondary)
                        Spacer()
                        if let doc {
                            Text("\(doc.fingerprintText.count) chars")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }

                // Copy button for this fingerprint
                if let doc {
                    CompactCopyButton(text: doc.fingerprintText)
                }
            }

            if isExpanded, let doc {
                VStack(alignment: .leading, spacing: 4) {
                    // Full fingerprint text
                    Text(doc.fingerprintText)
                        .font(.system(size: 10))
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)

                    // Metadata line
                    HStack(spacing: 8) {
                        Text("\(doc.sourceVideoCount) source videos")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("\(doc.moveLabel) / \(doc.position)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("\(doc.tokensUsed) tokens")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(6)
        .background(isEnabled ? Color.clear : Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    private func formatAllEnabledFingerprints(bundle: StructuredInputBundle) -> String {
        let enabled = bundle.availableFingerprintTypes.filter { viewModel.enabledFingerprintTypes.contains($0) }
        return enabled.compactMap { fpType -> String? in
            guard let doc = bundle.fingerprints[fpType] else { return nil }
            return "=== FINGERPRINT: \(fpType.displayName) (\(fpType.shortLabel)) ===\n\(doc.fingerprintText)"
        }.joined(separator: "\n\n")
    }

    private func methodToggleRow(_ method: OpenerMethod, accentColor: Color = .accentColor) -> some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { viewModel.enabledMethods.contains(method) },
                set: { enabled in
                    if enabled {
                        viewModel.enabledMethods.insert(method)
                    } else {
                        viewModel.enabledMethods.remove(method)
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(SwitchToggleStyle(tint: accentColor))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(method.rawValue).font(.caption).fontWeight(.bold)
                        .foregroundColor(method.isStructured ? .indigo : .primary)
                    Text(method.displayName).font(.caption)
                    if let status = viewModel.methodStatuses[method] {
                        statusBadge(status)
                    }
                }
                Text(method.shortDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if method.isStructured {
                let variantCount = method == .s5_skeletonDriven ? 3 : viewModel.enabledFingerprintTypes.count
                Text("\(variantCount) × \(method.ownCallCount) calls")
                    .font(.caption2)
                    .foregroundColor(.indigo)
            } else {
                Text("\(method.ownCallCount) call\(method.ownCallCount > 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        Group {
            if viewModel.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Progress")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.completedCount)/\(viewModel.totalExpectedCalls) calls")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: Double(viewModel.completedCount), total: max(Double(viewModel.totalExpectedCalls), 1))

                    // Status pills
                    FlowLayout(spacing: 6) {
                        ForEach(OpenerMethod.allCases.filter { viewModel.enabledMethods.contains($0) }) { method in
                            let pillColor: Color = method.isStructured ? .indigo : statusColor(viewModel.methodStatuses[method] ?? .pending)
                            HStack(spacing: 4) {
                                statusIcon(viewModel.methodStatuses[method] ?? .pending)
                                Text(method.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(pillColor.opacity(0.15))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        Group {
            if let run = viewModel.currentRun {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Results")
                            .font(.headline)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(run.totalCalls) calls | \(run.totalTokens) tokens")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Est. cost: \(String(format: "$%.4f", run.totalCost)) | Model: \(run.modelUsed)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    ForEach(run.strategyRuns) { stratRun in
                        ForEach(stratRun.methodResults.sorted(by: { OpenerComparisonRun.resultSortKey($0) < OpenerComparisonRun.resultSortKey($1) })) { result in
                            methodResultCard(result)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Method Result Card

    private func methodResultCard(_ result: OpenerMethodResult) -> some View {
        let badgeColor: Color = result.method.isStructured ? .indigo : .accentColor

        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(result.displayLabel)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.2))
                    .cornerRadius(4)
                Text(result.method.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                statusBadge(result.status)

                CompactCopyButton(text: result.outputText)
            }

            // Telemetry
            HStack(spacing: 12) {
                telemetryPill("\(result.calls.count) call\(result.calls.count > 1 ? "s" : "")")
                telemetryPill("\(result.totalPromptTokens + result.totalCompletionTokens) tok")
                telemetryPill(String(format: "$%.4f", result.totalCost))
                telemetryPill("\(String(format: "%.1f", Double(result.durationMs) / 1000.0))s")
            }

            // Output text
            if result.status == .completed {
                Text(result.outputText)
                    .font(.body)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
            } else if result.status == .failed {
                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Intermediate outputs disclosure
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
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(10)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .font(.caption)
            }

            // Raw prompts/responses disclosure
            DisclosureGroup("Debug: Prompts & Responses") {
                ForEach(result.calls) { call in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Call \(call.callIndex + 1): \(call.callLabel)")
                            .font(.caption)
                            .fontWeight(.semibold)

                        if let t = call.telemetry {
                            Text("In: \(t.promptTokens) | Out: \(t.completionTokens) | Model: \(t.modelUsed)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        DisclosureGroup("System Prompt") {
                            Text(call.systemPrompt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)

                        DisclosureGroup("User Prompt") {
                            Text(call.userPrompt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption2)

                        DisclosureGroup("Raw Response") {
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

            // Inline fidelity breakdown (if evaluated)
            if let eval = viewModel.fidelityEvaluations.first(where: { $0.label == result.displayLabel }),
               let cache = coordinator.fidelityCache {
                InlineFidelityBreakdown(
                    fidelityScore: eval.score,
                    sections: eval.sections,
                    corpusStats: cache.corpusStats,
                    baseline: cache.baseline,
                    slotDebug: eval.slotDebug
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Fidelity Evaluation Section

    private var fidelitySection: some View {
        Group {
            if viewModel.currentRun != nil {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Fidelity Evaluation")
                            .font(.headline)
                        Spacer()

                        if let cache = coordinator.fidelityCache {
                            let dateStr = cache.computedAt.formatted(date: .abbreviated, time: .shortened)
                            Text("Baseline: \(dateStr)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            viewModel.showWeightConfig = true
                        } label: {
                            Label("Weights", systemImage: "slider.horizontal.3")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await viewModel.evaluateFidelity() }
                        } label: {
                            HStack {
                                if viewModel.isEvaluating {
                                    ProgressView().controlSize(.small)
                                }
                                Text(viewModel.isEvaluating ? "Annotating S2..." : "Evaluate Fidelity")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isEvaluating || coordinator.fidelityCache == nil)

                        if !viewModel.fidelityEvaluations.isEmpty {
                            CopyAllButton(
                                items: [viewModel.copyFidelityReport()],
                                label: "Copy Report"
                            )
                        }
                    }

                    if coordinator.fidelityCache == nil {
                        Text("Compute fidelity baseline in the Structure Workbench tab first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Compact ranking table (detail now lives inline in each method card)
                    if viewModel.fidelityEvaluations.count > 1 {
                        let sorted = viewModel.fidelityEvaluations.sorted { $0.score.compositeScore > $1.score.compositeScore }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ranking")
                                .font(.headline)
                            ForEach(sorted.indices, id: \.self) { i in
                                HStack {
                                    Text("#\(i + 1)")
                                        .font(.caption.bold())
                                        .frame(width: 30)
                                    Text(sorted[i].label)
                                        .font(.subheadline)
                                    Spacer()
                                    if sorted[i].score.hardFailCount > 0 {
                                        Text("\(sorted[i].score.hardFailCount)F")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.red)
                                    }
                                    Text(String(format: "%.0f", sorted[i].score.compositeScore))
                                        .font(.subheadline.bold().monospaced())
                                        .foregroundStyle(sorted[i].score.compositeScore >= 80 ? .green : sorted[i].score.compositeScore >= 60 ? .yellow : sorted[i].score.compositeScore >= 40 ? .orange : .red)
                                }
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .sheet(isPresented: $viewModel.showWeightConfig) {
                    viewModel.persistWeightProfile()
                } content: {
                    FidelityWeightConfigView(weightProfile: $coordinator.fidelityWeightProfile)
                        .frame(minWidth: 500, minHeight: 600)
                }
            }
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Group {
            if !viewModel.runHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Run History")
                            .font(.headline)
                        Spacer()
                        if viewModel.runHistory.contains(where: { $0.bestFidelityComposite != nil }) {
                            CopyAllButton(
                                items: [viewModel.copyHistoryFidelityReport()],
                                label: "Copy Scores"
                            )
                        }

                        if coordinator.fidelityCache != nil {
                            Button {
                                viewModel.reEvaluateAllHistory()
                            } label: {
                                HStack(spacing: 4) {
                                    if viewModel.isReEvaluatingHistory {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(viewModel.isReEvaluatingHistory ? "Re-evaluating..." : "Re-evaluate All Fidelity")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isReEvaluatingHistory)
                        }
                    }

                    if !viewModel.reEvalProgressMessage.isEmpty {
                        Text(viewModel.reEvalProgressMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.runHistory) { summary in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("\(summary.modelUsed) | \(summary.methodCount) methods | \(summary.totalCalls) calls | \(String(format: "$%.4f", summary.totalCost))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if let score = summary.bestFidelityComposite,
                               let method = summary.bestFidelityMethod {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.0f", score))
                                        .font(.caption.bold().monospaced())
                                        .foregroundStyle(
                                            score >= 80 ? .green :
                                            score >= 60 ? .yellow :
                                            score >= 40 ? .orange : .red
                                        )
                                    Text(method)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button("Load") {
                                viewModel.loadSavedRun(summary)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                viewModel.deleteRun(summary)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var claudeModels: [AIModel] {
        AIModel.allCases.filter { $0.provider == "claude" }
    }

    private func modelDisplayName(_ model: AIModel) -> String {
        switch model {
        case .claude3Haiku: return "Claude 3 Haiku"
        case .claude3Sonnet: return "Claude 3 Sonnet"
        case .claude3Opus: return "Claude 3 Opus"
        case .claude35Haiku: return "Claude 3.5 Haiku"
        case .claude35Sonnet: return "Claude 3.5 Sonnet"
        case .claude37Sonnet: return "Claude 3.7 Sonnet"
        case .claude4Sonnet: return "Claude 4 Sonnet"
        case .claude4Opus: return "Claude 4 Opus"
        case .claude41Opus: return "Claude 4.1 Opus"
        case .claude45Sonnet: return "Claude 4.5 Sonnet"
        case .claude45Haiku: return "Claude 4.5 Haiku"
        case .claude45Opus: return "Claude 4.5 Opus"
        case .claude46Opus: return "Claude 4.6 Opus"
        default: return model.rawValue
        }
    }

    private func telemetryPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
    }

    private func statusBadge(_ status: MethodRunStatus) -> some View {
        HStack(spacing: 3) {
            statusIcon(status)
            Text(status.rawValue.capitalized)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor(status).opacity(0.15))
        .cornerRadius(4)
    }

    @ViewBuilder
    private func statusIcon(_ status: MethodRunStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle").font(.caption2).foregroundColor(.gray)
        case .running:
            ProgressView().controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").font(.caption2).foregroundColor(.red)
        case .skipped:
            Image(systemName: "forward.circle").font(.caption2).foregroundColor(.orange)
        }
    }

    private func statusColor(_ status: MethodRunStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }
}
