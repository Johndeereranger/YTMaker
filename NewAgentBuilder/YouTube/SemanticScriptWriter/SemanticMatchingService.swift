//
//  SemanticMatchingService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

/// Service for analyzing rambling content and matching to corpus templates
@MainActor
class SemanticMatchingService: ObservableObject {
    static let shared = SemanticMatchingService()

    @Published var isAnalyzing = false
    @Published var analysisProgress = ""

    private init() {}

    // MARK: - Live Tag Detection (Cheap, runs as user types)

    /// Detect content tags from rambling text (lightweight, regex-based)
    func detectTags(in text: String) -> [DetectedTag] {
        var tags: [DetectedTag] = []

        // Detect statistics/numbers
        let statPatterns = [
            #"\b\d+\.?\d*\s*%"#,           // percentages
            #"\b\d{2,}\b"#,                 // numbers with 2+ digits
            #"\b\d+\s*(out of|of)\s*\d+"#,  // "X out of Y"
            #"\$\d+[,\d]*"#                 // dollar amounts
        ]
        for pattern in statPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        tags.append(DetectedTag(type: .statistic, text: String(text[range]), range: range))
                    }
                }
            }
        }

        // Detect contrast patterns
        let contrastPatterns = [
            #"(?i)\bbut\s+(?:the\s+)?(?:data|evidence|research|studies?)\b"#,
            #"(?i)\b(?:most|many)\s+(?:people|hunters|experts?)\s+(?:think|believe|assume)\b"#,
            #"(?i)\bconventional\s+wisdom\b"#,
            #"(?i)\b(?:actually|in\s+fact|however|contrary)\b"#,
            #"(?i)\bthink\s+X\s+but\b"#
        ]
        for pattern in contrastPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        tags.append(DetectedTag(type: .contrast, text: String(text[range]), range: range))
                    }
                }
            }
        }

        // Detect credentials
        let credentialPatterns = [
            #"(?i)\bI(?:'ve|'m|\s+have|\s+am)\s+(?:been\s+)?(?:running|studying|researching|testing|analyzing)"#,
            #"(?i)\bmy\s+(?:data|research|study|analysis|experience)\b"#,
            #"(?i)\b(?:years?|months?|decades?)\s+of\s+(?:research|data|experience)\b"#
        ]
        for pattern in credentialPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        tags.append(DetectedTag(type: .credential, text: String(text[range]), range: range))
                    }
                }
            }
        }

        // Detect questions
        let questionPattern = #"[^.!?]*\?"#
        if let regex = try? NSRegularExpression(pattern: questionPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    tags.append(DetectedTag(type: .question, text: String(text[range]).trimmingCharacters(in: .whitespaces), range: range))
                }
            }
        }

        return tags
    }

    /// Detect content gaps (what's missing)
    func detectGaps(tags: [DetectedTag], text: String) -> [ContentGap] {
        var gaps: [ContentGap] = []

        // Check for missing elements
        let hasStats = tags.contains { $0.type == .statistic }
        let hasContrast = tags.contains { $0.type == .contrast }
        let hasCredential = tags.contains { $0.type == .credential }

        if !hasStats {
            gaps.append(ContentGap(type: .noData, description: "Add specific numbers or data points"))
        }

        if !hasContrast {
            gaps.append(ContentGap(type: .noContrast, description: "Consider adding tension: 'Most think X, but...'"))
        }

        if !hasCredential {
            gaps.append(ContentGap(type: .noCredential, description: "Add your source or credential"))
        }

        // Check if text is too short/vague
        let wordCount = text.split(separator: " ").count
        if wordCount < 50 {
            gaps.append(ContentGap(type: .vague, description: "Add more detail - current content may be too brief to match"))
        }

        // Check for "so what"
        let applicationPatterns = [
            #"(?i)\bthis\s+means\b"#,
            #"(?i)\bso\s+(?:what|you|hunters?|the)\b"#,
            #"(?i)\bimplication\b"#,
            #"(?i)\bwhy\s+(?:this|it)\s+matters\b"#
        ]
        var hasApplication = false
        for pattern in applicationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil {
                hasApplication = true
                break
            }
        }
        if !hasApplication {
            gaps.append(ContentGap(type: .noApplication, description: "Add 'so what' - why does this matter?"))
        }

        return gaps
    }

    // MARK: - Full Analysis (Expensive, runs on button press)

    /// Analyze rambling and match to corpus templates
    func analyzeAndMatch(
        rambling: String,
        studyCreators: [YouTubeChannel]
    ) async -> RamblingAnalysis? {
        isAnalyzing = true
        analysisProgress = "Detecting content patterns..."

        // Step 1: Detect tags
        let tags = detectTags(in: rambling)
        let gaps = detectGaps(tags: tags, text: rambling)

        analysisProgress = "Loading study creator templates..."

        // Step 2: Load templates for each study creator
        var allTemplates: [(channel: YouTubeChannel, template: StructuralTemplate)] = []

        for channel in studyCreators.filter({ $0.isStudyCreator }) {
            analysisProgress = "Loading \(channel.name)..."

            // Load sentence data for this channel's videos
            do {
                let videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channel.channelId)
                var sentenceData: [String: [SentenceFidelityTest]] = [:]

                for video in videos {
                    let runs = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
                    if !runs.isEmpty {
                        sentenceData[video.videoId] = runs
                    }
                }

                // Skip if not enough data
                let videosWithData = videos.filter { sentenceData[$0.videoId] != nil }
                if videosWithData.count < 3 { continue }

                // Extract template
                if let template = await TemplateExtractionService.shared.extractTemplate(
                    channel: channel,
                    videos: videos,
                    sentenceData: sentenceData
                ) {
                    // Get structural templates from clustering result
                    if let clustering = TemplateExtractionService.shared.currentClusteringResult {
                        for structTemplate in clustering.templates {
                            allTemplates.append((channel, structTemplate))
                        }
                    }
                }
            } catch {
                print("Failed to load templates for \(channel.name): \(error)")
                continue
            }
        }

        analysisProgress = "Matching content to templates..."

        // Step 3: Score templates against rambling content
        var matches: [TemplateMatch] = []

        for (channel, template) in allTemplates {
            let score = scoreTemplateMatch(rambling: rambling, tags: tags, template: template)
            let reason = generateMatchReason(tags: tags, template: template)

            matches.append(TemplateMatch(
                channelId: channel.channelId,
                channelName: channel.name,
                templateName: template.templateName,
                template: template,
                matchScore: score,
                matchReason: reason
            ))
        }

        // Sort by score and take top matches
        let topMatches = matches
            .sorted { $0.matchScore > $1.matchScore }
            .prefix(5)

        // Generate content summary
        let summary = generateContentSummary(tags: tags)

        isAnalyzing = false
        analysisProgress = ""

        return RamblingAnalysis(
            detectedTags: tags,
            gaps: gaps,
            contentSummary: summary,
            suggestedMatches: Array(topMatches)
        )
    }

    // MARK: - Template Scoring

    private func scoreTemplateMatch(
        rambling: String,
        tags: [DetectedTag],
        template: StructuralTemplate
    ) -> Double {
        var score = 0.0

        // Check if rambling content characteristics match template's dominant characteristics
        let hasStats = tags.contains { $0.type == .statistic }
        let hasContrast = tags.contains { $0.type == .contrast }
        let hasCredential = tags.contains { $0.type == .credential }
        let hasQuestions = tags.contains { $0.type == .question }

        // Match based on template characteristics
        for char in template.dominantCharacteristics {
            if char.contains("stat") && hasStats { score += 0.2 }
            if char.contains("contrast") && hasContrast { score += 0.2 }
            if char.contains("1P") && hasCredential { score += 0.15 }
            if char.contains("question") && hasQuestions { score += 0.15 }
        }

        // Check for pivot alignment (contrast in rambling = good fit for templates with pivots)
        if hasContrast && !template.keyPivots.isEmpty {
            score += 0.2
        }

        // Bonus for templates with more videos (more robust pattern)
        if template.videoCount >= 5 { score += 0.1 }

        return min(1.0, score)
    }

    private func generateMatchReason(
        tags: [DetectedTag],
        template: StructuralTemplate
    ) -> String {
        var reasons: [String] = []

        let hasStats = tags.contains { $0.type == .statistic }
        let hasContrast = tags.contains { $0.type == .contrast }

        if hasStats && template.dominantCharacteristics.contains(where: { $0.contains("stat") }) {
            reasons.append("Data-heavy content fits evidence structure")
        }

        if hasContrast && !template.keyPivots.isEmpty {
            reasons.append("Contrast pattern aligns with template pivots")
        }

        if template.dominantCharacteristics.contains(where: { $0.contains("1P") }) {
            reasons.append("First-person narrative style")
        }

        return reasons.isEmpty ? "General content match" : reasons.joined(separator: "; ")
    }

    private func generateContentSummary(tags: [DetectedTag]) -> String {
        var parts: [String] = []

        let statCount = tags.filter { $0.type == .statistic }.count
        let contrastCount = tags.filter { $0.type == .contrast }.count
        let questionCount = tags.filter { $0.type == .question }.count

        if statCount > 0 { parts.append("high STAT (\(statCount))") }
        if contrastCount > 0 { parts.append("CONTRAST present") }
        if questionCount > 0 { parts.append("\(questionCount) questions") }

        return parts.isEmpty ? "General content" : parts.joined(separator: ", ")
    }

    // MARK: - Slot Filling

    /// Fill template slots with rambling content
    func fillTemplateSlots(
        template: StructuralTemplate,
        rambling: String,
        tags: [DetectedTag]
    ) -> FilledTemplate {
        // Split rambling into sentences/chunks
        let sentences = splitIntoSentences(rambling)
        var usedSentenceIndices = Set<Int>()
        var slots: [FilledSlot] = []

        for chunk in template.typicalSequence {
            // Find sentences that best match this chunk's characteristics
            var mappedContent: [String] = []
            var chunkGaps: [String] = []

            // Look for content that matches chunk's high tags
            for (index, sentence) in sentences.enumerated() {
                guard !usedSentenceIndices.contains(index) else { continue }

                let sentenceTags = detectTags(in: sentence)
                let sentenceTagTypes = Set(sentenceTags.map { $0.type.rawValue })
                let chunkTagTypes = Set(chunk.highTags)

                // Check for overlap
                if !sentenceTagTypes.intersection(chunkTagTypes).isEmpty ||
                   (mappedContent.isEmpty && chunk.typicalRole.lowercased().contains("opening")) {
                    mappedContent.append(sentence)
                    usedSentenceIndices.insert(index)
                }
            }

            // Detect gaps
            if mappedContent.isEmpty {
                chunkGaps.append("No content mapped for: \(chunk.typicalRole)")
            }

            if chunk.highTags.contains("STAT") && !mappedContent.joined().contains(where: { $0.isNumber }) {
                chunkGaps.append("Template expects specific numbers")
            }

            slots.append(FilledSlot(
                chunkIndex: chunk.chunkIndex,
                templateChunk: chunk,
                mappedContent: mappedContent.joined(separator: " "),
                gaps: chunkGaps,
                overflow: []
            ))
        }

        // Collect unmapped content as parking lot
        var parkingLot: [String] = []
        for (index, sentence) in sentences.enumerated() {
            if !usedSentenceIndices.contains(index) {
                parkingLot.append(sentence)
            }
        }

        return FilledTemplate(
            match: TemplateMatch(
                channelId: template.channelId,
                channelName: "",  // Will be filled by caller
                templateName: template.templateName,
                template: template,
                matchScore: 0,
                matchReason: ""
            ),
            slots: slots,
            parkingLot: parkingLot
        )
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        // Simple sentence splitting
        let pattern = #"[^.!?]+[.!?]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [text]
        }

        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Section Generation

    /// Generate one section using corpus patterns as context
    func generateSection(
        slot: FilledSlot,
        template: StructuralTemplate,
        channelId: String
    ) async throws -> GeneratedSection {
        // Query corpus for sentence patterns at this position
        let patterns = try await querySentencePatterns(
            position: slot.templateChunk.positionStart,
            channelId: channelId,
            highTags: slot.templateChunk.highTags
        )

        // Build context for generation
        let context = buildGenerationContext(
            slot: slot,
            patterns: patterns
        )

        // Generate using Claude
        let generatedText = try await generateWithContext(
            userContent: slot.mappedContent,
            templateGuidance: slot.templateGuidance,
            context: context
        )

        // Parse into sentences with sources
        let sentences = parseGeneratedSentences(
            text: generatedText,
            patterns: patterns
        )

        return GeneratedSection(
            slotIndex: slot.chunkIndex,
            sentences: sentences,
            generatedAt: Date()
        )
    }

    private func querySentencePatterns(
        position: Double,
        channelId: String,
        highTags: [String]
    ) async throws -> [SentenceTelemetry] {
        // Load sentence data for this channel
        let videos = try await YouTubeFirebaseService.shared.getVideos(forChannel: channelId)
        var matchingPatterns: [SentenceTelemetry] = []

        for video in videos.prefix(10) {  // Limit for performance
            let runs = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
            guard let latestRun = runs.first else { continue }

            // Find sentences at similar position with matching tags
            let totalSentences = latestRun.sentences.count
            let targetIndex = Int(position * Double(totalSentences))
            let range = max(0, targetIndex - 5)...min(totalSentences - 1, targetIndex + 5)

            for index in range where index < latestRun.sentences.count {
                let sentence = latestRun.sentences[index]

                // Check tag match
                var matches = 0
                if highTags.contains("STAT") && sentence.hasStatistic { matches += 1 }
                if highTags.contains("CONTRAST") && sentence.hasContrastMarker { matches += 1 }
                if highTags.contains("1P") && sentence.hasFirstPerson { matches += 1 }
                if highTags.contains("2P") && sentence.hasSecondPerson { matches += 1 }

                if matches > 0 {
                    matchingPatterns.append(sentence)
                }
            }
        }

        // Return top matching patterns
        return Array(matchingPatterns.prefix(10))
    }

    private func buildGenerationContext(
        slot: FilledSlot,
        patterns: [SentenceTelemetry]
    ) -> String {
        var context = "CORPUS PATTERNS FOR THIS SECTION:\n\n"

        for (index, pattern) in patterns.prefix(5).enumerated() {
            context += "\(index + 1). \"\(pattern.text)\"\n"
        }

        context += "\nTEMPLATE GUIDANCE: \(slot.templateGuidance)\n"
        context += "POSITION: \(slot.templateChunk.positionLabel)\n"

        if slot.templateChunk.isPivotPoint {
            context += "NOTE: This is a PIVOT point - include contrast or revelation\n"
        }

        return context
    }

    private func generateWithContext(
        userContent: String,
        templateGuidance: String,
        context: String
    ) async -> String {
        // Use ClaudeModelAdapter for generation
        let prompt = """
        You are a script writer. Generate 3-5 sentences for this section of a YouTube script.

        USER'S CONTENT/NOTES:
        \(userContent)

        TEMPLATE GUIDANCE:
        \(templateGuidance)

        \(context)

        Write the section now. Match the style and structure of the corpus patterns while incorporating the user's specific content. Output ONLY the script text, no commentary.
        """

        let systemPrompt = "You are a YouTube script writer. Write concise, engaging script sections."

        let adapter = ClaudeModelAdapter()
        let response = await adapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.7, "max_tokens": 1000]
        )

        return response
    }

    private func parseGeneratedSentences(
        text: String,
        patterns: [SentenceTelemetry]
    ) -> [GeneratedSentence] {
        let sentences = splitIntoSentences(text)

        return sentences.enumerated().map { index, sentenceText in
            // Try to find a matching pattern for source reference
            let matchingPattern = patterns.first { pattern in
                // Simple similarity check - could be improved
                let words1 = Set(sentenceText.lowercased().split(separator: " "))
                let words2 = Set(pattern.text.lowercased().split(separator: " "))
                let overlap = words1.intersection(words2)
                return Double(overlap.count) / Double(max(words1.count, words2.count)) > 0.3
            }

            var sourceRef: SourceReference? = nil
            if let pattern = matchingPattern {
                sourceRef = SourceReference(
                    videoId: "",  // Would need to track this
                    videoTitle: "Corpus Match",
                    channelName: "",
                    timestamp: nil,
                    matchedSentence: pattern.text,
                    surroundingContext: []
                )
            }

            return GeneratedSentence(
                text: sentenceText,
                sourceReference: sourceRef
            )
        }
    }
}
