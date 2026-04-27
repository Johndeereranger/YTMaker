//
//  ArcComparisonViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  ViewModel for the Narrative Arc Comparison tab.
//  Manages dependency loading, run orchestration, and state.
//

import Foundation
import SwiftUI

@MainActor
class ArcComparisonViewModel: ObservableObject {

    // MARK: - Dependencies

    let coordinator: MarkovScriptWriterCoordinator
    let isPass2: Bool

    // MARK: - Configuration

    @Published var selectedModel: AIModel = .claude4Sonnet
    @Published var enabledPaths: Set<ArcPath> = Set(ArcPath.allCases)
    @Published var includeGapRambling: Bool = false

    // MARK: - Loaded Data

    @Published var creatorProfile: CreatorNarrativeProfile?
    @Published var representativeSpines: [NarrativeSpine] = []
    @Published var allThroughlines: [(videoId: String, throughline: String)] = []
    @Published var spineTransitionMatrix: SpineTransitionMatrix?
    @Published var spineCount: Int = 0

    /// Gap findings from gap analysis — G6 synthesis preferred (populated for Pass 2 runs).
    @Published var gapFindings: [GapFinding] = []

    /// ALL gap findings from ALL gap paths (for Q→A matching in enrichment).
    @Published var allGapFindings: [GapFinding] = []

    /// First-pass spine that gap detection analyzed (for V6–V10 enrichment positional reference).
    @Published var firstPassSpine: NarrativeSpine?

    @Published var isLoadingDependencies = false
    @Published var dependencyError: String?
    @Published var dependenciesLoaded = false

    // MARK: - Run State

    @Published var isRunning = false
    @Published var progressMessage = ""
    @Published var pathStatuses: [ArcPath: ArcPathRunStatus] = [:]
    @Published var completedCount = 0

    // MARK: - Results

    @Published var currentRun: ArcComparisonRun?
    @Published var runHistory: [ArcComparisonRunSummary] = []

    // MARK: - Error

    @Published var errorMessage: String?

    // MARK: - Computed

    /// Whether any V-paths (V6–V12) are enabled.
    var hasEnabledVPaths: Bool {
        enabledPaths.contains(where: \.isPass2Only)
    }

    /// Whether any enriched V-paths (V6–V10) are enabled — these need the enrichment preprocessing.
    var hasEnabledEnrichedPaths: Bool {
        enabledPaths.contains(where: \.isEnrichedPath)
    }

    var canRun: Bool {
        dependenciesLoaded &&
        !isRunning &&
        !enabledPaths.isEmpty &&
        !coordinator.session.rawRamblingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!isPass2 || hasGapRambling) &&
        (!hasEnabledVPaths || firstPassSpine != nil)
    }

    var prerequisiteMessage: String? {
        if coordinator.selectedChannelIds.isEmpty {
            return "Select a channel in the Input tab first."
        }
        if coordinator.session.rawRamblingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter raw rambling text in the Input tab first."
        }
        if isPass2 && !hasGapRambling {
            return "Enter gap rambling in the Respond tab first."
        }
        if hasEnabledVPaths && firstPassSpine == nil {
            return "V-paths require a first-pass spine. Complete Phase 1 and Gap Detection first."
        }
        return nil
    }

    var totalExpectedCalls: Int {
        let pathCalls = enabledPaths.reduce(0) { $0 + $1.callCount }
        let hasAnyVPath = enabledPaths.contains(where: \.isPass2Only)
        let preprocessingCalls = hasAnyVPath ? 2 : 0  // shared base inventory + supplemental inventory
        return pathCalls + preprocessingCalls
    }

    var hasGapRambling: Bool {
        !coordinator.session.arcGapRamblingText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var gapRamblingWordCount: Int {
        coordinator.session.arcGapRamblingText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var effectiveRamblingText: String {
        let base = coordinator.session.rawRamblingText
        let shouldInclude = isPass2 ? hasGapRambling : (includeGapRambling && hasGapRambling)
        guard shouldInclude else { return base }
        return base
            + "\n\n---\n\nSUPPLEMENTAL RAMBLING (responding to narrative gaps):\n\n"
            + coordinator.session.arcGapRamblingText
    }

    // MARK: - Init

    init(coordinator: MarkovScriptWriterCoordinator, isPass2: Bool = false) {
        self.coordinator = coordinator
        self.isPass2 = isPass2
        if isPass2 {
            self.includeGapRambling = true
            // Default Pass 2 to V6–V10 enabled, P1–P5 off
            self.enabledPaths = Set(ArcPath.allCases.filter(\.isPass2Only))
        } else {
            self.enabledPaths = Set(ArcPath.pass1Cases)
        }
    }

    // MARK: - Load Dependencies

    func loadDependencies() async {
        guard let channelId = coordinator.selectedChannelIds.first else {
            dependencyError = "No channel selected"
            return
        }

        isLoadingDependencies = true
        dependencyError = nil

        do {
            // 1. Load Creator Narrative Profile
            guard let profile = try await CreatorNarrativeProfileFirebaseService.shared.loadProfile(channelId: channelId) else {
                dependencyError = "No Creator Narrative Profile found for this channel. Build one first in the Ingestion pipeline."
                isLoadingDependencies = false
                return
            }
            self.creatorProfile = profile

            // 2. Load all spines (needed for throughlines + matrix + representative spine lookup)
            let allSpines = try await NarrativeSpineFirebaseService.shared.loadSpines(channelId: channelId)
            self.spineCount = allSpines.count
            self.allThroughlines = allSpines.map { ($0.videoId, $0.throughline) }

            // 3. Look up representative spines from loaded corpus
            let repVideoIds = Set(profile.representativeSpines.map(\.videoId))
            self.representativeSpines = allSpines.filter { repVideoIds.contains($0.videoId) }

            // 4. Load or rebuild SpineTransitionMatrix
            if let cached = SpineTransitionMatrix.loadCached(channelId: channelId),
               cached.sourceSpineCount == allSpines.count {
                self.spineTransitionMatrix = cached
            } else {
                let matrix = SpineTransitionMatrix.build(from: allSpines)
                matrix.saveToCache(channelId: channelId)
                self.spineTransitionMatrix = matrix
            }

            // 5. Load run history (also callable independently via loadRunHistory())
            loadRunHistory()

            self.dependenciesLoaded = true

        } catch {
            dependencyError = "Failed to load dependencies: \(error.localizedDescription)"
        }

        isLoadingDependencies = false
    }

    /// Load run history from local storage. Safe to call independently — no network dependencies.
    /// Falls back to scanning all session directories if the current session has none (handles session UUID changes).
    func loadRunHistory() {
        let label = isPass2 ? "Pass2" : "Arc"
        let sessionId = coordinator.session.id
        let basePath = ArcComparisonStorage.baseDirectoryPath(pass2: isPass2)
        let baseExists = FileManager.default.fileExists(atPath: basePath)
        print("[ArcVM:\(label)] loadRunHistory — baseDir=\(basePath), exists=\(baseExists), session=\(sessionId.uuidString.prefix(8))")
        let runIds = ArcComparisonStorage.listRunIds(sessionId: sessionId, pass2: isPass2)
        print("[ArcVM:\(label)] loadRunHistory — directMatch=\(runIds.count) runs")

        if !runIds.isEmpty {
            self.runHistory = runIds.compactMap { runId -> ArcComparisonRunSummary? in
                guard let run = ArcComparisonStorage.load(runId: runId, sessionId: sessionId, pass2: isPass2) else {
                    print("[ArcVM:\(label)] Failed to decode run \(runId.uuidString.prefix(8)) from session \(sessionId.uuidString.prefix(8))")
                    return nil
                }
                return ArcComparisonRunSummary(from: run, sessionId: sessionId)
            }.sorted { $0.createdAt > $1.createdAt }
        } else {
            // Fallback: scan all session directories (recovers orphaned runs after session UUID change)
            let allRuns = ArcComparisonStorage.listAllRunIds(pass2: isPass2)
            print("[ArcVM:\(label)] Fallback scan — found \(allRuns.count) runs across all sessions")
            self.runHistory = allRuns.compactMap { entry -> ArcComparisonRunSummary? in
                guard let run = ArcComparisonStorage.load(runId: entry.runId, sessionId: entry.sessionId, pass2: isPass2) else {
                    print("[ArcVM:\(label)] Failed to decode run \(entry.runId.uuidString.prefix(8)) from session \(entry.sessionId.uuidString.prefix(8))")
                    return nil
                }
                return ArcComparisonRunSummary(from: run, sessionId: entry.sessionId)
            }.sorted { $0.createdAt > $1.createdAt }
        }
        print("[ArcVM:\(label)] loadRunHistory complete — \(self.runHistory.count) runs loaded")
    }

    // MARK: - Run

    func startRun() async {
        guard canRun, let profile = creatorProfile, let matrix = spineTransitionMatrix else { return }

        let channelId = coordinator.selectedChannelIds.first ?? ""

        isRunning = true
        errorMessage = nil
        completedCount = 0
        pathStatuses = Dictionary(uniqueKeysWithValues: enabledPaths.map { ($0, ArcPathRunStatus.pending) })

        // Mark all enabled paths as running
        for path in enabledPaths {
            pathStatuses[path] = .running
        }

        var runner = ArcComparisonRunner(
            model: selectedModel,
            rawRambling: effectiveRamblingText,
            baseRambling: coordinator.session.rawRamblingText,
            channelId: channelId,
            creatorProfile: profile,
            representativeSpines: representativeSpines,
            allThroughlines: allThroughlines,
            enabledPaths: enabledPaths,
            gapFindings: gapFindings,
            allGapFindings: allGapFindings,
            supplementalText: coordinator.session.arcGapRamblingText,
            firstPassSpine: firstPassSpine,
            fetchSpinesByIds: { [weak self] videoIds in
                await self?.fetchSpinesByIds(videoIds) ?? []
            }
        )

        // Wire progress callbacks
        runner.onCallComplete = { [weak self] path, label in
            Task { @MainActor in
                self?.completedCount += 1
                self?.progressMessage = "\(path.rawValue): \(label)"
            }
        }
        runner.onPathComplete = { [weak self] path, status in
            Task { @MainActor in
                self?.pathStatuses[path] = status
            }
        }

        // Run all paths (shared preprocessing + per-path pipeline)
        let (results, preprocessingCalls) = await runner.run()

        // Validate each completed spine
        var validatedResults = results
        for i in 0..<validatedResults.count {
            if let spine = validatedResults[i].outputSpine {
                let contentAtoms: [String]?
                if let inventory = validatedResults[i].intermediateOutputs["contentInventory"] {
                    contentAtoms = Self.parseContentAtomList(inventory)
                } else {
                    contentAtoms = nil
                }
                validatedResults[i].validationResult = SpineTransitionValidator.validate(
                    spine: spine,
                    matrix: matrix,
                    contentAtoms: contentAtoms
                )
            }
            pathStatuses[validatedResults[i].path] = validatedResults[i].status
        }

        // Build run
        var run = ArcComparisonRun(modelUsed: selectedModel.rawValue, enabledPaths: enabledPaths)
        run.pathResults = validatedResults
        run.preprocessingCalls = preprocessingCalls
        run.finalize()
        self.currentRun = run

        // Persist
        do {
            try ArcComparisonStorage.save(run, sessionId: coordinator.session.id, pass2: isPass2)
            let summary = ArcComparisonRunSummary(from: run, sessionId: coordinator.session.id)
            runHistory.insert(summary, at: 0)
        } catch {
            print("[ArcVM] Failed to save run: \(error.localizedDescription)")
        }

        isRunning = false
    }

    // MARK: - Load / Delete Saved Runs

    func loadSavedRun(_ summary: ArcComparisonRunSummary) {
        guard let run = ArcComparisonStorage.load(runId: summary.id, sessionId: summary.sourceSessionId, pass2: isPass2) else {
            errorMessage = "Failed to load run from disk"
            return
        }
        self.currentRun = run
        self.pathStatuses = Dictionary(uniqueKeysWithValues: run.pathResults.map { ($0.path, $0.status) })
    }

    func deleteRun(_ summary: ArcComparisonRunSummary) {
        ArcComparisonStorage.delete(runId: summary.id, sessionId: summary.sourceSessionId, pass2: isPass2)
        runHistory.removeAll { $0.id == summary.id }
        if currentRun?.id == summary.id {
            currentRun = nil
            pathStatuses = [:]
        }
    }

    // MARK: - Helpers

    private func fetchSpinesByIds(_ videoIds: [String]) async -> [NarrativeSpine] {
        var spines: [NarrativeSpine] = []
        for videoId in videoIds {
            if let spine = try? await NarrativeSpineFirebaseService.shared.loadSpine(videoId: videoId) {
                spines.append(spine)
            }
        }
        return spines
    }

    /// Parse a numbered content inventory list into individual atoms.
    nonisolated static func parseContentAtomList(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                // Strip leading number and period/parenthesis
                if let range = line.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                    return String(line[range.upperBound...])
                }
                return line
            }
    }
}
