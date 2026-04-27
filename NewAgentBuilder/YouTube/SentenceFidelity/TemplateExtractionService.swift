//
//  TemplateExtractionService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

/// Service for extracting structural templates from analyzed videos
@MainActor
class TemplateExtractionService: ObservableObject {
    static let shared = TemplateExtractionService()

    @Published var state: TemplateExtractionState = .idle
    @Published var currentTemplate: CreatorTemplate?
    @Published var currentClusteringResult: ClusteringResult?
    @Published var currentBoundaryResults: [String: BoundaryDetectionResult] = [:]
    @Published var currentChannel: YouTubeChannel?

    // Track which channel the current template belongs to
    private var currentChannelId: String?

    private let boundaryService = BoundaryDetectionService.shared
    private let clusteringService = StructuralClusteringService.shared
    private let extractorVersion = "1.1"

    private init() {}

    /// Reset state when switching to a different channel
    func resetIfNeeded(for channelId: String) {
        if currentChannelId != channelId {
            forceReset()
            currentChannelId = channelId
        }
    }

    /// Force reset all state
    func forceReset() {
        currentChannelId = nil
        currentTemplate = nil
        currentClusteringResult = nil
        currentBoundaryResults = [:]
        currentChannel = nil
        state = .idle
    }

    // MARK: - Extract Template

    /// Extract a template from videos with sentence analysis
    func extractTemplate(
        channel: YouTubeChannel,
        videos: [YouTubeVideo],
        sentenceData: [String: [SentenceFidelityTest]],
        onProgress: ((String) -> Void)? = nil
    ) async -> CreatorTemplate? {

        // Track which channel we're extracting for
        currentChannelId = channel.channelId
        currentChannel = channel

        state = .analyzing(progress: "Starting template extraction...")
        onProgress?("Starting template extraction...")

        // Filter to videos with sentence analysis (sorted for deterministic processing)
        let analyzableVideos = videos.filter { sentenceData[$0.videoId] != nil }
            .sorted { $0.videoId < $1.videoId }

        guard analyzableVideos.count >= 3 else {
            state = .failed(error: "Need at least 3 videos with sentence analysis")
            return nil
        }

        onProgress?("Analyzing \(analyzableVideos.count) videos...")

        // Run boundary detection on each video
        var allResults: [(video: YouTubeVideo, result: BoundaryDetectionResult)] = []

        for (index, video) in analyzableVideos.enumerated() {
            guard let runs = sentenceData[video.videoId], let latestRun = runs.first else {
                continue
            }

            let progress = "Processing \(index + 1)/\(analyzableVideos.count): \(video.title)"
            state = .analyzing(progress: progress)
            onProgress?(progress)

            let result = boundaryService.detectBoundaries(from: latestRun)
            allResults.append((video, result))
        }

        guard !allResults.isEmpty else {
            state = .failed(error: "No valid boundary detection results")
            return nil
        }

        // Store boundary results for potential use by twin finder
        currentBoundaryResults = Dictionary(uniqueKeysWithValues: allResults.map { ($0.video.videoId, $0.result) })

        onProgress?("Extracting patterns...")
        state = .analyzing(progress: "Extracting patterns...")

        // Run structural clustering to get video sequences and templates
        onProgress?("Clustering video structures...")
        state = .analyzing(progress: "Clustering video structures...")

        let boundaryResults = allResults.map { $0.result }
        let clusteringResult = clusteringService.clusterVideos(
            channel: channel,
            boundaryResults: boundaryResults
        )
        currentClusteringResult = clusteringResult

        // Extract patterns
        let openingPattern = extractSectionPattern(
            from: allResults,
            sectionType: .opening,
            positionFilter: { $0.positionInVideo < 0.15 }
        )

        let closingPattern = extractSectionPattern(
            from: allResults,
            sectionType: .closing,
            positionFilter: { $0.positionInVideo > 0.85 }
        )

        let contentPatterns = extractContentPatterns(from: allResults)
        let styleMetrics = calculateStyleMetrics(from: allResults)

        // Build template
        let template = CreatorTemplate(
            id: UUID().uuidString,
            channelId: channel.channelId,
            channelName: channel.name,
            createdAt: Date(),
            videosAnalyzed: allResults.count,
            videoIds: allResults.map { $0.video.videoId },
            openingPattern: openingPattern,
            closingPattern: closingPattern,
            contentPatterns: contentPatterns,
            styleMetrics: styleMetrics,
            extractorVersion: extractorVersion
        )

        currentTemplate = template
        state = .complete(template: template)
        onProgress?("Template extraction complete!")

        return template
    }

    // MARK: - Section Pattern Extraction

    private func extractSectionPattern(
        from results: [(video: YouTubeVideo, result: BoundaryDetectionResult)],
        sectionType: SectionPattern.SectionType,
        positionFilter: (Chunk) -> Bool
    ) -> SectionPattern {

        var allChunks: [(video: YouTubeVideo, chunk: Chunk)] = []

        for (video, result) in results {
            let filteredChunks = result.chunks.filter(positionFilter)
            for chunk in filteredChunks {
                allChunks.append((video, chunk))
            }
        }

        // Calculate averages
        let avgChunkCount = Double(allChunks.count) / Double(max(1, results.count))
        let avgSentenceCount = allChunks.isEmpty ? 0 :
            Double(allChunks.reduce(0) { $0 + $1.chunk.sentenceCount }) / Double(allChunks.count)

        // Find dominant perspective and stance
        let dominantPerspective = findDominantValue(
            allChunks.map { $0.chunk.profile.dominantPerspective }
        )
        let dominantStance = findDominantValue(
            allChunks.map { $0.chunk.profile.dominantStance }
        )

        // Average tag densities
        let avgTagDensity = averageTagDensities(allChunks.map { $0.chunk.profile.tagDensity })

        // Trigger frequencies
        let triggerFreqs = calculateTriggerFrequencies(allChunks.map { $0.chunk })

        // Example sentences
        let examples = extractExampleSentences(from: allChunks, limit: 5)

        return SectionPattern(
            sectionType: sectionType,
            averageChunkCount: avgChunkCount,
            averageSentenceCount: avgSentenceCount,
            dominantPerspective: dominantPerspective,
            dominantStance: dominantStance,
            typicalTagDensity: avgTagDensity,
            commonTriggers: triggerFreqs,
            exampleSentences: examples
        )
    }

    // MARK: - Content Pattern Extraction

    private func extractContentPatterns(
        from results: [(video: YouTubeVideo, result: BoundaryDetectionResult)]
    ) -> [ContentPattern] {

        // Get all middle chunks
        var middleChunks: [(video: YouTubeVideo, chunk: Chunk)] = []

        for (video, result) in results {
            let filtered = result.chunks.filter {
                $0.positionInVideo >= 0.15 && $0.positionInVideo <= 0.85
            }
            for chunk in filtered {
                middleChunks.append((video, chunk))
            }
        }

        guard !middleChunks.isEmpty else {
            return []
        }

        // Cluster chunks by their characteristics
        var patterns: [ContentPattern] = []

        // Pattern 1: Evidence/Data blocks (high statistics/numbers)
        let evidenceChunks = middleChunks.filter {
            $0.chunk.profile.tagDensity.hasStatistic > 0.2 ||
            $0.chunk.profile.tagDensity.hasNumber > 0.3
        }
        if !evidenceChunks.isEmpty {
            patterns.append(buildContentPattern(
                patternId: "evidence",
                patternName: "Evidence Block",
                chunks: evidenceChunks,
                totalChunks: middleChunks.count
            ))
        }

        // Pattern 2: Story/Narrative blocks (high first person, low statistics)
        let storyChunks = middleChunks.filter {
            $0.chunk.profile.tagDensity.hasFirstPerson > 0.3 &&
            $0.chunk.profile.tagDensity.hasStatistic < 0.1
        }
        if !storyChunks.isEmpty {
            patterns.append(buildContentPattern(
                patternId: "story",
                patternName: "Story Section",
                chunks: storyChunks,
                totalChunks: middleChunks.count
            ))
        }

        // Pattern 3: Engagement blocks (high contrast/reveal/challenge)
        let engagementChunks = middleChunks.filter {
            $0.chunk.profile.tagDensity.hasContrastMarker > 0.2 ||
            $0.chunk.profile.tagDensity.hasRevealLanguage > 0.2 ||
            $0.chunk.profile.tagDensity.hasChallengeLanguage > 0.2
        }
        if !engagementChunks.isEmpty {
            patterns.append(buildContentPattern(
                patternId: "engagement",
                patternName: "Engagement Hook",
                chunks: engagementChunks,
                totalChunks: middleChunks.count
            ))
        }

        // Pattern 4: Direct address blocks (high second person)
        let directChunks = middleChunks.filter {
            $0.chunk.profile.tagDensity.hasSecondPerson > 0.3
        }
        if !directChunks.isEmpty {
            patterns.append(buildContentPattern(
                patternId: "direct",
                patternName: "Direct Address",
                chunks: directChunks,
                totalChunks: middleChunks.count
            ))
        }

        // Pattern 5: Explanation blocks (asserting stance, moderate complexity)
        let explanationChunks = middleChunks.filter {
            $0.chunk.profile.dominantStance == .asserting &&
            $0.chunk.profile.tagDensity.hasFirstPerson < 0.2 &&
            $0.chunk.profile.tagDensity.hasSecondPerson < 0.2
        }
        if !explanationChunks.isEmpty {
            patterns.append(buildContentPattern(
                patternId: "explanation",
                patternName: "Explanation",
                chunks: explanationChunks,
                totalChunks: middleChunks.count
            ))
        }

        return patterns.sorted {
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            return $0.patternId < $1.patternId  // Deterministic tie-breaker
        }
    }

    private func buildContentPattern(
        patternId: String,
        patternName: String,
        chunks: [(video: YouTubeVideo, chunk: Chunk)],
        totalChunks: Int
    ) -> ContentPattern {

        let frequency = Double(chunks.count) / Double(max(1, totalChunks))

        let avgSentenceCount = chunks.isEmpty ? 0 :
            Double(chunks.reduce(0) { $0 + $1.chunk.sentenceCount }) / Double(chunks.count)

        // Position range
        let positions = chunks.map { $0.chunk.positionInVideo }
        let positionRange = PositionRange(
            start: positions.min() ?? 0,
            end: positions.max() ?? 1
        )

        let dominantPerspective = findDominantValue(
            chunks.map { $0.chunk.profile.dominantPerspective }
        )
        let dominantStance = findDominantValue(
            chunks.map { $0.chunk.profile.dominantStance }
        )

        let avgTagDensity = averageTagDensities(chunks.map { $0.chunk.profile.tagDensity })

        // Entry/exit triggers
        let entryTrigger = findMostCommonTrigger(chunks.map { $0.chunk })
        let exitTrigger: BoundaryTrigger.BoundaryTriggerType? = nil  // Would need next chunk info

        // Examples
        let examples = chunks.prefix(3).map { item in
            ChunkExample(
                videoId: item.video.videoId,
                videoTitle: item.video.title,
                chunkIndex: item.chunk.chunkIndex,
                sentenceCount: item.chunk.sentenceCount,
                preview: item.chunk.preview,
                position: item.chunk.positionInVideo
            )
        }

        return ContentPattern(
            patternId: patternId,
            patternName: patternName,
            frequency: frequency,
            averageSentenceCount: avgSentenceCount,
            typicalPosition: positionRange,
            dominantPerspective: dominantPerspective,
            dominantStance: dominantStance,
            typicalTagDensity: avgTagDensity,
            typicalEntryTrigger: entryTrigger,
            typicalExitTrigger: exitTrigger,
            exampleChunks: Array(examples)
        )
    }

    // MARK: - Style Metrics

    private func calculateStyleMetrics(
        from results: [(video: YouTubeVideo, result: BoundaryDetectionResult)]
    ) -> StyleMetrics {

        var allChunks: [Chunk] = []
        for (_, result) in results {
            allChunks.append(contentsOf: result.chunks)
        }

        guard !allChunks.isEmpty else {
            return StyleMetrics(
                firstPersonUsage: 0, secondPersonUsage: 0, thirdPersonUsage: 0,
                assertingUsage: 0, questioningUsage: 0, challengingUsage: 0,
                statisticDensity: 0, entityDensity: 0, quoteDensity: 0,
                averageChunksPerVideo: 0, averageSentencesPerChunk: 0,
                contrastMarkerFrequency: 0, revealLanguageFrequency: 0,
                challengeLanguageFrequency: 0
            )
        }

        // Perspective usage
        let perspectives = allChunks.map { $0.profile.dominantPerspective }
        let firstPersonUsage = Double(perspectives.filter { $0 == .first }.count) / Double(perspectives.count)
        let secondPersonUsage = Double(perspectives.filter { $0 == .second }.count) / Double(perspectives.count)
        let thirdPersonUsage = Double(perspectives.filter { $0 == .third }.count) / Double(perspectives.count)

        // Stance usage
        let stances = allChunks.map { $0.profile.dominantStance }
        let assertingUsage = Double(stances.filter { $0 == .asserting }.count) / Double(stances.count)
        let questioningUsage = Double(stances.filter { $0 == .questioning }.count) / Double(stances.count)
        let challengingUsage = Double(stances.filter { $0 == .challenging }.count) / Double(stances.count)

        // Tag densities
        let avgDensity = averageTagDensities(allChunks.map { $0.profile.tagDensity })

        // Structural
        let avgChunksPerVideo = Double(allChunks.count) / Double(max(1, results.count))
        let avgSentencesPerChunk = Double(allChunks.reduce(0) { $0 + $1.sentenceCount }) / Double(allChunks.count)

        return StyleMetrics(
            firstPersonUsage: firstPersonUsage,
            secondPersonUsage: secondPersonUsage,
            thirdPersonUsage: thirdPersonUsage,
            assertingUsage: assertingUsage,
            questioningUsage: questioningUsage,
            challengingUsage: challengingUsage,
            statisticDensity: avgDensity.hasStatistic,
            entityDensity: avgDensity.hasNamedEntity,
            quoteDensity: avgDensity.hasQuote,
            averageChunksPerVideo: avgChunksPerVideo,
            averageSentencesPerChunk: avgSentencesPerChunk,
            contrastMarkerFrequency: avgDensity.hasContrastMarker,
            revealLanguageFrequency: avgDensity.hasRevealLanguage,
            challengeLanguageFrequency: avgDensity.hasChallengeLanguage
        )
    }

    // MARK: - Helpers

    private func findDominantValue(_ values: [ChunkProfile.DominantValue]) -> ChunkProfile.DominantValue {
        guard !values.isEmpty else { return .mixed }

        var counts: [ChunkProfile.DominantValue: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }

        return counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.rawValue < $1.key.rawValue  // Deterministic tie-breaker
        }.first?.key ?? .mixed
    }

    private func averageTagDensities(_ densities: [TagDensity]) -> AveragedTagDensity {
        guard !densities.isEmpty else { return .empty }

        let count = Double(densities.count)

        return AveragedTagDensity(
            hasNumber: densities.reduce(0) { $0 + $1.hasNumber } / count,
            hasStatistic: densities.reduce(0) { $0 + $1.hasStatistic } / count,
            hasNamedEntity: densities.reduce(0) { $0 + $1.hasNamedEntity } / count,
            hasQuote: densities.reduce(0) { $0 + $1.hasQuote } / count,
            hasContrastMarker: densities.reduce(0) { $0 + $1.hasContrastMarker } / count,
            hasRevealLanguage: densities.reduce(0) { $0 + $1.hasRevealLanguage } / count,
            hasChallengeLanguage: densities.reduce(0) { $0 + $1.hasChallengeLanguage } / count,
            hasFirstPerson: densities.reduce(0) { $0 + $1.hasFirstPerson } / count,
            hasSecondPerson: densities.reduce(0) { $0 + $1.hasSecondPerson } / count,
            isTransition: densities.reduce(0) { $0 + $1.isTransition } / count,
            isSponsorContent: densities.reduce(0) { $0 + $1.isSponsorContent } / count,
            isCallToAction: densities.reduce(0) { $0 + $1.isCallToAction } / count
        )
    }

    private func calculateTriggerFrequencies(_ chunks: [Chunk]) -> [TriggerFrequency] {
        var counts: [BoundaryTrigger.BoundaryTriggerType: Int] = [:]

        for chunk in chunks {
            if let trigger = chunk.profile.boundaryTrigger {
                counts[trigger.type, default: 0] += 1
            }
        }

        let total = max(1, chunks.count)

        return counts.map { type, count in
            TriggerFrequency(
                triggerType: type,
                frequency: Double(count) / Double(total),
                count: count
            )
        }.sorted {
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            return $0.triggerType.rawValue < $1.triggerType.rawValue  // Deterministic tie-breaker
        }
    }

    private func findMostCommonTrigger(_ chunks: [Chunk]) -> BoundaryTrigger.BoundaryTriggerType? {
        let freqs = calculateTriggerFrequencies(chunks)
        return freqs.first?.triggerType
    }

    private func extractExampleSentences(
        from chunks: [(video: YouTubeVideo, chunk: Chunk)],
        limit: Int
    ) -> [ExampleSentence] {

        var examples: [ExampleSentence] = []

        for (video, chunk) in chunks.prefix(limit) {
            if let sentence = chunk.sentences.first {
                let tags = buildTagList(sentence)
                examples.append(ExampleSentence(
                    videoId: video.videoId,
                    videoTitle: video.title,
                    sentenceIndex: sentence.sentenceIndex,
                    text: sentence.text,
                    tags: tags
                ))
            }
        }

        return examples
    }

    private func buildTagList(_ s: SentenceTelemetry) -> [String] {
        var tags: [String] = []
        if s.hasNumber { tags.append("NUM") }
        if s.hasStatistic { tags.append("STAT") }
        if s.hasNamedEntity { tags.append("ENT") }
        if s.hasQuote { tags.append("QUOTE") }
        if s.hasFirstPerson { tags.append("1P") }
        if s.hasSecondPerson { tags.append("2P") }
        if s.hasContrastMarker { tags.append("CONTRAST") }
        if s.hasRevealLanguage { tags.append("REVEAL") }
        if s.hasChallengeLanguage { tags.append("CHALLENGE") }
        if s.isTransition { tags.append("TRANS") }
        return tags
    }

    // MARK: - Export

    func exportTemplateAsText(_ template: CreatorTemplate, videos: [YouTubeVideo] = []) -> String {
        // Build video lookup dictionary
        let videoLookup = Dictionary(uniqueKeysWithValues: videos.map { ($0.videoId, $0) })

        var text = """
        ══════════════════════════════════════════════════════════════════
        CREATOR TEMPLATE: \(template.channelName)
        Created AT: \(Date())
        ══════════════════════════════════════════════════════════════════
        Generated: \(template.createdAt.formatted())
        Videos Analyzed: \(template.videosAnalyzed)

        """

        // Add structural templates if available
        if let clustering = currentClusteringResult, !clustering.templates.isEmpty {
            text += """

        ════════════════════════════════════════════════════════════════════
        STRUCTURAL TEMPLATES (\(clustering.templates.count) distinct patterns)
        ════════════════════════════════════════════════════════════════════
        Coverage: \(formatPercent(clustering.coveragePercent)) of videos fit a template

        """
            for template in clustering.templates.sorted(by: { $0.videoCount > $1.videoCount }) {
                text += formatStructuralTemplate(template, videoLookup: videoLookup)
                text += "\n"
            }

            // Add outliers with full breakdown
            if !clustering.outlierVideoIds.isEmpty {
                text += """

        ════════════════════════════════════════════════════════════════════
        OUTLIER VIDEOS (\(clustering.outlierVideoIds.count) videos with unique structure)
        ════════════════════════════════════════════════════════════════════

        """
                for outlierId in clustering.outlierVideoIds {
                    if let structure = clustering.videoStructures.first(where: { $0.videoId == outlierId }) {
                        text += formatOutlierVideo(structure)
                        text += "\n"
                    }
                }
            }
        }

        text += """

        ────────────────────────────────────────────────────────────────────
        STYLE METRICS
        ────────────────────────────────────────────────────────────────────
        Perspective Usage:
          • First Person: \(formatPercent(template.styleMetrics.firstPersonUsage))
          • Second Person: \(formatPercent(template.styleMetrics.secondPersonUsage))
          • Third Person: \(formatPercent(template.styleMetrics.thirdPersonUsage))

        Stance Distribution:
          • Asserting: \(formatPercent(template.styleMetrics.assertingUsage))
          • Questioning: \(formatPercent(template.styleMetrics.questioningUsage))
          • Challenging: \(formatPercent(template.styleMetrics.challengingUsage))

        Content Density:
          • Statistics: \(formatPercent(template.styleMetrics.statisticDensity))
          • Named Entities: \(formatPercent(template.styleMetrics.entityDensity))
          • Quotes: \(formatPercent(template.styleMetrics.quoteDensity))

        Engagement Features:
          • Contrast Markers: \(formatPercent(template.styleMetrics.contrastMarkerFrequency))
          • Reveal Language: \(formatPercent(template.styleMetrics.revealLanguageFrequency))
          • Challenge Language: \(formatPercent(template.styleMetrics.challengeLanguageFrequency))

        Structure:
          • Avg Chunks/Video: \(String(format: "%.1f", template.styleMetrics.averageChunksPerVideo))
          • Avg Sentences/Chunk: \(String(format: "%.1f", template.styleMetrics.averageSentencesPerChunk))

        ────────────────────────────────────────────────────────────────────
        OPENING PATTERN
        ────────────────────────────────────────────────────────────────────
        \(formatSectionPattern(template.openingPattern))

        ────────────────────────────────────────────────────────────────────
        CLOSING PATTERN
        ────────────────────────────────────────────────────────────────────
        \(formatSectionPattern(template.closingPattern))

        ────────────────────────────────────────────────────────────────────
        CONTENT PATTERNS (\(template.contentPatterns.count))
        ────────────────────────────────────────────────────────────────────
        """

        for pattern in template.contentPatterns {
            text += "\n\n\(formatContentPattern(pattern))"
        }

        return text
    }

    private func formatStructuralTemplate(_ template: StructuralTemplate, videoLookup: [String: YouTubeVideo] = [:]) -> String {
        var text = """
        ───────────────────────────────────────────────────────────
        TEMPLATE: "\(template.templateName)" (used in \(template.videoCount) videos)
        ───────────────────────────────────────────────────────────
        Typical chunk sequence:
        """

        for chunk in template.typicalSequence {
            let pivotMark = chunk.isPivotPoint ? " ← PIVOT" : ""
            let tagStr = chunk.highTags.isEmpty ? "" : " - high \(chunk.highTags.joined(separator: ", "))"
            text += "\n  \(chunk.chunkIndex + 1). \(chunk.positionLabel) \(chunk.typicalRole)\(tagStr)\(pivotMark)"
        }

        if !template.keyPivots.isEmpty {
            let pivotStr = template.keyPivots.map { "Chunk \(Int($0.position * 10) + 1) (\($0.label))" }.joined(separator: ", ")
            text += "\n\nKey pivots: \(pivotStr)"
        }

        if !template.videoIds.isEmpty {
            text += "\nSimilar videos (\(template.videoIds.count)):\n"
            for (index, videoId) in template.videoIds.enumerated() {
                if let video = videoLookup[videoId] {
                    // Format with stats: title | duration | word count | WPM
                    text += "  • \(video.title) | \(video.templateStatsString)\n"
                } else if index < template.exampleVideoTitles.count {
                    // Fallback to title if video not in lookup
                    text += "  • \(template.exampleVideoTitles[index])\n"
                } else {
                    text += "  • [Video ID: \(videoId)]\n"
                }
            }
        }

        return text
    }

    private func formatSectionPattern(_ pattern: SectionPattern) -> String {
        var text = """
        Avg Chunks: \(String(format: "%.1f", pattern.averageChunkCount))
        Avg Sentences: \(String(format: "%.1f", pattern.averageSentenceCount))
        Perspective: \(pattern.dominantPerspective.rawValue)
        Stance: \(pattern.dominantStance.rawValue)

        Top Tags:
        """
        for tag in pattern.typicalTagDensity.topTags {
            text += "\n  • \(tag.name): \(formatPercent(tag.value))"
        }

        if !pattern.exampleSentences.isEmpty {
            text += "\n\nExamples:"
            for example in pattern.exampleSentences.prefix(3) {
                text += "\n  \"\(example.text.prefix(80))...\""
            }
        }

        return text
    }

    private func formatContentPattern(_ pattern: ContentPattern) -> String {
        """
        [\(pattern.patternName)] - \(formatPercent(pattern.frequency)) of chunks
        Position: \(pattern.typicalPosition.label)
        Avg Sentences: \(String(format: "%.1f", pattern.averageSentenceCount))
        Perspective: \(pattern.dominantPerspective.rawValue)
        Stance: \(pattern.dominantStance.rawValue)
        """
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }

    private func formatOutlierVideo(_ structure: VideoStructure) -> String {
        var text = """
        ───────────────────────────────────────────────────────────
        OUTLIER: \(structure.videoTitle)
        ───────────────────────────────────────────────────────────
        Video ID: \(structure.videoId)
        Chunks: \(structure.chunkCount) | Sentences: \(structure.totalSentences)
        Pivot Points: \(structure.pivotPositions.count)
        Fingerprint Pattern: \(structure.fingerprint.dominantPattern)

        Structural Sequence:
        """

        for snapshot in structure.sequence {
            let pivotMark = snapshot.isPivot ? " ← PIVOT (\(snapshot.pivotReason ?? "shift"))" : ""
            let tags = snapshot.topTags.isEmpty ? "" : " [\(snapshot.topTags.joined(separator: ", "))]"
            let posLabel = String(format: "[%.0f%%]", snapshot.position * 100)
            text += "\n  \(snapshot.chunkIndex + 1). \(posLabel) - \(snapshot.dominantPerspective.rawValue)/\(snapshot.dominantStance.rawValue)\(tags)\(pivotMark)"
        }

        // Show why it didn't cluster
        if structure.pivotPositions.isEmpty {
            text += "\n\n  ⚠️ No pivot points detected - unusual structure"
        } else if structure.pivotPositions.count > 5 {
            text += "\n\n  ⚠️ Many pivot points (\(structure.pivotPositions.count)) - erratic structure"
        }

        let pattern = structure.fingerprint.dominantPattern
        if pattern == "standard" {
            text += "\n  ⚠️ Generic pattern - didn't match any discovered template"
        }

        text += "\n"
        return text
    }
}
