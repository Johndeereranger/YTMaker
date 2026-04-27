//
//  ArcComparisonPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  Prompt construction for the 5 narrative arc paths.
//  Reuses the 19-label function taxonomy and JSON output format
//  from NarrativeSpinePromptEngine.
//

import Foundation

struct ArcComparisonPromptEngine {

    // MARK: - Shared Components

    static let spineSystemPrompt = "You are a narrative structure analyst. Your job is to analyze raw creator ramblings and build narrative spines — structural blueprints of the story being told. Return valid JSON only. No markdown fences, no preamble, no commentary."

    static let functionTaxonomy = """
    ### Function labels

    - `opening-anchor` — grounds the viewer in a specific moment, place, or experience
    - `frame-set` — establishes the lens, perspective, or rules through which the story will be told
    - `setup-plant` — introduces an element that won't pay off until significantly later
    - `problem-statement` — names the core question or tension that drives the narrative
    - `stakes-raise` — quantifies, escalates, or makes the problem urgent
    - `context` — provides background necessary to understand what comes next
    - `expected-path` — shows the obvious approach, conventional wisdom, or first attempt
    - `dead-end` — a path that was tried and explicitly fails
    - `complication` — something doesn't add up, a contradiction surfaces, or a new obstacle appears
    - `method-shift` — a new approach, tool, lens, or framework is introduced
    - `discovery` — new information surfaces that changes understanding
    - `evidence` — data, example, anecdote, or proof that supports an adjacent beat
    - `reframe` — the problem or situation gets reinterpreted in light of new understanding
    - `mechanism` — explains HOW or WHY something works at a deeper level
    - `implication` — what this means going forward — the so-what
    - `escalation` — the scope expands beyond the original problem or the pressure increases
    - `pivot` — the story changes direction based on what was just established
    - `callback` — returns to an earlier beat with new meaning or payoff
    - `resolution` — the original question or tension gets answered
    """

    static let beatGuidance = """
    ### What a beat is (and is not)

    A beat is one **narrative construction move** — a deliberate structural choice the creator made to advance the argument.

    **A beat IS:**
    - A distinct move that changes the viewer's understanding, raises new tension, or resolves existing tension
    - Something that, if removed, would break the causal chain
    - Describable as a transferable pattern

    **A beat is NOT:**
    - An individual scene, location, or event (those are content that fills a beat)
    - A repetition of the same structural move with different content (three examples = one beat)
    - Texture, color, transitions, or supporting detail within a larger move

    ### Beat format

    For each beat: [One sentence describing THE MOVE] → [why this move appears here — what it sets up, proves, or resolves]

    ### Beat count guidance

    Rough calibration for a rambling-length piece:
    - Short rambling (under 5 min): 4-8 beats
    - Medium rambling (5-15 min): 7-14 beats
    - Long rambling (15+ min): 10-20 beats
    """

    static let spineJsonFormat = """
    ### OUTPUT FORMAT

    Return your response as valid JSON with this exact structure:
    ```json
    {
      "beats": [
        {
          "beatNumber": 1,
          "beatSentence": "Creator does X → this sets up Y",
          "function": "opening-anchor",
          "contentTag": "specific content from the rambling",
          "dependsOn": [],
          "creatorPatternNote": null
        }
      ],
      "throughline": "One paragraph (3-5 sentences) tracing the causal chain through each phase.",
      "phases": [
        {
          "phaseNumber": 1,
          "beatRange": [1, 5],
          "name": "Phase name",
          "definingTechnique": "What technique defines this phase"
        }
      ],
      "structuralSignatures": [
        {
          "name": "Pattern-name",
          "description": "1-2 sentence description with beat reference evidence."
        }
      ]
    }
    ```

    IMPORTANT: Return ONLY the JSON object. No markdown fences, no preamble, no commentary.
    """

    // MARK: - Gap Context Rendering (Pass 2)

    /// Renders gap analysis findings into a prompt section that instructs the model
    /// to treat supplemental rambling as structural expansion material.
    static func renderGapContext(_ findings: [GapFinding]) -> String {
        guard !findings.isEmpty else { return "" }

        let sorted = findings.sorted { $0.priority < $1.priority }

        var parts: [String] = []
        parts.append("""
        ## Gap Analysis Context

        A previous spine was built from the original rambling alone. Gap analysis identified the structural weaknesses listed below. The SUPPLEMENTAL RAMBLING section at the end of the raw rambling was recorded specifically to address these gaps.

        CRITICAL INSTRUCTIONS:
        - Each gap response in the supplemental rambling should be evaluated as a potential NEW beat — not just enrichment for existing beats.
        - The beat count from a first-pass spine is a FLOOR, not a target. This enriched material should produce MORE beats because it contains more structural content.
        - Actively look for these specific missing structural moves in the combined material.
        - Content from the supplemental rambling that maps to an identified gap should become its own beat with the function label the gap identified as missing.
        - Do NOT compress gap response content into existing beats' contentTags. If the gap analysis said a mechanism beat is missing and the supplemental rambling contains mechanism content, that is a NEW mechanism beat.

        ### Identified Gaps (ordered by priority)
        """)

        for (i, finding) in sorted.enumerated() {
            var entry = "\(i + 1). [\(finding.priority.rawValue)] [\(finding.type.rawValue)] \(finding.location)"
            entry += "\n   Missing: \(finding.whatsMissing)"
            entry += "\n   Why it matters: \(finding.whyItMatters)"
            if finding.action == .contentGap {
                entry += "\n   Action: New content needed — look for this in the supplemental rambling"
            } else if finding.action == .surface {
                entry += "\n   Action: Implicit content needs its own beat"
            } else {
                entry += "\n   Action: Existing content needs restructuring into a distinct beat"
            }
            entry += "\n   Question answered: \(finding.effectiveQuestion)"
            parts.append(entry)
        }

        parts.append("")
        return parts.joined(separator: "\n")
    }

    /// Additional rules injected when gap findings are present.
    static let gapAwareRules = """
    ### Gap-Aware Rules (Pass 2)

    - The supplemental rambling at the end addresses specific structural gaps identified by gap analysis. Treat it as STRUCTURAL EXPANSION material.
    - Content from gap responses that addresses an identified missing move MUST become a new beat — do not fold it into an existing beat's contentTag.
    - The expected beat count is HIGHER than a first-pass spine because there is more content with distinct structural roles.
    """

    // MARK: - Profile Rendering

    static func renderProfile(_ profile: CreatorNarrativeProfile) -> String {
        var parts: [String] = []
        parts.append("### Creator Narrative Profile: \(profile.channelName)")
        parts.append("")

        // Signatures
        parts.append("**Structural Signatures** (from \(profile.spineCount) videos):")
        for sig in profile.signatureAggregation.clusteredSignatures.prefix(15) {
            let pct = String(format: "%.0f", sig.frequencyPercent)
            parts.append("- \(sig.canonicalName) (\(pct)%): \(sig.description)")
        }
        parts.append("")

        // Phase architecture
        parts.append("**Typical Phase Architecture:**")
        parts.append(profile.phasePatterns.architectureNarrative)
        parts.append("")

        // Throughline patterns
        parts.append("**Throughline Patterns:**")
        parts.append(profile.throughlinePatterns.throughlineNarrative)
        parts.append("- Common openings: \(profile.throughlinePatterns.commonOpeningMoves.joined(separator: ", "))")
        parts.append("- Common closings: \(profile.throughlinePatterns.commonClosingMoves.joined(separator: ", "))")
        parts.append("")

        // Beat distribution (top functions)
        parts.append("**Top Function Labels (by frequency):**")
        for fn in profile.beatDistribution.globalDistribution.prefix(10) {
            let pct = String(format: "%.1f", fn.percent)
            parts.append("- \(fn.functionLabel): \(pct)%")
        }

        return parts.joined(separator: "\n")
    }

    private static func renderRepresentativeSpines(_ spines: [NarrativeSpine]) -> String {
        guard !spines.isEmpty else { return "" }
        var parts: [String] = []
        parts.append("### Representative Spines (\(spines.count) examples)")
        parts.append("")
        parts.append("Study these for recurring patterns — how this creator opens, escalates, pivots, proves, and closes. Your spine should be consistent with these in format, grain, and level of abstraction.")
        parts.append("")
        for (i, spine) in spines.enumerated() {
            parts.append("--- Example \(i + 1) ---")
            parts.append(spine.renderedText)
            parts.append("")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - PATH 1: Single Pass

    static func p1SinglePass(
        rawRambling: String,
        profile: CreatorNarrativeProfile,
        representativeSpines: [NarrativeSpine],
        gapFindings: [GapFinding] = []
    ) -> (system: String, user: String) {
        let gapContext = renderGapContext(gapFindings)
        let extraRules = gapFindings.isEmpty ? "" : "\n\n\(gapAwareRules)"

        let user = """
        You are building a **narrative spine** from a creator's raw rambling. The rambling is unstructured brain-dump audio that contains the story the creator wants to tell. Your job is to find that story and express it as a sequence of narrative beats.

        \(renderProfile(profile))

        \(renderRepresentativeSpines(representativeSpines))

        \(beatGuidance)

        \(functionTaxonomy)

        ### Rules

        1. Every beat must earn its place — if removing it doesn't break the causal chain, merge it.
        2. Dependencies are mandatory — every beat after Beat 1 must declare what it depends on.
        3. Do not invent content — every beat must trace to the rambling.
        4. Creator pattern notes are rare and specific (< 1/3 of beats).
        5. Consecutive instances of the same move are one beat.
        6. Structural contrasts (failure/success pair, spectacle/deflection) are one beat.\(extraRules)

        \(spineJsonFormat)

        \(gapContext)

        ---

        ## Raw Rambling

        \(rawRambling)
        """

        return (system: spineSystemPrompt, user: user)
    }

    // MARK: - SHARED: Content Inventory (used by P2, P3, P5)

    static func contentInventoryPrompt(rawRambling: String, gapFindings: [GapFinding] = []) -> (system: String, user: String) {
        let system = "You are a content analyst. Extract every distinct content point from the rambling below. No interpretation, no structure, no creator context — just inventory."

        let gapInstruction: String
        if !gapFindings.isEmpty {
            let gapSummary = gapFindings
                .sorted { $0.priority < $1.priority }
                .map { "- \($0.whatsMissing)" }
                .joined(separator: "\n")
            gapInstruction = """

            **IMPORTANT — Supplemental Content:** The rambling below includes a SUPPLEMENTAL RAMBLING section that was recorded to address specific structural gaps. Pay special attention to this section — it contains new content points that should be captured as distinct items, not merged with similar points from the original rambling. The gaps being addressed include:
            \(gapSummary)

            """
        } else {
            gapInstruction = ""
        }

        let user = """
        Read the raw rambling below and extract every distinct content point the creator communicated.

        **Rules:**
        - One sentence per point. Each point is a single, concrete thing the creator said.
        - Deduplicate — if the creator repeated themselves, list it once.
        - Strip meta-commentary ("so anyway", "I was thinking", "let me go back to") — extract the content, not the process.
        - No ordering, no categorization, no interpretation.
        - Number each point sequentially.
        \(gapInstruction)
        **Output format:**
        Return a numbered list. Nothing else.

        Example:
        1. The property has seen a 40% decline in deer population over three years.
        2. Trail camera data shows nocturnal movement patterns shifted after the neighboring property was logged.
        3. The state wildlife agency recommended a doe harvest moratorium.
        ...

        ---

        ## Raw Rambling

        \(rawRambling)
        """

        return (system: system, user: user)
    }

    // MARK: - PATH 2: Content-First

    static func p2SpineConstruction(
        contentInventory: String,
        profile: CreatorNarrativeProfile,
        representativeSpines: [NarrativeSpine],
        gapFindings: [GapFinding] = []
    ) -> (system: String, user: String) {
        let gapContext = renderGapContext(gapFindings)
        let extraRules = gapFindings.isEmpty ? "" : "\n\n\(gapAwareRules)"

        let user = """
        You are building a **narrative spine** from a clean content inventory (already extracted from the creator's raw rambling). The inventory tells you WHAT the creator wants to say. Your job is to find the story in that content and structure it as this creator would.

        \(renderProfile(profile))

        \(renderRepresentativeSpines(representativeSpines))

        \(beatGuidance)

        \(functionTaxonomy)

        ### Rules

        1. Every beat must earn its place — if removing it doesn't break the causal chain, merge it.
        2. Dependencies are mandatory — every beat after Beat 1 must declare what it depends on.
        3. Do not invent content — every beat must trace to the content inventory.
        4. Creator pattern notes are rare and specific (< 1/3 of beats).
        5. The content inventory was extracted without any creator context. Your job is to apply this creator's structural logic to organize it.\(extraRules)

        \(spineJsonFormat)

        \(gapContext)

        ---

        ## Content Inventory

        \(contentInventory)
        """

        return (system: spineSystemPrompt, user: user)
    }

    // MARK: - PATH 3: Four-Step Pipeline

    static func p3CausalThread(contentInventory: String) -> (system: String, user: String) {
        let system = "You are a narrative logic analyst. Find the causal chain in a set of content points. No creator context, no structural labels — just the story logic."

        let user = """
        Below is a numbered list of content points extracted from a creator's rambling. Find the causal chain — what story do these points add up to?

        **Output format:**
        Write a 5-10 line causal chain. Each line shows how one thing leads to the next:
        "A leads to B, which raises C, answered by D, which implies E"

        Do NOT use function labels, beat numbers, or structural terminology. Just trace the story logic in plain language.

        ---

        ## Content Inventory

        \(contentInventory)
        """

        return (system: system, user: user)
    }

    static func p3StructuralPlan(
        causalThread: String,
        contentInventory: String,
        profile: CreatorNarrativeProfile,
        gapFindings: [GapFinding] = []
    ) -> (system: String, user: String) {
        let system = "You are a narrative architect. Map a story's causal logic onto a specific creator's structural patterns."
        let gapContext = renderGapContext(gapFindings)

        let user = """
        You have:
        1. A causal thread — the pure story logic (no creator context)
        2. A content inventory — the raw content points
        3. A Creator Narrative Profile — this creator's documented structural patterns\(gapFindings.isEmpty ? "" : "\n4. Gap analysis results — structural weaknesses identified in a previous spine that the content inventory now addresses")

        Your job: Map this story onto this creator's structural logic. Which signatures apply? What phase architecture fits? Produce a structural plan.\(gapFindings.isEmpty ? "" : " The structural plan MUST include new beats for content that addresses the identified gaps.")

        \(renderProfile(profile))

        \(gapContext)

        **Output as JSON:**
        ```json
        {
          "phases": [
            {
              "phaseNumber": 1,
              "name": "Phase name",
              "coverageDescription": "What this phase covers",
              "proposedBeats": [
                {
                  "beatNumber": 1,
                  "function": "opening-anchor",
                  "contentAtoms": [1, 3],
                  "briefDescription": "What this beat does"
                }
              ]
            }
          ],
          "signatureApplications": [
            {
              "signatureName": "Dead-end-before-pivot",
              "appliedAtBeats": [4, 5],
              "reasoning": "Why this signature fits here"
            }
          ],
          "gaps": ["Content the rambling doesn't contain but the structure needs"]
        }
        ```

        \(functionTaxonomy)

        ---

        ## Causal Thread

        \(causalThread)

        ---

        ## Content Inventory

        \(contentInventory)
        """

        return (system: system, user: user)
    }

    static func p3FullSpine(
        structuralPlan: String,
        contentInventory: String,
        representativeSpines: [NarrativeSpine],
        gapFindings: [GapFinding] = []
    ) -> (system: String, user: String) {
        let gapContext = renderGapContext(gapFindings)
        let extraRules = gapFindings.isEmpty ? "" : "\n\n\(gapAwareRules)"

        let user = """
        You are writing the final narrative spine from a structural plan. The plan tells you the phase architecture, beat sequence, and content assignments. The representative spines show the format and grain.

        Your job: Flesh out the structural plan into a complete spine. Write beat descriptions as transferable moves. Fill in all fields.\(gapFindings.isEmpty ? "" : " The structural plan already accounts for gap analysis — ensure every proposed beat from the plan appears in the final spine.")

        \(renderRepresentativeSpines(representativeSpines))

        \(beatGuidance)\(extraRules)

        \(functionTaxonomy)

        \(spineJsonFormat)

        \(gapContext)

        ---

        ## Structural Plan

        \(structuralPlan)

        ---

        ## Content Inventory

        \(contentInventory)
        """

        return (system: spineSystemPrompt, user: user)
    }

    // MARK: - PATH 4: Dynamic Example Selection

    static func p4ExampleSelection(
        rawRambling: String,
        allThroughlines: [(videoId: String, throughline: String)],
        signatures: [ClusteredSignature],
        gapFindings: [GapFinding] = []
    ) -> (system: String, user: String) {
        let system = "You are an example selection specialist. Given a creator's rambling and their corpus of narrative spines, select the most relevant examples to guide spine construction."

        // Format throughlines compactly
        let throughlineList = allThroughlines.map { "[\($0.videoId)] \($0.throughline)" }.joined(separator: "\n\n")

        // Format signature names
        let signatureNames = signatures.prefix(15).map { "\($0.canonicalName) (\(String(format: "%.0f", $0.frequencyPercent))%)" }.joined(separator: ", ")

        let gapSelectionHint: String
        if !gapFindings.isEmpty {
            let missingMoves = Set(gapFindings.map(\.whatsMissing)).joined(separator: ", ")
            gapSelectionHint = """

            **Gap-aware selection:** This rambling includes supplemental content addressing structural gaps. The missing structural moves include: \(missingMoves). Prefer examples that demonstrate these moves well.

            """
        } else {
            gapSelectionHint = ""
        }

        let user = """
        Read the raw rambling below and select 8-12 corpus spines whose content type and structural pattern most closely match what this rambling is about.

        **Creator's known structural signatures:** \(signatureNames)

        **Selection criteria:**
        - Content type match: Does this example spine cover a similar kind of topic or situation?
        - Structural pattern match: Would the structural approach from this example work for the rambling's content?
        - Do NOT just pick the most recent or most popular — pick the most structurally relevant.
        \(gapSelectionHint)
        **Output as JSON:**
        ```json
        {
          "selectedSpines": [
            {
              "videoId": "abc123",
              "reason": "One sentence explaining why this spine is relevant"
            }
          ]
        }
        ```

        Return ONLY the JSON. No markdown fences, no preamble.

        ---

        ## Corpus Spine Throughlines (\(allThroughlines.count) total)

        \(throughlineList)

        ---

        ## Raw Rambling

        \(rawRambling)
        """

        return (system: system, user: user)
    }

    static func p4SpineConstruction(
        rawRambling: String,
        profile: CreatorNarrativeProfile,
        selectedSpines: [NarrativeSpine],
        gapFindings: [GapFinding] = []
    ) -> (system: String, user: String) {
        let gapContext = renderGapContext(gapFindings)
        let extraRules = gapFindings.isEmpty ? "" : "\n5. \(gapAwareRules)"

        let user = """
        You are building a **narrative spine** from a creator's raw rambling. The examples below were dynamically selected as the most relevant structural patterns from the creator's corpus for this specific rambling.

        \(renderProfile(profile))

        ### Dynamically Selected Examples (\(selectedSpines.count) spines)

        These were chosen because their content type and structural pattern closely match this rambling. Study them carefully — they represent the specific structural approaches most relevant to the story in this rambling.

        \(selectedSpines.enumerated().map { i, s in "--- Example \(i + 1) ---\n\(s.renderedText)" }.joined(separator: "\n\n"))

        \(beatGuidance)

        \(functionTaxonomy)

        ### Rules

        1. Every beat must earn its place — if removing it doesn't break the causal chain, merge it.
        2. Dependencies are mandatory — every beat after Beat 1 must declare what it depends on.
        3. Do not invent content — every beat must trace to the rambling.
        4. Creator pattern notes are rare and specific (< 1/3 of beats).\(extraRules)

        \(spineJsonFormat)

        \(gapContext)

        ---

        ## Raw Rambling

        \(rawRambling)
        """

        return (system: spineSystemPrompt, user: user)
    }

    // MARK: - PATH 5: Dynamic + Content-First

    static func p5ExampleSelection(
        contentInventory: String,
        allThroughlines: [(videoId: String, throughline: String)],
        signatures: [ClusteredSignature],
        gapFindings: [GapFinding] = []
    ) -> (system: String, user: String) {
        let system = "You are an example selection specialist. Given a clean content inventory and the creator's corpus of narrative spines, select the most relevant examples to guide spine construction."

        let throughlineList = allThroughlines.map { "[\($0.videoId)] \($0.throughline)" }.joined(separator: "\n\n")
        let signatureNames = signatures.prefix(15).map { "\($0.canonicalName) (\(String(format: "%.0f", $0.frequencyPercent))%)" }.joined(separator: ", ")

        let gapSelectionHint: String
        if !gapFindings.isEmpty {
            let missingMoves = Set(gapFindings.map(\.whatsMissing)).joined(separator: ", ")
            gapSelectionHint = """

            **Gap-aware selection:** This content inventory includes supplemental content addressing structural gaps. The missing structural moves include: \(missingMoves). Prefer examples that demonstrate these moves well.

            """
        } else {
            gapSelectionHint = ""
        }

        let user = """
        Read the content inventory below (already extracted from raw rambling) and select 8-12 corpus spines whose content type and structural pattern most closely match this content.

        **Creator's known structural signatures:** \(signatureNames)

        **Selection criteria:**
        - Content type match: Does this example spine cover a similar kind of topic or situation?
        - Structural pattern match: Would the structural approach from this example work for this content?
        \(gapSelectionHint)
        **Output as JSON:**
        ```json
        {
          "selectedSpines": [
            {
              "videoId": "abc123",
              "reason": "One sentence explaining why this spine is relevant"
            }
          ]
        }
        ```

        Return ONLY the JSON. No markdown fences, no preamble.

        ---

        ## Corpus Spine Throughlines (\(allThroughlines.count) total)

        \(throughlineList)

        ---

        ## Content Inventory

        \(contentInventory)
        """

        return (system: system, user: user)
    }

    static func p5SpineConstruction(
        contentInventory: String,
        profile: CreatorNarrativeProfile,
        selectedSpines: [NarrativeSpine],
        gapFindings: [GapFinding] = []
    ) -> (system: String, user: String) {
        let gapContext = renderGapContext(gapFindings)
        let extraRules = gapFindings.isEmpty ? "" : "\n5. \(gapAwareRules)"

        let user = """
        You are building a **narrative spine** from a clean content inventory. The inventory was extracted from raw rambling without any creator context. The examples below were dynamically selected as the most relevant structural patterns from the creator's corpus.

        \(renderProfile(profile))

        ### Dynamically Selected Examples (\(selectedSpines.count) spines)

        These were chosen because their content type and structural pattern closely match this content. Study them carefully.

        \(selectedSpines.enumerated().map { i, s in "--- Example \(i + 1) ---\n\(s.renderedText)" }.joined(separator: "\n\n"))

        \(beatGuidance)

        \(functionTaxonomy)

        ### Rules

        1. Every beat must earn its place — if removing it doesn't break the causal chain, merge it.
        2. Dependencies are mandatory — every beat after Beat 1 must declare what it depends on.
        3. Do not invent content — every beat must trace to the content inventory.
        4. Creator pattern notes are rare and specific (< 1/3 of beats).\(extraRules)

        \(spineJsonFormat)

        \(gapContext)

        ---

        ## Content Inventory

        \(contentInventory)
        """

        return (system: spineSystemPrompt, user: user)
    }

    // MARK: - Example Selection Response Parsing

    struct ExampleSelectionResponse: Codable {
        let selectedSpines: [SelectedSpine]

        struct SelectedSpine: Codable {
            let videoId: String
            let reason: String
        }
    }

    /// Parse example selection response to extract videoIds.
    static func parseExampleSelection(_ text: String) -> [String] {
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        guard let data = cleaned.data(using: .utf8) else { return [] }

        if let response = try? JSONDecoder().decode(ExampleSelectionResponse.self, from: data) {
            return response.selectedSpines.map(\.videoId)
        }

        // Fallback: extract videoId-like strings with regex
        let pattern = #""videoId"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: cleaned) else { return nil }
            return String(cleaned[range])
        }
    }

    // MARK: - V-Path Shared Preprocessing Prompts

    /// Supplemental inventory extraction prompt — extracts content atoms from cleaned supplemental text.
    /// The cleaned text has already been stripped of Q/A framing and meta-statements by Swift.
    static func supplementalInventoryPrompt(cleanedSupplemental: String) -> (system: String, user: String) {
        let system = "You are a content analyst. Extract every distinct content point from the supplemental recording below. No interpretation, no structure, no creator context — just inventory."

        let user = """
        Read the supplemental recording below. These are NEW content points the creator recorded to expand on specific topics identified as needing more depth.

        **Rules:**
        - One sentence per point. Each point is a single, concrete thing the creator said.
        - Extract each as a distinct content atom even if similar ideas appeared in other recordings. Do NOT collapse or merge similar-sounding points — each represents the creator deliberately going deeper on a topic.
        - Strip meta-commentary ("so anyway", "I was thinking", "let me go back to") — extract the content, not the process.
        - Number each point sequentially.

        **Output format:**
        Return a numbered list. Nothing else.

        Example:
        1. The feedback loop self-reinforces because each new subscriber increases recommendation surface area.
        2. Growth rate data from Q3 showed a 4x acceleration compared to Q1 despite identical content volume.
        3. The creator noticed the pattern only after switching from weekly to daily upload cadence.
        ...

        ---

        ## Supplemental Recording

        \(cleanedSupplemental)
        """

        return (system: system, user: user)
    }

    /// Renders positional gap metadata for V6-V10 structural planners.
    /// References [SUP]-tagged atoms by number range so the planner knows which atoms are gap content
    /// and where they belong in the narrative.
    static func renderPositionalGapMetadata(
        gapFindings: [GapFinding],
        supplementalRange: ClosedRange<Int>
    ) -> String {
        guard !gapFindings.isEmpty else { return "" }

        let sorted = gapFindings
            .filter { $0.refinementStatus != .resolved }
            .sorted { $0.priority < $1.priority }
        guard !sorted.isEmpty else { return "" }

        // Distribute supplemental atoms approximately across gap positions
        let totalSupplemental = supplementalRange.count
        let atomsPerGap = max(1, totalSupplemental / sorted.count)
        var currentAtom = supplementalRange.lowerBound

        var lines: [String] = []
        lines.append("### Structural Gap Positions")
        lines.append("Supplemental atoms are tagged [SUP] in the inventory (atoms \(supplementalRange.lowerBound)-\(supplementalRange.upperBound)).")
        lines.append("Place these at the indicated narrative positions:")
        lines.append("")

        for (i, finding) in sorted.enumerated() {
            let endAtom: Int
            if i == sorted.count - 1 {
                endAtom = supplementalRange.upperBound
            } else {
                endAtom = min(currentAtom + atomsPerGap - 1, supplementalRange.upperBound)
            }
            let atomRange = currentAtom == endAtom ? "Atom \(currentAtom)" : "Atoms \(currentAtom)-\(endAtom)"
            lines.append("\(i + 1). \(finding.location) | Role: \(finding.type.rawValue) | \(atomRange) | \(finding.whatsMissing)")
            currentAtom = endAtom + 1
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Stage 3: Gap coverage validation — post-hoc check that HIGH-priority gaps produced beats.
    static func gapCoverageValidationPrompt(
        spine: NarrativeSpine,
        highPriorityFindings: [GapFinding]
    ) -> (system: String, user: String) {
        let system = "You are a quality assurance analyst. Check whether a narrative spine adequately covers identified structural gaps. Return valid JSON only."

        // Render the spine beats compactly
        let beatsText = spine.beats.map { beat in
            "Beat \(beat.beatNumber) [\(beat.function)]: \(beat.beatSentence) | Content: \"\(beat.contentTag)\""
        }.joined(separator: "\n")

        // Render the gaps to check
        let gapsText = highPriorityFindings.enumerated().map { i, finding in
            "\(i + 1). [ID: \(finding.id.uuidString)] \(finding.location) — \(finding.whatsMissing) (\(finding.type.rawValue))"
        }.joined(separator: "\n")

        let user = """
        Below is a narrative spine and a list of HIGH-priority structural gaps that were identified in a previous analysis. For each gap, determine whether the spine now contains a beat that adequately addresses it.

        A gap is "covered" if there is a beat whose function and content clearly address what was missing. A gap is "uncovered" if no beat in the spine addresses the identified gap.

        ### Spine (\(spine.beats.count) beats)

        \(beatsText)

        ### HIGH-Priority Gaps to Validate

        \(gapsText)

        ### Output Format

        Return JSON:
        ```json
        {
          "covered": [
            { "gapId": "uuid-string", "coveredByBeat": 5, "reason": "Brief explanation" }
          ],
          "uncovered": [
            { "gapId": "uuid-string", "reason": "Brief explanation of why no beat covers this" }
          ],
          "summary": "One paragraph summarizing overall gap coverage"
        }
        ```

        Return ONLY the JSON. No markdown fences, no preamble.
        """

        return (system: system, user: user)
    }

    /// Parse gap coverage validation response.
    static func parseGapCoverageValidation(_ text: String, allGapIds: [UUID]) -> GapCoverageResult {
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        struct CoverageResponse: Codable {
            struct CoveredEntry: Codable { let gapId: String; let coveredByBeat: Int?; let reason: String? }
            struct UncoveredEntry: Codable { let gapId: String; let reason: String? }
            let covered: [CoveredEntry]?
            let uncovered: [UncoveredEntry]?
            let summary: String?
        }

        guard let data = cleaned.data(using: .utf8),
              let response = try? JSONDecoder().decode(CoverageResponse.self, from: data) else {
            return GapCoverageResult(
                coveredGapIds: [],
                uncoveredGapIds: allGapIds,
                coverageSummary: "Failed to parse gap coverage validation response."
            )
        }

        let coveredIds = (response.covered ?? []).compactMap { UUID(uuidString: $0.gapId) }
        let uncoveredIds = (response.uncovered ?? []).compactMap { UUID(uuidString: $0.gapId) }
        let summary = response.summary ?? "No summary provided."

        return GapCoverageResult(
            coveredGapIds: coveredIds,
            uncoveredGapIds: uncoveredIds,
            coverageSummary: summary
        )
    }
}
