//
//  ProjectStyleEditor.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/6/26.
//
//  Sheet for configuring the zoom percentages for a project's style.
//  Each project can have its own zoom levels (base, medium, punch, etc.).
//

import SwiftUI

// MARK: - Project Style Editor

/// Editor for configuring zoom percentages per project
struct ProjectStyleEditor: View {
    @Binding var projectStyle: ProjectStyle
    @Environment(\.dismiss) private var dismiss

    // Local editing state
    @State private var basePct: Double
    @State private var mediumPct: Double
    @State private var punchPct: Double
    @State private var extremePct: Double

    init(projectStyle: Binding<ProjectStyle>) {
        _projectStyle = projectStyle
        let style = projectStyle.wrappedValue
        _basePct = State(initialValue: style.percentage(for: .base))
        _mediumPct = State(initialValue: style.percentage(for: .medium))
        _punchPct = State(initialValue: style.percentage(for: .punch))
        _extremePct = State(initialValue: style.percentage(for: .extreme))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Zoom Levels")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color.platformControlBackground)

            Divider()

            // Zoom level sliders
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Explanation
                    Text("Configure the zoom percentages for each level. These are used by the zoom buttons.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    // Base zoom (the default talking head framing)
                    zoomLevelRow(
                        label: "Base",
                        description: "Default framing - where zooms return to",
                        value: $basePct,
                        range: 100...150,
                        color: .gray
                    )

                    Divider()

                    // Medium zoom
                    zoomLevelRow(
                        label: "Medium",
                        description: "Slight emphasis zoom",
                        value: $mediumPct,
                        range: 110...160,
                        color: .blue
                    )

                    Divider()

                    // Punch/Full zoom
                    zoomLevelRow(
                        label: "Full (Punch)",
                        description: "Strong emphasis - maximum normal zoom",
                        value: $punchPct,
                        range: 120...180,
                        color: .orange
                    )

                    Divider()

                    // Extreme zoom (rarely used)
                    zoomLevelRow(
                        label: "Extreme",
                        description: "Maximum zoom - use sparingly",
                        value: $extremePct,
                        range: 140...200,
                        color: .red
                    )

                    Divider()

                    // Preset buttons
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Presets")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            presetButton("Default", style: .default)
                            presetButton("Tight", style: .tightFraming)
                            presetButton("Wide", style: .wideFraming)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - Zoom Level Row

    private func zoomLevelRow(
        label: String,
        description: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            Slider(value: value, in: range, step: 1)
                .tint(color)
        }
    }

    // MARK: - Preset Button

    private func presetButton(_ name: String, style: ProjectStyle) -> some View {
        Button {
            applyPreset(style)
        } label: {
            VStack(spacing: 2) {
                Text(name)
                    .font(.caption)
                Text(style.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.platformControl)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func applyPreset(_ preset: ProjectStyle) {
        withAnimation(.easeInOut(duration: 0.2)) {
            basePct = preset.percentage(for: .base)
            mediumPct = preset.percentage(for: .medium)
            punchPct = preset.percentage(for: .punch)
            extremePct = preset.percentage(for: .extreme)
        }
    }

    private func saveAndDismiss() {
        // Create new style with updated values
        projectStyle = ProjectStyle(
            id: projectStyle.id,
            name: projectStyle.name,
            zoomLevels: [
                .wide: 100,  // Keep wide at 100
                .base: basePct,
                .medium: mediumPct,
                .punch: punchPct,
                .extreme: extremePct
            ]
        )
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
struct ProjectStyleEditor_Previews: PreviewProvider {
    static var previews: some View {
        ProjectStyleEditor(projectStyle: .constant(.default))
    }
}
#endif
