//
//  FidelityStorage.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/18/26.
//
//  File-based persistence for the Script Fidelity Evaluator.
//  Follows OpenerComparisonStorage pattern.
//  Stores FidelityCorpusCache per creator and FidelityWeightProfile globally.
//

import Foundation

struct FidelityStorage {

    // MARK: - Directory Structure

    private static var baseDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("FidelityData", isDirectory: true)
    }

    private static var baselinesDirectory: URL {
        baseDirectory.appendingPathComponent("Baselines", isDirectory: true)
    }

    private static var weightProfilesDirectory: URL {
        baseDirectory.appendingPathComponent("WeightProfiles", isDirectory: true)
    }

    private static func cacheFileURL(creatorId: String) -> URL {
        baselinesDirectory.appendingPathComponent("\(creatorId)_cache.json")
    }

    private static func weightProfileFileURL(id: UUID) -> URL {
        weightProfilesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private static var activeProfileIdURL: URL {
        weightProfilesDirectory.appendingPathComponent("active_profile_id.txt")
    }

    // MARK: - Encoder / Decoder

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Corpus Cache (per creator)

    // NOTE: The on-disk JSON schema mirrors FidelityCorpusCache → CorpusStats exactly.
    // If you add/remove/rename fields in CorpusStats (ScriptFidelityModels.swift),
    // old cache files become unreadable. loadCorpusCache auto-deletes stale files,
    // but the user must re-run "Compute Fidelity Baseline" to regenerate.
    static func saveCorpusCache(_ cache: FidelityCorpusCache) {
        do {
            try FileManager.default.createDirectory(at: baselinesDirectory, withIntermediateDirectories: true)
            let data = try encoder.encode(cache)
            let url = cacheFileURL(creatorId: cache.creatorId)
            try data.write(to: url, options: .atomic)
            print("[FidelityStorage] Saved corpus cache for \(cache.creatorId) (\(cache.sentenceCount) sentences)")
        } catch {
            print("[FidelityStorage] Failed to save corpus cache: \(error.localizedDescription)")
        }
    }

    // NOTE: Decoding fails when CorpusStats (ScriptFidelityModels.swift) gains new fields
    // that the saved JSON doesn't have. When that happens the stale file is auto-deleted
    // so the error only fires once. The user must re-run "Compute Fidelity Baseline"
    // in the Structure Workbench to regenerate. Keep in sync with saveCorpusCache above.
    static func loadCorpusCache(creatorId: String) -> FidelityCorpusCache? {
        let url = cacheFileURL(creatorId: creatorId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(FidelityCorpusCache.self, from: data)
        } catch {
            // Schema changed since this file was saved — delete the stale cache
            // so the error doesn't repeat every time selectedChannelIds fires didSet.
            print("[FidelityStorage] Stale cache for \(creatorId) — schema mismatch, deleting. Re-run Compute Fidelity Baseline.")
            if let decodingError = error as? DecodingError {
                print("[FidelityStorage] Detail: \(decodingError)")
            }
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    // MARK: - Weight Profiles

    static func saveWeightProfile(_ profile: FidelityWeightProfile) {
        do {
            try FileManager.default.createDirectory(at: weightProfilesDirectory, withIntermediateDirectories: true)
            let data = try encoder.encode(profile)
            let url = weightProfileFileURL(id: profile.id)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[FidelityStorage] Failed to save weight profile: \(error.localizedDescription)")
        }
    }

    static func loadWeightProfile(id: UUID) -> FidelityWeightProfile? {
        let url = weightProfileFileURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(FidelityWeightProfile.self, from: data)
        } catch {
            print("[FidelityStorage] Failed to load weight profile \(id): \(error.localizedDescription)")
            return nil
        }
    }

    static func listWeightProfiles() -> [FidelityWeightProfile] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: weightProfilesDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return contents.compactMap { url -> FidelityWeightProfile? in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(FidelityWeightProfile.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Active Profile Tracking

    static func setActiveProfileId(_ id: UUID) {
        do {
            try FileManager.default.createDirectory(at: weightProfilesDirectory, withIntermediateDirectories: true)
            try id.uuidString.write(to: activeProfileIdURL, atomically: true, encoding: .utf8)
        } catch {
            print("[FidelityStorage] Failed to save active profile id: \(error.localizedDescription)")
        }
    }

    static func loadActiveWeightProfile() -> FidelityWeightProfile? {
        guard let idString = try? String(contentsOf: activeProfileIdURL, encoding: .utf8),
              let id = UUID(uuidString: idString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return loadWeightProfile(id: id)
    }

    // MARK: - Delete

    static func deleteWeightProfile(id: UUID) {
        let url = weightProfileFileURL(id: id)
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteCorpusCache(creatorId: String) {
        let url = cacheFileURL(creatorId: creatorId)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - S2 Annotation Cache

    private static var s2CacheDirectory: URL {
        baseDirectory.appendingPathComponent("S2Cache", isDirectory: true)
    }

    private static func s2CacheFileURL(textHash: String) -> URL {
        s2CacheDirectory.appendingPathComponent("\(textHash).json")
    }

    /// Compute a stable hash key for a section of text.
    static func s2TextHash(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Simple deterministic hash — stable across runs, no CryptoKit dependency.
        var hash: UInt64 = 5381
        for byte in trimmed.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    static func saveS2Cache(_ entry: S2CacheEntry) {
        do {
            try FileManager.default.createDirectory(at: s2CacheDirectory, withIntermediateDirectories: true)
            let data = try encoder.encode(entry)
            let url = s2CacheFileURL(textHash: entry.textHash)
            try data.write(to: url, options: .atomic)
            print("[FidelityStorage] Saved S2 cache for hash \(entry.textHash) (\(entry.s2Signatures.count) sigs)")
        } catch {
            print("[FidelityStorage] Failed to save S2 cache: \(error.localizedDescription)")
        }
    }

    static func loadS2Cache(textHash: String) -> S2CacheEntry? {
        let url = s2CacheFileURL(textHash: textHash)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(S2CacheEntry.self, from: data)
        } catch {
            print("[FidelityStorage] Failed to load S2 cache for \(textHash): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
