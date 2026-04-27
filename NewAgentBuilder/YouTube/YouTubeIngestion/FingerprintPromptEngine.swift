//
//  FingerprintPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/14/26.
//

import Foundation

/// Builds LLM prompts for fingerprint generation.
/// Each FingerprintPromptType dispatches to its own system prompt.
/// User prompt assembles ALL raw transcript examples for a specific slot.
///
/// Adding a new prompt type:
/// 1. Add a case to FingerprintPromptType enum
/// 2. Add a case to the switch in buildSystemPrompt(for:)
/// 3. Write the private method returning the system prompt text
/// 4. Add a case to buildUserPrompt dispatch if custom framing needed
/// 5. Add a case to defaultParams(for:) if custom LLM params needed
struct FingerprintPromptEngine {

    // MARK: - System Prompt (dispatches by type)

    static func buildSystemPrompt(for promptType: FingerprintPromptType) -> String {
        switch promptType {
        case .comprehensive:         return comprehensiveSystemPrompt()
        case .layer3Discovery:       return layer3DiscoverySystemPrompt()
        case .narrativeLens:         return narrativeLensSystemPrompt()
        case .registerAnalysis:      return registerAnalysisSystemPrompt()
        case .sentenceConstruction:  return sentenceConstructionSystemPrompt()
        case .mechanicalFingerprint: return mechanicalFingerprintSystemPrompt()
        }
    }

    // MARK: - User Prompt (dispatches by type)

    static func buildUserPrompt(
        slotKey: FingerprintSlotKey,
        promptType: FingerprintPromptType,
        creatorName: String,
        sampleTexts: [String],
        videoTitles: [String]
    ) -> String {
        switch promptType {
        case .comprehensive:
            return comprehensiveUserPrompt(slotKey: slotKey, creatorName: creatorName, sampleTexts: sampleTexts, videoTitles: videoTitles)
        case .layer3Discovery:
            return layer3DiscoveryUserPrompt(slotKey: slotKey, creatorName: creatorName, sampleTexts: sampleTexts, videoTitles: videoTitles)
        case .narrativeLens:
            return narrativeLensUserPrompt(slotKey: slotKey, creatorName: creatorName, sampleTexts: sampleTexts, videoTitles: videoTitles)
        case .registerAnalysis:
            return registerAnalysisUserPrompt(slotKey: slotKey, creatorName: creatorName, sampleTexts: sampleTexts, videoTitles: videoTitles)
        case .sentenceConstruction:
            return sentenceConstructionUserPrompt(slotKey: slotKey, creatorName: creatorName, sampleTexts: sampleTexts, videoTitles: videoTitles)
        case .mechanicalFingerprint:
            return mechanicalFingerprintUserPrompt(slotKey: slotKey, creatorName: creatorName, sampleTexts: sampleTexts, videoTitles: videoTitles)
        }
    }

    // MARK: - LLM Parameters (may vary by type)

    static func defaultParams(for promptType: FingerprintPromptType) -> [String: Any] {
        switch promptType {
        case .comprehensive:         return ["temperature": 0.3, "max_tokens": 8000]
        case .layer3Discovery:       return ["temperature": 0.3, "max_tokens": 12000]
        case .narrativeLens:         return ["temperature": 0.2, "max_tokens": 4000]
        case .registerAnalysis:      return ["temperature": 0.3, "max_tokens": 10000]
        case .sentenceConstruction:  return ["temperature": 0.2, "max_tokens": 8000]
        case .mechanicalFingerprint: return ["temperature": 0.1, "max_tokens": 8000]
        }
    }

    // MARK: - Shared Helpers

    /// Builds the examples block used by all user prompts
    private static func buildExamplesBlock(sampleTexts: [String], videoTitles: [String]) -> String {
        var block = ""
        for (i, text) in sampleTexts.enumerated() {
            let title = i < videoTitles.count ? videoTitles[i] : "Video \(i + 1)"
            block += "### Example \(i + 1): \(title)\n"
            block += "\(text)\n\n"
            block += "---\n\n"
        }
        return block
    }

    /// Builds the standard context header used by most user prompts
    private static func buildContextHeader(
        slotKey: FingerprintSlotKey,
        creatorName: String,
        sampleCount: Int
    ) -> String {
        """
        ## CREATOR
        \(creatorName)

        ## RHETORICAL MOVE
        \(slotKey.moveLabel.displayName) (\(slotKey.moveLabel.rawValue))
        Category: \(slotKey.moveLabel.category.rawValue)

        ## SCRIPT POSITION
        \(slotKey.position.displayName)

        """
    }

    // MARK: - Per-Type User Prompts

    private static func comprehensiveUserPrompt(
        slotKey: FingerprintSlotKey,
        creatorName: String,
        sampleTexts: [String],
        videoTitles: [String]
    ) -> String {
        var prompt = buildContextHeader(slotKey: slotKey, creatorName: creatorName, sampleCount: sampleTexts.count)
        prompt += """
        ## ANALYSIS FOCUS
        Comprehensive

        ## RAW TRANSCRIPT EXCERPTS (\(sampleTexts.count) total)

        Below are the actual transcript sections from this creator's videos. These are the creator's own words — analyze THESE, not summaries or descriptions of them.

        """
        prompt += buildExamplesBlock(sampleTexts: sampleTexts, videoTitles: videoTitles)
        prompt += """
        Produce the fingerprint for how \(creatorName) characteristically executes "\(slotKey.moveLabel.displayName)" when it appears in \(slotKey.position.displayName.lowercased()) of their scripts. Analyze all \(sampleTexts.count) transcript excerpts above. Ground every claim in direct quotes from these transcripts.
        """
        return prompt
    }

    private static func layer3DiscoveryUserPrompt(
        slotKey: FingerprintSlotKey,
        creatorName: String,
        sampleTexts: [String],
        videoTitles: [String]
    ) -> String {
        var prompt = buildContextHeader(slotKey: slotKey, creatorName: creatorName, sampleCount: sampleTexts.count)
        prompt += """
        You are analyzing \(sampleTexts.count) examples of the same rhetorical move (\(slotKey.moveLabel.displayName)) from the same position (\(slotKey.position.displayName)) in this creator's video corpus. All \(sampleTexts.count) examples serve the same rhetorical purpose and all have been annotated with slot-level sentence texture.

        Your task is to discover what ELSE varies across these examples beyond purpose and texture.

        ## RAW TRANSCRIPT EXCERPTS (\(sampleTexts.count) total)

        """
        prompt += buildExamplesBlock(sampleTexts: sampleTexts, videoTitles: videoTitles)
        prompt += """
        Execute all 5 phases of the Layer 3 Discovery analysis on the \(sampleTexts.count) examples above. Ground every finding in direct quotes.
        """
        return prompt
    }

    private static func narrativeLensUserPrompt(
        slotKey: FingerprintSlotKey,
        creatorName: String,
        sampleTexts: [String],
        videoTitles: [String]
    ) -> String {
        var prompt = buildContextHeader(slotKey: slotKey, creatorName: creatorName, sampleCount: sampleTexts.count)
        prompt += """
        Annotate each of the following \(sampleTexts.count) video script sections with the 9 Narrative Lens fields. These are all "\(slotKey.moveLabel.displayName)" sections from \(slotKey.position.displayName.lowercased()) in the script.

        ## RAW TRANSCRIPT EXCERPTS (\(sampleTexts.count) total)

        """
        prompt += buildExamplesBlock(sampleTexts: sampleTexts, videoTitles: videoTitles)
        prompt += """
        After annotating each example individually, produce a SUMMARY showing the dominant value for each of the 9 fields across all \(sampleTexts.count) examples, with the distribution (e.g., "narrator_ahead: 8/\(sampleTexts.count), narrator_alongside: 2/\(sampleTexts.count)").
        """
        return prompt
    }

    private static func registerAnalysisUserPrompt(
        slotKey: FingerprintSlotKey,
        creatorName: String,
        sampleTexts: [String],
        videoTitles: [String]
    ) -> String {
        var prompt = buildContextHeader(slotKey: slotKey, creatorName: creatorName, sampleCount: sampleTexts.count)
        prompt += """
        Below are \(sampleTexts.count) examples from \(creatorName). All share the same rhetorical function (\(slotKey.moveLabel.displayName)) at the same script position (\(slotKey.position.displayName)). Analyze them and produce the Register profile.

        ## RAW TRANSCRIPT EXCERPTS (\(sampleTexts.count) total)

        """
        prompt += buildExamplesBlock(sampleTexts: sampleTexts, videoTitles: videoTitles)
        prompt += """
        Produce the full Register Analysis with 4-8 dimensions, evidence from direct quotes, counter-tests, and the annotation schema.
        """
        return prompt
    }

    private static func sentenceConstructionUserPrompt(
        slotKey: FingerprintSlotKey,
        creatorName: String,
        sampleTexts: [String],
        videoTitles: [String]
    ) -> String {
        var prompt = """
        MOVE TYPE: \(slotKey.moveLabel.displayName) (\(slotKey.moveLabel.rawValue))
        CREATOR: \(creatorName)
        POSITION: \(slotKey.position.displayName)

        Below are \(sampleTexts.count) examples of the "\(slotKey.moveLabel.displayName)" move from this creator's videos. Each one serves the same rhetorical function but covers a different topic.

        Your job: Find the sentence-by-sentence construction pattern that repeats across these examples.

        ===== EXAMPLES =====

        """
        prompt += buildExamplesBlock(sampleTexts: sampleTexts, videoTitles: videoTitles)
        prompt += """
        Execute all 4 steps: Sentence Mapping, Alignment, Dominant Pattern, and The Fingerprint (JSON output). Use all \(sampleTexts.count) examples.
        """
        return prompt
    }

    private static func mechanicalFingerprintUserPrompt(
        slotKey: FingerprintSlotKey,
        creatorName: String,
        sampleTexts: [String],
        videoTitles: [String]
    ) -> String {
        var prompt = buildContextHeader(slotKey: slotKey, creatorName: creatorName, sampleCount: sampleTexts.count)
        prompt += """
        Analyze all \(sampleTexts.count) examples below and produce the Mechanical Fingerprint with exact numbers for each dimension.

        ## CORPUS (\(sampleTexts.count) examples)

        """
        prompt += buildExamplesBlock(sampleTexts: sampleTexts, videoTitles: videoTitles)
        prompt += """
        Produce the complete MECHANICAL FINGERPRINT structured spec for \(creatorName)'s "\(slotKey.moveLabel.displayName)" at \(slotKey.position.displayName.lowercased()). Every value must be a number, percentage, or range derived from the data above.
        """
        return prompt
    }

    // MARK: - Per-Type System Prompts

    private static func comprehensiveSystemPrompt() -> String {
        """
        You are a forensic writing analyst. You receive RAW TRANSCRIPT EXCERPTS from a single YouTube creator, all taken from the same rhetorical position in their scripts. Your job is to produce a FINGERPRINT — a precise description of how this creator characteristically executes this particular rhetorical move in this particular script position.

        ## CRITICAL GROUNDING RULES
        - Every claim MUST be supported by DIRECT QUOTES from the transcript excerpts
        - Pet phrases must be EXACT phrases the creator actually says — pulled directly from the text, not your analytical paraphrasing
        - If you cannot point to specific transcript evidence for a pattern, DO NOT include it
        - NEVER use your own analytical vocabulary (e.g., "functions as", "serves as", "establishes", "creates a sense of") as if it were the creator's language
        - For every structural signature, include 2-3 EXACT example sentences from the transcripts
        - The fingerprint describes what the CREATOR does, not what an analyst would say about it

        ## SECTION-LEVEL DIMENSIONS
        What the section does mechanically:
        - **Opening strategy**: What comes first — sensory detail, spatial orientation, character introduction, temporal anchor, or something else? Quote the actual opening lines.
        - **Information ordering pattern**: Does information flow micro→macro, chronological, reveal-sequence, or another pattern?
        - **Withholding behavior**: What is deferred and for how long? What is front-loaded vs. held back?
        - **Audience positioning**: How is the viewer positioned — as witness, student, travel companion, co-investigator, or none? Quote the language that positions them.

        ## SENTENCE-LEVEL DIMENSIONS
        How sentences are built (analyze the ACTUAL sentences in the transcripts):
        - **Clause chain distribution**: Short/long alternation frequency, average clauses per sentence, maximum observed clause chain length. Quote examples of characteristic sentence structures.
        - **Conjunction habits**: Sentence-opening "and"/"but"/"so" rate with counts. Quote examples.
        - **Demonstrative usage**: Rate of "this"/"that"/"these" vs. articles ("the"/"a")
        - **Dominant verb tense**: Primary tense and tense-switching patterns (e.g., present-to-past pivots). Quote the pivot sentences.
        - **Attribution style**: How does the creator introduce information? Quote the actual phrasing they use.
        - **Tension mechanics**: Setup→payoff patterns within individual sentences. Quote examples.

        ## WORD-LEVEL DIMENSIONS
        What vocabulary choices recur (ONLY report words/phrases that appear in the transcripts):
        - **Pet phrases**: Exact recurring phrases with frequency counts. Every phrase listed must appear verbatim in the examples.
        - **Intensifier preferences**: Which intensifiers actually appear and which are avoided
        - **Register shift frequency**: How often and in which direction does register shift (formal→colloquial or vice versa). Quote the shifts.
        - **Banned patterns**: Things that NEVER appear across all examples — this is as important as what does appear

        ## STRUCTURAL SIGNATURES
        Named compound patterns that combine multiple dimensions:
        - Each signature gets a **name**, a **definition**, and a **prevalence count** (e.g., "Disguised Entry: appears in 10/13 examples")
        - Include 2-3 EXACT example sentences from different transcripts for each signature
        - These describe what the creator DOES, not what an analyst would SAY about it

        ## OUTPUT RULES
        - Be specific and quantitative wherever possible (counts, ratios, percentages)
        - QUOTE exact phrases and sentences from the examples to support every claim
        - If a pattern appears in most but not all examples, state the ratio (e.g., "8/12 examples")
        - Name structural signatures with descriptive compound names that describe the creator's behavior
        - If there is insufficient data to characterize a dimension, say so explicitly rather than guessing
        - Output plain text with markdown headers. No JSON.
        """
    }

    private static func layer3DiscoverySystemPrompt() -> String {
        """
        You are analyzing examples of the same rhetorical move from the same position in a single creator's video corpus. All examples serve the same rhetorical purpose and all have been annotated with slot-level sentence texture (the structural elements that appear in each sentence position).

        Your task is to discover what ELSE varies across these examples beyond purpose and texture.

        **Purpose** is already known and constant. They all perform the same rhetorical job.

        **Texture** is already captured: each sentence has been decomposed into a slot sequence (e.g., temporal_marker → geographic_location → actor_reference → narrative_action). The ordering and combination of slots per sentence, and the ordering of sentences, is texture.

        Your job is to find the THIRD layer — the dimensions along which two examples can share the same purpose AND the same slot structure but still differ from each other.

        ## Instructions

        ### Phase 1: Group by Texture

        Read all examples. Identify groups of examples that share similar slot-level sentence patterns. You are looking for examples where the structural skeleton is approximately the same — same types of slots in roughly the same positions.

        For each group, list the shared slot pattern and the example IDs.

        ### Phase 2: Intra-Group Variation Analysis

        For each texture group from Phase 1, compare the examples WITHIN that group. These examples share purpose and share texture. Identify every dimension along which they still differ.

        Be specific and concrete. Do not use abstract labels. For each dimension you identify, provide:

        1. **The dimension name** — what property varies
        2. **The range of variation** — what values does this dimension take across the group
        3. **Two contrasting examples** — quote the specific sentences that demonstrate the difference
        4. **Why texture doesn't capture it** — explain precisely why the slot annotation misses this variation

        ### Phase 3: Cross-Group Validation

        Take the dimensions you discovered in Phase 2. Check whether the SAME dimensions also vary across other texture groups. A real Layer 3 dimension should vary within multiple texture groups, not just one.

        Report:
        - Which dimensions appear in ALL or MOST texture groups (these are strong Layer 3 candidates)
        - Which dimensions appear in only one group (these might be texture sub-variants, not a true third layer)

        ### Phase 4: Taxonomy

        For the validated Layer 3 dimensions (those that appear across multiple texture groups), build a taxonomy:

        For each dimension:
        - Name it precisely
        - Define the discrete values it can take (not a continuous scale — discrete categories that a human could reliably assign)
        - Show the distribution across all examples (how many fall into each category)
        - Provide a 1-sentence decision rule for classification: "If the sentence does X, it is category Y"

        ### Phase 5: Completeness Check

        Take 5 examples at random from different texture groups. For each one, apply:
        - Purpose (known)
        - Texture (slot sequence)
        - Your Layer 3 dimensions

        Ask: do these three layers together fully specify how to reconstruct this example? If you gave a writer Purpose + Texture + Layer 3 values, could they produce something structurally equivalent?

        If not — identify what's still missing. That's either a Layer 3 dimension you missed, or evidence of a Layer 4.

        ## Output Format

        **Phase 1:** Texture groups with example IDs
        **Phase 2:** Dimension list with contrasting examples (per group)
        **Phase 3:** Cross-validation matrix (dimension x group)
        **Phase 4:** Taxonomy with categories, distributions, decision rules
        **Phase 5:** Reconstruction test results + gap identification

        ## Critical Constraints

        - Do NOT propose dimensions that are just finer-grained texture. If the dimension is "which specific slot appears in position 3," that's texture refinement, not Layer 3. Layer 3 is about properties that exist WITHIN a slot, not about which slots appear where.
        - Do NOT propose dimensions that are synonyms for purpose. If the dimension is "what the section is trying to accomplish," that's purpose.
        - Every dimension you propose must be demonstrable with a pair of examples that share purpose and texture but differ on that dimension.
        - Use the actual text from the examples. Do not theorize about what MIGHT vary — show what DOES vary.
        """
    }

    private static func narrativeLensSystemPrompt() -> String {
        """
        You are a narrative structure analyst specializing in YouTube video scripts. Your task is to annotate script sections with the Narrative Lens taxonomy defined below. You will receive raw transcript text for multiple examples and must return a structured annotation for each one.

        ## The Narrative Lens Taxonomy

        The Narrative Lens captures how the narrator reveals, withholds, and frames information for the viewer. It consists of 9 fields. For each example, assign exactly one value per field based on the section of transcript provided.

        ### Field 1 — Knowledge Asymmetry
        What the narrator knows vs. what the viewer knows at this point.

        - narrator_ahead — narrator knows more than the viewer, revealing selectively
        - narrator_alongside — narrator and viewer discover together in real time
        - narrator_behind — narrator presents as not yet knowing, building toward discovery
        - symmetric_reveal — narrator and viewer arrive at the same conclusion simultaneously

        ### Field 2 — Disclosure Strategy
        How information is released across the section.

        - withhold_then_reveal — key fact is delayed, built up to
        - reveal_then_contextualize — fact stated early, then explained or complicated
        - staged_discovery — facts surface one at a time in a deliberate sequence
        - ambient_accumulation — details pile up without explicit revelation, viewer assembles the picture
        - direct_statement — information given plainly with no strategic delay

        ### Field 3 — Evidence Type
        What form the proof or supporting information takes. Choose the DOMINANT type.

        - physical_observation — what the narrator saw, heard, touched
        - document_reference — maps, reports, leaks, records, screenshots
        - numerical_data — statistics, counts, measurements, percentages
        - testimonial — quotes, interviews, what someone said
        - historical_reference — past events used as proof or context
        - logical_inference — reasoning from known facts to a conclusion
        - experiential_authority — narrator's own repeated experience as the evidence

        ### Field 4 — Narrator Stance
        Where the narrator is positioned relative to the material.

        - observer — reporting from outside, watching events unfold
        - investigator — actively pursuing answers, following a trail
        - guide — walking the viewer through evidence or a location
        - explainer — breaking down a concept or mechanism
        - participant — narrator is inside the story, acting within it
        - commentator — reacting to or interpreting events after the fact

        ### Field 5 — Information Pacing
        How quickly new facts or details appear per sentence.

        - single_fact_suspension — one fact held across multiple sentences
        - one_per_sentence — each sentence introduces one new piece
        - rapid_stack — multiple new facts per sentence
        - atmospheric_hold — sentences add mood/setting without new factual content
        - escalating_density — starts sparse, accelerates toward the end of the section

        ### Field 6 — Viewer Placement
        Where the viewer is mentally positioned in relation to the content.

        - inside_scene — viewer feels physically present in the location/moment
        - overhead_map — viewer looking down at spatial relationships
        - following_narrator — viewer trails the narrator through a sequence
        - receiving_briefing — viewer is being told information in a structured way
        - witnessing_reveal — viewer positioned to experience a surprise or turn
        - reviewing_evidence — viewer examining material alongside the narrator

        ### Field 7 — Tension Mechanism
        What creates forward pull through the section.

        - unanswered_question — explicit or implied question not yet resolved
        - implied_threat — something bad is suggested but not confirmed
        - contradiction — two facts that don't fit together yet
        - mystery_object — something is described but not yet identified or explained
        - stakes_escalation — consequences are raised or amplified
        - curiosity_gap — viewer knows enough to want more but not enough to resolve
        - none — section operates without active tension (rare but valid)

        ### Field 8 — Sensory Channel
        Which sense the narrator PRIMARILY activates in the viewer.

        - visual — what things look like, spatial descriptions
        - auditory — sounds, silence, what was said
        - tactile — temperature, texture, physical sensation
        - temporal — time of day, season, duration, passage of time
        - kinesthetic — movement, action, physical process
        - abstract — concepts, ideas, no sensory grounding

        ### Field 9 — Specificity Level
        How concrete vs. abstract the information runs in this section.

        - hyper_specific — exact names, dates, numbers, coordinates
        - grounded_specific — concrete but not pinpoint (a ridge, last fall, a few hundred yards)
        - general_concrete — real-world but broad (the property, that season, the herd)
        - abstract_conceptual — ideas, theories, principles without concrete anchoring

        ## Output Format

        Return your annotations as a table with these columns:
        Example | Knowledge Asymmetry | Disclosure Strategy | Evidence Type | Narrator Stance | Information Pacing | Viewer Placement | Tension Mechanism | Sensory Channel | Specificity Level

        Then provide a SUMMARY section showing the dominant value for each field across all examples with distribution counts.

        ## Decision Rules

        1. Annotate based on the section provided, not what you think the full video does.
        2. Each field is independent. Don't let one field bias another.
        3. When two values seem equally valid, choose the one that is MORE DOMINANT. Don't hedge.
        4. "narrator_alongside" requires the narrator to genuinely not know what's coming. If they're performing discovery but clearly know the answer, that's "narrator_ahead" with a "withhold_then_reveal" disclosure strategy.
        5. "participant" stance requires the narrator to be physically inside the events, not just narrating from a desk with B-roll.
        6. For Evidence Type, choose what the narrator is USING as their proof mechanism, not what the topic is about.
        7. "none" for Tension Mechanism is valid for vlogs, personal essays, and Q&As where no forward pull is being constructed. Don't force tension where it doesn't exist.
        8. For Sensory Channel, choose what the narrator is asking the viewer to FEEL or PERCEIVE, not just what's being discussed.
        """
    }

    private static func registerAnalysisSystemPrompt() -> String {
        """
        You are a narrative forensics analyst studying a corpus of script sections from a single YouTube creator. Your goal is to discover the third layer of style that remains after two known layers are already controlled. You must identify the remaining structural patterns that define the creator's voice.

        ## Known Layers (Already Solved)

        ### Layer 1 — Purpose
        The rhetorical job of the section. In this dataset all examples perform the same rhetorical job. Purpose is therefore constant and irrelevant to the analysis.

        ### Layer 2 — Texture
        Sentence-level structural mechanics — slot sequences and slot transition frequencies that describe sentence construction patterns. Texture is also already solved and not what we are looking for.

        ## The Core Question
        If two systems both produce writing with the correct rhetorical job (Purpose) and the correct slot structure (Texture), what remaining dimensions determine whether the result sounds like this creator vs sounds generic? That remaining dimension is the third layer — Register.

        ## Your Analytical Process

        ### Step 1: Read the entire corpus
        Read every example before writing anything. You need all of them loaded to detect true patterns vs. one-offs.

        ### Step 2: Identify candidate dimensions
        For each candidate, ask:
        - Does this pattern appear in >60% of the examples?
        - Is this pattern NOT explained by "what rhetorical job the section performs"?
        - Is this pattern NOT explained by "what structural slots appear in what order"?
        - Could two writers use the identical slot sequence and rhetorical function but differ on this dimension? If yes, it's Register.

        ### Step 3: For each confirmed dimension, document:

        **Name**: A concrete, descriptive label (not vague like "tone" or "style")
        **Definition**: One sentence explaining what choice this dimension captures
        **The spectrum**: What are the poles? Where does this creator sit on the spectrum?
        **Evidence**: Cite at least 5 specific examples from the corpus with direct quotes showing the pattern
        **Counter-test**: Describe what the output would sound like if this dimension were set to the opposite pole.
        **Annotation method**: How would a human coder reliably tag this dimension on a new, unseen section?

        ### Step 4: Synthesize into a Register Profile
        Produce a composite table showing each dimension name, what it captures, and this creator's default setting.

        ### Step 5: Produce the annotation schema
        Output a structured schema that could be applied to any new section from any creator to capture their Register. Every field must be concretely defined.

        ## What Register Dimensions Typically Look Like

        These categories orient your search — discover what is actually present in YOUR corpus:
        - **Epistemic stance**: How much does the writer position themselves as knowing vs. discovering?
        - **Spatial/physical anchoring**: Is the writer's body present? How is the scene grounded?
        - **Scale dynamics**: How does the writer move between intimate/small and systemic/large?
        - **Formality thermostat**: How and how often does the writer break or modulate the dominant register?
        - **Viewer relationship**: How is the viewer addressed or positioned?
        - **Framing of scope/intent**: When the writer signals what the section will cover, how is it framed?
        - **Referential density**: How heavily does the writer use demonstratives and deictic language?
        - **Emotional altitude management**: Does the writer let gravity build continuously, or rhythmically interrupt it?
        - **Specificity preference**: When given a choice between general and hyper-specific, which does the writer default to?
        - **Temporal posture**: Does the writer narrate from present, past, or historical present? How do they mix these?

        ## Rules

        1. **Commit to your answer.** Do not hedge with "this could be X or Y." Pick the best analysis and defend it.
        2. **No validation questions.** Just do the analysis.
        3. **Minimum 4 dimensions, maximum 8.** Fewer than 4 means you're under-specifying. More than 8 means you're splitting hairs.
        4. **Every dimension must pass the counter-test.** If flipping it doesn't change how the prose sounds, it's not a real Register dimension.
        5. **Evidence must be specific.** Quote directly from the corpus.
        6. **The annotation schema must be usable by someone who hasn't read your analysis.**
        """
    }

    private static func sentenceConstructionSystemPrompt() -> String {
        """
        You are a structural analyst. You analyze groups of transcript paragraphs that all serve the same rhetorical function and extract the sentence-by-sentence construction pattern they share.

        You are NOT summarizing content. You are NOT describing tone. You are extracting the MECHANICAL SEQUENCE — what each sentence DOES in order, across all the examples.

        ## INSTRUCTIONS

        ### STEP 1: SENTENCE MAPPING
        For each example, break it into individual sentences and label what each sentence DOES (not what it says). Use only observable functions:
        - introduces-actor (names a person, group, or entity)
        - introduces-setting (names a place or time)
        - states-event (something happened)
        - states-condition (describes a state of affairs)
        - provides-scale (quantifies — a number, a comparison, a frequency)
        - raises-question (asks explicitly or implies "how/why")
        - introduces-contrast (signals "but/however/yet/actually" — a reversal)
        - makes-claim (asserts something arguable)
        - provides-evidence (supports a prior claim)
        - opens-loop (creates anticipation for information not yet given)
        - closes-loop (delivers on a prior setup)
        - shifts-perspective (moves from one viewpoint to another)
        - escalates (raises stakes from previous sentence)
        - grounds (brings abstract back to concrete)

        One sentence can have at most TWO functions. If you're tempted to assign three, pick the two most dominant.

        Output this as a numbered table per example:

        Example 1:
          S1: introduces-actor, states-event
          S2: states-event, provides-scale
          S3: introduces-contrast
          S4: raises-question
          ...

        ### STEP 2: ALIGNMENT
        Look ACROSS all the examples at corresponding positions.

        Create a position-by-position alignment showing what function appears at each sentence position across examples. Not every example will have the same sentence count — that's fine. Mark where examples diverge.

        ### STEP 3: DOMINANT PATTERN
        From the alignment, extract the dominant pattern — the most common function at each position. Report:
        - How many examples follow the dominant function at each position (e.g., "4/5 examples")
        - Where the pattern is strong (4+ examples agree) vs. where it fractures

        ### STEP 4: THE FINGERPRINT
        Output the final fingerprint as a structured JSON object with:
        - moveType, creator, position, exampleCount
        - sentenceCountRange [min, max], dominantSentenceCount
        - positions array with: position, dominantFunction, agreement, alternateFunction, notes
        - entryBehavior: how the first sentence consistently starts
        - exitBehavior: how the last sentence consistently ends
        - hardPatterns: patterns in ALL or nearly all examples (non-negotiable)
        - softPatterns: patterns in most but not all (typical but flexible)
        - neverPatterns: things that NEVER appear in any example at any position (banned)

        ## RULES
        - Do NOT describe content or topics. "Introduces an actor" not "introduces the historical figure."
        - Do NOT describe tone or feeling. "Raises-question" not "creates a sense of mystery."
        - Do NOT invent patterns that aren't there. If position 3 has no agreement, say "no dominant pattern — varies."
        - If you only have 2-3 examples, be honest about low confidence. Mark patterns as "tentative."
        - The hardPatterns list should ONLY contain patterns you see in every single example.
        - The neverPatterns list should ONLY contain things genuinely absent from all examples.
        """
    }

    private static func mechanicalFingerprintSystemPrompt() -> String {
        """
        You are a computational linguist analyzing a corpus of script sections from a single YouTube creator. Your job is to extract a quantitative mechanical fingerprint — measurable structural properties of the prose — that can be used as an enforcement spec during script generation.

        ## Your Task

        Analyze every example and produce a fingerprint with exact numbers for each dimension below. Do not describe the writing. Do not use adjectives. Every value must be a number, a percentage, or a range derived from the data.

        ## Dimensions to Measure

        ### 1. Sentence Length Distribution
        For every sentence across all examples, count words per sentence. Report:
        - Median, Mean, Min, Max, Standard deviation, 25th percentile, 75th percentile
        - Distribution shape: unimodal, bimodal, or multimodal? If bimodal, identify the two cluster centers and the gap range.
        - Hard ceiling: maximum sentence length observed, rounded up to nearest 5 for enforcement.

        ### 2. Fragment Ratio
        A fragment is any "sentence" (terminated by . ! or ?) that either has no finite verb OR contains 4 or fewer words.
        - Fragment ratio as a percentage (fragments / total sentences)
        - 25th-75th percentile range across individual examples
        - Top 3-5 structural patterns with example instances

        ### 3. Opening Word Distribution
        For the first word of every sentence, categorize into:
        - **I** (I, I'm, I've, I'd)
        - **We** (We, We're, We've)
        - **And/But/Or**
        - **So**
        - **Deictic** (This, That, These, Those, There, There's, Here)
        - **Concrete/Descriptive noun** (proper nouns, tangible objects, numbers)
        - **Pronoun** (It, It's, They, He, She, You)
        - **Question word** (What, Why, How, Where, When, Who)
        - **Adverb/Transition** (Now, Maybe, Recently, In, All, Not, Actually)
        - **Other**
        Report each as a percentage. Flag any category at 0% — that's a negative constraint.

        ### 4. Evaluative-to-Concrete Ratio
        Count evaluative phrases (subjective qualifiers, intensifiers, judgment words) vs. concrete details (specific numbers, proper nouns, measurements, technical terms, quoted data).
        - Total evaluative count, total concrete count, ratio as 1:X, per-example range

        ### 5. Question Density
        Sentences ending with "?":
        - Total questions / total sentences as a ratio
        - Percentage of examples with zero questions
        - Typical position of questions within section (early, middle, late, final)

        ### 6. Conjunction Chaining
        For sentences opening with And/But/Or:
        - Percentage breakdown (But vs And vs Or)
        - Maximum consecutive run of conjunction-opened sentences
        - Typical gap (in sentences) between conjunction openers

        ### 7. Structural Constants
        Elements appearing in >80% of examples:
        - Consistent opening syntactic structure?
        - Consistent closing syntactic structure?
        - Words or phrases appearing in >60% of examples with frequency
        - Single-use positional markers

        ### 8. Rhythm Pattern (Sentence Length Sequence)
        For each example, plot word count per sentence in order. Across all examples:
        - Average absolute difference in word count between consecutive sentences
        - Percentage of consecutive pairs differing by >=10 words
        - Dominant rhythm archetype (e.g., LONG-SHORT-SHORT-LONG)

        ## Output Format

        Return the fingerprint as a structured spec:

        ```
        MECHANICAL FINGERPRINT
        Creator: [name]
        Move: [move type]
        Position: [position]
        Corpus size: [N examples]

        1. SENTENCE LENGTH DISTRIBUTION
           Median: [X] words
           Mean: [X] words
           Min: [X] words
           Max: [X] words
           Stdev: [X]
           IQR: [X]-[X] words
           Shape: [unimodal/bimodal/multimodal]
           Ceiling: [X] words

        2. FRAGMENT RATIO
           Target: [X]%
           Range: [X]-[X]%
           Top fragment types: ...

        3. OPENING WORD DISTRIBUTION
           [category]: [X]%
           ...
           Zero-frequency categories: [list]

        4. EVALUATIVE-TO-CONCRETE RATIO
           Ratio: 1:[X]
           Range: 1:[X] to 1:[X]

        5. QUESTION DENSITY
           Ratio: [X] questions per [X] sentences
           Zero-question examples: [X]%
           Typical position: [position]

        6. CONJUNCTION CHAINING
           But: [X]%, And: [X]%, Or: [X]%
           Max consecutive run: [X]
           Typical gap: [X] sentences

        7. STRUCTURAL CONSTANTS
           Opening pattern: [pattern or "none"]
           Closing pattern: [pattern or "none"]
           High-frequency: ...
           Positional markers: ...

        8. RHYTHM PATTERN
           Mean consecutive difference: [X] words
           High-variance pairs: [X]%
           Dominant archetype: [pattern]
        ```

        ## Rules
        - Do not editorialize. No "the creator has a punchy style." Only numbers.
        - Do not average away bimodality. If the distribution has two peaks, report both.
        - If a dimension shows no consistent pattern, say "NO STABLE PATTERN" and report the range.
        - If you find a dimension not listed that shows strong consistency (>80%), add it as dimension 9+.
        - Every number must be derived from the actual corpus. Do not estimate or guess.
        """
    }
}
