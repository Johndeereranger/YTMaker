import Foundation
import SwiftUI

@MainActor
class ExperimentLabViewModel: ObservableObject {
    let video: YouTubeVideo

    // MARK: - Stored Experiments

    @Published var experiments: [PromptExperiment] = []

    // MARK: - Config for Next Run

    @Published var windowSize: Int = 5
    @Published var stepSize: Int = 2
    @Published var temperature: Double = 0.3
    @Published var sisterRunCount: Int = 3
    @Published var selectedPromptVariant: SectionSplitterPromptVariant = .classificationV2
    @Published var manualLabel: String = ""

    // MARK: - Run State

    @Published var isRunning = false
    @Published var progressMessage = ""
    @Published var progressValue: Double = 0

    // MARK: - Comparison State

    @Published var selectedRunIds: Set<String> = []
    @Published var selectedTab: Int = 0

    // MARK: - Parsed Sentences & Digressions

    @Published var sentences: [String] = []
    @Published var digressions: [DigressionAnnotation] = []

    // MARK: - Init

    init(video: YouTubeVideo) {
        self.video = video
        if let transcript = video.transcript {
            self.sentences = SentenceParser.parse(transcript)
        }
    }

    // MARK: - Persistence

    func loadExperiments() {
        experiments = ExperimentStorage.load(videoId: video.videoId)
        // Also load digressions for copy service
        Task {
            if let result = try? await DigressionFirebaseService.shared.getLatestResult(forVideoId: video.videoId) {
                digressions = result.digressions
            }
        }
    }

    func saveExperiments() {
        ExperimentStorage.save(experiments, videoId: video.videoId)
    }

    // MARK: - Run Experiment

    func runExperiment() async {
        guard let transcript = video.transcript, !transcript.isEmpty else {
            progressMessage = "No transcript available"
            return
        }

        isRunning = true
        progressValue = 0
        progressMessage = "Starting experiment..."

        let totalSteps = Double(sisterRunCount * 2) // 2 variants per sister run
        var completedSteps: Double = 0

        // Load digressions
        progressMessage = "Loading digression data..."
        var excludeSet: Set<Int>?
        do {
            if let digressionResult = try await DigressionFirebaseService.shared.getLatestResult(forVideoId: video.videoId) {
                excludeSet = DigressionDetectionService.shared.buildExcludeSet(from: digressionResult.digressions)
                digressions = digressionResult.digressions
                print("[ExperimentLab] Loaded \(excludeSet?.count ?? 0) digression indices, \(digressions.count) digressions")
            } else {
                print("[ExperimentLab] No digression data found for video")
            }
        } catch {
            print("[ExperimentLab] Failed to load digressions: \(error)")
        }

        let cleanToFullMap: [Int: Int]?
        let cleanSentenceCount: Int?
        if let exclude = excludeSet {
            cleanToFullMap = buildCleanToFullMap(totalSentences: sentences.count, excludeIndices: exclude)
            cleanSentenceCount = sentences.count - exclude.count
        } else {
            cleanToFullMap = nil
            cleanSentenceCount = nil
        }

        let promptText = selectedPromptVariant.systemPrompt

        var sisterRuns: [ExperimentSisterRun] = []

        for sisterNum in 1...sisterRunCount {
            let sisterStart = Date()

            // --- With Digressions (full transcript) ---
            progressMessage = "Sister \(sisterNum)/\(sisterRunCount): Running with digressions..."
            let withDigVariant: ExperimentVariant
            do {
                let result = try await SectionSplitterService.shared.runSplitter(
                    transcript: transcript,
                    windowSize: windowSize,
                    stepSize: stepSize,
                    temperature: temperature,
                    promptVariant: selectedPromptVariant,
                    excludeIndices: nil,
                    onProgress: { completed, total, phase in
                        let sisterProgress = completedSteps / totalSteps
                        let windowProgress = Double(completed) / Double(max(total, 1)) / totalSteps
                        self.progressValue = sisterProgress + windowProgress
                        self.progressMessage = "Sister \(sisterNum)/\(self.sisterRunCount): \(phase) (\(completed)/\(total))"
                    }
                )

                let duration = Date().timeIntervalSince(sisterStart)
                withDigVariant = buildVariant(
                    from: result,
                    variantType: .withDigressions,
                    runDuration: duration,
                    cleanToFullMap: nil
                )
            } catch {
                print("[ExperimentLab] Sister \(sisterNum) with-digressions failed: \(error)")
                isRunning = false
                progressMessage = "Failed: \(error.localizedDescription)"
                return
            }

            completedSteps += 1
            progressValue = completedSteps / totalSteps

            // --- Without Digressions (clean transcript) ---
            var withoutDigVariant: ExperimentVariant?
            if let exclude = excludeSet {
                progressMessage = "Sister \(sisterNum)/\(sisterRunCount): Running without digressions..."
                let cleanStart = Date()
                do {
                    let result = try await SectionSplitterService.shared.runSplitter(
                        transcript: transcript,
                        windowSize: windowSize,
                        stepSize: stepSize,
                        temperature: temperature,
                        promptVariant: selectedPromptVariant,
                        excludeIndices: exclude,
                        onProgress: { completed, total, phase in
                            let sisterProgress = completedSteps / totalSteps
                            let windowProgress = Double(completed) / Double(max(total, 1)) / totalSteps
                            self.progressValue = sisterProgress + windowProgress
                            self.progressMessage = "Sister \(sisterNum)/\(self.sisterRunCount): -Dig \(phase) (\(completed)/\(total))"
                        }
                    )

                    let duration = Date().timeIntervalSince(cleanStart)
                    withoutDigVariant = buildVariant(
                        from: result,
                        variantType: .withoutDigressions,
                        runDuration: duration,
                        cleanToFullMap: cleanToFullMap
                    )
                } catch {
                    print("[ExperimentLab] Sister \(sisterNum) without-digressions failed: \(error)")
                    // Continue — the with-digressions variant still succeeded
                }
            }

            completedSteps += 1
            progressValue = completedSteps / totalSteps

            let sisterRun = ExperimentSisterRun(
                id: UUID(),
                runNumber: sisterNum,
                timestamp: Date(),
                withDigressions: withDigVariant,
                withoutDigressions: withoutDigVariant,
                digressionExcludeIndices: excludeSet,
                totalSentences: sentences.count,
                cleanSentenceCount: cleanSentenceCount
            )
            sisterRuns.append(sisterRun)
        }

        // Build experiment
        let autoLabel = PromptExperiment.makeAutoLabel(
            windowSize: windowSize,
            stepSize: stepSize,
            temperature: temperature,
            sisterCount: sisterRunCount,
            variantName: selectedPromptVariant.name
        )

        let experiment = PromptExperiment(
            id: UUID(),
            videoId: video.videoId,
            createdAt: Date(),
            windowSize: windowSize,
            stepSize: stepSize,
            temperature: temperature,
            promptVariantId: selectedPromptVariant.id,
            promptVariantName: selectedPromptVariant.name,
            promptText: promptText,
            sisterRunCount: sisterRunCount,
            autoLabel: autoLabel,
            manualLabel: manualLabel.isEmpty ? nil : manualLabel,
            sisterRuns: sisterRuns,
            isComplete: true
        )

        experiments.insert(experiment, at: 0)
        saveExperiments()

        isRunning = false
        progressMessage = "Complete"
        progressValue = 1.0
    }

    // MARK: - Build Variant from SectionSplitterRunResult

    private func buildVariant(
        from result: SectionSplitterRunResult,
        variantType: VariantType,
        runDuration: TimeInterval,
        cleanToFullMap: [Int: Int]?
    ) -> ExperimentVariant {
        // Extract gap indices (0-indexed) from boundaries (1-indexed sentenceNumber)
        let rawPass1Gaps = Set(result.pass1Boundaries.map { $0.sentenceNumber - 1 })
        let rawFinalGaps = Set(result.boundaries.map { $0.sentenceNumber - 1 })

        // Remap if this is a without-digressions variant
        let pass1Gaps: Set<Int>
        let finalGaps: Set<Int>
        if let map = cleanToFullMap {
            pass1Gaps = remapGapIndices(rawPass1Gaps, using: map)
            finalGaps = remapGapIndices(rawFinalGaps, using: map)
        } else {
            pass1Gaps = rawPass1Gaps
            finalGaps = rawFinalGaps
        }

        // Extract raw outputs
        let rawOutputs = extractRawOutputs(from: result)

        return ExperimentVariant(
            id: UUID(),
            variantType: variantType,
            splitterResult: result,
            pass1GapIndices: pass1Gaps,
            finalGapIndices: finalGaps,
            rawWindowOutputs: rawOutputs,
            runDuration: runDuration,
            windowCount: result.totalWindows,
            cleanToFullIndexMap: cleanToFullMap
        )
    }

    private func extractRawOutputs(from result: SectionSplitterRunResult) -> [WindowRawOutput] {
        // Build a lookup for pass2 raw responses by window index
        let pass2ByWindow: [Int: String] = Dictionary(
            uniqueKeysWithValues: result.pass2Results.map { ($0.windowIndex, $0.rawResponse) }
        )

        return result.pass1Results.map { p1 in
            WindowRawOutput(
                windowIndex: p1.windowIndex,
                startSentence: p1.startSentence,
                endSentence: p1.endSentence,
                pass1Raw: p1.rawResponse,
                pass2Raw: pass2ByWindow[p1.windowIndex]
            )
        }
    }

    // MARK: - Experiment CRUD

    func deleteExperiment(_ experiment: PromptExperiment) {
        experiments.removeAll { $0.id == experiment.id }
        saveExperiments()
    }

    func updateLabel(experimentId: UUID, label: String) {
        if let idx = experiments.firstIndex(where: { $0.id == experimentId }) {
            experiments[idx].manualLabel = label.isEmpty ? nil : label
            saveExperiments()
        }
    }

    // MARK: - Selectable Runs for Comparison

    var allSelectableRuns: [SelectableRun] {
        var runs: [SelectableRun] = []
        for (expIdx, exp) in experiments.enumerated() {
            let expNum = expIdx + 1
            for sister in exp.sisterRuns {
                // With digressions — Final
                runs.append(SelectableRun(
                    id: SelectableRun.makeId(experimentId: exp.id, sisterRun: sister.runNumber, variant: .withDigressions, pass: .final),
                    experimentId: exp.id,
                    experimentLabel: exp.displayLabel,
                    experimentIndex: expNum,
                    sisterRunNumber: sister.runNumber,
                    variantType: .withDigressions,
                    passType: .final,
                    gapIndices: sister.withDigressions.finalGapIndices
                ))

                // With digressions — Pass 1
                runs.append(SelectableRun(
                    id: SelectableRun.makeId(experimentId: exp.id, sisterRun: sister.runNumber, variant: .withDigressions, pass: .pass1),
                    experimentId: exp.id,
                    experimentLabel: exp.displayLabel,
                    experimentIndex: expNum,
                    sisterRunNumber: sister.runNumber,
                    variantType: .withDigressions,
                    passType: .pass1,
                    gapIndices: sister.withDigressions.pass1GapIndices
                ))

                // Without digressions — Final
                if let clean = sister.withoutDigressions {
                    runs.append(SelectableRun(
                        id: SelectableRun.makeId(experimentId: exp.id, sisterRun: sister.runNumber, variant: .withoutDigressions, pass: .final),
                        experimentId: exp.id,
                        experimentLabel: exp.displayLabel,
                        experimentIndex: expNum,
                        sisterRunNumber: sister.runNumber,
                        variantType: .withoutDigressions,
                        passType: .final,
                        gapIndices: clean.finalGapIndices
                    ))

                    // Without digressions — Pass 1
                    runs.append(SelectableRun(
                        id: SelectableRun.makeId(experimentId: exp.id, sisterRun: sister.runNumber, variant: .withoutDigressions, pass: .pass1),
                        experimentId: exp.id,
                        experimentLabel: exp.displayLabel,
                        experimentIndex: expNum,
                        sisterRunNumber: sister.runNumber,
                        variantType: .withoutDigressions,
                        passType: .pass1,
                        gapIndices: clean.pass1GapIndices
                    ))
                }
            }
        }
        return runs
    }

    var selectedRuns: [SelectableRun] {
        allSelectableRuns.filter { selectedRunIds.contains($0.id) }
    }

    func toggleRunSelection(_ run: SelectableRun) {
        if selectedRunIds.contains(run.id) {
            selectedRunIds.remove(run.id)
        } else {
            selectedRunIds.insert(run.id)
        }
    }

    func isRunSelected(_ run: SelectableRun) -> Bool {
        selectedRunIds.contains(run.id)
    }

    func clearSelection() {
        selectedRunIds.removeAll()
    }

    // MARK: - Copy Helpers

    func copyAllSummary() -> String {
        ExperimentCopyService.copyAllSummary(experiments: experiments, videoTitle: video.title, digressions: digressions, sentences: sentences)
    }

    func copySummaryWithPrompts() -> String {
        ExperimentCopyService.copySummaryWithPrompts(experiments: experiments, videoTitle: video.title, digressions: digressions, sentences: sentences)
    }

    func copyRunDetail(experiment: PromptExperiment) -> String {
        ExperimentCopyService.copyRunDetail(experiment: experiment, sentences: sentences)
    }

    func copyComparison() -> String {
        ExperimentCopyService.copyComparison(selectedRuns: selectedRuns, sentences: sentences)
    }
}
