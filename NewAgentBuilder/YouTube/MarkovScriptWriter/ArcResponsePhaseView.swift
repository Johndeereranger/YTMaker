//
//  ArcResponsePhaseView.swift
//  NewAgentBuilder
//
//  Phase 3 of the Arc Pipeline: Respond to Gaps.
//  Findings summary + path filter + question panel + rambling editor.
//  Extracted from GapAnalysisSectionView.
//

import SwiftUI

// MARK: - Enriched Finding (pairs a GapFinding with its source path)

private struct EnrichedFinding: Identifiable {
    let id: UUID
    let finding: GapFinding
    let sourcePath: GapPath
}

struct ArcResponsePhaseView: View {
    @ObservedObject var gapVM: GapAnalysisViewModel
    @Binding var selectedPhase: ArcPipelinePhase

    // MARK: - Rambling Pad State
    @State private var ramblingText: String = ""
    @State private var usedQuestionIds: Set<UUID> = []
    @State private var isRamblingPadExpanded = true  // Expanded by default — this IS the main content

    // MARK: - Path Filter
    @State private var selectedGapPath: GapPath?  // nil = All

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Back button
            Button {
                withAnimation { selectedPhase = .gapDetection }
            } label: {
                Label("Back to Gap Detection", systemImage: "arrow.left.circle")
                    .font(.caption)
            }

            if let run = gapVM.currentGapRun {
                let allEnriched = enrichedFindings(from: run)
                let filtered = filteredFindings(allEnriched)

                if allEnriched.isEmpty {
                    emptyState
                } else {
                    // Findings summary header
                    findingsSummary(filtered, totalCount: allEnriched.count)

                    // Path filter picker
                    pathFilterPicker(run: run)

                    // Question panel + Rambling editor (main content)
                    CollapsibleRamblingSection(
                        title: "Respond to Gaps",
                        icon: "text.bubble",
                        isExpanded: $isRamblingPadExpanded,
                        text: $ramblingText,
                        placeholder: "Tap questions above, then ramble your answers here...",
                        onSave: {
                            gapVM.coordinator.session.arcGapRamblingText = ramblingText
                            gapVM.coordinator.persistSession()
                        },
                        questions: filtered.map { enriched in
                            RamblingQuestion(
                                id: enriched.finding.id,
                                text: enriched.finding.effectiveQuestion,
                                priorityColor: priorityColor(enriched.finding.priority),
                                subtitle: enriched.finding.whatsMissing,
                                detail: enriched.finding.whyItMatters,
                                locationLabel: enriched.finding.location,
                                sourceLabel: enriched.sourcePath.rawValue,
                                typeBadge: enriched.finding.type.displayName,
                                actionBadge: enriched.finding.action.rawValue
                            )
                        },
                        usedQuestionIds: $usedQuestionIds,
                        onInsertQuestion: { question in
                            insertQuestion(question)
                        }
                    )
                }
            } else {
                noGapRunState
            }

            // Next: Pass 2 button (shows when gap rambling has content)
            if !ramblingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                Button {
                    withAnimation { selectedPhase = .pass2 }
                } label: {
                    HStack {
                        Spacer()
                        Label("Next: Pass 2", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .onAppear {
            restoreRamblingState()
        }
    }

    // MARK: - Path Filter Picker

    private func pathFilterPicker(run: GapAnalysisRun) -> some View {
        let completedPaths = run.pathResults
            .filter { $0.status == .completed && !$0.findings.isEmpty }
            .map(\.path)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" button
                Button {
                    withAnimation { selectedGapPath = nil }
                } label: {
                    Text("All")
                        .font(.caption.weight(selectedGapPath == nil ? .bold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedGapPath == nil ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundColor(selectedGapPath == nil ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Per-path buttons
                ForEach(completedPaths) { path in
                    Button {
                        withAnimation { selectedGapPath = path }
                    } label: {
                        Text("\(path.rawValue): \(path.displayName)")
                            .font(.caption.weight(selectedGapPath == path ? .bold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedGapPath == path ? Color.accentColor : Color.secondary.opacity(0.15))
                            .foregroundColor(selectedGapPath == path ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("All gaps resolved!")
                .font(.headline)
            Text("No actionable gaps remaining. All findings are marked as resolved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var noGapRunState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No gap analysis results")
                .font(.headline)
            Text("Run gap detection in Phase 2 first to generate findings to respond to.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Findings Summary

    private func findingsSummary(_ findings: [EnrichedFinding], totalCount: Int) -> some View {
        let highCount = findings.filter { $0.finding.priority == .high }.count
        let medCount = findings.filter { $0.finding.priority == .medium }.count
        let lowCount = findings.filter { $0.finding.priority == .low }.count
        let answeredCount = usedQuestionIds.count
        let displayCount = findings.count
        let filterActive = selectedGapPath != nil

        return HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.orange)

            if filterActive {
                Text("\(displayCount) of \(totalCount) gaps")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("\(displayCount) actionable gaps")
                    .font(.subheadline.weight(.semibold))
            }

            FlowLayout(spacing: 6) {
                if highCount > 0 {
                    Text("\(highCount) HIGH")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if medCount > 0 {
                    Text("\(medCount) MED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if lowCount > 0 {
                    Text("\(lowCount) LOW")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Spacer()

            Text("\(answeredCount)/\(totalCount) answered")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Rambling State Management

    private func restoreRamblingState() {
        let saved = gapVM.coordinator.session.arcGapRamblingText
        guard !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ramblingText = saved

        // Restore used question IDs by scanning saved text for markers
        let allFindings = (gapVM.currentGapRun?.pathResults ?? [])
            .filter { $0.status == .completed }
            .flatMap(\.findings)
        for finding in allFindings {
            let originalMarker = "[Q: \(finding.questionToRambler)]"
            let effectiveMarker = "[Q: \(finding.effectiveQuestion)]"
            if saved.contains(originalMarker) || saved.contains(effectiveMarker) {
                usedQuestionIds.insert(finding.id)
            }
        }
    }

    private func insertQuestion(_ question: RamblingQuestion) {
        let header = "[Q: \(question.text)]"
        if ramblingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ramblingText = header + "\n"
        } else {
            if !ramblingText.hasSuffix("\n\n") {
                if ramblingText.hasSuffix("\n") {
                    ramblingText += "\n"
                } else {
                    ramblingText += "\n\n"
                }
            }
            ramblingText += header + "\n"
        }
        usedQuestionIds.insert(question.id)
    }

    // MARK: - Helpers

    /// Extract findings from all completed paths, preserving which path each came from.
    private func enrichedFindings(from run: GapAnalysisRun) -> [EnrichedFinding] {
        run.pathResults
            .filter { $0.status == .completed }
            .flatMap { result in
                result.findings
                    .filter { $0.refinementStatus != .resolved }
                    .map { EnrichedFinding(id: $0.id, finding: $0, sourcePath: result.path) }
            }
            .sorted { $0.finding.priority < $1.finding.priority }
    }

    /// Apply the selected path filter.
    private func filteredFindings(_ enriched: [EnrichedFinding]) -> [EnrichedFinding] {
        guard let path = selectedGapPath else { return enriched }
        return enriched.filter { $0.sourcePath == path }
    }

    private func priorityColor(_ priority: GapPriority) -> Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .blue
        }
    }
}
