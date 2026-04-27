//
//  MoveClassificationResultsView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Dedicated view for displaying move classification results.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct MoveClassificationResultsView: View {
    let result: MoveClassificationResultV2
    let sourceFile: String?

    @Environment(\.dismiss) private var dismiss
    @State private var showingCopyConfirmation = false
    @State private var showingSaveConfirmation = false
    @State private var savedLibrary: MoveLibrary?
    @State private var saveError: String?
    @State private var showingSaveError = false
    @State private var selectedPattern: MovePattern?

    init(result: MoveClassificationResultV2, sourceFile: String? = nil) {
        self.result = result
        self.sourceFile = sourceFile
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Summary Card
                    summaryCard

                    // Save as Presets button
                    savePresetsButton

                    // Pattern breakdown
                    patternBreakdown

                    // All canonical moves
                    allMovesSection
                }
                .padding()
            }
            .navigationTitle("Classification Results")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyResults()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
            .alert("Copied!", isPresented: $showingCopyConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Classification results copied to clipboard")
            }
            .alert("Saved!", isPresented: $showingSaveConfirmation) {
                Button("View Library") {
                    // TODO: Navigate to library
                }
                Button("OK", role: .cancel) {}
            } message: {
                if let library = savedLibrary {
                    Text("Saved \(library.count) move presets to your library.\n\nBase: \(Int(library.projectContext?.baseScale ?? 100))% → Emphasis: \(Int(library.projectContext?.emphasisScale ?? 140))%\n\nGo to Preset Library → Moves to use them.")
                }
            }
            .alert("Save Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Unknown error")
            }
        }
    }

    // MARK: - Save Presets Button

    /// Preview what the library will look like after deduplication
    private var previewLibrary: MoveLibrary {
        let service = MoveLibraryService.shared
        let projectName = sourceFile?.replacingOccurrences(of: ".fcpxml", with: "") ?? "Imported"
        return service.createLibrary(from: result, projectName: projectName, sourceFile: sourceFile)
    }

    private var savePresetsButton: some View {
        let preview = previewLibrary

        return Button {
            saveAsPresets()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save \(preview.count) Move Presets")
                            .font(.headline)
                        Text("(consolidated from \(result.canonicalMoves.count) patterns)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.6))
                }

                // Breakdown by definition type (not pattern)
                Text(presetBreakdownSummary(from: preview))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    /// Generate a summary like "3 Zoom Punch, 2 Ken Burns, 1 Zoom Out..."
    private func presetBreakdownSummary(from library: MoveLibrary) -> String {
        let byDefinition = Dictionary(grouping: library.presets, by: { $0.definition })
        let sorted = byDefinition.sorted { $0.value.count > $1.value.count }

        let parts = sorted.prefix(5).map { definition, presets in
            "\(presets.count) \(definition.displayName)"
        }

        var summary = parts.joined(separator: ", ")
        if sorted.count > 5 {
            let remaining = sorted.dropFirst(5).reduce(0) { $0 + $1.value.count }
            summary += ", +\(remaining) more"
        }

        return summary
    }

    private func saveAsPresets() {
        let service = MoveLibraryService.shared

        // Create library from classification results
        let projectName = sourceFile?.replacingOccurrences(of: ".fcpxml", with: "") ?? "Imported"
        let library = service.createLibrary(
            from: result,
            projectName: projectName,
            sourceFile: sourceFile
        )

        // Check if there's an existing library to merge with
        if let existing = service.load() {
            let merged = service.merge(library, into: existing)
            do {
                try service.save(merged)
                savedLibrary = merged
                showingSaveConfirmation = true
            } catch {
                saveError = error.localizedDescription
                showingSaveError = true
            }
        } else {
            // First time - just save
            do {
                try service.save(library)
                savedLibrary = library
                showingSaveConfirmation = true
            } catch {
                saveError = error.localizedDescription
                showingSaveError = true
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            HStack(spacing: 0) {
                statBox("Transforms", value: result.originalTransformCount, color: .gray)
                statBox("Segments", value: result.totalSegmentsExtracted, color: .blue)
                statBox("Animated", value: result.animatedSegments, color: .orange)
                statBox("Canonical", value: result.canonicalMoves.count, color: .green)
            }

            let totalOccurrences = result.canonicalMoves.reduce(0) { $0 + $1.occurrenceCount }
            Text("\(result.canonicalMoves.count) unique patterns from \(totalOccurrences) total occurrences")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private func statBox(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Pattern Breakdown

    private var patternBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Pattern")
                .font(.headline)

            ForEach(MovePattern.allCases, id: \.self) { pattern in
                let moves = result.canonicalMoves.filter { $0.pattern == pattern }
                if !moves.isEmpty {
                    patternRow(pattern: pattern, moves: moves)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private func patternRow(pattern: MovePattern, moves: [CanonicalMove]) -> some View {
        let totalOccurrences = moves.reduce(0) { $0 + $1.occurrenceCount }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: pattern.icon)
                    .foregroundColor(.purple)
                    .frame(width: 24)

                Text(pattern.displayName)
                    .fontWeight(.medium)

                Spacer()

                Text("\(moves.count) unique")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("(\(totalOccurrences) total)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)
            }

            // Show moves for this pattern
            ForEach(Array(moves.enumerated()), id: \.offset) { _, move in
                HStack {
                    Text("• \(move.name)")
                        .font(.subheadline)

                    Text("(\(move.durationBucket.displayName))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("×\(move.occurrenceCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - All Moves Section

    private var allMovesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Canonical Moves (\(result.canonicalMoves.count))")
                .font(.headline)

            ForEach(Array(result.canonicalMoves.enumerated()), id: \.offset) { index, move in
                moveDetailCard(index: index, move: move)
            }
        }
    }

    private func moveDetailCard(index: Int, move: CanonicalMove) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: move.pattern.icon)
                    .foregroundColor(.purple)

                Text("\(index + 1). \(move.name)")
                    .font(.headline)

                Spacer()

                Text("×\(move.occurrenceCount)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.purple)
                    .cornerRadius(8)
            }

            HStack(spacing: 16) {
                Label(move.pattern.displayName, systemImage: "tag")
                Label(move.durationBucket.displayName, systemImage: "clock")
                Label(String(format: "%.2fs avg", move.averageDuration), systemImage: "timer")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if let base = move.baseScale, let target = move.targetScale {
                HStack {
                    Text("Scale:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(base))% → \(Int(target))%")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            if let dir = move.positionDirection, let mag = move.positionMagnitude {
                HStack {
                    Text("Position:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(dir.rawValue) \(mag.displayName)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            if let dir = move.rotationDirection, let mag = move.rotationMagnitude {
                HStack {
                    Text("Rotation:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(dir.rawValue) \(mag.rawValue)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Copy

    private func copyResults() {
        let output = MoveClassifierService.shared.debugDescription(result)

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif

        showingCopyConfirmation = true
        print("Copied classification results (\(output.count) characters)")
    }
}
