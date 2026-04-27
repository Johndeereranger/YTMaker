//
//  GapAnalysisViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  ViewModel for the Gap Analysis layer.
//  Manages source arc selection, gap path execution, and results.
//

import Foundation
import SwiftUI

@MainActor
class GapAnalysisViewModel: ObservableObject {

    // MARK: - Dependencies

    let coordinator: MarkovScriptWriterCoordinator

    // MARK: - Source Selection

    @Published var availableArcResults: [ArcPathResult] = []
    @Published var selectedArcResultId: UUID?

    var selectedArcResult: ArcPathResult? {
        guard let id = selectedArcResultId else { return nil }
        return availableArcResults.first { $0.id == id }
    }

    // MARK: - Configuration

    @Published var selectedModel: AIModel = .claude4Sonnet
    @Published var enabledGapPaths: Set<GapPath> = Set(GapPath.primaryCases)

    // MARK: - Run State

    @Published var isRunning = false
    @Published var isRefining = false
    @Published var progressMessage = ""
    @Published var pathStatuses: [GapPath: ArcPathRunStatus] = [:]
    @Published var completedCount = 0

    // MARK: - Results

    @Published var currentGapRun: GapAnalysisRun?
    @Published var gapRunHistory: [GapAnalysisRunSummary] = []

    // MARK: - Dependencies from Parent

    var creatorProfile: CreatorNarrativeProfile?
    var representativeSpines: [NarrativeSpine] = []
    var transitionMatrix: SpineTransitionMatrix?

    // Source arc run ID (for tracking)
    var sourceArcRunId: UUID?

    // MARK: - Error

    @Published var errorMessage: String?

    // MARK: - Computed

    var canRun: Bool {
        !isRunning &&
        selectedArcResult != nil &&
        selectedArcResult?.outputSpine != nil &&
        !enabledGapPaths.isEmpty &&
        creatorProfile != nil &&
        transitionMatrix != nil
    }

    var prerequisiteMessage: String? {
        if selectedArcResult == nil {
            return "Select a completed arc result above to analyze."
        }
        if selectedArcResult?.outputSpine == nil {
            return "Selected arc result has no parsed spine."
        }
        if creatorProfile == nil {
            return "Creator profile not loaded."
        }
        return nil
    }

    var totalExpectedCalls: Int {
        let primaryCalls = enabledGapPaths.filter(\.isPrimary).reduce(0) { $0 + $1.callCount }
        let g6Calls = g6WillRun ? GapPath.g6_synthesis.callCount : 0
        return primaryCalls + g6Calls
    }

    /// G6 synthesis auto-runs when 2+ primary paths are enabled.
    var g6WillRun: Bool {
        enabledGapPaths.filter(\.isPrimary).count >= 2
    }

    // MARK: - Init

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Update Available Results

    func updateAvailableResults(from arcRun: ArcComparisonRun?) {
        guard let run = arcRun else {
            availableArcResults = []
            selectedArcResultId = nil
            return
        }

        sourceArcRunId = run.id
        availableArcResults = run.pathResults.filter { $0.status == .completed && $0.outputSpine != nil }

        // Auto-select first if nothing selected or previous selection is gone
        if selectedArcResultId == nil || !availableArcResults.contains(where: { $0.id == selectedArcResultId }) {
            selectedArcResultId = availableArcResults.first?.id
        }
    }

    // MARK: - Run

    func startRun() async {
        guard canRun,
              let arcResult = selectedArcResult,
              let profile = creatorProfile,
              let matrix = transitionMatrix,
              let arcRunId = sourceArcRunId
        else { return }

        isRunning = true
        errorMessage = nil
        completedCount = 0
        pathStatuses = Dictionary(uniqueKeysWithValues: enabledGapPaths.map { ($0, ArcPathRunStatus.running) })

        let contentInventory = arcResult.intermediateOutputs["contentInventory"]

        var runner = GapAnalysisRunner(
            model: selectedModel,
            sourceResult: arcResult,
            creatorProfile: profile,
            representativeSpines: representativeSpines,
            transitionMatrix: matrix,
            enabledPaths: enabledGapPaths,
            contentInventory: contentInventory
        )

        runner.onCallComplete = { [weak self] _, _ in
            Task { @MainActor in
                self?.completedCount += 1
            }
        }
        runner.onPathComplete = { [weak self] path, status in
            Task { @MainActor in
                self?.pathStatuses[path] = status
            }
        }

        let results = await runner.run()
        var allResults = results

        // Run G6 synthesis if 2+ primary paths completed with findings
        let completedWithFindings = results.filter { $0.status == .completed && !$0.findings.isEmpty }
        if completedWithFindings.count >= 2 {
            pathStatuses[.g6_synthesis] = .running
            let g6Result = await GapAnalysisRunner.runG6(
                model: selectedModel,
                completedResults: completedWithFindings
            )
            completedCount += 1
            allResults.append(g6Result)
            pathStatuses[.g6_synthesis] = g6Result.status
        }

        // Refinement pass: cross-reference best findings against the raw rambling
        isRefining = true
        let rawRambling = coordinator.session.rawRamblingText
        let bestFindings = Self.bestFindings(from: allResults)

        if !bestFindings.isEmpty {
            let (refinedFindings, refinementCall) = await GapAnalysisRunner.runRefinement(
                model: selectedModel,
                findings: bestFindings,
                rawRambling: rawRambling
            )

            // Write refined findings back to the appropriate path result(s)
            let g6Index = allResults.firstIndex(where: { $0.path == .g6_synthesis && $0.status == .completed })
            if let idx = g6Index {
                // G6 ran — replace G6's findings with refined versions
                allResults[idx].findings = refinedFindings
                if let call = refinementCall {
                    allResults[idx].calls.append(call)
                    allResults[idx].finalize()
                }
            } else {
                // No G6 — apply refinement to each completed path's findings by matching IDs
                let refinedById = Dictionary(uniqueKeysWithValues: refinedFindings.map { ($0.id, $0) })
                for i in 0..<allResults.count where allResults[i].status == .completed {
                    allResults[i].findings = allResults[i].findings.map { finding in
                        refinedById[finding.id] ?? finding
                    }
                }
            }
        }
        isRefining = false

        // Build run
        var run = GapAnalysisRun(
            modelUsed: selectedModel.rawValue,
            sourceArcRunId: arcRunId,
            sourceArcPath: arcResult.path,
            enabledGapPaths: enabledGapPaths
        )
        run.pathResults = allResults
        run.refinementApplied = !bestFindings.isEmpty
        run.finalize()
        self.currentGapRun = run

        // Persist
        do {
            try GapAnalysisStorage.save(run, sessionId: coordinator.session.id)
            let summary = GapAnalysisRunSummary(from: run, sessionId: coordinator.session.id)
            gapRunHistory.insert(summary, at: 0)
        } catch {
            print("[GapVM] Failed to save run: \(error.localizedDescription)")
        }

        isRunning = false
    }

    // MARK: - History Management

    /// Falls back to scanning all session directories if the current session has none (handles session UUID changes).
    func loadGapHistory() {
        let sessionId = coordinator.session.id
        let runIds = GapAnalysisStorage.listRunIds(sessionId: sessionId)

        if !runIds.isEmpty {
            self.gapRunHistory = runIds.compactMap { runId -> GapAnalysisRunSummary? in
                guard let run = GapAnalysisStorage.load(runId: runId, sessionId: sessionId) else { return nil }
                return GapAnalysisRunSummary(from: run, sessionId: sessionId)
            }.sorted { $0.createdAt > $1.createdAt }
        } else {
            let allRuns = GapAnalysisStorage.listAllRunIds()
            self.gapRunHistory = allRuns.compactMap { entry -> GapAnalysisRunSummary? in
                guard let run = GapAnalysisStorage.load(runId: entry.runId, sessionId: entry.sessionId) else { return nil }
                return GapAnalysisRunSummary(from: run, sessionId: entry.sessionId)
            }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func loadSavedRun(_ summary: GapAnalysisRunSummary) {
        guard let run = GapAnalysisStorage.load(runId: summary.id, sessionId: summary.sourceSessionId) else {
            errorMessage = "Failed to load gap run from disk"
            return
        }
        self.currentGapRun = run
        self.pathStatuses = Dictionary(uniqueKeysWithValues: run.pathResults.map { ($0.path, $0.status) })
    }

    /// Extract the best finding set: G6 if available, otherwise all completed findings merged.
    private static func bestFindings(from results: [GapPathResult]) -> [GapFinding] {
        let g6 = results.first { $0.path == .g6_synthesis && $0.status == .completed }
        if let g6, !g6.findings.isEmpty {
            return g6.findings
        }
        return results
            .filter { $0.status == .completed }
            .flatMap(\.findings)
    }

    func deleteRun(_ summary: GapAnalysisRunSummary) {
        GapAnalysisStorage.delete(runId: summary.id, sessionId: summary.sourceSessionId)
        gapRunHistory.removeAll { $0.id == summary.id }
        if currentGapRun?.id == summary.id {
            currentGapRun = nil
            pathStatuses = [:]
        }
    }
}
