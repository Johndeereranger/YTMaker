//
//  ArcComparisonStorage.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  File-based persistence for narrative arc comparison runs.
//  Follows OpenerComparisonStorage pattern.
//

import Foundation

struct ArcComparisonStorage {

    // MARK: - Directory Structure

    private static func baseDirectory(pass2: Bool = false) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let name = pass2 ? "ArcPass2" : "ArcComparisons"
        return docs.appendingPathComponent(name, isDirectory: true)
    }

    /// Debug helper — returns the resolved base directory path string.
    static func baseDirectoryPath(pass2: Bool = false) -> String {
        baseDirectory(pass2: pass2).path
    }

    private static func sessionDirectory(sessionId: UUID, pass2: Bool = false) -> URL {
        baseDirectory(pass2: pass2).appendingPathComponent(sessionId.uuidString, isDirectory: true)
    }

    private static func runFileURL(runId: UUID, sessionId: UUID, pass2: Bool = false) -> URL {
        sessionDirectory(sessionId: sessionId, pass2: pass2).appendingPathComponent("\(runId.uuidString).json")
    }

    // MARK: - Save

    static func save(_ run: ArcComparisonRun, sessionId: UUID, pass2: Bool = false) throws {
        let dir = sessionDirectory(sessionId: sessionId, pass2: pass2)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(run)

        let fileURL = runFileURL(runId: run.id, sessionId: sessionId, pass2: pass2)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Load

    static func load(runId: UUID, sessionId: UUID, pass2: Bool = false) -> ArcComparisonRun? {
        let fileURL = runFileURL(runId: runId, sessionId: sessionId, pass2: pass2)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ArcComparisonRun.self, from: data)
        } catch {
            print("[ArcComparisonStorage] Failed to load run \(runId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete

    static func delete(runId: UUID, sessionId: UUID, pass2: Bool = false) {
        let fileURL = runFileURL(runId: runId, sessionId: sessionId, pass2: pass2)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func deleteAll(sessionId: UUID, pass2: Bool = false) {
        let dir = sessionDirectory(sessionId: sessionId, pass2: pass2)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - List

    static func listRunIds(sessionId: UUID, pass2: Bool = false) -> [UUID] {
        let dir = sessionDirectory(sessionId: sessionId, pass2: pass2)
        let label = pass2 ? "Pass2" : "Arc"
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )
        } catch {
            print("[ArcStorage:\(label)] listRunIds — dir=\(dir.path), error=\(error.localizedDescription)")
            return []
        }

        let ids = contents.compactMap { url -> UUID? in
            guard url.pathExtension == "json" else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
        print("[ArcStorage:\(label)] listRunIds — dir=\(dir.lastPathComponent), files=\(contents.count), validIds=\(ids.count)")
        return ids
    }

    /// Scans ALL session subdirectories for runs. Fallback when current session directory is empty.
    static func listAllRunIds(pass2: Bool = false) -> [(runId: UUID, sessionId: UUID)] {
        let label = pass2 ? "Pass2" : "Arc"
        let base = baseDirectory(pass2: pass2)
        let sessionDirs: [URL]
        do {
            sessionDirs = try FileManager.default.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        } catch {
            print("[ArcStorage:\(label)] listAllRunIds — base=\(base.path), error=\(error.localizedDescription)")
            return []
        }

        print("[ArcStorage:\(label)] listAllRunIds — base=\(base.lastPathComponent), sessionDirs=\(sessionDirs.count)")

        var results: [(runId: UUID, sessionId: UUID)] = []
        for dir in sessionDirs {
            guard let sessionId = UUID(uuidString: dir.lastPathComponent) else { continue }
            let files: [URL]
            do {
                files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            } catch {
                print("[ArcStorage:\(label)] listAllRunIds — session=\(dir.lastPathComponent), error=\(error.localizedDescription)")
                continue
            }

            for file in files where file.pathExtension == "json" {
                if let runId = UUID(uuidString: file.deletingPathExtension().lastPathComponent) {
                    results.append((runId: runId, sessionId: sessionId))
                }
            }
        }
        return results
    }
}
