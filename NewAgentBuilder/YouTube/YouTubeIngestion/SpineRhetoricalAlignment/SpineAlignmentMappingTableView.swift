//
//  SpineAlignmentMappingTableView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/2/26.
//

import SwiftUI

struct SpineAlignmentMappingTableView: View {
    let channel: YouTubeChannel

    @State private var mappingTable: SpineRhetoricalMappingTable?
    @State private var isLoading = false
    @State private var isRecomputing = false
    @State private var errorMessage: String?
    @State private var showWeighted = true  // toggle: true = weighted, false = raw
    @State private var expandedFunctions: Set<String> = []

    private let firebase = SpineAlignmentFirebaseService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading mapping table...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(40)
                } else if let table = mappingTable {
                    tableHeader(table)
                    viewToggle
                    functionRows(table)
                    unmappedMovesSection(table)
                    summaryStats(table)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No mapping table computed yet")
                            .font(.subheadline)
                        Text("Run alignment on 3+ videos first, then compute the table")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        computeButton
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding()
        }
        .navigationTitle("Spine-Move Mapping Table")
        .task {
            await loadTable()
        }
    }

    // MARK: - Table Header

    private func tableHeader(_ table: SpineRhetoricalMappingTable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.headline)
                    Text("\(table.videoCount) videos | \(table.functionMappings.count) functions | Computed \(table.computedAt, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                CompactCopyButton(text: table.renderedText)
            }

            HStack(spacing: 8) {
                computeButton

                if isRecomputing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - View Toggle

    private var viewToggle: some View {
        Picker("View", selection: $showWeighted) {
            Text("Weighted").tag(true)
            Text("Raw").tag(false)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Function Rows

    private func functionRows(_ table: SpineRhetoricalMappingTable) -> some View {
        VStack(spacing: 8) {
            ForEach(table.functionMappings, id: \.function) { mapping in
                functionRow(mapping)
            }
        }
    }

    private func functionRow(_ mapping: FunctionMoveMapping) -> some View {
        let isExpanded = expandedFunctions.contains(mapping.function)

        return VStack(alignment: .leading, spacing: 6) {
            // Tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedFunctions.remove(mapping.function)
                    } else {
                        expandedFunctions.insert(mapping.function)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // Function label pill
                        Text(mapping.function)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.teal.opacity(0.15))
                            .foregroundColor(.teal)
                            .cornerRadius(4)

                        Spacer()

                        Text("\(mapping.totalOccurrences) beats")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                        Text("avg \(String(format: "%.1f", mapping.avgMovesPerBeat)) mv")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Top 4 move pills
                    FlowLayout(spacing: 4) {
                        ForEach(Array(mapping.moveDistribution.prefix(4).enumerated()), id: \.offset) { _, mf in
                            let pct = showWeighted ? mf.weightedPercentage : mf.rawPercentage
                            HStack(spacing: 2) {
                                Text(mf.moveType)
                                    .font(.system(size: 9))
                                Text(String(format: "%.0f%%", pct))
                                    .font(.system(size: 9).monospacedDigit().bold())
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(moveColor(mf.moveType).opacity(0.12))
                            .foregroundColor(moveColor(mf.moveType))
                            .cornerRadius(4)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Column headers
                    HStack {
                        Text("Move Type")
                            .font(.caption2.bold())
                            .frame(width: 130, alignment: .leading)
                        Text("W%")
                            .font(.caption2.bold())
                            .frame(width: 40, alignment: .trailing)
                        Text("R%")
                            .font(.caption2.bold())
                            .frame(width: 40, alignment: .trailing)
                        Text("F")
                            .font(.caption2.bold())
                            .frame(width: 24, alignment: .trailing)
                        Text("P")
                            .font(.caption2.bold())
                            .frame(width: 24, alignment: .trailing)
                        Text("T")
                            .font(.caption2.bold())
                            .frame(width: 24, alignment: .trailing)
                    }
                    .foregroundColor(.secondary)

                    Divider()

                    ForEach(mapping.moveDistribution, id: \.moveType) { mf in
                        HStack {
                            Text(mf.moveType)
                                .font(.caption2)
                                .frame(width: 130, alignment: .leading)
                                .lineLimit(1)
                            Text(String(format: "%.1f", mf.weightedPercentage))
                                .font(.caption2.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                                .foregroundColor(showWeighted ? .primary : .secondary)
                            Text(String(format: "%.1f", mf.rawPercentage))
                                .font(.caption2.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                                .foregroundColor(showWeighted ? .secondary : .primary)
                            Text("\(mf.fullCount)")
                                .font(.caption2.monospacedDigit())
                                .frame(width: 24, alignment: .trailing)
                                .foregroundColor(.green)
                            Text("\(mf.partialCount)")
                                .font(.caption2.monospacedDigit())
                                .frame(width: 24, alignment: .trailing)
                                .foregroundColor(.orange)
                            Text("\(mf.tangentialCount)")
                                .font(.caption2.monospacedDigit())
                                .frame(width: 24, alignment: .trailing)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Unmapped Moves Section

    private func unmappedMovesSection(_ table: SpineRhetoricalMappingTable) -> some View {
        Group {
            if !table.unmappedMoveStats.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unmapped Moves")
                        .font(.subheadline.bold())

                    ForEach(table.unmappedMoveStats, id: \.moveType) { stat in
                        HStack {
                            Text(stat.moveType)
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%% unmapped", stat.unmappedPercentage))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(stat.unmappedPercentage > 50 ? .orange : .secondary)
                            Text("(\(stat.unmappedCount)/\(stat.totalCount))")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Summary Stats

    private func summaryStats(_ table: SpineRhetoricalMappingTable) -> some View {
        let mappings = table.functionMappings
        let mostConnected = mappings.max(by: { $0.moveDistribution.count < $1.moveDistribution.count })
        let tightest = mappings.filter { !$0.moveDistribution.isEmpty }.min(by: { $0.moveDistribution.count < $1.moveDistribution.count })
        let allMoveTypes = Set(mappings.flatMap { $0.moveDistribution.map { $0.moveType } })

        return VStack(alignment: .leading, spacing: 6) {
            Text("Summary")
                .font(.subheadline.bold())

            if let mc = mostConnected {
                HStack {
                    Text("Most connected:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(mc.function)
                        .font(.caption.bold())
                    Text("(\(mc.moveDistribution.count) distinct moves)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let t = tightest {
                HStack {
                    Text("Tightest mapping:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(t.function)
                        .font(.caption.bold())
                    Text("(\(t.moveDistribution.count) distinct moves)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Total coverage:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(allMoveTypes.count) of 25 move types appear")
                    .font(.caption.bold())
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Compute Button

    private var computeButton: some View {
        Button {
            Task { await recompute() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                Text(mappingTable == nil ? "Compute Table" : "Recompute")
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.indigo.opacity(0.12))
            .foregroundColor(.indigo)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(isRecomputing)
    }

    // MARK: - Data Loading

    private func loadTable() async {
        isLoading = true
        do {
            mappingTable = try await firebase.loadMappingTable(channelId: channel.channelId)
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func recompute() async {
        isRecomputing = true
        errorMessage = nil
        do {
            mappingTable = try await SpineAlignmentService.shared.computeMappingTable(channelId: channel.channelId)
        } catch {
            errorMessage = "Recompute failed: \(error.localizedDescription)"
        }
        isRecomputing = false
    }

    // MARK: - Helpers

    /// Color for a move type based on its rhetorical category
    private func moveColor(_ moveType: String) -> Color {
        guard let parsed = RhetoricalMoveType.parse(moveType) else { return .gray }
        switch parsed.category {
        case .hook: return .red
        case .setup: return .blue
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .green
        case .closing: return .indigo
        }
    }
}
