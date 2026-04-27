//
//  ManualSequenceGistCard.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/5/26.
//
//  Compact expandable gist card for the Manual Sequence Builder pool.
//  Shows viability badge, category color, and supports tap-to-place + drag.
//

import SwiftUI

struct ManualSequenceGistCard: View {
    let entry: PoolEntry
    let isExpanded: Bool
    let onPlace: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Chunk \(entry.gist.chunkIndex + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)

                if let moveLabel = entry.gist.moveLabel {
                    Text(moveLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(moveLabelColor.opacity(0.15))
                        .cornerRadius(4)
                }

                Text(entry.gist.gistA.frame.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)

                Spacer()

                // Viability probability badge
                if entry.isViable, let prob = entry.transitionProbability {
                    Text("\(Int(prob * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(4)
                }

                if let conf = entry.gist.confidence {
                    Text("\(Int(conf * 100))%")
                        .font(.caption2)
                        .foregroundColor(conf >= 0.8 ? .green : conf >= 0.6 ? .orange : .red)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { onToggleExpand() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Matching move type hint
            if entry.isViable, let matchMove = entry.matchingMoveType {
                Text("matches \(matchMove.displayName)")
                    .font(.system(size: 9))
                    .foregroundColor(.green.opacity(0.8))
            }

            // Premise preview
            Text(entry.gist.gistB.premise)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 2)

            // Expanded content
            if isExpanded {
                expandedContent
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .opacity(entry.isViable ? 1.0 : 0.5)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(entry.isViable ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onPlace() }
        .draggable(entry.gist.id.uuidString)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            // GistA
            VStack(alignment: .leading, spacing: 4) {
                Text("GistA (Deterministic)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text("Subject: \(entry.gist.gistA.subject.joined(separator: ", "))")
                    .font(.caption2)
                Text("Premise: \(entry.gist.gistA.premise)")
                    .font(.caption2)
                Text("Frame: \(entry.gist.gistA.frame.rawValue)")
                    .font(.caption2)
            }
            .padding(8)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(6)

            // GistB
            VStack(alignment: .leading, spacing: 4) {
                Text("GistB (Flexible)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                Text("Subject: \(entry.gist.gistB.subject.joined(separator: ", "))")
                    .font(.caption2)
                Text("Premise: \(entry.gist.gistB.premise)")
                    .font(.caption2)
                Text("Frame: \(entry.gist.gistB.frame.rawValue)")
                    .font(.caption2)
            }
            .padding(8)
            .background(Color.green.opacity(0.05))
            .cornerRadius(6)

            // Source text
            VStack(alignment: .leading, spacing: 4) {
                Text("Source Text")
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text(entry.gist.sourceText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)

            // Telemetry
            if let telemetry = entry.gist.telemetry {
                HStack(spacing: 8) {
                    Text(telemetry.dominantStance.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)

                    if telemetry.contrastCount > 0 {
                        Text("contrast:\(telemetry.contrastCount)")
                            .font(.caption2)
                    }
                    if telemetry.questionCount > 0 {
                        Text("questions:\(telemetry.questionCount)")
                            .font(.caption2)
                    }
                    if telemetry.numberCount > 0 {
                        Text("numbers:\(telemetry.numberCount)")
                            .font(.caption2)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var moveLabelColor: Color {
        guard let moveLabel = entry.gist.moveLabel,
              let move = RhetoricalMoveType.parse(moveLabel) else {
            return .purple
        }
        switch move.category {
        case .hook: return .blue
        case .setup: return .green
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .gray
        case .closing: return .red
        }
    }
}
