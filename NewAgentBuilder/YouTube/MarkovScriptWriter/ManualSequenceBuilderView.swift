//
//  ManualSequenceBuilderView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/5/26.
//
//  Manual Sequence Builder — walk through script building one gist at a time.
//  Top: gist pool sorted by Markov viability. Bottom: placed sequence with drop zone.
//

import SwiftUI

struct ManualSequenceBuilderView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator
    @StateObject private var viewModel: ManualSequenceBuilderViewModel

    init(coordinator: MarkovScriptWriterCoordinator) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self._viewModel = StateObject(wrappedValue: ManualSequenceBuilderViewModel(coordinator: coordinator))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.hasGists {
                emptyGistsState
            } else if !viewModel.hasMatrix {
                noMatrixState
            } else {
                statsBar
                Divider()
                placedSequenceSection
                Divider()
                gistPoolSection
            }
        }
        .onAppear {
            viewModel.ensureExpansionIndex()
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack {
            Text("\(viewModel.placedGists.count) / \(viewModel.allGists.count) placed")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Coverage: \(Int(viewModel.coveragePercent * 100))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(viewModel.coveragePercent >= 0.8 ? .green : .secondary)

            Spacer()

            if !viewModel.placedGists.isEmpty {
                Button {
                    viewModel.clearAll()
                } label: {
                    Text("Clear All")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Placed Sequence Section

    private var placedSequenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.placedGists.isEmpty {
                emptySequenceHint
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(viewModel.placedGists.enumerated()), id: \.element.id) { index, placed in
                            placedGistChip(placed, index: index)
                        }
                        dropZone
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }

            // Dead end warning
            if let deadEnd = viewModel.deadEndInfo {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Dead end — no corpus sequences continue from \(deadEnd.lookupKey)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
        }
    }

    private var emptySequenceHint: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                dropZone
                Text("Tap a gist above to start building")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private func placedGistChip(_ placed: PlacedGist, index: Int) -> some View {
        let category = placed.moveType?.category ?? .evidence

        return Button {
            viewModel.removeGist(at: index)
        } label: {
            VStack(spacing: 3) {
                Text("\(index + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(viewModel.categoryColor(category))
                    .clipShape(Circle())

                Text(abbreviateMove(placed.moveType))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 55)

                if let prob = placed.markovProbability {
                    Text("\(Int(prob * 100))%")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(viewModel.categoryColor(category).opacity(0.12))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundColor(viewModel.dropTargetActive ? .green : .secondary.opacity(0.3))
            .frame(width: 55, height: 55)
            .overlay(
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundColor(viewModel.dropTargetActive ? .green : .secondary.opacity(0.5))
            )
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first,
                      let uuid = UUID(uuidString: idString) else { return false }
                viewModel.placeGist(uuid)
                return true
            } isTargeted: { isTargeted in
                viewModel.dropTargetActive = isTargeted
            }
    }

    // MARK: - Gist Pool Section

    private var gistPoolSection: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                let entries = viewModel.sortedPoolEntries

                // Section header for viable gists
                let viableCount = entries.filter(\.isViable).count
                let greyedCount = entries.count - viableCount

                if viableCount > 0 {
                    HStack {
                        Text("Viable (\(viableCount))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }

                ForEach(entries) { entry in
                    // Insert greyed section header at the boundary
                    if !entry.isViable && entries.first(where: { !$0.isViable })?.id == entry.id && greyedCount > 0 {
                        HStack {
                            Text("Other (\(greyedCount))")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                    }

                    ManualSequenceGistCard(
                        entry: entry,
                        isExpanded: viewModel.expandedPoolIds.contains(entry.gist.id),
                        onPlace: { viewModel.placeGist(entry.gist.id) },
                        onToggleExpand: { viewModel.togglePoolExpansion(entry.gist.id) }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Empty States

    private var emptyGistsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.quote")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Gists Loaded")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Load gists from the Input tab first, then come back here to manually build your sequence.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatrixState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Markov Matrix Not Built")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Build the matrix from the Markov tab first. The manual builder uses it to sort and rank your gists.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func abbreviateMove(_ moveType: RhetoricalMoveType?) -> String {
        guard let move = moveType else { return "?" }
        // Abbreviate to first word or short form
        let name = move.displayName
        let words = name.split(separator: " ")
        if words.count == 1 { return name }
        // Return first word, capped at 7 chars
        let first = String(words[0])
        return first.count > 7 ? String(first.prefix(6)) + "." : first
    }
}
