//
//  SynthesisView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  Top-level container for the synthesis pipeline.
//  Sub-tabs: Pass 1 | Pass 2 | History
//

import SwiftUI

struct SynthesisView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @State private var selectedSubTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab picker
            Picker("", selection: $selectedSubTab) {
                Text("Pass 1").tag(0)
                Text("Pass 2").tag(1)
                Text("History").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Loading overlay
            if coordinator.isLoading {
                synthesisProgressView
            }

            // Content
            switch selectedSubTab {
            case 0:
                Pass1ResultsView(coordinator: coordinator)
            case 1:
                Pass2ResultsView(coordinator: coordinator)
            case 2:
                synthesisHistoryView
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Progress View

    private var synthesisProgressView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(coordinator.loadingMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let progress = coordinator.synthesisProgress {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .padding(.horizontal, 40)
                Text("Section \(progress.current) of \(progress.total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - History View

    private var synthesisHistoryView: some View {
        List {
            if coordinator.session.synthesisRunSummaries.isEmpty {
                Text("No synthesis runs yet.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(coordinator.session.synthesisRunSummaries.reversed()) { summary in
                    Button {
                        coordinator.loadSynthesisRun(summary.id)
                        selectedSubTab = 0
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(summary.timestamp, style: .date)
                                    .font(.subheadline)
                                Text(summary.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(summary.promptVersion)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Text("\(summary.sectionCount) sections")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(summary.moveSequenceSummary)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                if summary.hasPass2 {
                                    Label("Pass 2", systemImage: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                } else {
                                    Label("Pass 1 only", systemImage: "circle")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    let reversed = coordinator.session.synthesisRunSummaries.reversed()
                    let arr = Array(reversed)
                    for index in indexSet {
                        coordinator.deleteSynthesisRun(arr[index].id)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !coordinator.session.synthesisRunSummaries.isEmpty {
                    Button("Delete All", role: .destructive) {
                        coordinator.deleteAllSynthesisRuns()
                    }
                }
            }
        }
    }
}
