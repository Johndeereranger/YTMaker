//
//  ShapeScriptWriterService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/27/26.
//

import Foundation

// MARK: - Shape Script Writer Service

/// Service for all AI calls in the Shape Script Writer flow
/// Handles: Content Extraction, Gap Analysis, Outline Generation, Script Writing
@MainActor
class ShapeScriptWriterService {
    static let shared = ShapeScriptWriterService()

    private let claude = ClaudeModelAdapter(model: .claude4Sonnet)

    private init() {}

    // MARK: - AI Response Result Type

    /// Result type that includes both parsed result and raw debug data
    struct AICallResult<T> {
        let result: T?
        let prompt: String
        let rawResponse: String
        let success: Bool
        let errorMessage: String?
    }

    // MARK: - AI Call #1: Content Extraction

    /// Extract structured content from raw rambling
    /// Input: Raw rambling text
    /// Output: ExtractedContent with hooks, points, evidence, aha, landing
    func extractContent(
        from rambling: String,
        onProgress: ((String) -> Void)? = nil
    ) async -> AICallResult<ExtractedContent> {
        onProgress?("Analyzing your rambling...")

        let systemPrompt = """
        You are a content analyst for video scripts. Your job is to extract structured information
        from unstructured "ramblings" - raw, stream-of-consciousness notes that someone wants to
        turn into a video script.

        Extract the following elements and return them as JSON:

        1. hookCandidates: Array of 2-4 potential opening hooks. These are statements or questions
           that could grab viewer attention in the first 10 seconds. Look for:
           - Surprising facts or contrarian takes
           - Questions that create curiosity
           - Bold claims or statements
           - Personal stories that create connection

        2. corePoints: Array of the main arguments or claims. These are the key things the speaker
           wants the audience to understand or believe by the end.

        3. evidenceExamples: Array of evidence, facts, statistics, quotes, or examples mentioned.
           Include anything that supports the core points.

        4. ahaRevelation: The single most important "aha" moment or insight. This is the "but here's
           the thing" moment that reframes everything. If there isn't a clear one, use null.

        5. landing: How should the viewer feel or what should they think at the end? What's the
           desired takeaway or call-to-action? If unclear, use null.

        Return ONLY valid JSON in this exact format:
        {
            "hookCandidates": ["hook1", "hook2"],
            "corePoints": ["point1", "point2"],
            "evidenceExamples": ["evidence1", "evidence2"],
            "ahaRevelation": "the key insight" or null,
            "landing": "desired ending feeling/action" or null
        }
        """

        let userPrompt = """
        Extract structured content from this rambling:

        ---
        \(rambling)
        ---

        Return ONLY the JSON, no other text.
        """

        let fullPrompt = "SYSTEM:\n\(systemPrompt)\n\nUSER:\n\(userPrompt)"

        let response = await claude.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 2000]
        )

        onProgress?("Parsing extraction results...")

        // Parse JSON response
        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            return AICallResult(
                result: nil,
                prompt: fullPrompt,
                rawResponse: response,
                success: false,
                errorMessage: "Failed to extract JSON from response"
            )
        }

        do {
            let decoded = try JSONDecoder().decode(ExtractedContentResponse.self, from: jsonData)
            let content = ExtractedContent(
                hookCandidates: decoded.hookCandidates,
                corePoints: decoded.corePoints,
                evidenceExamples: decoded.evidenceExamples,
                ahaRevelation: decoded.ahaRevelation,
                landing: decoded.landing,
                rawRambling: rambling
            )
            return AICallResult(
                result: content,
                prompt: fullPrompt,
                rawResponse: response,
                success: true,
                errorMessage: nil
            )
        } catch {
            return AICallResult(
                result: nil,
                prompt: fullPrompt,
                rawResponse: response,
                success: false,
                errorMessage: "JSON decode error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - AI Call #2: Gap Analysis

    /// Compare extracted content against creator's ingredient list
    /// Input: ExtractedContent + CreatorProfile
    /// Output: GapAnalysis with coverage score and questions
    func analyzeGaps(
        extractedContent: ExtractedContent,
        profile: CreatorProfile,
        onProgress: ((String) -> Void)? = nil
    ) async -> AICallResult<GapAnalysis> {
        onProgress?("Comparing against creator's style requirements...")

        // Build ingredient summary for prompt
        let requiredIngredients = profile.ingredientList.required.map {
            "- \($0.type): \($0.description)"
        }.joined(separator: "\n")

        let commonIngredients = profile.ingredientList.common.map {
            "- \($0.type): \($0.description)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a script development consultant. Your job is to identify CONTENT GAPS in the user's
        rambling - missing facts, evidence, examples, or narrative elements.

        IMPORTANT: You are NOT asking about style, voice, tone, or word choices. The creator's voice
        will be applied automatically from their profile. You are ONLY asking about missing CONTENT.

        CONTENT ELEMENTS THIS CREATOR'S VIDEOS TYPICALLY INCLUDE:

        REQUIRED CONTENT (must appear):
        \(requiredIngredients)

        COMMON CONTENT (usually appears):
        \(commonIngredients)

        Your task:
        1. Look at what was ALREADY EXTRACTED (marked ✅ in the input)
        2. Only identify gaps for content that is MISSING (marked ❌) or too weak/vague
        3. Calculate a coverage score (0-100) based on content completeness
        4. Generate questions ONLY for truly missing content - NOT for things already extracted
        5. If the extracted content is complete, return empty questions array with high score

        RULES FOR QUESTIONS:
        - ONLY ask about missing CONTENT (facts, data, examples, stories, evidence, pivot moments)
        - NEVER ask about style, voice, word choices, phrasing, or tone
        - NEVER ask "what words do you want to use" - the creator's words come from their profile
        - Focus on: "What happened?", "What's the evidence?", "What's the twist?", "What's an example?"

        GOOD QUESTION EXAMPLES:
        - "What specific data or numbers support your main claim?"
        - "What's the surprising twist or complication in this story?"
        - "Can you give a concrete example of [X] happening?"
        - "What's the 'aha moment' you want viewers to have?"

        BAD QUESTION EXAMPLES (NEVER ASK THESE):
        - "What contrast words do you want to use?" ← Style comes from profile
        - "How do you want to phrase the opening?" ← Style comes from profile
        - "What tone should the intro have?" ← Style comes from profile

        Return ONLY valid JSON:
        {
            "coverageScore": 65,
            "missingIngredients": ["ingredient-type-1", "ingredient-type-2"],
            "questions": [
                {
                    "question": "The specific CONTENT question to ask",
                    "reason": "What content element this fills",
                    "ingredientType": "which ingredient this fills",
                    "priority": 1
                }
            ]
        }
        """

        // Build a clear status of what we HAVE vs what's MISSING
        let hasHooks = !extractedContent.hookCandidates.isEmpty
        let hasPoints = !extractedContent.corePoints.isEmpty
        let hasEvidence = !extractedContent.evidenceExamples.isEmpty
        let hasAha = extractedContent.ahaRevelation != nil
        let hasLanding = extractedContent.landing != nil

        let userPrompt = """
        WHAT WE ALREADY EXTRACTED FROM THE USER'S RAMBLING:

        ✅ HOOKS: \(hasHooks ? "FOUND \(extractedContent.hookCandidates.count)" : "❌ MISSING")
        \(extractedContent.hookCandidates.map { "   - \($0)" }.joined(separator: "\n"))

        ✅ CORE POINTS: \(hasPoints ? "FOUND \(extractedContent.corePoints.count)" : "❌ MISSING")
        \(extractedContent.corePoints.map { "   - \($0)" }.joined(separator: "\n"))

        ✅ EVIDENCE/EXAMPLES: \(hasEvidence ? "FOUND \(extractedContent.evidenceExamples.count)" : "❌ MISSING")
        \(extractedContent.evidenceExamples.map { "   - \($0)" }.joined(separator: "\n"))

        \(hasAha ? "✅" : "❌") AHA MOMENT: \(extractedContent.ahaRevelation ?? "NOT FOUND - need to ask for this")

        \(hasLanding ? "✅" : "❌") LANDING/CONCLUSION: \(extractedContent.landing ?? "NOT FOUND - need to ask for this")

        ---

        INSTRUCTIONS:
        1. Do NOT ask for content we already have (marked ✅ above)
        2. ONLY ask for content that is ❌ MISSING or too weak/vague
        3. If everything looks good, return an empty questions array and high coverage score
        4. Remember: NEVER ask about style, voice, phrasing, or word choices - only ask for FACTS and CONTENT

        Return JSON with coverage score, missing ingredients, and questions (only for truly missing content).
        """

        let fullPrompt = "SYSTEM:\n\(systemPrompt)\n\nUSER:\n\(userPrompt)"

        let response = await claude.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.3, "max_tokens": 2000]
        )

        onProgress?("Processing gap analysis...")

        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            return AICallResult(
                result: nil,
                prompt: fullPrompt,
                rawResponse: response,
                success: false,
                errorMessage: "Failed to extract JSON from response"
            )
        }

        do {
            let decoded = try JSONDecoder().decode(GapAnalysisResponse.self, from: jsonData)
            let gaps = GapAnalysis(
                missingIngredients: decoded.missingIngredients,
                questions: decoded.questions.map { q in
                    GapQuestion(
                        question: q.question,
                        reason: q.reason,
                        ingredientType: q.ingredientType,
                        priority: q.priority
                    )
                },
                coverageScore: decoded.coverageScore
            )
            return AICallResult(
                result: gaps,
                prompt: fullPrompt,
                rawResponse: response,
                success: true,
                errorMessage: nil
            )
        } catch {
            return AICallResult(
                result: nil,
                prompt: fullPrompt,
                rawResponse: response,
                success: false,
                errorMessage: "JSON decode error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - AI Call #3: Outline Generation

    /// Generate section-by-section outline based on creator's shape
    /// Input: ExtractedContent + answers + CreatorProfile + length targets
    /// Output: ScriptOutline with sections and DB queries
    func generateOutline(
        extractedContent: ExtractedContent,
        questionAnswers: String,
        profile: CreatorProfile,
        targetMinutes: Int,
        targetWordCount: Int,
        targetSectionCount: Int,
        targetPivotCount: Int,
        wordsPerSection: Int,
        onProgress: ((String) -> Void)? = nil
    ) async -> AICallResult<ScriptOutline> {
        onProgress?("Building outline from creator's shape...")

        // Calculate position percentages for each section
        let positionPerSection = 100.0 / Double(targetSectionCount)

        // Calculate intro/middle/close section distribution
        // Intro: ~15% of sections, Middle: ~70%, Close: ~15%
        let introSections = max(1, Int(Double(targetSectionCount) * 0.15))
        let closeSections = max(1, Int(Double(targetSectionCount) * 0.15))
        let middleSections = targetSectionCount - introSections - closeSections

        let systemPrompt = """
        You are a video script architect. Create an outline that maps content to a creator's
        structural "shape" - their proven pattern for how videos flow.

        ═══════════════════════════════════════════════════════════════════
        TARGET LENGTH REQUIREMENTS (CRITICAL - YOU MUST HIT THESE NUMBERS)
        ═══════════════════════════════════════════════════════════════════

        TARGET: \(targetMinutes) minute video (~\(targetWordCount) words)

        SECTION COUNT: Generate EXACTLY \(targetSectionCount) outline sections
        - INTRO sections: \(introSections) sections (0-15% of video)
        - MIDDLE sections: \(middleSections) sections (15-85% of video)
        - CLOSE sections: \(closeSections) sections (85-100% of video)

        PIVOT COUNT: Include EXACTLY \(targetPivotCount) pivot moments (isPivot: true)

        WORDS PER SECTION: Each section should target ~\(wordsPerSection) words

        POSITION RANGES: Each section spans roughly \(String(format: "%.0f", positionPerSection))% of the video
        - Example: Section 1 = 0-\(Int(positionPerSection))%, Section 2 = \(Int(positionPerSection))-\(Int(positionPerSection * 2))%, etc.

        ═══════════════════════════════════════════════════════════════════
        CREATOR'S SHAPE (follow their patterns, but at the scale above)
        ═══════════════════════════════════════════════════════════════════

        INTRO STYLE (\(profile.shape.intro.typicalPositionRange)):
        - Name: \(profile.shape.intro.name)
        - Function: \(profile.shape.intro.description)
        - Key tags: \(profile.shape.intro.highTags.joined(separator: ", "))
        - Perspective: \(profile.shape.intro.dominantPerspective)

        MIDDLE STYLE (\(profile.shape.middle.typicalPositionRange)):
        - Name: \(profile.shape.middle.name)
        - Description: \(profile.shape.middle.description)
        - Key tags: \(profile.shape.middle.dominantTags.joined(separator: ", "))
        - Block types to use: \(profile.shape.middle.commonBlockTypes.map { $0.name }.joined(separator: ", "))

        CLOSE STYLE (\(profile.shape.close.typicalPositionRange)):
        - Name: \(profile.shape.close.name)
        - Function: \(profile.shape.close.description)
        - Key tags: \(profile.shape.close.highTags.joined(separator: ", "))
        - Perspective: \(profile.shape.close.dominantPerspective)

        ═══════════════════════════════════════════════════════════════════
        REQUIRED INGREDIENTS (must include sections for all of these)
        ═══════════════════════════════════════════════════════════════════
        \(profile.ingredientList.required.map { "- \($0.type): \($0.description)" }.joined(separator: "\n"))

        ═══════════════════════════════════════════════════════════════════
        INSTRUCTIONS
        ═══════════════════════════════════════════════════════════════════

        1. Generate EXACTLY \(targetSectionCount) sections (no more, no less)
        2. Distribute sections: \(introSections) INTRO → \(middleSections) MIDDLE → \(closeSections) CLOSE
        3. Mark EXACTLY \(targetPivotCount) sections as pivots (spread throughout middle)
        4. Each section's positionRange should span ~\(String(format: "%.0f", positionPerSection))%
        5. Use specific, descriptive sectionNames (e.g., "MIDDLE: The Population Discovery" not "MIDDLE: Section 3")
        6. contentSummary should describe what content from the rambling goes in that section

        Return ONLY valid JSON:
        {
            "estimatedLength": "\(targetMinutes) minutes",
            "structureNotes": "Brief note about the structure",
            "sections": [
                {
                    "sectionName": "INTRO: [Specific Name]",
                    "positionRange": "0-\(Int(positionPerSection))%",
                    "contentSummary": "What content goes here",
                    "targetTags": ["1P", "CONTRAST", "ENT"],
                    "isPivot": false
                }
            ]
        }
        """

        let userPrompt = """
        CONTENT TO ORGANIZE INTO \(targetSectionCount) SECTIONS:

        Hook Candidates:
        \(extractedContent.hookCandidates.map { "- \($0)" }.joined(separator: "\n"))

        Core Points:
        \(extractedContent.corePoints.map { "- \($0)" }.joined(separator: "\n"))

        Evidence/Examples:
        \(extractedContent.evidenceExamples.map { "- \($0)" }.joined(separator: "\n"))

        Aha Revelation: \(extractedContent.ahaRevelation ?? "None identified")

        Landing: \(extractedContent.landing ?? "None identified")

        \(questionAnswers.isEmpty ? "" : "ADDITIONAL ANSWERS FROM USER:\n\(questionAnswers)")

        ---

        Create an outline with EXACTLY \(targetSectionCount) sections and \(targetPivotCount) pivots.
        Return JSON only.
        """

        let fullPrompt = "SYSTEM:\n\(systemPrompt)\n\nUSER:\n\(userPrompt)"

        let response = await claude.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.4, "max_tokens": 3000]
        )

        onProgress?("Processing outline...")

        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            return AICallResult(
                result: nil,
                prompt: fullPrompt,
                rawResponse: response,
                success: false,
                errorMessage: "Failed to extract JSON from response"
            )
        }

        do {
            let decoded = try JSONDecoder().decode(ShapeOutlineResponse.self, from: jsonData)
            let outline = ScriptOutline(
                sections: decoded.sections.map { s in
                    ShapeOutlineSection(
                        sectionName: s.sectionName,
                        positionRange: s.positionRange,
                        contentSummary: s.contentSummary,
                        dbQuery: buildDBQuery(tags: s.targetTags, position: s.positionRange),
                        targetTags: s.targetTags,
                        isPivot: s.isPivot
                    )
                },
                estimatedLength: decoded.estimatedLength,
                structureNotes: decoded.structureNotes
            )
            return AICallResult(
                result: outline,
                prompt: fullPrompt,
                rawResponse: response,
                success: true,
                errorMessage: nil
            )
        } catch {
            return AICallResult(
                result: nil,
                prompt: fullPrompt,
                rawResponse: response,
                success: false,
                errorMessage: "JSON decode error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - AI Call #4: Section Writing

    /// Generate script text for a single section
    /// Input: OutlineSection + StyleFingerprint + DB examples
    /// Output: ShapeGeneratedSection with script text
    func writeSection(
        section: ShapeOutlineSection,
        profile: CreatorProfile,
        allContent: ExtractedContent,
        questionAnswers: String,
        styleExamples: [SentenceTelemetry],
        onProgress: ((String) -> Void)? = nil
    ) async -> ShapeGeneratedSection? {
        onProgress?("Writing \(section.sectionName)...")

        // Format style examples
        let examplesText = styleExamples.isEmpty
            ? "No examples available"
            : styleExamples.prefix(5).map { "- \"\($0.text)\"" }.joined(separator: "\n")

        let systemPrompt = """
        You are a script writer. Write a single section of a video script that matches a
        specific creator's voice and style.

        SECTION TO WRITE:
        - Name: \(section.sectionName)
        - Position: \(section.positionRange)
        - Target tags: \(section.targetTags.joined(separator: ", "))
        - Is pivot point: \(section.isPivot)

        CONTENT TO CONVEY:
        \(section.contentSummary)

        STYLE GUIDE:
        - Perspective mix: \(Int(profile.styleFingerprint.firstPersonUsage * 100))% first person ("I", "we"), \(Int(profile.styleFingerprint.secondPersonUsage * 100))% second person ("you")
        - Stance: \(Int(profile.styleFingerprint.assertingUsage * 100))% assertive (statements), \(Int(profile.styleFingerprint.questioningUsage * 100))% questioning
        - Use contrast markers ("but", "however", "actually") about \(Int(profile.styleFingerprint.contrastFrequency * 100))% of the time
        - Include named entities/specifics about \(Int(profile.styleFingerprint.entityDensity * 100))% of the time

        EXAMPLE SENTENCES FROM THIS CREATOR (match this voice):
        \(examplesText)

        RULES:
        1. Write 3-8 sentences for this section
        2. Match the creator's perspective and stance ratios
        3. Hit the target tags through your word choices
        4. If this is a PIVOT section, include a clear "turn" or reframe
        5. Write conversationally - this is spoken, not read

        Return ONLY the script text, no JSON, no labels, no quotes around it.
        """

        let userPrompt = """
        FULL CONTENT AVAILABLE:

        Core Points: \(allContent.corePoints.joined(separator: "; "))

        Evidence: \(allContent.evidenceExamples.joined(separator: "; "))

        Aha moment: \(allContent.ahaRevelation ?? "none")

        \(questionAnswers.isEmpty ? "" : "Additional context: \(questionAnswers)")

        ---

        Write the "\(section.sectionName)" section now. Output ONLY the script text.
        """

        let response = await claude.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.7, "max_tokens": 1000]
        )

        // Clean up response (remove any JSON wrapping if present)
        let scriptText = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = scriptText.split(separator: " ").count

        // Calculate confidence based on word count and section requirements
        let confidence = calculateConfidence(
            scriptText: scriptText,
            targetTags: section.targetTags,
            isPivot: section.isPivot
        )

        // Detect which tags were likely hit
        let tagsHit = detectTagsHit(in: scriptText, targetTags: section.targetTags)

        return ShapeGeneratedSection(
            sectionName: section.sectionName,
            scriptText: scriptText,
            wordCount: wordCount,
            tagsHit: tagsHit,
            confidence: confidence
        )
    }

    // MARK: - DB Query: Style Examples

    /// Query sentence data to find examples matching tags and position
    func findStyleExamples(
        channelId: String,
        targetTags: [String],
        positionRange: String,
        maxResults: Int = 5
    ) async -> [SentenceTelemetry] {
        // Parse position range (e.g., "15-35%")
        let (minPos, maxPos) = parsePositionRange(positionRange)

        do {
            // Get video IDs that have analysis for this channel
            let videoIds = try await SentenceFidelityFirebaseService.shared.getVideoIdsWithAnalysis(forChannelId: channelId)

            guard !videoIds.isEmpty else {
                print("No videos with analysis found for channel: \(channelId)")
                return []
            }

            // Get test runs for all videos
            let runsByVideo = try await SentenceFidelityFirebaseService.shared.getTestRunsForVideos(Array(videoIds))

            // Flatten all sentences from the most recent run of each video
            var allSentences: [SentenceTelemetry] = []
            for (_, runs) in runsByVideo {
                // Take the most recent run for each video
                if let latestRun = runs.first {
                    allSentences.append(contentsOf: latestRun.sentences)
                }
            }

            // Filter by position
            let filtered = allSentences.filter { sentence in
                sentence.positionPercentile >= minPos && sentence.positionPercentile <= maxPos
            }

            // Score by tag match
            let scored = filtered.map { sentence -> (SentenceTelemetry, Int) in
                var score = 0
                for tag in targetTags {
                    if matchesTag(sentence: sentence, tag: tag) {
                        score += 1
                    }
                }
                return (sentence, score)
            }

            // Sort by score descending, then take top results
            let sorted = scored.sorted { $0.1 > $1.1 }
            return sorted.prefix(maxResults).map { $0.0 }

        } catch {
            print("Failed to fetch style examples: \(error)")
            return []
        }
    }

    // MARK: - Helper Methods

    /// Extract JSON from a response that might have markdown code blocks
    private func extractJSON(from response: String) -> String? {
        // Try to find JSON in code blocks first
        if let match = response.range(of: "```json\\s*(.+?)\\s*```", options: .regularExpression) {
            let jsonBlock = String(response[match])
            let cleaned = jsonBlock
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }

        // Try to find JSON in generic code blocks
        if let match = response.range(of: "```\\s*(.+?)\\s*```", options: .regularExpression) {
            let jsonBlock = String(response[match])
            let cleaned = jsonBlock
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }

        // Try to find raw JSON (starts with { or [)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }

        // Try to extract JSON from anywhere in the response
        if let start = response.firstIndex(of: "{"),
           let end = response.lastIndex(of: "}") {
            return String(response[start...end])
        }

        return nil
    }

    /// Build a DB query string for finding examples
    private func buildDBQuery(tags: [String], position: String) -> String {
        "position:\(position), tags:\(tags.joined(separator: ","))"
    }

    /// Parse position range string like "15-35%" into (0.15, 0.35)
    private func parsePositionRange(_ range: String) -> (Double, Double) {
        let cleaned = range.replacingOccurrences(of: "%", with: "")
        let parts = cleaned.split(separator: "-")
        guard parts.count == 2,
              let min = Double(parts[0]),
              let max = Double(parts[1]) else {
            return (0.0, 1.0)
        }
        return (min / 100.0, max / 100.0)
    }

    /// Check if a sentence matches a tag
    private func matchesTag(sentence: SentenceTelemetry, tag: String) -> Bool {
        switch tag.uppercased() {
        case "1P", "FIRST":
            return sentence.hasFirstPerson
        case "2P", "SECOND":
            return sentence.hasSecondPerson
        case "3P", "THIRD":
            return sentence.perspective == "third"
        case "CONTRAST":
            return sentence.hasContrastMarker
        case "ENT", "ENTITY":
            return sentence.hasNamedEntity
        case "STAT", "STATISTIC":
            return sentence.hasStatistic
        case "QUOTE":
            return sentence.hasQuote
        case "REVEAL":
            return sentence.hasRevealLanguage
        case "CHALLENGE":
            return sentence.hasChallengeLanguage
        case "QUESTION":
            return sentence.endsWithQuestion
        case "ASSERTING":
            return sentence.stance == "asserting"
        case "QUESTIONING":
            return sentence.stance == "questioning"
        default:
            return false
        }
    }

    /// Calculate confidence score for generated section
    private func calculateConfidence(scriptText: String, targetTags: [String], isPivot: Bool) -> Int {
        var score = 70 // Base score

        // Check for tag indicators
        let text = scriptText.lowercased()

        for tag in targetTags {
            switch tag.uppercased() {
            case "1P", "FIRST":
                if text.contains(" i ") || text.contains("i'm") || text.contains("i've") || text.contains(" my ") {
                    score += 3
                }
            case "2P", "SECOND":
                if text.contains(" you ") || text.contains("you're") || text.contains(" your ") {
                    score += 3
                }
            case "CONTRAST":
                if text.contains("but ") || text.contains("however") || text.contains("actually") || text.contains("yet ") {
                    score += 3
                }
            case "ENT", "ENTITY":
                // Check for capitalized words (rough entity detection)
                let words = scriptText.split(separator: " ")
                let capitalizedCount = words.filter { $0.first?.isUppercase == true && $0.count > 1 }.count
                if capitalizedCount >= 2 {
                    score += 3
                }
            case "REVEAL":
                if text.contains("the truth") || text.contains("here's the thing") || text.contains("turns out") {
                    score += 3
                }
            default:
                break
            }
        }

        // Pivot sections should have contrast
        if isPivot && (text.contains("but") || text.contains("however") || text.contains("here's")) {
            score += 5
        }

        return min(score, 95) // Cap at 95
    }

    /// Detect which target tags were likely hit in the script
    private func detectTagsHit(in scriptText: String, targetTags: [String]) -> [String] {
        var hits: [String] = []
        let text = scriptText.lowercased()

        for tag in targetTags {
            var hit = false

            switch tag.uppercased() {
            case "1P", "FIRST":
                hit = text.contains(" i ") || text.contains("i'm") || text.contains("i've") || text.contains(" my ")
            case "2P", "SECOND":
                hit = text.contains(" you ") || text.contains("you're") || text.contains(" your ")
            case "CONTRAST":
                hit = text.contains("but ") || text.contains("however") || text.contains("actually")
            case "ENT", "ENTITY":
                let words = scriptText.split(separator: " ")
                hit = words.filter { $0.first?.isUppercase == true && $0.count > 1 }.count >= 2
            case "STAT", "STATISTIC":
                hit = text.range(of: "\\d+%|\\d+\\s*(million|billion|thousand|percent)", options: .regularExpression) != nil
            case "REVEAL":
                hit = text.contains("the truth") || text.contains("here's the thing") || text.contains("turns out")
            case "CHALLENGE":
                hit = text.contains("everyone thinks") || text.contains("you've been told") || text.contains("most people")
            case "QUESTION":
                hit = text.contains("?")
            default:
                break
            }

            if hit {
                hits.append(tag)
            }
        }

        return hits
    }
}

// MARK: - Response Models for JSON Decoding

private struct ExtractedContentResponse: Codable {
    let hookCandidates: [String]
    let corePoints: [String]
    let evidenceExamples: [String]
    let ahaRevelation: String?
    let landing: String?
}

private struct GapAnalysisResponse: Codable {
    let coverageScore: Int
    let missingIngredients: [String]
    let questions: [GapQuestionResponse]
}

private struct GapQuestionResponse: Codable {
    let question: String
    let reason: String
    let ingredientType: String
    let priority: Int
}

private struct ShapeOutlineResponse: Codable {
    let estimatedLength: String
    let structureNotes: String
    let sections: [OutlineSectionResponse]
}

private struct OutlineSectionResponse: Codable {
    let sectionName: String
    let positionRange: String
    let contentSummary: String
    let targetTags: [String]
    let isPivot: Bool
}
