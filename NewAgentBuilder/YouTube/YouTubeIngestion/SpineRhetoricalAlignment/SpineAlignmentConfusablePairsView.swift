//
//  SpineAlignmentConfusablePairsView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/2/26.
//

import SwiftUI

// MARK: - View Model

@MainActor
class SpineAlignmentConfusablePairsViewModel: ObservableObject {
    let channel: YouTubeChannel
    private let firebase = SpineAlignmentFirebaseService.shared

    @Published var pairs: [SpineAlignmentConfusablePair] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFunction: String?

    init(channel: YouTubeChannel) {
        self.channel = channel
    }

    func loadPairs() async {
        isLoading = true
        errorMessage = nil
        do {
            pairs = try await firebase.loadConfusablePairs(creatorId: channel.channelId)
        } catch {
            errorMessage = "Load failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func deleteAll() async {
        do {
            try await firebase.deleteConfusablePairs(creatorId: channel.channelId)
            pairs = []
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Computed

    var filteredPairs: [SpineAlignmentConfusablePair] {
        if let fn = selectedFunction {
            return pairs.filter { $0.function == fn }
        }
        return pairs
    }

    var pairsByFunction: [String: [SpineAlignmentConfusablePair]] {
        Dictionary(grouping: filteredPairs, by: \.function)
    }

    var availableFunctions: [String] {
        Array(Set(pairs.map(\.function))).sorted()
    }

    var copyText: String {
        var lines: [String] = []
        lines.append("SPINE ALIGNMENT CONFUSABLE PAIRS")
        lines.append("Creator: \(channel.name)")
        lines.append("Total pairs: \(filteredPairs.count)")
        lines.append("Videos contributing: \(Set(filteredPairs.flatMap(\.sourceVideoIds)).count)")
        lines.append("")

        for fn in pairsByFunction.keys.sorted() {
            guard let fnPairs = pairsByFunction[fn] else { continue }
            lines.append("[\(fn)] — \(fnPairs.count) pairs")
            for pair in fnPairs {
                let pct = String(format: "%.0f%%", pair.confidence * 100)
                lines.append("  \(pair.moveA) <-> \(pair.moveB)  \(pair.swapCount)/\(pair.sampleSize) (\(pct)) from \(pair.sourceVideoIds.count) videos")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Main View

struct SpineAlignmentConfusablePairsView: View {
    @StateObject private var vm: SpineAlignmentConfusablePairsViewModel

    init(channel: YouTubeChannel) {
        _vm = StateObject(wrappedValue: SpineAlignmentConfusablePairsViewModel(channel: channel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if vm.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading confusable pairs...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if vm.pairs.isEmpty {
                    emptyState
                } else {
                    statsHeader
                    functionFilter
                    pairsList
                }

                // Actions
                HStack(spacing: 8) {
                    Button {
                        Task { await vm.loadPairs() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Refresh")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    if !vm.pairs.isEmpty {
                        CompactCopyButton(text: vm.copyText, fadeDuration: 2.0)
                    }

                    if !vm.pairs.isEmpty {
                        Button {
                            Task { await vm.deleteAll() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Clear All")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding()
        }
        .navigationTitle("Spine Alignment Confusable Pairs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await vm.loadPairs() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No confusable pairs stored yet.")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Run batch alignment (3 runs per video) to generate confusable pairs automatically.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 12) {
            statPill(value: "\(vm.filteredPairs.count)", label: "Pairs", color: .orange)
            statPill(value: "\(vm.pairsByFunction.count)", label: "Functions", color: .teal)

            let videoCount = Set(vm.filteredPairs.flatMap(\.sourceVideoIds)).count
            statPill(value: "\(videoCount)", label: "Videos", color: .blue)

            let highConfidence = vm.filteredPairs.filter { $0.confidence >= 0.25 }.count
            statPill(value: "\(highConfidence)", label: "High Conf", color: .red)
        }
    }

    // MARK: - Function Filter

    private var functionFilter: some View {
        HStack(spacing: 8) {
            Text("Filter:")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Function", selection: $vm.selectedFunction) {
                Text("All").tag(nil as String?)
                ForEach(vm.availableFunctions, id: \.self) { fn in
                    Text(fn.replacingOccurrences(of: "-", with: " ").capitalized)
                        .tag(fn as String?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Pairs List

    private var pairsList: some View {
        ForEach(Array(vm.pairsByFunction.keys.sorted()), id: \.self) { function in
            if let pairs = vm.pairsByFunction[function] {
                functionGroup(function: function, pairs: pairs)
            }
        }
    }

    private func functionGroup(function: String, pairs: [SpineAlignmentConfusablePair]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(function.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(pairs.count) pairs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(pairs) { pair in
                confusablePairRow(pair)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Confusable Pair Row

    private func confusablePairRow(_ pair: SpineAlignmentConfusablePair) -> some View {
        HStack(spacing: 8) {
            moveLabel(pair.moveA)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 9))
                .foregroundColor(.orange)

            moveLabel(pair.moveB)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(pair.swapCount)/\(pair.sampleSize)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f%%", pair.confidence * 100))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(confidenceColor(pair.confidence))
            }

            Text("\(pair.sourceVideoIds.count)v")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(6)
    }

    // MARK: - Helpers

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.bold())
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    private func moveLabel(_ move: String) -> some View {
        Text(move.replacingOccurrences(of: "-", with: " "))
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.12))
            .foregroundColor(.orange)
            .cornerRadius(4)
            .lineLimit(1)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.5 { return .red }
        if confidence >= 0.25 { return .orange }
        return .secondary
    }
}
