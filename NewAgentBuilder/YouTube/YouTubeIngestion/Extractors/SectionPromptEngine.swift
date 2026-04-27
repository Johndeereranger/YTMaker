//
//  SectionPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//


import SwiftUI

// MARK: - Prompt Engines
// MARK: - Prompt Engines

// A1a: Section Extraction Engine
struct SectionPromptEngine {
    let video: YouTubeVideo
    
    func generatePrompt() -> String {
        guard let transcript = video.transcript else {
            return "⚠️ No transcript available for this video"
        }

        let wordCount = transcript.split(separator: " ").count

        // Parse transcript into sentences using SentenceParser
        let sentences = SentenceParser.parse(transcript)
        let sentenceCount = sentences.count

        // Format with numbers: [1] First sentence. [2] Second sentence.
        let numberedTranscript = sentences.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: " ")

        return """
    ════════════════════════════════════════
    🚨 OUTPUT FORMAT: JSON ONLY 🚨
    ════════════════════════════════════════

    Your response MUST be ONLY valid JSON.

    ❌ DO NOT include:
    - Any text before the JSON (no "I'll analyze...", no "Here's the analysis:")
    - Any text after the JSON (no summaries, no explanations)
    - Any markdown formatting (no ```json blocks)

    ✅ Your response should start with { and end with }

    ════════════════════════════════════════

    You are analyzing a YouTube video transcript to extract its structural spine.

    ────────────────────────────────────────
    A1A SCOPE (READ FIRST)
    ────────────────────────────────────────

    You are extracting a COARSE STRUCTURAL SPINE only.

    Do NOT:
    - Model rhythm, alternation, or repeated rhetorical moves
    - Optimize for creator style, cadence, or mode
    - Classify the video into a pattern category

    Those are handled in later stages. Your job is to identify SECTIONS and their ROLES.

    ────────────────────────────────────────
    BOUNDARY IDENTIFICATION (CRITICAL)
    ────────────────────────────────────────

    The transcript below is pre-split into numbered sentences: [1], [2], [3], etc.
    Total sentences: \(sentenceCount)

    For each section, provide the SENTENCE NUMBER where that section ENDS.
    Code will use this to calculate exact boundaries deterministically.

    EXAMPLE:
    If the HOOK section ends at sentence [12], you output:
    "boundarySentence": 12

    RULES:
    - boundarySentence = the sentence number of the LAST sentence in that section
    - Sections are contiguous: if section 1 ends at [12], section 2 starts at [13]
    - The LAST section doesn't need boundarySentence (it goes to end of transcript)
    - Use the bracketed numbers [1], [2], etc. — NOT word counts

    ────────────────────────────────────────
    TRANSCRIPT (SENTENCES NUMBERED)
    ────────────────────────────────────────

    \(numberedTranscript)

    ────────────────────────────────────────
    VIDEO METADATA
    ────────────────────────────────────────

    Title: \(video.title)
    Duration: \(video.duration)
    Total Words: \(wordCount)
    Total Sentences: \(sentenceCount)

    ────────────────────────────────────────
    SECTION ROLE DEFINITIONS
    ────────────────────────────────────────

    HOOK: The attention-grabbing opening that makes viewers commit to watching.
    - Typically 1-4 sentences
    - Creates curiosity, stakes, or intrigue
    - Ends when the video transitions from GRABBING attention to PROVIDING context

    HOOK TEST: If this content was removed, would the viewer still understand the video's argument?
    If YES → it's HOOK (pure attention-grab)
    If NO → it's likely SETUP (necessary context)

    HOOK SCOPE: The HOOK is the initial attention-grabber, NOT the full opening story or example.
    If an opening story spans 10 sentences, the HOOK is likely just the first 1-3 that create the "I need to know more" moment.

    ────────────────────────────────────────

    SETUP: Provides context, background, or framing needed to understand the argument.
    - Introduces the problem space, key players, or situation
    - Ends when the video begins MAKING an argument, not just providing background

    SETUP TEST: Could this content stand alone as a Wikipedia-style introduction?
    If YES → it's SETUP (context/background)
    If NO → it's likely EVIDENCE (building toward a conclusion)

    SETUP COMPLETION SIGNALS:
    Phrases like "Let's go", "Let's do this", "Let's find out", "Here's what we're going to do"
    - These phrases END setup (include them IN SETUP), they do not START the next section
    - They mark the transition from "context" to "action/journey"
    - SETUP ends ON the transition phrase, not before it

    ────────────────────────────────────────

    EVIDENCE: Builds the case using data, observations, examples, or explanation.
    - Multiple EVIDENCE sections are VALID
    - May contain local "but actually..." corrections (those are beat-level, NOT section boundaries)

    ────────────────────────────────────────

    TURN: The PRIMARY STRUCTURAL PIVOT of the video.

    TURN IS:
    - Where the DOMINANT EXPLANATORY FRAME changes
    - Where everything BEFORE gets reinterpreted
    - Where the video shifts from "building the case" to "delivering consequences"
    - Where the video's RECOMMENDATION or STANCE becomes clear
    - ONE per video, even in cascade-heavy styles

    TURN IS NOT:
    - Every "but actually..." moment
    - Local corrections or complications
    - Re-hooks or engagement beats
    - Rhythmic alternation
    - Simply introducing complexity (that's still EVIDENCE)

    TURN TEST (apply this):
    Does everything AFTER this section operate under a different premise than everything BEFORE?
    If YES → this is the TURN section.
    If NO → it's a correction inside EVIDENCE, not a new section.

    TURN TIE-BREAKER: When multiple sentences could qualify as the TURN:
    1. PREFER sentences with explicit linguistic pivot markers ("but here's the thing", "the real issue is", "this is where it gets complicated", "what this actually means")
    2. If no explicit marker, choose the EARLIEST sentence that passes the reframe test
    3. The TURN is where the STANCE emerges, not just where complexity is introduced

    ────────────────────────────────────────
    TURN IN MYSTERY/DISCOVERY VIDEOS (ABSOLUTE RULE)
    ────────────────────────────────────────

    Some videos don't have a "here's what I think" pivot.
    Instead they have a DISCOVERY structure:
      Explanation → Paradox raised → Investigation → Provisional answers → Meaning

    ABSOLUTE RULE FOR DISCOVERY VIDEOS:
    The TURN starts at the FIRST moment of ADMITTED CONFUSION or STATED PARADOX.

    TURN SIGNAL PHRASES (these START the TURN section):
    - "Something is missing from my understanding"
    - "But here's the paradox"
    - "The question is..."
    - "This is what bothered scientists"
    - "Wait, that doesn't make sense"
    - "I think something is missing"

    ⚠️ CRITICAL DISTINCTION:
    - The TURN is where CONFUSION IS ADMITTED, not where ANSWERS are given
    - The TURN is the INVESTIGATION phase, not the CONCLUSION phase
    - "Something is missing from my understanding" = TURN STARTS HERE
    - "It's associated with spacetime" = This is PAYOFF, not TURN

    ❌ WRONG: Starting TURN at the answer/insight sentence
    ✓ CORRECT: Starting TURN at the confusion/paradox sentence

    The TURN section INCLUDES:
    - The stated paradox/confusion
    - The investigation that follows
    - Any provisional or partial answers

    The TURN section ENDS when:
    - The video shifts to broader implications/reflection (PAYOFF)

    This makes TURN larger, but that's correct for discovery videos.

    ────────────────────────────────────────
    EVIDENCE vs TURN BOUNDARY (CRITICAL)
    ────────────────────────────────────────

    EVIDENCE includes:
    - Facts, demos, examples
    - Evaluations and inferences
    - Addressing objections
    - Dismissing weak counterarguments
    - Negating naive conclusions ("that's not the real issue")

    EVIDENCE ends when the video finishes CLEARING THE WAY for the new frame.

    TURN starts when:
    - The narrator STATES what they actually think
    - A new governing premise is INTRODUCED (not just hinted at)
    - The argument moves from NEGATION to REPLACEMENT

    KEY TEST: Does this sentence say what the new frame IS, or just what it ISN'T?
    - "This isn't the biggest issue" → EVIDENCE (negation)
    - "The real issue is X" → TURN (replacement)

    TURN begins at REPLACEMENT, not at NEGATION.

    ────────────────────────────────────────
    EVIDENCE DISMISSAL RULE (CRITICAL)
    ────────────────────────────────────────

    When EVIDENCE includes addressing objections or counterarguments:
    - EVIDENCE must include the COMPLETE dismissal of weak arguments
    - Sentences that dismiss objections ("It turns out that's not the real issue",
      "That's not actually the biggest problem") are the LAST sentence of EVIDENCE
    - Do NOT end EVIDENCE in the middle of addressing an objection
    - Do NOT end EVIDENCE at a rhetorical question that's part of building the case

    EXAMPLE (Robot Refs video):
    [32] "wouldn't you want a system that makes the right call every time?" ← Building the case (rhetorical Q)
    [33-40] Addressing "entertainment" objection ← Still building the case
    [41] "It turns out though that wanting to argue with the ref isn't actually the biggest issue here either." ← Complete dismissal = END EVIDENCE
    [42] "The main complaint is something that I kind of actually agree with..." ← New frame = START TURN

    RULE: EVIDENCE ends on the sentence that COMPLETES the dismissal, not mid-objection.

    ────────────────────────────────────────

    PAYOFF: Delivers conclusions, implications, or actionable insights.

    CTA: Call to action (subscribe, comment, watch next).

    SPONSORSHIP: Ad reads or sponsor segments.

    ────────────────────────────────────────
    SPONSORSHIP SPANNING RULE (CRITICAL)
    ────────────────────────────────────────

    When content continues THE SAME TOPIC after a sponsorship:
    - Create ONE EVIDENCE section that spans ACROSS the sponsorship
    - EVIDENCE boundarySentence goes to the END of the resumed content
    - The sponsorship sentences are simply IGNORED for section boundary purposes

    ❌ WRONG (splitting at sponsorship):
       EVIDENCE→[117], then EVIDENCE→[175]

    ✓ CORRECT (spanning across sponsorship):
       EVIDENCE→[175] (spans sentences 34-175, ignoring sponsorship at 118-134)

    TEST: If you removed the sponsorship sentences, would the content before and after flow as ONE continuous argument?
    - If YES → create ONE section spanning the full range
    - If NO → they are genuinely separate EVIDENCE sections

    DO NOT create a separate SPONSORSHIP section in the main sections array.
    The sponsorship will be handled separately by downstream tooling.

    ────────────────────────────────────────
    PIVOT SENTENCE PLACEMENT RULE
    ────────────────────────────────────────

    Sentences containing explicit pivot language belong to the INCOMING section, not the outgoing section.

    Pivot phrases: "It turns out though...", "But here's the thing...", "The real issue is...",
    "This is where it gets complicated...", "What this actually means..."

    RULE:
    - END sections on the sentence BEFORE the pivot
    - START new sections on the pivot sentence itself

    Example:
    - Sentence [41]: "So that covers the basics of how it works."
    - Sentence [42]: "But here's the thing nobody talks about..."

    → EVIDENCE ends at [41], TURN starts at [42]

    ────────────────────────────────────────
    GLOBAL TIE-BREAKER RULE
    ────────────────────────────────────────

    When uncertain between two adjacent sentences for ANY boundary:
    - For HOOK and SETUP: prefer the EARLIER boundary (keep these sections tight)
    - For TURN: prefer the sentence with explicit pivot language, or the EARLIEST qualifying sentence
    - For EVIDENCE sections: prefer boundaries at natural topic shifts, not mid-argument

    ────────────────────────────────────────
    STRUCTURAL PATTERNS (reference only)
    ────────────────────────────────────────

    These patterns are DESCRIPTIVE ONLY. Do NOT force the video to match a pattern. Use them only to avoid misclassification when structure seems unusual.

    Pattern A: Classic
    HOOK → SETUP → EVIDENCE → TURN → PAYOFF

    Pattern B: Progressive Falsification
    HOOK → SETUP → EVIDENCE → EVIDENCE → EVIDENCE → TURN → PAYOFF
    - Multiple EVIDENCE sections with internal corrections
    - Still only ONE TURN section

    Pattern C: Narrative Arc
    HOOK → SETUP → EVIDENCE → EVIDENCE → TURN → PAYOFF

    Pattern D: Explanatory Build
    HOOK → SETUP → EVIDENCE → EVIDENCE → EVIDENCE → PAYOFF
    - TURN minimal or absent — if so, choose closest pivot and flag

    ────────────────────────────────────────
    STRUCTURAL RULES (ENFORCED)
    ────────────────────────────────────────

    ✓ Identify 3-8 major sections
    ✓ Exactly ONE section must have role = TURN
    ✓ Multiple EVIDENCE sections are allowed
    ✓ TURN must pass the "reframe test"
    ✓ Each section ends where the next begins (code handles contiguity)
    ✓ Use sentence numbers for boundaries (boundarySentence)

    ❌ DO NOT:
    - Create multiple TURN sections for "but actually" moments
    - Split EVIDENCE sections because they contain corrections
    - Let rhythmic alternation drive section boundaries
    - Output word indexes or count words
    - Use sentence numbers outside the valid range (1 to \(sentenceCount))

    AMBIGUITY HANDLING:
    - If two sections both qualify as TURN → choose ONE, flag in logicSpineStep
    - If no clear TURN exists → choose closest pivot, note in videoSummary

    ────────────────────────────────────────
    EXTRACTION INSTRUCTIONS
    ────────────────────────────────────────

    1. VIDEO SUMMARY
    2-4 sentence natural prose summary capturing:
    - Video TYPE (myth-bust, data analysis, tutorial, research study, etc.)
    - Rhetorical move (challenges conventional wisdom, reveals data, teaches technique)
    - Evidence used (thermal footage, data, research, observations)
    - Core argument or teaching

    Do NOT use bullet points.

    2. SECTIONS WITH ROLES
    For each section:
    - id: "sect_1", "sect_2", etc.
    - boundarySentence: The sentence number where this section ENDS (NOT for the final section)
    - role: HOOK, SETUP, EVIDENCE, TURN, or PAYOFF (DO NOT create standalone SPONSORSHIP sections)
    - goal: What this section accomplishes
    - logicSpineStep: One sentence describing this step in the argument

    NOTE: The LAST section should have boundarySentence: null (it runs to end of transcript)
    NOTE: If sponsorship interrupts EVIDENCE, span EVIDENCE across it (see SPONSORSHIP SPANNING RULE)

    3. LOGIC SPINE
    - chain: Array of strings describing argument progression
    - causalLinks: Array with { from, to, connection }

    4. BRIDGE POINTS
    - text: EXACT bridge sentence from transcript
    - belongsTo: Array of section IDs this bridges

    ────────────────────────────────────────
    OUTPUT FORMAT (strict JSON)
    ────────────────────────────────────────

    {
      "videoSummary": "2-4 sentence prose summary",
      "sections": [
        {
          "id": "sect_1",
          "boundarySentence": 12,
          "role": "HOOK",
          "goal": "Generate curiosity about...",
          "logicSpineStep": "Claims that X causes Y"
        },
        {
          "id": "sect_2",
          "boundarySentence": 34,
          "role": "SETUP",
          "goal": "Provide context for...",
          "logicSpineStep": "Introduces the problem space"
        },
        {
          "id": "sect_3",
          "boundarySentence": 175,
          "role": "EVIDENCE",
          "goal": "Build the case with data and examples (spans across sponsorship)",
          "logicSpineStep": "Presents supporting evidence"
        },
        {
          "id": "sect_4",
          "boundarySentence": 218,
          "role": "TURN",
          "goal": "Investigate the paradox/mystery",
          "logicSpineStep": "Admits confusion and explores implications"
        },
        {
          "id": "sect_5",
          "boundarySentence": null,
          "role": "PAYOFF",
          "goal": "Deliver the key insight...",
          "logicSpineStep": "Concludes with broader meaning"
        }
      ],
      "logicSpine": {
        "chain": ["HOOK claims X", "SETUP introduces Y"],
        "causalLinks": [
          {
            "from": "sect_1",
            "to": "sect_2",
            "connection": "HOOK leads into context"
          }
        ]
      },
      "bridgePoints": [
        {
          "text": "Exact bridge sentence",
          "belongsTo": ["sect_1", "sect_2"]
        }
      ]
    }

    ────────────────────────────────────────
    VALIDATION CHECKLIST (before output)
    ────────────────────────────────────────

    ☐ Each section (except the last) has boundarySentence with a valid number
    ☐ Last section has boundarySentence: null
    ☐ boundarySentence values are in ascending order (e.g., 12, 34, 56, null)
    ☐ boundarySentence values are within range (1 to \(sentenceCount))
    ☐ Exactly ONE TURN section
    ☐ 3-8 total sections

    ────────────────────────────────────────
    CRITICAL
    ────────────────────────────────────────

    - Return ONLY valid JSON, no markdown
    - Use boundarySentence (integer), NOT word indexes or text quotes
    - boundarySentence = the [N] number of the LAST sentence in that section
    - Last section has boundarySentence: null
    - Do NOT add fields (no timeRange, no startWordIndex, no endWordIndex, no boundaryText)
    - Exactly ONE TURN section per video

    ⚠️ SPONSORSHIP: If there's a sponsorship mid-content, span EVIDENCE across it.
       Do NOT create: EVIDENCE→[117], EVIDENCE→[175]
       DO create: EVIDENCE→[175] (one section spanning the full range)

    ⚠️ MYSTERY VIDEOS: If the video has "Something is missing from my understanding" or similar,
       that sentence STARTS the TURN, not the later insight/answer sentence.
       TURN = where confusion is admitted, not where answers are given.
    """
    }
    
    /// Extracts JSON from a response that may contain preamble text or markdown fences
    private func extractJSON(from response: String) -> String? {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace smart quotes first
        text = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // "
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // "
            .replacingOccurrences(of: "\u{2018}", with: "'")   // '
            .replacingOccurrences(of: "\u{2019}", with: "'")   // '

        // Try to find JSON in markdown code block first (most common case)
        if let jsonBlockRange = text.range(of: "```json") {
            let afterMarker = text[jsonBlockRange.upperBound...]
            if let endRange = afterMarker.range(of: "```") {
                let jsonContent = String(afterMarker[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print("✅ Extracted JSON from ```json block")
                return jsonContent
            }
        }

        // Try generic code block
        if let codeBlockRange = text.range(of: "```") {
            let afterMarker = text[codeBlockRange.upperBound...]
            // Skip language identifier if present (e.g., "json\n")
            var jsonStart = afterMarker.startIndex
            if let newlineIndex = afterMarker.firstIndex(of: "\n") {
                jsonStart = afterMarker.index(after: newlineIndex)
            }
            if let endRange = afterMarker.range(of: "```", range: jsonStart..<afterMarker.endIndex) {
                let jsonContent = String(afterMarker[jsonStart..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print("✅ Extracted JSON from ``` block")
                return jsonContent
            }
        }

        // If no markdown block, try to find JSON object directly
        // Look for first { and match to last }
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            let jsonContent = String(text[firstBrace...lastBrace])
            // Validate it's actually JSON by checking basic structure
            if jsonContent.contains("\"") && jsonContent.count > 10 {
                print("✅ Extracted JSON object from position \(text.distance(from: text.startIndex, to: firstBrace))")
                return jsonContent
            }
        }

        // If already clean JSON, return as-is
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return text
        }

        return nil
    }

    func parseResponse(_ jsonString: String) throws -> AlignmentResponse {
        print("\n")
        print("========================================")
        print("🔍 STARTING JSON PARSING")
        print("========================================")

        print("\n📥 RAW RESPONSE:")
        print("Length: \(jsonString.count) characters")
        print("First 200 chars: \(String(jsonString.prefix(200)))")

        print("\n🧹 EXTRACTING JSON...")

        // Use robust extraction
        guard let cleanJSON = extractJSON(from: jsonString) else {
            print("\n⚠️ COULD NOT EXTRACT JSON FROM RESPONSE!")
            print("First 500 chars: \(String(jsonString.prefix(500)))")
            print("\nThis is likely an error message or refusal from Claude.")
            throw PromptEngineError.invalidJSON("Could not extract JSON from response. Starts with: '\(String(jsonString.prefix(50)))'")
        }

        print("\n📋 EXTRACTED JSON:")
        print("Length after extraction: \(cleanJSON.count) characters")
        print(String(cleanJSON.prefix(200)))

        guard let jsonData = cleanJSON.data(using: .utf8) else {
            print("❌ Could not convert to UTF-8 data")
            throw PromptEngineError.invalidJSON("Could not convert to UTF-8 data")
        }
        
        print("✅ Converted to Data: \(jsonData.count) bytes")
        
        print("\n🔬 ATTEMPTING TO DECODE JSON...")
        
        let decoder = JSONDecoder()
        
        do {
            let response = try decoder.decode(AlignmentResponse.self, from: jsonData)
            print("✅ JSON DECODED SUCCESSFULLY!")
            print("📝 Video Summary: \(response.videoSummary)...")
            print("Sections found: \(response.sections.count)")
            print("Logic spine chain length: \(response.logicSpine.chain.count)")
            print("Causal links: \(response.logicSpine.causalLinks.count)")
            print("Bridge points: \(response.bridgePoints.count)")
            
            // Log each section
            for (index, section) in response.sections.enumerated() {
                print("\nSection \(index + 1):")
                print("  ID: \(section.id)")
                print("  Role: \(section.role)")
                print("  Boundary sentence: \(section.boundarySentence.map { String($0) } ?? "(final section)")")
            }
            
            print("\n========================================")
            print("✅ PARSING COMPLETE")
            print("========================================\n")
            
            return response
            
        } catch let DecodingError.keyNotFound(key, context) {
            print("\n❌ KEY NOT FOUND ERROR")
            print("Missing key: '\(key.stringValue)'")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            print("Underlying error: \(String(describing: context.underlyingError))")
            throw PromptEngineError.invalidJSON("Missing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            
        } catch let DecodingError.typeMismatch(type, context) {
            print("\n❌ TYPE MISMATCH ERROR")
            print("Expected type: \(type)")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            print("Underlying error: \(String(describing: context.underlyingError))")
            throw PromptEngineError.invalidJSON("Type mismatch - expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            
        } catch let DecodingError.valueNotFound(type, context) {
            print("\n❌ VALUE NOT FOUND ERROR")
            print("Expected type: \(type)")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            throw PromptEngineError.invalidJSON("Value not found for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            
        } catch let DecodingError.dataCorrupted(context) {
            print("\n❌ DATA CORRUPTED ERROR")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            print("Underlying error: \(String(describing: context.underlyingError))")
            print("\n⚠️ ACTUAL RESPONSE RECEIVED (first 500 chars):")
            print(String(cleanJSON.prefix(500)))
            print("\n⚠️ This usually means Claude returned a text message instead of JSON.")
            print("Check if: 1) Prompt is too long, 2) API rate limited, 3) Content policy issue")
            throw PromptEngineError.invalidJSON("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            
        } catch {
            print("\n❌ UNKNOWN DECODING ERROR")
            print("Error type: \(type(of: error))")
            print("Error: \(error)")
            print("Localized description: \(error.localizedDescription)")
            throw PromptEngineError.invalidJSON("Unknown error: \(error.localizedDescription)")
        }
    }
    
    func calculateTimestamps(response: AlignmentResponse) -> AlignmentData {
        print("\n")
        print("========================================")
        print("📐 RESOLVING SENTENCE BOUNDARIES")
        print("========================================")

        guard let transcript = video.transcript else {
            fatalError("No transcript available")
        }

        // Parse transcript into sentences (same as generatePrompt)
        let sentences = SentenceParser.parse(transcript)
        let sentenceCount = sentences.count

        // Total words computed from actual transcript (for timestamp estimation)
        let totalWords = transcript.split(separator: " ").count
        let videoDurationSeconds = TimestampCalculator.parseDuration(video.duration)
        let wordsPerSecond = videoDurationSeconds > 0 ? Double(totalWords) / Double(videoDurationSeconds) : 0

        print("\n📊 Transcript Stats:")
        print("Total transcript length: \(transcript.count) characters")
        print("Total sentences: \(sentenceCount)")
        print("Total words: \(totalWords)")
        print("Words per second: \(String(format: "%.2f", wordsPerSecond))")

        // Log boundary sentences from response
        print("\n🔍 Processing \(response.sections.count) sections with sentence boundaries...")
        for (index, section) in response.sections.enumerated() {
            if let boundary = section.boundarySentence {
                print("  Section \(index + 1) (\(section.role)): ends at sentence [\(boundary)]")
            } else {
                print("  Section \(index + 1) (\(section.role)): ends at transcript end")
            }
        }

        // Build SectionData array from sentence boundaries
        // CRITICAL: Word indexes are computed FROM the extracted sentence text, not from pre-computed ranges
        var sectionsWithWordBoundaries: [SectionData] = []
        var currentStartSentence = 0  // 0-indexed
        var currentWordPosition = 0   // Track cumulative word position

        print("\n🔍 Converting sentence boundaries to sections (sentence-first approach):")
        for (index, section) in response.sections.enumerated() {
            // Determine end sentence (convert from 1-indexed to 0-indexed)
            let endSentence: Int
            if let boundary = section.boundarySentence {
                endSentence = boundary - 1  // Convert 1-indexed to 0-indexed
            } else {
                endSentence = sentenceCount - 1  // Last section goes to end
            }

            // Validate sentence range
            guard currentStartSentence < sentenceCount && endSentence < sentenceCount && currentStartSentence <= endSentence else {
                print("  ⚠️ Invalid sentence range for section \(index + 1): \(currentStartSentence) to \(endSentence)")
                continue
            }

            // STEP 1: Extract text from sentences (this is the SOURCE OF TRUTH)
            let sectionSentences = sentences[currentStartSentence...endSentence]
            let sectionText = sectionSentences.joined(separator: " ")

            // STEP 2: Compute word indexes FROM the actual text we just extracted
            let sectionWordCount = sectionText.split(separator: " ").count
            let startWordIndex = currentWordPosition
            let endWordIndex = currentWordPosition + sectionWordCount - 1

            // STEP 3: Advance word position for next section
            currentWordPosition = endWordIndex + 1

            // Derive boundaryText from the actual boundary sentence (for downstream compatibility)
            let boundaryText = section.boundarySentence != nil ? sentences[endSentence] : nil

            print("\nSection \(index + 1) (\(section.id) - \(section.role)):")
            print("  Sentence range: [\(currentStartSentence + 1)] to [\(endSentence + 1)]")
            print("  Section text (\(sectionWordCount) words): \"\(String(sectionText.prefix(60)))...\"")
            print("  Word range (computed from text): \(startWordIndex) - \(endWordIndex)")
            if let bt = boundaryText {
                print("  Boundary text: \"\(bt.prefix(50))...\"")
            }

            // Estimate time from word indexes for display purposes
            let estimatedStartTime = wordsPerSecond > 0 ? Int(Double(startWordIndex) / wordsPerSecond) : 0
            let estimatedEndTime = wordsPerSecond > 0 ? Int(Double(endWordIndex) / wordsPerSecond) : 0
            print("  Estimated time: \(formatSeconds(estimatedStartTime)) - \(formatSeconds(estimatedEndTime))")

            // Convert nested sections if present
            let nestedSections: [NestedSection]? = section.nestedSections?.map { nested in
                NestedSection(
                    role: nested.role,
                    startSentence: nested.startSentence,
                    endSentence: nested.endSentence
                )
            }

            if let nested = nestedSections, !nested.isEmpty {
                print("  Nested sections: \(nested.count)")
                for ns in nested {
                    print("    - \(ns.role): sentences [\(ns.startSentence)] to [\(ns.endSentence)]")
                }
            }

            let sectionData = SectionData(
                id: "\(video.videoId)_\(section.id)",
                timeRange: nil,  // No longer storing time as primary data
                startSentenceIndex: currentStartSentence,  // 0-indexed
                endSentenceIndex: endSentence,              // 0-indexed
                startWordIndex: startWordIndex,   // Computed FROM the text
                endWordIndex: endWordIndex,       // Computed FROM the text
                role: section.role,
                goal: section.goal,
                logicSpineStep: section.logicSpineStep,
                nestedSections: nestedSections,
                boundaryText: boundaryText,
                matchConfidence: 1.0  // Deterministic lookup = 100% confidence
            )

            sectionsWithWordBoundaries.append(sectionData)

            // Next section starts at the sentence after this one ends
            currentStartSentence = endSentence + 1
        }

        print("\n✅ All section boundaries resolved from sentence numbers")

        // Validate contiguity
        print("\n🔍 Boundary Validation:")
        var validationIssues: [String] = []
        for i in 0..<(sectionsWithWordBoundaries.count - 1) {
            let current = sectionsWithWordBoundaries[i]
            let next = sectionsWithWordBoundaries[i + 1]
            if let currentEnd = current.endWordIndex, let nextStart = next.startWordIndex {
                if currentEnd + 1 != nextStart {
                    validationIssues.append("Gap between section \(i + 1) and \(i + 2): word \(currentEnd) to \(nextStart)")
                }
            }
        }
        if validationIssues.isEmpty {
            print("  ✅ All boundaries valid and contiguous")
        } else {
            for issue in validationIssues {
                print("  ⚠️ \(issue)")
            }
        }

        // Convert causal links
        print("\n🔗 Processing Causal Links:")
        let causalLinks = response.logicSpine.causalLinks.map { link in
            CausalLink(
                from: "\(video.videoId)_\(link.from)",
                to: "\(video.videoId)_\(link.to)",
                connection: link.connection
            )
        }
        print("✅ \(causalLinks.count) causal links processed")

        // Calculate bridge point timestamps (estimated from word position)
        print("\n🌉 Processing Bridge Points:")
        var bridgePointsWithTimestamps: [BridgePoint] = []

        for (index, bridge) in response.bridgePoints.enumerated() {
            print("\nBridge \(index + 1):")
            print("  Text: '\(String(bridge.text.prefix(60)))'...")
            print("  Belongs to: \(bridge.belongsTo.joined(separator: ", "))")

            // Find approximate word position for bridge text
            let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
            let timestamp = calculator.calculateTimestamp(for: bridge.text)
            print("  ✅ Estimated timestamp: \(timestamp)s (\(formatSeconds(timestamp)))")

            let bridgeData = BridgePoint(
                text: bridge.text,
                belongsTo: bridge.belongsTo.map { "\(video.videoId)_\($0)" },
                timestamp: timestamp
            )

            bridgePointsWithTimestamps.append(bridgeData)
        }
        print("\n✅ All bridge points processed")

        // Create alignment data
        let alignmentData = AlignmentData(
            videoId: video.videoId,
            channelId: video.channelId,
            videoSummary: response.videoSummary,
            sections: sectionsWithWordBoundaries,
            logicSpine: LogicSpineData(
                chain: response.logicSpine.chain,
                causalLinks: causalLinks
            ),
            bridgePoints: bridgePointsWithTimestamps
        )

        // Validate
        print("\n✅ Running Validation:")
        let validator = AlignmentValidator()
        let validation = validator.validate(alignmentData)

        print("Validation status: \(validation.status)")
        if !validation.issues.isEmpty {
            print("Issues found: \(validation.issues.count)")
            for issue in validation.issues {
                print("  [\(issue.severity)] \(issue.type): \(issue.message)")
            }
        } else {
            print("No validation issues found")
        }

        var finalData = alignmentData
        finalData.validationStatus = validation.status
        finalData.validationIssues = validation.issues.isEmpty ? nil : validation.issues

        print("\n========================================")
        print("✅ WORD BOUNDARY PROCESSING COMPLETE")
        print("========================================\n")

        return finalData
    }
    
    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    // Response structure (updated for sentence-based boundaries)
    struct AlignmentResponse: Codable {
        struct NestedSectionResponse: Codable {
            let role: String
            let startSentence: Int
            let endSentence: Int
        }

        struct SectionResponse: Codable {
            let id: String
            let boundarySentence: Int?  // Sentence number where section ends (null for final section)
            let role: String
            let goal: String
            let logicSpineStep: String
            let nestedSections: [NestedSectionResponse]?  // Optional nested sections (e.g., sponsorship inside evidence)
        }

        struct CausalLinkResponse: Codable {
            let from: String
            let to: String
            let connection: String
        }

        struct LogicSpineResponse: Codable {
            let chain: [String]
            let causalLinks: [CausalLinkResponse]
        }

        struct BridgePointResponse: Codable {
            let text: String
            let belongsTo: [String]
        }

        let videoSummary: String
        let sections: [SectionResponse]
        let logicSpine: LogicSpineResponse
        let bridgePoints: [BridgePointResponse]
    }
}


// MARK: - Error Types

// MARK: - Unified Error Handling for All Prompt Engines

enum PromptEngineError: LocalizedError {
    case invalidJSON(String)
    case noTranscript
    case noAlignment
    case missingBeatData
    case invalidBeatIndex
    case parsingFailed(String)
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON(let details):
            return "JSON parsing failed: \(details)"
        case .noTranscript:
            return "No transcript available for this video"
        case .noAlignment:
            return "No alignment data available. Run A1a first."
        case .missingBeatData:
            return "Beat data is missing or incomplete"
        case .invalidBeatIndex:
            return "Invalid beat index provided"
        case .parsingFailed(let details):
            return "Response parsing failed: \(details)"
        case .notImplemented:
            return "This feature is not yet implemented"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidJSON:
            return "Check that the AI response is valid JSON without markdown formatting"
        case .noTranscript:
            return "Ensure the video has been processed and transcript extracted"
        case .noAlignment:
            return "Run structural spine extraction (A1a) before beat extraction"
        case .missingBeatData:
            return "Run beat boundary extraction (A1b) before detailed extraction"
        case .invalidBeatIndex:
            return "Verify the beat exists in the section"
        case .parsingFailed:
            return "The AI response may be incomplete or malformed"
        case .notImplemented:
            return "This feature will be available in a future update"
        }
    }
}

// MARK: - Reusable UI Components

struct PromptDisplayView: View {
    let prompt: String
    let stepNumber: Int
    let stepTitle: String
    let onCopy: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "\(stepNumber).circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(stepTitle)
                    .font(.headline)
            }
            
            Text("Copy this prompt and paste it into Claude.ai")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ScrollView {
                Text(prompt)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            }
            .frame(height: 300)
            
            HStack {
                Button(action: onCopy) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onNext) {
                    Label("Next: Paste Response", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct ResponsePasteView: View {
    @Binding var response: String
    let stepNumber: Int
    let stepTitle: String
    let error: String?
    let onBack: () -> Void
    let onProcess: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "\(stepNumber).circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text(stepTitle)
                    .font(.headline)
            }
            
            Text("Paste Claude's JSON response below")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextEditor(text: $response)
                .font(.system(.body, design: .monospaced))
                .frame(height: 300)
                .padding(4)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onProcess) {
                    Label("Process & Calculate", systemImage: "gearshape.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}


// MARK: - Review Views

struct SectionReviewView: View {
    let alignment: AlignmentData
    let onBack: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "3.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Review Calculated Timestamps")
                    .font(.headline)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(alignment.sections.enumerated()), id: \.element.id) { index, section in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(section.role)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(roleColor(section.role).opacity(0.2))
                                    .foregroundColor(roleColor(section.role))
                                    .cornerRadius(4)
                                
                                Text(formatSectionBoundary(section))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            
                            Text(section.goal)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                    }
                    
                    Divider()
                    
                    Text("Bridge Points: \(alignment.bridgePoints.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Logic Spine: \(alignment.logicSpine.chain.count) steps")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let issues = alignment.validationIssues, !issues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Validation Issues:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(issues, id: \.message) { issue in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundColor(issue.severity == .error ? .red : .orange)
                                    Text(issue.message)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 400)
            
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onSave) {
                    Label("Save to Firebase", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private func roleColor(_ role: String) -> Color {
        switch role {
        case "HOOK": return .blue
        case "SETUP": return .green
        case "EVIDENCE": return .purple
        case "TURN": return .orange
        case "PAYOFF": return .pink
        case "CTA": return .red
        case "SPONSORSHIP": return .gray
        default: return .secondary
        }
    }
    
    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatSectionBoundary(_ section: SectionData) -> String {
        // Prefer word boundaries (new format)
        if let start = section.startWordIndex, let end = section.endWordIndex {
            return "words \(start)-\(end)"
        }
        // Fall back to time range (legacy format)
        if let timeRange = section.timeRange {
            return "\(formatSeconds(timeRange.start)) - \(formatSeconds(timeRange.end))"
        }
        return "—"
    }
}

struct BeatReviewView: View {
    let beatData: SimpleBeatData  // Changed from BeatData
    let onBack: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "3.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Review Extracted Beats")
                    .font(.headline)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Beats (\(beatData.beats.count))")
                        .font(.headline)
                    
                    ForEach(Array(beatData.beats.enumerated()), id: \.offset) { index, beat in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(beat.type)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(beatTypeColor(beat.type).opacity(0.2))
                                    .foregroundColor(beatTypeColor(beat.type))
                                    .cornerRadius(4)
                                
                                Spacer()
                                
                                Text(formatSeconds(beat.timeRange.start))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(beat.text)
                                .font(.body)
                            
                            Text("Word range: \(beat.startWordIndex) - \(beat.endWordIndex)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 400)
            
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onSave) {
                    Label("Save & Continue", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private func beatTypeColor(_ type: String) -> Color {
        switch type {
        case "TEASE": return .purple
        case "QUESTION": return .blue
        case "PROMISE": return .green
        case "DATA": return .orange
        case "STORY": return .pink
        case "AUTHORITY": return .red
        case "SYNTHESIS": return .cyan
        case "TURN": return .indigo
        case "CALLBACK": return .yellow
        case "CTA": return .brown
        default: return .gray
        }
    }
    
    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
struct A1aCompleteView: View {
    let alignment: AlignmentData
    let onDone: () -> Void
    let onContinue: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.green)
                Text("A1a Complete!")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("✅ Extracted \(alignment.sections.count) sections")
                Text("✅ Logic spine: \(alignment.logicSpine.chain.count) steps")
                Text("✅ Bridge points: \(alignment.bridgePoints.count)")
                Text("✅ Timestamps calculated")
                
                if let issues = alignment.validationIssues, !issues.isEmpty {
                    Text("⚠️ \(issues.filter { $0.severity == .warning }.count) warnings")
                        .foregroundColor(.orange)
                }
            }
            .font(.subheadline)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            
            Divider()
            
            Text("Ready for A1b: Beat Extraction")
                .font(.headline)
            
            Text("Extract beats for each of the \(alignment.sections.count) sections")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Button(action: onDone) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onContinue) {
                    Label("Continue to A1b", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
