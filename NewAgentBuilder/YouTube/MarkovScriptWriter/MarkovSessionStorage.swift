//
//  MarkovSessionStorage.swift
//  NewAgentBuilder
//
//  File-based persistence for MarkovScriptSession.
//  Replaces UserDefaults to avoid the 4MB size limit — chain runs accumulate
//  dead ends, guidance prompts, and raw API responses that easily exceed that ceiling.
//

import Foundation

struct MarkovSessionStorage {

    // MARK: - Directory

    private static var storageDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("MarkovSessions", isDirectory: true)
    }

    private static var sessionFileURL: URL {
        storageDirectory.appendingPathComponent("CurrentSession.json")
    }

    // MARK: - Save

    static func save(_ session: MarkovScriptSession) {
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(session)
            try data.write(to: sessionFileURL, options: .atomic)
        } catch {
            print("[MarkovSessionStorage] Failed to save session: \(error.localizedDescription)")
        }
    }

    // MARK: - Load

    static func load() -> MarkovScriptSession? {
        guard FileManager.default.fileExists(atPath: sessionFileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: sessionFileURL)
            return try JSONDecoder().decode(MarkovScriptSession.self, from: data)
        } catch {
            print("[MarkovSessionStorage] Failed to load session: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete

    static func delete() {
        try? FileManager.default.removeItem(at: sessionFileURL)
    }

    // MARK: - Chain Run Storage (one file per run)

    private static func chainRunsDirectory(sessionId: UUID) -> URL {
        storageDirectory.appendingPathComponent(sessionId.uuidString, isDirectory: true)
            .appendingPathComponent("ChainRuns", isDirectory: true)
    }

    private static func chainRunFileURL(runId: UUID, sessionId: UUID) -> URL {
        chainRunsDirectory(sessionId: sessionId).appendingPathComponent("\(runId.uuidString).json")
    }

    static func saveChainRun(_ run: ChainBuildRun, sessionId: UUID) {
        do {
            let dir = chainRunsDirectory(sessionId: sessionId)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(run)
            try data.write(to: chainRunFileURL(runId: run.id, sessionId: sessionId), options: .atomic)
        } catch {
            print("[MarkovSessionStorage] Failed to save chain run: \(error.localizedDescription)")
        }
    }

    static func loadChainRun(runId: UUID, sessionId: UUID) -> ChainBuildRun? {
        let url = chainRunFileURL(runId: runId, sessionId: sessionId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ChainBuildRun.self, from: data)
        } catch {
            print("[MarkovSessionStorage] Failed to load chain run \(runId): \(error.localizedDescription)")
            return nil
        }
    }

    static func deleteChainRun(runId: UUID, sessionId: UUID) {
        try? FileManager.default.removeItem(at: chainRunFileURL(runId: runId, sessionId: sessionId))
    }

    static func deleteAllChainRuns(sessionId: UUID) {
        try? FileManager.default.removeItem(at: chainRunsDirectory(sessionId: sessionId))
    }

    // MARK: - Migrate from UserDefaults

    /// One-time migration: moves session data from UserDefaults to file storage,
    /// then removes the UserDefaults key so it doesn't sit there wasting space.
    static func migrateFromUserDefaultsIfNeeded(key: String) {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }

        // Only migrate if we don't already have a file
        guard !FileManager.default.fileExists(atPath: sessionFileURL.path) else {
            // File already exists — just clean up the old key
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        do {
            // Validate it decodes before writing
            _ = try JSONDecoder().decode(MarkovScriptSession.self, from: data)
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            try data.write(to: sessionFileURL, options: .atomic)
            UserDefaults.standard.removeObject(forKey: key)
            print("[MarkovSessionStorage] Migrated session from UserDefaults to file storage")
        } catch {
            print("[MarkovSessionStorage] Migration failed: \(error.localizedDescription)")
        }
    }
}
