//
//  ArcGapPhaseView.swift
//  NewAgentBuilder
//
//  Phase 2 of the Arc Pipeline: Gap Detection.
//  Source arc picker, run G1-G6 paths, G6 synthesis first, comparison, per-path results.
//  Extracted from GapAnalysisSectionView.
//

import SwiftUI

struct ArcGapPhaseView: View {
    @ObservedObject var gapVM: GapAnalysisViewModel
    @Binding var selectedPhase: ArcPipelinePhase

    // MARK: - Collapsible Section Expansion States
    @State private var isGapConfigExpanded = true
    @State private var isGapComparisonExpanded = false
    @State private var isG1Expanded = false
    @State private var isG2Expanded = false
    @State private var isG3Expanded = false
    @State private var isG4Expanded = false
    @State private var isG5Expanded = false
    @State private var isG6Expanded = true  // Synthesis expanded by default

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Source arc info banner
            if let selected = gapVM.selectedArcResult {
                sourceArcBanner(selected)
            }

            // 2. Config
            gapConfigCollapsibleSection

            // 3. Progress (transient)
            if gapVM.isRunning {
                gapProgressSection
            }
            if gapVM.isRefining {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Refining findings against raw rambling...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 4. G6 Synthesis FIRST (the merged findings — what you care about)
            if let run = gapVM.currentGapRun,
               let g6 = run.pathResults.first(where: { $0.path == .g6_synthesis }) {
                gapPathCollapsibleSection(for: g6)
            }

            // 5. Comparison table
            gapComparisonCollapsibleSection

            Divider()

            // 6. Per-path results G1-G5
            if let run = gapVM.currentGapRun {
                ForEach(run.pathResults.filter { $0.path != .g6_synthesis }, id: \.id) { result in
                    gapPathCollapsibleSection(for: result)
                }
            }

            // 7. Next → Respond button
            if let run = gapVM.currentGapRun,
               !gapFindings(from: run).isEmpty {
                Divider()
                Button {
                    withAnimation { selectedPhase = .respond }
                } label: {
                    HStack {
                        Spacer()
                        Label("Next: Respond to Gaps", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    // MARK: - Source Arc Banner

    private func sourceArcBanner(_ result: ArcPathResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.blue)
            Text("Analyzing spine from")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(result.path.rawValue): \(result.path.displayName)")
                .font(.caption.weight(.semibold))
            if let spine = result.outputSpine {
                Text("(\(spine.beats.count) beats)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Binding Helpers

    private func bindingForGapPath(_ path: GapPath) -> Binding<Bool> {
        switch path {
        case .g1_singleLLM:               return $isG1Expanded
        case .g2_programmaticPlusLLM:     return $isG2Expanded
        case .g3_representativeComparison: return $isG3Expanded
        case .g4_viewerSimulation:        return $isG4Expanded
        case .g5_combined:                return $isG5Expanded
        case .g6_synthesis:               return $isG6Expanded
        }
    }

    private func gapPathCountBadge(for result: GapPathResult) -> String? {
        switch result.status {
        case .completed:
            let count = result.findings.count
            return count == 0 ? "No gaps" : "\(count) findings"
        case .failed:  return "Failed"
        case .skipped: return "Skipped"
        case .running: return "Running..."
        case .pending: return "Pending"
        }
    }

    // MARK: - Config Section

    private var gapConfigCollapsibleSection: some View {
        CollapsibleSection(
            title: "Gap Detection Config",
            icon: "gearshape",
            isExpanded: $isGapConfigExpanded,
            count: "\(gapVM.enabledGapPaths.count) paths"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run 5 different gap detection approaches on a selected narrative spine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Arc result picker
                if gapVM.availableArcResults.isEmpty {
                    Text("Run spine generation (Phase 1) first to get results to analyze.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    HStack {
                        Text("Source Arc:")
                            .font(.subheadline)
                        Picker("Arc Result", selection: $gapVM.selectedArcResultId) {
                            Text("Select...").tag(nil as UUID?)
                            ForEach(gapVM.availableArcResults) { result in
                                Text("\(result.path.rawValue): \(result.path.displayName) (\(result.outputSpine?.beats.count ?? 0) beats)")
                                    .tag(result.id as UUID?)
                            }
                        }
                        .frame(maxWidth: 400)
                    }
                }

                // Model picker
                HStack {
                    Text("Model:")
                        .font(.subheadline)
                    Picker("Model", selection: $gapVM.selectedModel) {
                        Text("Claude 4 Sonnet").tag(AIModel.claude4Sonnet)
                        Text("Claude 4 Opus").tag(AIModel.claude4Opus)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }

                Divider()

                // Gap path toggles
                gapPathTogglesSection

                Divider()

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        Task { await gapVM.startRun() }
                    } label: {
                        Label("Run Gap Analysis", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!gapVM.canRun)

                    if let run = gapVM.currentGapRun {
                        MenuCopyButton(text: run.copyAllOutput(), label: "Copy Outputs")
                        MenuCopyButton(text: run.copyAllWithPrompts(), label: "Copy + Prompts")
                        MenuCopyButton(text: run.copyPromptsOnly(), label: "Copy Prompts")
                        MenuCopyButton(text: run.copyGapQuestionsOnly(), label: "Copy Questions")
                    }
                }

                if let msg = gapVM.prerequisiteMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let err = gapVM.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var gapPathTogglesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Gap Paths")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(gapVM.enabledGapPaths.count == GapPath.primaryCases.count ? "Deselect All" : "Select All") {
                    if gapVM.enabledGapPaths.count == GapPath.primaryCases.count {
                        gapVM.enabledGapPaths = []
                    } else {
                        gapVM.enabledGapPaths = Set(GapPath.primaryCases)
                    }
                }
                .font(.caption)
            }

            ForEach(GapPath.primaryCases) { path in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { gapVM.enabledGapPaths.contains(path) },
                        set: { enabled in
                            if enabled { gapVM.enabledGapPaths.insert(path) }
                            else { gapVM.enabledGapPaths.remove(path) }
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
                        .background(colorForGapPath(path))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(path.displayName)
                        .font(.subheadline)

                    Text("(\(path.callCount) calls)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let status = gapVM.pathStatuses[path] {
                        statusBadge(status)
                    }
                }
            }

            if gapVM.g6WillRun {
                HStack(spacing: 6) {
                    Text("G6")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("Synthesis will run automatically after G1-G5 complete.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let status = gapVM.pathStatuses[.g6_synthesis] {
                        statusBadge(status)
                    }
                }
            }
        }
    }

    // MARK: - Progress Section

    private var gapProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(gapVM.completedCount), total: Double(max(gapVM.totalExpectedCalls, 1)))
                .tint(.orange)

            Text("\(gapVM.completedCount) / \(gapVM.totalExpectedCalls) calls")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(GapPath.primaryCases) { path in
                    if gapVM.enabledGapPaths.contains(path) {
                        HStack(spacing: 4) {
                            statusIcon(gapVM.pathStatuses[path] ?? .pending)
                            Text(path.rawValue)
                                .font(.caption2.monospaced().weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(gapVM.pathStatuses[path] ?? .pending).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                if gapVM.g6WillRun {
                    HStack(spacing: 4) {
                        statusIcon(gapVM.pathStatuses[.g6_synthesis] ?? .pending)
                        Text("G6")
                            .font(.caption2.monospaced().weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(gapVM.pathStatuses[.g6_synthesis] ?? .pending).opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Per-Path CollapsibleSections

    private func gapPathCollapsibleSection(for result: GapPathResult) -> some View {
        CollapsibleSection(
            title: "\(result.path.rawValue): \(result.path.displayName)",
            icon: "magnifyingglass",
            isExpanded: bindingForGapPath(result.path),
            count: gapPathCountBadge(for: result)
        ) {
            gapPathResultContent(result)
        }
    }

    private func gapPathResultContent(_ result: GapPathResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status + Copy row
            HStack {
                statusBadge(result.status)
                Spacer()
                if result.status == .completed {
                    let findingsText = result.findings.enumerated().map { i, f in
                        "\(i + 1). [\(f.priority.rawValue)] [\(f.type.rawValue)] \(f.whatsMissing)"
                    }.joined(separator: "\n")
                    CompactCopyButton(text: findingsText)
                }
            }

            // Telemetry
            gapTelemetryRow(result)

            // Error
            if let err = result.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Findings
            if !result.findings.isEmpty {
                gapFindingsList(result.findings)
            } else if result.status == .completed {
                Text("No gaps detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Intermediate outputs
            if !result.intermediateOutputs.isEmpty {
                gapIntermediateOutputsDisclosure(result)
            }

            // Prompt debugging
            gapPromptDebugDisclosure(result)
        }
    }

    private func gapTelemetryRow(_ result: GapPathResult) -> some View {
        FlowLayout(spacing: 6) {
            telemetryPill("\(result.telemetry.totalCalls) calls", icon: "phone.fill")
            telemetryPill("\(result.telemetry.totalTokens) tok", icon: "textformat.123")
            telemetryPill(String(format: "$%.4f", result.telemetry.totalCost), icon: "dollarsign.circle")
            telemetryPill(String(format: "%.1fs", Double(result.telemetry.durationMs) / 1000.0), icon: "clock")
            telemetryPill("\(result.findings.count) findings", icon: "magnifyingglass")
        }
    }

    private func gapFindingsList(_ findings: [GapFinding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(findings) { finding in
                gapFindingRow(finding)
            }
        }
    }

    private func gapFindingRow(_ finding: GapFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type + Action + Priority + Refinement pills
            FlowLayout(spacing: 4) {
                priorityBadge(finding.priority)
                typePill(finding.type)
                actionPill(finding.action)
                if let status = finding.refinementStatus {
                    refinementBadge(status)
                }
                Text(finding.location)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // What's missing
            Text(finding.whatsMissing)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(finding.refinementStatus == .resolved ? 0.5 : 1.0)

            // Why it matters
            Text(finding.whyItMatters)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Rambling excerpt (for resolved/refined)
            if let excerpt = finding.ramblingExcerpt, !excerpt.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(excerpt)
                        .font(.caption2)
                        .foregroundStyle(.green.opacity(0.8))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Refinement note
            if let note = finding.refinementNote, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            // Question section
            if finding.refinementStatus == .resolved {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Already covered in rambling — spine builder should incorporate this.")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if finding.refinementStatus == .refined, let refined = finding.refinedQuestion, !refined.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "questionmark.bubble")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(refined)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "questionmark.bubble")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text(finding.questionToRambler)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.4))
                        .strikethrough()
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "questionmark.bubble")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(finding.questionToRambler)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .background(finding.refinementStatus == .resolved
            ? Color.green.opacity(0.05)
            : priorityBackgroundColor(finding.priority))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func gapIntermediateOutputsDisclosure(_ result: GapPathResult) -> some View {
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

    private func gapPromptDebugDisclosure(_ result: GapPathResult) -> some View {
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

    // MARK: - Comparison Section

    private var gapComparisonCollapsibleSection: some View {
        CollapsibleSection(
            title: "Gap Comparison",
            icon: "chart.bar.xaxis",
            isExpanded: $isGapComparisonExpanded,
            count: {
                let completed = (gapVM.currentGapRun?.pathResults ?? []).filter { $0.status == .completed }
                return completed.isEmpty ? nil : "\(completed.count) paths"
            }()
        ) {
            gapComparisonContent
        }
    }

    @ViewBuilder
    private var gapComparisonContent: some View {
        let completed = (gapVM.currentGapRun?.pathResults ?? []).filter { $0.status == .completed }
        if completed.isEmpty {
            Text(gapVM.currentGapRun != nil
                 ? "No completed paths to compare."
                 : "Run gap analysis to see comparisons.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Metric")
                        .frame(width: 140, alignment: .leading)
                    ForEach(completed, id: \.id) { result in
                        Text(result.path.rawValue)
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(colorForGapPath(result.path))
                            .frame(width: 80)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.05))

                Divider()

                comparisonRow("Total Findings", values: completed.map { "\($0.findings.count)" })
                comparisonRow("HIGH", values: completed.map { "\($0.findings.filter { $0.priority == .high }.count)" })
                comparisonRow("MEDIUM", values: completed.map { "\($0.findings.filter { $0.priority == .medium }.count)" })
                comparisonRow("LOW", values: completed.map { "\($0.findings.filter { $0.priority == .low }.count)" })

                Divider()

                ForEach(GapType.allCases) { gapType in
                    comparisonRow(gapType.displayName, values: completed.map { result in
                        "\(result.findings.filter { $0.type == gapType }.count)"
                    })
                }

                Divider()

                comparisonRow("Calls", values: completed.map { "\($0.telemetry.totalCalls)" })
                comparisonRow("Cost", values: completed.map { String(format: "$%.3f", $0.telemetry.totalCost) })
                comparisonRow("Duration", values: completed.map { String(format: "%.1fs", Double($0.telemetry.durationMs) / 1000.0) })
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

    // MARK: - Gap Findings Helper

    private func gapFindings(from run: GapAnalysisRun) -> [GapFinding] {
        run.pathResults
            .filter { $0.status == .completed }
            .flatMap(\.findings)
            .filter { $0.refinementStatus != .resolved }
            .sorted { $0.priority < $1.priority }
    }

    // MARK: - Styling Helpers

    private func colorForGapPath(_ path: GapPath) -> Color {
        switch path {
        case .g1_singleLLM:               return .cyan
        case .g2_programmaticPlusLLM:     return .mint
        case .g3_representativeComparison: return .pink
        case .g4_viewerSimulation:        return .yellow
        case .g5_combined:                return .red
        case .g6_synthesis:               return .purple
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

    private func priorityBadge(_ priority: GapPriority) -> some View {
        Text(priority.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func typePill(_ type: GapType) -> some View {
        Text(type.rawValue)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func actionPill(_ action: GapAction) -> some View {
        Text(action.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(actionColor(action))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(actionColor(action).opacity(0.12))
            .clipShape(Capsule())
    }

    private func refinementBadge(_ status: RefinementStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(refinementColor(status))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func priorityColor(_ priority: GapPriority) -> Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .blue
        }
    }

    private func priorityBackgroundColor(_ priority: GapPriority) -> Color {
        switch priority {
        case .high:   return Color.red.opacity(0.08)
        case .medium: return Color.orange.opacity(0.08)
        case .low:    return Color.blue.opacity(0.05)
        }
    }

    private func refinementColor(_ status: RefinementStatus) -> Color {
        switch status {
        case .resolved:  return .green
        case .refined:   return .orange
        case .confirmed: return .blue
        }
    }

    private func actionColor(_ action: GapAction) -> Color {
        switch action {
        case .reshape:    return .purple
        case .surface:    return .teal
        case .contentGap: return .orange
        }
    }
}
