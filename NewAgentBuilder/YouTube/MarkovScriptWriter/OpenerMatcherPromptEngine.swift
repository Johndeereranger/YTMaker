//
//  OpenerMatcherPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/11/26.
//
//  Builds the two-stage opener matching prompt and parses the JSON response.
//  Stage 1: Identify 3 distinct opening strategies for the rambling material.
//  Stage 2: For each strategy, find the 2 best corpus matches.
//

import Foundation

struct OpenerMatcherPromptEngine {

    static let PROMPT_VERSION = "v1.0"

    // MARK: - Input Types

    struct Input {
        let corpusOpenings: [CorpusOpening]
        let rawRamblingText: String
        let ramblingGists: [RamblingGist]
    }

    struct CorpusOpening {
        let videoId: String
        let title: String
        let sectionTexts: [(label: String, text: String)]  // 1 or 2 entries
    }

    // MARK: - LLM Response Types (Codable for JSON decoding)

    struct LLMResponse: Codable {
        let rambling_profile: LLMRamblingProfile
        let strategies: [LLMStrategy]
        let anti_matches: [LLMAntiMatch]?
    }

    struct LLMRamblingProfile: Codable {
        let entry_energy: String
        let emotional_trajectory: String
        let stakes_shape: String
        let complexity_load: String
        let speaker_posture: String
    }

    struct LLMStrategy: Codable {
        let strategy_id: String
        let strategy_name: String
        let strategy_description: String
        let matches: [LLMMatch]
    }

    struct LLMMatch: Codable {
        let rank: Int
        let video_id: String
        let video_title: String
        let match_reasoning: String
        let opening_strategy_summary: String
    }

    struct LLMAntiMatch: Codable {
        let video_id: String
        let video_title: String
        let why_not: String
    }

    // MARK: - Pattern-Based Response Types

    struct LLMPatternResponse: Codable {
        let rambling_profile: LLMRamblingProfile
        let strategies: [LLMPatternStrategy]
    }

    struct LLMPatternStrategy: Codable {
        let strategy_id: String
        let pattern_label: String
        let strategy_name: String
        let strategy_description: String
        let match_reasoning: String
    }

    // MARK: - Prompt Building

    static func buildPrompt(input: Input) -> (system: String, user: String) {
        let system = buildSystemPrompt()
        let user = buildUserPrompt(input: input)
        return (system, user)
    }

    private static func buildSystemPrompt() -> String {
        """
        You are a script structure analyst. You will be given two things:

        1. A creator's raw spoken ramblings about a video they want to make, along with extracted gist summaries of that rambling.
        2. A library of real video openings from a specific YouTube creator. Each opening contains the first two sections of a real, published video — the actual script text as performed, with rhetorical move labels.

        Your job has two stages:

        STAGE 1: Read the rambling and identify 3 distinct opening strategies that could work. These are not 3 variations of the same approach — they are fundamentally different storytelling directions. The viewer's experience in the first 60 seconds should feel different for each strategy. Name each strategy and describe what it does to the audience.

        STAGE 2: For each of your 3 strategies, find the 2 best openings from the library that execute that strategy. This gives 6 total picks organized into 3 strategic buckets.

        ## What "Fit" Means

        You are NOT matching by topic. A rambling about deer behavior might best match an opening from a video about truck modifications if both share the same narrative energy.

        What you ARE matching:

        - **Entry energy.** Does the rambling start with a personal moment? A question the speaker is wrestling with? A problem they encountered? A surprising thing they learned? Match that to openings that enter the same way.

        - **Emotional trajectory.** Does the rambling build from confusion to clarity? From excitement to concern? From a specific moment to a big idea? Find openings that travel the same emotional arc across their two sections.

        - **Stakes shape.** Is the rambling driven by personal stakes ("this happened to me"), communal stakes ("hunters need to know this"), discovery stakes ("I found something nobody's talking about"), or correction stakes ("everyone's wrong about this")? Match to openings that establish stakes the same way.

        - **Complexity load.** Does the rambling introduce one clean idea or juggle multiple threads? Match to openings that handle similar density — a simple rambling shouldn't get matched to an opening that juggles three ideas in two sections, and vice versa.

        - **Speaker posture.** Is the speaker positioned as explorer, teacher, challenger, storyteller, or reporter in the rambling? Match to openings where the creator adopts a similar posture.

        ## How to Evaluate

        First, profile the rambling across all 5 dimensions.

        Then, before matching to specific videos, step back and ask: what are the genuinely different ways this material could open? Different strategies should produce different viewer experiences — not just different templates for the same experience. Think about what the viewer knows, feels, and expects after the first 60 seconds under each strategy.

        Then scan the library for the 2 best executions of each strategy.

        Do not just pick openings that share keywords or subject matter with the rambling. Two openings about completely different topics can have identical structural DNA. You are matching DNA, not topic.

        ## Output Format

        Return your response in this exact JSON structure:

        {
          "rambling_profile": {
            "entry_energy": "one sentence",
            "emotional_trajectory": "one sentence",
            "stakes_shape": "one sentence",
            "complexity_load": "one sentence",
            "speaker_posture": "one sentence"
          },
          "strategies": [
            {
              "strategy_id": "A",
              "strategy_name": "short evocative name, e.g. 'The Investigation Frame'",
              "strategy_description": "2-3 sentences describing what this opening strategy does to the viewer. What do they know, feel, and expect after the first 60 seconds?",
              "matches": [
                {
                  "rank": 1,
                  "video_id": "the video ID from the library",
                  "video_title": "the title if provided",
                  "match_reasoning": "2-3 sentences on WHY this opening executes this strategy well and why it fits this rambling material",
                  "opening_strategy_summary": "One sentence describing what this specific opening does structurally"
                },
                {
                  "rank": 2,
                  "video_id": "...",
                  "video_title": "...",
                  "match_reasoning": "...",
                  "opening_strategy_summary": "..."
                }
              ]
            },
            {
              "strategy_id": "B",
              "strategy_name": "...",
              "strategy_description": "...",
              "matches": [{"rank": 1, "video_id": "...", "video_title": "...", "match_reasoning": "...", "opening_strategy_summary": "..."}, {"rank": 2, "video_id": "...", "video_title": "...", "match_reasoning": "...", "opening_strategy_summary": "..."}]
            },
            {
              "strategy_id": "C",
              "strategy_name": "...",
              "strategy_description": "...",
              "matches": [{"rank": 1, "video_id": "...", "video_title": "...", "match_reasoning": "...", "opening_strategy_summary": "..."}, {"rank": 2, "video_id": "...", "video_title": "...", "match_reasoning": "...", "opening_strategy_summary": "..."}]
            }
          ],
          "anti_matches": [
            {
              "video_id": "id",
              "video_title": "title",
              "why_not": "One sentence on why this opening was tempting but structurally wrong for this rambling"
            }
          ]
        }

        Always return exactly 3 strategies with exactly 2 matches each. Include 1-2 anti_matches only if there were openings that seemed close but had a critical structural mismatch — this helps calibrate future runs. If nothing was tempting-but-wrong, return an empty anti_matches array.

        No duplicate video_ids across the 6 matches. Each opening can only appear once.
        """
    }

    private static func buildUserPrompt(input: Input) -> String {
        var parts: [String] = []

        // --- Ramblings ---
        parts.append("## MY RAMBLINGS")
        parts.append("")
        parts.append("### Raw Rambling")
        parts.append(input.rawRamblingText)
        parts.append("")
        parts.append("### Extracted Gists")

        for (index, gist) in input.ramblingGists.enumerated() {
            let frame = gist.gistA.frame.rawValue
            let subject = gist.gistA.subject.joined(separator: ", ")
            let premise = gist.gistA.premise
            parts.append("- Gist \(index + 1): [\(frame)] \(subject) — \(premise)")
        }

        parts.append("")
        parts.append("---")
        parts.append("")

        // --- Opening Library ---
        parts.append("## OPENING LIBRARY (\(input.corpusOpenings.count) videos)")
        parts.append("")

        for opening in input.corpusOpenings {
            parts.append("### Video: \(opening.videoId) | \(opening.title)")
            parts.append("")

            for (sectionIndex, section) in opening.sectionTexts.enumerated() {
                parts.append("**Section \(sectionIndex) (\(section.label)):**")
                parts.append(section.text)
                parts.append("")
            }

            parts.append("---")
            parts.append("")
        }

        parts.append("Based on my ramblings above, identify 3 distinct opening strategies that could work for this material, then find the 2 best openings from the library for each strategy. Match on structural DNA, not topic.")

        return parts.joined(separator: "\n")
    }

    // MARK: - Response Parsing

    /// Parse the LLM response, validating video IDs against the known corpus.
    static func parseResponse(rawResponse: String, validVideoIds: Set<String>) throws -> LLMResponse {
        guard let jsonString = extractJSON(from: rawResponse) else {
            throw OpenerMatcherError.invalidJSON("Could not extract JSON from response. Raw length: \(rawResponse.count) chars.")
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw OpenerMatcherError.invalidJSON("Could not convert extracted JSON to data.")
        }

        let decoder = JSONDecoder()
        let response: LLMResponse

        do {
            response = try decoder.decode(LLMResponse.self, from: jsonData)
        } catch let DecodingError.keyNotFound(key, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw OpenerMatcherError.invalidJSON("Missing key '\(key.stringValue)' at path: \(path)")
        } catch let DecodingError.typeMismatch(type, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw OpenerMatcherError.invalidJSON("Type mismatch: expected \(type) at path: \(path)")
        } catch let DecodingError.dataCorrupted(context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw OpenerMatcherError.invalidJSON("Data corrupted at path: \(path)")
        } catch {
            throw OpenerMatcherError.parsingFailed("JSON decode failed: \(error.localizedDescription)")
        }

        // Validate structure: exactly 3 strategies, exactly 2 matches each
        guard response.strategies.count == 3 else {
            throw OpenerMatcherError.validationFailed("Expected 3 strategies, got \(response.strategies.count)")
        }

        // Validate no duplicate video IDs across all matches
        let allMatchVideoIds = response.strategies.flatMap { $0.matches.map(\.video_id) }
        let uniqueIds = Set(allMatchVideoIds)
        if uniqueIds.count != allMatchVideoIds.count {
            print("⚠️ Opener Matcher: Duplicate video IDs in response — \(allMatchVideoIds)")
        }

        // Validate video IDs exist in corpus
        let invalidIds = uniqueIds.subtracting(validVideoIds)
        if !invalidIds.isEmpty {
            print("⚠️ Opener Matcher: LLM returned video IDs not in corpus: \(invalidIds)")
            throw OpenerMatcherError.validationFailed("Unknown video IDs: \(invalidIds.joined(separator: ", "))")
        }

        return response
    }

    // MARK: - Pattern-Based Prompt Building

    /// Build a prompt that presents pre-computed opening patterns and asks the LLM to pick 3.
    static func buildPatternPrompt(
        patterns: [OpeningPattern],
        patternSamples: [String: [CorpusOpening]],
        rawRamblingText: String,
        ramblingGists: [RamblingGist]
    ) -> (system: String, user: String) {
        let system = buildPatternSystemPrompt()
        let user = buildPatternUserPrompt(
            patterns: patterns,
            patternSamples: patternSamples,
            rawRamblingText: rawRamblingText,
            ramblingGists: ramblingGists
        )
        return (system, user)
    }

    private static func buildPatternSystemPrompt() -> String {
        """
        You are a script structure analyst. You will be given two things:

        1. A creator's raw spoken ramblings about a video they want to make, along with extracted gist summaries.
        2. A library of OPENING PATTERNS from this creator's published videos. Each pattern represents a specific structural opening — defined by the first two rhetorical moves — used across multiple videos.

        Your job: Pick the 3 opening patterns from the library that best fit the rambling material.

        ## What "Fit" Means

        You are NOT matching by topic. Match on structural DNA:

        - **Entry energy.** Does the rambling start with a personal moment? A question? A problem? A surprise? Match to patterns that enter the same way.

        - **Emotional trajectory.** Does the rambling build from confusion to clarity? Excitement to concern? Match patterns with similar arcs.

        - **Stakes shape.** Personal stakes, communal stakes, discovery stakes, or correction stakes? Match patterns that establish stakes the same way.

        - **Complexity load.** One clean idea or multiple threads? Match patterns handling similar density.

        - **Speaker posture.** Explorer, teacher, challenger, storyteller, reporter? Match patterns with similar posture.

        ## How to Evaluate

        First, profile the rambling across all 5 dimensions.

        Then examine each pattern's sample openings. Different patterns should produce different viewer experiences in the first 60 seconds.

        Pick 3 patterns that offer genuinely different opening strategies for this material. Do not pick 3 variations of the same approach.

        ## Output Format

        Return your response in this exact JSON structure:

        {
          "rambling_profile": {
            "entry_energy": "one sentence",
            "emotional_trajectory": "one sentence",
            "stakes_shape": "one sentence",
            "complexity_load": "one sentence",
            "speaker_posture": "one sentence"
          },
          "strategies": [
            {
              "strategy_id": "A",
              "pattern_label": "exact pattern label from the library",
              "strategy_name": "short evocative name for this opening approach",
              "strategy_description": "2-3 sentences describing what this opening does to the viewer",
              "match_reasoning": "2-3 sentences on WHY this pattern's structural DNA fits this rambling"
            },
            {
              "strategy_id": "B",
              "pattern_label": "...",
              "strategy_name": "...",
              "strategy_description": "...",
              "match_reasoning": "..."
            },
            {
              "strategy_id": "C",
              "pattern_label": "...",
              "strategy_name": "...",
              "strategy_description": "...",
              "match_reasoning": "..."
            }
          ]
        }

        CRITICAL: The "pattern_label" must be an EXACT match to one of the pattern labels in the library. Do not modify, rephrase, or create new labels. Each strategy must use a different pattern.
        """
    }

    private static func buildPatternUserPrompt(
        patterns: [OpeningPattern],
        patternSamples: [String: [CorpusOpening]],
        rawRamblingText: String,
        ramblingGists: [RamblingGist]
    ) -> String {
        var parts: [String] = []

        // --- Ramblings ---
        parts.append("## MY RAMBLINGS")
        parts.append("")
        parts.append("### Raw Rambling")
        parts.append(rawRamblingText)
        parts.append("")
        parts.append("### Extracted Gists")

        for (index, gist) in ramblingGists.enumerated() {
            let frame = gist.gistA.frame.rawValue
            let subject = gist.gistA.subject.joined(separator: ", ")
            let premise = gist.gistA.premise
            parts.append("- Gist \(index + 1): [\(frame)] \(subject) \u{2014} \(premise)")
        }

        parts.append("")
        parts.append("---")
        parts.append("")

        // --- Pattern Library ---
        parts.append("## OPENING PATTERN LIBRARY (\(patterns.count) patterns)")
        parts.append("")

        for pattern in patterns {
            parts.append("### Pattern: \(pattern.label)")
            parts.append("Used in \(pattern.frequency) videos")
            parts.append("")

            if let samples = patternSamples[pattern.label] {
                for (i, sample) in samples.enumerated() {
                    parts.append("**Sample \(i + 1): \(sample.title)**")
                    for section in sample.sectionTexts {
                        parts.append("[\(section.label)]")
                        parts.append(section.text)
                        parts.append("")
                    }
                }
            }

            parts.append("---")
            parts.append("")
        }

        parts.append("Pick the 3 patterns from the library above that best fit my rambling material. Match on structural DNA, not topic. Each pattern_label must be an exact match from the library.")

        return parts.joined(separator: "\n")
    }

    // MARK: - Pattern Response Parsing

    /// Parse the pattern-based LLM response, validating pattern labels against computed patterns.
    static func parsePatternResponse(
        rawResponse: String,
        validPatternLabels: Set<String>
    ) throws -> LLMPatternResponse {
        guard let jsonString = extractJSON(from: rawResponse) else {
            throw OpenerMatcherError.invalidJSON("Could not extract JSON from pattern response. Raw length: \(rawResponse.count) chars.")
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw OpenerMatcherError.invalidJSON("Could not convert pattern JSON to data.")
        }

        let response: LLMPatternResponse
        do {
            response = try JSONDecoder().decode(LLMPatternResponse.self, from: jsonData)
        } catch let DecodingError.keyNotFound(key, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw OpenerMatcherError.invalidJSON("Missing key '\(key.stringValue)' at path: \(path)")
        } catch let DecodingError.typeMismatch(type, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw OpenerMatcherError.invalidJSON("Type mismatch: expected \(type) at path: \(path)")
        } catch {
            throw OpenerMatcherError.parsingFailed("Pattern JSON decode failed: \(error.localizedDescription)")
        }

        // Validate exactly 3 strategies
        guard response.strategies.count == 3 else {
            throw OpenerMatcherError.validationFailed("Expected 3 strategies, got \(response.strategies.count)")
        }

        // Validate pattern labels exist in computed patterns
        for strategy in response.strategies {
            guard validPatternLabels.contains(strategy.pattern_label) else {
                throw OpenerMatcherError.validationFailed("Unknown pattern label: '\(strategy.pattern_label)'")
            }
        }

        // Validate no duplicate pattern labels
        let labels = response.strategies.map(\.pattern_label)
        let uniqueLabels = Set(labels)
        if uniqueLabels.count != labels.count {
            throw OpenerMatcherError.validationFailed("Duplicate pattern labels in response")
        }

        return response
    }

    // MARK: - Step 3: Draft Prompt Building

    /// Build the prompt for drafting an opening that mirrors the structural pattern of 2 matched templates.
    /// Called once per strategy (3 total calls). Original version using all gists.
    static func buildDraftPrompt(
        strategy: OpenerStrategy,
        matchOpenings: [CorpusOpening],
        rawRamblingText: String,
        ramblingGists: [RamblingGist]
    ) -> (system: String, user: String) {
        let system = buildDraftSystemPrompt()
        let user = buildDraftUserPrompt(
            strategy: strategy,
            matchOpenings: matchOpenings,
            rawRamblingText: rawRamblingText,
            ramblingGists: ramblingGists
        )
        return (system, user)
    }

    private static func buildDraftSystemPrompt() -> String {
        """
        You will receive template openings from a YouTube creator and raw spoken ramblings about a different topic. Write a new opening about the rambling's topic that sounds like the template creator wrote it.

        \(OpenerComparisonPromptEngine.NARRATIVE_MODE)

        \(OpenerComparisonPromptEngine.VERB_CONSTRAINT)

        \(OpenerComparisonPromptEngine.ACTOR_REQUIREMENT)

        \(OpenerComparisonPromptEngine.EVIDENCE_MINIMUM)

        \(OpenerComparisonPromptEngine.TEXTURE_RULES)

        CONTENT DISCIPLINE:
        - Use ONLY facts present in the raw material
        - Do not invent scenes, metaphors, details, or actors not in the source
        - If the source mentions hunters, a landowner, a drone, or equipment — use those as your actors
        - Do not give away findings or conclusions
        - End with the viewer wanting to know what happens next — use a question or a concrete next action ("So we flew a drone over this property"), NOT an evaluative tease ("what we found changed everything")

        Output only the script text. No commentary.
        """
    }

    private static func buildDraftUserPrompt(
        strategy: OpenerStrategy,
        matchOpenings: [CorpusOpening],
        rawRamblingText: String,
        ramblingGists: [RamblingGist]
    ) -> String {
        var parts: [String] = []

        // Templates first — the primary reference the LLM needs to match
        parts.append("## WRITE IT LIKE THIS:")
        parts.append("")
        for (i, opening) in matchOpenings.enumerated() {
            parts.append("### Template \(i + 1): \(opening.title)")
            for (sectionIndex, section) in opening.sectionTexts.enumerated() {
                parts.append("[\(section.label)]")
                parts.append(section.text)
                parts.append("")
            }
        }

        parts.append("---")
        parts.append("")

        // Raw rambling — content source
        parts.append("## WRITE IT ABOUT THIS:")
        parts.append(rawRamblingText)
        parts.append("")
        // Gists as quick reference for the key points in the rambling
        if !ramblingGists.isEmpty {
            parts.append("## KEY POINTS FROM THE RAMBLING:")
            for (index, gist) in ramblingGists.enumerated() {
                let frame = gist.gistA.frame.rawValue
                let subject = gist.gistA.subject.joined(separator: ", ")
                let premise = gist.gistA.premise
                parts.append("- \(index + 1). [\(frame)] \(subject) — \(premise)")
            }
            parts.append("")
        }

        return parts.joined(separator: "\n")
    }

    /// Build draft prompt using only the 2 filtered gists per strategy (after gist filter step).
    /// Each gist maps to a specific opening position.
    static func buildFilteredDraftPrompt(
        strategy: OpenerStrategy,
        matchOpenings: [CorpusOpening],
        filteredGists: [RamblingGist]
    ) -> (system: String, user: String) {
        let system = buildDraftSystemPrompt()
        let user = buildFilteredDraftUserPrompt(
            strategy: strategy,
            matchOpenings: matchOpenings,
            filteredGists: filteredGists
        )
        return (system, user)
    }

    private static func buildFilteredDraftUserPrompt(
        strategy: OpenerStrategy,
        matchOpenings: [CorpusOpening],
        filteredGists: [RamblingGist]
    ) -> String {
        var parts: [String] = []

        // Templates first — the primary reference the LLM needs to match
        parts.append("## WRITE IT LIKE THIS:")
        parts.append("")
        for (i, opening) in matchOpenings.enumerated() {
            parts.append("### Template \(i + 1): \(opening.title)")
            for (_, section) in opening.sectionTexts.enumerated() {
                parts.append("[\(section.label)]")
                parts.append(section.text)
                parts.append("")
            }
        }

        parts.append("---")
        parts.append("")

        // Filtered gists — exactly 2, one per position
        parts.append("## WRITE IT ABOUT THIS:")
        parts.append("")

        for (posIdx, gist) in filteredGists.enumerated() {
            let frame = gist.gistA.frame.displayName
            let subject = gist.gistA.subject.joined(separator: ", ")
            let premise = gist.gistA.premise
            parts.append("### Position \(posIdx + 1) Content:")
            parts.append("Frame: \(frame) | Subject: \(subject)")
            parts.append("Premise: \(premise)")
            parts.append("")
            parts.append("Raw material:")
            parts.append(gist.sourceText)
            parts.append("")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Step 4: Rewrite Prompt Building

    /// Build the prompt for a voice-correction rewrite pass.
    /// Takes the Step 2 draft + the same template openings and forces a concrete voice analysis before rewriting.
    static func buildRewritePrompt(
        draftText: String,
        matchOpenings: [CorpusOpening]
    ) -> (system: String, user: String) {
        let system = buildRewriteSystemPrompt()
        let user = buildRewriteUserPrompt(draftText: draftText, matchOpenings: matchOpenings)
        return (system, user)
    }

    private static func buildRewriteSystemPrompt() -> String {
        """
        You are rewriting a script opening to match a specific creator's voice. The draft has the right content but the voice and narrative mode have drifted.

        Before analyzing voice mechanics, answer this critical question:

        QUESTION 0 — NARRATIVE MODE:
        Classify every sentence in the TEMPLATES as one of:
        - EVENT (someone did something, something happened)
        - EVIDENCE (something was found, observed, or measured)
        - CONTRADICTION (what should be true vs. what is)
        - QUESTION (direct question to viewer)
        - ACTOR (new person or group enters the story doing something)
        - EVALUATION (judgment, explanation, advice, generalization)

        Count the ratio of EVENT+EVIDENCE+CONTRADICTION+ACTOR to EVALUATION sentences.

        Now classify every sentence in the DRAFT the same way. If the draft has more than 2 EVALUATION sentences, those must be REPLACED with EVENT or EVIDENCE sentences during the rewrite — not just revoiced. A well-textured explanation is still wrong.

        Now analyze the template openings and answer these questions:

        SKELETON QUESTIONS:
        1. What's the average sentence length? Count words in 5 representative sentences.
        2. How does the creator start sentences — with subjects, with observations, with "I", with scene details?
        3. Where do fragments appear and what job do they do?
        4. How do transitions between ideas work — conjunctions, jump cuts, rhetorical questions, temporal markers?

        TEXTURE QUESTIONS:
        5. DEMONSTRATIVE POINTING: Count every "this + noun" and "these + noun" in the templates. How often does the creator use "this" instead of "the" or "a"?
        6. NOUN REPETITION: After introducing a key noun, how many sentences before the creator switches to a pronoun? List instances where the full noun phrase is repeated where "it" would be grammatically correct.
        7. CONJUNCTION CHAIN PATTERNS: In sentences over 20 words, are they long because of subordinate clauses or because of "and/but" chaining? Copy the 3 longest sentences and mark where the conjunctions fall.
        8. CASUAL SPOKEN INSERTIONS: List every instance of casual/informal language — "like," "a nice little," "just over," etc. How many per paragraph?
        9. SPOKEN SYNTAX vs. WRITTEN SYNTAX: Does the creator use "what they found is that..." or "they found that..."? List spoken-syntax inversions.
        10. EVALUATIVE REGISTER AT PIVOT: When the creator transitions to stakes, is the language elevated or flat conversational? Quote the exact pivot sentences.

        Compare the draft against ALL observations — narrative mode, skeleton, AND texture.

        \(OpenerComparisonPromptEngine.VERB_CONSTRAINT)

        \(OpenerComparisonPromptEngine.ACTOR_REQUIREMENT)

        \(OpenerComparisonPromptEngine.EVIDENCE_MINIMUM)

        REWRITE PROCESS — three passes:

        PASS 1 — NARRATIVE MODE REPAIR:
        Before touching voice texture, check every draft sentence against the template's narrative mode ratio. If a sentence is EVALUATION type ("This isn't just bad luck," "Understanding why requires," "You need to understand"), replace it with an EVENT or EVIDENCE sentence using facts from the source material. You may restructure the draft significantly at this step. Actors must appear at least every other sentence.

        PASS 2 — ANNOTATED TEXTURE DRAFT:
        Now rewrite sentence by sentence applying texture. After each sentence, add brackets citing which texture features you are executing. Example:
        "They called it DD because more often than not they were actually seeing double-digit deer on this tree stand. [demonstrative: 'this tree stand'] [conjunction chain]"

        Every sentence must cite at least one texture feature. If you can't cite one, the sentence is probably too generic — rewrite it.

        PASS 3 — CLEAN FINAL:
        Strip all annotations for the final reading-ready script.

        Output your work in four sections:

        ## VOICE ANALYSIS
        [narrative mode classification + 10 question analysis]

        ## NARRATIVE MODE REPAIR
        [the restructured draft with evaluation sentences replaced by event/evidence sentences]

        ## ANNOTATED DRAFT
        [texture-annotated rewrite]

        ## REWRITTEN OPENING
        [clean final script]
        """
    }

    private static func buildRewriteUserPrompt(
        draftText: String,
        matchOpenings: [CorpusOpening]
    ) -> String {
        var parts: [String] = []

        parts.append("## THE VOICE TO MATCH:")
        parts.append("")
        for (i, opening) in matchOpenings.enumerated() {
            parts.append("### Template \(i + 1): \(opening.title)")
            for (_, section) in opening.sectionTexts.enumerated() {
                parts.append("[\(section.label)]")
                parts.append(section.text)
                parts.append("")
            }
        }

        parts.append("---")
        parts.append("")
        parts.append("## THE DRAFT TO REWRITE:")
        parts.append(draftText)

        return parts.joined(separator: "\n")
    }

    /// Parse the rewrite response into voice analysis and rewrite text.
    /// Extracts content between ## VOICE ANALYSIS and ## REWRITTEN OPENING markers.
    static func parseRewriteResponse(rawResponse: String) -> (voiceAnalysis: String, rewriteText: String) {
        let text = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the two markers
        let analysisMarker = "## VOICE ANALYSIS"
        let rewriteMarker = "## REWRITTEN OPENING"

        guard let analysisRange = text.range(of: analysisMarker),
              let rewriteRange = text.range(of: rewriteMarker) else {
            // Markers not found — return full response as rewrite, empty analysis
            return (voiceAnalysis: "", rewriteText: text)
        }

        let voiceAnalysis = String(text[analysisRange.upperBound..<rewriteRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rewriteText = String(text[rewriteRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (voiceAnalysis: voiceAnalysis, rewriteText: rewriteText)
    }

    /// Parse M2 V4 response with 4 sections: voice analysis, narrative mode repair, annotated draft, and clean rewrite.
    /// Falls back to 3-section (V3) then 2-section parsing if markers are missing.
    static func parseM2Response(rawResponse: String) -> (voiceAnalysis: String, narrativeModeRepair: String, annotatedDraft: String, rewriteText: String) {
        let text = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        let analysisMarker = "## VOICE ANALYSIS"
        let repairMarker = "## NARRATIVE MODE REPAIR"
        let annotatedMarker = "## ANNOTATED DRAFT"
        let rewriteMarker = "## REWRITTEN OPENING"

        // Try 4-section parse first (V4)
        if let analysisRange = text.range(of: analysisMarker),
           let repairRange = text.range(of: repairMarker),
           let annotatedRange = text.range(of: annotatedMarker),
           let rewriteRange = text.range(of: rewriteMarker) {

            let voiceAnalysis = String(text[analysisRange.upperBound..<repairRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let narrativeModeRepair = String(text[repairRange.upperBound..<annotatedRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let annotatedDraft = String(text[annotatedRange.upperBound..<rewriteRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rewriteText = String(text[rewriteRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return (voiceAnalysis: voiceAnalysis, narrativeModeRepair: narrativeModeRepair, annotatedDraft: annotatedDraft, rewriteText: rewriteText)
        }

        // Fallback: 3-section parse (V3 — no repair section)
        if let analysisRange = text.range(of: analysisMarker),
           let annotatedRange = text.range(of: annotatedMarker),
           let rewriteRange = text.range(of: rewriteMarker) {

            let voiceAnalysis = String(text[analysisRange.upperBound..<annotatedRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let annotatedDraft = String(text[annotatedRange.upperBound..<rewriteRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rewriteText = String(text[rewriteRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return (voiceAnalysis: voiceAnalysis, narrativeModeRepair: "", annotatedDraft: annotatedDraft, rewriteText: rewriteText)
        }

        // Fallback: 2-section parse
        let twoSection = parseRewriteResponse(rawResponse: rawResponse)
        return (voiceAnalysis: twoSection.voiceAnalysis, narrativeModeRepair: "", annotatedDraft: "", rewriteText: twoSection.rewriteText)
    }

    // MARK: - Step 2: Gist Filter Prompt Building

    struct GistFilterInput {
        let strategyId: String
        let strategyName: String
        /// Per-position data: 2 entries (position 0 and position 1).
        /// Each position may have candidates from 1-2 matched corpus videos.
        let positions: [GistFilterPositionInput]
    }

    struct GistFilterPositionInput {
        let positionIndex: Int
        /// Move types from the matched corpus videos at this position (1-2 entries).
        let corpusMoveTypes: [RhetoricalMoveType]
        /// Corpus section texts at this position from the matched videos.
        let corpusSections: [(videoTitle: String, moveLabel: String, text: String)]
        /// Candidate gists (already filtered by frame→move eligibility).
        let candidateGists: [RamblingGist]
    }

    struct LLMGistFilterResponse: Codable {
        let position_0: LLMGistSelection
        let position_1: LLMGistSelection
    }

    struct LLMGistSelection: Codable {
        let selected_gist_id: String
        let reasoning: String
    }

    /// Build the prompt for matching filtered gists to opening positions.
    /// Called once per strategy (3 total calls).
    static func buildGistFilterPrompt(input: GistFilterInput) -> (system: String, user: String) {
        let system = buildGistFilterSystemPrompt()
        let user = buildGistFilterUserPrompt(input: input)
        return (system, user)
    }

    private static func buildGistFilterSystemPrompt() -> String {
        """
        You are matching a speaker's rambling gists to structural opening positions.

        You will receive:
        1. Two opening positions from a creator's corpus videos. Each position has a rhetorical move label, category, and the actual script text from 1-2 reference videos.
        2. A pool of candidate gists from the speaker's ramblings. These have already been filtered to structurally compatible ones via frame→move eligibility.

        For each position, pick the single best gist. The best gist is the one whose CONTENT most naturally fills that structural slot. You are matching content-to-structure:
        - A "personal-stake" slot needs content with personal investment or first-person experience
        - A "shocking-fact" slot needs content with a surprising data point or counterintuitive claim
        - A "scene-set" slot needs content that paints a specific moment or place

        Look at what the corpus text DOES in each position, then find the gist whose raw material could do the same thing about a different topic.

        Choose facts that raise questions, not facts that answer them. Prefer gists that create a narrative problem or contradiction. Avoid analytical findings or investigation results that explain the mystery — those belong later in the script, not in the opening.

        Do NOT pick the same gist for both positions. Each position must get a different gist.

        Return your response as JSON:
        {
          "position_0": {
            "selected_gist_id": "the UUID string of the chosen gist",
            "reasoning": "1-2 sentences on why this gist's content fits this structural position"
          },
          "position_1": {
            "selected_gist_id": "the UUID string of the chosen gist",
            "reasoning": "1-2 sentences on why this gist's content fits this structural position"
          }
        }
        """
    }

    private static func buildGistFilterUserPrompt(input: GistFilterInput) -> String {
        var parts: [String] = []

        parts.append("## Strategy \(input.strategyId): \(input.strategyName)")
        parts.append("")

        // Position details with corpus references
        for pos in input.positions {
            let moveLabels = pos.corpusMoveTypes.map(\.displayName).joined(separator: " / ")
            let categories = Array(Set(pos.corpusMoveTypes.map { $0.category.rawValue })).joined(separator: ", ")
            parts.append("### POSITION \(pos.positionIndex): [\(moveLabels)] (\(categories))")
            parts.append("")

            for section in pos.corpusSections {
                parts.append("**Corpus: \(section.videoTitle)** [\(section.moveLabel)]:")
                parts.append(section.text)
                parts.append("")
            }

            parts.append("**Candidate Gists for Position \(pos.positionIndex):**")
            if pos.candidateGists.isEmpty {
                parts.append("(No structurally compatible gists — pick the best from all gists below)")
            } else {
                for gist in pos.candidateGists {
                    let frame = gist.gistA.frame.rawValue
                    let subject = gist.gistA.subject.joined(separator: ", ")
                    let premise = gist.gistA.premise
                    let sourceSnippet = String(gist.sourceText.prefix(300))
                    parts.append("- **ID: \(gist.id.uuidString)**")
                    parts.append("  Frame: \(frame) | Subject: \(subject)")
                    parts.append("  Premise: \(premise)")
                    parts.append("  Source: \"\(sourceSnippet)\"")
                    parts.append("")
                }
            }

            parts.append("---")
            parts.append("")
        }

        parts.append("Pick the single best gist for each position. Different gist for each position.")

        return parts.joined(separator: "\n")
    }

    /// Parse the gist filter LLM response, validating gist IDs.
    static func parseGistFilterResponse(
        rawResponse: String,
        validGistIds: Set<UUID>
    ) throws -> LLMGistFilterResponse {
        guard let jsonString = extractJSON(from: rawResponse) else {
            throw OpenerMatcherError.invalidJSON("Could not extract JSON from gist filter response. Raw length: \(rawResponse.count) chars.")
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw OpenerMatcherError.invalidJSON("Could not convert gist filter JSON to data.")
        }

        let response: LLMGistFilterResponse
        do {
            response = try JSONDecoder().decode(LLMGistFilterResponse.self, from: jsonData)
        } catch {
            throw OpenerMatcherError.parsingFailed("Gist filter JSON decode failed: \(error.localizedDescription)")
        }

        // Validate returned IDs exist in candidate pool
        if let id0 = UUID(uuidString: response.position_0.selected_gist_id), !validGistIds.contains(id0) {
            print("⚠️ Gist Filter: Position 0 selected gist \(response.position_0.selected_gist_id) not in candidate pool")
        }
        if let id1 = UUID(uuidString: response.position_1.selected_gist_id), !validGistIds.contains(id1) {
            print("⚠️ Gist Filter: Position 1 selected gist \(response.position_1.selected_gist_id) not in candidate pool")
        }

        // Validate not the same gist for both positions
        if response.position_0.selected_gist_id == response.position_1.selected_gist_id {
            print("⚠️ Gist Filter: Same gist selected for both positions: \(response.position_0.selected_gist_id)")
        }

        return response
    }

    // MARK: - JSON Extraction

    private static func extractJSON(from response: String) -> String? {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace smart quotes and ellipsis
        text = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2026}", with: "...")

        // Try ```json block first
        if let jsonBlockRange = text.range(of: "```json") {
            let afterMarker = text[jsonBlockRange.upperBound...]
            if let endRange = afterMarker.range(of: "```") {
                let jsonContent = String(afterMarker[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print("✅ Opener Matcher: Extracted JSON from ```json block")
                return jsonContent
            }
        }

        // Try generic ``` block
        if let codeBlockRange = text.range(of: "```") {
            let afterMarker = text[codeBlockRange.upperBound...]
            var jsonStart = afterMarker.startIndex
            if let newlineIndex = afterMarker.firstIndex(of: "\n") {
                jsonStart = afterMarker.index(after: newlineIndex)
            }
            if let endRange = afterMarker.range(of: "```", range: jsonStart..<afterMarker.endIndex) {
                let jsonContent = String(afterMarker[jsonStart..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print("✅ Opener Matcher: Extracted JSON from ``` block")
                return jsonContent
            }
        }

        // Try raw JSON object
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            let jsonContent = String(text[firstBrace...lastBrace])
            if jsonContent.contains("\"") && jsonContent.count > 10 {
                print("✅ Opener Matcher: Extracted raw JSON object")
                return jsonContent
            }
        }

        // Already clean JSON
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return text
        }

        return nil
    }
}

// MARK: - Error Types

enum OpenerMatcherError: LocalizedError {
    case invalidJSON(String)
    case parsingFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let details): return "JSON parsing failed: \(details)"
        case .parsingFailed(let details): return "Response parsing failed: \(details)"
        case .validationFailed(let details): return "Validation failed: \(details)"
        }
    }
}
