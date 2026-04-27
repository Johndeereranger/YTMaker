//
//  FidelityTestManager.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import Foundation

// MARK: - Stored Fidelity Models

struct StoredFidelityTestRun: Codable, Identifiable {
    var id: UUID = UUID()
    var videoId: String
    var videoTitle: String
    var channelId: String
    var testDate: Date
    var runCount: Int
    var successfulRuns: Int
    var temperature: Double
    var promptType: FidelityPromptType
    var sectionId: String?  // For A1b tests
    var sectionRole: String?  // For A1b tests
    var results: [StoredBoundaryResult]

    // Computed stats
    var varianceCount: Int {
        results.filter { !$0.isStable }.count
    }

    var stableCount: Int {
        results.filter { $0.isStable }.count
    }

    var stabilityPercentage: Double {
        guard !results.isEmpty else { return 0 }
        return Double(stableCount) / Double(results.count) * 100
    }

    var summaryText: String {
        let stable = stableCount
        let total = results.count
        if stable == total {
            return "100% stable (\(total)/\(total))"
        } else {
            return "\(stable)/\(total) stable, \(varianceCount) with variance"
        }
    }
}

enum FidelityPromptType: String, Codable {
    case a1a = "A1a"
    case a1b = "A1b"
}

struct StoredBoundaryResult: Codable, Identifiable {
    var id: String { role }
    var role: String  // Section role (HOOK, SETUP, etc.) or beat position (Beat 1, Beat 2)
    var boundaryDistribution: [Int: Int]  // boundary sentence -> count
    var isStable: Bool
    var dominantBoundary: Int?  // Most common boundary
    var dominantPercentage: Double?  // How dominant is the most common

    // For displaying variance details
    var varianceDetails: String {
        guard !isStable else { return "Stable at [\(dominantBoundary ?? 0)]" }

        let sorted = boundaryDistribution.sorted { $0.value > $1.value }
        return sorted.map { "[\($0.key)]: \($0.value)x" }.joined(separator: ", ")
    }
}

// MARK: - Fidelity Test Manager

class FidelityTestManager {
    static let shared = FidelityTestManager()

    private let userDefaultsKey = "fidelity_test_history_v1"
    private let maxHistoryPerVideo = 10  // Keep last 10 runs per video
    private let maxTotalHistory = 100  // Keep max 100 total runs

    private init() {}

    // MARK: - Save

    func save(run: StoredFidelityTestRun) {
        var history = loadAll()
        history.append(run)

        // Prune old entries per video
        history = pruneHistory(history)

        saveAll(history)
        print("💾 Saved fidelity test: \(run.videoTitle) - \(run.promptType.rawValue)")
    }

    // MARK: - Load

    func loadAll() -> [StoredFidelityTestRun] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }

        do {
            let runs = try JSONDecoder().decode([StoredFidelityTestRun].self, from: data)
            return runs.sorted { $0.testDate > $1.testDate }
        } catch {
            print("❌ Failed to decode fidelity history: \(error)")
            return []
        }
    }

    func loadForVideo(videoId: String) -> [StoredFidelityTestRun] {
        return loadAll().filter { $0.videoId == videoId }
    }

    func loadA1aTests() -> [StoredFidelityTestRun] {
        return loadAll().filter { $0.promptType == .a1a }
    }

    func loadA1bTests() -> [StoredFidelityTestRun] {
        return loadAll().filter { $0.promptType == .a1b }
    }

    /// Get unique videos that have been tested
    func getTestedVideos() -> [(videoId: String, videoTitle: String, testCount: Int, lastTest: Date)] {
        let all = loadAll()
        var videoMap: [String: (title: String, count: Int, lastDate: Date)] = [:]

        for run in all {
            if let existing = videoMap[run.videoId] {
                videoMap[run.videoId] = (
                    title: run.videoTitle,
                    count: existing.count + 1,
                    lastDate: max(existing.lastDate, run.testDate)
                )
            } else {
                videoMap[run.videoId] = (
                    title: run.videoTitle,
                    count: 1,
                    lastDate: run.testDate
                )
            }
        }

        return videoMap.map { (videoId: $0.key, videoTitle: $0.value.title, testCount: $0.value.count, lastTest: $0.value.lastDate) }
            .sorted { $0.lastTest > $1.lastTest }
    }

    // MARK: - Delete

    func deleteRun(id: UUID) {
        var history = loadAll()
        history.removeAll { $0.id == id }
        saveAll(history)
    }

    func deleteAllForVideo(videoId: String) {
        var history = loadAll()
        history.removeAll { $0.videoId == videoId }
        saveAll(history)
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        print("🗑️ Cleared all fidelity test history")
    }

    // MARK: - Cross-Video Analysis

    /// Find roles/boundaries that are consistently problematic across videos
    func findCommonVariancePatterns() -> [String: Int] {
        let a1aTests = loadA1aTests()
        var roleVarianceCounts: [String: Int] = [:]

        for test in a1aTests {
            for result in test.results where !result.isStable {
                roleVarianceCounts[result.role, default: 0] += 1
            }
        }

        return roleVarianceCounts.sorted { $0.value > $1.value }
            .reduce(into: [String: Int]()) { $0[$1.key] = $1.value }
    }

    /// Get stability trend for a specific role across all videos
    func getStabilityTrendForRole(_ role: String) -> [(videoTitle: String, isStable: Bool, dominantBoundary: Int?)] {
        let a1aTests = loadA1aTests()
        var trends: [(videoTitle: String, isStable: Bool, dominantBoundary: Int?)] = []

        // Get most recent test per video
        var latestPerVideo: [String: StoredFidelityTestRun] = [:]
        for test in a1aTests {
            if let existing = latestPerVideo[test.videoId] {
                if test.testDate > existing.testDate {
                    latestPerVideo[test.videoId] = test
                }
            } else {
                latestPerVideo[test.videoId] = test
            }
        }

        for (_, test) in latestPerVideo {
            if let result = test.results.first(where: { $0.role == role }) {
                trends.append((
                    videoTitle: test.videoTitle,
                    isStable: result.isStable,
                    dominantBoundary: result.dominantBoundary
                ))
            }
        }

        return trends
    }

    // MARK: - Private Helpers

    private func saveAll(_ runs: [StoredFidelityTestRun]) {
        do {
            let data = try JSONEncoder().encode(runs)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("❌ Failed to encode fidelity history: \(error)")
        }
    }

    private func pruneHistory(_ history: [StoredFidelityTestRun]) -> [StoredFidelityTestRun] {
        var pruned = history

        // Group by video and keep only last N per video
        let grouped = Dictionary(grouping: pruned) { $0.videoId }
        pruned = []

        for (_, runs) in grouped {
            let sorted = runs.sorted { $0.testDate > $1.testDate }
            pruned.append(contentsOf: sorted.prefix(maxHistoryPerVideo))
        }

        // Also enforce total limit
        if pruned.count > maxTotalHistory {
            pruned = Array(pruned.sorted { $0.testDate > $1.testDate }.prefix(maxTotalHistory))
        }

        return pruned
    }
}

// MARK: - Helper to Convert Runtime Results to Stored Format

extension FidelityTestManager {

    /// Convert A1a fidelity results to storable format
    func createA1aTestRun(
        video: YouTubeVideo,
        results: [A1aFidelityRunResult],
        runCount: Int,
        temperature: Double
    ) -> StoredFidelityTestRun {
        var storedResults: [StoredBoundaryResult] = []

        // Get all roles from first result
        guard let firstRun = results.first else {
            return StoredFidelityTestRun(
                videoId: video.videoId,
                videoTitle: video.title,
                channelId: video.channelId,
                testDate: Date(),
                runCount: runCount,
                successfulRuns: results.count,
                temperature: temperature,
                promptType: .a1a,
                results: []
            )
        }

        for sectionResult in firstRun.sections {
            let role = sectionResult.role

            // Collect all boundaries for this role across runs
            var boundaryDist: [Int: Int] = [:]
            for run in results {
                if let section = run.sections.first(where: { $0.role == role }),
                   let boundary = section.boundarySentence {
                    boundaryDist[boundary, default: 0] += 1
                }
            }

            let isStable = boundaryDist.count == 1
            let dominant = boundaryDist.max(by: { $0.value < $1.value })
            let dominantPct = dominant.map { Double($0.value) / Double(results.count) * 100 }

            storedResults.append(StoredBoundaryResult(
                role: role,
                boundaryDistribution: boundaryDist,
                isStable: isStable,
                dominantBoundary: dominant?.key,
                dominantPercentage: dominantPct
            ))
        }

        return StoredFidelityTestRun(
            videoId: video.videoId,
            videoTitle: video.title,
            channelId: video.channelId,
            testDate: Date(),
            runCount: runCount,
            successfulRuns: results.count,
            temperature: temperature,
            promptType: .a1a,
            results: storedResults
        )
    }

    /// Convert A1b fidelity results to storable format
    func createA1bTestRun(
        video: YouTubeVideo,
        sectionId: String,
        sectionRole: String,
        results: [A1bFidelityRunResult],
        runCount: Int,
        temperature: Double
    ) -> StoredFidelityTestRun {
        var storedResults: [StoredBoundaryResult] = []

        // Find max beat count
        let maxBeats = results.map { $0.beatCount }.max() ?? 0

        for beatIndex in 0..<maxBeats {
            let role = "Beat \(beatIndex + 1)"

            // Collect all boundaries for this beat position
            var boundaryDist: [Int: Int] = [:]
            for run in results {
                guard beatIndex < run.beats.count else { continue }
                if let boundary = run.beats[beatIndex].boundarySentence {
                    boundaryDist[boundary, default: 0] += 1
                }
            }

            let isStable = boundaryDist.count <= 1
            let dominant = boundaryDist.max(by: { $0.value < $1.value })
            let runsWithThisBeat = results.filter { beatIndex < $0.beats.count }.count
            let dominantPct = dominant.map { Double($0.value) / Double(runsWithThisBeat) * 100 }

            storedResults.append(StoredBoundaryResult(
                role: role,
                boundaryDistribution: boundaryDist,
                isStable: isStable,
                dominantBoundary: dominant?.key,
                dominantPercentage: dominantPct
            ))
        }

        return StoredFidelityTestRun(
            videoId: video.videoId,
            videoTitle: video.title,
            channelId: video.channelId,
            testDate: Date(),
            runCount: runCount,
            successfulRuns: results.count,
            temperature: temperature,
            promptType: .a1b,
            sectionId: sectionId,
            sectionRole: sectionRole,
            results: storedResults
        )
    }
}
