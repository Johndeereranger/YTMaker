//
//  MoveButtonGrid.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Right panel UI with grouped move buttons:
//  - ZOOM IN: 3x2 grid (Instant|Medium|Slow × Medium|Full levels)
//  - ZOOM OUT: Single row to return to base
//  - POSITION: Left|Right|Up|Down buttons
//
//  Uses ProjectStyle to show actual zoom percentages for this video.
//

import SwiftUI

// MARK: - Move Button Grid

/// Right panel showing grouped move buttons for quick application
struct MoveButtonGrid: View {
    @Binding var selectedMovePreset: MovePreset?
    let projectStyle: ProjectStyle
    let onMoveSelected: (MovePreset) -> Void

    // The speeds displayed as columns
    private let speeds: [DurationPreset] = [.instant, .medium, .slow]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ZOOM IN Section
                MoveSection(title: "ZOOM IN", icon: "plus.magnifyingglass") {
                    zoomInGrid
                }

                Divider()

                // ZOOM OUT Section (simplified - just returns to base)
                MoveSection(title: "ZOOM OUT", icon: "minus.magnifyingglass") {
                    zoomOutGrid
                }

                Divider()

                // POSITION Section
                MoveSection(title: "POSITION", icon: "arrow.up.left.and.arrow.down.right") {
                    positionGrid
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 200, maxWidth: 280)
        .background(Color.platformControlBackground)
    }

    // MARK: - Zoom In Grid (3x2)

    private var zoomInGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with speed labels
            HStack(spacing: 4) {
                Text("").frame(width: 80) // Spacer for row labels (wider for percentages)
                ForEach(speeds, id: \.self) { speed in
                    Text(speedLabel(speed))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Row 1: Medium Zoom In (BASE → MEDIUM)
            let mediumPct = Int(projectStyle.percentage(for: .medium))
            zoomRow(
                label: "Medium (\(mediumPct)%)",
                definition: .zoomIn,
                toLevel: .medium
            )

            // Row 2: Full Zoom In (BASE → PUNCH)
            let punchPct = Int(projectStyle.percentage(for: .punch))
            zoomRow(
                label: "Full (\(punchPct)%)",
                definition: .zoomPunch,
                toLevel: .punch
            )
        }
    }

    // MARK: - Zoom Out Grid (simplified - returns to base)

    private var zoomOutGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with speed labels
            HStack(spacing: 4) {
                Text("").frame(width: 80)
                ForEach(speeds, id: \.self) { speed in
                    Text(speedLabel(speed))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Single row: Zoom Out (→ BASE)
            // This works regardless of current zoom level - it transitions to base
            let basePct = Int(projectStyle.percentage(for: .base))
            zoomRow(
                label: "To Base (\(basePct)%)",
                definition: .zoomOut,
                toLevel: .base,
                isZoomOut: true
            )
        }
    }

    // MARK: - Position Grid

    private var positionGrid: some View {
        VStack(spacing: 8) {
            // Direction buttons in cross layout
            HStack(spacing: 4) {
                Spacer()
                positionButton(.reframeUp, icon: "arrow.up", label: "Up")
                Spacer()
            }

            HStack(spacing: 4) {
                positionButton(.reframeLeft, icon: "arrow.left", label: "Left")
                Spacer()
                positionButton(.reframeRight, icon: "arrow.right", label: "Right")
            }

            HStack(spacing: 4) {
                Spacer()
                positionButton(.reframeDown, icon: "arrow.down", label: "Down")
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Helper Views

    private func zoomRow(
        label: String,
        definition: MoveDefinition,
        toLevel: ZoomLevel,
        isZoomOut: Bool = false,
        fromPunch: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            ForEach(speeds, id: \.self) { speed in
                moveButton(
                    definition: definition,
                    duration: speed,
                    toLevel: toLevel,
                    fromPunch: fromPunch
                )
            }
        }
    }

    private func moveButton(
        definition: MoveDefinition,
        duration: DurationPreset,
        toLevel: ZoomLevel,
        fromPunch: Bool = false
    ) -> some View {
        let preset = createPreset(
            definition: definition,
            duration: duration,
            toLevel: toLevel,
            fromPunch: fromPunch
        )

        return Button {
            selectedMovePreset = preset
            onMoveSelected(preset)
        } label: {
            Text(speedLabel(duration))
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    selectedMovePreset?.id == preset.id
                        ? Color.accentColor
                        : Color.platformControl
                )
                .foregroundColor(
                    selectedMovePreset?.id == preset.id
                        ? .white
                        : .primary
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func positionButton(
        _ definition: MoveDefinition,
        icon: String,
        label: String
    ) -> some View {
        let preset = MovePreset(
            name: definition.displayName,
            definition: definition,
            duration: .medium,
            positionDirection: positionDirection(for: definition),
            positionMagnitude: .medium
        )

        return Button {
            selectedMovePreset = preset
            onMoveSelected(preset)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
            .padding(8)
            .frame(width: 60)
            .background(
                selectedMovePreset?.id == preset.id
                    ? Color.accentColor
                    : Color.platformControl
            )
            .foregroundColor(
                selectedMovePreset?.id == preset.id
                    ? .white
                    : .primary
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func speedLabel(_ speed: DurationPreset) -> String {
        switch speed {
        case .instant: return "Inst"
        case .quick: return "Quick"
        case .medium: return "Med"
        case .slow: return "Slow"
        case .verySlow: return "V.Slow"
        case .ambient: return "Amb"
        }
    }

    private func createPreset(
        definition: MoveDefinition,
        duration: DurationPreset,
        toLevel: ZoomLevel,
        fromPunch: Bool
    ) -> MovePreset {
        let name = "\(definition.displayName) (\(speedLabel(duration)))"
        return MovePreset(
            name: name,
            definition: definition,
            duration: duration
        )
    }

    private func positionDirection(for definition: MoveDefinition) -> PositionDirection? {
        switch definition {
        case .reframeLeft: return .left
        case .reframeRight: return .right
        case .reframeUp: return .up
        case .reframeDown: return .down
        default: return nil
        }
    }
}

// MARK: - Move Section Container

struct MoveSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }

            content()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MoveButtonGrid_Previews: PreviewProvider {
    static var previews: some View {
        MoveButtonGrid(
            selectedMovePreset: .constant(nil),
            projectStyle: .default,
            onMoveSelected: { _ in }
        )
        .frame(height: 600)
    }
}
#endif
