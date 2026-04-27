//
//  GapAnalysisStorage.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  File-based persistence for gap analysis runs.
//  Follows ArcComparisonStorage pattern.
//

import Foundation

struct GapAnalysisStorage {

    // MARK: - Directory Structure

    private static var baseDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("GapAnalysis", isDirectory: true)
    }

    private static func sessionDirectory(sessionId: UUID) -> URL {
        baseDirectory.appendingPathComponent(sessionId.uuidString, isDirectory: true)
    }

    private static func runFileURL(runId: UUID, sessionId: UUID) -> URL {
        sessionDirectory(sessionId: sessionId).appendingPathComponent("\(runId.uuidString).json")
    }

    // MARK: - Save

    static func save(_ run: GapAnalysisRun, sessionId: UUID) throws {
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

    static func load(runId: UUID, sessionId: UUID) -> GapAnalysisRun? {
        let fileURL = runFileURL(runId: runId, sessionId: sessionId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GapAnalysisRun.self, from: data)
        } catch {
            print("[GapAnalysisStorage] Failed to load run \(runId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete

    static func delete(runId: UUID, sessionId: UUID) {
        let fileURL = runFileURL(runId: runId, sessionId: sessionId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func deleteAll(sessionId: UUID) {
        let dir = sessionDirectory(sessionId: sessionId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - List

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

    /// Scans ALL session subdirectories for runs. Fallback when current session directory is empty.
    static func listAllRunIds() -> [(runId: UUID, sessionId: UUID)] {
        guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var results: [(runId: UUID, sessionId: UUID)] = []
        for dir in sessionDirs {
            guard let sessionId = UUID(uuidString: dir.lastPathComponent),
                  let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { continue }

            for file in files where file.pathExtension == "json" {
                if let runId = UUID(uuidString: file.deletingPathExtension().lastPathComponent) {
                    results.append((runId: runId, sessionId: sessionId))
                }
            }
        }
        return results
    }
}
