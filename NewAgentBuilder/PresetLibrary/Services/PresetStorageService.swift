//
//  PresetStorageService.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/3/26.
//
//  Saves and loads presets from local storage.
//  Uses JSON files for persistence.
//

import Foundation

// MARK: - Preset Storage Service

class PresetStorageService {
    static let shared = PresetStorageService()

    private let fileManager = FileManager.default

    /// Directory for storing presets
    private var presetsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let presetsDir = appSupport.appendingPathComponent("PresetLibrary", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: presetsDir.path) {
            try? fileManager.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        }

        return presetsDir
    }

    private init() {}

    // MARK: - Save Presets

    /// Save a transform preset
    func save(_ preset: TransformPreset) throws {
        let url = presetsDirectory.appendingPathComponent("transforms/\(preset.id.uuidString).json")
        try ensureDirectoryExists(url.deletingLastPathComponent())
        let data = try JSONEncoder().encode(preset)
        try data.write(to: url)
    }

    /// Save a text overlay preset
    func save(_ preset: TextOverlayPreset) throws {
        let url = presetsDirectory.appendingPathComponent("textOverlays/\(preset.id.uuidString).json")
        try ensureDirectoryExists(url.deletingLastPathComponent())
        let data = try JSONEncoder().encode(preset)
        try data.write(to: url)
    }

    /// Save a transition preset
    func save(_ preset: TransitionPreset) throws {
        let url = presetsDirectory.appendingPathComponent("transitions/\(preset.id.uuidString).json")
        try ensureDirectoryExists(url.deletingLastPathComponent())
        let data = try JSONEncoder().encode(preset)
        try data.write(to: url)
    }

    /// Save a B-roll preset
    func save(_ preset: BRollPreset) throws {
        let url = presetsDirectory.appendingPathComponent("bRolls/\(preset.id.uuidString).json")
        try ensureDirectoryExists(url.deletingLastPathComponent())
        let data = try JSONEncoder().encode(preset)
        try data.write(to: url)
    }

    /// Save all presets from a parse result
    func saveAll(from result: FCPXMLParseResult) throws -> Int {
        var count = 0

        for preset in result.transforms {
            try save(preset)
            count += 1
        }
        for preset in result.textOverlays {
            try save(preset)
            count += 1
        }
        for preset in result.transitions {
            try save(preset)
            count += 1
        }
        for preset in result.bRolls {
            try save(preset)
            count += 1
        }

        return count
    }

    // MARK: - Load Presets

    /// Load all transform presets
    func loadTransforms() -> [TransformPreset] {
        loadPresets(from: "transforms")
    }

    /// Load all text overlay presets
    func loadTextOverlays() -> [TextOverlayPreset] {
        loadPresets(from: "textOverlays")
    }

    /// Load all transition presets
    func loadTransitions() -> [TransitionPreset] {
        loadPresets(from: "transitions")
    }

    /// Load all B-roll presets
    func loadBRolls() -> [BRollPreset] {
        loadPresets(from: "bRolls")
    }

    /// Load all presets of all types
    func loadAll() -> PresetLibrary {
        PresetLibrary(
            transforms: loadTransforms(),
            textOverlays: loadTextOverlays(),
            transitions: loadTransitions(),
            bRolls: loadBRolls()
        )
    }

    // MARK: - Delete Presets

    /// Delete a preset by ID and type
    func delete(id: UUID, type: EditType) throws {
        let subdir: String
        switch type {
        case .transform: subdir = "transforms"
        case .textOverlay: subdir = "textOverlays"
        case .transition: subdir = "transitions"
        case .bRoll: subdir = "bRolls"
        }

        let url = presetsDirectory.appendingPathComponent("\(subdir)/\(id.uuidString).json")
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Delete all presets
    func deleteAll() throws {
        if fileManager.fileExists(atPath: presetsDirectory.path) {
            try fileManager.removeItem(at: presetsDirectory)
        }
    }

    // MARK: - Helpers

    private func loadPresets<T: Decodable>(from subdirectory: String) -> [T] {
        let dir = presetsDirectory.appendingPathComponent(subdirectory)
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> T? in
                guard let data = try? Data(contentsOf: url),
                      let preset = try? JSONDecoder().decode(T.self, from: data) else {
                    return nil
                }
                return preset
            }
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Preset Library

/// Container for all loaded presets
struct PresetLibrary {
    var transforms: [TransformPreset]
    var textOverlays: [TextOverlayPreset]
    var transitions: [TransitionPreset]
    var bRolls: [BRollPreset]

    var totalCount: Int {
        transforms.count + textOverlays.count + transitions.count + bRolls.count
    }

    var isEmpty: Bool {
        totalCount == 0
    }

    /// All presets as a flat array
    var allPresets: [any EditPreset] {
        var all: [any EditPreset] = []
        all.append(contentsOf: transforms)
        all.append(contentsOf: textOverlays)
        all.append(contentsOf: transitions)
        all.append(contentsOf: bRolls)
        return all
    }

    /// Filter presets by search text
    func filtered(by searchText: String) -> PresetLibrary {
        guard !searchText.isEmpty else { return self }

        let lowercased = searchText.lowercased()

        return PresetLibrary(
            transforms: transforms.filter { $0.name.lowercased().contains(lowercased) || $0.tags.contains { $0.lowercased().contains(lowercased) } },
            textOverlays: textOverlays.filter { $0.name.lowercased().contains(lowercased) || $0.tags.contains { $0.lowercased().contains(lowercased) } },
            transitions: transitions.filter { $0.name.lowercased().contains(lowercased) || $0.tags.contains { $0.lowercased().contains(lowercased) } },
            bRolls: bRolls.filter { $0.name.lowercased().contains(lowercased) || $0.tags.contains { $0.lowercased().contains(lowercased) } }
        )
    }

    /// Filter to favorites only
    func favoritesOnly() -> PresetLibrary {
        PresetLibrary(
            transforms: transforms.filter { $0.isFavorite },
            textOverlays: textOverlays.filter { $0.isFavorite },
            transitions: transitions.filter { $0.isFavorite },
            bRolls: bRolls.filter { $0.isFavorite }
        )
    }

    /// Filter by edit type
    func filtered(by type: EditType) -> [any EditPreset] {
        switch type {
        case .transform: return transforms
        case .textOverlay: return textOverlays
        case .transition: return transitions
        case .bRoll: return bRolls
        }
    }
}
