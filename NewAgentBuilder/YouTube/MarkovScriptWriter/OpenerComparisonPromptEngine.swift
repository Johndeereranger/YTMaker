//
//  OpenerComparisonPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//
//  Prompt builders for opener comparison methods M3-M8.
//  M1 and M2 reuse OpenerMatcherPromptEngine.buildFilteredDraftPrompt / buildRewritePrompt.
//

import Foundation

struct OpenerComparisonPromptEngine {

    // MARK: - V4 Constraint Blocks

    static let NARRATIVE_MODE = """
    NARRATIVE MODE — this is the most important constraint in this prompt:

    This creator tells stories through EVENTS and EVIDENCE, not through EXPLANATIONS or ADVICE.

    ALLOWED sentence types (use these):
    - EVENT: Someone did something. ("Last fall, a frozen dead body was brought into this Portland hotel.")
    - EVIDENCE: Something was found or observed. ("They started tracking these trucks with GPS and found that the trucks were loaded with oil.")
    - CONTRADICTION: What should be true vs. what is true. ("But here he was a few months later on display at a public event.")
    - QUESTION: Direct questions at the pivot. ("How is this possible?")
    - ACTOR: Introduce a person or group doing something. ("Some reporters from a local TV station caught wind of this.")

    BANNED sentence types (never use these):
    - EXPLANATION: "Understanding why requires..." / "This means..." / "What this shows is..."
    - ADVICE: "You need to understand..." / "You need to see what they see..."
    - EVALUATION: "This was a complete collapse..." / "This isn't just bad luck..."
    - GENERALIZATION: "When deer patterns shift dramatically, there's always a reason..."
    - METAPHOR: "It was the kind of spot legends are made of..." / "Like Christmas morning..."
    """

    static let VERB_CONSTRAINT = """
    VERB CONSTRAINT:

    Prefer investigative or observational verbs:
    - saw, spotted, counted, tracked, followed, recorded, filmed, found, discovered, mapped, climbed, sat, watched, called, flew

    Avoid abstract or explanatory verbs:
    - understand, reveal, explain, demonstrate, indicate, illustrate, show (when meaning "demonstrate"), require, suggest, mean

    Example:
    BAD: "Understanding why requires getting inside the mind of a whitetail"
    GOOD: "So we flew a thermal drone over this property and started tracking where these deer were actually moving"
    """

    static let ACTOR_REQUIREMENT = """
    ACTOR REQUIREMENT:

    The story must include actors performing actions. At least every second sentence should contain an actor doing something.

    Actors can include:
    - hunters, landowners, researchers, investigators, drones, cameras, biologists, trail cameras

    BAD: "The deer disappeared from the property."
    GOOD: "These hunters kept climbing into this same stand and the deer never showed up."

    BAD: "Deer patterns shifted dramatically."
    GOOD: "The landowner checked his trail cameras and what he found is that these deer had completely changed their movement patterns."
    """

    static let EVIDENCE_MINIMUM = """
    EVIDENCE REQUIREMENT:

    The opening must contain at least 2 pieces of concrete evidence:
    - numbers ("double-digit deer," "five deer per hunt")
    - measurements or counts
    - locations ("this tree stand," "this property")
    - objects or equipment ("trail cameras," "thermal drone")
    - recorded observations

    BAD: "The property stopped producing."
    GOOD: "Five deer on any given hunt became a high-end day on this property."
    """

    static let TEXTURE_RULES = """
    VOICE TEXTURE — apply these while writing events:
    - Use "this/these + noun" instead of "the/a + noun" ("this tree stand" not "the stand," "these deer" not "the deer")
    - Repeat key nouns instead of switching to pronouns ("this property...this property" not "this property...it")
    - Build long sentences with "and/but/then" chains, not subordinate clauses
    - Drop in casual spoken asides ("like," "around," "basically," "just," "what the hell")
    - Use spoken syntax inversions ("what they found is that..." not "they found that...")
    """

    // MARK: - Shared Helpers

    /// Format template openings into prompt text blocks.
    private static func formatTemplates(_ openings: [OpenerMatcherPromptEngine.CorpusOpening]) -> String {
        var parts: [String] = []
        for (i, opening) in openings.enumerated() {
            parts.append("### Template \(i + 1): \(opening.title)")
            for section in opening.sectionTexts {
                parts.append("[\(section.label)]")
                parts.append(section.text)
                parts.append("")
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Format filtered gists into prompt text blocks.
    private static func formatGists(_ gists: [RamblingGist]) -> String {
        var parts: [String] = []
        for (posIdx, gist) in gists.enumerated() {
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

    // MARK: - M3: Cognitive Scaffolding

    static func buildCognitiveScaffoldingPrompt(
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist]
    ) -> (system: String, user: String) {

        let system = """
        You are writing a YouTube script opening. You must follow this exact cognitive sequence — do NOT skip steps.

        STEP 1 — TEMPLATE ANALYSIS
        Before writing anything, analyze the template openings. For each template, identify:

        Skeleton features:
        - How does the first sentence land? (Question? Scene? Statement? How many words?)
        - What's the sentence length pattern?
        - Where does the pivot happen?
        - How does the creator address the viewer?
        - What information is revealed vs. withheld?

        Spoken texture features (EQUALLY IMPORTANT):
        - DEMONSTRATIVE COUNT: How many times does the creator use "this + noun" or "these + noun"? List every instance.
        - NOUN REPETITION: Where does the creator repeat a full noun phrase instead of using a pronoun? List every instance.
        - CONJUNCTION CHAINS: Copy the 3 longest sentences and mark whether they're long from subordinate clauses or from "and/but/then" chaining.
        - CASUAL INSERTIONS: List every casual aside, approximation, or informal riff.
        - SPOKEN INVERSIONS: List every instance of spoken syntax ("what they found is that" vs. "they found that").

        Narrative mode features (MOST IMPORTANT):
        - SENTENCE TYPE COUNT: Classify every template sentence as EVENT, EVIDENCE, CONTRADICTION, QUESTION, ACTOR, or EVALUATION. What's the ratio?
        - What percentage of template sentences describe events/observations vs. explain/advise?

        STEP 2 — CONTENT CLASSIFICATION
        Classify every fact from the provided content into exactly one bucket:
        - EVENT: Something that happened or was done by an actor. ("They called it DD." "These hunters climbed into this stand." "Five deer became a high-end hunt.") These are PRIMARY — build the opening from these.
        - SETTING: Scene details, context, location. These SUPPORT events.
        - PROBLEM: Contradictions, surprising observations. CAP at 2.
        - DISCOVERY: Findings, conclusions, explanations. OFF-LIMITS.

        NEW RULE: At least 70% of your sentences must be EVENT type — actors doing things, observations being made. No more than 2 sentences in the entire opening can be direct advice or explanation to the viewer.

        STEP 3 — STRUCTURAL MAPPING
        Decide which EVENT and SETTING facts map to which position in the template structure. Write a brief beat-by-beat plan. For each beat, identify which actor is performing which action.

        STEP 4 — DRAFT
        Write the opening.

        \(Self.NARRATIVE_MODE)

        \(Self.VERB_CONSTRAINT)

        \(Self.ACTOR_REQUIREMENT)

        \(Self.EVIDENCE_MINIMUM)

        \(Self.TEXTURE_RULES)

        Write as if reporting what happened, not explaining what it means. Every sentence should describe something someone did, something someone found, or a contradiction between what was expected and what occurred.

        STEP 5 — SELF-AUDIT (forced rewrites, not yes/no questions)
        Do each of these checks IN ORDER. Do not skip any.

        1. NARRATIVE MODE CHECK: Count your sentences. How many describe events/actions by actors vs. how many explain/advise/evaluate? If more than 2 sentences are explanation or advice, rewrite them as events right now.
           BEFORE: "You need to understand the details of your property"
           AFTER: "So we flew a thermal drone over this property and started tracking where these deer were moving"

        2. ACTOR CHECK: Does at least every other sentence have an actor doing something? If not, add actors to the sentences that lack them.

        3. VERB CHECK: Scan every verb. Replace any instance of "understand," "reveal," "explain," "demonstrate," "indicate," or "require" with an investigative verb (tracked, found, spotted, filmed, counted, mapped, flew, climbed, sat, watched).

        4. CONJUNCTION CHECK: Copy your three longest sentences. Are they built from "and/but/then" chains or subordinate clauses? If subordinate, rewrite as conjunction chains.

        5. DEMONSTRATIVE CHECK: Count your "this/these + noun" instances. List them. If fewer than 5, replace "the" with "this" in at least 3 places.

        6. CONTENT DISCIPLINE: Does the viewer know the situation but NOT the explanation? Did any DISCOVERY bucket facts or evaluative summary statements leak in?

        OUTPUT FORMAT:
        First output your analysis work under ## ANALYSIS (steps 1-3), then output the final script under ## OPENING.
        """

        var user = "## WRITE IT LIKE THIS:\n\n"
        user += formatTemplates(matchOpenings)
        user += "\n---\n\n## WRITE IT ABOUT THIS:\n\n"
        user += formatGists(filteredGists)

        return (system, user)
    }

    /// Parse M3 response: extract analysis and opening text.
    /// Strips any self-audit section (STEP 5) that the LLM appends after the opening.
    static func parseCognitiveScaffoldingResponse(_ response: String) -> (analysis: String, opening: String) {
        let analysisMarker = "## ANALYSIS"
        let openingMarker = "## OPENING"

        guard let analysisRange = response.range(of: analysisMarker),
              let openingRange = response.range(of: openingMarker) else {
            return (analysis: "", opening: response.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let analysis = String(response[analysisRange.upperBound..<openingRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var opening = String(response[openingRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip self-audit if the LLM appended it after the opening
        let auditMarkers = ["### STEP 5", "## STEP 5", "**STEP 5", "STEP 5 —", "SELF-AUDIT"]
        for marker in auditMarkers {
            if let auditRange = opening.range(of: marker) {
                opening = String(opening[opening.startIndex..<auditRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        return (analysis: analysis, opening: opening)
    }

    // MARK: - M4: Analysis-First Rewrite

    static func buildAnalysisRewritePrompt(
        draftText: String,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are rewriting a script opening to match a specific creator's voice. The draft has the right content but the voice has drifted.

        Before rewriting, perform a QUANTITATIVE mechanical analysis of the template openings:

        SKELETON ANALYSIS:
        1. SENTENCE LENGTH: Count the exact word count of every sentence in both templates. Report the distribution.
        2. ENTRY PATTERN: What is the first sentence? How many words? Type?
        3. FRAGMENT USAGE: List every fragment. What structural job does each do?
        4. TRANSITION MECHANICS: Between each pair of consecutive sentences, classify the transition.
        5. ENERGY MAP: Rate each sentence's energy (1-5). Where does the peak land?

        NARRATIVE MODE ANALYSIS:
        6. SENTENCE TYPE CLASSIFICATION: Classify every sentence in both templates as EVENT, EVIDENCE, CONTRADICTION, QUESTION, ACTOR, or EVALUATION. Report the count and ratio. What percentage are event/evidence? Your rewrite must match this ratio. Any sentence you write that is EVALUATION type must be justified by a matching EVALUATION in the templates.

        TEXTURE ANALYSIS:
        7. CONSTRUCTION FEEL: For each sentence over 15 words, classify as SPOKEN-FEEL (and/but/then chains) or WRITTEN-FEEL (subordinate clauses). Report ratio. Your rewrite must match.
        8. ARTICLE CHOICE: Count this/these vs the/a for key nouns. Report ratio as a concrete number. Your rewrite must match density.
        9. PIVOT REGISTER: Quote the exact pivot sentences. Classify register.

        Compare the draft against ALL 9 measurements. Identify SPECIFIC divergences.

        \(Self.VERB_CONSTRAINT)

        \(Self.ACTOR_REQUIREMENT)

        \(Self.EVIDENCE_MINIMUM)

        REWRITE PROCESS — sentence by sentence:
        For each sentence in your rewrite, INTERNALLY determine:
        (1) Target word count from analysis
        (2) Transition type from analysis
        (3) Sentence type — must be EVENT, EVIDENCE, CONTRADICTION, or QUESTION (not EVALUATION unless templates have one at that position)
        (4) One texture feature to execute (construction feel, article choice, or spoken insertion)

        Then write the sentence. Do NOT include your internal planning in the final output.

        Output in two sections:
        ## MECHANICAL ANALYSIS
        [your quantitative analysis of all 9 dimensions + divergence list]

        ## REWRITTEN OPENING
        [ONLY the final clean script text — no scaffolding, no targets, no annotations, no bullet points. Just the script ready to read on camera.]
        """

        var user = "## THE VOICE TO MATCH:\n\n"
        user += formatTemplates(matchOpenings)
        user += "\n---\n\n## THE DRAFT TO REWRITE:\n\(draftText)"

        return (system, user)
    }

    /// Parse M4 response: extract mechanical analysis and rewritten opening.
    static func parseAnalysisRewriteResponse(_ response: String) -> (analysis: String, rewriteText: String) {
        let analysisMarker = "## MECHANICAL ANALYSIS"
        let rewriteMarker = "## REWRITTEN OPENING"

        guard let analysisRange = response.range(of: analysisMarker),
              let rewriteRange = response.range(of: rewriteMarker) else {
            return (analysis: "", rewriteText: response.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let analysis = String(response[analysisRange.upperBound..<rewriteRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rewriteText = String(response[rewriteRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (analysis: analysis, rewriteText: rewriteText)
    }

    // MARK: - M5: Spoon-Fed Rules

    /// M5-call-1: Extract concrete mechanical rules from templates.
    static func buildRuleExtractionPrompt(
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are a voice mechanics analyst. Read the template openings below and extract a short list of concrete, enforceable writing rules.

        CRITICAL FILTER: Extract rules that distinguish THIS creator from a generic competent writer. If a rule could apply to any YouTube script, it's too generic — skip it.

        Test each rule: Would following it make a generic writer sound more like this specific creator, or just make them a better generic writer? Only include the first kind.

        Extract exactly 5 rules. Each must be:
        - SPECIFIC enough to verify mechanically
        - DISTINCTIVE to this creator
        - Illustrated with a BEFORE/AFTER example

        CRITICAL CONSTRAINT: At least 2 of your 5 rules must be about NARRATIVE MODE — how the creator structures information as investigation/events rather than explanation/advice.

        Examples of narrative mode rules:
        - "Every sentence must describe an event, observation, or discovery — never an explanation or piece of advice."
          BEFORE: "Understanding why requires getting inside the mind of a whitetail"
          AFTER: "So we flew a thermal drone over this property and what we found is that these deer were doing something nobody expected"

        - "Introduce actors as subjects performing actions — never use passive generalization."
          BEFORE: "When deer patterns shift dramatically, there's always a reason"
          AFTER: "These hunters kept climbing into this stand and the deer never showed up"

        The remaining 3 rules can be about voice texture (demonstratives, noun repetition, spoken construction, casual insertions, etc.)

        Also provide a BANNED PHRASES list including:
        - Generic YouTube phrases this creator never uses
        - Explanatory/advice constructions ("You need to understand," "This means," "Understanding why requires")
        - Written-sounding constructions that violate spoken texture

        Output format:
        ## RULES
        1. [Rule] — Example: [before] → [after]
        2. ...

        ## BANNED PHRASES
        - phrase 1
        - phrase 2
        """

        let user = "## TEMPLATE OPENINGS TO ANALYZE:\n\n" + formatTemplates(matchOpenings)

        return (system, user)
    }

    /// M5-call-2: Apply extracted rules to rewrite the M1 draft.
    static func buildRuleApplicationPrompt(
        draftText: String,
        extractedRules: String
    ) -> (system: String, user: String) {

        let system = """
        You are rewriting a script opening to comply with a set of voice rules.

        You will receive:
        1. A numbered list of rules with before/after examples
        2. A banned phrases list
        3. A draft opening to rewrite

        Your job:
        - Go through the draft sentence by sentence
        - Check each sentence against every rule
        - Rewrite sentences that violate any rule
        - Remove or replace any banned phrases
        - Preserve the content and facts — only change the voice mechanics

        NARRATIVE MODE RULES TAKE PRIORITY. If a sentence violates a narrative mode rule (it explains or advises instead of narrating events), rewrite the entire sentence — don't just adjust the texture. A well-textured explanation is still an explanation.

        \(Self.VERB_CONSTRAINT)

        \(Self.ACTOR_REQUIREMENT)

        ANTI-INFLATION: Not all rules are equally important. If applying a rule makes a sentence sound MORE written and LESS spoken, the rule is being applied wrong. The spoken feel always wins over mechanical compliance. Do not pad sentences. Do not add adjectives or clauses to satisfy a "details" rule.

        After rewriting, if any sentence is longer than the longest sentence in the templates, shorten it. The rules are guidelines, not targets to maximize.

        Output in two sections:
        ## RULE VIOLATIONS
        [list each violation found: which sentence, which rule, what's wrong]

        ## REWRITTEN OPENING
        [the final rewritten script text]
        """

        var user = "## VOICE RULES:\n\n\(extractedRules)"
        user += "\n\n---\n\n## DRAFT TO REWRITE:\n\(draftText)"

        return (system, user)
    }

    // MARK: - M6: 2-Call Analysis → Rewrite

    /// Parse M5-call-2 response: extract rule violations and rewritten opening.
    static func parseRuleApplicationResponse(_ response: String) -> (ruleViolations: String, rewriteText: String) {
        let violationsMarker = "## RULE VIOLATIONS"
        let rewriteMarker = "## REWRITTEN OPENING"

        guard let violationsRange = response.range(of: violationsMarker),
              let rewriteRange = response.range(of: rewriteMarker) else {
            return (ruleViolations: "", rewriteText: response.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let ruleViolations = String(response[violationsRange.upperBound..<rewriteRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rewriteText = String(response[rewriteRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (ruleViolations: ruleViolations, rewriteText: rewriteText)
    }

    /// M6-call-1: Generate a standalone voice analysis document from templates.
    static func buildVoiceAnalysisPrompt(
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are creating a Voice Analysis Document for a YouTube creator. This document will be used by a separate writing system to generate script openings that match this creator's voice.

        Analyze the template openings and produce a detailed mechanical description covering these 10 dimensions:

        ## DIMENSION 0 — NARRATIVE MODE (most important)

        Classify every sentence in both templates as:
        - EVENT: Someone did something / something happened
        - EVIDENCE: Something was found, observed, measured
        - CONTRADICTION: Expected reality vs. actual reality
        - QUESTION: Direct question
        - ACTOR: Introduces a person/group doing something
        - EVALUATION: Judgment, explanation, advice, generalization

        Count the totals. Report the ratio of EVENT+EVIDENCE+CONTRADICTION+ACTOR to EVALUATION.

        Quote 3 EVENT sentences and 3 EVIDENCE sentences verbatim as rhythm references.

        This creator's voice is fundamentally INVESTIGATIVE REPORTING, not EXPLANATION. The downstream writer must produce event/evidence sentences, not evaluation sentences. This is the single most important constraint in this document.

        SKELETON DIMENSIONS:

        ### 1. SENTENCE ARCHITECTURE
        - Average sentence length (count words in every sentence, report range and median)
        - Sentence length PATTERN
        - Dominant sentence type

        For each finding, include 2-3 VERBATIM QUOTES from the templates.

        ### 2. ENTRY MECHANICS
        - First sentence: exact structure, word count, type
        - First 3 sentences: what does viewer know? What don't they know?

        Include verbatim quotes.

        ### 3. INFORMATION ECONOMY
        - What is revealed? What is withheld?
        - How many concrete facts? How many evaluative statements?
        - Where does mystery get planted?

        Include verbatim quotes.

        ### 4. TRANSITION SIGNATURES
        - How does the creator move between sentences?
        - List every transition word/phrase and count frequency

        Include verbatim quotes.

        ### 5. ENERGY ARC
        - Map energy of each sentence (1-5)
        - Where is the peak? What creates it?

        Include verbatim quotes.

        TEXTURE DIMENSIONS:

        ### 6. DEMONSTRATIVE POINTING PATTERN
        - Count every "this + noun" and "these + noun"
        - List them all with surrounding context
        - Calculate density per paragraph
        - Contrast with "the + noun" for same referents

        ### 7. NOUN REPETITION vs. PRONOUN ECONOMY
        - For each key noun, track full phrase vs. pronoun appearances
        - List specific examples of "unnecessary" noun repetition
        - Quantify repetition tolerance

        ### 8. SPOKEN SYNTAX MARKERS
        - CONJUNCTION CHAINS: For sentences over 20 words, map clause structure. Report spoken vs. written ratio.
        - CASUAL INSERTIONS: List every informal element. Count per paragraph.
        - INDIRECT CONSTRUCTIONS: List spoken-syntax inversions. Count frequency.
        - REGISTER MIXING: Examples of casual+neutral in same sentence.

        Include verbatim quotes for every finding.

        ### 9. PIVOT REGISTER
        - Quote exact pivot sentences
        - Classify: flat conversational, moderate, or elevated rhetorical
        - What does creator specifically NOT do at the pivot?

        Be QUANTITATIVE. This document must be precise enough to serve as a constraint set.

        Output as a structured document.
        """

        let user = "## TEMPLATE OPENINGS TO ANALYZE:\n\n" + formatTemplates(matchOpenings)

        return (system, user)
    }

    /// M6-call-2: Rewrite draft using the voice analysis as binding constraints.
    static func buildConstrainedRewritePrompt(
        draftText: String,
        voiceAnalysis: String,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are rewriting a script opening using a Voice Analysis Document as your constraint set.

        The analysis describes the creator's voice across three layers:
        - NARRATIVE MODE: event/evidence storytelling vs. explanation (MOST IMPORTANT)
        - TEXTURE: demonstratives, noun repetition, spoken syntax markers, pivot register
        - SKELETON: sentence lengths, entry patterns, transitions, energy arc

        PRIORITY ORDER — follow this strictly:
        1. NARRATIVE MODE — every sentence must be an event, evidence, contradiction, or question. Not explanation or advice. A perfectly textured explanation sentence is still wrong.
        2. TEXTURE — demonstratives, noun repetition, conjunction chains, casual insertions, spoken syntax
        3. SKELETON — sentence lengths, transitions, energy arc

        The analysis is your guide, but the TEMPLATE OPENINGS are your ground truth. When in doubt between what the analysis describes and what the templates actually sound like, match the templates.

        \(Self.VERB_CONSTRAINT)

        \(Self.ACTOR_REQUIREMENT)

        \(Self.EVIDENCE_MINIMUM)

        Specific checks before finalizing:
        - Is every sentence an EVENT, EVIDENCE, CONTRADICTION, or QUESTION? (not EVALUATION)
        - Does at least every other sentence have an actor doing something?
        - Did you use investigative verbs, not explanatory verbs?
        - Did you use "this/these + noun" at the density described in the analysis?
        - Did you repeat key noun phrases instead of defaulting to pronouns?
        - Are long sentences built from "and/but" chains, not subordinate clauses?
        - Did you include casual spoken insertions?
        - Is your pivot register flat/conversational, not elevated?

        Do NOT add evaluative language unless the analysis specifically identifies it as a feature.

        Output the rewritten opening only. No commentary.
        """

        var user = "## VOICE ANALYSIS DOCUMENT:\n\n\(voiceAnalysis)"
        user += "\n\n---\n\n## TEMPLATE OPENINGS (ground truth):\n\n"
        user += formatTemplates(matchOpenings)
        user += "\n\n---\n\n## DRAFT TO REWRITE:\n\(draftText)"

        return (system, user)
    }

    // MARK: - M7: Sentence-Function Spec

    /// M7-call-1: Extract sentence-level functional jobs from templates.
    static func buildSentenceJobExtractionPrompt(
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are annotating template script openings to extract a REUSABLE sentence-job sequence.

        For each sentence, describe:

        1. STRUCTURAL JOB — what the sentence accomplishes in the narrative. This must be TOPIC-INDEPENDENT — it should work for any investigative story, not just this template's specific topic.

        BAD (topic-specific): "Deliver content warning for disturbing autopsy material"
        GOOD (structural): "Prime the audience that what follows is surprising or uncomfortable"

        BAD: "Humanize the corpse victim with military background"
        GOOD: "Attach a human identity and backstory to raise emotional stakes"

        BAD: "Reveal the body was at an oddities expo"
        GOOD: "Reveal the commercial/unexpected context that makes the situation feel wrong"

        2. NARRATIVE TYPE — classify as EVENT, EVIDENCE, CONTRADICTION, QUESTION, or ACTOR. At least 80% of jobs should be EVENT, EVIDENCE, or CONTRADICTION. If a sentence is EVALUATION type in the template, note it but mark as "rare — do not default to this type."

        3. VOICE EXECUTION — HOW this creator delivers the job:
           - Demonstrative usage ("this/these + noun")
           - Noun repetition vs. pronouns
           - Conjunction chain vs. subordinate clause construction
           - Casual insertions present?
           - Spoken syntax inversions?
           - Register level (flat conversational vs. elevated)
           - What investigative/observational verbs are used?

        The STRUCTURAL JOB must be abstract enough to execute with ANY topic's content.
        The VOICE EXECUTION must be specific enough to sound like THIS creator.

        Output format:
        S[1]:
        - JOB: [topic-independent structural job]
        - TYPE: [EVENT/EVIDENCE/CONTRADICTION/QUESTION/ACTOR/EVALUATION]
        - VOICE: [specific execution notes with template quote as reference]
        S[2]: ...
        """

        let user = "## TEMPLATE OPENINGS TO ANNOTATE:\n\n" + formatTemplates(matchOpenings)

        return (system, user)
    }

    /// M7-call-2: Execute sentence-level jobs using filtered gist content + template voice reference.
    static func buildSentenceJobExecutionPrompt(
        sentenceJobs: String,
        filteredGists: [RamblingGist],
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are executing a sequence of sentence-level writing jobs to produce a script opening.

        You will receive:
        1. A numbered list of sentence jobs — each has a STRUCTURAL JOB, NARRATIVE TYPE, and VOICE EXECUTION notes
        2. Content material (gists with raw source text) — your ONLY source of facts
        3. Template openings — your VOICE REFERENCE showing how this creator actually sounds

        You are executing jobs IN THE VOICE shown in these templates. Before writing each sentence, read the corresponding template sentence. Your sentence should feel like it lives in the same show.

        CRITICAL — CONTENT MAPPING:
        The sentence jobs were extracted from a DIFFERENT topic than yours. You must MAP each job to YOUR content, not recreate the template's specific narrative.

        If a job says "Attach a human identity and backstory" — find the equivalent in YOUR content (the hunters, the landowner, the property's history). Do NOT try to recreate the template's specific scene.

        If a job requires content you don't have, SKIP that job. Write fewer sentences rather than forcing a bad mapping. You have permission to execute 60-80% of the jobs.

        \(Self.NARRATIVE_MODE)

        \(Self.VERB_CONSTRAINT)

        \(Self.ACTOR_REQUIREMENT)

        \(Self.EVIDENCE_MINIMUM)

        \(Self.TEXTURE_RULES)

        Rules:
        - Write EXACTLY one sentence per job you execute (skip jobs that don't map)
        - Each sentence must be the NARRATIVE TYPE specified (EVENT, EVIDENCE, etc.)
        - Each sentence must match the VOICE EXECUTION notes
        - Use ONLY facts from the provided content material
        - Do NOT fabricate facts, scenes, or details not in the content
        - Do NOT use evaluative language

        Output the script opening as continuous prose. One sentence per executed job.
        """

        var user = "## SENTENCE JOBS:\n\n\(sentenceJobs)"
        user += "\n\n---\n\n## CONTENT MATERIAL:\n\n"
        user += formatGists(filteredGists)
        user += "\n\n---\n\n## TEMPLATE OPENINGS (voice reference):\n\n"
        user += formatTemplates(matchOpenings)

        return (system, user)
    }

    // MARK: - M8: Mechanical 3-Phase

    /// M8-call-1: Extract mechanical spec from templates.
    static func buildMechanicalSpecPrompt(
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are extracting a mechanical voice specification from template script openings. This spec will be used by TWO separate downstream calls — a content mapper and a draft writer — so it must be CONCISE and DIRECTLY ACTIONABLE.

        Produce a spec of MAXIMUM 10 bullet points. Each bullet must be a concrete constraint with a target number or a do/don't example.

        Format each bullet like this:
        "Demonstratives: use 'this/these + noun' at ~2 per paragraph. Template evidence: 'this Portland hotel,' 'this dead body,' 'these large tanker trucks.' NOT 'the hotel,' 'the body,' 'the trucks.'"

        Your 10 bullets must cover these three layers in this priority order:

        NARRATIVE MODE (bullets 1-3):
        1. Narrative mode: What % of template sentences are EVENT/EVIDENCE/CONTRADICTION/QUESTION vs EVALUATION? (with counts and template evidence)
        2. Actor frequency: How many sentences have a concrete actor performing a concrete action? (with ratio)
        3. Verb palette: What are the 10 most common verbs? Are they investigative/observational or interpretive?

        TEXTURE (bullets 4-7):
        4. Demonstrative density ("this/these + noun" count, ratio vs "the/a")
        5. Noun repetition tolerance (how many times before pronoun switch)
        6. Conjunction chain architecture (spoken "and/but" chains vs written subordinate clauses — quote the 3 longest)
        7. Casual spoken insertions (list them, count per paragraph)

        SKELETON (bullets 8-10):
        8. Sentence length range and pattern (with word counts)
        9. Entry pattern (first sentence structure, word count)
        10. Pivot placement + register (which sentence, what register — flat or elevated, quote the pivot sentences)

        Output as a numbered bullet list. 10 bullets maximum. Each bullet: constraint + target number + template evidence.
        """

        let user = "## TEMPLATE OPENINGS:\n\n" + formatTemplates(matchOpenings)

        return (system, user)
    }

    /// M8-call-2: Map gist content to structural beats using the mechanical spec.
    static func buildContentMapPrompt(
        mechanicalSpec: String,
        filteredGists: [RamblingGist]
    ) -> (system: String, user: String) {

        let system = """
        You are creating a content map for a script opening. You will receive:
        1. A mechanical voice spec
        2. Content material (gists) to draw from

        For each beat position:
        - Which gist provides the content?
        - What specific fact or detail fills this position?
        - NARRATIVE TYPE: Must be EVENT, EVIDENCE, or CONTRADICTION. If you cannot make the beat one of these types with the available content, do not include the beat.
        - Which ACTOR is performing an action in this beat?
        - What is explicitly WITHHELD?
        - What question does this beat plant?
        - Which texture features from the spec are most important to execute here?

        CONTENT DISCIPLINE: Your content material is LIMITED. Do not plan more beats than you have content to fill. If the content only supports 5-6 sentences, plan 5-6 beats. Do not create beats that will require the draft step to invent content. Shorter and accurate beats longer and fabricated.

        Output format:
        Beat 1: [content, source gist, narrative type, actor, texture priorities]
        Beat 2: ...
        WITHHELD: [list facts deliberately excluded]
        FORWARD PULL: [the question the viewer must keep watching to answer]
        HARD CONSTRAINT: The draft MUST NOT mention, imply, or invent details about: [re-state every WITHHELD item]
        """

        var user = "## MECHANICAL SPEC:\n\n\(mechanicalSpec)"
        user += "\n\n---\n\n## CONTENT MATERIAL:\n\n"
        user += formatGists(filteredGists)

        return (system, user)
    }

    // MARK: - M9/M10: Analyze-Then-Fix Pipeline (Shared Prompts)

    /// Call 2 (shared by M9 and M10): Analyze a draft against templates.
    /// Produces a 6-section diagnosis with a prioritized fix list. Does NOT rewrite.
    static func buildAnalyzeDraftPrompt(
        draftText: String,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        filteredGists: [RamblingGist]
    ) -> (system: String, user: String) {

        let system = """
        You are analyzing a script opening draft by comparing it against template openings from a specific YouTube creator. Your job is to produce a detailed, specific diagnosis of everything that needs to change — but you will NOT rewrite anything. A separate system will execute your fixes.

        ANALYSIS PROCESS — do these in order:

        ## 1. NARRATIVE MODE COMPARISON

        Classify every sentence in the TEMPLATES as:
        - EVENT (someone did something, something happened)
        - EVIDENCE (something was found, observed, measured)
        - CONTRADICTION (expected vs. actual reality)
        - QUESTION (direct question)
        - ACTOR (person/group introduced doing something)
        - EVALUATION (judgment, explanation, advice)

        Count the template ratio: EVENT+EVIDENCE+CONTRADICTION vs. EVALUATION.

        Now classify every sentence in the DRAFT the same way.

        For every DRAFT sentence classified as EVALUATION, EXPLANATION, or ADVICE:
        - Quote the exact sentence
        - Explain why it's the wrong type
        - Suggest what type it SHOULD be (EVENT, EVIDENCE, etc.)
        - Provide a brief direction for what the fix should describe (but do NOT write the replacement sentence)

        ## 2. VERB AUDIT

        List every main verb in the draft. Flag any that are abstract/explanatory:
        - understand, reveal, explain, demonstrate, indicate, illustrate, require, suggest, mean, show (when meaning "demonstrate")

        For each flagged verb, suggest an investigative replacement verb from this list:
        - saw, spotted, counted, tracked, followed, recorded, filmed, found, discovered, mapped, climbed, sat, watched, called, flew

        ## 3. ACTOR FREQUENCY CHECK

        For each sentence in the draft, note whether it contains an actor performing an action.
        Flag any stretch of 2+ consecutive sentences without an actor.
        Suggest which actor from the content (hunters, landowner, drone, trail cameras) should be inserted.

        ## 4. TEXTURE COMPARISON — sentence by sentence

        For each draft sentence, compare against the corresponding template position and note:

        a. DEMONSTRATIVE CHECK: Does the sentence use "this/these + noun"? Should it? Where specifically should "the" be replaced with "this"?

        b. NOUN REPETITION: Did the draft switch to a pronoun where the creator would repeat the full noun phrase? Quote the specific pronoun and what noun phrase should replace it.

        c. CONJUNCTION CHAINS: Is the sentence built from "and/but/then" chains (spoken feel) or subordinate clauses (written feel)? If written, describe how to restructure it as a chain.

        d. CASUAL INSERTIONS: Is there a casual spoken aside? Should there be one? Suggest where one could go (but don't write it — just indicate the position and type, e.g., "add an approximation like 'around' or 'basically' before the number").

        e. SPOKEN SYNTAX: Does the sentence use any spoken inversions ("what they found is that...")? Should it?

        f. REGISTER: Is the sentence's register flat conversational (matching the creator) or elevated/literary (wrong)?

        ## 5. STRUCTURAL ISSUES

        Note any problems with:
        - Opening sentence (does it match the template's entry pattern?)
        - Pivot placement (is the stakes transition in the right position?)
        - Forward pull (does the ending create mystery/curiosity, not evaluate?)
        - Overall length (appropriate for the content available?)

        ## 6. FIX PRIORITY LIST

        Produce a numbered list of the TOP 10 most important fixes, ordered by impact.

        CRITICAL — EACH FIX MUST BE ONE ATOMIC OPERATION:
        - Each fix targets exactly ONE sentence
        - Each fix describes exactly ONE change
        - If a sentence needs two changes (e.g., replace a verb AND add a demonstrative), create TWO separate numbered fixes
        - The IN quote must be the exact sentence from the draft
        - The CHANGE description must be ≤10 words — one specific action

        Format:
        1. [TYPE] IN: "exact sentence from draft" → CHANGE: [single change in ≤10 words]
        2. [TYPE] IN: "exact sentence from draft" → CHANGE: [single change in ≤10 words]

        BAD (two changes in one fix):
        1. [TEXTURE] IN: "DD decided to deploy a thermal drone" → CHANGE: replace "deploy" with investigative verb, add casual insertion

        GOOD (split into atomic fixes):
        1. [VERB] IN: "DD decided to deploy a thermal drone" → CHANGE: replace "deploy" with "flew"
        2. [TEXTURE] IN: "DD decided to flew a thermal drone" → CHANGE: add casual aside before "thermal"

        OUTPUT FORMAT:
        Output your analysis as a structured document with all 6 sections. Be specific — quote exact sentences, name exact words to change, identify exact positions. The downstream fixer will execute your diagnosis literally, so vagueness will produce bad results.
        """

        var user = "## TEMPLATE OPENINGS (the voice to match):\n\n"
        user += formatTemplates(matchOpenings)
        user += "\n\n---\n\n## DRAFT TO ANALYZE:\n\n\(draftText)"
        user += "\n\n---\n\n## ORIGINAL CONTENT (for reference — these are the only facts allowed):\n\n"
        user += formatGists(filteredGists)

        return (system, user)
    }

    /// Call 3 (shared by M9 and M10): Execute atomic fixes from the priority list on the draft.
    /// Receives ONLY the fix list + draft + templates. No full analysis, no gists — reduced input to prevent creative drift.
    static func buildFixDraftPrompt(
        draftText: String,
        fixPriorityList: String,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are a SURGICAL EDITOR applying a numbered checklist of atomic fixes to a script draft. You are NOT rewriting — you are PATCHING. Each fix is one sentence, one change.

        EXECUTION RULES:
        - Work through the FIX PRIORITY LIST top to bottom
        - For each fix, locate the exact IN sentence in the draft
        - Apply ONLY the single change described in CHANGE
        - Do not restructure surrounding sentences for "flow" — leave them as-is unless a fix targets them
        - Do not introduce new problems while fixing old ones
        - If a fix cannot be applied (sentence not found, change doesn't make sense), skip it and note it in verification

        DO NOT:
        - Rewrite sentences that are not targeted by a fix
        - Add your own analysis or identify additional problems
        - Fabricate facts, scenes, or details not present in the original draft
        - Restructure paragraph flow or sentence order unless a fix specifically says to
        - Add evaluative language, metaphors, or literary flourishes
        - "Improve" sentences beyond what the fix specifies

        VOICE GROUND TRUTH:
        The template openings are your rhythm reference. When applying a fix, the result should sound like the templates — but ONLY change what the fix asks you to change.

        CONTENT DISCIPLINE:
        You may not add facts that weren't in the original draft. If a fix asks you to replace an explanation with an event, use facts already present elsewhere in the draft.

        OUTPUT FORMAT:
        ## FIXED SCRIPT
        [the complete script with all fixes applied — every sentence from the original draft, modified only where a fix targets it]

        ## VERIFICATION
        For each fix in the priority list, confirm execution:
        1. Fix: [describe what was changed] → Result: "quote the exact sentence from your FIXED SCRIPT that executes this fix"
        2. ...
        If you skipped a fix, write: SKIPPED — [reason]
        If any fix is not represented in your output, REVISE your script before finalizing.
        """

        var user = "## TEMPLATE OPENINGS (voice reference):\n\n"
        user += formatTemplates(matchOpenings)
        user += "\n\n---\n\n## ORIGINAL DRAFT:\n\n\(draftText)"
        user += "\n\n---\n\n## FIX PRIORITY LIST:\n\n\(fixPriorityList)"

        return (system, user)
    }

    /// Parse Call 3 (Fix) response: extract fixed script and verification checklist.
    static func parseFixDraftResponse(_ response: String) -> (fixedScript: String, verification: String) {
        let scriptMarker = "## FIXED SCRIPT"
        let verifyMarker = "## VERIFICATION"

        guard let scriptRange = response.range(of: scriptMarker) else {
            // No markers — treat entire response as the script
            return (fixedScript: response.trimmingCharacters(in: .whitespacesAndNewlines), verification: "")
        }

        let afterScript = response[scriptRange.upperBound...]

        if let verifyRange = afterScript.range(of: verifyMarker) {
            let fixedScript = String(afterScript[afterScript.startIndex..<verifyRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let verification = String(afterScript[verifyRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (fixedScript: fixedScript, verification: verification)
        }

        // Has ## FIXED SCRIPT but no ## VERIFICATION
        let fixedScript = String(afterScript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (fixedScript: fixedScript, verification: "")
    }

    /// Parse Call 2 (Analyze) response: extract full analysis and fix priority list separately.
    static func parseAnalyzeDraftResponse(_ response: String) -> (fullAnalysis: String, fixPriorityList: String) {
        let fixMarker = "## 6. FIX PRIORITY LIST"
        let altFixMarker = "## 6."

        if let fixRange = response.range(of: fixMarker) {
            let fixPriorityList = String(response[fixRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (fullAnalysis: response, fixPriorityList: fixPriorityList)
        }

        // Fallback: try shorter marker
        if let fixRange = response.range(of: altFixMarker) {
            let fixPriorityList = String(response[fixRange.lowerBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (fullAnalysis: response, fixPriorityList: fixPriorityList)
        }

        return (fullAnalysis: response, fixPriorityList: "")
    }

    // MARK: - M8: Mechanical 3-Phase

    /// M8-call-3: Generate draft using spec + content map + templates.
    static func buildMechanicalDraftPrompt(
        mechanicalSpec: String,
        contentMap: String,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are writing a script opening using three reference documents:

        1. A MECHANICAL SPEC — voice properties to match
        2. A CONTENT MAP — facts assigned to beat positions
        3. TEMPLATE OPENINGS — the target voice in action

        NARRATIVE MODE IS THE PRIMARY CONSTRAINT:
        Every sentence must describe an event, observation, evidence finding, or contradiction. If you find yourself writing a sentence that explains, advises, or evaluates — stop and rewrite it as something that HAPPENED.

        BEFORE (evaluation): "You need to understand the details of your property"
        AFTER (event): "So we flew this thermal drone over this property and started mapping where these deer were actually moving"

        BEFORE (explanation): "This dramatic drop doesn't happen overnight"
        AFTER (evidence): "These hunters kept climbing into this same stand season after season and the deer numbers kept dropping"

        \(Self.VERB_CONSTRAINT)

        \(Self.ACTOR_REQUIREMENT)

        Apply texture ON TOP of event narration:
        - Match demonstrative density from the spec
        - Repeat key noun phrases at the tolerance level specified
        - Build long sentences from "and/but" conjunction chains
        - Include casual spoken insertions
        - Match pivot register from the spec

        LENGTH FLEXIBILITY: You may write FEWER sentences than the templates contain. If the content map provides 5 beats, write 5 sentences. Do not invent additional sentences to match template length.

        ANTI-HALLUCINATION: Under no circumstances fabricate facts, scenes, findings, or investigation details not present in the content map. Before outputting, check every sentence against the content map. If any sentence contains a fact that isn't in the content map's beat descriptions, delete it.

        Do NOT include any facts listed under HARD CONSTRAINT in the content map.

        End on the forward pull identified in the content map.

        Output only the script text. No commentary, no headers.
        """

        var user = "## MECHANICAL SPEC:\n\n\(mechanicalSpec)"
        user += "\n\n---\n\n## CONTENT MAP:\n\n\(contentMap)"
        user += "\n\n---\n\n## TEMPLATE OPENINGS (rhythm reference):\n\n"
        user += formatTemplates(matchOpenings)

        return (system, user)
    }

    // MARK: - M11: Iterative Refinement (3-Round Diagnosis → Fix)

    /// M11 Diagnosis: Compare draft against templates and identify sentences that don't match the writer's voice.
    /// Simpler than M9/M10's 6-section analysis — just sentence-level REPLACE/WITH pairs.
    static func buildIterativeDiagnosisPrompt(
        draftText: String,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening],
        roundNumber: Int
    ) -> (system: String, user: String) {

        let roundGuidance: String
        switch roundNumber {
        case 1:
            roundGuidance = "This is the FIRST pass. Focus on the biggest voice mismatches — sentences that clearly don't sound like the template writer."
        case 2:
            roundGuidance = "This is the SECOND pass. Major issues were already fixed in round 1. Focus on remaining moderate mismatches — verb choices, sentence construction, texture."
        default:
            roundGuidance = "This is the FINAL pass. Only flag subtle remaining mismatches — demonstrative density, conjunction style, casual insertion placement, register."
        }

        let system = """
        You are comparing a script draft against template openings from a specific YouTube creator. The draft should sound exactly like it was written by the same person who wrote the templates — as if they are the same writer.

        \(roundGuidance)

        Go through the draft sentence by sentence. For each sentence that does NOT sound like the template writer, output a replacement block:

        REPLACE: "exact sentence from the draft"
        REASON: [≤15 words — what specifically doesn't match the template voice]
        WITH: "replacement sentence written in the template writer's voice"

        RULES:
        - Flag a MAXIMUM of 5 sentences per round. Pick the biggest mismatches only.
        - The replacement must use facts from the original sentence — do NOT invent new content.
        - The replacement must sound like it was written by the same person who wrote the templates.
        - If a sentence already sounds like the templates, leave it alone — do NOT flag it.

        VOICE REFERENCE — what to check for:

        \(Self.NARRATIVE_MODE)

        \(Self.VERB_CONSTRAINT)

        \(Self.ACTOR_REQUIREMENT)

        \(Self.TEXTURE_RULES)

        Output ONLY the REPLACE/REASON/WITH blocks. No commentary, no headers, no analysis. If every sentence already matches, output: NO CHANGES NEEDED
        """

        var user = "## TEMPLATE SCRIPTS (the voice to match):\n\n"
        user += formatTemplates(matchOpenings)
        user += "\n\n---\n\n## DRAFT (round \(roundNumber) of 3):\n\n\(draftText)"

        return (system, user)
    }

    /// M11 Fix: Apply specific sentence replacements from the diagnosis to the draft.
    static func buildIterativeFixPrompt(
        draftText: String,
        diagnosis: String,
        matchOpenings: [OpenerMatcherPromptEngine.CorpusOpening]
    ) -> (system: String, user: String) {

        let system = """
        You are applying specific sentence replacements to a script draft. You will receive:

        1. The original draft
        2. A list of REPLACE/REASON/WITH blocks — each identifies one sentence to swap
        3. Template openings showing the target voice

        For each REPLACE/WITH pair:
        - Find the exact sentence in the draft
        - Swap it with the WITH sentence
        - If the transition between the replaced sentence and its neighbors feels abrupt, you may adjust transition words (one or two words max) — but do NOT rewrite neighboring sentences

        DO NOT:
        - Change any sentence that is NOT in the REPLACE list
        - Add new content, facts, or sentences
        - Restructure paragraphs or reorder sentences
        - "Improve" anything beyond what the replacement list specifies

        OUTPUT FORMAT:

        ## FIXED SCRIPT
        [the complete draft with all replacements applied — every sentence present, only flagged ones changed]

        ## CHANGES APPLIED
        1. Replaced: "original sentence" → "new sentence"
        2. ...
        """

        var user = "## TEMPLATE OPENINGS (voice reference):\n\n"
        user += formatTemplates(matchOpenings)
        user += "\n\n---\n\n## ORIGINAL DRAFT:\n\n\(draftText)"
        user += "\n\n---\n\n## SENTENCE REPLACEMENTS:\n\n\(diagnosis)"

        return (system, user)
    }

    /// Parse M11 Fix response: extract the fixed script from ## FIXED SCRIPT section.
    static func parseIterativeFixResponse(_ response: String) -> (fixedScript: String, changesApplied: String) {
        let scriptMarker = "## FIXED SCRIPT"
        let changesMarker = "## CHANGES APPLIED"

        guard let scriptRange = response.range(of: scriptMarker) else {
            return (fixedScript: response.trimmingCharacters(in: .whitespacesAndNewlines), changesApplied: "")
        }

        let afterScript = response[scriptRange.upperBound...]

        if let changesRange = afterScript.range(of: changesMarker) {
            let fixedScript = String(afterScript[afterScript.startIndex..<changesRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let changesApplied = String(afterScript[changesRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (fixedScript: fixedScript, changesApplied: changesApplied)
        }

        let fixedScript = String(afterScript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (fixedScript: fixedScript, changesApplied: "")
    }
}
