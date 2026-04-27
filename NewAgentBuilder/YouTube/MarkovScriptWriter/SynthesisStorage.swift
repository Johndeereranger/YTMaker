//
//  SynthesisStorage.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  File-based persistence for synthesis runs.
//  Full SynthesizedScript objects are saved as JSON files in the app Documents directory.
//  This avoids UserDefaults size limits (each run stores full prompts + responses, 100KB+).
//

import Foundation

struct SynthesisStorage {

    // MARK: - Directory Structure

    private static var baseDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SynthesisRuns", isDirectory: true)
    }

    private static func sessionDirectory(sessionId: UUID) -> URL {
        baseDirectory.appendingPathComponent(sessionId.uuidString, isDirectory: true)
    }

    private static func runFileURL(runId: UUID, sessionId: UUID) -> URL {
        sessionDirectory(sessionId: sessionId).appendingPathComponent("\(runId.uuidString).json")
    }

    // MARK: - Save

    static func save(_ run: SynthesizedScript, sessionId: UUID) throws {
        let dir = sessionDirectory(sessionId: sessionId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(run)

        let fileURL = runFileURL(runId: run.id, sessionId: sessionId)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Load

    static func load(runId: UUID, sessionId: UUID) -> SynthesizedScript? {
        let fileURL = runFileURL(runId: runId, sessionId: sessionId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SynthesizedScript.self, from: data)
        } catch {
            print("[SynthesisStorage] Failed to load run \(runId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete Single Run

    static func delete(runId: UUID, sessionId: UUID) {
        let fileURL = runFileURL(runId: runId, sessionId: sessionId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Delete All Runs for Session

    static func deleteAll(sessionId: UUID) {
        let dir = sessionDirectory(sessionId: sessionId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - List Run IDs for Session

    static func listRunIds(sessionId: UUID) -> [UUID] {
        let dir = sessionDirectory(sessionId: sessionId)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return contents.compactMap { url -> UUID? in
            guard url.pathExtension == "json" else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
    }
}
