//
//  FidelityWeightConfigView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/18/26.
//
//  Weight slider UI for the Script Fidelity Evaluator.
//  Configurable dimension weights (linked to sum 1.0),
//  hard-fail rule editor, and profile save/load.
//

import SwiftUI

struct FidelityWeightConfigView: View {
    @Binding var weightProfile: FidelityWeightProfile
    @State private var showRuleEditor = false
    @State private var editingRule: HardFailRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            weightSliders
            Divider()
            hardFailSection
            Divider()
            profileNotes
        }
        .padding()
        .sheet(item: $editingRule) { rule in
            HardFailRuleEditor(rule: rule) { updated in
                if let idx = weightProfile.hardFailRules.firstIndex(where: { $0.id == updated.id }) {
                    weightProfile.hardFailRules[idx] = updated
                }
                editingRule = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fidelity Weight Profile")
                    .font(.headline)
                Text("Weights start equal. Adjust from real failure data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Equal Weights") {
                resetToEqual()
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Weight Sliders

    private var weightSliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dimension Weights")
                .font(.subheadline.bold())

            ForEach(FidelityDimension.allCases) { dim in
                weightRow(dim)
            }

            // Sum validation
            let sum = FidelityDimension.allCases.map { weightProfile.weight(for: $0) }.reduce(0, +)
            if abs(sum - 1.0) > 0.01 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Weights sum to \(String(format: "%.1f%%", sum * 100)) — should be 100%")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Normalize") {
                        weightProfile.normalizeWeights()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func weightRow(_ dim: FidelityDimension) -> some View {
        HStack(spacing: 8) {
            Text(dim.shortLabel)
                .font(.caption.monospaced())
                .frame(width: 50, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { weightProfile.weight(for: dim) },
                    set: { newValue in
                        adjustWeight(dim, to: newValue)
                    }
                ),
                in: 0...0.5,
                step: 0.01
            )

            Text(String(format: "%.0f%%", weightProfile.weight(for: dim) * 100))
                .font(.caption.monospaced().bold())
                .frame(width: 40, alignment: .trailing)

            Text(dim.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
        }
    }

    // MARK: - Hard-Fail Section

    private var hardFailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hard-Fail Rules")
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    addNewRule()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
            }

            Text("Rules outside the weighted scoring. A violation vetoes the section regardless of composite score.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(weightProfile.hardFailRules) { rule in
                hardFailRuleRow(rule)
            }
        }
    }

    private func hardFailRuleRow(_ rule: HardFailRule) -> some View {
        HStack(spacing: 8) {
            // Enable toggle
            Toggle(isOn: Binding(
                get: { rule.isEnabled },
                set: { enabled in
                    if let idx = weightProfile.hardFailRules.firstIndex(where: { $0.id == rule.id }) {
                        weightProfile.hardFailRules[idx].isEnabled = enabled
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(SwitchToggleStyle(tint: rule.severity == .fail ? .red : .orange))
            .labelsHidden()

            // Severity badge
            Text(rule.severity == .fail ? "FAIL" : "WARN")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(rule.severity == .fail ? .red : .orange, in: Capsule())

            // Rule description
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.label)
                    .font(.caption.bold())
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)

                let compSymbol = rule.comparison == .greaterThan ? ">" : "<"
                let modeStr = rule.thresholdMode == .absolute
                    ? String(format: "%.2f", rule.threshold)
                    : String(format: "%.1f× corpus", rule.threshold)
                Text("\(rule.metric.displayName) \(compSymbol) \(modeStr)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Edit button
            Button {
                editingRule = rule
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.caption)
            }

            // Delete button
            Button(role: .destructive) {
                weightProfile.hardFailRules.removeAll { $0.id == rule.id }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .opacity(rule.isEnabled ? 1.0 : 0.6)
    }

    // MARK: - Profile Notes

    private var profileNotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.subheadline.bold())
            Text("Document why you chose these weights.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextEditor(text: $weightProfile.notes)
                .font(.caption)
                .frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    // MARK: - Actions

    private func resetToEqual() {
        let equal = 1.0 / Double(FidelityDimension.allCases.count)
        for dim in FidelityDimension.allCases {
            weightProfile.setWeight(equal, for: dim)
        }
    }

    /// Adjust one weight and redistribute others proportionally to keep sum = 1.0.
    private func adjustWeight(_ dimension: FidelityDimension, to newValue: Double) {
        let oldValue = weightProfile.weight(for: dimension)
        let delta = newValue - oldValue
        guard abs(delta) > 0.001 else { return }

        weightProfile.setWeight(newValue, for: dimension)

        // Redistribute delta across other dimensions proportionally
        let otherDims = FidelityDimension.allCases.filter { $0 != dimension }
        let otherSum = otherDims.map { weightProfile.weight(for: $0) }.reduce(0, +)

        if otherSum > 0.001 {
            for dim in otherDims {
                let proportion = weightProfile.weight(for: dim) / otherSum
                let adjusted = weightProfile.weight(for: dim) - delta * proportion
                weightProfile.setWeight(max(0, adjusted), for: dim)
            }
        }
    }

    private func addNewRule() {
        let rule = HardFailRule(
            id: UUID(),
            label: "New Rule",
            metric: .firstPersonRate,
            comparison: .greaterThan,
            threshold: 2.0,
            thresholdMode: .corpusMultiplier,
            isEnabled: true,
            severity: .warn
        )
        weightProfile.hardFailRules.append(rule)
        editingRule = rule
    }
}

// MARK: - Hard-Fail Rule Editor (Sheet)

struct HardFailRuleEditor: View {
    @State var rule: HardFailRule
    let onSave: (HardFailRule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Hard-Fail Rule")
                .font(.headline)

            // Label
            VStack(alignment: .leading, spacing: 4) {
                Text("Label").font(.caption).foregroundStyle(.secondary)
                TextField("Rule name", text: $rule.label)
                    .textFieldStyle(.roundedBorder)
            }

            // Metric
            VStack(alignment: .leading, spacing: 4) {
                Text("Metric").font(.caption).foregroundStyle(.secondary)
                Picker("Metric", selection: $rule.metric) {
                    ForEach(HardFailMetric.allCases) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .pickerStyle(.menu)
            }

            // Comparison
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comparison").font(.caption).foregroundStyle(.secondary)
                    Picker("Comparison", selection: $rule.comparison) {
                        Text(">").tag(HardFailComparison.greaterThan)
                        Text("<").tag(HardFailComparison.lessThan)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 120)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Threshold Mode").font(.caption).foregroundStyle(.secondary)
                    Picker("Mode", selection: $rule.thresholdMode) {
                        ForEach(ThresholdMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Threshold value
            VStack(alignment: .leading, spacing: 4) {
                Text("Threshold: \(String(format: "%.2f", rule.threshold))")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $rule.threshold, in: 0.1...5.0, step: 0.1)
            }

            // Severity
            VStack(alignment: .leading, spacing: 4) {
                Text("Severity").font(.caption).foregroundStyle(.secondary)
                Picker("Severity", selection: $rule.severity) {
                    ForEach(HardFailSeverity.allCases) { sev in
                        Text(sev.displayName).tag(sev)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
    }
}
