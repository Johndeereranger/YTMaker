//
//  GistAvailabilityView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/3/26.
//
//  Debug surface for the FrameExpansionIndex.
//  Shows per-gist frame->category->move mappings (binary eligibility),
//  category coverage summary.
//

import SwiftUI

struct GistAvailabilityView: View {
    @ObservedObject var coordinator: MarkovScriptWriterCoordinator

    @State private var expandedGistIds: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if coordinator.session.ramblingGists.isEmpty {
                    emptyState
                } else if let index = coordinator.expansionIndex {
                    coverageSummary(index: index)
                    gistList(index: index)
                } else {
                    buildPrompt
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Gists Loaded")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Load gists from the Input tab first.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var buildPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Expansion Index Not Built")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Build the index to see how your gists map to rhetorical moves.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                coordinator.rebuildExpansionIndex()
            } label: {
                Label("Build Index", systemImage: "hammer")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Coverage Summary

    private func coverageSummary(index: FrameExpansionIndex) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category Coverage")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                ForEach(RhetoricalCategory.allCases, id: \.self) { category in
                    let count = index.categoryToGistIds[category]?.count ?? 0
                    let isEmpty = count == 0

                    VStack(spacing: 4) {
                        Text("\(count)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(isEmpty ? .red : .primary)
                        Text(category.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isEmpty ? Color.red.opacity(0.08) : Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }

            // Warnings for empty categories
            let emptyCategories = RhetoricalCategory.allCases.filter {
                (index.categoryToGistIds[$0]?.count ?? 0) == 0
            }
            if !emptyCategories.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("No gists for: \(emptyCategories.map(\.rawValue).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
            }

            // Stats row
            HStack(spacing: 16) {
                let movesWithGists = RhetoricalMoveType.allCases.filter {
                    !(index.moveToGists[$0]?.isEmpty ?? true)
                }.count
                statBadge(value: "\(index.totalGists)", label: "Gists")
                statBadge(value: "\(movesWithGists)/25", label: "Moves Covered")
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Gist List

    private func gistList(index: FrameExpansionIndex) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(coordinator.session.ramblingGists) { gist in
                gistCard(gist: gist, index: index)
            }
        }
    }

    private func gistCard(gist: RamblingGist, index: FrameExpansionIndex) -> some View {
        let isExpanded = expandedGistIds.contains(gist.id)
        let catInfo = FrameExpansionIndex.primaryCategory(for: gist.gistA.frame)
        let constraint = index.constraintScore(for: gist.id)
        let moves = index.gistToMoves[gist.id] ?? []

        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Text("Chunk \(gist.chunkIndex + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)

                // Frame badge
                Text(gist.gistA.frame.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)

                // MoveLabel badge (if present)
                if let moveLabel = gist.moveLabel {
                    Text(moveLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                }

                Spacer()

                // Constraint score
                Text("\(constraint) slots")
                    .font(.caption2)
                    .foregroundColor(constraint <= 3 ? .orange : .secondary)

                Button {
                    withAnimation { toggleExpansion(gist.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }

            // Category mapping summary (always visible)
            HStack(spacing: 6) {
                categoryBadge(catInfo.primary, label: "Primary")
                ForEach(catInfo.secondaries, id: \.self) { secondary in
                    categoryBadge(secondary, label: "Secondary")
                }
            }

            // Brief premise
            Text(gist.gistB.premise)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 1)

            // Expanded: eligible moves (binary — no relevance scores)
            if isExpanded {
                Divider()

                // Group eligible moves by category
                let sortedMoves = moves.sorted { $0.displayName < $1.displayName }
                let movesByCategory = Dictionary(grouping: sortedMoves, by: { $0.category })

                ForEach(RhetoricalCategory.allCases, id: \.self) { category in
                    if let categoryMoves = movesByCategory[category], !categoryMoves.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            let isPrimary = category == catInfo.primary
                            let isSecondary = catInfo.secondaries.contains(category)

                            HStack {
                                Text(category.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(categoryColor(category))
                                if isPrimary {
                                    Text("PRIMARY")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.2))
                                        .cornerRadius(3)
                                } else if isSecondary {
                                    Text("SECONDARY")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.yellow.opacity(0.2))
                                        .cornerRadius(3)
                                }
                            }

                            ForEach(categoryMoves, id: \.self) { move in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    Text(move.displayName)
                                        .font(.caption2)
                                    Spacer()
                                }
                            }
                        }
                        .padding(6)
                        .background(categoryColor(category).opacity(0.04))
                        .cornerRadius(6)
                    }
                }

                // Excluded categories
                let coveredCategories = Set(moves.map(\.category))
                let excludedCategories = RhetoricalCategory.allCases.filter { !coveredCategories.contains($0) }
                if !excludedCategories.isEmpty {
                    HStack(spacing: 4) {
                        Text("Excluded:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ForEach(excludedCategories, id: \.self) { cat in
                            Text(cat.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(3)
                        }
                        Text("(frame doesn't map)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Helpers

    private func toggleExpansion(_ id: UUID) {
        if expandedGistIds.contains(id) {
            expandedGistIds.remove(id)
        } else {
            expandedGistIds.insert(id)
        }
    }

    private func categoryColor(_ category: RhetoricalCategory) -> Color {
        switch category {
        case .hook: return .blue
        case .setup: return .green
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .gray
        case .closing: return .red
        }
    }

    private func categoryBadge(_ category: RhetoricalCategory, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(categoryColor(category))
                .frame(width: 6, height: 6)
            Text(category.rawValue)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(categoryColor(category).opacity(0.08))
        .cornerRadius(4)
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
    }
}
