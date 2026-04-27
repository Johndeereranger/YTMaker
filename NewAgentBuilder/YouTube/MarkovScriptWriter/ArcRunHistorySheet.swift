//
//  ArcRunHistorySheet.swift
//  NewAgentBuilder
//
//  Unified history sheet for Arc Pipeline.
//  Shows both Arc Comparison and Gap Analysis run history.
//  Presented from the persistent top bar "History" button.
//

import SwiftUI

struct ArcRunHistorySheet: View {
    @ObservedObject var vm: ArcComparisonViewModel
    @ObservedObject var gapVM: GapAnalysisViewModel
    @ObservedObject var pass2VM: ArcComparisonViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Arc Run History
                Section {
                    if vm.runHistory.isEmpty {
                        Text("No saved arc runs yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.runHistory) { summary in
                            arcHistoryRow(summary)
                        }
                    }
                } header: {
                    HStack {
                        Label("Spine Generation Runs", systemImage: "arrow.triangle.branch")
                        Spacer()
                        Text("\(vm.runHistory.count) runs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Pass 2 Run History
                Section {
                    if pass2VM.runHistory.isEmpty {
                        Text("No saved Pass 2 runs yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pass2VM.runHistory) { summary in
                            pass2HistoryRow(summary)
                        }
                    }
                } header: {
                    HStack {
                        Label("Pass 2 Runs", systemImage: "arrow.2.squarepath")
                        Spacer()
                        Text("\(pass2VM.runHistory.count) runs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Gap Run History
                Section {
                    if gapVM.gapRunHistory.isEmpty {
                        Text("No saved gap runs yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(gapVM.gapRunHistory) { summary in
                            gapHistoryRow(summary)
                        }
                    }
                } header: {
                    HStack {
                        Label("Gap Detection Runs", systemImage: "magnifyingglass")
                        Spacer()
                        Text("\(gapVM.gapRunHistory.count) runs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Run History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Arc History Row

    private func arcHistoryRow(_ summary: ArcComparisonRunSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.createdAt, style: .date)
                    .font(.caption.weight(.semibold))
                    + Text("  ")
                    + Text(summary.createdAt, style: .time)
                        .font(.caption)

                HStack(spacing: 8) {
                    Text(summary.modelUsed)
                    Text("\(summary.pathCount) paths")
                    Text("\(summary.totalCalls) calls")
                    Text(String(format: "$%.3f", summary.totalCost))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                FlowLayout(spacing: 4) {
                    ForEach(summary.completedPaths, id: \.self) { label in
                        Text(label)
                            .font(.caption2.monospaced().weight(.bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            Button("Load") {
                vm.loadSavedRun(summary)
                dismiss()
            }
            .font(.caption)

            Button("Delete") {
                vm.deleteRun(summary)
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Pass 2 History Row

    private func pass2HistoryRow(_ summary: ArcComparisonRunSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.createdAt, style: .date)
                    .font(.caption.weight(.semibold))
                    + Text("  ")
                    + Text(summary.createdAt, style: .time)
                        .font(.caption)

                HStack(spacing: 8) {
                    Text(summary.modelUsed)
                    Text("\(summary.pathCount) paths")
                    Text("\(summary.totalCalls) calls")
                    Text(String(format: "$%.3f", summary.totalCost))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                FlowLayout(spacing: 4) {
                    ForEach(summary.completedPaths, id: \.self) { label in
                        Text(label)
                            .font(.caption2.monospaced().weight(.bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            Button("Load") {
                pass2VM.loadSavedRun(summary)
                dismiss()
            }
            .font(.caption)

            Button("Delete") {
                pass2VM.deleteRun(summary)
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Gap History Row

    private func gapHistoryRow(_ summary: GapAnalysisRunSummary) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.createdAt, style: .date)
                    .font(.caption.weight(.semibold))
                    + Text("  ")
                    + Text(summary.createdAt, style: .time)
                        .font(.caption)

                HStack(spacing: 8) {
                    Text(summary.modelUsed)
                    Text("Source: \(summary.sourceArcPath)")
                    Text("\(summary.totalFindings) findings")
                    Text("\(summary.highCount) HIGH")
                        .foregroundStyle(.red)
                    Text(String(format: "$%.3f", summary.totalCost))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                // Top findings preview
                if !summary.topFindings.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(summary.topFindings, id: \.self) { finding in
                            Text("- \(finding)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            Button("Load") {
                gapVM.loadSavedRun(summary)
                dismiss()
            }
            .font(.caption)

            Button("Delete") {
                gapVM.deleteRun(summary)
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
}
