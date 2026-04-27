//
//  ArcSpinePhaseView.swift
//  NewAgentBuilder
//
//  Phase 1 of the Arc Pipeline: Spine Generation.
//  Config, run P1-P5 paths, comparison table, per-path results.
//  Extracted from ArcComparisonView.
//

import SwiftUI

struct ArcSpinePhaseView: View {
    @ObservedObject var vm: ArcComparisonViewModel
    @Binding var selectedPhase: ArcPipelinePhase

    // MARK: - Collapsible Section Expansion States
    @State private var isConfigExpanded = true
    @State private var isComparisonExpanded = true
    @State private var isP1Expanded = false
    @State private var isP2Expanded = false
    @State private var isP3Expanded = false
    @State private var isP4Expanded = false
    @State private var isP5Expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Config
            configCollapsibleSection

            // 2. Progress (transient)
            if vm.isRunning {
                progressSection
            }

            // 3. Comparison table FIRST (summary before details)
            comparisonCollapsibleSection

            Divider()

            // 4. Per-path results
            ForEach(ArcPath.pass1Cases) { path in
                pathCollapsibleSection(for: path)
            }

            // 5. Next → Gap Detection button
            if let run = vm.currentRun,
               run.pathResults.contains(where: { $0.status == .completed }) {
                Divider()
                Button {
                    withAnimation { selectedPhase = .gapDetection }
                } label: {
                    HStack {
                        Spacer()
                        Label("Next: Gap Detection", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }

    // MARK: - Binding Helpers

    private func bindingForPath(_ path: ArcPath) -> Binding<Bool> {
        switch path {
        case .p1_singlePass:          return $isP1Expanded
        case .p2_contentFirst:        return $isP2Expanded
        case .p3_fourStepPipeline:    return $isP3Expanded
        case .p4_dynamicSelection:    return $isP4Expanded
        case .p5_dynamicContentFirst: return $isP5Expanded
        default: return $isP1Expanded  // V-paths not shown in Pass 1
        }
    }

    private func pathCountBadge(for path: ArcPath) -> String? {
        guard let result = vm.currentRun?.pathResults.first(where: { $0.path == path }) else {
            if !vm.enabledPaths.contains(path) { return "Skipped" }
            if vm.pathStatuses[path] == .running { return "Running..." }
            return nil
        }
        switch result.status {
        case .completed:
            let beatCount = result.outputSpine?.beats.count ?? 0
            return "\(beatCount) beats"
        case .failed:  return "Failed"
        case .skipped: return "Skipped"
        case .running: return "Running..."
        case .pending: return "Pending"
        }
    }

    // MARK: - Config Section

    private var configCollapsibleSection: some View {
        CollapsibleSection(
            title: "Narrative Arc Comparison",
            icon: "arrow.triangle.branch",
            isExpanded: $isConfigExpanded,
            count: vm.dependenciesLoaded
                ? "\(vm.enabledPaths.count) paths enabled"
                : nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run 5 different spine-building approaches on the same rambling and compare outputs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Model picker
                HStack {
                    Text("Model:")
                        .font(.subheadline)
                    Picker("Model", selection: $vm.selectedModel) {
                        Text("Claude 4 Sonnet").tag(AIModel.claude4Sonnet)
                        Text("Claude 4 Opus").tag(AIModel.claude4Opus)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }

                // Dependencies status
                dependencyStatusRow

                Divider()

                // Path toggles
                pathTogglesSection

                Divider()

                // Gap rambling toggle
                if vm.hasGapRambling {
                    HStack {
                        Toggle("Include gap rambling", isOn: $vm.includeGapRambling)
                            .font(.subheadline)
                        Text("\(vm.gapRamblingWordCount) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        Task { await vm.startRun() }
                    } label: {
                        Label("Run All Enabled", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.canRun)

                    if let run = vm.currentRun {
                        MenuCopyButton(text: run.copyAllOutput(), label: "Copy Outputs")
                        MenuCopyButton(text: run.copyAllWithPrompts(), label: "Copy + Prompts")
                        MenuCopyButton(text: run.copyPromptsOnly(), label: "Copy Prompts")
                    }
                }
            }
        }
    }

    private var dependencyStatusRow: some View {
        HStack(spacing: 8) {
            if vm.isLoadingDependencies {
                ProgressView()
                    .controlSize(.small)
                Text("Loading profile & spines...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = vm.dependencyError {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Retry") {
                    Task { await vm.loadDependencies() }
                }
                .font(.caption)
            } else if vm.dependenciesLoaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Profile loaded | \(vm.spineCount) spines | \(vm.representativeSpines.count) representative | Matrix cached")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Load Dependencies") {
                    Task { await vm.loadDependencies() }
                }
                .font(.caption)
            }
        }
    }

    private var pathTogglesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Paths")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(vm.enabledPaths.count == ArcPath.pass1Cases.count ? "Deselect All" : "Select All") {
                    if vm.enabledPaths.count == ArcPath.pass1Cases.count {
                        vm.enabledPaths = []
                    } else {
                        vm.enabledPaths = Set(ArcPath.pass1Cases)
                    }
                }
                .font(.caption)
            }

            ForEach(ArcPath.pass1Cases) { path in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { vm.enabledPaths.contains(path) },
                        set: { enabled in
                            if enabled { vm.enabledPaths.insert(path) }
                            else { vm.enabledPaths.remove(path) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text(path.rawValue)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForPath(path))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(path.displayName)
                        .font(.subheadline)

                    Text("(\(path.callCount) calls)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let status = vm.pathStatuses[path] {
                        statusBadge(status)
                    }
                }
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(vm.completedCount), total: Double(max(vm.totalExpectedCalls, 1)))
                .tint(.blue)

            Text("\(vm.completedCount) / \(vm.totalExpectedCalls) calls")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(ArcPath.pass1Cases) { path in
                    if vm.enabledPaths.contains(path) {
                        HStack(spacing: 4) {
                            statusIcon(vm.pathStatuses[path] ?? .pending)
                            Text(path.rawValue)
                                .font(.caption2.monospaced().weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(vm.pathStatuses[path] ?? .pending).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Per-Path CollapsibleSections

    private func pathCollapsibleSection(for path: ArcPath) -> some View {
        CollapsibleSection(
            title: "\(path.rawValue): \(path.displayName)",
            icon: "arrow.triangle.turn.up.right.diamond",
            isExpanded: bindingForPath(path),
            count: pathCountBadge(for: path)
        ) {
            if let result = vm.currentRun?.pathResults.first(where: { $0.path == path }) {
                pathResultContent(result)
            } else if !vm.enabledPaths.contains(path) {
                Text("Skipped (not enabled)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding()
            } else {
                Text("Not run yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding()
            }
        } trailingContent: {
            if let result = vm.currentRun?.pathResults.first(where: { $0.path == path }),
               result.status == .completed {
                CompactCopyButton(text: result.copyPromptAndOutput())
            }
        }
    }

    private func pathResultContent(_ result: ArcPathResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status + Copy row
            HStack {
                statusBadge(result.status)
                Spacer()
                if result.status == .completed, let spine = result.outputSpine {
                    CompactCopyButton(text: spine.renderedText)
                }
            }

            // Telemetry pills
            telemetryRow(result)

            // Spine display
            if let spine = result.outputSpine {
                spineDisplay(spine)
            } else if result.status == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    if let err = result.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if !result.rawSpineText.isEmpty {
                        DisclosureGroup("Raw Response") {
                            Text(result.rawSpineText.prefix(2000))
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                }
            }

            // Intermediate outputs
            if !result.intermediateOutputs.isEmpty {
                intermediateOutputsDisclosure(result)
            }

            // Prompt debugging
            promptDebugDisclosure(result)

            // Validation
            if let validation = result.validationResult {
                validationDisplay(validation)
            }
        }
    }

    private func telemetryRow(_ result: ArcPathResult) -> some View {
        FlowLayout(spacing: 6) {
            telemetryPill("\(result.calls.count) calls", icon: "phone.fill")
            telemetryPill("\(result.totalPromptTokens + result.totalCompletionTokens) tok", icon: "textformat.123")
            telemetryPill(String(format: "$%.4f", result.totalCost), icon: "dollarsign.circle")
            telemetryPill(String(format: "%.1fs", Double(result.durationMs) / 1000.0), icon: "clock")
        }
    }

    private func spineDisplay(_ spine: NarrativeSpine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Throughline
            Text("Throughline")
                .font(.caption.weight(.semibold))
            Text(spine.throughline)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Divider()

            // Beat list
            Text("Beats (\(spine.beats.count))")
                .font(.caption.weight(.semibold))
            ForEach(spine.beats) { beat in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(beat.beatNumber)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    Text(beat.function)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(functionColor(beat.function))
                        .frame(width: 100, alignment: .leading)
                    Text(beat.beatSentence)
                        .font(.caption2)
                        .lineLimit(2)
                }
            }

            Divider()

            // Phase summary
            Text("Phases (\(spine.phases.count))")
                .font(.caption.weight(.semibold))
            ForEach(spine.phases, id: \.phaseNumber) { phase in
                let range = phase.beatRange.count >= 2
                    ? "Beats \(phase.beatRange[0])-\(phase.beatRange[1])"
                    : "Beat \(phase.beatRange.first ?? 0)"
                Text("Phase \(phase.phaseNumber) (\(range)): \(phase.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func intermediateOutputsDisclosure(_ result: ArcPathResult) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                let sorted = result.intermediateOutputs.sorted { $0.key < $1.key }
                ForEach(sorted, id: \.key) { key, value in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(key)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            CompactCopyButton(text: value)
                        }
                        Text(value.prefix(1000) + (value.count > 1000 ? "..." : ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        } label: {
            Text("Intermediate Outputs (\(result.intermediateOutputs.count))")
                .font(.caption.weight(.semibold))
        }
    }

    private func promptDebugDisclosure(_ result: ArcPathResult) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(result.calls) { call in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Call \(call.callIndex + 1): \(call.callLabel)")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            if let t = call.telemetry {
                                Text("in: \(t.promptTokens) | out: \(t.completionTokens)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        DisclosureGroup("System Prompt") {
                            Text(call.systemPrompt)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                            CompactCopyButton(text: call.systemPrompt)
                        }
                        .font(.caption)

                        DisclosureGroup("User Prompt") {
                            Text(call.userPrompt.prefix(3000) + (call.userPrompt.count > 3000 ? "\n... [\(call.userPrompt.count) chars total]" : ""))
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                            CompactCopyButton(text: call.userPrompt)
                        }
                        .font(.caption)

                        DisclosureGroup("Raw Response") {
                            Text(call.rawResponse.prefix(3000) + (call.rawResponse.count > 3000 ? "\n... [\(call.rawResponse.count) chars total]" : ""))
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                            CompactCopyButton(text: call.rawResponse)
                        }
                        .font(.caption)
                    }
                    if call.id != result.calls.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            Text("Debug: Prompts & Responses (\(result.calls.count) calls)")
                .font(.caption.weight(.semibold))
        }
    }

    private func validationDisplay(_ v: SpineValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Validation")
                .font(.caption.weight(.semibold))

            FlowLayout(spacing: 6) {
                validationPill("Log prob: \(String(format: "%.2f", v.sequenceLogProbability))",
                              ok: v.sequenceLogProbability > -20)
                validationPill("Low-prob: \(v.lowProbabilityTransitions.count)",
                              ok: v.lowProbabilityTransitions.count < 3)
                validationPill("Missing: \(v.missingCommonTransitions.count)",
                              ok: v.missingCommonTransitions.count < 3)
                validationPill("Unknown fn: \(v.unknownFunctions.count)",
                              ok: v.unknownFunctions.isEmpty)
                validationPill("Deps valid: \(v.hasValidDependencyChain ? "yes" : "NO")",
                              ok: v.hasValidDependencyChain)
                if let unmapped = v.unmappedContentAtoms {
                    validationPill("Unmapped: \(unmapped.count)",
                                  ok: unmapped.isEmpty)
                }
            }

            if !v.lowProbabilityTransitions.isEmpty {
                DisclosureGroup("Low-Probability Transitions") {
                    ForEach(v.lowProbabilityTransitions, id: \.beatIndex) { t in
                        Text("Beat \(t.beatIndex): \(t.fromFunction) → \(t.toFunction) (p=\(String(format: "%.3f", t.probability)))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Comparison Section

    private var comparisonCollapsibleSection: some View {
        CollapsibleSection(
            title: "Comparison",
            icon: "chart.bar.xaxis",
            isExpanded: $isComparisonExpanded,
            count: {
                let completed = (vm.currentRun?.pathResults ?? []).filter { $0.status == .completed }
                return completed.isEmpty ? nil : "\(completed.count) paths"
            }()
        ) {
            comparisonContent
        }
    }

    @ViewBuilder
    private var comparisonContent: some View {
        let completed = (vm.currentRun?.pathResults ?? []).filter { $0.status == .completed }
        if completed.isEmpty {
            Text(vm.currentRun != nil
                 ? "No completed paths to compare."
                 : "Run the pipeline to see comparisons.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Metric")
                        .frame(width: 140, alignment: .leading)
                    ForEach(completed, id: \.id) { result in
                        Text(result.path.rawValue)
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(colorForPath(result.path))
                            .frame(width: 80)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.05))

                Divider()

                comparisonRow("Beat Count", values: completed.map { "\($0.outputSpine?.beats.count ?? 0)" })
                comparisonRow("Phase Count", values: completed.map { "\($0.outputSpine?.phases.count ?? 0)" })
                comparisonRow("Signatures", values: completed.map { "\($0.outputSpine?.structuralSignatures.count ?? 0)" })
                comparisonRow("Log Prob", values: completed.map {
                    $0.validationResult.map { String(format: "%.1f", $0.sequenceLogProbability) } ?? "—"
                })
                comparisonRow("Low-Prob", values: completed.map {
                    $0.validationResult.map { "\($0.lowProbabilityTransitions.count)" } ?? "—"
                })
                comparisonRow("Calls", values: completed.map { "\($0.calls.count)" })
                comparisonRow("Cost", values: completed.map { String(format: "$%.3f", $0.totalCost) })
                comparisonRow("Duration", values: completed.map { String(format: "%.1fs", Double($0.durationMs) / 1000.0) })
            }
        }
    }

    private func comparisonRow(_ label: String, values: [String]) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .frame(width: 140, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .frame(width: 80)
            }
        }
        .font(.caption)
        .padding(.vertical, 2)
    }

    // MARK: - Styling Helpers

    private func colorForPath(_ path: ArcPath) -> Color {
        switch path {
        case .p1_singlePass:          return .blue
        case .p2_contentFirst:        return .purple
        case .p3_fourStepPipeline:    return .orange
        case .p4_dynamicSelection:    return .teal
        case .p5_dynamicContentFirst: return .indigo
        case .v6_enrichedSinglePass:      return .mint
        case .v7_enrichedContentFirst:    return .cyan
        case .v8_enrichedFourStep:        return .brown
        case .v9_enrichedDynamic:         return .pink
        case .v10_enrichedDynamicContent: return .gray
        case .v11_freshFourStep:          return .green
        case .v12_freshDynamicContent:    return .yellow
        }
    }

    private func telemetryPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }

    private func validationPill(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ok ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
            .foregroundStyle(ok ? .green : .red)
            .clipShape(Capsule())
    }

    private func statusBadge(_ status: ArcPathRunStatus) -> some View {
        HStack(spacing: 3) {
            statusIcon(status)
            Text(status.rawValue.capitalized)
        }
        .font(.caption2)
        .foregroundStyle(statusColor(status))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor(status).opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func statusIcon(_ status: ArcPathRunStatus) -> some View {
        switch status {
        case .pending:   Image(systemName: "circle").foregroundStyle(.secondary)
        case .running:   ProgressView().controlSize(.mini)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped:   Image(systemName: "forward.fill").foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ status: ArcPathRunStatus) -> Color {
        switch status {
        case .pending:   return .secondary
        case .running:   return .blue
        case .completed: return .green
        case .failed:    return .red
        case .skipped:   return .secondary
        }
    }

    private func functionColor(_ function: String) -> Color {
        switch function {
        case "opening-anchor", "frame-set": return .blue
        case "setup-plant", "problem-statement", "stakes-raise", "context": return .purple
        case "expected-path", "dead-end", "complication": return .orange
        case "method-shift", "discovery", "evidence": return .green
        case "reframe", "mechanism", "implication": return .teal
        case "escalation", "pivot", "callback", "resolution": return .indigo
        default: return .secondary
        }
    }
}
