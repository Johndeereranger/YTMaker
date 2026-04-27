//
//  MoveLibraryService.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/5/26.
//
//  Converts classification results → saved MoveLibrary
//  Handles persistence of move presets to disk.
//

import Foundation

// MARK: - Move Library Service

class MoveLibraryService {
    static let shared = MoveLibraryService()

    private let fileManager = FileManager.default
    private let libraryFileName = "MoveLibrary.json"

    private var libraryURL: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PresetLibrary")
            .appendingPathComponent(libraryFileName)
    }

    private init() {
        // Ensure directory exists
        if let url = libraryURL?.deletingLastPathComponent() {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Convert Classification → Library

    /// Convert classification results into a MoveLibrary
    /// This is the main pipeline: CanonicalMoves → MovePresets
    func createLibrary(
        from result: MoveClassificationResultV2,
        projectName: String = "Imported",
        sourceFile: String? = nil
    ) -> MoveLibrary {

        // Step 1: Auto-detect project scale context from the data
        let projectContext = detectProjectContext(from: result.canonicalMoves, projectName: projectName)

        // Step 2: Convert each canonical move to a preset
        var presets: [MovePreset] = []

        for canonical in result.canonicalMoves {
            let preset = convertToPreset(canonical, sourceFile: sourceFile)
            presets.append(preset)
        }

        // Step 3: Deduplicate by definition + duration (keep highest confidence)
        let deduplicated = deduplicatePresets(presets)

        print("[MoveLibrary] Created library with \(deduplicated.count) presets from \(result.canonicalMoves.count) canonical moves")
        print("[MoveLibrary] Project context: \(projectContext.scaleDescription)")

        return MoveLibrary(presets: deduplicated, projectContext: projectContext)
    }

    // MARK: - Detect Project Context

    /// Auto-detect the project's scale levels from classification data
    /// Uses ZOOM PUNCH moves specifically - they reliably go from base → emphasis
    private func detectProjectContext(from canonicalMoves: [CanonicalMove], projectName: String) -> ProjectScaleContext {
        // ZOOM PUNCH is the most reliable signal: it goes from base (talking head) to emphasis
        let zoomPunches = canonicalMoves.filter {
            $0.pattern == .zoomPunch &&
            $0.baseScale != nil &&
            $0.targetScale != nil &&
            $0.baseScale! > 0 && $0.baseScale! < 500 &&  // Sanity check - valid scale range
            $0.targetScale! > 0 && $0.targetScale! < 500
        }

        // If we have zoom punches, use them to find base and emphasis
        if !zoomPunches.isEmpty {
            // Weight by occurrence count - more occurrences = more reliable
            var baseWeights: [Int: Int] = [:]
            var emphasisWeights: [Int: Int] = [:]

            for punch in zoomPunches {
                let base = Int(punch.baseScale!)
                let emphasis = Int(punch.targetScale!)
                let weight = punch.occurrenceCount

                baseWeights[base, default: 0] += weight
                emphasisWeights[emphasis, default: 0] += weight
            }

            let detectedBase = baseWeights.max(by: { $0.value < $1.value })?.key ?? 115
            let detectedEmphasis = emphasisWeights.max(by: { $0.value < $1.value })?.key ?? 140

            print("[MoveLibrary] From \(zoomPunches.count) Zoom Punches:")
            print("  Base weights: \(baseWeights)")
            print("  Emphasis weights: \(emphasisWeights)")
            print("  → Detected Base: \(detectedBase)%, Emphasis: \(detectedEmphasis)%")

            return ProjectScaleContext.detected(
                base: Double(detectedBase),
                emphasis: Double(detectedEmphasis),
                projectName: projectName
            )
        }

        // Fallback: look for any scale moves with reasonable values
        let scaleMoves = canonicalMoves.filter {
            $0.baseScale != nil && $0.targetScale != nil &&
            $0.baseScale! > 50 && $0.baseScale! < 300 &&  // Reasonable talking head range
            $0.targetScale! > 50 && $0.targetScale! < 300
        }

        guard !scaleMoves.isEmpty else {
            print("[MoveLibrary] No usable scale moves found, using default context")
            return .default
        }

        // Find most common scales weighted by occurrence
        var fromWeights: [Int: Int] = [:]
        var toWeights: [Int: Int] = [:]

        for move in scaleMoves {
            let from = Int(move.baseScale!)
            let to = Int(move.targetScale!)
            let weight = move.occurrenceCount

            fromWeights[from, default: 0] += weight
            toWeights[to, default: 0] += weight
        }

        let mostCommonFrom = fromWeights.max(by: { $0.value < $1.value })?.key ?? 115
        let mostCommonTo = toWeights.max(by: { $0.value < $1.value })?.key ?? 140

        print("[MoveLibrary] Fallback detection from \(scaleMoves.count) scale moves:")
        print("  From weights: \(fromWeights)")
        print("  To weights: \(toWeights)")
        print("  → Base: \(mostCommonFrom)%, Emphasis: \(mostCommonTo)%")

        return ProjectScaleContext.detected(
            base: Double(mostCommonFrom),
            emphasis: Double(mostCommonTo),
            projectName: projectName
        )
    }

    // MARK: - Convert Canonical → Preset

    /// Convert a single CanonicalMove to a MovePreset
    private func convertToPreset(_ canonical: CanonicalMove, sourceFile: String?) -> MovePreset {
        // Map MovePattern → MoveDefinition
        let definition = mapPatternToDefinition(canonical.pattern)

        // Map DurationBucket → DurationPreset
        let duration = mapDurationBucket(canonical.durationBucket)

        // Determine if this should have absolute values (self-contained)
        var absoluteScaleFrom: Double? = nil
        var absoluteScaleTo: Double? = nil

        if !definition.needsProjectContext {
            // Self-contained moves get absolute values
            absoluteScaleFrom = canonical.baseScale
            absoluteScaleTo = canonical.targetScale
        }

        return MovePreset(
            name: canonical.name,
            definition: definition,
            duration: duration,
            durationFlexible: true,
            easeIn: definition.isAmbient,  // Ambient moves ease in
            easeOut: true,
            positionDirection: canonical.positionDirection,
            positionMagnitude: canonical.positionMagnitude,
            rotationDirection: canonical.rotationDirection,
            rotationMagnitude: canonical.rotationMagnitude,
            absoluteScaleFrom: absoluteScaleFrom,
            absoluteScaleTo: absoluteScaleTo,
            averageDurationSeconds: canonical.averageDuration,
            confidence: canonical.occurrenceCount,
            tags: generateTags(for: definition, duration: duration),
            isFavorite: canonical.occurrenceCount >= 10,  // Auto-favorite frequent moves
            sourceFile: sourceFile
        )
    }

    /// Map classification MovePattern to our MoveDefinition
    private func mapPatternToDefinition(_ pattern: MovePattern) -> MoveDefinition {
        switch pattern {
        case .zoomPunch: return .zoomPunch
        case .zoomIn: return .zoomIn
        case .zoomOut: return .zoomOut
        case .zoomHold: return .zoomReset
        case .kenBurns: return .kenBurns
        case .reframeLeft: return .reframeLeft
        case .reframeRight: return .reframeRight
        case .reframeUp: return .reframeUp
        case .reframeDown: return .reframeDown
        case .positionDrift: return .positionDrift
        case .tiltLeft: return .tiltLeft
        case .tiltRight: return .tiltRight
        case .dutchAngle: return .dutchAngle
        case .zoomAndPan: return .zoomAndPan
        case .customCompound: return .zoomAndPan
        case .unknown: return .zoomPunch  // Default fallback
        }
    }

    /// Map classification DurationBucket to DurationPreset
    private func mapDurationBucket(_ bucket: DurationBucket) -> DurationPreset {
        switch bucket {
        case .instant: return .instant
        case .quick: return .quick
        case .medium: return .medium
        case .slow: return .slow
        case .verySlow: return .ambient
        }
    }

    /// Generate tags based on move type
    private func generateTags(for definition: MoveDefinition, duration: DurationPreset) -> [String] {
        var tags: [String] = []

        // Category tag
        switch definition.category {
        case .scale: tags.append("scale")
        case .position: tags.append("position")
        case .rotation: tags.append("rotation")
        case .compound: tags.append("compound")
        }

        // Ambient vs emphatic
        if definition.isAmbient {
            tags.append("ambient")
        } else {
            tags.append("emphasis")
        }

        // Speed tag
        switch duration {
        case .instant, .quick: tags.append("fast")
        case .medium: break
        case .slow, .verySlow, .ambient: tags.append("slow")
        }

        return tags
    }

    // MARK: - Deduplication

    /// Remove duplicate presets, keeping the one with highest confidence
    private func deduplicatePresets(_ presets: [MovePreset]) -> [MovePreset] {
        // Group by definition + duration
        let grouped = Dictionary(grouping: presets) { preset in
            "\(preset.definition.rawValue)_\(preset.duration.rawValue)"
        }

        // Keep the highest confidence from each group
        return grouped.values.compactMap { group in
            group.max(by: { $0.confidence < $1.confidence })
        }.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Persistence

    /// Save library to disk
    func save(_ library: MoveLibrary) throws {
        guard let url = libraryURL else {
            throw MoveLibraryError.noStorageLocation
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(library)
        try data.write(to: url)

        print("[MoveLibrary] Saved \(library.count) presets to \(url.lastPathComponent)")
    }

    /// Load library from disk
    func load() -> MoveLibrary? {
        guard let url = libraryURL,
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let library = try decoder.decode(MoveLibrary.self, from: data)
            print("[MoveLibrary] Loaded \(library.count) presets")
            return library
        } catch {
            print("[MoveLibrary] Failed to load: \(error)")
            return nil
        }
    }

    /// Merge new presets into existing library
    func merge(_ newLibrary: MoveLibrary, into existingLibrary: MoveLibrary) -> MoveLibrary {
        var combined = existingLibrary.presets + newLibrary.presets

        // Deduplicate
        combined = deduplicatePresets(combined)

        // Use new project context if provided, otherwise keep existing
        let context = newLibrary.projectContext ?? existingLibrary.projectContext

        return MoveLibrary(presets: combined, projectContext: context)
    }

    /// Clear all saved presets
    func clearLibrary() throws {
        guard let url = libraryURL else { return }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            print("[MoveLibrary] Cleared library")
        }
    }
}

// MARK: - Errors

enum MoveLibraryError: Error, LocalizedError {
    case noStorageLocation
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .noStorageLocation: return "Could not determine storage location"
        case .encodingFailed: return "Failed to encode move library"
        case .decodingFailed: return "Failed to decode move library"
        }
    }
}
