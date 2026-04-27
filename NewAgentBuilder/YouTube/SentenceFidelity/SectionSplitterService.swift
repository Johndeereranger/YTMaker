//
//  SectionSplitterService.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/20/26.
//

import Foundation

// MARK: - Data Models

struct SectionSplitterPromptVariant: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let systemPrompt: String

    static let legacy = SectionSplitterPromptVariant(
        id: "legacy-splitter",
        name: "Legacy Splitter",
        systemPrompt: """
        You are a transcript section splitter. You analyze consecutive sentences from a video transcript and determine whether the speaker shifts rhetorical purpose within the window.

        RHETORICAL PURPOSES (the types of sections you are splitting between):

        HOOK — Grabbing attention:
          personal-stake, shocking-fact, question-hook, scene-set

        SETUP — Establishing context:
          common-belief, historical-context, define-frame, stakes-establishment

        TENSION — Creating conflict:
          complication, counterargument, contradiction, mystery-raise

        REVELATION — Revealing truth:
          hidden-truth, reframe, root-cause, connection-reveal, action-directive

        EVIDENCE — Supporting with proof:
          evidence-stack, authority-cite, data-present, case-study, analogy, live-experience

        CLOSING — Wrapping up:
          synthesis, implication, future-project, viewer-address

        DIGRESSION — Stepping outside the main thread:
          content-warning, personal-aside, sponsor-read, meta-commentary, tangent

        A section break occurs when the speaker transitions from one of these purposes to a different one. You do not need to classify which purpose each sentence serves — just detect where the PURPOSE CHANGES.

        IMPORTANT: Digressions are sections too. When a speaker steps outside the main narrative to address the viewer directly ("Before I go on..."), deliver a content warning, read a sponsor ad, or go on a personal tangent — that is a DIGRESSION section. It starts where they leave the main thread and ends where they return to it. Both the entry into and exit from a digression are section breaks.

        WHAT COUNTS AS A SECTION BREAK:
        - Speaker shifts from telling a story to stepping outside it (meta-commentary, content warnings, asides to the viewer)
        - Speaker shifts from building tension/argument to presenting evidence or proof
        - Speaker shifts from presenting evidence to drawing conclusions or stating a thesis
        - Speaker shifts from main content to sponsor/ad content, or back
        - Speaker shifts from conceding a point to arguing against it
        - Speaker shifts from one distinct narrative episode to another (new time, new place, new actor)
        - Speaker shifts from factual reporting to moral/emotional evaluation
        - Speaker digresses from the main thread (tangent, aside, content warning) — the digression is its own section
        - Speaker returns from a digression back to the main thread

        WHAT DOES NOT COUNT AS A SECTION BREAK:
        - Continuing the same story with a new detail ("And then..." "So the CIA..." "From there...")
        - Using transition words within the same rhetorical purpose ("So instead..." "But also..." "Not to mention...")
        - Elaborating on the same point with another example
        - Brief parenthetical remarks that don't sustain for multiple sentences (one throwaway line is NOT a digression section)
        - Restating or rephrasing what was just said

        CRITICAL RULES:
        1. A single window can have AT MOST one split. If you see multiple possible splits, pick the strongest one.
        2. The split point is BETWEEN two sentences. Sentence N is the last sentence of the outgoing section. Sentence N+1 is the first sentence of the incoming section.
        3. Housekeeping sentences ("check the links below", "before I go on", "if you want more info") belong with the section they are closing out, NOT with the next section.
        4. When a speaker says something like "Okay, so..." or "With that, let's get back to..." — that sentence is the FIRST sentence of the new section, not the last sentence of the old one.
        5. If you are unsure, say NO SPLIT. Only split when the rhetorical shift is clear.
        6. A digression must sustain for at least 2-3 sentences to count as its own section. A single aside sentence within a longer block is not a section break.

        Respond with ONLY one of these two formats:
        NO SPLIT: <reason>
        SPLIT AFTER SENTENCE [N]: <reason>
        """
    )
    static let classification = SectionSplitterPromptVariant(
            id: "merged-splitter",
            name: "Merged Splitter",
            systemPrompt: """
            You are a transcript section splitter. You analyze consecutive sentences from a video transcript and determine whether the speaker shifts rhetorical purpose within the window. You also classify the rhetorical move using the taxonomy below.

            RHETORICAL MOVES TAXONOMY:

            HOOK — Grabbing attention:
              personal-stake, shocking-fact, question-hook, scene-set

            SETUP — Establishing context:
              common-belief, historical-context, define-frame, stakes-establishment

            TENSION — Creating conflict:
              complication, counterargument, contradiction, mystery-raise

            REVELATION — Revealing truth:
              hidden-truth, reframe, root-cause, connection-reveal, action-directive

            EVIDENCE — Supporting with proof:
              evidence-stack, authority-cite, data-present, case-study, analogy

            STORYTELLING — Narrating events or explaining how things work:
              action-sequence, travel-narration, reaction-moment, encounter, challenge-progress,
              mechanism-explain, process-walkthrough, system-describe, comparison, live-experience

            CLOSING — Wrapping up:
              synthesis, implication, future-project, viewer-address

            DIGRESSION — Stepping outside the main thread:
              content-warning, personal-aside, sponsor-read, meta-commentary, tangent

            A section break occurs when the speaker transitions from one rhetorical purpose to a fundamentally different one. Your job is to detect where the speaker's GOAL FOR THE AUDIENCE changes — what they want the viewer to think, feel, or understand shifts.

            WHAT COUNTS AS A SECTION BREAK:
            - Speaker shifts from telling a story to stepping outside it (meta-commentary, content warnings, asides to the viewer)
            - Speaker shifts from building tension/argument to presenting evidence or proof
            - Speaker shifts from presenting evidence to drawing conclusions or stating a thesis
            - Speaker shifts from main content to sponsor/ad content, or back
            - Speaker shifts from conceding a point to arguing against it
            - Speaker shifts from one distinct narrative episode to another (new time period, new location, new subject)
            - Speaker shifts from factual reporting to moral/emotional evaluation that SUSTAINS for multiple sentences
            - Speaker digresses from the main thread (tangent, aside, content warning) — the digression is its own section
            - Speaker returns from a digression back to the main thread

            WHAT DOES NOT COUNT AS A SECTION BREAK:
            - Continuing the same story with a new detail ("And then..." "So the CIA..." "From there...")
            - Shifting between describing how something works and narrating what happened next WITHIN THE SAME STORY. If the speaker is telling the same story about the same subject in the same time period, moving between system-describe, mechanism-explain, action-sequence, evidence-stack, or process-walkthrough is NOT a split. The section continues.
            - Using transition words within the same rhetorical purpose ("So instead..." "But also..." "Not to mention...")
            - Elaborating on the same point with another example or another piece of evidence
            - Stacking multiple examples, anecdotes, or data points that all serve the same argument
            - Brief parenthetical remarks that don't sustain for multiple sentences (one throwaway line is NOT a digression section)
            - Restating or rephrasing what was just said
            - A brief evaluative comment ("I mean, the guy's good") within an ongoing narrative — this is color, not a purpose change
            - Showing visual evidence (photos, footage, maps) of something just described — this supports the current section, it doesn't start a new one

            CRITICAL RULES:
            1. A single window can have AT MOST one split. If you see multiple possible splits, pick the strongest one.
            2. The split point is BETWEEN two sentences. Sentence N is the last sentence of the outgoing section. Sentence N+1 is the first sentence of the incoming section.
            3. Housekeeping sentences ("check the links below", "before I go on", "if you want more info") belong with the section they are closing out, NOT with the next section.
            4. Transitional sentences ("Okay, so..." or "With that, let's get back to...") belong with the section they are OPENING, not the one they are closing.
            5. If you are unsure, say NO SPLIT. Only split when the rhetorical shift is clear and sustained.
            6. A digression must sustain for at least 2-3 sentences to count as its own section. A single aside sentence within a longer block is not a section break.
            7. Moves within the same parent category are NOT splits. action-sequence → mechanism-explain is NOT a split (both STORYTELLING). evidence-stack → data-present is NOT a split (both EVIDENCE). Only split when the PARENT CATEGORY changes.
            8. Even across parent categories, do NOT split if both sides serve the same story or argument. If a speaker is telling the story of a prison escape and shifts from describing the prison layout (system-describe / STORYTELLING) to presenting its security statistics (data-present / EVIDENCE), that is NOT a split if it all serves the same narrative about the prison. Ask yourself: "Is the speaker still trying to get the audience to understand the same thing?" If yes, no split.
            9. Before declaring a split, consider: would this create a section shorter than 5 sentences on either side? If so, the bar is much higher. Only split for short sections if the shift is to/from a DIGRESSION or CLOSING, or represents a completely new topic/episode.

            RESPONSE FORMAT:
            Respond with ONLY one of these two formats:

            NO SPLIT [move-label]
            <your reasoning>

            SPLIT[N] [move-before] → [move-after]
            <your reasoning>

            Where N is the sentence number of the LAST sentence in the outgoing section. Use the specific move label (e.g. "action-sequence", "sponsor-read"), not the parent category.
            """
        )
    static let classificationV2 = SectionSplitterPromptVariant(
        id: "classification-splitter",
        name: "Classification Splitter",
        systemPrompt: """
        You are a transcript section classifier. You analyze consecutive sentences from a video transcript and classify the rhetorical purpose of the content using the taxonomy below. A section break exists wherever the classification changes.

        RHETORICAL MOVES TAXONOMY:

        HOOK — Grabbing attention:
          personal-stake, shocking-fact, question-hook, scene-set

        SETUP — Establishing context:
          common-belief, historical-context, define-frame, stakes-establishment

        TENSION — Creating conflict:
          complication, counterargument, contradiction, mystery-raise

        REVELATION — Revealing truth:
          hidden-truth, reframe, root-cause, connection-reveal

        EVIDENCE — Supporting with proof:
          evidence-stack, authority-cite, data-present, case-study, analogy

        EXPLANATION — Teaching or describing a system:
          mechanism-explain, process-walkthrough, system-describe, comparison

        NARRATIVE — Experiential storytelling:
          action-sequence, travel-narration, reaction-moment, encounter, challenge-progress

        CLOSING — Wrapping up:
          synthesis, implication, future-project, viewer-address

        DIGRESSION — Stepping outside the main thread:
          content-warning, personal-aside, sponsor-read, meta-commentary, tangent

        YOUR TASK:
        Classify the rhetorical move of the FIRST 3 sentences in the window and the LAST 3 sentences in the window. If the classification changes between these regions, that is a split.

        RULES:
        1. Always classify using the specific move (e.g. "complication", "evidence-stack"), not just the parent category.
        2. A single window can have AT MOST one split.
        3. The split point is BETWEEN two sentences. Sentence N is the last sentence of the outgoing move. Sentence N+1 is the first sentence of the incoming move.
        4. Housekeeping sentences ("check the links below", "before I go on") belong with the section they are closing out.
        5. Transitional sentences ("Okay, so..." or "With that, let's get back to...") belong with the section they are opening.
        6. If the entire window is within a DIGRESSION (e.g. sponsor-read, tangent, personal-aside), do NOT split on rhetorical moves internal to the digression. Only split when the digression begins or ends.
        7. If a digression is fewer than 4 sentences and the content returns to the same rhetorical move it left, absorb it into the surrounding section. Do NOT split.
        8. Moves within the same parent category (e.g. travel-narration → action-sequence, both under NARRATIVE) are NOT splits. Only split when the parent category changes or when there is a clear topic/subject change within the same parent category.
        9. If the entire window serves the same rhetorical move, say so.
        10. If you are unsure between two moves within the same parent category, that is a signal there is no split.

        Respond with ONLY one of these two formats:
        NO SPLIT: [move]
        SPLIT AFTER SENTENCE [N]: [move-before] → [move-after] the orig
        """
    )
    static let classificationOriginal = SectionSplitterPromptVariant(
        id: "classification-splitter",
        name: "Classification Splitter",
        systemPrompt: """
        You are a transcript section classifier. You analyze consecutive sentences from a video transcript and classify the rhetorical purpose of the content using the taxonomy below. A section break exists wherever the classification changes.

        RHETORICAL MOVES TAXONOMY:

        HOOK — Grabbing attention:
          personal-stake, shocking-fact, question-hook, scene-set

        SETUP — Establishing context:
          common-belief, historical-context, define-frame, stakes-establishment

        TENSION — Creating conflict:
          complication, counterargument, contradiction, mystery-raise

        REVELATION — Revealing truth:
          hidden-truth, reframe, root-cause, connection-reveal

        EVIDENCE — Supporting with proof:
          evidence-stack, authority-cite, data-present, case-study, analogy

        CLOSING — Wrapping up:
          synthesis, implication, future-project, viewer-address

        DIGRESSION — Stepping outside the main thread:
          content-warning, personal-aside, sponsor-read, meta-commentary, tangent

        YOUR TASK:
        Classify the rhetorical move of the EARLY sentences in the window and the LATE sentences in the window. If the classification changes within the window, that is a split.

        RULES:
        1. Always classify using the specific move (e.g. "complication", "evidence-stack"), not just the parent category.
        2. A single window can have AT MOST one split.
        3. The split point is BETWEEN two sentences. Sentence N is the last sentence of the outgoing move. Sentence N+1 is the first sentence of the incoming move.
        4. Housekeeping sentences ("check the links below", "before I go on") belong with the section they are closing out.
        5. Transitional sentences ("Okay, so..." or "With that, let's get back to...") belong with the section they are opening.
        6. A digression must sustain for at least 2-3 sentences to count as its own section.
        7. If the entire window serves the same rhetorical move, say so.
        8. If you are unsure between two moves, pick the one that best describes the speaker's primary intent.

        Respond with ONLY one of these two formats:
        NO SPLIT: [move]
        SPLIT AFTER SENTENCE [N]: [move-before] → [move-after]
        """
    )
}

/// A window of consecutive sentences to analyze for section boundaries
struct SentenceWindow: Identifiable, Codable {
    let id: Int
    let windowIndex: Int
    let startSentence: Int   // 1-indexed
    let endSentence: Int     // 1-indexed
    let sentences: [String]
}

/// Result from a single window's LLM analysis
struct WindowSplitResult: Identifiable, Codable {
    let id: Int
    let windowIndex: Int
    let startSentence: Int
    let endSentence: Int
    let splitAfterSentence: Int?  // nil = NO SPLIT; otherwise 1-indexed sentence number
    let outgoingMove: String?
    let incomingMove: String?
    let reason: String?
    let rawResponse: String

    enum CodingKeys: String, CodingKey {
        case id, windowIndex, startSentence, endSentence, splitAfterSentence
        case outgoingMove, incomingMove, reason, rawResponse
    }

    init(
        id: Int,
        windowIndex: Int,
        startSentence: Int,
        endSentence: Int,
        splitAfterSentence: Int?,
        outgoingMove: String?,
        incomingMove: String?,
        reason: String?,
        rawResponse: String
    ) {
        self.id = id
        self.windowIndex = windowIndex
        self.startSentence = startSentence
        self.endSentence = endSentence
        self.splitAfterSentence = splitAfterSentence
        self.outgoingMove = outgoingMove
        self.incomingMove = incomingMove
        self.reason = reason
        self.rawResponse = rawResponse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        windowIndex = try container.decode(Int.self, forKey: .windowIndex)
        startSentence = try container.decode(Int.self, forKey: .startSentence)
        endSentence = try container.decode(Int.self, forKey: .endSentence)
        splitAfterSentence = try container.decodeIfPresent(Int.self, forKey: .splitAfterSentence)
        outgoingMove = try container.decodeIfPresent(String.self, forKey: .outgoingMove)
        incomingMove = try container.decodeIfPresent(String.self, forKey: .incomingMove)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        rawResponse = try container.decode(String.self, forKey: .rawResponse)
    }
}

/// A boundary detected through consensus across overlapping windows
struct SectionBoundary: Identifiable, Codable {
    let id: Int
    let sentenceNumber: Int      // 1-indexed: split occurs AFTER this sentence
    let confidence: Double       // 0.0 to 1.0: fraction of overlapping windows that agree
    let windowVotes: Int
    let windowsOverlapping: Int
    let reasons: [String]
    let sentenceText: String
}

/// Tracks what happened to a single window across both passes
struct WindowPassComparison: Identifiable, Codable {
    let id: Int  // windowIndex
    let windowIndex: Int
    let startSentence: Int
    let endSentence: Int
    let pass1Result: WindowSplitResult
    let pass2Result: WindowSplitResult?  // nil if pass 1 was NO SPLIT (not sent to pass 2)
    let finalResult: WindowSplitResult   // what consensus uses

    /// Was this window sent to pass 2?
    var wasRefined: Bool { pass2Result != nil }

    /// Did pass 2 change the decision?
    var pass2Changed: Bool {
        guard let p2 = pass2Result else { return false }
        return p2.splitAfterSentence != pass1Result.splitAfterSentence
    }

    /// What specifically changed
    var changeDescription: String {
        guard let p2 = pass2Result else { return "not refined" }
        let p1 = pass1Result
        if p1.splitAfterSentence == p2.splitAfterSentence {
            return "confirmed"
        } else if p1.splitAfterSentence != nil && p2.splitAfterSentence == nil {
            return "REVOKED (pass 1 split → pass 2 no split)"
        } else if let p1s = p1.splitAfterSentence, let p2s = p2.splitAfterSentence, p1s != p2s {
            return "MOVED (pass 1: [\(p1s)] → pass 2: [\(p2s)])"
        } else {
            return "changed"
        }
    }
}

/// Complete result of one splitter run (pass 1 + pass 2)
struct SectionSplitterRunResult: Identifiable, Codable {
    let id: UUID
    let runNumber: Int
    let promptVariantId: String
    let promptVariantName: String
    let pass1Results: [WindowSplitResult]         // raw pass 1 output
    let pass2Results: [WindowSplitResult]          // raw pass 2 output (only refined windows)
    let mergedResults: [WindowSplitResult]         // final merged (used for consensus)
    let windowComparisons: [WindowPassComparison]  // pass 1 vs pass 2 per window
    let boundaries: [SectionBoundary]
    let pass1Boundaries: [SectionBoundary]   // consensus using ONLY pass 1 results (no pass 2)
    let totalSentences: Int
    let totalWindows: Int
    let timestamp: Date
    let temperature: Double
    let windowSize: Int
    let stepSize: Int

    enum CodingKeys: String, CodingKey {
        case id, runNumber, promptVariantId, promptVariantName
        case pass1Results, pass2Results, mergedResults, windowComparisons
        case boundaries, pass1Boundaries, totalSentences, totalWindows
        case timestamp, temperature, windowSize, stepSize
    }

    /// How many windows pass 1 flagged as splits
    var pass1SplitCount: Int { pass1Results.filter { $0.splitAfterSentence != nil }.count }

    /// How many pass 2 confirmed as splits
    var pass2SplitCount: Int { pass2Results.filter { $0.splitAfterSentence != nil }.count }

    /// How many pass 2 revoked (changed split → no split)
    var pass2RevokedCount: Int {
        windowComparisons.filter { $0.wasRefined && $0.pass1Result.splitAfterSentence != nil && $0.pass2Result?.splitAfterSentence == nil }.count
    }

    /// How many pass 2 moved to a different sentence
    var pass2MovedCount: Int {
        windowComparisons.filter {
            guard let p2 = $0.pass2Result else { return false }
            guard let p1s = $0.pass1Result.splitAfterSentence, let p2s = p2.splitAfterSentence else { return false }
            return p1s != p2s
        }.count
    }

    /// Boundaries in merged that don't exist in pass1-only (pass 2 caused them to appear)
    var pass2AddedBoundaries: [SectionBoundary] {
        boundaries.filter { merged in
            !pass1Boundaries.contains { $0.sentenceNumber == merged.sentenceNumber }
        }
    }

    /// Boundaries in pass1-only that don't exist in merged (pass 2 removed them)
    var pass2RemovedBoundaries: [SectionBoundary] {
        pass1Boundaries.filter { p1 in
            !boundaries.contains { $0.sentenceNumber == p1.sentenceNumber }
        }
    }

    init(
        runNumber: Int,
        promptVariant: SectionSplitterPromptVariant = .legacy,
        pass1Results: [WindowSplitResult],
        pass2Results: [WindowSplitResult],
        mergedResults: [WindowSplitResult],
        windowComparisons: [WindowPassComparison],
        boundaries: [SectionBoundary],
        pass1Boundaries: [SectionBoundary] = [],
        totalSentences: Int,
        totalWindows: Int,
        timestamp: Date = Date(),
        temperature: Double,
        windowSize: Int,
        stepSize: Int
    ) {
        self.id = UUID()
        self.runNumber = runNumber
        self.promptVariantId = promptVariant.id
        self.promptVariantName = promptVariant.name
        self.pass1Results = pass1Results
        self.pass2Results = pass2Results
        self.mergedResults = mergedResults
        self.windowComparisons = windowComparisons
        self.boundaries = boundaries
        self.pass1Boundaries = pass1Boundaries
        self.totalSentences = totalSentences
        self.totalWindows = totalWindows
        self.timestamp = timestamp
        self.temperature = temperature
        self.windowSize = windowSize
        self.stepSize = stepSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        runNumber = try container.decode(Int.self, forKey: .runNumber)
        promptVariantId = try container.decodeIfPresent(String.self, forKey: .promptVariantId) ?? SectionSplitterPromptVariant.legacy.id
        promptVariantName = try container.decodeIfPresent(String.self, forKey: .promptVariantName) ?? SectionSplitterPromptVariant.legacy.name
        pass1Results = try container.decode([WindowSplitResult].self, forKey: .pass1Results)
        pass2Results = try container.decode([WindowSplitResult].self, forKey: .pass2Results)
        mergedResults = try container.decode([WindowSplitResult].self, forKey: .mergedResults)
        windowComparisons = try container.decode([WindowPassComparison].self, forKey: .windowComparisons)
        boundaries = try container.decode([SectionBoundary].self, forKey: .boundaries)
        pass1Boundaries = try container.decodeIfPresent([SectionBoundary].self, forKey: .pass1Boundaries) ?? []
        totalSentences = try container.decode(Int.self, forKey: .totalSentences)
        totalWindows = try container.decode(Int.self, forKey: .totalWindows)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        temperature = try container.decode(Double.self, forKey: .temperature)
        windowSize = try container.decode(Int.self, forKey: .windowSize)
        stepSize = try container.decode(Int.self, forKey: .stepSize)
    }
}

// MARK: - Section Splitter Service

class SectionSplitterService {

    static let shared = SectionSplitterService()

    // MARK: - Window Generation

    func generateWindows(
        sentences: [String],
        windowSize: Int,
        stepSize: Int
    ) -> [SentenceWindow] {
        var windows: [SentenceWindow] = []
        var windowIndex = 0
        var startIndex = 0

        while startIndex < sentences.count {
            let endIndex = min(startIndex + windowSize, sentences.count)
            let windowSentences = Array(sentences[startIndex..<endIndex])

            // Discard windows with fewer than 2 sentences
            if windowSentences.count >= 2 {
                windows.append(SentenceWindow(
                    id: windowIndex,
                    windowIndex: windowIndex,
                    startSentence: startIndex + 1,  // 1-indexed
                    endSentence: endIndex,           // 1-indexed
                    sentences: windowSentences
                ))
                windowIndex += 1
            }

            startIndex += stepSize
        }

        return windows
    }

    // MARK: - Single Window Analysis

    func analyzeWindow(
        window: SentenceWindow,
        temperature: Double,
        promptVariant: SectionSplitterPromptVariant = .legacy,
        previousContext: String? = nil
    ) async throws -> WindowSplitResult {
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        var userPrompt = ""

        // Prepend context for pass 2
        if let context = previousContext {
            userPrompt += "PREVIOUS SECTION CONTEXT (sentences immediately before this window):\n"
            userPrompt += context + "\n\n"
        }

        // Build numbered sentences
        var sentenceLines: [String] = []
        for (offset, sentence) in window.sentences.enumerated() {
            let sentenceNum = window.startSentence + offset
            sentenceLines.append("[\(sentenceNum)] \(sentence)")
        }

        userPrompt += "Here are sentences \(window.startSentence) through \(window.endSentence) from a video transcript:\n\n"
        userPrompt += sentenceLines.joined(separator: "\n")
        userPrompt += "\n\nDo all these sentences belong to the same rhetorical section, or is there a split?"

        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: promptVariant.systemPrompt,
            params: ["temperature": temperature, "max_tokens": 200]
        )

        return parseWindowResponse(response, window: window)
    }

    // MARK: - Response Parsing

    func parseWindowResponse(_ response: String, window: SentenceWindow) -> WindowSplitResult {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for SPLIT AFTER SENTENCE [N] pattern (case-insensitive)
        let splitPattern = #"(?i)SPLIT\s+AFTER\s+SENTENCE\s+\[?(\d+)\]?"#
        if let regex = try? NSRegularExpression(pattern: splitPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let numRange = Range(match.range(at: 1), in: trimmed) {

            let sentenceNum = Int(trimmed[numRange]) ?? 0

            // Extract reason (everything after the sentence number and optional colon)
            let reasonPattern = #"(?i)SPLIT\s+AFTER\s+SENTENCE\s+\[?\d+\]?\s*:?\s*(.*)"#
            var reason: String?
            if let reasonRegex = try? NSRegularExpression(pattern: reasonPattern, options: .dotMatchesLineSeparators),
               let reasonMatch = reasonRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let reasonRange = Range(reasonMatch.range(at: 1), in: trimmed) {
                let extracted = String(trimmed[reasonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty {
                    reason = extracted
                }
            }
            let parsedMoves = parseMoves(from: reason ?? "")

            // Validate the sentence number is within the window range
            let validSentenceNum = (sentenceNum >= window.startSentence && sentenceNum < window.endSentence) ? sentenceNum : nil

            return WindowSplitResult(
                id: window.windowIndex,
                windowIndex: window.windowIndex,
                startSentence: window.startSentence,
                endSentence: window.endSentence,
                splitAfterSentence: validSentenceNum,
                outgoingMove: parsedMoves.before,
                incomingMove: parsedMoves.after,
                reason: reason,
                rawResponse: trimmed
            )
        }

        // Check for NO SPLIT pattern — extract reason
        var noSplitReason: String?
        let noSplitPattern = #"(?i)NO\s+SPLIT\s*:?\s*(.*)"#
        if let noSplitRegex = try? NSRegularExpression(pattern: noSplitPattern, options: .dotMatchesLineSeparators),
           let noSplitMatch = noSplitRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let reasonRange = Range(noSplitMatch.range(at: 1), in: trimmed) {
            let extracted = String(trimmed[reasonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty {
                noSplitReason = extracted
            }
        }

        return WindowSplitResult(
            id: window.windowIndex,
            windowIndex: window.windowIndex,
            startSentence: window.startSentence,
            endSentence: window.endSentence,
            splitAfterSentence: nil,
            outgoingMove: noSplitReason,
            incomingMove: nil,
            reason: noSplitReason,
            rawResponse: trimmed
        )
    }

    private func parseMoves(from text: String) -> (before: String?, after: String?) {
        let parts = text
            .split(separator: "→", maxSplits: 1, omittingEmptySubsequences: false)
            .map {
                String($0)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            }

        if parts.count == 2 {
            return (
                before: parts[0].isEmpty ? nil : parts[0],
                after: parts[1].isEmpty ? nil : parts[1]
            )
        }

        let single = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (before: single?.isEmpty == false ? single : nil, after: nil)
    }

    // MARK: - Full Two-Pass Run

    func runSplitter(
        transcript: String,
        windowSize: Int = 5,
        stepSize: Int = 2,
        temperature: Double = 0.3,
        promptVariant: SectionSplitterPromptVariant = .legacy,
        excludeIndices: Set<Int>? = nil,
        onProgress: ((Int, Int, String) -> Void)? = nil  // (completed, total, phase)
    ) async throws -> SectionSplitterRunResult {
        var sentences = SentenceParser.parse(transcript)
        if let exclude = excludeIndices {
            sentences = sentences.enumerated().filter { !exclude.contains($0.offset) }.map(\.element)
        }
        let windows = generateWindows(sentences: sentences, windowSize: windowSize, stepSize: stepSize)

        print("\n=== SECTION SPLITTER ===")
        print("Sentences: \(sentences.count), Windows: \(windows.count), WinSize: \(windowSize), Step: \(stepSize)")

        // PASS 1: All windows in parallel, no context
        let pass1Results = try await runPass1(
            windows: windows,
            temperature: temperature,
            promptVariant: promptVariant,
            onProgress: { completed, total in
                onProgress?(completed, total, "Pass 1: Windows")
            }
        )

        let splitCount = pass1Results.filter { $0.splitAfterSentence != nil }.count
        print("Pass 1 complete: \(splitCount) splits found out of \(windows.count) windows")

        // Compute pass 1-only consensus (before any pass 2 refinement)
        let pass1Boundaries = calculateConsensus(
            windowResults: pass1Results,
            sentences: sentences,
            totalSentences: sentences.count
        )
        print("Pass 1 consensus: \(pass1Boundaries.count) boundaries")

        // PASS 2: Sequential context refinement on split windows only
        let refinedResults = try await refineWithContext(
            splitResults: pass1Results,
            sentences: sentences,
            temperature: temperature,
            promptVariant: promptVariant,
            contextSize: windowSize,
            onProgress: { completed, total in
                onProgress?(completed, total, "Pass 2: Refining")
            }
        )

        // Build pass 2 lookup by window index
        var pass2Lookup: [Int: WindowSplitResult] = [:]
        for r in refinedResults {
            pass2Lookup[r.windowIndex] = r
        }

        // Merge: replace pass 1 split results with pass 2 refined results
        var mergedResults: [WindowSplitResult] = []
        var windowComparisons: [WindowPassComparison] = []

        for p1 in pass1Results {
            let p2 = pass2Lookup[p1.windowIndex]
            let final = p2 ?? p1  // use pass 2 if available, otherwise pass 1

            mergedResults.append(final)
            windowComparisons.append(WindowPassComparison(
                id: p1.windowIndex,
                windowIndex: p1.windowIndex,
                startSentence: p1.startSentence,
                endSentence: p1.endSentence,
                pass1Result: p1,
                pass2Result: p2,
                finalResult: final
            ))
        }
        mergedResults.sort { $0.windowIndex < $1.windowIndex }
        windowComparisons.sort { $0.windowIndex < $1.windowIndex }

        let refinedSplitCount = refinedResults.filter { $0.splitAfterSentence != nil }.count
        let revokedCount = windowComparisons.filter { $0.wasRefined && $0.pass1Result.splitAfterSentence != nil && $0.pass2Result?.splitAfterSentence == nil }.count
        let movedCount = windowComparisons.filter { $0.pass2Changed && $0.pass2Result?.splitAfterSentence != nil && $0.pass1Result.splitAfterSentence != nil && $0.pass2Result?.splitAfterSentence != $0.pass1Result.splitAfterSentence }.count
        print("Pass 2 complete: \(refinedSplitCount) confirmed, \(revokedCount) revoked, \(movedCount) moved (was \(splitCount) from pass 1)")

        // Calculate consensus
        let boundaries = calculateConsensus(
            windowResults: mergedResults,
            sentences: sentences,
            totalSentences: sentences.count
        )

        print("Consensus: \(boundaries.count) boundaries found")
        for boundary in boundaries {
            print("  [\(boundary.sentenceNumber)] confidence: \(String(format: "%.0f%%", boundary.confidence * 100)) (\(boundary.windowVotes)/\(boundary.windowsOverlapping))")
        }

        return SectionSplitterRunResult(
            runNumber: 0,  // Caller assigns run number
            promptVariant: promptVariant,
            pass1Results: pass1Results,
            pass2Results: refinedResults,
            mergedResults: mergedResults,
            windowComparisons: windowComparisons,
            boundaries: boundaries,
            pass1Boundaries: pass1Boundaries,
            totalSentences: sentences.count,
            totalWindows: windows.count,
            temperature: temperature,
            windowSize: windowSize,
            stepSize: stepSize
        )
    }

    // MARK: - Pass 1: Parallel (No Context)

    private enum WindowAnalysisResult {
        case success(Int, WindowSplitResult)
        case failure(Int, String)
    }

    private func runPass1(
        windows: [SentenceWindow],
        temperature: Double,
        promptVariant: SectionSplitterPromptVariant,
        onProgress: ((Int, Int) -> Void)?
    ) async throws -> [WindowSplitResult] {
        let maxConcurrent = 15
        var results: [Int: WindowSplitResult] = [:]
        var completedCount = 0
        let lock = NSLock()

        await withTaskGroup(of: WindowAnalysisResult.self) { group in
            var iterator = windows.makeIterator()

            // Start initial batch with staggered 0.5s intervals
            for i in 0..<min(maxConcurrent, windows.count) {
                if let window = iterator.next() {
                    let delayNs = UInt64(i) * 500_000_000  // 0.5s between each start
                    group.addTask {
                        if delayNs > 0 {
                            try? await Task.sleep(nanoseconds: delayNs)
                        }
                        do {
                            let result = try await self.analyzeWindow(window: window, temperature: temperature, promptVariant: promptVariant)
                            return .success(window.windowIndex, result)
                        } catch {
                            return .failure(window.windowIndex, error.localizedDescription)
                        }
                    }
                }
            }

            // Sliding window: as each completes, start next
            for await result in group {
                lock.lock()
                switch result {
                case .success(let index, let windowResult):
                    results[index] = windowResult
                case .failure(let index, let error):
                    print("⚠️ Window \(index) failed: \(error)")
                }
                completedCount += 1
                let count = completedCount
                lock.unlock()

                await MainActor.run {
                    onProgress?(count, windows.count)
                }

                // Add next task if available
                if let nextWindow = iterator.next() {
                    group.addTask {
                        do {
                            let result = try await self.analyzeWindow(window: nextWindow, temperature: temperature, promptVariant: promptVariant)
                            return .success(nextWindow.windowIndex, result)
                        } catch {
                            return .failure(nextWindow.windowIndex, error.localizedDescription)
                        }
                    }
                }
            }
        }

        // Return in window order
        return (0..<windows.count).compactMap { results[$0] }
    }

    // MARK: - Pass 2: Parallel Context Refinement

    private enum Pass2Result {
        case success(Int, WindowSplitResult)  // (windowIndex, result)
        case failure(Int, WindowSplitResult)  // (windowIndex, original pass 1 fallback)
    }

    func refineWithContext(
        splitResults: [WindowSplitResult],
        sentences: [String],
        temperature: Double,
        promptVariant: SectionSplitterPromptVariant,
        contextSize: Int = 5,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> [WindowSplitResult] {
        // Filter to only split results, sorted by start sentence
        let splits = splitResults
            .filter { $0.splitAfterSentence != nil }
            .sorted { $0.startSentence < $1.startSentence }

        if splits.isEmpty { return [] }

        // Pre-build all windows and contexts (all derived from static transcript)
        let tasks: [(window: SentenceWindow, context: String, original: WindowSplitResult)] = splits.map { splitResult in
            let windowStart0 = splitResult.startSentence - 1
            let contextString: String
            if windowStart0 <= 0 {
                contextString = "START OF TRANSCRIPT — no previous section."
            } else {
                let contextStart = max(0, windowStart0 - contextSize)
                let contextEnd = windowStart0
                var contextLines: [String] = []
                for i in contextStart..<contextEnd {
                    contextLines.append("[\(i + 1)] \(sentences[i])")
                }
                contextString = contextLines.joined(separator: "\n")
            }

            let windowSentences: [String] = (splitResult.startSentence...splitResult.endSentence).compactMap { num in
                let idx = num - 1
                return idx >= 0 && idx < sentences.count ? sentences[idx] : nil
            }

            let window = SentenceWindow(
                id: splitResult.windowIndex,
                windowIndex: splitResult.windowIndex,
                startSentence: splitResult.startSentence,
                endSentence: splitResult.endSentence,
                sentences: windowSentences
            )

            return (window, contextString, splitResult)
        }

        let maxConcurrent = 10
        let totalSplits = tasks.count
        var results: [Int: WindowSplitResult] = [:]
        var completedCount = 0
        let lock = NSLock()

        await withTaskGroup(of: Pass2Result.self) { group in
            var iterator = tasks.makeIterator()

            // Start initial batch with staggered 0.3s intervals
            for i in 0..<min(maxConcurrent, tasks.count) {
                if let task = iterator.next() {
                    let delayNs = UInt64(i) * 300_000_000  // 0.3s between each start
                    group.addTask {
                        if delayNs > 0 {
                            try? await Task.sleep(nanoseconds: delayNs)
                        }
                        do {
                            let refined = try await self.analyzeWindow(
                                window: task.window,
                                temperature: temperature,
                                promptVariant: promptVariant,
                                previousContext: task.context
                            )
                            return .success(task.window.windowIndex, refined)
                        } catch {
                            print("⚠️ Pass 2 refinement failed for window \(task.window.windowIndex): \(error)")
                            return .failure(task.window.windowIndex, task.original)
                        }
                    }
                }
            }

            // Sliding window: as each completes, start next
            for await result in group {
                lock.lock()
                switch result {
                case .success(let index, let refined):
                    results[index] = refined
                case .failure(let index, let original):
                    results[index] = original
                }
                completedCount += 1
                let count = completedCount
                lock.unlock()

                await MainActor.run {
                    onProgress?(count, totalSplits)
                }

                if let nextTask = iterator.next() {
                    group.addTask {
                        do {
                            let refined = try await self.analyzeWindow(
                                window: nextTask.window,
                                temperature: temperature,
                                promptVariant: promptVariant,
                                previousContext: nextTask.context
                            )
                            return .success(nextTask.window.windowIndex, refined)
                        } catch {
                            print("⚠️ Pass 2 refinement failed for window \(nextTask.window.windowIndex): \(error)")
                            return .failure(nextTask.window.windowIndex, nextTask.original)
                        }
                    }
                }
            }
        }

        // Return in window order (matching the sorted splits order)
        return splits.compactMap { results[$0.windowIndex] }
    }

    // MARK: - Consensus Calculation

    func calculateConsensus(
        windowResults: [WindowSplitResult],
        sentences: [String],
        totalSentences: Int
    ) -> [SectionBoundary] {
        var boundaries: [SectionBoundary] = []

        for sentenceNum in 1...totalSentences {
            // Count how many windows overlap this sentence
            let overlapping = windowResults.filter { result in
                sentenceNum >= result.startSentence && sentenceNum <= result.endSentence
            }

            // Count how many of those voted for a split after this sentence
            let votes = overlapping.filter { $0.splitAfterSentence == sentenceNum }

            if !votes.isEmpty {
                let confidence = Double(votes.count) / Double(overlapping.count)
                let reasons = votes.compactMap { $0.reason }
                let sentenceText = sentenceNum <= sentences.count ? sentences[sentenceNum - 1] : "(unknown)"

                boundaries.append(SectionBoundary(
                    id: sentenceNum,
                    sentenceNumber: sentenceNum,
                    confidence: confidence,
                    windowVotes: votes.count,
                    windowsOverlapping: overlapping.count,
                    reasons: reasons,
                    sentenceText: sentenceText
                ))
            }
        }

        return boundaries.sorted { $0.sentenceNumber < $1.sentenceNumber }
    }
}
