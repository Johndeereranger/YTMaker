//
//  MoveLibraryView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Browse and use saved move presets.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct MoveLibraryView: View {
    @EnvironmentObject var nav: NavigationViewModel
    @StateObject private var viewModel = MoveLibraryViewModel()
    @State private var searchText = ""
    @State private var showingCopyConfirmation = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading moves...")
            } else if viewModel.library == nil || viewModel.library?.count == 0 {
                emptyState
            } else {
                libraryContent
            }
        }
        .navigationTitle("Move Library")
        .searchable(text: $searchText, prompt: "Search moves...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    if viewModel.library != nil {
                        Button {
                            copyLibraryToClipboard()
                        } label: {
                            Label("Copy Library", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button(role: .destructive) {
                            viewModel.showingClearConfirmation = true
                        } label: {
                            Label("Clear Library", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Copied!", isPresented: $showingCopyConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Move library copied to clipboard")
        }
        .alert("Clear Library?", isPresented: $viewModel.showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                viewModel.clearLibrary()
            }
        } message: {
            Text("This will delete all saved move presets. This cannot be undone.")
        }
        .task {
            viewModel.load()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Moves Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import an FCPXML file and classify moves to build your library.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                nav.pop()  // Go back to Preset Library to import
            } label: {
                Label("Go to Import", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Project Context Card
                if let context = viewModel.library?.projectContext {
                    projectContextCard(context)
                }

                // Grouped Move Sections
                groupedMoveSections
            }
            .padding()
        }
    }

    // MARK: - Project Style Card

    private func projectContextCard(_ context: ProjectScaleContext) -> some View {
        let style = context.toStyle()

        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "video.fill")
                    .foregroundColor(.blue)
                Text("Project Style: \(context.projectName)")
                    .font(.headline)
                Spacer()
            }

            // Zoom Levels Grid
            HStack(spacing: 12) {
                ForEach([ZoomLevel.wide, .base, .medium, .punch, .extreme], id: \.self) { level in
                    VStack(spacing: 4) {
                        Text(level.displayName.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(levelColor(level))

                        Text("\(Int(style.percentage(for: level)))%")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(levelColor(level))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(levelColor(level).opacity(0.1))
                    .cornerRadius(8)
                }
            }

            // Move legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Zoom Punch: BASE → PUNCH")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.caption)
                        .foregroundColor(.cyan)
                    Text("Zoom Out: PUNCH → BASE")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }

    private func levelColor(_ level: ZoomLevel) -> Color {
        switch level {
        case .wide: return .green
        case .base: return .gray
        case .medium: return .orange
        case .punch: return .blue
        case .extreme: return .purple
        }
    }

    // MARK: - Grouped Move Sections

    private var groupedMoveSections: some View {
        let presets = viewModel.library?.presets ?? []

        // Group presets by logical sections
        let zoomIn = presets.filter { $0.definition == .zoomPunch || $0.definition == .zoomIn }
        let zoomOut = presets.filter { $0.definition == .zoomOut || $0.definition == .zoomReset }
        let reframeLeft = presets.filter { $0.definition == .reframeLeft }
        let reframeRight = presets.filter { $0.definition == .reframeRight }
        let reframeUp = presets.filter { $0.definition == .reframeUp }
        let reframeDown = presets.filter { $0.definition == .reframeDown }
        let ambient = presets.filter { $0.definition == .kenBurns || $0.definition == .positionDrift }
        let rotation = presets.filter { $0.definition == .dutchAngle || $0.definition == .tiltLeft || $0.definition == .tiltRight }
        let other = presets.filter { $0.definition == .zoomAndPan }

        return VStack(alignment: .leading, spacing: 24) {
            // ZOOM Section
            if !zoomIn.isEmpty || !zoomOut.isEmpty {
                moveGroupSection(
                    title: "ZOOM",
                    icon: "plus.magnifyingglass",
                    color: .blue
                ) {
                    HStack(alignment: .top, spacing: 12) {
                        // Zoom In Box
                        if !zoomIn.isEmpty {
                            moveBox(title: "Zoom In", icon: "arrow.up.left.and.arrow.down.right", presets: zoomIn, color: .blue)
                        }
                        // Zoom Out Box
                        if !zoomOut.isEmpty {
                            moveBox(title: "Zoom Out", icon: "arrow.down.right.and.arrow.up.left", presets: zoomOut, color: .cyan)
                        }
                    }
                }
            }

            // POSITION Section
            if !reframeLeft.isEmpty || !reframeRight.isEmpty || !reframeUp.isEmpty || !reframeDown.isEmpty {
                moveGroupSection(
                    title: "POSITION",
                    icon: "arrow.up.and.down.and.arrow.left.and.right",
                    color: .orange
                ) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], spacing: 8) {
                        if !reframeLeft.isEmpty {
                            directionBox(title: "Left", icon: "arrow.left", presets: reframeLeft)
                        }
                        if !reframeRight.isEmpty {
                            directionBox(title: "Right", icon: "arrow.right", presets: reframeRight)
                        }
                        if !reframeUp.isEmpty {
                            directionBox(title: "Up", icon: "arrow.up", presets: reframeUp)
                        }
                        if !reframeDown.isEmpty {
                            directionBox(title: "Down", icon: "arrow.down", presets: reframeDown)
                        }
                    }
                }
            }

            // AMBIENT Section
            if !ambient.isEmpty {
                moveGroupSection(
                    title: "AMBIENT",
                    icon: "leaf",
                    color: .green
                ) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(ambient, id: \.id) { preset in
                            compactPresetCard(preset)
                        }
                    }
                }
            }

            // ROTATION Section
            if !rotation.isEmpty {
                moveGroupSection(
                    title: "ROTATION",
                    icon: "rotate.right",
                    color: .purple
                ) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(rotation, id: \.id) { preset in
                            compactPresetCard(preset)
                        }
                    }
                }
            }

            // OTHER Section
            if !other.isEmpty {
                moveGroupSection(
                    title: "OTHER",
                    icon: "square.stack",
                    color: .gray
                ) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(other, id: \.id) { preset in
                            compactPresetCard(preset)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Move Group Section Container

    private func moveGroupSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
            }

            // Content
            content()
        }
        .padding()
        .background(color.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Move Box (for Zoom In/Out)

    private func moveBox(title: String, icon: String, presets: [MovePreset], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(color)

            ForEach(presets.sorted(by: { $0.confidence > $1.confidence }), id: \.id) { preset in
                presetRow(preset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Direction Box (for Position moves)

    private func directionBox(title: String, icon: String, presets: [MovePreset]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.orange)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Each preset with details
            ForEach(presets.sorted(by: { $0.confidence > $1.confidence }), id: \.id) { preset in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        // Duration + Magnitude
                        HStack(spacing: 4) {
                            Text(preset.duration.displayName)
                                .font(.caption2)
                                .fontWeight(.medium)
                            if let mag = preset.positionMagnitude {
                                Text(mag.displayName)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }

                        // Raw duration
                        if let rawDuration = preset.averageDurationSeconds {
                            Text(formatDuration(rawDuration))
                                .font(.caption2)
                                .foregroundColor(rawDuration > 10 ? .orange : .secondary)
                        }
                    }

                    Spacer()

                    Text("×\(preset.confidence)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button {
                        viewModel.deletePreset(preset)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Preset Row (with full detail)

    private func presetRow(_ preset: MovePreset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Duration bucket
                Text(preset.duration.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                Text("×\(preset.confidence)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    viewModel.deletePreset(preset)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Scale values with zoom level names - THE KEY INFO
            if let scales = preset.scaleValues(using: viewModel.library?.projectContext) {
                HStack(spacing: 4) {
                    // Show zoom level names if available
                    if let fromLevel = preset.definition.fromLevel,
                       let toLevel = preset.definition.toLevel {
                        Text("\(fromLevel.displayName.uppercased())→\(toLevel.displayName.uppercased())")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.purple)
                    }
                    Text("\(Int(scales.from))%→\(Int(scales.to))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            // Raw duration
            if let rawDuration = preset.averageDurationSeconds {
                HStack(spacing: 4) {
                    Text(formatDuration(rawDuration))
                        .font(.caption2)
                    if rawDuration > 10 {
                        Text("⚠️")
                            .font(.caption2)
                    }
                }
                .foregroundColor(rawDuration > 10 ? .orange : .secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.2fs", seconds)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        }
    }

    // MARK: - Compact Preset Card (for Ambient/Rotation)

    private func compactPresetCard(_ preset: MovePreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with name and delete
            HStack {
                Text(preset.definition.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("×\(preset.confidence)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    viewModel.deletePreset(preset)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Duration bucket
            Text(preset.duration.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .cornerRadius(4)

            // Scale values if present
            if let scales = preset.scaleValues(using: viewModel.library?.projectContext) {
                Text("\(Int(scales.from))% → \(Int(scales.to))%")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }

            // Position if present
            if let dir = preset.positionDirection, let mag = preset.positionMagnitude {
                Text("\(dir.rawValue) \(mag.displayName)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            // Raw duration - KEY for identifying trash
            if let rawDuration = preset.averageDurationSeconds {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption2)
                    Text(formatDuration(rawDuration))
                        .font(.caption2)
                        .fontWeight(.medium)
                    if rawDuration > 10 {
                        Text("⚠️ TRASH?")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                .foregroundColor(rawDuration > 10 ? .orange : .secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 140)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Copy Library

    private func copyLibraryToClipboard() {
        guard let library = viewModel.library else { return }

        var output = "MOVE LIBRARY\n"
        output += String(repeating: "=", count: 50) + "\n\n"

        // Project Style with Named Zoom Levels
        if let context = library.projectContext {
            let style = context.toStyle()
            output += "PROJECT STYLE: \(context.projectName)\n"
            output += "  Named Zoom Levels:\n"
            for level in [ZoomLevel.wide, .base, .medium, .punch, .extreme] {
                output += "    \(level.displayName.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)): \(Int(style.percentage(for: level)))%\n"
            }
            output += "\n"
            output += "  Move Mappings:\n"
            output += "    Zoom Punch: BASE → PUNCH (\(Int(style.percentage(for: .base)))% → \(Int(style.percentage(for: .punch)))%)\n"
            output += "    Zoom In:    BASE → MEDIUM (\(Int(style.percentage(for: .base)))% → \(Int(style.percentage(for: .medium)))%)\n"
            output += "    Zoom Out:   PUNCH → BASE (\(Int(style.percentage(for: .punch)))% → \(Int(style.percentage(for: .base)))%)\n"
            output += "\n"
        }

        output += "PRESETS (\(library.count) total):\n"
        output += String(repeating: "-", count: 50) + "\n\n"

        // Group by definition
        let byDefinition = Dictionary(grouping: library.presets, by: { $0.definition })
        let sortedDefinitions = byDefinition.keys.sorted { $0.rawValue < $1.rawValue }

        for definition in sortedDefinitions {
            guard let presets = byDefinition[definition] else { continue }

            output += "\(definition.displayName.uppercased()) (\(presets.count))\n"
            output += "  Category: \(definition.category.displayName)\n"
            // Show zoom level transitions for project-style moves
            if let from = definition.fromLevel, let to = definition.toLevel {
                output += "  Transition: \(from.displayName.uppercased()) → \(to.displayName.uppercased())\n"
            } else {
                output += "  Self-contained (absolute values)\n"
            }
            output += "\n"

            for preset in presets.sorted(by: { $0.confidence > $1.confidence }) {
                output += "  [\(preset.duration.displayName)] ×\(preset.confidence)\n"

                // Show RAW stored values (what's actually in the preset)
                if let absFrom = preset.absoluteScaleFrom, let absTo = preset.absoluteScaleTo {
                    output += "    Stored (absolute): \(Int(absFrom))% → \(Int(absTo))%\n"
                }

                // Show COMPUTED values with zoom level names
                if let scales = preset.scaleValues(using: library.projectContext) {
                    var scaleStr = "    Scale: \(Int(scales.from))% → \(Int(scales.to))%"
                    if let from = definition.fromLevel, let to = definition.toLevel {
                        scaleStr += " (\(from.displayName)→\(to.displayName))"
                    }
                    output += scaleStr + "\n"
                }

                // Position info
                if let dir = preset.positionDirection, let mag = preset.positionMagnitude {
                    output += "    Position: \(dir.rawValue) \(mag.displayName)\n"
                }

                // Rotation info
                if let rotDir = preset.rotationDirection, let rotMag = preset.rotationMagnitude {
                    output += "    Rotation: \(rotDir.rawValue) \(rotMag.rawValue)\n"
                }

                // Tags
                if !preset.tags.isEmpty {
                    output += "    Tags: \(preset.tags.joined(separator: ", "))\n"
                }

                output += "\n"
            }
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif

        showingCopyConfirmation = true
    }
}

// MARK: - Move Filter Chip

struct MoveFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.3))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Move Preset Card

struct MovePresetCard: View {
    let preset: MovePreset
    let projectContext: ProjectScaleContext?
    let onApply: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: preset.definition.icon)
                    .font(.title3)
                    .foregroundColor(.purple)

                Spacer()

                if preset.confidence > 0 {
                    Text("×\(preset.confidence)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(4)
                }

                // Delete button
                Button {
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // Definition Name (the intent)
            Text(preset.definition.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)

            // Raw Duration - THIS IS KEY for identifying trash
            if let rawDuration = preset.averageDurationSeconds {
                HStack {
                    Image(systemName: "timer")
                        .font(.caption2)
                    Text(formatDuration(rawDuration))
                        .font(.caption)
                        .fontWeight(.medium)
                    if rawDuration > 10 {
                        Text("⚠️")
                            .font(.caption2)
                    }
                }
                .foregroundColor(rawDuration > 10 ? .orange : .secondary)
            } else {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(preset.duration.displayName)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            // Scale Values
            if let scales = preset.scaleValues(using: projectContext) {
                HStack {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                    Text("\(Int(scales.from))% → \(Int(scales.to))%")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }

            // Position info if present
            if let direction = preset.positionDirection, let magnitude = preset.positionMagnitude {
                HStack {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption2)
                    Text("\(direction.rawValue) \(magnitude.displayName)")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }

            Spacer()

            // Apply Button
            Button(action: onApply) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Apply")
                }
                .font(.caption)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(minHeight: 160)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .confirmationDialog("Delete this preset?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(preset.definition.displayName) - \(preset.duration.displayName)")
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.2fs", seconds)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        }
    }
}

// MARK: - View Model

@MainActor
class MoveLibraryViewModel: ObservableObject {
    @Published var library: MoveLibrary?
    @Published var isLoading = false
    @Published var showingClearConfirmation = false

    private let service = MoveLibraryService.shared

    func load() {
        isLoading = true
        library = service.load()
        isLoading = false

        if let lib = library {
            print("[MoveLibraryView] Loaded \(lib.count) presets")
        } else {
            print("[MoveLibraryView] No library found")
        }
    }

    func reload() {
        load()
    }

    func clearLibrary() {
        do {
            try service.clearLibrary()
            library = nil
        } catch {
            print("[MoveLibraryView] Failed to clear: \(error)")
        }
    }

    func applyMove(_ preset: MovePreset) {
        // TODO: Implement actual move application
        print("[MoveLibraryView] Apply move: \(preset.name)")
        print("  Definition: \(preset.definition.displayName)")
        print("  Duration: \(preset.duration.seconds)s")

        if let context = library?.projectContext {
            if let scales = preset.scaleValues(using: context) {
                print("  Scale: \(Int(scales.from))% → \(Int(scales.to))%")
            }
        }
    }

    func deletePreset(_ preset: MovePreset) {
        guard var lib = library else { return }

        // Remove the preset
        lib.presets.removeAll { $0.id == preset.id }

        // Save and reload
        do {
            try service.save(lib)
            library = lib
            print("[MoveLibraryView] Deleted preset: \(preset.definition.displayName)")
        } catch {
            print("[MoveLibraryView] Failed to delete: \(error)")
        }
    }
}
