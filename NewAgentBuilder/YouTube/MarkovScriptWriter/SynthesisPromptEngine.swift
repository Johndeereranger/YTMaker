//
//  SynthesisPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/6/26.
//
//  Builds prompts for the two-pass synthesis pipeline.
//  This is a first-class artifact — expect heavy iteration.
//

import Foundation

struct SynthesisPromptEngine {

    // Bump this when prompts change. Stored on every SynthesizedScript for history tracking.
    static let PROMPT_VERSION = "v1.1"

    // MARK: - Pass 1: Section Synthesis

    struct Pass1Input {
        let moveType: RhetoricalMoveType
        let arcMoveSequence: [RhetoricalMoveType]   // Full ordered move list
        let currentPositionIndex: Int                // Which position we're writing

        let scriptSoFar: String                      // Concatenated previous sections
        let priorSummaries: [String]                 // One-sentence summaries of prior sections
        let priorCallbacks: [String]                 // Setups/callbacks from earlier sections

        let rawRambling: String                      // User's actual spoken words for this section
        let gistADescription: String                 // GistA: subject + premise + frame
        let gistBDescription: String                 // GistB: subject + premise + frame
        let frameLabel: String                       // GistFrame label

        let creatorSections: [CreatorSectionBundle]  // 12-15 examples with preceding context
        let transitionBridge: TransitionBridgeBundle? // Move-pair examples (sections 2+)
    }

    struct CreatorSectionBundle {
        let fullChunkText: String
        let videoTitle: String
        let precedingChunkText: String?              // Preceding chunk from same video
    }

    struct TransitionBridgeBundle {
        let previousMoveType: RhetoricalMoveType
        let currentMoveType: RhetoricalMoveType
        let examples: [(tailText: String, headText: String, videoTitle: String)]
        let isFallback: Bool
        let fallbackType: String?
    }

    static func buildPass1Prompt(input: Pass1Input) -> (system: String, user: String) {

        let system = buildPass1SystemPrompt()

        // --- Arc Position ---
        let totalPositions = input.arcMoveSequence.count
        let arcStr = input.arcMoveSequence.enumerated().map { idx, move in
            let marker = idx == input.currentPositionIndex ? "▶︎" : " "
            return "\(marker) \(idx + 1). \(move.displayName)"
        }.joined(separator: "\n")
        
        let opening = """
        TASK
        You are ghostwriting one section of a YouTube script. Your job 
        is to transform the user's raw spoken rambling into polished 
        script text that reads as if a specific creator wrote it. 

        You are NOT summarizing the rambling. You are NOT writing in 
        your own voice. You are pattern-matching against real examples 
        of this creator executing this exact type of section, then 
        producing new text that uses the same structural and stylistic 
        mechanics on the user's content.

        The creator's real script sections are provided below as your 
        primary reference. Your output should be indistinguishable from 
        those examples in voice, sentence structure, pacing, and 
        technique — but covering the user's topic, not the creator's.
        
        """

        // --- Move Contract ---
        let moveContract = """
        MOVE CONTRACT
        Move: \(input.moveType.displayName)
        Definition: \(input.moveType.rhetoricalDefinition)
        Example: "\(input.moveType.examplePhrase)"
        Position: Section \(input.currentPositionIndex + 1) of \(totalPositions)
        """

        // --- Arc ---
        let arcSection = """
        ARC POSITION
        Full move sequence for this script (▶︎ marks current section):
        \(arcStr)
        """

        // --- Script So Far ---
        let scriptSoFarSection: String
        if input.scriptSoFar.isEmpty {
            scriptSoFarSection = """
            SCRIPT SO FAR
            (This is the first section — no prior script.)
            """
        } else {
            let summaryStr = input.priorSummaries.enumerated()
                .map { "  Section \($0.offset + 1): \($0.element)" }
                .joined(separator: "\n")
            scriptSoFarSection = """
            SCRIPT SO FAR
            Prior section summaries:
            \(summaryStr)

            Full text written so far:
            ---
            \(input.scriptSoFar)
            ---
            """
        }

        // --- Callbacks ---
        let callbackSection: String
        if input.priorCallbacks.isEmpty {
            callbackSection = ""
        } else {
            let cbStr = input.priorCallbacks.map { "  • \($0)" }.joined(separator: "\n")
            callbackSection = """

            PRIOR SETUPS & CALLBACKS
            These setups were established in earlier sections. Where natural, reference or pay them off in this section:
            \(cbStr)
            """
        }

        // --- Raw Rambling ---
        let ramblingSection = """
        RAW RAMBLING (user's actual words for this section)
        ---
        \(input.rawRambling)
        ---
        """

        // --- Rambling Gist ---
        let gistSection = """
        RAMBLING GIST (semantic anchor — what the rambling is about)
        Frame: \(input.frameLabel)
        GistA: \(input.gistADescription)
        GistB: \(input.gistBDescription)
        """

        // --- Creator Sections ---
        var creatorLines: [String] = []
        for (idx, bundle) in input.creatorSections.enumerated() {
            var entry = "Example \(idx + 1) [\(bundle.videoTitle)]:\n\(bundle.fullChunkText)"
            if let preceding = bundle.precedingChunkText {
                entry = "What came before (context):\n\(preceding)\n\nThen the creator wrote (\(input.moveType.displayName)):\n\(bundle.fullChunkText)"
            }
            creatorLines.append(entry)
        }
        let creatorSection = """
        CREATOR SECTIONS — \(input.moveType.displayName.uppercased())
        These are real examples of this creator executing this exact rhetorical move. Study how they open it, develop it, and land it:

        \(creatorLines.joined(separator: "\n\n---\n\n"))
        """

        // --- Transition Bridge ---
        let transitionSection: String
        if let bridge = input.transitionBridge {
            let label = bridge.isFallback ? " (approximate — \(bridge.fallbackType ?? "fallback"))" : ""
            var bridgeLines: [String] = []
            for (idx, ex) in bridge.examples.enumerated() {
                bridgeLines.append("""
                Transition Example \(idx + 1) [\(ex.videoTitle)]\(label):
                End of \(bridge.previousMoveType.displayName):
                \(ex.tailText.suffix(500))

                Start of \(bridge.currentMoveType.displayName):
                \(String(ex.headText.prefix(500)))
                """)
            }
            transitionSection = """

            TRANSITION BRIDGE (\(bridge.previousMoveType.displayName) → \(bridge.currentMoveType.displayName))
            These show how the creator moves from the preceding move type into this one:

            \(bridgeLines.joined(separator: "\n\n---\n\n"))
            """
        } else {
            transitionSection = ""
        }
        
        let generationFormat = """
        STAGE 1: PATTERN EXTRACTION (think step-by-step in <analysis> tags)

        Before writing anything, analyze the creator examples above and identify:

        1. ENTRY POINT: How does the creator begin this move type?
           - What tense? (present/past/imperative)
           - What's the first sensory channel? (visual/auditory/spatial/dialogue)
           - Does the section start mid-action, mid-thought, or with scene-setting?
           - How many words before the audience understands WHERE they are?

        2. SENTENCE MECHANICS:
           - Average sentence length in the examples (short/medium/long)
           - Ratio of fragments to complete sentences
           - How often does the creator use questions?
           - How often does the creator talk TO the audience vs. narrate?

        3. LANDING PATTERN: How does the creator END this move type?
           - Does it resolve or leave tension open?
           - Does it end on action, dialogue, detail, or reflection?
           - Does it signal what's coming next or just stop?

        4. WHAT THE CREATOR NEVER DOES in this move type:
           - List specific patterns you do NOT see in any example

        Write your analysis inside <analysis> tags. Be specific — cite 
        phrases from the examples.

        STAGE 2: GENERATION

        Using your analysis above, write the section.

        COMPLIANCE RULES:
        - Your first sentence must use the ENTRY POINT pattern you 
          identified. If you identified present-tense visual/spatial 
          immersion, your first sentence must place the audience in a 
          physical location with sensory detail. Not a phone call. Not 
          "I got asked to." The audience should SEE something.

        - Every sentence must pass your SENTENCE MECHANICS profile. 
          If you identified short sentences with fragments and 
          conversational asides, do not write in flowing summary prose.

        - Your final sentence must match the LANDING PATTERN. If you 
          identified "ends on a concrete detail with implicit tension 
          and doesn't resolve," then do not end with a question or a 
          thesis. End on an image or fact that dangles.

        - Cross-check against your NEVER DOES list before finalizing. 
          If any sentence matches a pattern from that list, rewrite it.

        ADDITIONAL CONSTRAINTS:
        - Do not summarize the rambling. PLACE the audience inside the 
          moment. If the rambling says "I got called to fly a property," 
          the script should open with the audience ON the property or 
          IN the air, not hearing about a phone call.
          
        - If the rambling lacks sensory detail, invent plausible 
          details consistent with the scenario (terrain, weather, 
          sounds, time of day). Flag any invented details in your 
          summary field with [INVENTED].

        - The raw rambling mentions: property, deer, declining numbers, 
          tree stand. These are CONTENT ANCHORS. All must appear in 
          your output. But they must appear INSIDE an immersive scene, 
          not as a summary list of facts.
        """

        // --- Output Format ---
        let outputFormat = """

        OUTPUT FORMAT
        After your <analysis>, respond with valid JSON in this exact structure:
        {
          "writtenText": "The full section text you've written...",
          "summary": "One sentence describing what this section established.",
          "callbacks": ["Any setups or callbacks introduced that later sections should reference"],
          "endingNote": "One sentence describing how this section lands and what it leaves open for the next section."
        }
        """

        let user = [opening,
            moveContract,
            arcSection,
            scriptSoFarSection,
            callbackSection,
            ramblingSection,
            gistSection,
            creatorSection,
            transitionSection,
            generationFormat,
            outputFormat
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")

        return (system: system, user: user)
    }

    private static func buildPass1SystemPrompt() -> String {
        return """
        You are a script writer synthesizing a video script section by section.

        For each section you receive:
        1. A MOVE CONTRACT — the rhetorical job this section must execute. This is the frame. Non-negotiable.
        2. RAW RAMBLING — the user's actual spoken words. This is the substance. Their ideas, stories, and data are what this section communicates.
        3. CREATOR SECTIONS — real examples of this creator executing this exact move type. These are the execution model. Study how the creator opens, develops, and lands this move. Write using that pattern.
        4. SCRIPT SO FAR — everything written in previous sections. This is the continuity constraint. Don't contradict, repeat, or ignore what's already been established.

        Rules:
        - Transform the user's rambling into polished script text that executes the move contract.
        - Preserve ALL of the user's ideas, claims, stories, and data. Do not drop substance.
        - Match the creator's execution pattern — how they structure sentences, pace information, build momentum for this specific move type.
        - Voice emerges from the creator examples. Do not invent a voice. Let pattern matching do the work.
        - When prior callbacks/setups are listed, weave references to them naturally where they fit. Do not force them.
        - The endingNote should describe how this section concludes and what it opens for the next section.
        - First write your pattern analysis inside <analysis> tags, then respond with valid JSON. No markdown code fences.
        """
    }

    // MARK: - Pass 2: Transition Smoothing

    struct Pass2Input {
        let sections: [SynthesisSection]             // All Pass 1 sections
        let moveSequence: [RhetoricalMoveType]       // Full move list
        let transitionExamples: [SeamTransition]     // Per-seam transition examples
    }

    struct SeamTransition {
        let seamIndex: Int                           // Between section N and N+1
        let moveA: RhetoricalMoveType
        let moveB: RhetoricalMoveType
        let endingNoteA: String                      // How section A lands
        let examples: [(tailText: String, headText: String, videoTitle: String)]
        let isFallback: Bool
        let fallbackType: String?
    }

    static func buildPass2Prompt(input: Pass2Input) -> (system: String, user: String) {

        let system = buildPass2SystemPrompt()

        // --- Build full draft with seam markers ---
        var draftParts: [String] = []
        for (idx, section) in input.sections.enumerated() {
            draftParts.append(section.writtenText)

            // Insert seam marker between sections
            if idx < input.sections.count - 1 {
                let seamIdx = idx
                if let seam = input.transitionExamples.first(where: { $0.seamIndex == seamIdx }) {
                    let endingNote = section.endingNote.isEmpty ? "(no ending note)" : section.endingNote
                    draftParts.append("""
                    [SEAM \(seamIdx + 1): \(seam.moveA.displayName) → \(seam.moveB.displayName)]
                    Ending note: \(endingNote)
                    """)
                }
            }
        }
        let fullDraft = draftParts.joined(separator: "\n\n")

        // --- Move Sequence ---
        let moveStr = input.moveSequence.enumerated()
            .map { "\($0.offset + 1). \($0.element.displayName)" }
            .joined(separator: "\n")
        let moveSection = """
        MOVE SEQUENCE
        \(moveStr)
        """

        // --- Transition Examples Per Seam ---
        var seamSections: [String] = []
        for seam in input.transitionExamples {
            let label = seam.isFallback ? " (approximate — \(seam.fallbackType ?? "fallback"))" : ""
            if seam.examples.isEmpty {
                seamSections.append("""
                SEAM \(seam.seamIndex + 1): \(seam.moveA.displayName) → \(seam.moveB.displayName)
                No transition examples available for this move pair. Smooth this seam using your best judgment based on the ending note and the content of both sections.
                """)
            } else {
                var exLines: [String] = []
                for (i, ex) in seam.examples.prefix(3).enumerated() {
                    exLines.append("""
                    Example \(i + 1) [\(ex.videoTitle)]\(label):
                    ...end of \(seam.moveA.displayName): \(String(ex.tailText.suffix(300)))
                    ...start of \(seam.moveB.displayName): \(String(ex.headText.prefix(300)))
                    """)
                }
                seamSections.append("""
                SEAM \(seam.seamIndex + 1): \(seam.moveA.displayName) → \(seam.moveB.displayName)
                Creator transition examples:
                \(exLines.joined(separator: "\n\n"))
                """)
            }
        }

        let transitionsBlock = seamSections.joined(separator: "\n\n---\n\n")

        let user = """
        FULL DRAFT
        The following script was written section by section. Seam markers show where sections meet.

        ---
        \(fullDraft)
        ---

        \(moveSection)

        TRANSITION EXAMPLES
        For each seam, here's how this creator actually bridges these move types:

        \(transitionsBlock)

        OUTPUT
        Return the complete script with smoothed transitions. Do not rewrite section bodies — only modify text at the seams to create natural bridges. Maintain the creator's voice through the joins. Return ONLY the script text — no JSON, no markers, no commentary.
        """

        return (system: system, user: user)
    }

    private static func buildPass2SystemPrompt() -> String {
        return """
        You are a line editor working exclusively on seams between script sections.

        Your job:
        - Smooth transitions between sections
        - Ensure callbacks and setups from earlier sections are honored at boundaries
        - Tighten pacing at section boundaries
        - Maintain the creator's voice through the joins

        Your constraints:
        - Do NOT rewrite section bodies — only modify text near the boundaries
        - Do NOT change the rhetorical move order
        - Do NOT add new claims, evidence, or data
        - Do NOT remove content
        - Each seam is explicitly marked with [SEAM n: moveA → moveB]
        - Study the creator transition examples to understand how this creator bridges these specific move types
        - Return ONLY the complete script text — no JSON wrapping, no markers, no commentary
        """
    }
}
