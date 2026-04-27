import Foundation
import FirebaseFirestore
import Combine

@MainActor
class BatchDigressionAnalysisService: ObservableObject {

    // MARK: - Published State

    @Published var videoResults: [BatchDigressionVideoResult] = []
    @Published var isRunning = false
    @Published var currentVideoTitle = ""
    @Published var currentVideoIndex = 0
    @Published var currentRunInVideo = 0
    @Published var totalVideos = 0
    @Published var overallPhase = ""
    @Published var errorMessage: String?

    // Aggregation
    @Published var aggregate: GlobalDigressionAggregate?

    // MARK: - Firebase

    private let db = Firestore.firestore()
    private let collectionName = "batchDigressionResults"

    // MARK: - Load Existing Results

    func loadResults(forChannelId channelId: String) async {
        do {
            let snapshot = try await db.collection(collectionName)
                .whereField("channelId", isEqualTo: channelId)
                .getDocuments()

            videoResults = snapshot.documents.compactMap { doc in
                try? doc.data(as: BatchDigressionVideoResult.self)
            }
            print("Loaded \(videoResults.count) batch digression results for channel: \(channelId)")
        } catch {
            errorMessage = "Failed to load results: \(error.localizedDescription)"
            print("Failed to load batch digression results: \(error)")
        }
    }

    // MARK: - Run Batch Analysis

    func runBatchAnalysis(
        channel: YouTubeChannel,
        videos: [YouTubeVideo],
        sentenceData: [String: [SentenceFidelityTest]]
    ) async {
        guard !isRunning else { return }

        isRunning = true
        errorMessage = nil

        // Load existing results for resume detection
        await loadResults(forChannelId: channel.channelId)

        let videosWithSentences = videos.filter { sentenceData[$0.videoId] != nil }
        totalVideos = videosWithSentences.count
        overallPhase = "Starting batch analysis for \(totalVideos) videos..."

        for (index, video) in videosWithSentences.enumerated() {
            // Check if already complete
            if let existing = videoResults.first(where: { $0.videoId == video.videoId }), existing.isComplete {
                continue
            }

            currentVideoIndex = index + 1
            currentVideoTitle = video.title
            overallPhase = "Video \(currentVideoIndex)/\(totalVideos): \(video.title)"

            await processOneVideo(
                video: video,
                channel: channel,
                sentenceData: sentenceData
            )
        }

        overallPhase = "Complete"
        isRunning = false

        // Build aggregate
        await buildAggregate(channelId: channel.channelId, sentenceData: sentenceData)
    }

    // MARK: - Resume

    func resumeBatchAnalysis(
        channel: YouTubeChannel,
        videos: [YouTubeVideo],
        sentenceData: [String: [SentenceFidelityTest]]
    ) async {
        guard !isRunning else { return }

        isRunning = true
        errorMessage = nil

        // Load existing results
        await loadResults(forChannelId: channel.channelId)

        let videosWithSentences = videos.filter { sentenceData[$0.videoId] != nil }

        // Find incomplete videos
        let incomplete = videosWithSentences.filter { video in
            guard let existing = videoResults.first(where: { $0.videoId == video.videoId }) else {
                return true  // not started
            }
            return !existing.isComplete
        }

        totalVideos = incomplete.count
        overallPhase = "Resuming: \(incomplete.count) videos remaining..."

        for (index, video) in incomplete.enumerated() {
            currentVideoIndex = index + 1
            currentVideoTitle = video.title
            overallPhase = "Video \(currentVideoIndex)/\(totalVideos): \(video.title)"

            await processOneVideo(
                video: video,
                channel: channel,
                sentenceData: sentenceData
            )
        }

        overallPhase = "Complete"
        isRunning = false

        // Build aggregate
        await buildAggregate(channelId: channel.channelId, sentenceData: sentenceData)
    }

    // MARK: - Process One Video

    private func processOneVideo(
        video: YouTubeVideo,
        channel: YouTubeChannel,
        sentenceData: [String: [SentenceFidelityTest]]
    ) async {
        guard let tests = sentenceData[video.videoId],
              let latestTest = tests.first else {
            print("No sentence data for video: \(video.videoId)")
            return
        }

        let sentences = latestTest.sentences
        guard !sentences.isEmpty else { return }

        let config = DigressionDetectionConfig(
            enableLLMEscalation: false,
            temperature: 0.3,
            maxConcurrentLLMCalls: 5,
            enabledTypes: Set(DigressionType.allCases),
            minConfidenceThreshold: 0.0,
            boundaryBoostEnabled: true,
            boundaryBoostAmount: 0.2,
            detectionMode: .llmFirst
        )

        // Check for existing partial result
        var result: BatchDigressionVideoResult
        if let existing = videoResults.first(where: { $0.videoId == video.videoId }) {
            result = existing
        } else {
            result = BatchDigressionVideoResult(
                channelId: channel.channelId,
                videoId: video.videoId,
                videoTitle: video.title,
                runs: [],
                totalSentences: sentences.count,
                config: config
            )
        }

        let runsNeeded = 3 - result.runs.count
        guard runsNeeded > 0 else { return }

        // Run remaining detections in parallel
        let startRunNumber = result.runs.count + 1
        currentRunInVideo = 0

        let capturedVideoId = video.videoId
        let capturedSentences = sentences
        let totalRunsForVideo = runsNeeded

        let newRuns = await withTaskGroup(
            of: DigressionFidelityRunResult.self,
            returning: [DigressionFidelityRunResult].self
        ) { group in
            for i in 0..<runsNeeded {
                let runNumber = startRunNumber + i
                group.addTask {
                    let detectionResult = await DigressionDetectionService.shared.detectDigressions(
                        videoId: capturedVideoId,
                        from: capturedSentences,
                        config: config
                    )

                    return DigressionFidelityRunResult(
                        runNumber: runNumber,
                        temperature: config.temperature,
                        enabledLLMEscalation: config.enableLLMEscalation,
                        digressions: detectionResult.digressions,
                        cleanSentenceIndices: detectionResult.cleanSentenceIndices,
                        totalSentences: detectionResult.totalSentences,
                        detectionMode: config.detectionMode
                    )
                }
            }

            var collected: [DigressionFidelityRunResult] = []
            for await runResult in group {
                collected.append(runResult)
                await MainActor.run {
                    self.currentRunInVideo = collected.count
                    self.overallPhase = "Video \(self.currentVideoIndex)/\(self.totalVideos): Run \(collected.count)/\(totalRunsForVideo)"
                }
            }
            return collected
        }

        // Append new runs and save
        result.runs.append(contentsOf: newRuns.sorted { $0.runNumber < $1.runNumber })
        if result.runs.count >= 3 {
            result.completedAt = Date()
        }

        // Update local state
        if let existingIndex = videoResults.firstIndex(where: { $0.videoId == video.videoId }) {
            videoResults[existingIndex] = result
        } else {
            videoResults.append(result)
        }

        // Save to Firebase
        do {
            try await saveVideoResult(result)
        } catch {
            print("Failed to save batch digression result for \(video.videoId): \(error)")
        }
    }

    // MARK: - Aggregation

    func buildAggregate(
        channelId: String,
        sentenceData: [String: [SentenceFidelityTest]]
    ) async {
        // Ensure we have results loaded
        if videoResults.isEmpty {
            await loadResults(forChannelId: channelId)
        }

        var allDigressions: [AggregatedDigression] = []
        var videosComplete = 0

        for result in videoResults {
            guard !result.runs.isEmpty else { continue }
            if result.isComplete { videosComplete += 1 }

            // Get sentences for this video
            guard let tests = sentenceData[result.videoId],
                  let latestTest = tests.first else { continue }
            let sentences = latestTest.sentences

            // Cluster digressions across runs
            let regions = CrossRunDigressionRegion.buildRegions(from: result.runs)

            for region in regions {
                let tier = ConfidenceTier.from(
                    runsDetected: region.runsDetected,
                    totalRuns: region.totalRuns
                )

                // Validate against rules using the first run's annotation for this region
                let representativeAnnotations = region.perRunAnnotation.values.map { $0 }
                let validations = DigressionRulesValidator.shared.validate(
                    digressions: Array(representativeAnnotations),
                    sentences: sentences
                )

                // Majority verdict
                let verdictCounts = Dictionary(grouping: validations, by: { $0.verdict })
                let majorityVerdict = verdictCounts.max(by: { $0.value.count < $1.value.count })?.key ?? .neutral

                // Extract context sentences
                let beforeStart = max(0, region.mergedStart - 10)
                let afterEnd = min(sentences.count - 1, region.mergedEnd + 10)

                let contextBefore = sentences.filter {
                    $0.sentenceIndex >= beforeStart && $0.sentenceIndex < region.mergedStart
                }
                let digressionSentences = sentences.filter {
                    $0.sentenceIndex >= region.mergedStart && $0.sentenceIndex <= region.mergedEnd
                }
                let contextAfter = sentences.filter {
                    $0.sentenceIndex > region.mergedEnd && $0.sentenceIndex <= afterEnd
                }

                let aggregated = AggregatedDigression(
                    videoId: result.videoId,
                    videoTitle: result.videoTitle,
                    region: region,
                    confidenceTier: tier,
                    rulesVerdict: majorityVerdict,
                    validatedDigressions: validations,
                    contextBefore: contextBefore,
                    digressionSentences: digressionSentences,
                    contextAfter: contextAfter,
                    allSentences: sentences
                )

                allDigressions.append(aggregated)
            }
        }

        aggregate = GlobalDigressionAggregate(
            allDigressions: allDigressions,
            videoCount: videoResults.count,
            videosComplete: videosComplete
        )
    }

    // MARK: - Firebase CRUD

    private func saveVideoResult(_ result: BatchDigressionVideoResult) async throws {
        let docRef = db.collection(collectionName).document(result.id)
        let data = try Firestore.Encoder().encode(result)
        try await docRef.setData(data)
        print("Saved batch digression result: \(result.id) (\(result.runs.count) runs)")
    }

    func deleteResult(forVideoId videoId: String, channelId: String) async throws {
        let docId = BatchDigressionVideoResult.docId(channelId: channelId, videoId: videoId)
        try await db.collection(collectionName).document(docId).delete()
        videoResults.removeAll { $0.videoId == videoId }
        print("🗑️ BATCH DIGRESSION: Deleted single result for video: \(videoId)")
    }

    func deleteResults(forChannelId channelId: String) async throws {
        print("🗑️ BATCH DIGRESSION: Querying collection '\(collectionName)' where channelId == '\(channelId)'...")
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        let count = snapshot.documents.count
        print("🗑️ BATCH DIGRESSION: Found \(count) documents to delete")

        for (i, doc) in snapshot.documents.enumerated() {
            try await doc.reference.delete()
            print("🗑️ BATCH DIGRESSION: Deleted \(i + 1)/\(count) — id: \(doc.documentID)")
        }
        videoResults = []
        aggregate = nil
        print("🗑️ BATCH DIGRESSION: DONE — \(count) documents deleted for channel: \(channelId)")
    }

    /// Delete ALL batch digression results across all channels
    func deleteAllResults() async throws -> Int {
        print("🗑️ BATCH DIGRESSION: Querying ALL documents in '\(collectionName)'...")
        let snapshot = try await db.collection(collectionName).getDocuments()
        let docs = snapshot.documents
        print("🗑️ BATCH DIGRESSION: Found \(docs.count) documents total")

        guard !docs.isEmpty else {
            print("🗑️ BATCH DIGRESSION: Nothing to delete")
            return 0
        }

        for chunk in stride(from: 0, to: docs.count, by: 500) {
            let batch = db.batch()
            let end = min(chunk + 500, docs.count)
            for i in chunk..<end {
                batch.deleteDocument(docs[i].reference)
            }
            try await batch.commit()
            print("🗑️ BATCH DIGRESSION: Committed batch \(chunk)-\(end - 1)")
        }

        videoResults = []
        aggregate = nil
        print("🗑️ BATCH DIGRESSION: DONE — \(docs.count) documents deleted")
        return docs.count
    }

    // MARK: - Copy Text Generation

    func generateFilteredCopyText(
        channelName: String,
        tier: ConfidenceTier?,
        type: DigressionType?,
        verdict: RulesVerdict?,
        minSentenceCount: Int = 1
    ) -> String {
        guard let aggregate else { return "No data" }

        let filtered = aggregate.filtered(tier: tier, type: type, verdict: verdict, minSentenceCount: minSentenceCount)
        let grouped = aggregate.groupedByVideo(tier: tier, type: type, verdict: verdict, minSentenceCount: minSentenceCount)

        var lines: [String] = []
        lines.append("BATCH DIGRESSION ANALYSIS")
        lines.append("Channel: \(channelName)")

        var filterParts: [String] = []
        if let tier { filterParts.append("Tier: \(tier.shortLabel)") }
        if let type { filterParts.append("Type: \(type.displayName)") }
        if let verdict { filterParts.append("Verdict: \(verdict.rawValue)") }
        if minSentenceCount > 1 { filterParts.append("Min Sentences: \(minSentenceCount)") }
        let filterStr = filterParts.isEmpty ? "All" : filterParts.joined(separator: " | ")
        lines.append("Filter: \(filterStr)")
        lines.append("Total: \(filtered.count) digressions across \(grouped.count) videos")
        lines.append("")

        for group in grouped {
            lines.append("--- Video: \"\(group.videoTitle)\" ---")
            lines.append("")

            for (idx, d) in group.digressions.enumerated() {
                lines.append("[\(idx + 1)] \(d.region.primaryType.displayName) | \(d.region.rangeLabel) | \(d.confidenceTier.displayName) | \(d.rulesVerdict.rawValue.capitalized)")

                // Context before
                if !d.contextBefore.isEmpty {
                    lines.append("  Context Before:")
                    for s in d.contextBefore {
                        lines.append("    [s\(s.sentenceIndex)] \(s.text)")
                    }
                }

                // Digression text
                lines.append("  DIGRESSION:")
                for s in d.digressionSentences {
                    lines.append("    [s\(s.sentenceIndex)] \(s.text)")
                }

                // Context after
                if !d.contextAfter.isEmpty {
                    lines.append("  Context After:")
                    for s in d.contextAfter {
                        lines.append("    [s\(s.sentenceIndex)] \(s.text)")
                    }
                }

                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - LLM Detail Copy Text

    func generateLLMDetailCopyText(
        channelName: String,
        tier: ConfidenceTier?,
        type: DigressionType?,
        verdict: RulesVerdict?,
        minSentenceCount: Int = 1
    ) -> String {
        guard let aggregate else { return "No data" }

        let filtered = aggregate.filtered(tier: tier, type: type, verdict: verdict, minSentenceCount: minSentenceCount)
        let grouped = aggregate.groupedByVideo(tier: tier, type: type, verdict: verdict, minSentenceCount: minSentenceCount)

        var lines: [String] = []
        lines.append("BATCH DIGRESSION ANALYSIS — LLM DETAIL")
        lines.append("Channel: \(channelName)")

        var filterParts: [String] = []
        if let tier { filterParts.append("Tier: \(tier.shortLabel)") }
        if let type { filterParts.append("Type: \(type.displayName)") }
        if let verdict { filterParts.append("Verdict: \(verdict.rawValue)") }
        if minSentenceCount > 1 { filterParts.append("Min Sentences: \(minSentenceCount)") }
        lines.append("Filter: \(filterParts.isEmpty ? "All" : filterParts.joined(separator: " | "))")
        lines.append("Total: \(filtered.count) digressions across \(grouped.count) videos")
        lines.append("")

        for group in grouped {
            lines.append("=== Video: \"\(group.videoTitle)\" ===")
            lines.append("")

            for (idx, d) in group.digressions.enumerated() {
                lines.append("[\(idx + 1)] \(d.region.primaryType.displayName) | \(d.region.rangeLabel) | \(d.confidenceTier.displayName) | \(d.rulesVerdict.rawValue.capitalized)")
                lines.append("    Sentence Count: \(d.region.sentenceCount)")

                // Per-run LLM annotations
                for (runNum, annotation) in d.region.perRunAnnotation.sorted(by: { $0.key < $1.key }) {
                    lines.append("")
                    lines.append("    --- Run \(runNum) ---")
                    lines.append("    Type: \(annotation.type.displayName)")
                    lines.append("    Range: s\(annotation.startSentence)-s\(annotation.endSentence) (\(annotation.sentenceCount) sentences)")
                    lines.append("    Confidence: \(String(format: "%.2f", annotation.confidence))")
                    lines.append("    Detection Method: \(annotation.detectionMethod.displayName)")

                    if let brief = annotation.briefContent, !brief.isEmpty {
                        lines.append("    Brief: \(brief)")
                    }

                    if !annotation.entryMarker.isEmpty {
                        lines.append("    Entry Marker: \(annotation.entryMarker)")
                    }
                    if !annotation.exitMarker.isEmpty {
                        lines.append("    Exit Marker: \(annotation.exitMarker)")
                    }

                    if let narrative = annotation.surroundingNarrativeThread, !narrative.isEmpty {
                        lines.append("    Narrative Thread: \(narrative)")
                    }

                    // Mechanical flags
                    var flags: [String] = []
                    if annotation.hasCTA { flags.append("CTA") }
                    if annotation.perspectiveShift { flags.append("Perspective Shift") }
                    if annotation.stanceShift { flags.append("Stance Shift") }
                    if !flags.isEmpty {
                        lines.append("    Flags: \(flags.joined(separator: ", "))")
                    }

                    // Foreshadowing details
                    if let payoff = annotation.foreshadowingPayoffSentence {
                        lines.append("    Foreshadowing Payoff: s\(payoff)")
                    }
                    if let distance = annotation.foreshadowingDistance {
                        lines.append("    Foreshadowing Distance: \(distance) sentences")
                    }
                }

                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Rules Detail Copy Text

    func generateRulesDetailCopyText(
        channelName: String,
        tier: ConfidenceTier?,
        type: DigressionType?,
        verdict: RulesVerdict?,
        minSentenceCount: Int = 1
    ) -> String {
        guard let aggregate else { return "No data" }

        let filtered = aggregate.filtered(tier: tier, type: type, verdict: verdict, minSentenceCount: minSentenceCount)
        let grouped = aggregate.groupedByVideo(tier: tier, type: type, verdict: verdict, minSentenceCount: minSentenceCount)

        var lines: [String] = []
        lines.append("BATCH DIGRESSION ANALYSIS — RULES/DETERMINISTIC DETAIL")
        lines.append("Channel: \(channelName)")

        var filterParts: [String] = []
        if let tier { filterParts.append("Tier: \(tier.shortLabel)") }
        if let type { filterParts.append("Type: \(type.displayName)") }
        if let verdict { filterParts.append("Verdict: \(verdict.rawValue)") }
        if minSentenceCount > 1 { filterParts.append("Min Sentences: \(minSentenceCount)") }
        lines.append("Filter: \(filterParts.isEmpty ? "All" : filterParts.joined(separator: " | "))")
        lines.append("Total: \(filtered.count) digressions across \(grouped.count) videos")
        lines.append("")

        for group in grouped {
            lines.append("=== Video: \"\(group.videoTitle)\" ===")
            lines.append("")

            for (idx, d) in group.digressions.enumerated() {
                lines.append("[\(idx + 1)] \(d.region.primaryType.displayName) | \(d.region.rangeLabel) | \(d.confidenceTier.displayName)")
                lines.append("    Sentence Count: \(d.region.sentenceCount)")

                // Per-validation gate checks
                for (valIdx, validation) in d.validatedDigressions.enumerated() {
                    let runLabel = d.validatedDigressions.count > 1 ? " (Validation \(valIdx + 1))" : ""
                    lines.append("")
                    lines.append("    --- Verdict: \(validation.verdict.rawValue.capitalized)\(runLabel) ---")

                    let passed = validation.checks.filter(\.passed).count
                    let total = validation.checks.count
                    lines.append("    Gate Checks: \(passed)/\(total) passed")

                    for check in validation.checks {
                        let icon = check.passed ? "PASS" : "FAIL"
                        lines.append("    [\(icon)] \(check.name): \(check.detail)")
                    }

                    if let reason = validation.contradictionReason {
                        lines.append("    Contradiction: \(reason)")
                    }
                }

                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Single Digression Copy Text

    func generateSingleDigressionCopyText(_ d: AggregatedDigression) -> String {
        var lines: [String] = []
        lines.append("== DIGRESSION CONTEXT ==")
        lines.append("Video: \(d.videoTitle)")
        lines.append("Type: \(d.region.primaryType.displayName) | Range: \(d.region.rangeLabel) | Confidence: \(d.confidenceTier.displayName) | Rules: \(d.rulesVerdict.rawValue.capitalized)")
        lines.append("")

        // Context before
        if !d.contextBefore.isEmpty {
            lines.append("-- Context Before (\(d.contextBefore.count) sentences) --")
            for s in d.contextBefore {
                lines.append("[s\(s.sentenceIndex)] \(s.text)")
            }
            lines.append("")
        }

        // Digression
        lines.append("-- DIGRESSION (\(d.digressionSentences.count) sentences) --")
        for s in d.digressionSentences {
            // Show per-run labels
            var runLabels: [String] = []
            for (runNum, annotation) in d.region.perRunAnnotation.sorted(by: { $0.key < $1.key }) {
                if annotation.contains(sentenceIndex: s.sentenceIndex) {
                    runLabels.append("R\(runNum):\(annotation.type.displayName)")
                }
            }
            let runSuffix = runLabels.isEmpty ? "" : " [\(runLabels.joined(separator: ", "))]"
            lines.append("[s\(s.sentenceIndex)] \(s.text)\(runSuffix)")
        }
        lines.append("")

        // Context after
        if !d.contextAfter.isEmpty {
            lines.append("-- Context After (\(d.contextAfter.count) sentences) --")
            for s in d.contextAfter {
                lines.append("[s\(s.sentenceIndex)] \(s.text)")
            }
            lines.append("")
        }

        // Gate checks
        if let firstValidation = d.validatedDigressions.first {
            lines.append("-- Gate Checks (\(firstValidation.verdict.rawValue.capitalized)) --")
            for check in firstValidation.checks {
                let icon = check.passed ? "PASS" : "FAIL"
                lines.append("[\(icon)] \(check.name): \(check.detail)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
