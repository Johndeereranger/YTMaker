//
//  ConfusablePairView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/16/26.
//

import SwiftUI

// MARK: - View Model

@MainActor
class ConfusablePairViewModel: ObservableObject {
    let channel: YouTubeChannel
    private let service = ConfusablePairService.shared

    // MARK: - Browse
    @Published var storedPairs: [ConfusablePair] = []
    @Published var isLoading = false
    @Published var selectedMoveType: String?
    @Published var errorMessage: String?

    // MARK: - Expansion Test
    @Published var testSignature = ""
    @Published var testMoveType = "scene_set"
    @Published var expandedSignatures: [String] = []

    init(channel: YouTubeChannel) {
        self.channel = channel
    }

    // MARK: - Load Stored Pairs

    func loadStoredPairs() async {
        isLoading = true
        do {
            storedPairs = try await service.loadPairs()
        } catch {
            errorMessage = "Load failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Delete Pair

    func deletePair(_ pair: ConfusablePair) async {
        do {
            try await service.deletePair(id: pair.id)
            storedPairs.removeAll { $0.id == pair.id }
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Test Expansion

    func testExpansion() {
        guard !testSignature.isEmpty, !storedPairs.isEmpty else {
            expandedSignatures = []
            return
        }
        let lookup = service.buildLookup(from: storedPairs)
        expandedSignatures = service.expandSignature(testSignature, using: lookup, moveType: testMoveType)
    }

    // MARK: - Computed

    var filteredPairs: [ConfusablePair] {
        if let moveType = selectedMoveType {
            return storedPairs.filter { $0.moveType == moveType }
        }
        return storedPairs
    }

    var pairsByMoveType: [String: [ConfusablePair]] {
        Dictionary(grouping: filteredPairs, by: \.moveType)
    }

    var availableMoveTypes: [String] {
        Array(Set(storedPairs.map(\.moveType))).sorted()
    }
}

// MARK: - Main View

struct ConfusablePairView: View {
    @StateObject private var vm: ConfusablePairViewModel

    init(channel: YouTubeChannel) {
        _vm = StateObject(wrappedValue: ConfusablePairViewModel(channel: channel))
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
                } else if vm.storedPairs.isEmpty {
                    emptyState
                } else {
                    statsHeader
                    moveTypeFilter
                    pairsList
                    expansionTesterSection
                }

                // Refresh
                Button {
                    Task { await vm.loadStoredPairs() }
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
        .navigationTitle("Confusable Pairs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await vm.loadStoredPairs() }
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
            Text("Run a Slot Fidelity Test and press \"Save Confusable Pairs\" to populate the index.")
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
            statPill(value: "\(vm.filteredPairs.count)", label: "Pairs", color: .purple)
            statPill(value: "\(vm.pairsByMoveType.count)", label: "Section Types", color: .blue)

            let videoCount = Set(vm.filteredPairs.flatMap(\.sourceVideoIds)).count
            statPill(value: "\(videoCount)", label: "Videos", color: .teal)
        }
    }

    // MARK: - Move Type Filter

    private var moveTypeFilter: some View {
        HStack(spacing: 8) {
            Text("Filter:")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Move Type", selection: $vm.selectedMoveType) {
                Text("All").tag(nil as String?)
                ForEach(vm.availableMoveTypes, id: \.self) { type in
                    Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .tag(type as String?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Pairs List

    private var pairsList: some View {
        ForEach(Array(vm.pairsByMoveType.keys.sorted()), id: \.self) { moveType in
            if let pairs = vm.pairsByMoveType[moveType] {
                moveTypeGroup(moveType: moveType, pairs: pairs)
            }
        }
    }

    private func moveTypeGroup(moveType: String, pairs: [ConfusablePair]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(moveType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(pairs.count) pairs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(pairs) { pair in
                confusablePairRow(pair)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await vm.deletePair(pair) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Expansion Tester

    private var expansionTesterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test Expansion")
                .font(.subheadline.bold())

            HStack(spacing: 8) {
                TextField("Enter slot signature (e.g. actor_reference|narrative_action)", text: $vm.testSignature)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Picker("Type", selection: $vm.testMoveType) {
                    ForEach(vm.availableMoveTypes, id: \.self) { type in
                        Text(type.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)

                Button {
                    vm.testExpansion()
                } label: {
                    Text("Expand")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            if !vm.expandedSignatures.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(vm.expandedSignatures.count) variant(s):")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(vm.expandedSignatures, id: \.self) { sig in
                        let isOriginal = sig == vm.testSignature
                        Text(sig)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(isOriginal ? .primary : .purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isOriginal ? Color(.systemGray5) : Color.purple.opacity(0.08))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Confusable Pair Row

    private func confusablePairRow(_ pair: ConfusablePair) -> some View {
        HStack(spacing: 8) {
            Text("pos \(pair.slotPosition)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            slotLabel(pair.labelA)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 9))
                .foregroundColor(.purple)

            slotLabel(pair.labelB)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(pair.swapCount)/\(pair.sampleSize)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f%%", pair.confidence * 100))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(confidenceColor(pair.confidence))
            }
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

    private func slotLabel(_ label: String) -> some View {
        Text(label.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(slotColor(label).opacity(0.12))
            .foregroundColor(slotColor(label))
            .cornerRadius(4)
            .lineLimit(1)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.5 { return .red }
        if confidence >= 0.25 { return .orange }
        return .secondary
    }

    private func slotColor(_ type: String) -> Color {
        switch type {
        case "geographic_location": return .blue
        case "visual_detail": return .cyan
        case "quantitative_claim": return .purple
        case "temporal_marker": return .orange
        case "actor_reference": return .green
        case "contradiction": return .red
        case "sensory_detail": return .mint
        case "rhetorical_question": return .pink
        case "evaluative_claim": return .yellow
        case "pivot_phrase": return .indigo
        case "direct_address": return .teal
        case "narrative_action": return .brown
        case "abstract_framing": return .gray
        case "comparison": return .purple
        case "empty_connector": return .gray
        case "factual_relay": return .cyan
        case "reaction_beat": return .pink
        case "visual_anchor": return .mint
        default: return .secondary
        }
    }
}
