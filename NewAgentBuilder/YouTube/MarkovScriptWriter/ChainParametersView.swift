//
//  ChainParametersView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/3/26.
//
//  Tab 5: Parameter tuning view for chain builder settings.
//  Grouped sections with sliders, steppers, and pickers.
//

import SwiftUI

struct ChainParametersView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator

    @State private var changedSinceLastBuild = false

    private var params: Binding<ChainParameters> {
        Binding(
            get: { coordinator.session.parameters },
            set: { newValue in
                coordinator.session.parameters = newValue
                changedSinceLastBuild = true
                coordinator.persistSession()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                markovConstraintsSection
                chainStructureSection
                positionConstraintsSection
                algorithmSection
                rebuildButton
            }
            .padding()
        }
    }

    // MARK: - Markov Constraints

    private var markovConstraintsSection: some View {
        parameterCard("Markov Constraints") {
            VStack(alignment: .leading, spacing: 12) {
                // Transition Threshold
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Transition Threshold")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(params.wrappedValue.transitionThreshold * 100))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    Slider(value: params.transitionThreshold, in: 0...0.30, step: 0.01)
                    Text("Transitions below this probability are rejected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // History Depth
                HStack {
                    Text("History Depth")
                        .font(.caption)
                    Spacer()
                    Stepper("\(params.wrappedValue.historyDepth)", value: params.historyDepth, in: 1...8)
                        .font(.caption)
                }
                Text("N-step context for Markov lookups (1=bigram, 3=4-gram)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider()

                // Min Observation Count
                HStack {
                    Text("Min Observation Count")
                        .font(.caption)
                    Spacer()
                    Stepper("\(params.wrappedValue.minObservationCount)", value: params.minObservationCount, in: 1...10)
                        .font(.caption)
                }
                Text("Transitions with fewer observations get flagged as sparse")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider()

                // Use Parent Level
                Toggle(isOn: params.useParentLevel) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Parent Level")
                            .font(.caption)
                        Text("6 categories instead of 25 moves")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    // MARK: - Chain Structure

    private var chainStructureSection: some View {
        parameterCard("Chain Structure") {
            VStack(alignment: .leading, spacing: 12) {
                // Min Chain Length
                HStack {
                    Text("Min Chain Length")
                        .font(.caption)
                    Spacer()
                    Stepper("\(params.wrappedValue.minChainLength)", value: params.minChainLength, in: 1...20)
                        .font(.caption)
                }

                Divider()

                // Max Chain Length
                HStack {
                    Text("Max Chain Length")
                        .font(.caption)
                    Spacer()
                    Stepper("\(params.wrappedValue.maxChainLength)", value: params.maxChainLength, in: 3...100)
                        .font(.caption)
                }

                Divider()

                // Coverage Target
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Coverage Target")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(params.wrappedValue.coverageTarget * 100))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    Slider(value: params.coverageTarget, in: 0...1.0, step: 0.05)
                    Text("Minimum % of gists that should be used in the chain")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Allow Consecutive Same Category
                Toggle(isOn: params.allowConsecutiveSameCategory) {
                    Text("Allow Consecutive Same Category")
                        .font(.caption)
                }
                .toggleStyle(.switch)

                // Max Consecutive Same Category
                HStack {
                    Text("Max Consecutive Same Category")
                        .font(.caption)
                        .foregroundColor(params.wrappedValue.allowConsecutiveSameCategory ? .primary : .secondary)
                    Spacer()
                    Stepper("\(params.wrappedValue.maxConsecutiveSameCategory)", value: params.maxConsecutiveSameCategory, in: 1...10)
                        .font(.caption)
                }
                .disabled(!params.wrappedValue.allowConsecutiveSameCategory)
            }
        }
    }

    // MARK: - Position Constraints

    private var positionConstraintsSection: some View {
        parameterCard("Position Constraints") {
            VStack(alignment: .leading, spacing: 12) {
                // Position Constraint Weight
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Constraint Weight")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.1f", params.wrappedValue.positionConstraintWeight))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    Slider(value: params.positionConstraintWeight, in: 0...1.0, step: 0.1)
                    Text("0 = ignore position, 1 = hard position constraint")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Position Constraint Zones
                VStack(alignment: .leading, spacing: 4) {
                    Text("Constraint Zones")
                        .font(.caption)
                    Picker("Zones", selection: params.positionConstraintZones) {
                        ForEach(PositionConstraintZone.allCases, id: \.self) { zone in
                            Text(zone.rawValue).tag(zone)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Where position constraints apply in the chain")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Algorithm

    private var algorithmSection: some View {
        parameterCard("Algorithm") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Algorithm", selection: params.algorithmType) {
                    ForEach(ChainAlgorithm.allCases, id: \.self) { algo in
                        HStack {
                            Text(algo.rawValue)
                            if algo != .exhaustive && algo != .treeWalk {
                                Text("Coming soon")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }.tag(algo)
                    }
                }
                .pickerStyle(.menu)

                switch params.wrappedValue.algorithmType {
                case .exhaustive:
                    Text("One greedy path per starter with backtracking memory")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                case .treeWalk:
                    treeWalkParameters

                default:
                    Text("Only Exhaustive and Tree Walk are currently implemented")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private var treeWalkParameters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explores all branches from each starter. Dead ends reveal what your rambling is missing.")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            // Path Budget
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Path Budget")
                        .font(.caption)
                    Spacer()
                    Text("\(params.wrappedValue.monteCarloSimulations)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                Picker("Budget", selection: params.monteCarloSimulations) {
                    ForEach([200, 500, 1000, 2000, 4000, 6000, 10000], id: \.self) { budget in
                        Text("\(budget)").tag(budget)
                    }
                }
                .pickerStyle(.segmented)
                Text("Maximum paths to explore before stopping")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Max Guidance Gaps
            HStack {
                Text("Max Guidance Gaps")
                    .font(.caption)
                Spacer()
                Stepper("\(params.wrappedValue.maxGuidanceGaps)", value: params.maxGuidanceGaps, in: 3...10)
                    .font(.caption)
            }
            Text("Top N dead end groups that get LLM-generated guidance")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            // Move Type Frequency Cap
            HStack {
                Text("Move Type Frequency Cap")
                    .font(.caption)
                Spacer()
                Text("\(Int(params.wrappedValue.maxMoveTypeShare * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)
                Slider(value: params.maxMoveTypeShare, in: 0.2...1.0, step: 0.05)
                    .frame(width: 150)
            }
            Text(params.wrappedValue.maxMoveTypeShare >= 1.0
                ? "Disabled — no limit on how often a single move type can repeat"
                : "Max \(Int(params.wrappedValue.maxMoveTypeShare * 100))% of chain positions for any single move type (auto-set to 35% for budget \u{2265} 1000)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            // Gist Branching
            Toggle(isOn: params.enableGistBranching) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gist Branching")
                        .font(.caption)
                    Text("Also explore alternative gist assignments per move")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            if params.wrappedValue.enableGistBranching {
                HStack {
                    Text("Max Gist Branches/Move")
                        .font(.caption)
                    Spacer()
                    Stepper("\(params.wrappedValue.maxGistBranchesPerMove)", value: params.maxGistBranchesPerMove, in: 1...8)
                        .font(.caption)
                }
                Text("Top N most-constrained gists explored per move (constraint score \u{2264} 5)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Upside Weights
            VStack(alignment: .leading, spacing: 8) {
                Text("Upside Weights")
                    .font(.caption)
                    .fontWeight(.semibold)

                upsideWeightRow("Frequency", value: params.upsideFrequencyWeight, desc: "Weight for how many dead ends this move blocks")
                upsideWeightRow("Depth", value: params.upsideDepthWeight, desc: "Weight for how deep in the chain dead ends occur")
                upsideWeightRow("Diversity", value: params.upsideDiversityWeight, desc: "Weight for how many distinct starter paths are blocked")
            }
        }
    }

    private func upsideWeightRow(_ label: String, value: Binding<Double>, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2)
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            Slider(value: value, in: 0...1.0, step: 0.1)
            Text(desc)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Rebuild Button

    private var rebuildButton: some View {
        Button {
            coordinator.buildChain()
            changedSinceLastBuild = false
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(changedSinceLastBuild ? "Rebuild Chain (params changed)" : "Rebuild Chain")
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(changedSinceLastBuild ? .orange : .blue)
        .disabled(coordinator.markovMatrix == nil || coordinator.session.ramblingGists.isEmpty)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func parameterCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            content()
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}
